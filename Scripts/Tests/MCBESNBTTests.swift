import Foundation

@main
struct MCBESNBTTests {
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }

    static func bytes(_ documents: [NBTDocument]) throws -> Data {
        var result = Data()
        for document in documents { result.append(try BedrockNBTCodec.encode(document, encoding: .littleEndian)) }
        return result
    }

    static func rejects(_ text: String) {
        do { _ = try MCBESNBTCodec.decode(text: text); preconditionFailure("accepted malformed input: \(text.prefix(180))") }
        catch { }
    }

    static func main() throws {
        let raw = NBTRawStringCodec.decode(Data([0xFF, 0x80, 0x00, 0x42]))
        let source = [NBTDocument(rootName: "名称\"\\\n😀", root: .compound([
            NBTNamedTag(name: "", value: .string("")),
            NBTNamedTag(name: "same", value: .byte(-128)),
            NBTNamedTag(name: "same", value: .short(-32768)),
            NBTNamedTag(name: "int", value: .int(.min)),
            NBTNamedTag(name: "long", value: .long(.min)),
            NBTNamedTag(name: "longMax", value: .long(.max)),
            NBTNamedTag(name: "binary", value: .string(raw)),
            NBTNamedTag(name: "special", value: .string(" a,b ['x'] {\"y\"} \\ \t\r\n\u{0}\u{8}\u{C}尾😀 ")),
            NBTNamedTag(name: "bytes", value: .byteArray(Data([0, 127, 128, 255]))),
            NBTNamedTag(name: "ints", value: .intArray([.min, 0, .max])),
            NBTNamedTag(name: "longs", value: .longArray([.min, 9_007_199_254_740_993, .max])),
            NBTNamedTag(name: "emptyBytes", value: .byteArray(Data())),
            NBTNamedTag(name: "emptyInts", value: .intArray([])),
            NBTNamedTag(name: "emptyLongs", value: .longArray([])),
            NBTNamedTag(name: "empty", value: .compound([])),
            NBTNamedTag(name: "strings", value: .list(.string, [.string(""), .string(" "), .string("x,y]😀")])),
            NBTNamedTag(name: "nested", value: .list(.list, [.list(.int, [.int(1)]), .list(.string, [.string(""), .string("two")]), .list(.end, [])])),
            NBTNamedTag(name: "emptyList", value: .list(.compound, [])),
            NBTNamedTag(name: "endList", value: .list(.end, [])),
            NBTNamedTag(name: "compounds", value: .list(.compound, [.compound([]), .compound([NBTNamedTag(name: "x", value: .int(2))])])),
            NBTNamedTag(name: "arrays", value: .list(.longArray, [.longArray([]), .longArray([.max])]))
        ]))]
        var documents = source
        for bits: UInt32 in [0, 0x80000000, 1, 0x007FFFFF, 0x7F7FFFFF, 0x7FC01234, 0xFF801234, 0x7F800000, 0xFF800000] {
            documents.append(NBTDocument(rootName: "float", root: .float(Float(bitPattern: bits))))
        }
        for bits: UInt64 in [0, 0x8000000000000000, 1, 0x000FFFFFFFFFFFFF, 0x7FEFFFFFFFFFFFFF, 0x7FF8000000001234, 0xFFF0000000001234, 0x7FF0000000000000, 0xFFF0000000000000] {
            documents.append(NBTDocument(rootName: "double", root: .double(Double(bitPattern: bits))))
        }
        let encoded = try MCBESNBTCodec.encode(documents)
        let text = String(decoding: encoded, as: UTF8.self)
        expect(text.contains(#"'List'''"endList"="""#), "unspecified empty List must export an empty element-type marker")
        expect(text.contains(#"['List'''=""]"#), "anonymous empty child List must export an empty element-type marker")
        expect(text.contains(#"'List''Compound'"emptyList"="""#), "typed empty List must retain Compound element type")
        let emptyInput = try MCBESNBTCodec.decode(text: #"'List'''"Items"="""#)
        guard case .list(.end, let emptyValues)? = emptyInput[0].root.compoundValue(named: "Items") else {
            preconditionFailure("empty element-type marker must decode to an unspecified List")
        }
        expect(emptyValues.isEmpty, "unspecified List must remain empty")
        for invalid in [#"''"x"="""#, #"'Int'''"x"="""#, #"'List'''"x"="1""#, #"'List'''"x"="[]""#, #"'List''List'''"x"="[1]""#] { rejects(invalid) }
        let decoded = try MCBESNBTCodec.decode(encoded)
        let expected = try bytes(documents)
        let actual = try bytes(decoded)
        expect(actual == expected, "binary roundtrip lost tag name/order/type/string/number data")
        let canonical = try MCBESNBTCodec.encode(decoded)
        expect(canonical == encoded, "canonical text is unstable")
        expect(String(decoding: encoded, as: UTF8.self).contains("bits:7FC01234"), "NaN bit pattern not exported")
        let legacy = try MCBESNBTCodec.decode(text: #"'List''List''Int'"nested"="[1,2],[]",'List''List'"mixed"="['List''Int'=[1]],['List''String'=[two]]",'List''Float'"Pos"="0.0,64.0,0.0""#)
        expect(legacy.count == 1 && legacy[0].root.children.count == 3, "legacy command forms")
        let escaped = try MCBESNBTCodec.decode(text: #"{'String'"\uD83D\uDE00"="\uD83D\uDE00\,\[\]\{\}\'\\\"\n\r\t\b\f"}"#)
        expect(escaped[0].root.children[0].name == "😀", "surrogate pair name")
        expect(escaped[0].root.children[0].value.summary == "😀,[]{}'\\\"\n\r\t\u{8}\u{C}", "escaped string")
        let bomDocuments = try MCBESNBTCodec.decode(Data([0xEF, 0xBB, 0xBF]) + Data("{}".utf8))
        expect(bomDocuments.count == 1, "BOM")
        for text in ["", " ", "[]", "[", "{} garbage", "{},", "['Int'\"x\"=\"1\",]", "'Int'\"x\"=\"1\",", "'Byte'\"x\"=\"128\"", "'Short'\"x\"=\"32768\"", "'Int'\"x\"=\"2147483648\"", "'Long'\"x\"=\"9223372036854775808\"", "'ByteArray'\"x\"=\"[128]\"", "'IntArray'\"x\"=\"[2147483648]\"", "'LongArray'\"x\"=\"[9223372036854775808]\"", "'IntArray'\"x\"=\"[1,]\"", "'Float'\"x\"=\"1e39\"", "'Double'\"x\"=\"1e309\"", "'Double'\"x\"=\"bits:0\"", "'Float'\"x\"=\"bits:XYZ00000\"", "'List''Int'\"x\"=\"['String'=\"1\"]\"", "'List''End'\"x\"=\"1\"", "'List'\"x\"=\"\"", "'End'\"x\"=\"\"", "'List''Int'\"x\"=\"1,\"", "'String'\"x\"=\"\\q\"", "'String'\"x\"=\"\\uDC00\"", "'String'\"x\"=\"\\uD800\"", "'String'\"x\"=\"\\uD800\\u0000\"", "'String'\"x\"=\"\\u12\"", "'String'\"x\"=\"unterminated", "'Compound'\"x\"=\"{'Int'\"y\"=\"1\",}\""] { rejects(text) }
        do { _ = try MCBESNBTCodec.decode(Data([0xFF])); preconditionFailure("invalid UTF-8 accepted") } catch { }
        var nested: NBTValue = .int(1)
        for _ in 0..<256 { nested = .list(nested.type, [nested]) }
        let boundary = try MCBESNBTCodec.encode([NBTDocument(rootName: "", root: nested)])
        _ = try MCBESNBTCodec.decode(boundary)
        nested = .list(.list, [nested])
        do { _ = try MCBESNBTCodec.encode([NBTDocument(rootName: "", root: nested)]); preconditionFailure("deep encode accepted") } catch { }
        rejects("['List'" + String(repeating: "'List'", count: 257) + "'Int'\"x\"=\"\"]")
        do { _ = try MCBESNBTCodec.encode([NBTDocument(rootName: "", root: .list(.int, [.long(1)]))]); preconditionFailure("mismatched encode accepted") } catch { }
        do { _ = try MCBESNBTCodec.encode([]); preconditionFailure("empty documents accepted") } catch { }
        print("MCBE-SNBT Swift codec: byte-exact roundtrip, canonical text, legacy forms, malformed input and depth checks passed")
    }
}
