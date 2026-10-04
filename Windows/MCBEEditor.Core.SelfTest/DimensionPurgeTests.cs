using MCBEEditor.Core.World;
using MCBEEditor.Core.Nbt;
using MCBEEditor.Core.Chunk;

static class DimensionPurgeTests
{
    public static void Run()
    {
        byte[] Encode(NbtValue root)=>BedrockNbtCodec.Encode(new NbtDocument("",root));
        var player=new NbtCompoundValue([new("DimensionId",new NbtIntValue(1000)),new("Pos",new NbtListValue(NbtTagType.Float,[new NbtFloatValue(5),new NbtFloatValue(66),new NbtFloatValue(8)])),new("SpawnDimension",new NbtIntValue(1000)),new("SpawnX",new NbtIntValue(5)),new("SpawnY",new NbtIntValue(64)),new("SpawnZ",new NbtIntValue(8)),new("Health",new NbtShortValue(20))]);
        using var db=new SelfTestWorldDatabase();var store=new DimensionStore(db);store.Add("bear",1000);store.Add("nether",1);
        db.Put("~local_player"u8.ToArray(),Encode(player));db.Put(BedrockDbKey.SubChunk(0,0,1000,0),[1]);
        db.Put("WorldClocks"u8.ToArray(),Encode(new NbtCompoundValue([new("clocks",new NbtListValue(NbtTagType.Compound,[new NbtCompoundValue([new("Name",new NbtStringValue("bear"))]),new NbtCompoundValue([new("Name",new NbtStringValue("minecraft:nether"))])]))])));
        var batches=db.ApplyBatchCount;var result=store.Purge(1000);
        Check(result.AffectedPlayerCount==1 && db.ApplyBatchCount==batches+1,"purge and player migration must use one batch");
        Check(store.Snapshot().Select(row=>row.Id).SequenceEqual(new[]{1}) && db.Get("bear"u8.ToArray()) is null,"purged dimension absent");
        var updated=BedrockNbtCodec.Decode(db.Get("~local_player"u8.ToArray())!).Root;
        Check(updated.IntValue("DimensionId")==1 && updated.IntValue("SpawnDimension")==1 && updated.IntValue("SpawnX")==0 && updated.IntValue("SpawnY")==64 && updated.IntValue("SpawnZ")==0,"migrate current and respawn references");
        Check(updated.CompoundValue("Pos") is NbtListValue position && position.Values.Count==3 && position.Values[0] is NbtFloatValue {Value:0.5f} && position.Values[1] is NbtFloatValue y && Math.Abs(y.Value-65.62f)<0.001 && position.Values[2] is NbtFloatValue {Value:0.5f},"migrate position coordinates");
        Check(updated.CompoundValue("Health") is NbtShortValue {Value:20},"retain player settings");
        Check(BedrockNbtCodec.Decode(db.Get("WorldClocks"u8.ToArray())!).Root.CompoundValue("clocks") is NbtListValue list && list.Values.Count==1 && list.Values[0].StringValue("Name")=="minecraft:nether","remove only target clock");
        store.Add("bear",1000);
        using var only=new SelfTestWorldDatabase();var onlyStore=new DimensionStore(only);onlyStore.Add("bear",1000);only.Put("~local_player"u8.ToArray(),Encode(player));
        string[] Snapshot()=>only.Entries(includeValues:true).Select(entry=>Convert.ToHexString(entry.Key)+Convert.ToHexString(entry.Value!)).ToArray();
        var before=Snapshot();batches=only.ApplyBatchCount;
        try {onlyStore.Purge(1000);throw new InvalidOperationException("last dimension with player accepted");} catch(InvalidDataException) {Check(before.SequenceEqual(Snapshot()) && only.ApplyBatchCount==batches,"reject without partial write");}
        only.Delete("~local_player"u8.ToArray());onlyStore.Purge(1000);Check(onlyStore.Snapshot().Count==0,"allow last dimension when no player references");
        Console.WriteLine("Dimension purge tests passed.");
    }
    static void Check(bool ok,string message) {if(!ok)throw new InvalidOperationException(message);}
}
