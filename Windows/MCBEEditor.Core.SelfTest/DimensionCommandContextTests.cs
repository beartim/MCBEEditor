using System.Text;
using MCBEEditor.Core.Chunk;
using MCBEEditor.Core.World;

static class DimensionCommandContextTests
{
    public static void Run()
    {
        using var db = new SelfTestWorldDatabase();
        var store = new DimensionStore(db); store.Add("initial",9000);
        db.Put(Encoding.UTF8.GetBytes("occupied"),new byte[]{0});
        var before = db.Entries(includeValues:true).ToDictionary(row=>Convert.ToHexString(row.Key),row=>Convert.ToHexString(row.Value!));
        var batches = db.ApplyBatchCount;
        var context = DimensionCommandContext.FromDatabase(db);
        context.Apply(DimensionCommandParser.Parse("dimension add bear 1000"));
        Check(context.Resolve("bear")==1000,"projected addition");
        Reject(()=>context.Apply(DimensionCommandParser.Parse("dimension add cat 1000")));
        Reject(()=>context.Apply(DimensionCommandParser.Parse("dimension add occupied 1100")));
        Check(context.Resolve("initial")==9000,"prior name retained");
        context.Apply(DimensionCommandParser.Parse("dimension empty bear"));
        Check(context.Resolve("bear")==1000,"empty retained projected name");
        context.Apply(DimensionCommandParser.Parse("dimension purge bear"));
        Reject(()=>context.Resolve("bear"));
        context.Apply(DimensionCommandParser.Parse("dimension add bear 1000"));
        Check(context.Resolve("bear")==1000,"purge/add reuse");
        Check(db.ApplyBatchCount==batches && before.Count==db.Entries().Count(),"projection wrote database");
        foreach(var row in db.Entries(includeValues:true)) Check(before[Convert.ToHexString(row.Key)]==Convert.ToHexString(row.Value!),"projection changed bytes");
        var numeric=new DimensionCommandContext(new[]{new DimensionRecord("1002",1002,1)});
        numeric.Apply(DimensionCommandParser.Parse("dimension empty 1002"));
        Check(numeric.Resolve("dimension_1002")==1002,"empty persists unregistered numeric dimension name");
        Console.WriteLine("Dimension command context tests passed.");
    }
    static void Reject(Action action){try{action();throw new InvalidOperationException("invalid projection accepted");}catch(InvalidDataException){}}
    static void Check(bool condition,string message){if(!condition)throw new InvalidOperationException(message);}
}
