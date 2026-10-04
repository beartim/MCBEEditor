using MCBEEditor.Core.Chunk;
using MCBEEditor.Core.World;

static class DimensionCommandResolverTests
{
    public static void Run()
    {
        using var db=new SelfTestWorldDatabase();var store=new DimensionStore(db);store.Add("wzn:bear",1000);store.Add("bear",1001);
        Func<string, int> resolver=store.Resolve;
        Check(BlockCommandParser.Parse("setblock wzn:bear 0 64 0 minecraft:stone NULL",resolver) is SetBlockCommandRequest {Dimension:1000},"setblock custom name");
        Check(BlockCommandParser.Parse("clone wzn:bear 0 0 0 1 1 1 bear 2 2 2",resolver) is CloneBlockCommandRequest {SourceDimension:1000,TargetDimension:1001},"cross dimension clone");
        Check(StorageBiomeCommandParser.Parse("storage query bear 0 64 0",resolver) is StorageQueryStorageBiomeCommandRequest {Dimension:1001},"storage plain name");
        Check(TargetingCommandParser.Parse("teleport @s wzn:bear 0 Auto 0",resolver) is TeleportTargetingCommandRequest {Dimension:1000},"teleport custom name");
        Check(EntityActionCommandParser.Parse("summon minecraft:pig bear 0 64 0 default",resolver) is SummonEntityActionCommandRequest {Dimension:1001},"summon custom name");
        Check(EntityQueryCommandParser.Parse("entity bear",resolver).Dimension==1001,"entity custom name");
        Check(EnvironmentCommandParser.Parse("tickingarea add circle wzn:bear 0 0 1 test 0",resolver) is TickingAreaEnvironmentCommandRequest {Area: {Dimension:1000}},"tickingarea custom dimension");
        Check(StructureTemplateCommandParser.Parse("structure load wzn:test bear 0 64 0",resolver).Dimension==1001,"structure custom dimension");
        Check(ChunkCommandParser.Parse("chunk query wzn:bear",resolver).Dimension==1000,"chunk custom name");
        Check(BlockCommandParser.Parse("getblock -2147483648 0 0 0") is GetBlockCommandRequest {Dimension:int.MinValue},"numeric boundary without world");
        try{BlockCommandParser.Parse("getblock missing 0 0 0",resolver);throw new InvalidOperationException("unknown dimension accepted");}catch(InvalidDataException){}
        using var other=new SelfTestWorldDatabase();var otherStore=new DimensionStore(other);otherStore.Add("bear",9000);
        Check(BlockCommandParser.Parse("getblock bear 0 0 0",otherStore.Resolve) is GetBlockCommandRequest {Dimension:9000},"world resolvers must remain isolated");
        Console.WriteLine("Dimension command resolver tests passed.");
    }
    static void Check(bool ok,string message){if(!ok)throw new InvalidOperationException(message);}
}
