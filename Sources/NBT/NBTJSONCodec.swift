import Foundation

/// Lossless typed JSON bridge for NBT documents.
///
/// Single-root files use the common prismarine-style shape:
/// `{ "name": "", "type": "compound", "value": { ... } }`.
/// Consecutive NBT files use a small wrapper with a `documents` array.
/// The decoder also accepts ordinary JSON and infers compatible NBT types.
enum NBTJSONCodec {
  private static let formatIdentifier = "mcbeeditor-nbt-json"
  private static let legacyFormatIdentifier = "blocktopograph-nbt-json"

  private static func isSupportedFormat(_ value: Any?) -> Bool {
    guard let format = value as? String else { return false }
    return format == formatIdentifier || format == legacyFormatIdentifier
  }

  static func encode(_ documents: [NBTDocument], prettyPrinted: Bool = true) throws -> Data {
    guard !documents.isEmpty else {
      throw MCBEEditorError.malformedData("没有可导出的 NBT 根标签")
    }
    let object: Any
    if documents.count == 1, let document = documents.first {
      object = encodeDocument(document)
    } else {
      object =
        [
          "format": formatIdentifier,
          "version": 1,
          "documents": documents.map(encodeDocument),
        ] as [String: Any]
    }
    var options: JSONSerialization.WritingOptions = [.sortedKeys]
    if prettyPrinted { options.insert(.prettyPrinted) }
    return try JSONSerialization.data(withJSONObject: object, options: options)
  }

  /// Encodes one entity compound in the tag-list JSON layout used by
  /// MCBEEditor's selected-entity exports. Each child tag becomes one
  /// entry in `documents`, preserving the entity's complete tag set.
  static func encodeEntityDocument(_ document: NBTDocument, prettyPrinted: Bool = true) throws
    -> Data
  {
    guard case .compound(let tags) = document.root else {
      throw MCBEEditorError.malformedData("实体 JSON 的 NBT 根标签必须是 Compound")
    }
    let documents: [[String: Any]] = tags.map { tag in
      var encoded = encodeTag(tag.value)
      encoded["name"] = tag.name
      return encoded
    }
    let object: [String: Any] = [
      "documents": documents,
      "format": formatIdentifier,
      "version": 1,
    ]
    var options: JSONSerialization.WritingOptions = [.sortedKeys]
    if prettyPrinted { options.insert(.prettyPrinted) }
    return try JSONSerialization.data(withJSONObject: object, options: options)
  }

  /// Decodes both selected-entity JSON (where `documents` are the entity's
  /// child tags) and the normal typed/ordinary JSON formats supported by the
  /// standalone NBT tool.
  static func decodeEntityDocuments(_ data: Data) throws -> [NBTDocument] {
    let object: Any
    do {
      object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    } catch {
      throw MCBEEditorError.malformedData("JSON 解析失败：\(error.localizedDescription)")
    }
    if let wrapper = object as? [String: Any],
      isSupportedFormat(wrapper["format"]),
      let rawDocuments = wrapper["documents"] as? [Any],
      !rawDocuments.isEmpty
    {
      let dictionaries = rawDocuments.compactMap { $0 as? [String: Any] }
      let commonEntityNames: Set<String> = [
        "UniqueID", "identifier", "definitions", "Pos", "Motion", "Rotation", "Attributes",
      ]
      let isSelectedEntityLayout =
        dictionaries.count == rawDocuments.count
        && dictionaries.allSatisfy {
          $0["name"] is String && $0["type"] is String && $0["value"] != nil
        }
        && (dictionaries.contains { commonEntityNames.contains($0["name"] as? String ?? "") }
          || dictionaries.contains { ($0["type"] as? String)?.lowercased() != "compound" })
      if isSelectedEntityLayout {
        let tags = try dictionaries.enumerated().map { index, dictionary -> NBTNamedTag in
          guard let name = dictionary["name"] as? String else {
            throw MCBEEditorError.malformedData("实体 JSON documents[\(index)] 缺少 name")
          }
          return NBTNamedTag(
            name: name,
            value: try decodeTag(dictionary, path: "$.documents[\(index)]")
          )
        }
        return [NBTDocument(rootName: "", root: .compound(tags))]
      }
    }
    return try decode(data)
  }

