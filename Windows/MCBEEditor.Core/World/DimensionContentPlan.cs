using System.Buffers.Binary;
using System.Text;
using MCBEEditor.Core.Nbt;

namespace MCBEEditor.Core.World;

public sealed record DimensionMutationSummary(int DeletedKeyCount, int RemovedActorCount, int UpdatedKeyCount, int AffectedPlayerCount = 0);

internal sealed class DimensionContentPlan
{
    public List<WorldDatabasePut> Puts { get; } = [];
    public List<byte[]> Deletes { get; } = [];
    public int ActorCount { get; private set; }

    public static DimensionContentPlan Build(IWorldDatabase db, int id, IReadOnlyList<DimensionRecord> dimensions)
    {
        var plan = new DimensionContentPlan();
        var keys = db.Entries(includeValues:false).Select(e=>e.Key).ToArray();
        var roots = dimensions.Select(row => row.Name switch { "overworld"=>"Overworld","nether"=>"Nether","the_end"=>"TheEnd",_=>row.Name });
        var protectedNames = roots.Concat(DimensionDatabaseKeys.GlobalNames).ToHashSet(StringComparer.Ordinal);
        var targetRefs = new HashSet<string>(StringComparer.Ordinal); var otherRefs = new HashSet<string>(StringComparer.Ordinal);
        var villages = new Dictionary<string,List<byte[]>>(StringComparer.Ordinal);
        foreach(var key in keys)
        {
            var text = Encoding.UTF8.GetString(key);
            if(protectedNames.Contains(text) || DimensionDatabaseKeys.PreservedPrefixes.Any(prefix=>text.StartsWith(prefix,StringComparison.Ordinal)) || text.StartsWith("portals",StringComparison.Ordinal)) continue;
            if(key.AsSpan().StartsWith("digp"u8) && key.Length is 12 or 16)
            {
                var dimension = key.Length==16 ? BinaryPrimitives.ReadInt32LittleEndian(key.AsSpan(12,4)) : 0;
                var value=db.Get(key) ?? [];
                if(value.Length%8!=0) throw new InvalidDataException("digp actor 引用长度不是8的倍数");
                var refs=dimension==id ? targetRefs : otherRefs;
                for(var i=0;i<value.Length;i+=8) refs.Add(Convert.ToHexString(value.AsSpan(i,8)));
                if(dimension==id) plan.Deletes.Add(key);
                continue;
            }
            if(text.StartsWith("actorprefix",StringComparison.Ordinal)) continue;
            if(text.StartsWith("tickingarea",StringComparison.Ordinal))
            {
                var records=ConsecutiveNbtCodec.Decode(db.Get(key) ?? []);
                if(records.Count!=1) throw new InvalidDataException("常加载区块必须包含一个NBT根");
                var dimension=Owner(records[0].Document.Root,dimensions) ?? throw new InvalidDataException("常加载区块缺少维度");
                if(dimension==id) plan.Deletes.Add(key);
                continue;
            }
            if(text.StartsWith("VILLAGE_",StringComparison.Ordinal))
            {
                var group=text;
                foreach(var suffix in new[]{"_INFO","_POI","_DWELLERS","_PLAYERS","_RAID"})
                    if(group.EndsWith(suffix,StringComparison.Ordinal)) { group=group[..^suffix.Length]; break; }
                if(!villages.TryGetValue(group,out var list)) villages[group]=list=[];
                list.Add(key); continue;
            }
            if(text.StartsWith("structuretemplate_",StringComparison.Ordinal)) continue;
            if(key.Length is >=9 and <=11)
            { if(id==0) plan.Deletes.Add(key); }
            else if(key.Length is >=13 and <=15 && BinaryPrimitives.ReadInt32LittleEndian(key.AsSpan(8,4))==id)
                plan.Deletes.Add(key);
        }
        foreach(var reference in targetRefs.Except(otherRefs))
        {
            var key="actorprefix"u8.ToArray().Concat(Convert.FromHexString(reference)).ToArray();
            if(db.Get(key) is not null) {plan.Deletes.Add(key); plan.ActorCount++;}
        }
        foreach(var key in keys.Where(k=>k.Length==19 && k.AsSpan().StartsWith("actorprefix"u8)))
        {
            var reference=Convert.ToHexString(key.AsSpan(11,8));
            if(targetRefs.Contains(reference) || otherRefs.Contains(reference)) continue;
            var records=ConsecutiveNbtCodec.Decode(db.Get(key) ?? []);
            var kept=records.Where(record=>Owner(record.Document.Root,dimensions)!=id).ToArray();
            if(kept.Length==records.Count) continue;
            if(kept.Length==0) {plan.Deletes.Add(key); plan.ActorCount++;}
            else plan.Puts.Add(new(key,kept.SelectMany(record=>record.RawData).ToArray()));
        }
        foreach(var (name,group) in villages)
        {
            var owners=group.SelectMany(key=>ConsecutiveNbtCodec.Decode(db.Get(key) ?? []))
                .Select(record=>Owner(record.Document.Root,dimensions)).Append(VillageKeyOwner(name,dimensions)).Where(owner=>owner.HasValue).Select(owner=>owner!.Value).Distinct().ToArray();
            if(owners.Length>1) throw new InvalidDataException("村庄记录包含冲突维度，未清理任何数据");
            if((owners.FirstOrDefault())==id) plan.Deletes.AddRange(group);
        }
        if(id is >=0 and <=2 && db.Get(Encoding.UTF8.GetBytes($"dimension{id}")) is {} legacyBytes)
        {
            var records=ConsecutiveNbtCodec.Decode(legacyBytes);
            if(records.Count!=1 || records[0].Document.Root is not NbtCompoundValue) throw new InvalidDataException("旧版维度结构根必须为唯一Compound");
            plan.Deletes.Add(Encoding.UTF8.GetBytes($"dimension{id}"));
        }
        foreach(var key in keys.Where(key=>Encoding.UTF8.GetString(key).StartsWith("portals",StringComparison.Ordinal)))
        {
            var records=ConsecutiveNbtCodec.Decode(db.Get(key) ?? []);
            if(records.Count!=1) throw new InvalidDataException("门户记录必须包含唯一NBT根");
            var changed=false; var root=FilterPortals(records[0].Document.Root,id,ref changed);
            if(changed) plan.Puts.Add(new(key,BedrockNbtCodec.Encode(new NbtDocument(records[0].Document.RootName,root),records[0].Encoding)));
        }
        foreach(var name in new[]{"mVillages","villages","AutonomousEntities"})
        {
            var key=Encoding.UTF8.GetBytes(name); if(db.Get(key) is not {} bytes) continue;
            var records=ConsecutiveNbtCodec.Decode(bytes); var changed=false;
            using var output=new MemoryStream();
            foreach(var record in records)
            {
                var recognized=false; var rootChanged=false;
                var root=FilterLists(record.Document.Root,name,id,dimensions,ref rootChanged,ref recognized);
                if((name=="mVillages" || name=="villages") && !recognized && HasPayload(root) && (Owner(root,dimensions)??0)==id)
                { changed=true; continue; }
                if(name=="AutonomousEntities" && !recognized && HasPayload(root))
                    throw new InvalidDataException("AutonomousEntities 内容格式无法识别，未清理任何数据");
                changed |= rootChanged;
                output.Write(rootChanged ? BedrockNbtCodec.Encode(new NbtDocument(record.Document.RootName,root),record.Encoding) : record.RawData);
            }
            if(changed)
            {
                var updated=output.Length==0 ? BedrockNbtCodec.Encode(new NbtDocument(records.FirstOrDefault()?.Document.RootName??"",new NbtCompoundValue([])),records.FirstOrDefault()?.Encoding??NbtEncoding.LittleEndian) : output.ToArray();
                plan.Puts.Add(new(key,updated));
            }
        }
        return plan;
    }

