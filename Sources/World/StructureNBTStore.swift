import Foundation

struct StructureNBTRecord: Hashable {
    let key: Data
    let keyText: String
    let displayName: String
    let document: NBTDocument?
    let rawData: Data
    let encoding: NBTEncoding?
    let decodeError: String?

    static func == (lhs: StructureNBTRecord, rhs: StructureNBTRecord) -> Bool { lhs.key == rhs.key }
    func hash(into hasher: inout Hasher) { hasher.combine(key) }

    var sizeDescription: String? {
        guard let document = document,
              let values = Self.integerVector(named: "size", in: document.root),
              values.count >= 3 else { return nil }
        return "\(values[0])×\(values[1])×\(values[2])"
    }

    var originDescription: String? {
        guard let document = document,
              let values = Self.integerVector(named: "structure_world_origin", in: document.root),
              values.count >= 3 else { return nil }
        return "(\(values[0]), \(values[1]), \(values[2]))"
    }

    var formatVersion: Int32? { document?.root.intValue(named: "format_version") }

    var detailDescription: String {
        var parts = [String]()
        if let sizeDescription = sizeDescription { parts.append("尺寸 \(sizeDescription)") }
        if let originDescription = originDescription { parts.append("原点 \(originDescription)") }
        if let formatVersion = formatVersion { parts.append("格式 \(formatVersion)") }
        parts.append(ByteCountFormatter.string(fromByteCount: Int64(rawData.count), countStyle: .file))
        if document == nil { parts.insert("NBT 无法解析", at: 0) }
        return parts.joined(separator: " · ")
    }

    private static func integerVector(named name: String, in root: NBTValue) -> [Int64]? {
        guard let value = root.compoundValue(named: name) else { return nil }
        switch value {
        case .intArray(let values): return values.map(Int64.init)
        case .longArray(let values): return values
        case .list(_, let values):
            let converted = values.compactMap { value -> Int64? in
                switch value {
                case .byte(let number): return Int64(number)
                case .short(let number): return Int64(number)
                case .int(let number): return Int64(number)
                case .long(let number): return number
                default: return nil
                }
            }
            return converted.count == values.count ? converted : nil
        default:
            return nil
        }
    }
}

final class StructureNBTStore {
    static let keyPrefix = "structuretemplate"

    private let session: WorldSession

    init(session: WorldSession) {
        self.session = session
    }

    func records() throws -> [StructureNBTRecord] {
        let database = try session.database()
        let entries = try database.entries(
            prefix: Data(Self.keyPrefix.utf8),
            includeValues: true,
            limit: 0
        )

        return entries.compactMap { entry in
            guard let rawData = entry.value else { return nil }
            let keyText = String(data: entry.key, encoding: .utf8) ?? "0x\(entry.key.hexString)"
            let decoded = decode(rawData)
            return StructureNBTRecord(
                key: entry.key,
                keyText: keyText,
                displayName: displayName(for: keyText, document: decoded.document),
                document: decoded.document,
                rawData: rawData,
                encoding: decoded.encoding,
                decodeError: decoded.error
            )
        }.sorted { lhs, rhs in
            let order = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
            if order != .orderedSame { return order == .orderedAscending }
            return lhs.keyText < rhs.keyText
        }
    }

    func save(record: StructureNBTRecord, document: NBTDocument) throws {
        guard let encoding = record.encoding else {
            throw MCBEEditorError.unsupported("无法确定该结构记录的 NBT 编码，不能安全写回。")
        }
        let encoded = try BedrockNBTCodec.encode(document, encoding: encoding)
        try session.database().put(encoded, for: record.key, sync: true)
    }

    func containsStructure(named name: String) throws -> Bool {
        try session.database().get(key(forStructureName: name)) != nil
    }

    func record(named name: String) throws -> StructureNBTRecord? {
        let target = try key(forStructureName: name)
        return try records().first(where: { $0.key == target })
    }

    func save(document: NBTDocument, named name: String, overwrite: Bool = true) throws {
        let key = try key(forStructureName: name)
        let database = try session.database()
        if !overwrite, try database.get(key) != nil {
            throw MCBEEditorError.malformedData("已存在同名结构：\(normalizedStructureName(name))")
        }
        let normalized = try JavaStructureConverter.convertIfNeeded(document).document
        let encoded = try BedrockNBTCodec.encode(normalized, encoding: .littleEndian)
        try database.put(encoded, for: key, sync: true)
        guard try database.get(key) == encoded else {
            throw MCBEEditorError.malformedData("结构写入后未能从 LevelDB 读回")
        }
    }

    @discardableResult
    func delete(named name: String) throws -> Bool {
        let key = try key(forStructureName: name)
        let database = try session.database()
        guard try database.get(key) != nil else { return false }
        try database.delete(key, sync: true)
        return true
    }

    @discardableResult
    func deleteAll() throws -> Int {
        let entries = try session.database().entries(
            prefix: Data(Self.keyPrefix.utf8),
            includeValues: false,
            limit: 0
        )
        guard !entries.isEmpty else { return 0 }
        try session.database().applyBatch(puts: [], deletes: entries.map(\.key), sync: true)
        return entries.count
    }

    func isSameStructure(_ record: StructureNBTRecord, named name: String) -> Bool {
        guard let target = try? key(forStructureName: name) else { return false }
        return target == record.key
    }

