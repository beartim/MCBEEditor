import Foundation

enum CommandSyntaxRegression {
    static func run() throws {
        let pairs: [(String, String)] = [
            ("dimension", "dimension query"),
            ("chunk", "chunk query"),
            ("structure", "structure query"),
            ("time", "time query daytime"),
            ("time query", "time query daytime"),
            ("weather", "weather query"),
            ("weather clear", "weather clear 1"),
            ("weather rain", "weather rain 6000 1.0 1"),
            ("weather thunder", "weather thunder 6000 1.0 1"),
            ("weather rain 100", "weather rain 100 1.0 1"),
            ("weather thunder 100 0.25", "weather thunder 100 0.25 1"),
            ("tickingarea", "tickingarea list ALL"),
            ("tickingarea list", "tickingarea list ALL"),
            ("tickingarea query", "tickingarea list ALL"),
            ("tickingarea query nether", "tickingarea list nether"),
            ("tickingarea add square 0 1 1 0 0 Spawn", "tickingarea add square 0 1 1 0 0 Spawn 0"),
            ("tickingarea add circle 0 1 -1 0 Spawn", "tickingarea add circle 0 1 -1 0 Spawn 0"),
            ("give @s minecraft:stone", "give @s Auto minecraft:stone 1 NULL"),
            ("give @s minecraft:stone 64", "give @s Auto minecraft:stone 64 NULL"),
            ("give @s minecraft:stone 64 NULL", "give @s Auto minecraft:stone 64 NULL"),
            ("give @s 5 minecraft:stone", "give @s 5 minecraft:stone 1 NULL"),
            ("give @s Auto minecraft:stone 64", "give @s Auto minecraft:stone 64 NULL"),
            ("give @s aUtO minecraft:stone 64 null", "give @s Auto minecraft:stone 64 NULL"),
            ("kill @a", "kill @a 0"),
            ("kill -42", "kill -42 0"),
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
        ]
        for (short, explicit) in pairs {
            let actual = try WorldCommandParser.parse(short)
            let expected = try WorldCommandParser.parse(explicit)
            precondition(String(reflecting: actual) == String(reflecting: expected), "default differs: \(short)")
        }
        let state = "'String'\"kind\"=\"A B\""
        let template = "'String'\"id\"=\"Chest\""
        guard case .setBlock(_, _, let storages, let spec) = try WorldCommandParser.parse("setblock 0 0 64 0 minecraft:stone " + state + " " + template),
              storages.count == 1, storages[0].states.first?.name == "kind", case .template = spec else {
            preconditionFailure("states and block entity NBT boundary")
        }
        guard case .setBlock(_, _, let statesOnly, .preserve) = try WorldCommandParser.parse("setblock 0 0 64 0 minecraft:stone " + state),
              statesOnly.count == 1, statesOnly[0].states.count == 1 else { preconditionFailure("first NBT belongs to states") }
        let blocks = Array(repeating: "minecraft:air", count: 255).joined(separator: " ")
        guard case .setBlock(_, _, let maximum, .preserve) = try WorldCommandParser.parse("setblock 0 0 64 0 " + blocks),
              maximum.count == 255 else { preconditionFailure("255 omitted states") }
        try reject("setblock 0 0 64 0 " + blocks + " minecraft:air")
        for text in [
            "dimension extra",
            "chunk query 0 1",
            "structure query extra",
            "time query daytime extra",
            "time add",
            "weather query extra",
            "weather clear 1 extra",
            "weather rain 1 1 1 extra",
            "weather rain NULL",
            "tickingarea delete",
            "tickingarea query ALL extra",
            "tickingarea add square 0 0 0 1 1",
            "give @s",
            "give @s minecraft:stone NULL",
            "give @s Auto minecraft:stone 1 NULL extra",
            "give @s 36 minecraft:stone",
            "give @s minecraft:stone 0",
            "kill",
            "kill 0 0 0 1 1 1",
            "kill @a 2",
            "effect give @s",
            "effect give @s freezing NULL",
            "effect clear @s ALL extra",
            "effect clear @s all",
            "summon minecraft:pig 0 0 64",
            "summon minecraft:pig 0 0 64 0 42",
            "summon minecraft:pig 0 0 64 0 NULL",
            "setblock 0 0 64 0",
            "setblock 0 0 64 0 minecraft:stone NULL NULL",
            "setblock 0 0 64 0 minecraft:stone empty minecraft:water",
            "storage set 0 0 64 0 minecraft:stone",
            "storage set 0 0 64 0 0 minecraft:stone NULL extra"
        ] { try reject(text) }
        guard case .tickingArea(.list(let dimension)) = try WorldCommandParser.parse("tickingarea list all", dimensionResolver: { _ in 7 }), dimension == 7 else {
            preconditionFailure("lowercase all dimension must retain its meaning")
        }
        guard case .tickingArea(.delete(let name)) = try WorldCommandParser.parse("tickingarea delete all"), name == "all" else {
            preconditionFailure("lowercase all name must not delete all areas")
        }
        let reads = ["help", "info", "dimension", "chunk", "structure", "time", "time query", "weather",
                     "tickingarea", "tickingarea list", "tickingarea query 0", "entity"]
        let writes = ["give @s minecraft:stone", "kill @a", "kill overworld 0 0 0 1 1 1",
                      "effect give @a freezing", "effect clear @s", "summon minecraft:pig overworld 0 64 0",
                      "setblock overworld 0 64 0 minecraft:stone", "fill 0 0 64 0 1 64 1 minecraft:stone",
                      "storage set 0 0 64 0 1 minecraft:water", "weather rain", "tickingarea add circle 0 0 0 1 Spawn"]
        for (commands, mayMutate) in [(reads, false), (writes, true)] {
            for text in commands {
                var errors = [String]()
                let plan = CliCommandPlan.parse([CliCommandLine(lineNumber: 1, text: text)], forExecution: true, error: { errors.append($0) })
                precondition(plan?.mayMutate == mayMutate && errors.isEmpty, "CLI syntax/default policy: \(text) \(errors)")
            }
        }
        var errors = [String]()
        let invalid = CliCommandPlan.parse([CliCommandLine(lineNumber: 1, text: "give @s minecraft:stone"),
                                           CliCommandLine(lineNumber: 2, text: "kill 0 0 0 1 1 1")],
                                          forExecution: true, error: { errors.append($0) })
        precondition(invalid == nil && errors.contains { $0.contains("第 2 行") }, "default parameters bypassed whole-script preflight")
        print("Command syntax regression passed: \(pairs.count) typed default equivalences, NBT boundaries, 255 layers and strict failures")
    }
    private static func reject(_ text: String) throws {
        var rejected = false
        do { _ = try WorldCommandParser.parse(text) } catch { rejected = true }
        precondition(rejected, "invalid syntax accepted: \(text)")
    }
}
