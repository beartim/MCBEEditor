import Foundation

struct ConsecutiveNBTRecord {
    var document: NBTDocument
    var rawData: Data
    var encoding: NBTEncoding
}

enum ConsecutiveNBTCodec {
    static func decode(_ data: Data) throws -> [ConsecutiveNBTRecord] {
        guard !data.isEmpty else { return [] }

        var cursor = BinaryCursor(data: data)
        var records = [ConsecutiveNBTRecord]()
        while cursor.remaining > 0 {
            let remaining = data[cursor.offset..<data.count]
            if remaining.allSatisfy({ $0 == 0 }) { break }

            let before = cursor.offset
            do {
                let document = try BedrockNBTCodec.decodeDocument(cursor: &cursor, encoding: .littleEndian)
                records.append(ConsecutiveNBTRecord(
                    document: document,
                    rawData: data.subdata(in: before..<cursor.offset),
                    encoding: .littleEndian
                ))
            } catch {
                if records.isEmpty {
                    var fallbackCursor = BinaryCursor(data: data)
                    do {
                        let fallback = try BedrockNBTCodec.decodeDocument(
                            cursor: &fallbackCursor, encoding: .littleEndianVarInt)
                        let trailing = data[fallbackCursor.offset..<data.count]
                        guard trailing.allSatisfy({ $0 == 0 }) else {
                            throw MCBEEditorError.malformedData("VarInt NBT 后仍有未解析数据")
                        }
                        return [ConsecutiveNBTRecord(
                            document: fallback, rawData: data, encoding: .littleEndianVarInt)]
                    } catch {
                        throw MCBEEditorError.malformedData(
                            "NBT 既不是有效 Little Endian，也不是完整 VarInt：\(error.localizedDescription)")
                    }
                }
                throw MCBEEditorError.malformedData("连续 NBT 在偏移 \(before) 解析失败：\(error.localizedDescription)")
            }

            guard cursor.offset > before else {
                throw MCBEEditorError.malformedData("NBT 解析器没有前进")
            }
        }
        return records
    }

    static func encode(_ records: [ConsecutiveNBTRecord]) throws -> Data {
        var data = Data()
        for record in records {
            data.append(try BedrockNBTCodec.encode(record.document, encoding: record.encoding))
        }
        return data
    }
}