    /// Imports standard NBT in the same formats recognized by prismarine-nbt:
    /// Big Endian, Little Endian, Little Endian VarInt, plus gzip/zlib wrapped data.
    /// Java structure NBT is semantically converted into the Bedrock mcstructure schema;
    /// existing mcstructure data is normalized to uncompressed Little Endian.
    @discardableResult
    func importStructure(data: Data, named name: String, overwrite: Bool) throws -> StructureImportResult {
        let decoded = decode(data)
        guard let document = decoded.document else {
            throw MCBEEditorError.malformedData(
                "文件不是可识别的 NBT／mcstructure（支持 Big Endian、Little Endian、Little Endian VarInt、GZip 和 Zlib）：\(decoded.error ?? "未知 NBT 编码")"
            )
        }
        let conversion = try JavaStructureConverter.convertIfNeeded(document)
        let converted = try BedrockNBTCodec.encode(conversion.document, encoding: .littleEndian)
        let key = try key(forStructureName: name)
        let database = try session.database()
        if !overwrite, try database.get(key) != nil {
            throw MCBEEditorError.malformedData("已存在同名结构：\(normalizedStructureName(name))")
        }
        try database.put(converted, for: key, sync: true)
        return conversion.result
    }

    func rename(record: StructureNBTRecord, to name: String, overwrite: Bool) throws {
        let targetKey = try key(forStructureName: name)
        guard targetKey != record.key else { return }
        let database = try session.database()
        if !overwrite, try database.get(targetKey) != nil {
            throw MCBEEditorError.malformedData("已存在同名结构：\(normalizedStructureName(name))")
        }
        try database.applyBatch(
            puts: [(key: targetKey, value: record.rawData)],
            deletes: [record.key],
            sync: true
        )
    }

    func delete(record: StructureNBTRecord) throws {
        try session.database().delete(record.key, sync: true)
    }

    func normalizedStructureName(_ name: String) -> String {
        var clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix(Self.keyPrefix) {
            clean.removeFirst(Self.keyPrefix.count)
            while clean.first == "_" || clean.first == ":" || clean.first == "/" {
                clean.removeFirst()
            }
        }
        return clean
    }

    private func key(forStructureName name: String) throws -> Data {
        let clean = normalizedStructureName(name)
        guard !clean.isEmpty else {
            throw MCBEEditorError.malformedData("结构名称不能为空")
        }
        guard !clean.contains("\n"), !clean.contains("\r"), !clean.contains("\0") else {
            throw MCBEEditorError.malformedData("结构名称包含无效字符")
        }
        return Data("\(Self.keyPrefix)_\(clean)".utf8)
    }

    private func decode(_ originalData: Data) -> (document: NBTDocument?, encoding: NBTEncoding?, error: String?) {
        var payloads = [(label: "未压缩", data: originalData)]
        var decompressionError: String?

        // prismarine-nbt transparently accepts compressed NBT. zlib's auto-wrapper mode
        // handles both the gzip and zlib containers used by common structure tools.
        do {
            let expected = UInt(max(originalData.count * 4, 64 * 1024))
            let inflated = try BTCompressionBridge.inflateWrapped(originalData, expectedSize: expected)
            if !inflated.isEmpty, inflated != originalData {
                payloads.insert((label: "GZip/Zlib", data: inflated), at: 0)
            }
        } catch {
            decompressionError = error.localizedDescription
        }

        var failures = [String]()
        for payload in payloads {
            // Match prismarine-nbt's supported formats and detection order.
            for encoding in [NBTEncoding.bigEndian, .littleEndian, .littleEndianVarInt] {
                do {
                    let document = try decodeExactly(payload.data, encoding: encoding)
                    return (document, encoding, nil)
                } catch {
                    failures.append("\(payload.label) \(description(of: encoding)): \(error.localizedDescription)")
                }
            }
        }
        if let decompressionError = decompressionError {
            failures.append("GZip/Zlib: \(decompressionError)")
        }
        return (nil, nil, failures.joined(separator: "; "))
    }

    private func decodeExactly(_ data: Data, encoding: NBTEncoding) throws -> NBTDocument {
        var cursor = BinaryCursor(data: data)
        let document = try BedrockNBTCodec.decodeDocument(cursor: &cursor, encoding: encoding, maximumDepth: 256)
        // Permit padding zeroes emitted by a few editors, but reject arbitrary trailing bytes
        // so a wrong endian mode cannot be accepted accidentally.
        while !cursor.isAtEnd {
            guard try cursor.readByte() == 0 else {
                throw MCBEEditorError.malformedData("NBT 根标签后存在非零尾随数据")
            }
        }
        return document
    }

    private func description(of encoding: NBTEncoding) -> String {
        switch encoding {
        case .bigEndian: return "Big Endian"
        case .littleEndian: return "Little Endian"
        case .littleEndianVarInt: return "Little Endian VarInt"
        }
    }

    private func displayName(for keyText: String, document: NBTDocument?) -> String {
        var suffix = keyText
        if suffix.hasPrefix(Self.keyPrefix) {
            suffix.removeFirst(Self.keyPrefix.count)
        }
        while suffix.first == "_" || suffix.first == ":" || suffix.first == "/" {
            suffix.removeFirst()
        }
        if !suffix.isEmpty { return suffix }
        if let rootName = document?.rootName.trimmingCharacters(in: .whitespacesAndNewlines), !rootName.isEmpty {
            return rootName
        }
        return "未命名结构"
    }
}
