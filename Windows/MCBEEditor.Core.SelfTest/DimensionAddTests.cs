using System.Text;
using MCBEEditor.Core.Nbt;
using MCBEEditor.Core.World;

static class DimensionAddTests
{
    public static void Run()
    {
        using var db = new SelfTestWorldDatabase();
        var store = new DimensionStore(db);
        store.Add("wzn:bear", 1000);
        store.Add("bear", 1001);
        Check(db.ApplyBatchCount == 2, "one batch for each addition");
        var table = BedrockNbtCodec.Decode(db.Get(DimensionStore.RegistryKey)!).Root.CompoundValue("entries")!;
        Check(table.IntValue("wzn:bear") == 1000 && table.IntValue("bear") == 1001, "names preserved in actual registry");
        var dim = BedrockNbtCodec.Decode(db.Get(Encoding.UTF8.GetBytes("bear"))!).Root;
        Check(dim.CompoundValue("data")?.CompoundValue("LimboEntities") is NbtListValue { ElementType: NbtTagType.Compound, Values.Count: 0 }, "dimension root matches sample");
        Check(new DimensionStore(db).Snapshot().Select(x => x.Id).SequenceEqual(new[] {1000,1001}), "reopened service sees empty registered dimensions");
        db.Put(Encoding.UTF8.GetBytes("existing_global_control"), [1,2,3]);
        foreach (var (name,id) in new[] { ("bear",2000), ("other",1000), ("existing_global_control",2000), ("scoreboard",2000),("portals",2000),("dimension1",2000),("schedulerWT",2000),("map_test",2000), ("123",2000), ("white space",2000), ("overworld",5), ("other",0) })
        {
            var before = Bytes(db);
            try { store.Add(name,id); throw new Exception("invalid add accepted: " + name); }
            catch (InvalidDataException) { }
            Check(before.SequenceEqual(Bytes(db)), "rejected add must leave all bytes untouched");
        }
        foreach (var (name,id,key) in new[] { ("overworld",0,"Overworld"), ("nether",1,"Nether"), ("the_end",2,"TheEnd") })
        {
            store.Add(name,id);
            Check(db.Get(Encoding.UTF8.GetBytes(key)) is not null, "restore canonical dimension root");
        }
        Check(new DimensionStore(db).Snapshot().Select(x => x.Id).SequenceEqual(new[] {0,1,2,1000,1001}), "canonical missing dimensions restored");
        store.Add("negative",int.MinValue); store.Add("positive",int.MaxValue);
        Console.WriteLine("Dimension add tests passed.");
    }
    static string[] Bytes(SelfTestWorldDatabase db) => db.Entries(includeValues:true).Select(x => Convert.ToHexString(x.Key)+Convert.ToHexString(x.Value!)).ToArray();
    static void Check(bool ok,string message) { if (!ok) throw new InvalidOperationException(message); }
}
