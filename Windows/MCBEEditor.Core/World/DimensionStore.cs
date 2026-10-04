using System.Buffers.Binary;
using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;
using MCBEEditor.Core.Chunk;
using MCBEEditor.Core.Nbt;

namespace MCBEEditor.Core.World;

public sealed record DimensionRecord(string Name, int Id, int ChunkCount)
{
    public string QueryText => $"{Name}={Id.ToString(CultureInfo.InvariantCulture)}，区块={ChunkCount.ToString(CultureInfo.InvariantCulture)}";
}

/// <summary>Discovers registered empty dimensions and dimensions with actual data.</summary>
public sealed class DimensionStore(IWorldDatabase database)
{
    public static byte[] RegistryKey => Encoding.UTF8.GetBytes("DimensionNameIdTable");

    public int Resolve(string token)
    {
        var row=Snapshot().FirstOrDefault(row=>row.Name==token); if(row is not null) return row.Id;
        return token.ToLowerInvariant() switch {"overworld" or "minecraft:overworld"=>0,"nether" or "minecraft:nether"=>1,"the_end" or "minecraft:the_end"=>2,
            _=>int.TryParse(token,NumberStyles.AllowLeadingSign,CultureInfo.InvariantCulture,out var id)?id:throw new InvalidDataException($"维度名称或 ID 无效：{token}")};
    }

    public DimensionMutationSummary Purge(int id)
    {
        var dimensions=Snapshot();var target=dimensions.FirstOrDefault(row=>row.Id==id) ?? throw new InvalidDataException($"维度不存在：{id}");
        var plan=DimensionContentPlan.Build(database,id,dimensions);var references=DimensionReferencePlan.Build(database,target,dimensions);
        plan.Puts.AddRange(references.Puts);plan.Deletes.Add(DataKey(target.Name));
        if(id is >=0 and <=2) plan.Deletes.Add(DataKey(new[]{"overworld","nether","the_end"}[id]));
        if(database.Get(RegistryKey) is {} bytes)
        {
            var document=BedrockNbtCodec.Decode(bytes);
            if(document.Root is not NbtCompoundValue root || root.CompoundValue("entries") is not NbtCompoundValue entries) throw new InvalidDataException("维度登记格式错误");
            var kept=entries.Tags.Where(tag=>tag.Value is not NbtIntValue value || value.Value!=id).ToArray();
            if(kept.Length!=entries.Tags.Count)
                plan.Puts.Add(new(RegistryKey,BedrockNbtCodec.Encode(new NbtDocument(document.RootName,new NbtCompoundValue(root.Tags.Select(tag=>tag.Name=="entries" ? new NbtNamedTag(tag.Name,new NbtCompoundValue(kept)) : tag).ToArray())))));
        }
        var puts=plan.Puts.Select(put=>Convert.ToHexString(put.Key)).ToHashSet(StringComparer.Ordinal);
        var deletes=plan.Deletes.Where(key=>!puts.Contains(Convert.ToHexString(key))).DistinctBy(key=>Convert.ToHexString(key)).ToArray();
        database.ApplyBatch(plan.Puts,deletes,sync:true);
        return new DimensionMutationSummary(deletes.Length,plan.ActorCount,plan.Puts.Count,references.PlayerCount);
    }

    public DimensionMutationSummary Empty(int id)
    {
        var dimensions=Snapshot(); var target=dimensions.FirstOrDefault(row=>row.Id==id) ?? throw new InvalidDataException($"维度不存在：{id}");
        var plan=DimensionContentPlan.Build(database,id,dimensions);var name=target.Name;
        if(id is <0 or >2)
        {
            var registry=database.Get(RegistryKey) is {} bytes ? BedrockNbtCodec.Decode(bytes):new NbtDocument("",new NbtCompoundValue([new("entries",new NbtCompoundValue([]))]));
            if(registry.Root.CompoundValue("entries")?.IntValue(name)!=id)
            {
                name=$"dimension_{id}";
                while(dimensions.Any(row=>row.Name==name)||database.Get(DataKey(name)) is not null) name+="_";
                if(registry.Root is not NbtCompoundValue root || root.CompoundValue("entries") is not NbtCompoundValue entries) throw new InvalidDataException("维度登记格式错误");
                var replacement=new NbtNamedTag("entries",new NbtCompoundValue(entries.Tags.Append(new NbtNamedTag(name,new NbtIntValue(id))).ToArray()));
                plan.Puts.Add(new(RegistryKey,BedrockNbtCodec.Encode(new NbtDocument(registry.RootName,new NbtCompoundValue(root.Tags.Select(tag=>tag.Name=="entries"?replacement:tag).ToArray())))));
            }
        }
        var key=DataKey(name);
        var document=database.Get(key) is {} data ? BedrockNbtCodec.Decode(data):new NbtDocument("",new NbtCompoundValue([]));
        if(document.Root is not NbtCompoundValue compound) throw new InvalidDataException("维度根必须为 Compound");
        if(compound.CompoundValue("data") is {} dataValue && dataValue is not NbtCompoundValue) throw new InvalidDataException("维度 data 必须为 Compound");
        var dataTags=(compound.CompoundValue("data") as NbtCompoundValue)?.Tags.Where(tag=>tag.Name!="LimboEntities" && !(id==2 && tag.Name=="DragonFight")).ToList() ?? [];
        dataTags.Add(new("LimboEntities",new NbtListValue(NbtTagType.Compound,[])));
        var tags=compound.Tags.Where(tag=>tag.Name!="data").Append(new NbtNamedTag("data",new NbtCompoundValue(dataTags))).ToArray();
        plan.Puts.Add(new(key,BedrockNbtCodec.Encode(new NbtDocument(document.RootName,new NbtCompoundValue(tags)))));
        var puts=plan.Puts.Select(put=>Convert.ToHexString(put.Key)).ToHashSet(StringComparer.Ordinal);
        var deletes=plan.Deletes.Where(key=>!puts.Contains(Convert.ToHexString(key))).DistinctBy(key=>Convert.ToHexString(key)).ToArray();
        database.ApplyBatch(plan.Puts,deletes,sync:true);
        return new DimensionMutationSummary(deletes.Length,plan.ActorCount,plan.Puts.Count);
    }