  static func decode(_ data: Data) throws -> [NBTDocument] {
    guard !data.isEmpty else {
      throw MCBEEditorError.malformedData("JSON 文件为空")
    }
    let object: Any
    do {
      object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    } catch {
      throw MCBEEditorError.malformedData("JSON 解析失败：\(error.localizedDescription)")
    }

    if let dictionary = object as? [String: Any], let documents = dictionary["documents"] as? [Any]
    {
      guard !documents.isEmpty else {
        throw MCBEEditorError.malformedData("JSON 中没有 NBT 根标签")
      }
      return try documents.enumerated().map { index, item in
        try decodeDocument(item, fallbackName: "root_\(index)")
      }
    }
    if let array = object as? [Any], array.allSatisfy({ ($0 as? [String: Any])?["type"] != nil }) {
      return try array.enumerated().map { index, item in
        try decodeDocument(item, fallbackName: "root_\(index)")
      }
    }
    if let dictionary = object as? [String: Any], dictionary["type"] != nil {
      return [try decodeDocument(dictionary, fallbackName: "")]
    }

    // Ordinary JSON fallback. This makes generic JSON files editable and convertible.
    return [NBTDocument(rootName: "", root: try inferValue(from: object, path: "$"))]
  }

  private static func encodeDocument(_ document: NBTDocument) -> [String: Any] {
    var result = encodeTag(document.root)
    result["name"] = document.rootName
    return result
  }

  private static func encodeTag(_ value: NBTValue) -> [String: Any] {
    ["type": typeName(value.type), "value": encodePayload(value)]
  }

  private static func encodePayload(_ value: NBTValue) -> Any {
    switch value {
    case .byte(let number): return Int(number)
    case .short(let number): return Int(number)
    case .int(let number): return Int(number)
    case .long(let number): return String(number)  // Preserve all 64 bits across JSON implementations.
    case .float(let number): return Double(number)
    case .double(let number): return number
    case .byteArray(let data): return data.map { Int(Int8(bitPattern: $0)) }
    case .string(let text): return text
    case .list(let type, let values):
      return [
        "type": typeName(type),
        "value": values.map(encodePayload),
      ] as [String: Any]
    case .compound(let tags):
      var dictionary = [String: Any]()
      for tag in tags { dictionary[tag.name] = encodeTag(tag.value) }
      return dictionary
    case .intArray(let values): return values.map(Int.init)
    case .longArray(let values): return values.map(String.init)
    }
  }

  private static func decodeDocument(_ object: Any, fallbackName: String) throws -> NBTDocument {
    guard let dictionary = object as? [String: Any] else {
      throw MCBEEditorError.malformedData("NBT JSON 根标签必须是对象")
    }
    if let nested = dictionary["root"] {
      let name = dictionary["name"] as? String ?? dictionary["rootName"] as? String ?? fallbackName
      return NBTDocument(rootName: name, root: try decodeTag(nested, path: "$root"))
    }
    let name = dictionary["name"] as? String ?? dictionary["rootName"] as? String ?? fallbackName
    return NBTDocument(rootName: name, root: try decodeTag(dictionary, path: "$"))
  }

  private static func decodeTag(_ object: Any, path: String) throws -> NBTValue {
    guard let dictionary = object as? [String: Any], let rawType = dictionary["type"] as? String
    else {
      return try inferValue(from: object, path: path)
    }
    guard let type = tagType(rawType) else {
      throw MCBEEditorError.malformedData("\(path) 使用了未知 NBT 类型 \(rawType)")
    }
    guard type != .end else {
      throw MCBEEditorError.malformedData("\(path) 不能使用 End 作为实际标签")
    }
    guard let payload = dictionary["value"] else {
      throw MCBEEditorError.malformedData("\(path) 缺少 value")
    }
    return try decodePayload(type: type, payload: payload, path: path)
  }

