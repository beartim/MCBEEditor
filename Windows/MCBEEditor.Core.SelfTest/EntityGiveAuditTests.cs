using System.Text;
using MCBEEditor.Core.Chunk;
using MCBEEditor.Core.Nbt;

internal static class EntityGiveAuditTests
{
    private static void Check(bool value, string message)
    {
        if (!value) throw new Exception("Entity give regression: " + message);
    }

    public static void Run()
    {
        using var database = new SelfTestWorldDatabase();
        var key = Encoding.UTF8.GetBytes("~local_player");
        var store = new EntityActionCommandStore(database);
        NbtValue Item(int slot, string name) => new NbtCompoundValue([
            new("Slot", new NbtByteValue((sbyte)slot)), new("Name", new NbtStringValue(name)), new("Count", new NbtByteValue(1))]);
        void Seed(params NbtValue[] items) => database.Put(key, BedrockNbtCodec.Encode(new NbtDocument("", new NbtCompoundValue([
            new("UniqueID", new NbtLongValue(1001)), new("DimensionId", new NbtIntValue(0)),
            new("Pos", new NbtListValue(NbtTagType.Float, [new NbtFloatValue(0), new NbtFloatValue(64), new NbtFloatValue(0)])),
            new("Inventory", new NbtListValue(NbtTagType.Compound, items))])), NbtEncoding.LittleEndian));
        IReadOnlyList<NbtValue> Inventory() => ((NbtListValue)BedrockNbtCodec.Decode(database.Get(key)!, NbtEncoding.LittleEndian)
            .Root.CompoundValue("Inventory")!).Values;
        void Give(string command) => Check(store.Give((GiveEntityActionCommandRequest)EntityActionCommandParser.Parse(command)).ChangedWorld, command);
        string? NameAt(int slot) => Inventory().Single(item => item.CompoundValue("Slot")?.IntegerValue() == slot).StringValue("Name");

        Seed(Item(5, "minecraft:stone"), Item(9, "minecraft:dirt"));
        Give("give @s 0 minecraft:diamond 3 NULL");
        Check(Inventory().Count == 3 && NameAt(5) == "minecraft:stone" && NameAt(9) == "minecraft:dirt"
              && NameAt(0) == "minecraft:diamond", "indexed give overwrote an unrelated sparse slot");

        Seed(Item(5, "minecraft:stone"), Item(9, "minecraft:dirt"));
        Give("give @s Auto minecraft:diamond 3 NULL");
        Check(Inventory().Count == 3 && NameAt(0) == "minecraft:diamond" && NameAt(5) == "minecraft:stone"
              && NameAt(9) == "minecraft:dirt", "Auto must use the first absent slot");

        Seed(Item(0, "minecraft:stone"), Item(9, ""));
        Give("give @s Auto minecraft:diamond 3 NULL");
        Check(NameAt(1) == "minecraft:diamond" && NameAt(0) == "minecraft:stone" && NameAt(9) == "", "Auto must prefer the lower missing slot");

        Seed(Enumerable.Range(0, 36).Select(slot => Item(slot, "minecraft:stone")).ToArray());
        Give("give @s Auto minecraft:diamond 3 NULL");
        Check(Inventory().Count == 36 && NameAt(35) == "minecraft:diamond"
              && Enumerable.Range(0, 35).All(slot => NameAt(slot) == "minecraft:stone"), "full inventory fallback changed");

        Seed();
        Give("give @s 0 minecraft:diamond 128 'String'\"name\"=\"minecraft:dirt\",'Long'\"count\"=\"999\",'Byte'\"slot\"=\"5\",'Byte'\"waspickedup\"=\"1\",'String'\"note\"=\"keep\"");
        var stack = Inventory().Single();
        Check(stack.StringValue("Name") == "minecraft:diamond" && stack.CompoundValue("Count") is NbtShortValue { Value: 128 }
              && stack.CompoundValue("Slot")?.IntegerValue() == 0 && stack.CompoundValue("WasPickedUp")?.IntegerValue() == 0
              && stack.StringValue("note") == "keep", "command-owned tags must retain canonical names and values");
        Console.WriteLine("Entity give audit: 5 behavioral scenarios passed.");
    }
}
