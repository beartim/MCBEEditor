import Foundation

// Filesystem boundaries for the portable test target. Production CLI parser/plan
// code is linked; these preflight tests never publish a file.
enum CliError: LocalizedError {
    case input(String), file(String)
    var errorDescription: String? { switch self { case .input(let text), .file(let text): return text } }
}
struct CliWorldPaths {
    let source: URL, cache: URL
    let output: URL?
    let isDirectory: Bool
    static func canonical(_ path: String) -> URL { URL(fileURLWithPath: path).standardizedFileURL }
    static func same(_ left: URL, _ right: URL) -> Bool { left.standardizedFileURL == right.standardizedFileURL }
    static func sameOrInside(_ left: URL, _ right: URL) -> Bool { same(left, right) || left.path.hasPrefix(right.path + "/") }
}
enum CliFileSystem {
    static func isDirectory(_ url: URL) -> Bool {
        var flag = ObjCBool(false)
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &flag) && flag.boolValue
    }
    static func publishFile(_ temporary: URL, to destination: URL, overwrite: Bool) throws {
        preconditionFailure("portable preflight tests must not publish files")
    }
}

enum DimensionCliPreflightRegression {
    static func run() throws {
        let apostrophe = #"summon 'String'"identifier"="minecraft:pig",'List''Float'"Pos"="0,64,0",'Compound'"Extra"="{'String'"label"="O'Brien"}""#
        _ = try CliStructureFileCommand.parse(apostrophe)
        let db = MojangLevelDB(), store = DimensionStore(database: db)
        try store.add(name: "existing:name", id: 800)
        let before = db.values
        func plan(_ commands: [String], bound: Bool = true) throws -> CliCommandPlan? {
            let context = bound ? try DimensionCommandContext(database: db) : DimensionCommandContext()
            return CliCommandPlan.parse(commands.enumerated().map { CliCommandLine(lineNumber: $0.offset + 1, text: $0.element) },
                forExecution: bound, dimensionContext: context, error: { _ in })
        }
        guard let valid = try plan(["dimension add bear 1000", "getblock bear 0 64 0", "dimension query", "dimension purge bear"]),
              case .getBlock(let id, _) = valid.commands[1].command, id == 1000 else { preconditionFailure("CLI projected add") }
        for commands in [
            ["dimension add bear 1000", "dimension add bear 1001"],
            ["dimension add bear 1000", "dimension add cat 1000"],
            ["dimension purge existing:name", "getblock existing:name 0 0 0"],
            ["dimension add bear 1000", "getblock bear bad 0 0"], ["dimension empty missing"]
        ] {
            let failed = try plan(commands)
            precondition(failed == nil && db.values == before)
        }
        let reused = try plan(["dimension purge existing:name", "dimension add existing:name 800", "getblock existing:name 0 0 0"])
        guard case .getBlock(let reusedID, _)? = reused?.commands.last?.command, reusedID == 800 else { preconditionFailure("CLI purge/add reuse") }
        let syntax = try plan(["getblock unresolved:name 0 0 0"], bound: false)
        precondition(syntax != nil && db.values == before)
        print("Swift CLI dimension preflight passed: actual parser/plan, projected state and no writes")
    }
}
