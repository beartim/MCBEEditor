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
                    let littleEndianError = error
                    do {
                        let fallback = try BedrockNBTCodec.decode(data, encoding: .littleEndianVarInt)
                        // `decode` intentionally permits trailing bytes. For a fallback
                        // codec that is dangerous: ordinary little-endian NBT beginning
                        // with 0A 00 00 can otherwise be misread as an empty VarInt
                        // Compound and silently turn a real actor into “未知实体”. Only
                        // accept the fallback when it round-trips the entire payload.
                        let reencoded = try BedrockNBTCodec.encode(fallback, encoding: .littleEndianVarInt)
                        let trailing = data.dropFirst(min(reencoded.count, data.count))
                        guard data.count >= reencoded.count,
                            data.prefix(reencoded.count) == reencoded,
                            trailing.allSatisfy({ $0 == 0 })
                        else { throw littleEndianError }
                        return [ConsecutiveNBTRecord(
                            document: fallback, rawData: data, encoding: .littleEndianVarInt
                        )]
                    } catch {
                        throw MCBEEditorError.malformedData(
                            "连续 NBT 在偏移 \(before) 解析失败：\(littleEndianError.localizedDescription)"
                        )
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
