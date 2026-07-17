import Foundation

final class StandaloneNBTFile {
    enum StorageKind: Equatable {
        case single
        case consecutive
    }

    let originalFilename: String
    let originalExtension: String
    let originalEncoding: NBTEncoding
    let originalWasJSON: Bool
    var storageKind: StorageKind { documents.count == 1 ? .single : .consecutive }
    let wasCompressed: Bool
    var documents: [NBTDocument]
    var dirty = false

    init(
        originalFilename: String,
        originalExtension: String,
        originalEncoding: NBTEncoding,
        originalWasJSON: Bool = false,
        storageKind _: StorageKind,
        wasCompressed: Bool,
        documents: [NBTDocument]
    ) {
        self.originalFilename = originalFilename
        self.originalExtension = originalExtension
        self.originalEncoding = originalEncoding
        self.originalWasJSON = originalWasJSON
        self.wasCompressed = wasCompressed
        self.documents = documents
    }

    var formatDescription: String {
        let layout = storageKind == .single ? "单根 NBT" : "连续 NBT（\(documents.count) 个根标签）"
        if originalWasJSON { return "\(layout) · JSON NBT" }
        let compression = wasCompressed ? " · 原文件为 GZip/Zlib" : ""
        return "\(layout) · \(Self.description(of: originalEncoding))\(compression)"
    }

    static func description(of encoding: NBTEncoding) -> String {
        switch encoding {
        case .bigEndian: return "Big Endian"
        case .littleEndian: return "Little Endian"
        case .littleEndianVarInt: return "Little Endian VarInt"
        }
    }
}

enum StandaloneNBTFileCodec {
    struct DecodedPayload {
        let documents: [NBTDocument]
        let encoding: NBTEncoding
        let wasCompressed: Bool
    }

    static func decode(data originalData: Data, filename: String) throws -> StandaloneNBTFile {
        guard !originalData.isEmpty else {
            throw BlocktopographError.malformedData("NBT/JSON 文件为空")
        }

        let ext = URL(fileURLWithPath: filename).pathExtension.lowercased()
        let firstNonWhitespace = originalData.first { byte in
            byte != 0x20 && byte != 0x09 && byte != 0x0A && byte != 0x0D
        }
        if ext == "json" || firstNonWhitespace == 0x7B || firstNonWhitespace == 0x5B {
            do {
                let documents = try NBTJSONCodec.decode(originalData)
                return StandaloneNBTFile(
                    originalFilename: filename,
                    originalExtension: ext,
                    originalEncoding: .littleEndian,
                    originalWasJSON: true,
                    storageKind: documents.count == 1 ? .single : .consecutive,
                    wasCompressed: false,
                    documents: documents
                )
            } catch where ext == "json" {
                throw error
            } catch {
                // A binary NBT file can start with a byte that resembles JSON; continue binary detection.
            }
        }

        var payloads = [(data: originalData, compressed: false)]
        if let inflated = try? BTCompressionBridge.inflateWrapped(
            originalData,
            expectedSize: UInt(max(originalData.count * 4, 64 * 1024))
        ), !inflated.isEmpty, inflated != originalData {
            payloads.insert((data: inflated, compressed: true), at: 0)
        }

        var failures = [String]()
        for payload in payloads {
            for encoding in preferredEncodings(for: filename) {
                do {
                    let documents = try decodeEveryRoot(payload.data, encoding: encoding)
                    guard !documents.isEmpty else {
                        throw BlocktopographError.malformedData("没有发现 NBT 根标签")
                    }
                    return StandaloneNBTFile(
                        originalFilename: filename,
                        originalExtension: URL(fileURLWithPath: filename).pathExtension.lowercased(),
                        originalEncoding: encoding,
                        originalWasJSON: false,
                        storageKind: documents.count == 1 ? .single : .consecutive,
                        wasCompressed: payload.compressed,
                        documents: documents
                    )
                } catch {
                    let compression = payload.compressed ? "GZip/Zlib" : "未压缩"
                    failures.append("\(compression) \(StandaloneNBTFile.description(of: encoding))：\(error.localizedDescription)")
                }
            }
        }
        throw BlocktopographError.malformedData(
            "无法识别该文件。支持 JSON NBT、Big Endian、Little Endian、Little Endian VarInt、连续多根 NBT 以及 GZip/Zlib。\n" + failures.prefix(6).joined(separator: "\n")
        )
    }

    static func encodeJSON(_ documents: [NBTDocument]) throws -> Data {
        try NBTJSONCodec.encode(documents)
    }

    static func encode(_ documents: [NBTDocument], encoding: NBTEncoding) throws -> Data {
        guard !documents.isEmpty else {
            throw BlocktopographError.malformedData("没有可导出的 NBT 根标签")
        }
        var output = Data()
        for document in documents {
            output.append(try BedrockNBTCodec.encode(document, encoding: encoding))
        }
        return output
    }

    static func encodeAsMCStructure(_ documents: [NBTDocument]) throws -> (data: Data, result: StructureImportResult) {
        guard documents.count == 1, let document = documents.first else {
            throw BlocktopographError.unsupported("只有单根 Java 结构 NBT 或 Bedrock mcstructure 可以转换为 mcstructure。连续 NBT 文件不能整体转换为结构。")
        }
        let conversion = try JavaStructureConverter.convertIfNeeded(document)
        return (
            try BedrockNBTCodec.encode(conversion.document, encoding: .littleEndian),
            conversion.result
        )
    }

    private static func preferredEncodings(for filename: String) -> [NBTEncoding] {
        let ext = URL(fileURLWithPath: filename).pathExtension.lowercased()
        if ext == "mcstructure" { return [.littleEndian, .littleEndianVarInt, .bigEndian] }
        return [.bigEndian, .littleEndian, .littleEndianVarInt]
    }

    private static func decodeEveryRoot(_ data: Data, encoding: NBTEncoding) throws -> [NBTDocument] {
        var cursor = BinaryCursor(data: data)
        var documents = [NBTDocument]()
        documents.reserveCapacity(encoding == .littleEndianVarInt ? 1024 : 1)

        while !cursor.isAtEnd {
            if data[cursor.offset] == 0 {
                let tail = data[cursor.offset..<data.count]
                if tail.allSatisfy({ $0 == 0 }) { break }
                throw BlocktopographError.malformedData("偏移 \(cursor.offset) 处不是有效的 NBT 根标签")
            }
            let before = cursor.offset
            let document = try BedrockNBTCodec.decodeDocument(
                cursor: &cursor,
                encoding: encoding,
                maximumDepth: 256
            )
            guard cursor.offset > before else {
                throw BlocktopographError.malformedData("NBT 解析器在偏移 \(before) 没有前进")
            }
            documents.append(document)
            if documents.count > 2_000_000 {
                throw BlocktopographError.malformedData("连续 NBT 根标签数量超过安全上限")
            }
        }
        return documents
    }
}
