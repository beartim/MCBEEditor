import Foundation

extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }

    init?(hexString: String) {
        let cleaned = hexString.filter { !$0.isWhitespace }
        guard cleaned.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(cleaned.count / 2)
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            guard let value = UInt8(cleaned[index..<next], radix: 16) else { return nil }
            bytes.append(value)
            index = next
        }
        self.init(bytes)
    }

    func hexDump(bytesPerLine: Int = 16, maximumBytes: Int = 1_048_576) -> String {
        let countToShow = Swift.min(count, maximumBytes)
        var lines = [String]()
        var offset = 0
        while offset < countToShow {
            let end = Swift.min(offset + Swift.max(1, bytesPerLine), countToShow)
            let chunk = self[offset..<end]
            let hex = chunk.map { String(format: "%02x", $0) }.joined(separator: " ")
            let ascii = chunk.map { byte -> Character in
                (32...126).contains(byte) ? Character(UnicodeScalar(byte)) : "."
            }
            let offsetText = String(format: "%08x", offset)
            let paddedHex = hex.padding(toLength: 47, withPad: " ", startingAt: 0)
            lines.append("\(offsetText)  \(paddedHex)  \(String(ascii))")
            offset = end
        }
        if count > countToShow { lines.append("… 已截断，原始大小：\(count) bytes") }
        return lines.joined(separator: "\n")
    }

    func littleEndianUInt16(at offset: Int) throws -> UInt16 {
        guard offset >= 0, offset + 2 <= count else { throw MCBEEditorError.malformedData("UInt16 越界") }
        return withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            UInt16(raw[offset]) | (UInt16(raw[offset + 1]) << 8)
        }
    }

    func littleEndianUInt32(at offset: Int) throws -> UInt32 {
        guard offset >= 0, offset + 4 <= count else { throw MCBEEditorError.malformedData("UInt32 越界") }
        return withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            UInt32(raw[offset]) |
            (UInt32(raw[offset + 1]) << 8) |
            (UInt32(raw[offset + 2]) << 16) |
            (UInt32(raw[offset + 3]) << 24)
        }
    }

    func littleEndianInt32(at offset: Int) throws -> Int32 {
        Int32(bitPattern: try littleEndianUInt32(at: offset))
    }

    mutating func appendLE(_ value: UInt16) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
    }

    mutating func appendLE(_ value: UInt32) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
        append(UInt8(truncatingIfNeeded: value >> 16))
        append(UInt8(truncatingIfNeeded: value >> 24))
    }

    mutating func appendLE(_ value: Int32) {
        appendLE(UInt32(bitPattern: value))
    }
}
