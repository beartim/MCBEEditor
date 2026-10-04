// Validation-only Linux adapters. The converter and all NBT/structure codecs
// are compiled unchanged from production source. This is not an Apple build.
import Foundation
import Glibc

@_silgen_name("snbt_test_inflate")
func inflateForTest(_ input: UnsafePointer<UInt8>?, _ length: Int,
    _ output: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>, _ size: UnsafeMutablePointer<Int>) -> Int32

enum BTCompressionBridge {
    static func inflateWrapped(_ data: Data, expectedSize: UInt) throws -> Data {
        var output: UnsafeMutablePointer<UInt8>?
        var size = 0
        let code = data.withUnsafeBytes { raw in
            inflateForTest(raw.bindMemory(to: UInt8.self).baseAddress, data.count, &output, &size)
        }
        guard code == 0, let buffer = output else { throw MCBEEditorError.malformedData("Invalid compressed data") }
        defer { free(buffer) }
        return Data(bytes: buffer, count: size)
    }
}
enum CliError: LocalizedError {
    case input(String), file(String)
    var errorDescription: String? { switch self { case .input(let text), .file(let text): return text } }
}
enum CliWorldPaths {
    static func canonical(_ path: String) -> URL { URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath() }
}
enum CliFileSystem {
    static func isDirectory(_ url: URL) -> Bool {
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) && directory.boolValue
    }
    static func publishFile(_ temporary: URL, to destination: URL, overwrite: Bool) throws {
        let result = temporary.path.withCString { source in
            destination.path.withCString { target in overwrite ? rename(source, target) : link(source, target) }
        }
        guard result == 0 else { throw CliError.file(String(cString: strerror(errno))) }
        if !overwrite { try FileManager.default.removeItem(at: temporary) }
    }
}
@main struct FormatConverterProbe {
    static func main() {
        do {
            let code = try CliFormatConverter.run(Array(CommandLine.arguments.dropFirst()), output: { print($0) })
            exit(code)
        } catch {
            FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
            if case CliError.input = error { exit(2) }
            exit(3)
        }
    }
}
