import Foundation

/// Lossless typed text interchange for standalone NBT files. This codec deliberately
/// has no dependency on command parsing, world state or UI display summaries.
enum MCBESNBTCodec {
    static let maximumDepth = 256
    static let maximumRoots = 2_000_000

    static func decode(_ data: Data) throws -> [NBTDocument] {
        guard let text = String(data: data, encoding: .utf8) else {
            throw MCBEEditorError.malformedData("MCBE-SNBT 必须使用有效的 UTF-8")
        }
        return try decode(text: text)
    }

    static func decode(text: String) throws -> [NBTDocument] {
        var parser = Parser(text: text)
        return try parser.documents()
    }

    static func encode(_ documents: [NBTDocument]) throws -> Data {
        guard !documents.isEmpty, documents.count <= maximumRoots else {
            throw MCBEEditorError.malformedData("MCBE-SNBT 根标签数量必须为 1…\(maximumRoots)")
        }
        let roots = try documents.map { try namedTag(NBTNamedTag(name: $0.rootName, value: $0.root), depth: 0) }
        return Data(("[\n" + roots.joined(separator: ",\n") + "\n]\n").utf8)
    }

    private static func checkDepth(_ depth: Int) throws {
        guard depth <= maximumDepth else {
            throw MCBEEditorError.malformedData("MCBE-SNBT 嵌套深度超过 \(maximumDepth)")
        }
    }

    private static func descriptor(_ value: NBTValue) -> String {
        if case .list(let type, _) = value { return "'List''\(type == .end ? "" : type.displayName)'" }
        return "'\(value.type.displayName)'"
    }

    private static func namedTag(_ tag: NBTNamedTag, depth: Int) throws -> String {
        try descriptor(tag.value) + "\"" + escaped(tag.name) + "\"=\"" + payload(tag.value, depth: depth) + "\""
    }

    private static func payload(_ value: NBTValue, depth: Int) throws -> String {
        try checkDepth(depth)
        switch value {
        case .byte(let number): return String(number)
        case .short(let number): return String(number)
        case .int(let number): return String(number)
        case .long(let number): return String(number)
        case .float(let number):
            if number.isNaN { return "bits:" + hex(number.bitPattern, width: 8) }
            if number.isInfinite { return number.sign == .minus ? "-Infinity" : "Infinity" }
            return String(number)
        case .double(let number):
            if number.isNaN { return "bits:" + hex(number.bitPattern, width: 16) }
            if number.isInfinite { return number.sign == .minus ? "-Infinity" : "Infinity" }
            return String(number)
        case .string(let text): return escaped(text)
        case .byteArray(let bytes): return "[" + bytes.map { String(Int8(bitPattern: $0)) }.joined(separator: ",") + "]"
        case .intArray(let values): return "[" + values.map(String.init).joined(separator: ",") + "]"
        case .longArray(let values): return "[" + values.map(String.init).joined(separator: ",") + "]"
        case .compound(let tags):
            return try "{" + tags.map { try namedTag($0, depth: depth + 1) }.joined(separator: ",") + "}"
        case .list(let type, let values):
            guard values.allSatisfy({ $0.type == type }), type != .end || values.isEmpty else {
                throw MCBEEditorError.malformedData("MCBE-SNBT List 的元素与声明类型不一致")
            }
            return try values.map { child in
                let content = try payload(child, depth: depth + 1)
                if type == .string || type == .list { return "[" + descriptor(child) + "=\"" + content + "\"]" }
                return content
            }.joined(separator: ",")
        }
    }

    private static func hex<T: FixedWidthInteger>(_ value: T, width: Int) -> String {
        let digits = String(value, radix: 16, uppercase: true)
        return String(repeating: "0", count: width - digits.count) + digits
    }

