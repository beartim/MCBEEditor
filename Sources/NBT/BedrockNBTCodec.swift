import Foundation

enum BedrockNBTCodec {
    static func decode(_ data: Data, encoding: NBTEncoding = .littleEndian, maximumDepth: Int = 256) throws -> NBTDocument {
        var cursor = BinaryCursor(data: data)
        let document = try decodeDocument(cursor: &cursor, encoding: encoding, maximumDepth: maximumDepth)
        return document
    }

    static func decodeDocument(cursor: inout BinaryCursor, encoding: NBTEncoding = .littleEndian, maximumDepth: Int = 256) throws -> NBTDocument {
        let rawType = try cursor.readByte()
        guard let type = NBTTagType(rawValue: rawType), type != .end else {
            throw BlocktopographError.malformedData("NBT 根标签类型无效：\(rawType)")
        }
        let name = try readString(cursor: &cursor, encoding: encoding)
        let value = try readPayload(type: type, cursor: &cursor, encoding: encoding, depth: 0, maximumDepth: maximumDepth)
        return NBTDocument(rootName: name, root: value)
    }

    static func encode(_ document: NBTDocument, encoding: NBTEncoding = .littleEndian) throws -> Data {
        var writer = BinaryWriter()
        writer.writeByte(document.root.type.rawValue)
        try writeString(document.rootName, writer: &writer, encoding: encoding)
        try writePayload(document.root, writer: &writer, encoding: encoding)
        return writer.data
    }

    private static func readPayload(type: NBTTagType, cursor: inout BinaryCursor, encoding: NBTEncoding, depth: Int, maximumDepth: Int) throws -> NBTValue {
        guard depth <= maximumDepth else { throw BlocktopographError.malformedData("NBT 嵌套超过 \(maximumDepth) 层") }
        switch type {
        case .end:
            throw BlocktopographError.malformedData("End 标签不能作为值")
        case .byte:
            return .byte(Int8(bitPattern: try cursor.readByte()))
        case .short:
            return .short(encoding == .bigEndian ? try cursor.readInt16BE() : try cursor.readInt16LE())
        case .int:
            switch encoding {
            case .bigEndian: return .int(try cursor.readInt32BE())
            case .littleEndian: return .int(try cursor.readInt32LE())
            case .littleEndianVarInt: return .int(try cursor.readSignedVarInt32())
            }
        case .long:
            switch encoding {
            case .bigEndian: return .long(try cursor.readInt64BE())
            case .littleEndian: return .long(try cursor.readInt64LE())
            case .littleEndianVarInt: return .long(try cursor.readSignedVarInt64())
            }
        case .float:
            return .float(encoding == .bigEndian ? try cursor.readFloatBE() : try cursor.readFloatLE())
        case .double:
            return .double(encoding == .bigEndian ? try cursor.readDoubleBE() : try cursor.readDoubleLE())
        case .byteArray:
            let count = try readLength(cursor: &cursor, encoding: encoding)
            return .byteArray(try cursor.readData(count: count))
        case .string:
            return .string(try readString(cursor: &cursor, encoding: encoding))
        case .list:
            let elementRaw = try cursor.readByte()
            guard let elementType = NBTTagType(rawValue: elementRaw) else {
                throw BlocktopographError.malformedData("NBT List 元素类型无效：\(elementRaw)")
            }
            let count = try readLength(cursor: &cursor, encoding: encoding)
            if count > 0 && elementType == .end {
                throw BlocktopographError.malformedData("非空 List 不能使用 End 元素类型")
            }
            var values = [NBTValue]()
            values.reserveCapacity(count)
            for _ in 0..<count {
                values.append(try readPayload(type: elementType, cursor: &cursor, encoding: encoding, depth: depth + 1, maximumDepth: maximumDepth))
            }
            return .list(elementType, values)
        case .compound:
            var tags = [NBTNamedTag]()
            while true {
                let raw = try cursor.readByte()
                guard let childType = NBTTagType(rawValue: raw) else {
                    throw BlocktopographError.malformedData("Compound 子标签类型无效：\(raw)")
                }
                if childType == .end { break }
                let name = try readString(cursor: &cursor, encoding: encoding)
                let value = try readPayload(type: childType, cursor: &cursor, encoding: encoding, depth: depth + 1, maximumDepth: maximumDepth)
                tags.append(NBTNamedTag(name: name, value: value))
            }
            return .compound(tags)
        case .intArray:
            let count = try readLength(cursor: &cursor, encoding: encoding)
            var values = [Int32]()
            values.reserveCapacity(count)
            for _ in 0..<count {
                switch encoding {
                case .bigEndian: values.append(try cursor.readInt32BE())
                case .littleEndian: values.append(try cursor.readInt32LE())
                case .littleEndianVarInt: values.append(try cursor.readSignedVarInt32())
                }
            }
            return .intArray(values)
        case .longArray:
            let count = try readLength(cursor: &cursor, encoding: encoding)
            var values = [Int64]()
            values.reserveCapacity(count)
            for _ in 0..<count {
                switch encoding {
                case .bigEndian: values.append(try cursor.readInt64BE())
                case .littleEndian: values.append(try cursor.readInt64LE())
                case .littleEndianVarInt: values.append(try cursor.readSignedVarInt64())
                }
            }
            return .longArray(values)
        }
    }

