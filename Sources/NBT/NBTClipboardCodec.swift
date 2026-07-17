import Foundation

/// Binary payload used for copying more than one NBT tag through UIPasteboard.
///
/// Each document is encoded as an independent uncompressed Little Endian NBT
/// root so names and numeric types remain lossless. The UI writes this payload
/// and the legacy single-tag representation into the same pasteboard item.
enum NBTClipboardCodec {
    private static let magic = Data("BTNBTB1".utf8)

    static func encodeBatch(_ documents: [NBTDocument]) throws -> Data {
        guard !documents.isEmpty else {
            throw BlocktopographError.malformedData("没有可复制的 NBT 标签")
        }
        guard documents.count <= Int(UInt32.max) else {
            throw BlocktopographError.malformedData("复制的 NBT 标签数量过多")
        }

        let encoded = try documents.map {
            try BedrockNBTCodec.encode($0, encoding: .littleEndian)
        }
        var output = Data()
        output.append(magic)
        appendUInt32(UInt32(encoded.count), to: &output)
        for item in encoded {
            guard item.count <= Int(UInt32.max) else {
                throw BlocktopographError.malformedData("单个 NBT 标签过大，无法复制")
            }
            appendUInt32(UInt32(item.count), to: &output)
            output.append(item)
        }
        return output
    }

    static func decodeBatch(_ data: Data) throws -> [NBTDocument] {
        guard data.starts(with: magic) else {
            throw BlocktopographError.malformedData("不是 Blocktopograph 批量 NBT 剪贴板数据")
        }
        var offset = magic.count
        let count = try readUInt32(from: data, offset: &offset)
        var documents = [NBTDocument]()
        documents.reserveCapacity(Int(count))

        for _ in 0..<count {
            let length = try readUInt32(from: data, offset: &offset)
            guard offset + Int(length) <= data.count else {
                throw BlocktopographError.malformedData("批量 NBT 剪贴板数据长度无效")
            }
            let payload = data.subdata(in: offset..<(offset + Int(length)))
            offset += Int(length)
            documents.append(try BedrockNBTCodec.decode(payload, encoding: .littleEndian))
        }
        guard offset == data.count else {
            throw BlocktopographError.malformedData("批量 NBT 剪贴板包含多余数据")
        }
        guard !documents.isEmpty else {
            throw BlocktopographError.malformedData("批量 NBT 剪贴板中没有标签")
        }
        return documents
    }

    static func isBatchPayload(_ data: Data) -> Bool {
        data.starts(with: magic)
    }

    private static func appendUInt32(_ value: UInt32, to data: inout Data) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
    }

    private static func readUInt32(from data: Data, offset: inout Int) throws -> UInt32 {
        guard offset + 4 <= data.count else {
            throw BlocktopographError.malformedData("批量 NBT 剪贴板数据不完整")
        }
        let value = data[offset..<(offset + 4)].enumerated().reduce(UInt32(0)) { result, pair in
            result | (UInt32(pair.element) << UInt32(pair.offset * 8))
        }
        offset += 4
        return value
    }
}