    private static int? VillageKeyOwner(string key,IReadOnlyList<DimensionRecord> dimensions)
    {
        var body=key["VILLAGE_".Length..];
        var candidates=dimensions.Select(row=>(Name:row.Name,Id:row.Id))
            .Concat(new[]{(Name:"overworld",Id:0),(Name:"nether",Id:1),(Name:"the_end",Id:2)})
            .Where(row=>body.StartsWith(row.Name+"_",row.Id is >=0 and <=2 ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal)).ToArray();
        if(candidates.Length>0)
        {
            var length=candidates.Max(row=>row.Name.Length);
            var owners=candidates.Where(row=>row.Name.Length==length).Select(row=>row.Id).Distinct().ToArray();
            if(owners.Length!=1) throw new InvalidDataException($"村庄键维度名称有歧义：{key}");
            return owners[0];
        }
        if(body.Contains('_')) throw new InvalidDataException($"村庄键维度名称无法解析：{key}");
        return null;
    }
    private static NbtValue FilterPortals(NbtValue value,int id,ref bool changed)
    {
        if(value is not NbtCompoundValue compound) throw new InvalidDataException("门户根必须为Compound");
        var dataTags=compound.Tags.Where(tag=>tag.Name=="data").ToArray();
        if(dataTags.Length==0) {if(HasPayload(value)) throw new InvalidDataException("门户缺少data，未清理任何数据"); return value;}
        if(dataTags.Length!=1 || dataTags[0].Value is not NbtCompoundValue data) throw new InvalidDataException("门户data格式错误");
        var lists=data.Tags.Where(tag=>tag.Name=="PortalRecords").ToArray();
        if(lists.Length==0) {if(HasPayload(data)) throw new InvalidDataException("门户缺少PortalRecords"); return value;}
        if(lists.Length!=1 || lists[0].Value is not NbtListValue list || (list.ElementType!=NbtTagType.Compound && list.Values.Count>0)) throw new InvalidDataException("PortalRecords必须为Compound列表");
        var kept=new List<NbtValue>();
        foreach(var record in list.Values)
        {
            if(record is not NbtCompoundValue fields || fields.Tags.Count(tag=>tag.Name=="DimId")!=1 || fields.CompoundValue("DimId") is not NbtIntValue dimension) throw new InvalidDataException("门户DimId必须为唯一Int");
            if(dimension.Value!=id) kept.Add(record);
        }
        if(kept.Count==list.Values.Count) return value;
        changed=true;
        var updated=new NbtCompoundValue(data.Tags.Select(tag=>tag.Name=="PortalRecords" ? new NbtNamedTag(tag.Name,new NbtListValue(list.ElementType,kept)) : tag).ToArray());
        return new NbtCompoundValue(compound.Tags.Select(tag=>tag.Name=="data" ? new NbtNamedTag(tag.Name,updated) : tag).ToArray());
    }
    private static bool HasPayload(NbtValue value) => value switch
    {
        NbtCompoundValue compound=>compound.Tags.Any(tag=>HasPayload(tag.Value)),
        NbtListValue list=>list.Values.Count>0,
        _=>true
    };
    private static string Normalize(string text)=>new(text.Where(char.IsLetterOrDigit).Select(char.ToLowerInvariant).ToArray());
    private static int? Owner(NbtValue value,IReadOnlyList<DimensionRecord> dimensions)
    {
        if(value is NbtCompoundValue compound)
        {
            var directOwners=compound.Tags.Where(tag=>new[]{"dimension","dimensionid","dimensionindex","dim"}.Contains(Normalize(tag.Name)))
                .Select(tag=>DirectOwner(tag.Value,dimensions)).Distinct().ToArray();
            if(directOwners.Length>1) throw new InvalidDataException("内容记录包含冲突维度");
            if(directOwners.Length==1) return directOwners[0];
            var owners=compound.Tags.Select(tag=>Owner(tag.Value,dimensions)).Where(owner=>owner.HasValue).Distinct().ToArray();
            if(owners.Length>1) throw new InvalidDataException("内容记录包含冲突维度");
            return owners.FirstOrDefault();
        }
        else if(value is NbtListValue list)
        {
            var owners=list.Values.Select(child=>Owner(child,dimensions)).Where(owner=>owner.HasValue).Distinct().ToArray();
            if(owners.Length>1) throw new InvalidDataException("内容记录包含冲突维度");
            return owners.FirstOrDefault();
        }
        return null;
    }
    private static int DirectOwner(NbtValue value,IReadOnlyList<DimensionRecord> dimensions)
    {
        if((value is NbtByteValue or NbtShortValue or NbtIntValue or NbtLongValue) && value.IntegerValue() is {} number && number is >=int.MinValue and <=int.MaxValue) return (int)number;
        if(value is NbtStringValue text)
        {
            if(int.TryParse(text.Value,out var id)) return id;
            var named=dimensions.FirstOrDefault(row=>row.Name==text.Value); if(named is not null) return named.Id;
            switch(text.Value.ToLowerInvariant()) {case "overworld": case "minecraft:overworld": return 0;case "nether":case "minecraft:nether":return 1;case "the_end":case "end":case "minecraft:the_end":return 2;}
        }
        throw new InvalidDataException("内容记录的维度无法解析");
    }
    private static NbtValue FilterLists(NbtValue value,string hint,int id,IReadOnlyList<DimensionRecord> dimensions,ref bool changed,ref bool recognized)
    {
        if(value is NbtListValue list && new[]{"mvillages","villages","villagecollection","villagelist","autonomousentitylist"}.Contains(Normalize(hint)))
        {
            recognized=true;
            var kept=list.Values.Where(child=>(Owner(child,dimensions)??0)!=id).ToArray();
            if(kept.Length!=list.Values.Count) changed=true;
            return new NbtListValue(list.ElementType,kept);
        }
        if(value is NbtCompoundValue compound)
        {
            if(new[]{"mvillages","villages","villagecollection","villagelist","autonomousentitylist"}.Contains(Normalize(hint)) && compound.Tags.Count>0 && compound.Tags.All(tag=>tag.Value is NbtCompoundValue))
            {
                var owners=compound.Tags.Select(tag=>Owner(tag.Value,dimensions)).ToArray();
                if(owners.All(owner=>owner.HasValue))
                {
                    recognized=true;
                    var kept=compound.Tags.Where((tag,index)=>owners[index]!=id).ToArray();
                    if(kept.Length!=compound.Tags.Count) changed=true;
                    return new NbtCompoundValue(kept);
                }
            }
            var tags=new List<NbtNamedTag>();
            foreach(var tag in compound.Tags) tags.Add(new(tag.Name,FilterLists(tag.Value,tag.Name,id,dimensions,ref changed,ref recognized)));
            return new NbtCompoundValue(tags);
        }
        if(value is NbtListValue nested)
        {
            var values=new List<NbtValue>();foreach(var child in nested.Values) values.Add(FilterLists(child,hint,id,dimensions,ref changed,ref recognized));
            return new NbtListValue(nested.ElementType,values);
        }
        return value;
    }
}