  private static func decodePayload(type: NBTTagType, payload: Any, path: String) throws -> NBTValue
  {
    switch type {
    case .end:
      throw MCBEEditorError.malformedData("\(path) 的 End 类型没有值")
    case .byte:
      return .byte(
        Int8(try integer(payload, path: path, minimum: Int64(Int8.min), maximum: Int64(Int8.max))))
    case .short:
      return .short(
        Int16(
          try integer(payload, path: path, minimum: Int64(Int16.min), maximum: Int64(Int16.max))))
    case .int:
      return .int(
        Int32(
          try integer(payload, path: path, minimum: Int64(Int32.min), maximum: Int64(Int32.max))))
    case .long:
      return .long(try integer(payload, path: path, minimum: Int64.min, maximum: Int64.max))
    case .float:
      return .float(Float(try floating(payload, path: path)))
    case .double:
      return .double(try floating(payload, path: path))
    case .byteArray:
      guard let values = payload as? [Any] else { throw typeError(path, expected: "整数数组") }
      return .byteArray(
        Data(
          try values.enumerated().map { index, item in
            UInt8(
              bitPattern: Int8(
                try integer(
                  item, path: "\(path)[\(index)]", minimum: Int64(Int8.min),
                  maximum: Int64(Int8.max))))
          }))
    case .string:
      guard let text = payload as? String else { throw typeError(path, expected: "字符串") }
      return .string(text)
    case .compound:
      guard let dictionary = payload as? [String: Any] else {
        throw typeError(path, expected: "对象")
      }
      let tags = try dictionary.keys.sorted().map { key in
        guard let item = dictionary[key] else {
          throw MCBEEditorError.malformedData("\(path).\(key) 在解析期间消失")
        }
        return NBTNamedTag(
          name: key, value: try decodeTag(item, path: "\(path).\(key)"))
      }
      return .compound(tags)
    case .list:
      if let wrapper = payload as? [String: Any], let rawElementType = wrapper["type"] as? String {
        guard let elementType = tagType(rawElementType) else {
          throw MCBEEditorError.malformedData("\(path) 的 List 使用了未知元素类型 \(rawElementType)")
        }
        guard let items = wrapper["value"] as? [Any] else {
          throw typeError(path, expected: "List value 数组")
        }
        if elementType == .end {
          guard items.isEmpty else {
            throw MCBEEditorError.malformedData("\(path) 的非空 List 不能使用 End 元素类型")
          }
          return .list(.end, [])
        }
        let values = try items.enumerated().map { index, item in
          if let tagged = item as? [String: Any], tagged["type"] != nil {
            let value = try decodeTag(tagged, path: "\(path)[\(index)]")
            guard value.type == elementType else {
              throw MCBEEditorError.malformedData("\(path)[\(index)] 类型与 List 元素类型不一致")
            }
            return value
          }
          return try decodePayload(type: elementType, payload: item, path: "\(path)[\(index)]")
        }
        return .list(elementType, values)
      }
      guard let items = payload as? [Any] else { throw typeError(path, expected: "List 对象或数组") }
      if items.isEmpty { return .list(.end, []) }
      let values = try items.enumerated().map {
        try decodeTag($0.element, path: "\(path)[\($0.offset)]")
      }
      guard let elementType = values.first?.type, values.allSatisfy({ $0.type == elementType })
      else {
        throw MCBEEditorError.malformedData("\(path) 的 List 元素类型不一致")
      }
      return .list(elementType, values)
    case .intArray:
      guard let values = payload as? [Any] else { throw typeError(path, expected: "整数数组") }
      return .intArray(
        try values.enumerated().map { index, item in
          Int32(
            try integer(
              item, path: "\(path)[\(index)]", minimum: Int64(Int32.min), maximum: Int64(Int32.max))
          )
        })
    case .longArray:
      guard let values = payload as? [Any] else { throw typeError(path, expected: "长整数数组") }
      return .longArray(
        try values.enumerated().map { index, item in
          try integer(item, path: "\(path)[\(index)]", minimum: Int64.min, maximum: Int64.max)
        })
    }
  }

