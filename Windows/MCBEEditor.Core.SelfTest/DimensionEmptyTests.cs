using System.Text;
using System.Buffers.Binary;
using MCBEEditor.Core.World;
using MCBEEditor.Core.Nbt;
using MCBEEditor.Core.Chunk;

static class DimensionEmptyTests
{
    public static void Run()
    {
        using var db = new SelfTestWorldDatabase();
        var store = new DimensionStore(db); store.Add("bear",1000); store.Add("cat",1001);
        db.Put(BedrockDbKey.SubChunk(0,0,1000,0),[1]);
        var unknown = new byte[13]; BinaryPrimitives.WriteInt32LittleEndian(unknown.AsSpan(8,4),1000); unknown[12]=0x7f; db.Put(unknown,[2]);
        var other = BedrockDbKey.SubChunk(0,0,1001,0); db.Put(other,[3]);
        byte[] Ref(long id) { var b=new byte[8]; BinaryPrimitives.WriteInt64LittleEndian(b,id); return b; }
        byte[] Digest(int id) { var b=new byte[16]; Encoding.ASCII.GetBytes("digp").CopyTo(b,0); BinaryPrimitives.WriteInt32LittleEndian(b.AsSpan(12,4),id); return b; }
        byte[] Actor(long id) => Encoding.ASCII.GetBytes("actorprefix").Concat(Ref(id)).ToArray();
        db.Put(Digest(1000),Ref(7).Concat(Ref(8)).ToArray()); db.Put(Digest(1001),Ref(8));
        db.Put(Actor(7),[10,0,0,0]); db.Put(Actor(8),[10,0,0,0]);
        byte[] Nbt(int id) => BedrockNbtCodec.Encode(new NbtDocument("",new NbtCompoundValue([new("Dimension",new NbtIntValue(id))])));
        db.Put(Encoding.ASCII.GetBytes("tickingarea_target"),Nbt(1000)); db.Put(Encoding.ASCII.GetBytes("tickingarea_other"),Nbt(1001));
        db.Put(Encoding.ASCII.GetBytes("VILLAGE_uuid_INFO"),Nbt(1000)); db.Put(Encoding.ASCII.GetBytes("VILLAGE_uuid_POI"),[10,0,0,0]);
        var table=db.Get(DimensionStore.RegistryKey)!;
        var result=store.Empty(store.Resolve("bear"));
        Check(result.DeletedKeyCount>=6 && db.Get(unknown) is null,"delete all target records including unknown tags");
        Check(db.Get(Actor(7)) is null && db.Get(Actor(8)) is not null,"shared actor must survive");
        Check(db.Get(other)!.SequenceEqual(new byte[]{3}) && db.Get(Digest(1001))!.SequenceEqual(Ref(8)),"other dimension unchanged");
        Check(table.SequenceEqual(db.Get(DimensionStore.RegistryKey)!),"registry preserved exactly");
        Check(store.Snapshot().Single(x=>x.Id==1000).ChunkCount==0 && store.Resolve("1000")==1000,"empty dimension retained");
        Check(db.Get(Encoding.ASCII.GetBytes("tickingarea_target")) is null && db.Get(Encoding.ASCII.GetBytes("tickingarea_other")) is not null,"target tickingarea only");
        Check(db.Get(Encoding.ASCII.GetBytes("VILLAGE_uuid_POI")) is null,"village siblings inherit group dimension");
        LegacyAndFailureTests();
        MetadataTests();
        DimensionSafetyRegressionTests.Run();
        Console.WriteLine("Dimension empty tests passed.");
    }
    static void LegacyAndFailureTests()
    {
        NbtValue Village(int id)=>new NbtCompoundValue([new("Dimension",new NbtIntValue(id))]);
        NbtValue[] roots=[Village(1000),new NbtListValue(NbtTagType.Compound,[Village(1000),Village(1001)]),new NbtCompoundValue([new("first",Village(1000)),new("second",Village(1001))])];
        foreach(var root in roots)
        {
            using var db=new SelfTestWorldDatabase(); var store=new DimensionStore(db);
            store.Add("bear",1000); store.Add("cat",1001);
            var key=Encoding.UTF8.GetBytes("mVillages"); var bytes=BedrockNbtCodec.Encode(new NbtDocument("",root)); db.Put(key,bytes);
            store.Empty(1000);
            Check(!db.Get(key)!.SequenceEqual(bytes),"legacy root, list and compound map must change");
            var updated=BedrockNbtCodec.Decode(db.Get(key)!).Root;
            if(root is NbtListValue) Check(updated is NbtListValue list && list.Values.Count==1 && list.Values[0].CompoundValue("Dimension") is NbtIntValue dimension && dimension.Value==1001,"keep other legacy village in list");
            if(root is NbtCompoundValue compound && compound.Tags.Count==2) Check(updated is NbtCompoundValue map && map.Tags.Count==1 && map.Tags[0].Name=="second","keep other legacy village in map");
        }
        using var guarded=new SelfTestWorldDatabase(); var target=new DimensionStore(guarded); target.Add("overworld",0);
        foreach(var name in new[]{"schedulerWT","dimension0","portals"}) guarded.Put(Encoding.UTF8.GetBytes(name),[10,0,0,0]);
        guarded.Put("VILLAGE_NETHER_uuid_INFO"u8.ToArray(),[10,0,0,0]);
        target.Empty(0);
        Check(guarded.Get("VILLAGE_NETHER_uuid_INFO"u8.ToArray()) is not null,"vanilla village key ownership does not depend on discovered dimension roots");
        foreach(var name in new[]{"schedulerWT","portals"}) Check(guarded.Get(Encoding.UTF8.GetBytes(name)) is not null,"protect global metadata keys");
        string[] Snapshot()=>guarded.Entries(includeValues:true).Select(e=>Convert.ToHexString(e.Key)+":"+Convert.ToHexString(e.Value!)).Order().ToArray();
        var digest="digp"u8.ToArray().Concat(new byte[8]).ToArray(); guarded.Put(digest,[1]);
        var before=Snapshot();
        try { target.Empty(0); throw new InvalidOperationException("malformed digest accepted"); }
        catch(InvalidDataException) { Check(before.SequenceEqual(Snapshot()),"failed preflight must preserve all bytes"); }
        guarded.Delete(digest);
        guarded.Put(Encoding.UTF8.GetBytes("portals"),BedrockNbtCodec.Encode(new NbtDocument("",Village(0)))); before=Snapshot();
        try { target.Empty(0); throw new InvalidOperationException("unsupported portal layout accepted"); }
        catch(InvalidDataException) { Check(before.SequenceEqual(Snapshot()),"unsupported metadata must preserve all bytes"); }
    }
    static void MetadataTests()
    {
        using var db=new SelfTestWorldDatabase(); var store=new DimensionStore(db); store.Add("bear",1000); store.Add("cat",1001);
        byte[] Encode(NbtValue root)=>BedrockNbtCodec.Encode(new NbtDocument("",root));
        NbtValue Portal(int id)=>new NbtCompoundValue([new("DimId",new NbtIntValue(id)),new("TpX",new NbtIntValue(17))]);
        db.Put("portals"u8.ToArray(),Encode(new NbtCompoundValue([new("data",new NbtCompoundValue([new("PortalRecords",new NbtListValue(NbtTagType.Compound,[Portal(1000),Portal(1001)])),new("setting",new NbtIntValue(5))]))])));
        var scheduler=Encode(new NbtCompoundValue([new("daysSinceLastWTSpawn",new NbtIntValue(3))])); db.Put("schedulerWT"u8.ToArray(),scheduler);
        db.Put("VILLAGE_bear_uuid_RAID"u8.ToArray(),[10,0,0,0]); db.Put("VILLAGE_cat_uuid_INFO"u8.ToArray(),[10,0,0,0]);
        store.Empty(1000);
        var data=BedrockNbtCodec.Decode(db.Get("portals"u8.ToArray())!).Root.CompoundValue("data")!;
        Check(data.CompoundValue("PortalRecords") is NbtListValue list && list.Values.Count==1 && list.Values[0].IntValue("DimId")==1001,"remove target portal only");
        Check(data.IntValue("setting")==5 && db.Get("schedulerWT"u8.ToArray())!.SequenceEqual(scheduler),"preserve global settings");
        Check(db.Get("VILLAGE_bear_uuid_RAID"u8.ToArray()) is null && db.Get("VILLAGE_cat_uuid_INFO"u8.ToArray()) is not null,"dimension name in village key owns raid records");
        using var legacy=new SelfTestWorldDatabase(); var legacyStore=new DimensionStore(legacy);
        legacy.Put("dimension1"u8.ToArray(),Encode(new NbtCompoundValue([new("bridge",new NbtCompoundValue([]))]))); legacy.Put("dimension2"u8.ToArray(),[10,0,0,0]);
        Check(legacyStore.Snapshot().Select(row=>row.Id).SequenceEqual(new[]{1,2}),"discover legacy dimensions");
        var other=legacy.Get("dimension2"u8.ToArray())!; legacyStore.Empty(1);
        Check(legacy.Get("dimension1"u8.ToArray()) is null && legacy.Get("dimension2"u8.ToArray())!.SequenceEqual(other),"clear target legacy structure cache");
        Check(legacyStore.Snapshot().Select(row=>row.Id).SequenceEqual(new[]{1,2}),"keep empty legacy dimension via canonical root");
        legacy.Put("TheEnd"u8.ToArray(),Encode(new NbtCompoundValue([new("data",new NbtCompoundValue([new("DragonFight",new NbtCompoundValue([new("DragonUUID",new NbtLongValue(99))])),new("setting",new NbtIntValue(42))]))])));
        legacyStore.Empty(2);
        var endData=BedrockNbtCodec.Decode(legacy.Get("TheEnd"u8.ToArray())!).Root.CompoundValue("data")!;
        Check(endData.CompoundValue("DragonFight") is null && endData.IntValue("setting")==42,"clear stale dragon fight while retaining settings");
    }
    static void Check(bool ok,string message) { if(!ok) throw new InvalidOperationException(message); }
}
