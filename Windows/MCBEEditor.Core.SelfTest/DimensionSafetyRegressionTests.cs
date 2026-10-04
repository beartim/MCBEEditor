using System.Buffers.Binary;
using System.Text;
using MCBEEditor.Core.World;
using MCBEEditor.Core.Chunk;
using MCBEEditor.Core.Nbt;

static class DimensionSafetyRegressionTests
{
    public static void Run()
    {
        RawOnly(); VillagePrefixes(); OwnershipAliases();
        Console.WriteLine("Dimension safety regressions passed: unknown raw tags, longest village names and atomic ownership rejection.");
    }
    static void RawOnly()
    {
        foreach(var id in new[]{0,43,44,47,118,1000,-1,int.MinValue,int.MaxValue})
        foreach(var suffix in new[]{1,2,3})
        {
            var key=new byte[(id==0 ? 8 : 12)+suffix];
            BinaryPrimitives.WriteInt32LittleEndian(key.AsSpan(0,4),7);
            BinaryPrimitives.WriteInt32LittleEndian(key.AsSpan(4,4),9);
            if(id!=0) BinaryPrimitives.WriteInt32LittleEndian(key.AsSpan(8,4),id);
            key[id==0 ? 8 : 12]=0x7f;
            using var db=new SelfTestWorldDatabase(); db.Put(key,[42]); var store=new DimensionStore(db);
            var before=Bytes(db); var batches=db.ApplyBatchCount;
            var row=store.Snapshot().SingleOrDefault();
            Check(row is not null && row.Id==id && row.ChunkCount==1,"discover unknown-tag-only dimension: "+id);
            Check(before.SequenceEqual(Bytes(db)) && batches==db.ApplyBatchCount,"query does not write");
            try {store.Add(id==0 ? "overworld" : "raw-test",id); throw new InvalidOperationException("occupied raw ID accepted");}
            catch(InvalidDataException) {Check(before.SequenceEqual(Bytes(db)) && batches==db.ApplyBatchCount,"rejected add preserves all bytes");}
            store.Empty(id);
            Check(db.Get(key) is null && store.Snapshot().Single().Id==id && store.Snapshot().Single().ChunkCount==0,"empty raw dimension retains root");
            using var purgeDb=new SelfTestWorldDatabase(); purgeDb.Put(key,[42]); var purgeStore=new DimensionStore(purgeDb);
            purgeStore.Purge(id);
            Check(purgeDb.Get(key) is null && purgeStore.Snapshot().Count==0,"purge raw-only dimension");
        }
        using var metadata=new SelfTestWorldDatabase();
        foreach(var name in new[]{"Overworld","Nether","TheEnd","tickingarea_xy","VILLAGE_x","portals_x","map_abcde","player_abcdef","digp_xxxx"})
            metadata.Put(Encoding.UTF8.GetBytes(name),[10,0,0,0]);
        var roots=new DimensionStore(metadata).Snapshot();
        Check(roots.Select(row=>row.Id).SequenceEqual(new[]{0,1,2}) && roots.All(row=>row.ChunkCount==0),"exclude roots and metadata from raw discovery");
    }
    static void VillagePrefixes()
    {
        foreach(var (name,id) in new[]{("overworld",0),("nether",1),("the_end",2)})
        foreach(var purge in new[]{false,true})
        {
            using var db=new SelfTestWorldDatabase(); var store=new DimensionStore(db);
            store.Add(name,id); store.Add(name+"_custom",1000);
            var key=Encoding.UTF8.GetBytes($"VILLAGE_{name}_custom_uuid_RAID");
            byte[] village=[10,0,0,0]; db.Put(key,village);
            if(purge) store.Purge(id); else store.Empty(id);
            Check(db.Get(key)?.SequenceEqual(village)==true,"preserve longer custom-name village: "+name);
            if(purge) store.Purge(1000); else store.Empty(1000);
            Check(db.Get(key) is null,"delete custom dimension village: "+name);
        }
    }
    static void OwnershipAliases()
    {
        foreach(var alias in new NbtValue[]{new NbtIntValue(1001),new NbtStringValue("missing"),new NbtLongValue((long)int.MaxValue+1)})
        foreach(var reverse in new[]{false,true})
        foreach(var purge in new[]{false,true})
        foreach(var kind in new[]{"actor","tickingarea","village","autonomous","legacyVillage"})
        {
            using var db=new SelfTestWorldDatabase(); var store=new DimensionStore(db);
            store.Add("bear",1000); store.Add("cat",1001);
            db.Put(BedrockDbKey.SubChunk(0,0,1000,0),[42]);
            NbtNamedTag[] fields=[new("Dimension",new NbtIntValue(1000)),new("DimensionId",alias)];
            if(reverse) Array.Reverse(fields);
            NbtValue root=new NbtCompoundValue(fields);
            var key=kind switch {
                "actor"=>"actorprefix"u8.ToArray().Concat(new byte[8]).ToArray(),
                "tickingarea"=>"tickingarea_test"u8.ToArray(), "village"=>"VILLAGE_bear_uuid_INFO"u8.ToArray(),
                "autonomous"=>"AutonomousEntities"u8.ToArray(), _=>"mVillages"u8.ToArray() };
            if(kind=="autonomous") root=new NbtCompoundValue([new("AutonomousEntityList",new NbtListValue(NbtTagType.Compound,[root]))]);
            if(kind=="legacyVillage") root=new NbtListValue(NbtTagType.Compound,[root]);
            db.Put(key,BedrockNbtCodec.Encode(new NbtDocument("",root)));
            var before=Bytes(db); var batches=db.ApplyBatchCount;
            try {if(purge) store.Purge(1000); else store.Empty(1000); throw new InvalidOperationException("invalid direct owner accepted: "+kind);}
            catch(InvalidDataException) {Check(before.SequenceEqual(Bytes(db)) && db.ApplyBatchCount==batches,"ownership rejection must leave all bytes unchanged: "+kind);}
        }
        using var valid=new SelfTestWorldDatabase(); var storeValid=new DimensionStore(valid); storeValid.Add("bear",1000);
        valid.Put("tickingarea_agree"u8.ToArray(),BedrockNbtCodec.Encode(new NbtDocument("",new NbtCompoundValue([new("Dimension",new NbtIntValue(1000)),new("DimensionId",new NbtStringValue("bear"))]))));
        storeValid.Empty(1000); Check(valid.Get("tickingarea_agree"u8.ToArray()) is null,"agreeing aliases supported");
    }
    static string[] Bytes(SelfTestWorldDatabase db)=>db.Entries(includeValues:true).Select(e=>Convert.ToHexString(e.Key)+":"+Convert.ToHexString(e.Value!)).Order().ToArray();
    static void Check(bool value,string message) {if(!value) throw new InvalidOperationException(message);}
}
