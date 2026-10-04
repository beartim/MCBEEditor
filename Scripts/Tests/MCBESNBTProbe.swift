import Foundation

@main
struct MCBESNBTProbe {
    static func main() {
        do {
            try run()
        } catch {
            FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
            exit(1)
        }
    }

    private static func run() throws {
        let args = CommandLine.arguments
        guard args.count == 4 else { throw MCBEEditorError.malformedData("usage: probe decode|encode input output") }
        let input = try Data(contentsOf: URL(fileURLWithPath: args[2]))
        let output: Data
        if args[1] == "decode" {
            var binary = Data()
            for document in try MCBESNBTCodec.decode(input) { binary.append(try BedrockNBTCodec.encode(document, encoding: .littleEndian)) }
            output = binary
        } else if args[1] == "encode" {
            var cursor = BinaryCursor(data: input)
            var documents = [NBTDocument]()
            while !cursor.isAtEnd { documents.append(try BedrockNBTCodec.decodeDocument(cursor: &cursor, encoding: .littleEndian, maximumDepth: 256)) }
            output = try MCBESNBTCodec.encode(documents)
        } else { throw MCBEEditorError.malformedData("unknown operation") }
        try output.write(to: URL(fileURLWithPath: args[3]))
    }
}