    private static func writePayload(_ value: NBTValue, writer: inout BinaryWriter, encoding: NBTEncoding) throws {
        switch value {
        case .byte(let number):
            writer.writeByte(UInt8(bitPattern: number))
        case .short(let number):
            if encoding == .bigEndian { writer.writeInt16BE(number) } else { writer.writeInt16LE(number) }
        case .int(let number):
            switch encoding {
            case .bigEndian: writer.writeInt32BE(number)
            case .littleEndian: writer.writeInt32LE(number)
            case .littleEndianVarInt: writer.writeSignedVarInt(number)
            }
        case .long(let number):
            switch encoding {
            case .bigEndian: writer.writeInt64BE(number)
            case .littleEndian: writer.writeInt64LE(number)
            case .littleEndianVarInt: writer.writeSignedVarLong(number)
            }
        case .float(let number):
            if encoding == .bigEndian { writer.writeFloatBE(number) } else { writer.writeFloatLE(number) }
        case .double(let number):
            if encoding == .bigEndian { writer.writeDoubleBE(number) } else { writer.writeDoubleLE(number) }
        case .byteArray(let bytes):
            try writeLength(bytes.count, writer: &writer, encoding: encoding)
            writer.writeData(bytes)
        case .string(let text):
            try writeString(text, writer: &writer, encoding: encoding)
        case .list(let elementType, let values):
            guard values.allSatisfy({ $0.type == elementType }) else {
                throw BlocktopographError.malformedData("NBT List 中存在不同类型元素")
            }
            writer.writeByte(elementType.rawValue)
            try writeLength(values.count, writer: &writer, encoding: encoding)
            for child in values { try writePayload(child, writer: &writer, encoding: encoding) }
        case .compound(let tags):
            for tag in tags {
                writer.writeByte(tag.value.type.rawValue)
                try writeString(tag.name, writer: &writer, encoding: encoding)
                try writePayload(tag.value, writer: &writer, encoding: encoding)
            }
            writer.writeByte(NBTTagType.end.rawValue)
        case .intArray(let values):
            try writeLength(values.count, writer: &writer, encoding: encoding)
            for number in values {
                switch encoding {
                case .bigEndian: writer.writeInt32BE(number)
                case .littleEndian: writer.writeInt32LE(number)
                case .littleEndianVarInt: writer.writeSignedVarInt(number)
                }
            }
        case .longArray(let values):
            try writeLength(values.count, writer: &writer, encoding: encoding)
            for number in values {
                switch encoding {
                case .bigEndian: writer.writeInt64BE(number)
                case .littleEndian: writer.writeInt64LE(number)
                case .littleEndianVarInt: writer.writeSignedVarLong(number)
                }
            }
        }
    }

    private static func readLength(cursor: inout BinaryCursor, encoding: NBTEncoding) throws -> Int {
        let raw: Int64
        switch encoding {
        case .bigEndian: raw = Int64(try cursor.readInt32BE())
        case .littleEndian: raw = Int64(try cursor.readInt32LE())
        case .littleEndianVarInt: raw = Int64(try cursor.readSignedVarInt32())
        }
        guard raw >= 0, raw <= Int64(Int.max), raw <= 100_000_000 else {
            throw BlocktopographError.malformedData("NBT 长度无效：\(raw)")
        }
        return Int(raw)
    }

    private static func writeLength(_ count: Int, writer: inout BinaryWriter, encoding: NBTEncoding) throws {
        guard count >= 0, count <= Int(Int32.max) else {
            throw BlocktopographError.malformedData("NBT 长度无法编码：\(count)")
        }
        switch encoding {
        case .bigEndian: writer.writeInt32BE(Int32(count))
        case .littleEndian: writer.writeInt32LE(Int32(count))
        case .littleEndianVarInt: writer.writeSignedVarInt(Int32(count))
        }
    }

    private static func readString(cursor: inout BinaryCursor, encoding: NBTEncoding) throws -> String {
        let length: Int
        switch encoding {
        case .bigEndian:
            length = Int(try cursor.readUInt16BE())
        case .littleEndian:
            length = Int(try cursor.readUInt16LE())
        case .littleEndianVarInt:
            let value = try cursor.readUnsignedVarInt(maxBytes: 5)
            guard value <= UInt64(Int.max), value <= 16_777_216 else {
                throw BlocktopographError.malformedData("NBT 字符串过长")
            }
            length = Int(value)
        }
        let data = try cursor.readData(count: length)
        guard let text = String(data: data, encoding: .utf8) else {
            throw BlocktopographError.malformedData("NBT 字符串不是 UTF-8")
        }
        return text
    }

    private static func writeString(_ value: String, writer: inout BinaryWriter, encoding: NBTEncoding) throws {
        guard let data = value.data(using: .utf8) else {
            throw BlocktopographError.malformedData("字符串无法编码为 UTF-8")
        }
        switch encoding {
        case .bigEndian:
            guard data.count <= Int(UInt16.max) else { throw BlocktopographError.malformedData("NBT 字符串超过 65535 字节") }
            writer.writeUInt16BE(UInt16(data.count))
        case .littleEndian:
            guard data.count <= Int(UInt16.max) else { throw BlocktopographError.malformedData("NBT 字符串超过 65535 字节") }
            writer.writeUInt16LE(UInt16(data.count))
        case .littleEndianVarInt:
            writer.writeUnsignedVarInt(UInt64(data.count))
        }
        writer.writeData(data)
    }
}
