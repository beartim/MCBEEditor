using System.Text.Json;
using MCBEEditor.Core.Chunk;

internal static class CommandSyntaxTests
{
    private static object Parse(string text)
    {
        if (DimensionCommandParser.IsDimensionCommand(text)) return DimensionCommandParser.Parse(text);
        if (BlockCommandParser.IsBlockCommand(text)) return BlockCommandParser.Parse(text);
        if (StorageBiomeCommandParser.IsStorageBiomeCommand(text)) return StorageBiomeCommandParser.Parse(text);
        if (EntityActionCommandParser.IsEntityActionCommand(text)) return EntityActionCommandParser.Parse(text);
        if (TargetingCommandParser.IsTargetingCommand(text)) return TargetingCommandParser.Parse(text);
        if (EnvironmentCommandParser.IsEnvironmentCommand(text)) return EnvironmentCommandParser.Parse(text);
        if (StructureTemplateCommandParser.IsStructureTemplateCommand(text)) return StructureTemplateCommandParser.Parse(text);
        return ChunkCommandParser.Parse(text);
    }

    public static void Run()
    {
        var pairs = new (string Short, string Explicit)[] {
            ("dimension", "dimension query"), ("chunk", "chunk query"), ("structure", "structure query"),
            ("time", "time query daytime"), ("time query", "time query daytime"),
            ("weather", "weather query"), ("weather clear", "weather clear 1"),
            ("weather rain", "weather rain 6000 1.0 1"), ("weather thunder", "weather thunder 6000 1.0 1"),
            ("weather rain 100", "weather rain 100 1.0 1"), ("weather thunder 100 0.25", "weather thunder 100 0.25 1"),
            ("tickingarea", "tickingarea list ALL"), ("tickingarea list", "tickingarea list ALL"),
            ("tickingarea query", "tickingarea list ALL"), ("tickingarea query nether", "tickingarea list nether"),
            ("tickingarea add square 0 1 1 0 0 Spawn", "tickingarea add square 0 1 1 0 0 Spawn 0"),
            ("tickingarea add circle 0 1 -1 0 Spawn", "tickingarea add circle 0 1 -1 0 Spawn 0"),
            ("give @s minecraft:stone", "give @s Auto minecraft:stone 1 NULL"),
            ("give @s minecraft:stone 64", "give @s Auto minecraft:stone 64 NULL"),
            ("give @s minecraft:stone 64 NULL", "give @s Auto minecraft:stone 64 NULL"),
            ("give @s 5 minecraft:stone", "give @s 5 minecraft:stone 1 NULL"),
            ("give @s Auto minecraft:stone 64", "give @s Auto minecraft:stone 64 NULL"),
            ("give @s aUtO minecraft:stone 64 null", "give @s Auto minecraft:stone 64 NULL"),
            ("kill @a", "kill @a 0"), ("kill -42", "kill -42 0"),
            ("kill 7 1 1 1 0 0 0", "kill 7 1 1 1 0 0 0 0"),
            ("effect give @s freezing", "effect give @s freezing 600 0"),
            ("effect give @s freezing -1", "effect give @s freezing -1 0"),
            ("effect give @s minecraft:freezing", "effect give @s freezing 600 0"),
            ("effect clear @s", "effect clear @s ALL"),
            ("effect clear @s minecraft:freezing", "effect clear @s freezing"),
            ("summon minecraft:pig 0 0 64 0", "summon minecraft:pig 0 0 64 0 default Auto"),
            ("summon minecraft:pig 0 0 64 0 DEFAULT auto", "summon minecraft:pig 0 0 64 0 default Auto"),
            ("setblock 0 0 64 0 minecraft:stone", "setblock 0 0 64 0 minecraft:stone NULL preserve"),
            ("setblock 0 0 64 0 minecraft:stone NULL", "setblock 0 0 64 0 minecraft:stone NULL preserve"),
            ("setblock 0 0 64 0 minecraft:stone empty", "setblock 0 0 64 0 minecraft:stone NULL empty"),
            ("setblock 0 0 64 0 minecraft:stone minecraft:water", "setblock 0 0 64 0 minecraft:stone NULL minecraft:water NULL preserve"),
            ("setblock 0 0 64 0 minecraft:stone null minecraft:water EMPTY", "setblock 0 0 64 0 minecraft:stone NULL minecraft:water NULL empty"),
            ("fill 0 0 64 0 1 64 1 minecraft:stone", "fill 0 0 64 0 1 64 1 minecraft:stone NULL preserve"),
            ("fill 0 0 64 0 1 64 1 minecraft:stone NULL", "fill 0 0 64 0 1 64 1 minecraft:stone NULL preserve"),
            ("storage set 0 0 64 0 2 minecraft:water", "storage set 0 0 64 0 2 minecraft:water NULL")
        };
        foreach (var (shortText, explicitText) in pairs)
        {
            var actual = Parse(shortText); var expected = Parse(explicitText);
            // Request payloads use init properties. Exclude derived properties
            // such as Area.Normalized, which recursively return another area.
            var options = new JsonSerializerOptions { IgnoreReadOnlyProperties = true };
            Check(actual.GetType() == expected.GetType()
                && JsonSerializer.Serialize(actual, actual.GetType(), options) == JsonSerializer.Serialize(expected, expected.GetType(), options),
                "default differs: " + shortText);
            if (actual is SetBlockCommandRequest set && expected is SetBlockCommandRequest expectedSet)
                Check(set.BlockEntity.Mode == expectedSet.BlockEntity.Mode, "setblock entity mode: " + shortText);
            if (actual is FillBlockCommandRequest fill && expected is FillBlockCommandRequest expectedFill)
                Check(fill.BlockEntity.Mode == expectedFill.BlockEntity.Mode, "fill entity mode: " + shortText);
        }
        var state = "'String'\"kind\"=\"A B\"";
        var template = "'String'\"id\"=\"Chest\"";
        var block = (SetBlockCommandRequest)Parse("setblock 0 0 64 0 minecraft:stone " + state + " " + template);
        Check(block.Storages.Single().States.Single().Name == "kind" && block.BlockEntity.Mode == BlockEntityCommandMode.Template,
            "adjacent states and block-entity NBT must remain separate");
        var onlyState = (SetBlockCommandRequest)Parse("setblock 0 0 64 0 minecraft:stone " + state);
        Check(onlyState.BlockEntity.Mode == BlockEntityCommandMode.Preserve && onlyState.Storages.Single().States.Count == 1,
            "first NBT after block belongs to states");
        var max = (SetBlockCommandRequest)Parse("setblock 0 0 64 0 " + string.Join(' ', Enumerable.Repeat("minecraft:air", 255)));
        Check(max.Storages.Count == 255, "255 omitted states");
        Reject("setblock 0 0 64 0 " + string.Join(' ', Enumerable.Repeat("minecraft:air", 256)));
        foreach (var text in new[] {
            "dimension extra", "chunk query 0 1", "structure query extra", "time query daytime extra", "time add",
            "weather query extra", "weather clear 1 extra", "weather rain 1 1 1 extra", "weather rain NULL",
            "tickingarea delete", "tickingarea query ALL extra", "tickingarea add square 0 0 0 1 1",
            "give @s", "give @s minecraft:stone NULL", "give @s Auto minecraft:stone 1 NULL extra",
            "give @s 36 minecraft:stone", "give @s minecraft:stone 0", "kill", "kill 0 0 0 1 1 1", "kill @a 2",
            "effect give @s", "effect give @s freezing NULL", "effect clear @s ALL extra", "effect clear @s all",
            "summon minecraft:pig 0 0 64", "summon minecraft:pig 0 0 64 0 42", "summon minecraft:pig 0 0 64 0 NULL",
            "setblock 0 0 64 0", "setblock 0 0 64 0 minecraft:stone NULL NULL",
            "setblock 0 0 64 0 minecraft:stone empty minecraft:water", "storage set 0 0 64 0 minecraft:stone",
            "storage set 0 0 64 0 0 minecraft:stone NULL extra" }) Reject(text);
        Check(EnvironmentCommandParser.Parse("tickingarea list all", name => name == "all" ? 7 : throw new Exception())
            is TickingAreaEnvironmentCommandRequest { Dimension: 7 }, "lowercase all dimension must retain its meaning");
        Check(EnvironmentCommandParser.Parse("tickingarea delete all") is TickingAreaEnvironmentCommandRequest { Name: "all" },
            "lowercase all name must not delete all areas");
        Console.WriteLine($"Command syntax passed: {pairs.Length} typed default equivalences, NBT boundaries, 255 layers and strict failures.");
    }

    private static void Check(bool value, string message)
    {
        if (!value) throw new Exception("Command syntax: " + message);
    }
    private static void Reject(string text)
    {
        var rejected = false;
        try { _ = Parse(text); } catch (InvalidDataException) { rejected = true; }
        Check(rejected, "invalid syntax accepted: " + text);
    }
}