    public static string ValidateAddition(string name, int id)
    {
        if (string.IsNullOrEmpty(name) || Encoding.UTF8.GetByteCount(name) > 65535
            || name.Any(c => char.IsWhiteSpace(c) || char.IsControl(c)) || Regex.IsMatch(name, @"^[+-]?[0-9]+$"))
            throw new InvalidDataException("维度名称必须非空，不含空白/控制字符，且不能为纯数字");
        (string Name, int Id)? builtin = name.ToLowerInvariant() switch
        {
            "overworld" or "minecraft:overworld" => ("overworld", 0),
            "nether" or "minecraft:nether" => ("nether", 1),
            "the_end" or "minecraft:the_end" => ("the_end", 2),
            _ => null
        };
        if (builtin is { } vanilla)
        {
            if (id != vanilla.Id) throw new InvalidDataException($"{vanilla.Name} 的 ID 必须为 {vanilla.Id}");
            return vanilla.Name;
        }
        if (id is >= 0 and <= 2) throw new InvalidDataException("ID 0、1、2 保留给原版维度");
        var reserved = DimensionDatabaseKeys.GlobalNames;
        string[] prefixes = ["actorprefix", "digp", "tickingarea", "VILLAGE_", "structuretemplate", "player_", "legacy_console_player_", "map_", "PosTrackDB-", "RealmsStoriesData_", "chunk_loaded_request_", "portals"];
        if (reserved.Contains(name, StringComparer.Ordinal) || prefixes.Any(prefix => name.StartsWith(prefix, StringComparison.Ordinal)))
            throw new InvalidDataException($"维度名称与保留数据库键冲突：{name}");
        return name;
    }

    internal static byte[] DataKey(string name) => Encoding.UTF8.GetBytes(name switch
    { "overworld" => "Overworld", "nether" => "Nether", "the_end" => "TheEnd", _ => name });

    public void Add(string name, int id)
    {
        name = ValidateAddition(name, id);
        if (Snapshot().Any(row => row.Name == name || row.Id == id))
            throw new InvalidDataException($"维度名称或 ID 已存在：{name}={id}");
        var key = DataKey(name);
        if (database.Get(key) is not null) throw new InvalidDataException($"数据库键已存在：{name}");
        var root = new NbtDocument("", new NbtCompoundValue([new("data", new NbtCompoundValue([
            new("LimboEntities", new NbtListValue(NbtTagType.Compound, []))]))]));
        var puts = new List<WorldDatabasePut> { new(key, BedrockNbtCodec.Encode(root)) };
        if (id is < 0 or > 2)
        {
            var registry = database.Get(RegistryKey) is { } bytes ? BedrockNbtCodec.Decode(bytes)
                : new NbtDocument("", new NbtCompoundValue([new("entries", new NbtCompoundValue([]))]));
            if (registry.Root is not NbtCompoundValue compound || compound.Tags.Count(tag => tag.Name == "entries") != 1
                || compound.CompoundValue("entries") is not NbtCompoundValue entries)
                throw new InvalidDataException("维度登记表必须包含唯一的 entries Compound");
            var replacement = new NbtNamedTag("entries", new NbtCompoundValue(entries.Tags.Append(new NbtNamedTag(name, new NbtIntValue(id))).ToArray()));
            var updated = new NbtDocument(registry.RootName, new NbtCompoundValue(compound.Tags.Select(tag => tag.Name == "entries" ? replacement : tag).ToArray()));
            puts.Add(new WorldDatabasePut(RegistryKey, BedrockNbtCodec.Encode(updated)));
        }
        database.ApplyBatch(puts, [], sync: true);
    }

