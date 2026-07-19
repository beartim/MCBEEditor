import Foundation

struct LevelDatFile {
    var version: UInt32
    var document: NBTDocument
}

final class WorldDocument {
    let rootURL: URL
    var levelDatURL: URL { rootURL.appendingPathComponent("level.dat") }
    var databaseURL: URL { rootURL.appendingPathComponent("db", isDirectory: true) }

    init(rootURL: URL) {
        self.rootURL = rootURL
    }

    func readLevelDat() throws -> LevelDatFile {
        let data = try Data(contentsOf: levelDatURL, options: .mappedIfSafe)
        guard data.count >= 8 else { throw MCBEEditorError.malformedData("level.dat 少于 8 字节") }
        let version = try data.littleEndianUInt32(at: 0)
        let declaredLength = Int(try data.littleEndianUInt32(at: 4))
        guard declaredLength >= 0, 8 + declaredLength <= data.count else {
            throw MCBEEditorError.malformedData("level.dat 声明长度越界")
        }
        let payload = data.subdata(in: 8..<(8 + declaredLength))
        let document = try BedrockNBTCodec.decode(payload, encoding: .littleEndian)
        return LevelDatFile(version: version, document: document)
    }

    func writeLevelDat(_ file: LevelDatFile) throws {
        let payload = try BedrockNBTCodec.encode(file.document, encoding: .littleEndian)
        guard payload.count <= Int(UInt32.max) else { throw MCBEEditorError.malformedData("level.dat 过大") }
        var output = Data()
        output.appendLE(file.version)
        output.appendLE(UInt32(payload.count))
        output.append(payload)
        try AtomicFile.write(output, to: levelDatURL)
    }

    func openDatabase(readOnly: Bool = true) throws -> MojangLevelDB {
        try MojangLevelDB(path: databaseURL, readOnly: readOnly)
    }
}
