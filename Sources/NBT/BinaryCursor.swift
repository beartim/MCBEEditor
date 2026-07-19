import Foundation

struct BinaryCursor {
    let data: Data
    private(set) var offset: Int = 0

    var remaining: Int { data.count - offset }
    var isAtEnd: Bool { offset >= data.count }

    mutating func readByte() throws -> UInt8 {
        guard offset < data.count else { throw MCBEEditorError.malformedData("读取字节越界") }
        defer { offset += 1 }
        return data[offset]
    }

    mutating func readData(count: Int) throws -> Data {
        guard count >= 0, offset + count <= data.count else {
            throw MCBEEditorError.malformedData("读取 \(count) 字节越界")
        }
        let result = data.subdata(in: offset..<(offset + count))
        offset += count
        return result
    }

    mutating func readUInt16LE() throws -> UInt16 {
        let a = UInt16(try readByte())
        let b = UInt16(try readByte())
        return a | (b << 8)
    }

    mutating func readInt16LE() throws -> Int16 {
        Int16(bitPattern: try readUInt16LE())
    }

    mutating func readUInt16BE() throws -> UInt16 {
        let a = UInt16(try readByte()) << 8
        let b = UInt16(try readByte())
        return a | b
    }

    mutating func readInt16BE() throws -> Int16 {
        Int16(bitPattern: try readUInt16BE())
    }

    mutating func readUInt32LE() throws -> UInt32 {
        let a = UInt32(try readByte())
        let b = UInt32(try readByte()) << 8
        let c = UInt32(try readByte()) << 16
        let d = UInt32(try readByte()) << 24
        return a | b | c | d
    }

    mutating func readInt32LE() throws -> Int32 {
        Int32(bitPattern: try readUInt32LE())
    }

    mutating func readUInt32BE() throws -> UInt32 {
        let a = UInt32(try readByte()) << 24
        let b = UInt32(try readByte()) << 16
        let c = UInt32(try readByte()) << 8
        let d = UInt32(try readByte())
        return a | b | c | d
    }

    mutating func readInt32BE() throws -> Int32 {
        Int32(bitPattern: try readUInt32BE())
    }

    mutating func readUInt64LE() throws -> UInt64 {
        let low = UInt64(try readUInt32LE())
        let high = UInt64(try readUInt32LE()) << 32
        return low | high
    }

    mutating func readInt64LE() throws -> Int64 {
        Int64(bitPattern: try readUInt64LE())
    }

    mutating func readFloatLE() throws -> Float {
        Float(bitPattern: try readUInt32LE())
    }

    mutating func readDoubleLE() throws -> Double {
        Double(bitPattern: try readUInt64LE())
    }

    mutating func readUInt64BE() throws -> UInt64 {
        let high = UInt64(try readUInt32BE()) << 32
        let low = UInt64(try readUInt32BE())
        return high | low
    }

    mutating func readInt64BE() throws -> Int64 {
        Int64(bitPattern: try readUInt64BE())
    }

    mutating func readFloatBE() throws -> Float {
        Float(bitPattern: try readUInt32BE())
    }

    mutating func readDoubleBE() throws -> Double {
        Double(bitPattern: try readUInt64BE())
    }

    mutating func readUnsignedVarInt(maxBytes: Int = 5) throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        for _ in 0..<maxBytes {
            let byte = try readByte()
            result |= UInt64(byte & 0x7f) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
        }
        throw MCBEEditorError.malformedData("VarInt 过长")
    }

    mutating func readSignedVarInt32() throws -> Int32 {
        let raw = UInt32(truncatingIfNeeded: try readUnsignedVarInt(maxBytes: 5))
        return Int32(bitPattern: (raw >> 1) ^ (~(raw & 1) &+ 1))
    }

    mutating func readSignedVarInt64() throws -> Int64 {
        let raw = try readUnsignedVarInt(maxBytes: 10)
        return Int64(bitPattern: (raw >> 1) ^ (~(raw & 1) &+ 1))
    }
}

struct BinaryWriter {
    private(set) var data = Data()

    mutating func writeByte(_ value: UInt8) { data.append(value) }
    mutating func writeData(_ value: Data) { data.append(value) }
    mutating func writeUInt16LE(_ value: UInt16) { data.appendLE(value) }
    mutating func writeInt16LE(_ value: Int16) { writeUInt16LE(UInt16(bitPattern: value)) }
    mutating func writeUInt16BE(_ value: UInt16) {
        writeByte(UInt8(truncatingIfNeeded: value >> 8))
        writeByte(UInt8(truncatingIfNeeded: value))
    }
    mutating func writeInt16BE(_ value: Int16) { writeUInt16BE(UInt16(bitPattern: value)) }
    mutating func writeUInt32LE(_ value: UInt32) { data.appendLE(value) }
    mutating func writeInt32LE(_ value: Int32) { data.appendLE(value) }
    mutating func writeUInt64LE(_ value: UInt64) {
        writeUInt32LE(UInt32(truncatingIfNeeded: value))
        writeUInt32LE(UInt32(truncatingIfNeeded: value >> 32))
    }
    mutating func writeInt64LE(_ value: Int64) { writeUInt64LE(UInt64(bitPattern: value)) }
    mutating func writeFloatLE(_ value: Float) { writeUInt32LE(value.bitPattern) }
    mutating func writeDoubleLE(_ value: Double) { writeUInt64LE(value.bitPattern) }
    mutating func writeUInt32BE(_ value: UInt32) {
        writeByte(UInt8(truncatingIfNeeded: value >> 24))
        writeByte(UInt8(truncatingIfNeeded: value >> 16))
        writeByte(UInt8(truncatingIfNeeded: value >> 8))
        writeByte(UInt8(truncatingIfNeeded: value))
    }
    mutating func writeInt32BE(_ value: Int32) { writeUInt32BE(UInt32(bitPattern: value)) }
    mutating func writeUInt64BE(_ value: UInt64) {
        writeUInt32BE(UInt32(truncatingIfNeeded: value >> 32))
        writeUInt32BE(UInt32(truncatingIfNeeded: value))
    }
    mutating func writeInt64BE(_ value: Int64) { writeUInt64BE(UInt64(bitPattern: value)) }
    mutating func writeFloatBE(_ value: Float) { writeUInt32BE(value.bitPattern) }
    mutating func writeDoubleBE(_ value: Double) { writeUInt64BE(value.bitPattern) }

    mutating func writeUnsignedVarInt(_ value: UInt64) {
        var current = value
        repeat {
            var byte = UInt8(current & 0x7f)
            current >>= 7
            if current != 0 { byte |= 0x80 }
            writeByte(byte)
        } while current != 0
    }

    mutating func writeSignedVarInt(_ value: Int32) {
        let zigzag = UInt32(bitPattern: (value << 1) ^ (value >> 31))
        writeUnsignedVarInt(UInt64(zigzag))
    }

    mutating func writeSignedVarLong(_ value: Int64) {
        let zigzag = UInt64(bitPattern: (value << 1) ^ (value >> 63))
        writeUnsignedVarInt(zigzag)
    }
}
