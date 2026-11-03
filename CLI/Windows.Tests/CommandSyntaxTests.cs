namespace MCBEEditor.Cli.Tests;

internal static class CommandSyntaxTests
{
    public static void RunParserTests()
    {
        var reads = new[] { "help", "info", "dimension", "chunk", "structure", "time", "time query", "weather",
            "tickingarea", "tickingarea list", "tickingarea query 0", "entity" };
        var writes = new[] { "give @s minecraft:stone", "kill @a", "kill overworld 0 0 0 1 1 1",
            "effect give @a freezing", "effect clear @s", "summon minecraft:pig overworld 0 64 0",
            "setblock overworld 0 64 0 minecraft:stone", "fill 0 0 64 0 1 64 1 minecraft:stone",
            "storage set 0 0 64 0 1 minecraft:water", "weather rain", "tickingarea add circle 0 0 0 1 Spawn" };
        foreach (var (commands, mayMutate) in new[] { (reads, false), (writes, true) })
        {
            foreach (var text in commands)
            {
                using var error = new StringWriter();
                var plan = CliCommandPlan.Parse([new CliCommandLine(1, text)], error, forExecution: true);
                if (plan is null || plan.MayMutate != mayMutate || error.ToString().Length != 0)
                    throw new Exception("CLI syntax/default policy: " + text + "\n" + error);
            }
        }
        using var invalidError = new StringWriter();
        if (CliCommandPlan.Parse([new(1, "give @s minecraft:stone"), new(2, "kill 0 0 0 1 1 1")], invalidError, true) is not null
            || !invalidError.ToString().Contains("第 2 行"))
            throw new Exception("default parameters bypassed whole-script preflight");
        Console.WriteLine("CLI command syntax passed: 12 readonly queries, 11 writes and atomic syntax preflight.");
    }
}