  private static func inferValue(from object: Any, path: String) throws -> NBTValue {
    if object is NSNull {
      throw MCBEEditorError.malformedData("\(path) 是 null；NBT 没有 null 标签")
    }
    if let text = object as? String { return .string(text) }
    if let number = object as? NSNumber {
      if String(cString: number.objCType) == "c" { return .byte(number.boolValue ? 1 : 0) }
      let double = number.doubleValue
      if double.isFinite, double.rounded() == double {
        if double >= Double(Int32.min), double <= Double(Int32.max) { return .int(Int32(double)) }
        if double >= Double(Int64.min), double <= Double(Int64.max) { return .long(Int64(double)) }
      }
      return .double(double)
    }
    if let dictionary = object as? [String: Any] {
      return .compound(
        try dictionary.keys.sorted().map { key in
          guard let item = dictionary[key] else {
            throw MCBEEditorError.malformedData("\(path).\(key) 在解析期间消失")
          }
          return NBTNamedTag(
            name: key, value: try inferValue(from: item, path: "\(path).\(key)"))
        })
    }
    if let array = object as? [Any] {
      if array.isEmpty { return .list(.end, []) }
      let values = try array.enumerated().map {
        try inferValue(from: $0.element, path: "\(path)[\($0.offset)]")
      }
      guard let type = values.first?.type, values.allSatisfy({ $0.type == type }) else {
        throw MCBEEditorError.malformedData("\(path) 是混合类型 JSON 数组；NBT List 必须使用相同元素类型")
      }
      return .list(type, values)
    }
    throw MCBEEditorError.malformedData("\(path) 包含无法转换为 NBT 的 JSON 值")
  }

  private static func integer(_ object: Any, path: String, minimum: Int64, maximum: Int64) throws
    -> Int64
  {
    let value: Int64?
    if let text = object as? String {
      value = Int64(text)
    } else if let number = object as? NSNumber {
      let double = number.doubleValue
      value = double.rounded() == double ? Int64(exactly: double) : nil
    } else {
      value = nil
    }
    guard let integer = value, integer >= minimum, integer <= maximum else {
      throw typeError(path, expected: "\(minimum)...\(maximum) 的整数")
    }
    return integer
  }

  private static func floating(_ object: Any, path: String) throws -> Double {
    if let number = object as? NSNumber { return number.doubleValue }
    if let text = object as? String, let value = Double(text) { return value }
    throw typeError(path, expected: "数字")
  }

  private static func typeError(_ path: String, expected: String) -> Error {
    MCBEEditorError.malformedData("\(path) 应为\(expected)")
  }

  private static func typeName(_ type: NBTTagType) -> String {
    switch type {
    case .end: return "end"
    case .byte: return "byte"
    case .short: return "short"
    case .int: return "int"
    case .long: return "long"
    case .float: return "float"
    case .double: return "double"
    case .byteArray: return "byteArray"
    case .string: return "string"
    case .list: return "list"
    case .compound: return "compound"
    case .intArray: return "intArray"
    case .longArray: return "longArray"
    }
  }

  private static func tagType(_ value: String) -> NBTTagType? {
    let normalized = value.replacingOccurrences(of: "TAG_", with: "", options: [.caseInsensitive])
      .replacingOccurrences(of: "_", with: "")
      .replacingOccurrences(of: "-", with: "")
      .lowercased()
    switch normalized {
    case "end": return .end
    case "byte": return .byte
    case "short": return .short
    case "int", "integer": return .int
    case "long": return .long
    case "float": return .float
    case "double": return .double
    case "bytearray": return .byteArray
    case "string": return .string
    case "list": return .list
    case "compound", "object": return .compound
    case "intarray", "integerarray": return .intArray
    case "longarray": return .longArray
    default: return nil
    }
  }
}