    private static func escaped(_ text: String) -> String {
        var result = ""
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x5C: result += "\\\\"
            case 0x22: result += "\\\""
            case 0x0A: result += "\\n"
            case 0x0D: result += "\\r"
            case 0x09: result += "\\t"
            case 0x08: result += "\\b"
            case 0x0C: result += "\\f"
            case 0...0x1F, 0x7F...0x9F: result += "\\u" + hex(scalar.value, width: 4)
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    private indirect enum Descriptor {
        case value(NBTTagType)
        case list(Descriptor?)

        var type: NBTTagType {
            switch self {
            case .value(let type): return type
            case .list: return .list
            }
        }
    }

    private struct Parser {
        let scalars: [Unicode.Scalar]
        var offset = 0
        var peek: Unicode.Scalar? { offset < scalars.count ? scalars[offset] : nil }

        init(text: String) {
            scalars = Array(text.unicodeScalars)
            if scalars.first?.value == 0xFEFF { offset = 1 }
        }

        mutating func documents() throws -> [NBTDocument] {
            whitespace()
            guard peek != nil else { throw error("文件为空") }
            var result = [NBTDocument]()
            if peek == "[" {
                offset += 1
                whitespace()
                guard peek != "]" else { throw error("根标签序列不能为空") }
                while true {
                    let tag = try named(depth: 0)
                    result.append(NBTDocument(rootName: tag.name, root: tag.value))
                    guard result.count <= MCBESNBTCodec.maximumRoots else { throw error("根标签数量超过安全上限") }
                    whitespace()
                    if peek == "]" { offset += 1; break }
                    try expect(",")
                    whitespace()
                    guard peek != "]", peek != nil else { throw error("根标签末尾不能有逗号") }
                }
            } else if peek == "{" {
                offset += 1
                result = [NBTDocument(rootName: "", root: .compound(try tags(closing: "}", depth: 1)))]
                try expect("}")
            } else {
                result = [NBTDocument(rootName: "", root: .compound(try tags(closing: nil, depth: 1)))]
            }
            whitespace()
            guard peek == nil else { throw error("末尾存在无法识别的内容") }
            return result
        }

        private mutating func tags(closing: Unicode.Scalar?, depth: Int) throws -> [NBTNamedTag] {
            whitespace()
            if let closing, peek == closing { return [] }
            var result = [NBTNamedTag]()
            while true {
                result.append(try named(depth: depth))
                whitespace()
                if peek == closing { return result }
                try expect(",")
                whitespace()
                guard peek != closing, peek != nil else { throw error("标签末尾不能有逗号") }
            }
        }

        private mutating func named(depth: Int) throws -> NBTNamedTag {
            try MCBESNBTCodec.checkDepth(depth)
            let kind = try typeDescriptor()
            let name = try quoted("\"")
            try expect("=")
            try expect("\"")
            let value = try payload(kind, terminator: "\"", depth: depth)
            try expect("\"")
            return NBTNamedTag(name: name, value: value)
        }

        private mutating func typeDescriptor(level: Int = 0) throws -> Descriptor {
            try MCBESNBTCodec.checkDepth(level)
            let name = try quoted("'")
            // An explicit empty descriptor is valid only directly after List.
            // NBT stores an unspecified empty List with element type End (0).
            if name.isEmpty, level > 0 { return .value(.end) }
            guard let type = NBTTagType.allCases.first(where: { $0.displayName == name }) else { throw error("未知类型：\(name)") }
            if type == .list {
                whitespace()
                return .list(peek == "'" ? try typeDescriptor(level: level + 1) : nil)
            }
            return .value(type)
        }

        private mutating func payload(_ kind: Descriptor, terminator: Unicode.Scalar, depth: Int) throws -> NBTValue {
            try MCBESNBTCodec.checkDepth(depth)
            switch kind {
            case .list(let element):
                guard let element else { throw error("List 缺少元素类型") }
                return .list(element.type, try list(element: element, terminator: terminator, depth: depth + 1))
            case .value(let type):
                switch type {
                case .string: return .string(try read(until: [terminator]))
                case .compound:
                    try expect("{")
                    let children = try tags(closing: "}", depth: depth + 1)
                    try expect("}")
                    return .compound(children)
                case .byteArray:
                    let values: [Int8] = try numericArray(type: type, convert: Int8.init)
                    return .byteArray(Data(values.map { UInt8(bitPattern: $0) }))
                case .intArray: return .intArray(try numericArray(type: type, convert: Int32.init))
                case .longArray: return .longArray(try numericArray(type: type, convert: Int64.init))
                case .end, .list: throw error("End 仅能作为空 List 的元素类型")
                default: return try scalar(type, raw: read(until: [terminator]))
                }
            }
        }

        private mutating func list(element: Descriptor, terminator: Unicode.Scalar, depth: Int) throws -> [NBTValue] {
            whitespace()
            if peek == terminator { return [] }
            guard element.type != .end else { throw error("未指定元素类型的 List 必须为空") }
            var result = [NBTValue]()
            while true {
                result.append(try listElement(element, terminator: terminator, depth: depth))
                whitespace()
                if peek == terminator { return result }
                try expect(",")
                whitespace()
                guard peek != terminator, peek != nil else { throw error("List 末尾不能有逗号") }
            }
        }

        private mutating func listElement(_ kind: Descriptor, terminator: Unicode.Scalar, depth: Int) throws -> NBTValue {
            try MCBESNBTCodec.checkDepth(depth)
            whitespace()
            if peek == "[" {
                let saved = offset
                offset += 1
                whitespace()
                if startsAnonymousValue() {
                    do {
                        let actual = try typeDescriptor()
                        guard actual.type == kind.type else { throw error("匿名元素类型与 List 声明不一致") }
                        try expect("=")
                        let value: NBTValue
                        whitespace()
                        if peek == "\"" {
                            offset += 1
                            value = try payload(actual, terminator: "\"", depth: depth)
                            try expect("\"")
                        } else {
                            // Legacy entity/getblock output: ['List''Int'=[1,2]].
                            guard case .list = actual else { throw error("匿名元素缺少值引号") }
                            try expect("[")
                            value = try payload(actual, terminator: "]", depth: depth)
                            try expect("]")
                        }
                        try expect("]")
                        return value
                    } catch {
                        // Keep type-looking text in legacy compact String lists.
                        guard case .list(.some(.value(.string))) = kind else { throw error }
                    }
                }
                offset = saved
            }
            switch kind {
            case .list:
                try expect("[")
                let value = try payload(kind, terminator: "]", depth: depth)
                try expect("]")
                return value
            case .value(let type):
                switch type {
                case .compound, .byteArray, .intArray, .longArray:
                    return try payload(kind, terminator: terminator, depth: depth)
                case .string:
                    let value = try read(until: [",", terminator])
                    guard !value.isEmpty else { throw error("空字符串 List 元素必须使用带类型的匿名值") }
                    return .string(value)
                default: return try scalar(type, raw: read(until: [",", terminator]))
                }
            }
        }

        private func startsAnonymousValue() -> Bool {
            var probe = self
            guard probe.peek == "'", (try? probe.typeDescriptor()) != nil else { return false }
            probe.whitespace()
            guard probe.peek == "=" else { return false }
            probe.offset += 1
            probe.whitespace()
            return probe.peek == "\"" || probe.peek == "["
        }

        private mutating func numericArray<T>(type: NBTTagType, convert: (String) -> T?) throws -> [T] {
            try expect("[")
            whitespace()
            if peek == "]" { offset += 1; return [] }
            var values = [T]()
            while true {
                let raw = try read(until: [",", "]"]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard integerText(raw), let value = convert(raw) else { throw error("\(type.displayName) 数值无效或溢出：\(raw)") }
                values.append(value)
                if peek == "]" { offset += 1; return values }
                try expect(",")
                whitespace()
                guard peek != "]" else { throw error("数组末尾不能有逗号") }
            }
        }

        private func scalar(_ type: NBTTagType, raw text: String) throws -> NBTValue {
            let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
            switch type {
            case .byte: if integerText(raw), let value = Int8(raw) { return .byte(value) }
            case .short: if integerText(raw), let value = Int16(raw) { return .short(value) }
            case .int: if integerText(raw), let value = Int32(raw) { return .int(value) }
            case .long: if integerText(raw), let value = Int64(raw) { return .long(value) }
            case .float:
                if raw.hasPrefix("bits:"), let bits = bitPattern(raw, digits: 8) { return .float(Float(bitPattern: UInt32(bits))) }
                if raw == "NaN" { return .float(.nan) }
                if raw == "Infinity" { return .float(.infinity) }
                if raw == "-Infinity" { return .float(-.infinity) }
                if floatingText(raw), let value = Float(raw), value.isFinite { return .float(value) }
            case .double:
                if raw.hasPrefix("bits:"), let bits = bitPattern(raw, digits: 16) { return .double(Double(bitPattern: bits)) }
                if raw == "NaN" { return .double(.nan) }
                if raw == "Infinity" { return .double(.infinity) }
                if raw == "-Infinity" { return .double(-.infinity) }
                if floatingText(raw), let value = Double(raw), value.isFinite { return .double(value) }
            default: break
            }
            throw error("\(type.displayName) 数值无效或溢出：\(raw)")
        }

        private func integerText(_ text: String) -> Bool {
            var bytes = Array(text.utf8)
            if bytes.first == 43 || bytes.first == 45 { bytes.removeFirst() }
            return !bytes.isEmpty && bytes.allSatisfy { (48...57).contains($0) }
        }

        private func floatingText(_ text: String) -> Bool {
            text.range(of: #"^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$"#, options: .regularExpression) != nil
        }

        private func bitPattern(_ raw: String, digits: Int) -> UInt64? {
            let text = raw.dropFirst(5)
            guard text.utf8.count == digits, text.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else { return nil }
            return UInt64(text, radix: 16)
        }

        private mutating func quoted(_ quote: Unicode.Scalar) throws -> String {
            try expect(quote)
            let value = try read(until: [quote])
            try expect(quote)
            return value
        }

        private mutating func read(until stops: Set<Unicode.Scalar>) throws -> String {
            var value = ""
            while let character = peek {
                if stops.contains(character) { return value }
                offset += 1
                if character == "\\" { value.unicodeScalars.append(try escapedScalar()) }
                else { value.unicodeScalars.append(character) }
            }
            throw error("字符串、数组或 List 未闭合")
        }

        private mutating func escapedScalar() throws -> Unicode.Scalar {
            guard let code = peek else { throw error("转义序列不完整") }
            offset += 1
            switch code {
            case "\\", "\"", "'", ",", "[", "]", "{", "}": return code
            case "n": return "\n"
            case "r": return "\r"
            case "t": return "\t"
            case "b": return Unicode.Scalar(8)!
            case "f": return Unicode.Scalar(12)!
            case "u":
                let first = try utf16Unit()
                if (0xD800...0xDBFF).contains(first) {
                    guard peek == "\\" else { throw error("UTF-16 高代理项缺少低代理项") }
                    offset += 1
                    guard peek == "u" else { throw error("UTF-16 高代理项缺少低代理项") }
                    offset += 1
                    let second = try utf16Unit()
                    guard (0xDC00...0xDFFF).contains(second) else { throw error("UTF-16 低代理项无效") }
                    return Unicode.Scalar(0x10000 + (first - 0xD800) * 0x400 + second - 0xDC00)!
                }
                guard !(0xDC00...0xDFFF).contains(first), let scalar = Unicode.Scalar(first) else { throw error("UTF-16 代理项无效") }
                return scalar
            default: throw error("未知转义：\\\(code)")
            }
        }

        private mutating func utf16Unit() throws -> UInt32 {
            var result: UInt32 = 0
            for _ in 0..<4 {
                guard let digit = peek, let value = UInt32(String(digit), radix: 16), digit.isASCII else { throw error("\\u 转义必须包含四个十六进制数字") }
                result = result * 16 + value
                offset += 1
            }
            return result
        }

        private mutating func whitespace() {
            while let character = peek, CharacterSet.whitespacesAndNewlines.contains(character) { offset += 1 }
        }

        private mutating func expect(_ expected: Unicode.Scalar) throws {
            whitespace()
            guard peek == expected else { throw error("应为 \(expected)") }
            offset += 1
        }

        private func error(_ message: String) -> MCBEEditorError {
            .malformedData("MCBE-SNBT 字符 \(offset)：\(message)")
        }
    }
}
