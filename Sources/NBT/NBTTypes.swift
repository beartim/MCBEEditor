import Foundation

enum NBTEncoding: Equatable {
    case bigEndian
    case littleEndian
    case littleEndianVarInt
}

enum NBTTagType: UInt8, CaseIterable {
    case end = 0
    case byte = 1
    case short = 2
    case int = 3
    case long = 4
    case float = 5
    case double = 6
    case byteArray = 7
    case string = 8
    case list = 9
    case compound = 10
    case intArray = 11
    case longArray = 12
}

struct NBTNamedTag {
    var name: String
    var value: NBTValue
}

indirect enum NBTValue {
    case byte(Int8)
    case short(Int16)
    case int(Int32)
    case long(Int64)
    case float(Float)
    case double(Double)
    case byteArray(Data)
    case string(String)
    case list(NBTTagType, [NBTValue])
    case compound([NBTNamedTag])
    case intArray([Int32])
    case longArray([Int64])

    var type: NBTTagType {
        switch self {
        case .byte: return .byte
        case .short: return .short
        case .int: return .int
        case .long: return .long
        case .float: return .float
        case .double: return .double
        case .byteArray: return .byteArray
        case .string: return .string
        case .list: return .list
        case .compound: return .compound
        case .intArray: return .intArray
        case .longArray: return .longArray
        }
    }

    var summary: String {
        switch self {
        case .byte(let value): return String(value)
        case .short(let value): return String(value)
        case .int(let value): return String(value)
        case .long(let value): return String(value)
        case .float(let value): return String(value)
        case .double(let value): return String(value)
        case .byteArray(let value): return "ByteArray[\(value.count)]"
        case .string(let value): return value
        case .list(_, let values): return "List[\(values.count)]"
        case .compound(let values): return "Compound{\(values.count)}"
        case .intArray(let values): return "IntArray[\(values.count)]"
        case .longArray(let values): return "LongArray[\(values.count)]"
        }
    }

    var children: [NBTNamedTag] {
        switch self {
        case .compound(let tags): return tags
        case .list(_, let values): return values.enumerated().map { NBTNamedTag(name: "[\($0.offset)]", value: $0.element) }
        default: return []
        }
    }

    func compoundValue(named name: String) -> NBTValue? {
        guard case .compound(let tags) = self else { return nil }
        return tags.first(where: { $0.name == name })?.value
    }

    func stringValue(named name: String) -> String? {
        guard let value = compoundValue(named: name) else { return nil }
        if case .string(let text) = value { return text }
        return nil
    }

    func intValue(named name: String) -> Int32? {
        guard let value = compoundValue(named: name) else { return nil }
        switch value {
        case .int(let number): return number
        case .short(let number): return Int32(number)
        case .byte(let number): return Int32(number)
        default: return nil
        }
    }
}

struct NBTDocument {
    var rootName: String
    var root: NBTValue
}

extension NBTTagType {
    var displayName: String {
        switch self {
        case .end: return "End"
        case .byte: return "Byte"
        case .short: return "Short"
        case .int: return "Int"
        case .long: return "Long"
        case .float: return "Float"
        case .double: return "Double"
        case .byteArray: return "ByteArray"
        case .string: return "String"
        case .list: return "List"
        case .compound: return "Compound"
        case .intArray: return "IntArray"
        case .longArray: return "LongArray"
        }
    }
}