internal sealed class DimensionReferencePlan
{
    internal List<WorldDatabasePut> Puts {get;}=[];
    internal int PlayerCount {get;private set;}
    private static string Normalize(string name)=>new(name.Where(char.IsLetterOrDigit).Select(char.ToLowerInvariant).ToArray());
    private static readonly HashSet<string> CurrentNames=["dimensionid","dimension"];
    private static readonly HashSet<string> SpawnNames=["spawndimension","respawndimension","spawndimensionid"];
    private static readonly HashSet<string> NestedNames=["respawn","spawn","spawnpoint","playerspawn","bedspawn","respawnpoint"];
    internal static DimensionReferencePlan Build(IWorldDatabase db,DimensionRecord target,IReadOnlyList<DimensionRecord> dimensions)
    {
        var plan=new DimensionReferencePlan();var remaining=dimensions.Where(row=>row.Id!=target.Id).ToArray();var fallback=remaining.FirstOrDefault(row=>row.Id==0)??remaining.FirstOrDefault();
        foreach(var entry in db.Entries(includeValues:false))
        {
            var name=Encoding.UTF8.GetString(entry.Key);
            if(name!="~local_player" && name!="LocalPlayer" && !name.StartsWith("player_",StringComparison.Ordinal) && !name.StartsWith("legacy_console_player_",StringComparison.Ordinal)) continue;
            var records=ConsecutiveNbtCodec.Decode(db.Get(entry.Key)??[]);var changed=false;using var output=new MemoryStream();
            foreach(var record in records)
            {
                var rootChanged=false;var root=Migrate(record.Document.Root,target.Id,fallback,dimensions,false,ref rootChanged);changed|=rootChanged;
                output.Write(rootChanged?BedrockNbtCodec.Encode(new NbtDocument(record.Document.RootName,root),record.Encoding):record.RawData);
            }
            if(changed) {plan.Puts.Add(new(entry.Key,output.ToArray()));plan.PlayerCount++;}
        }
        if(db.Get("WorldClocks"u8) is {} bytes)
        {
            var records=ConsecutiveNbtCodec.Decode(bytes);
            if(records.Count!=1 || records[0].Document.Root is not NbtCompoundValue root || root.CompoundValue("clocks") is not NbtListValue clocks) throw new InvalidDataException("WorldClocks格式错误");
            var kept=clocks.Values.Where(clock=>ClockId(clock.StringValue("Name")??throw new InvalidDataException("维度时钟缺少Name"),dimensions)!=target.Id).ToArray();
            if(kept.Length!=clocks.Values.Count)
                plan.Puts.Add(new("WorldClocks"u8.ToArray(),BedrockNbtCodec.Encode(new NbtDocument(records[0].Document.RootName,new NbtCompoundValue(root.Tags.Select(tag=>tag.Name=="clocks"?new NbtNamedTag(tag.Name,new NbtListValue(clocks.ElementType,kept)):tag).ToArray())),records[0].Encoding)));
        }
        return plan;
    }
    private static int? ClockId(string name,IReadOnlyList<DimensionRecord> dimensions)
    {
        var row=dimensions.FirstOrDefault(row=>row.Name==name);if(row is not null)return row.Id;
        return name.ToLowerInvariant() switch {"overworld" or "minecraft:overworld"=>0,"nether" or "minecraft:nether"=>1,"the_end" or "minecraft:the_end"=>2,_=>int.TryParse(name,out var id)?id:null};
    }
    private static int ReferenceId(NbtValue value,IReadOnlyList<DimensionRecord> dimensions)
    {
        if((value is NbtByteValue or NbtShortValue or NbtIntValue or NbtLongValue) && value.IntegerValue() is {} number && number is >=int.MinValue and <=int.MaxValue) return (int)number;
        if(value is NbtStringValue text && ClockId(text.Value,dimensions) is {} id)return id;
        throw new InvalidDataException("玩家维度引用无法解析，未删除任何数据");
    }
    private static NbtValue Migrate(NbtValue value,int target,DimensionRecord? fallback,IReadOnlyList<DimensionRecord> dimensions,bool nested,ref bool changed)
    {
        if(value is not NbtCompoundValue compound)throw new InvalidDataException("玩家NBT根或重生位置必须为Compound");
        var tags=compound.Tags.ToList();var dimensionTags=tags.Where(tag=>CurrentNames.Contains(Normalize(tag.Name))||(nested&&SpawnNames.Contains(Normalize(tag.Name)))).ToArray();
        var positionExists=tags.Any(tag=>Normalize(tag.Name) is "pos" or "position");
        if(dimensionTags.Select(tag=>ReferenceId(tag.Value,dimensions)).Distinct().Count()>1)throw new InvalidDataException("玩家当前位置维度冲突");
        var currentAffected=dimensionTags.Any(tag=>ReferenceId(tag.Value,dimensions)==target)||(dimensionTags.Length==0&&(positionExists||(nested&&tags.Any(tag=>Normalize(tag.Name) is "x" or "z" or "spawnx" or "spawnz")))&&target==0);
        var spawnTags=tags.Where(tag=>SpawnNames.Contains(Normalize(tag.Name))).ToArray();var spawnExists=tags.Any(tag=>Normalize(tag.Name) is "spawnx" or "spawnz");
        if(spawnTags.Select(tag=>ReferenceId(tag.Value,dimensions)).Distinct().Count()>1)throw new InvalidDataException("玩家重生维度冲突");
        var spawnAffected=!nested&&(spawnTags.Any(tag=>ReferenceId(tag.Value,dimensions)==target)||(spawnTags.Length==0&&spawnExists&&target==0));
        if(currentAffected||spawnAffected)
        {
            if(fallback is null)throw new InvalidDataException("玩家仍引用此维度，且没有可迁入的剩余维度");changed=true;
            void Set(string name,NbtValue replacement){tags.RemoveAll(tag=>tag.Name==name);tags.Add(new(name,replacement));}
            for(var i=0;i<tags.Count;i++)if((currentAffected&&CurrentNames.Contains(Normalize(tags[i].Name)))||((spawnAffected||nested)&&SpawnNames.Contains(Normalize(tags[i].Name))))tags[i]=new(tags[i].Name,new NbtIntValue(fallback.Id));
            if(currentAffected)
            {
                if(dimensionTags.Length==0)Set(nested?"SpawnDimension":"DimensionId",new NbtIntValue(fallback.Id));
                for(var i=0;i<tags.Count;i++)if(Normalize(tags[i].Name) is "pos" or "position")tags[i]=new(tags[i].Name,new NbtListValue(NbtTagType.Float,[new NbtFloatValue(0.5f),new NbtFloatValue(nested?64:65.62f),new NbtFloatValue(0.5f)]));
                if(!nested&&!positionExists)Set("Pos",new NbtListValue(NbtTagType.Float,[new NbtFloatValue(0.5f),new NbtFloatValue(65.62f),new NbtFloatValue(0.5f)]));
            }
            if(spawnAffected||nested)
            {
                if(spawnTags.Length==0&&!nested)Set("SpawnDimension",new NbtIntValue(fallback.Id));
                for(var i=0;i<tags.Count;i++)
                {
                    var key=Normalize(tags[i].Name);
                    if(key is "spawnx" or "spawnz" or "spawnforced" or "forced" || (nested&&key is "x" or "z"))tags[i]=new(tags[i].Name,key.Contains("forced",StringComparison.Ordinal)?new NbtByteValue(0):new NbtIntValue(0));
                    if(key=="spawny"||(nested&&key=="y"))tags[i]=new(tags[i].Name,new NbtIntValue(64));
                }
                if(!nested){Set("SpawnX",new NbtIntValue(0));Set("SpawnY",new NbtIntValue(64));Set("SpawnZ",new NbtIntValue(0));Set("SpawnForced",new NbtByteValue(0));}
            }
        }
        if(!nested)for(var i=0;i<tags.Count;i++)if(NestedNames.Contains(Normalize(tags[i].Name)))tags[i]=new(tags[i].Name,Migrate(tags[i].Value,target,fallback,dimensions,true,ref changed));
        return new NbtCompoundValue(tags);
    }
}
