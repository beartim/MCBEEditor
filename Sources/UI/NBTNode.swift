import Foundation


struct NBTNode {
  let path: [NBTPathComponent]
  let name: String
  let value: NBTValue
  let depth: Int

  var hasChildren: Bool {
    switch value {
    case .compound(let tags): return !tags.isEmpty
    case .list(_, let values): return !values.isEmpty
    default: return false
    }
  }

  var pathDescription: String {
    NBTPathComponent.description(of: path)
  }
}

/// Shared tree projection used by every NBT browser/editor. Keeping traversal
/// and search in one place prevents the different editors from drifting apart
/// and avoids eight copies of the same recursive implementation.
enum NBTTreeRows {
  static func rows(in document: NBTDocument, expanded: Set<[NBTPathComponent]>, query: String) -> [NBTNode] {
    switch document.root {
    case .compound, .list:
      return query.isEmpty ? visibleChildren(of: document.root, expanded: expanded)
        : search(in: document.root, query: query)
    default:
      let root = NBTNode(path: [], name: document.rootName.isEmpty ? "（根标签）" : document.rootName,
                         value: document.root, depth: 0)
      return query.isEmpty || matches(root, query: query) ? [root] : []
    }
  }

  static func visibleChildren(
    of root: NBTValue,
    expanded: Set<[NBTPathComponent]>
  ) -> [NBTNode] {
    var result = [NBTNode]()
    appendChildren(
      of: root,
      parentPath: [],
      depth: 0,
      expanded: expanded,
      to: &result
    )
    return result
  }

  static func search(in root: NBTValue, query rawQuery: String) -> [NBTNode] {
    let query = normalizedQuery(rawQuery)
    guard !query.isEmpty else { return [] }

    var allNodes = [NBTNode]()
    appendChildren(of: root, parentPath: [], depth: 0, expanded: nil, to: &allNodes)

    // Search uses strict fallback priority across the whole tree:
    // 1. tag name; only when there are no name matches,
    // 2. the tag's own scalar/array value; only when there are no value matches,
    // 3. tag type. Paths, parent summaries and child contents are never searched.
    let nameMatches = allNodes.filter {
      $0.name.localizedCaseInsensitiveContains(query)
    }
    if !nameMatches.isEmpty { return nameMatches }

    let valueMatches = allNodes.filter { node in
      directValueMatches(node.value, query: query)
    }
    if !valueMatches.isEmpty { return valueMatches }

    return allNodes.filter {
      $0.value.type.displayName.localizedCaseInsensitiveContains(query)
    }
  }

  static func searchDocuments(_ documents: [NBTDocument], query rawQuery: String) -> [Int] {
    let query = normalizedQuery(rawQuery)
    guard !query.isEmpty else { return Array(documents.indices) }

    let nameMatches = documents.indices.filter {
      documents[$0].rootName.localizedCaseInsensitiveContains(query)
    }
    if !nameMatches.isEmpty { return nameMatches }

    let valueMatches = documents.indices.filter { index in
      directValueMatches(documents[index].root, query: query)
    }
    if !valueMatches.isEmpty { return valueMatches }

    return documents.indices.filter {
      documents[$0].root.type.displayName.localizedCaseInsensitiveContains(query)
    }
  }

  static func matches(_ node: NBTNode, query rawQuery: String) -> Bool {
    let query = normalizedQuery(rawQuery)
    guard !query.isEmpty else { return false }
    if node.name.localizedCaseInsensitiveContains(query) { return true }
    if directValueMatches(node.value, query: query) {
      return true
    }
    return node.value.type.displayName.localizedCaseInsensitiveContains(query)
  }

  private static func directValueMatches(_ value: NBTValue, query: String) -> Bool {
    // Compound and List have no direct value. Their summaries only describe
    // child counts and previously caused unrelated parent rows to match.
    switch value {
    case .byte(let number): return String(number).localizedCaseInsensitiveContains(query)
    case .short(let number): return String(number).localizedCaseInsensitiveContains(query)
    case .int(let number): return String(number).localizedCaseInsensitiveContains(query)
    case .long(let number): return String(number).localizedCaseInsensitiveContains(query)
    case .float(let number): return String(number).localizedCaseInsensitiveContains(query)
    case .double(let number): return String(number).localizedCaseInsensitiveContains(query)
    case .string(let text): return text.localizedCaseInsensitiveContains(query)
    case .byteArray(let data):
      return data.contains {
        String(Int8(bitPattern: $0)).localizedCaseInsensitiveContains(query)
      }
    case .intArray(let values):
      return values.contains { String($0).localizedCaseInsensitiveContains(query) }
    case .longArray(let values):
      return values.contains { String($0).localizedCaseInsensitiveContains(query) }
    case .list, .compound: return false
    }
  }

  private static func normalizedQuery(_ query: String) -> String {
    query.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func appendChildren(
    of value: NBTValue,
    parentPath: [NBTPathComponent],
    depth: Int,
    expanded: Set<[NBTPathComponent]>?,
    to result: inout [NBTNode]
  ) {
    switch value {
    case .compound(let tags):
      var occurrences = [String: Int]()
      for tag in tags {
        let path = parentPath + [NBTPathComponent.child(named: tag.name, occurrences: &occurrences)]
        result.append(NBTNode(path: path, name: tag.name, value: tag.value, depth: depth))
        if expanded?.contains(path) ?? true {
          appendChildren(
            of: tag.value,
            parentPath: path,
            depth: depth + 1,
            expanded: expanded,
            to: &result
          )
        }
      }
    case .list(_, let values):
      for (index, child) in values.enumerated() {
        let path = parentPath + [.list(index)]
        result.append(NBTNode(path: path, name: "[\(index)]", value: child, depth: depth))
        if expanded?.contains(path) ?? true {
          appendChildren(
            of: child,
            parentPath: path,
            depth: depth + 1,
            expanded: expanded,
            to: &result
          )
        }
      }
    default:
      break
    }
  }
}


extension NBTValue {
  var editableText: String? {
    switch self {
    case .byte(let value): return String(value)
    case .short(let value): return String(value)
    case .int(let value): return String(value)
    case .long(let value): return String(value)
    case .float(let value): return String(value)
    case .double(let value): return String(value)
    case .string(let value):
      return NBTRawStringCodec.rawData(in: value) == nil ? value : nil
    case .byteArray(let value):
      return value.map { String(Int8(bitPattern: $0)) }.joined(separator: ", ")
    case .intArray(let values):
      return values.map(String.init).joined(separator: ", ")
    case .longArray(let values):
      return values.map(String.init).joined(separator: ", ")
    case .list, .compound:
      return nil
    }
  }

  var isDirectlyEditable: Bool { editableText != nil }
}
