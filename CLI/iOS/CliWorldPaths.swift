import Foundation

struct CliWorldPaths {
    let source: URL
    let cache: URL
    let output: URL?
    let isDirectory: Bool

    static func canonical(_ path: String) -> URL {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
    }
    static func same(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.path.precomposedStringWithCanonicalMapping.lowercased() == rhs.path.precomposedStringWithCanonicalMapping.lowercased()
    }
    static func sameOrInside(_ candidate: URL, _ directory: URL) -> Bool {
        let directoryPath = directory.path.precomposedStringWithCanonicalMapping.lowercased()
        let root = directoryPath == "/" ? "/" : directoryPath + "/"
        return same(candidate, directory) || candidate.path.lowercased().hasPrefix(root.lowercased())
    }

    static func validate(_ options: CliRunOptions) throws -> CliWorldPaths {
        let manager = FileManager.default
        let source = canonical(options.world), cache = canonical(options.cache)
        let output = options.output.map(canonical)
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: source.path, isDirectory: &isDirectory) else {
            throw CliError.file("找不到世界来源：\(source.path)")
        }
        if isDirectory.boolValue {
            if sameOrInside(cache, source) { throw CliError.input("缓存目录不能等于源世界目录或位于其内部。") }
        } else if !["mcworld", "zip"].contains(source.pathExtension.lowercased()) {
            throw CliError.input("输入需要世界文件夹、.mcworld 或 ZIP 世界文件。")
        }
        if options.inPlace {
            if !isDirectory.boolValue && source.pathExtension.lowercased() != "mcworld" {
                throw CliError.input("原位更新支持世界文件夹或 .mcworld；ZIP 输入请用 --output 另存为。")
            }
            if source.path == "/" { throw CliError.input("不能原位替换文件系统根目录。") }
            if let script = options.script, script != "-", same(source, canonical(script)) {
                throw CliError.input("原位更新不能覆盖输入命令文件。")
            }
        }
        if let output = output {
            if output.pathExtension.lowercased() != "mcworld" { throw CliError.input("输出文件必须使用 .mcworld 扩展名。") }
            var targetIsDirectory: ObjCBool = false
            let exists = manager.fileExists(atPath: output.path, isDirectory: &targetIsDirectory)
            if targetIsDirectory.boolValue { throw CliError.input("输出路径指向文件夹，请指定 .mcworld 文件。") }
            if sameOrInside(output, cache) { throw CliError.input("输出文件不能位于工作副本缓存目录内。") }
            if same(output, source) || (isDirectory.boolValue && sameOrInside(output, source)) {
                throw CliError.input("另存为不能覆盖源世界；原位更新请使用 --in-place。")
            }
            if let script = options.script, script != "-", same(output, canonical(script)) {
                throw CliError.input("输出不能覆盖输入命令文件。")
            }
            if exists && !options.overwrite { throw CliError.input("输出文件已存在；另选文件名或显式使用 --overwrite。") }
        }
        return CliWorldPaths(source: source, cache: cache, output: output, isDirectory: isDirectory.boolValue)
    }
}