    public IReadOnlyList<DimensionRecord> Snapshot()
    {
        var names = new Dictionary<int, string>();
        if (database.Get(RegistryKey) is { } bytes)
        {
            var root = BedrockNbtCodec.Decode(bytes, NbtEncoding.LittleEndian).Root;
            if (root.CompoundValue("entries") is not NbtCompoundValue entries)
                throw new InvalidDataException("DimensionNameIdTable.entries 必须为 Compound");
            foreach (var entry in entries.Tags)
            {
                if (entry.Value is not NbtIntValue id || entry.Name.Length == 0)
                    throw new InvalidDataException("维度登记必须为非空名称及 Int ID");
                if (names.TryGetValue(id.Value, out var existing) && existing != entry.Name)
                    throw new InvalidDataException($"维度 ID {id.Value} 有重复名称：{existing}、{entry.Name}");
                names[id.Value] = entry.Name;
            }
        }
        var keys = database.Entries(includeValues: false).Select(entry => entry.Key).ToArray();
        var keySet = keys.Select(key => Convert.ToHexString(key)).ToHashSet(StringComparer.Ordinal);
        var namedRoots = names.Values.Concat(new[]{"overworld","nether","the_end"})
            .Select(name => Convert.ToHexString(DataKey(name))).ToHashSet(StringComparer.Ordinal);
        (string Key, string Name, int Id)[] roots = [("Overworld", "overworld", 0), ("Nether", "nether", 1), ("TheEnd", "the_end", 2)];
        foreach (var (key, name, id) in roots)
            if (keySet.Contains(Convert.ToHexString(Encoding.UTF8.GetBytes(key))) || keySet.Contains(Convert.ToHexString(Encoding.UTF8.GetBytes($"dimension{id}")))) names.TryAdd(id, name);
        var positions = new Dictionary<int, HashSet<ChunkPosition>>();
        var digestPrefix = Encoding.ASCII.GetBytes("digp");
        foreach (var key in keys)
        {
            var text=Encoding.UTF8.GetString(key);
            if (namedRoots.Contains(Convert.ToHexString(key)) || DimensionDatabaseKeys.GlobalNames.Contains(text) || DimensionDatabaseKeys.PreservedPrefixes.Any(prefix=>text.StartsWith(prefix,StringComparison.Ordinal))) continue;
            ChunkPosition position;
            if ((key.Length is 12 or 16) && key.AsSpan().StartsWith(digestPrefix))
                position = new ChunkPosition(BinaryPrimitives.ReadInt32LittleEndian(key.AsSpan(4, 4)),
                    BinaryPrimitives.ReadInt32LittleEndian(key.AsSpan(8, 4)),
                    key.Length == 16 ? BinaryPrimitives.ReadInt32LittleEndian(key.AsSpan(12, 4)) : 0);
            else
            {
                if(new[]{"digp","actorprefix","tickingarea","VILLAGE_","portals"}.Any(prefix=>text.StartsWith(prefix,StringComparison.Ordinal))) continue;
                if(!BedrockRawChunkKey.TryParsePosition(key,out position)) continue;
            }
            if (!positions.TryGetValue(position.Dimension, out var set))
                positions[position.Dimension] = set = [];
            set.Add(position);
            var defaultName = position.Dimension switch { 0 => "overworld", 1 => "nether", 2 => "the_end", _ => position.Dimension.ToString(CultureInfo.InvariantCulture) };
            names.TryAdd(position.Dimension, defaultName);
        }
        return names.OrderBy(entry => entry.Key).Select(entry =>
            new DimensionRecord(entry.Value, entry.Key, positions.TryGetValue(entry.Key, out var chunks) ? chunks.Count : 0)).ToArray();
    }
}

internal static class DimensionDatabaseKeys
{
    internal static readonly HashSet<string> GlobalNames = new(["DimensionNameIdTable", "AutonomousEntities", "BiomeData", "BiomeIdsTable", "WorldClocks", "scoreboard", "mobevents", "mVillages", "villages", "dimension0", "dimension1", "dimension2", "schedulerWT", "portals", "LevelChunkMetaDataDictionary", "DynamicProperties", "PositionTrackDB-LastId", "LevelSpawnWasFixed", "game_flatworldlayers", "SST_SALOG", "SST_WORD", "SST_WORD_", "DedicatedServerForcedCorruption", "~local_player", "LocalPlayer", "TheEnd"], StringComparer.Ordinal);
    internal static readonly string[] PreservedPrefixes = ["player_", "legacy_console_player_", "map_", "PosTrackDB-", "RealmsStoriesData_", "structuretemplate"];
}
