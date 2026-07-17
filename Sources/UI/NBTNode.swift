import Foundation

enum NBTPathComponent: Hashable {
    case compound(String)
    case list(Int)
}

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
        guard !path.isEmpty else { return "/" }
        return path.reduce(into: "") { result, component in
            switch component {
            case .compound(let name):
                result += "/\(name)"
            case .list(let index):
                result += "[\(index)]"
            }
        }
    }
}

enum NBTTreeMutation {
    static func value(at path: [NBTPathComponent], in root: NBTValue) -> NBTValue? {
        guard let first = path.first else { return root }
        let tail = Array(path.dropFirst())
        switch (first, root) {
        case (.compound(let name), .compound(let tags)):
            guard let tag = tags.first(where: { $0.name == name }) else { return nil }
            return value(at: tail, in: tag.value)
        case (.list(let index), .list(_, let values)):
            guard values.indices.contains(index) else { return nil }
            return value(at: tail, in: values[index])
        default:
            return nil
        }
    }

    static func replacingValue(at path: [NBTPathComponent], in root: NBTValue, with replacement: NBTValue) throws -> NBTValue {
        guard let first = path.first else { return replacement }
        let tail = Array(path.dropFirst())
        switch (first, root) {
        case (.compound(let name), .compound(var tags)):
            guard let index = tags.firstIndex(where: { $0.name == name }) else {
                throw BlocktopographError.malformedData("NBT 路径不存在：\(name)")
            }
            tags[index].value = try replacingValue(at: tail, in: tags[index].value, with: replacement)
            return .compound(tags)
        case (.list(let index), .list(let type, var values)):
            guard values.indices.contains(index) else {
                throw BlocktopographError.malformedData("NBT 列表索引越界：\(index)")
            }
            if tail.isEmpty, replacement.type != type {
                throw BlocktopographError.malformedData("NBT 列表元素类型不一致")
            }
            values[index] = try replacingValue(at: tail, in: values[index], with: replacement)
            return .list(type, values)
        default:
            throw BlocktopographError.malformedData("NBT 路径与节点类型不匹配")
        }
    }



    static func adding(
        _ value: NBTValue,
        named name: String?,
        to path: [NBTPathComponent],
        in root: NBTValue,
        replacingExisting: Bool = false
    ) throws -> NBTValue {
        if path.isEmpty {
            return try appending(value, named: name, to: root, replacingExisting: replacingExisting)
        }
        guard let container = self.value(at: path, in: root) else {
            throw BlocktopographError.malformedData("NBT 容器路径不存在")
        }
        let replacement = try appending(value, named: name, to: container, replacingExisting: replacingExisting)
        return try replacingValue(at: path, in: root, with: replacement)
    }

    private static func appending(
        _ value: NBTValue,
        named name: String?,
        to container: NBTValue,
        replacingExisting: Bool
    ) throws -> NBTValue {
        switch container {
        case .compound(var tags):
            let cleanName = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanName.isEmpty else {
                throw BlocktopographError.malformedData("Compound 标签名称不能为空")
            }
            if let existingIndex = tags.firstIndex(where: { $0.name == cleanName }) {
                guard replacingExisting else {
                    throw BlocktopographError.malformedData("同级 Compound 已存在标签：\(cleanName)")
                }
                tags[existingIndex].value = value
                return .compound(tags)
            }
            tags.append(NBTNamedTag(name: cleanName, value: value))
            return .compound(tags)
        case .list(let elementType, var values):
            if elementType == .end, values.isEmpty {
                return .list(value.type, [value])
            }
            guard value.type == elementType else {
                throw BlocktopographError.malformedData("List 只能增加 \(elementType.displayName) 元素")
            }
            values.append(value)
            return .list(elementType, values)
        default:
            throw BlocktopographError.unsupported("只能向 Compound 或 List 增加节点")
        }
    }

    static func normalizedDeletionPaths(_ paths: [[NBTPathComponent]]) -> [[NBTPathComponent]] {
        let unique = Array(Set(paths.filter { !$0.isEmpty }))
        return unique.filter { candidate in
            !unique.contains { other in
                guard other.count < candidate.count else { return false }
                return Array(candidate.prefix(other.count)) == other
            }
        }
    }

    static func deleting(at paths: [[NBTPathComponent]], in root: NBTValue) throws -> NBTValue {
        let normalized = normalizedDeletionPaths(paths)
        let ordered = normalized.sorted { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            let lhsParent = Array(lhs.dropLast())
            let rhsParent = Array(rhs.dropLast())
            if lhsParent == rhsParent,
               case .list(let lhsIndex)? = lhs.last,
               case .list(let rhsIndex)? = rhs.last {
                return lhsIndex > rhsIndex
            }
            return pathSortKey(lhs) > pathSortKey(rhs)
        }
        return try ordered.reduce(root) { current, path in
            try deleting(at: path, in: current)
        }
    }

    private static func pathSortKey(_ path: [NBTPathComponent]) -> String {
        path.map { component in
            switch component {
            case .compound(let name): return "c:\(name)"
            case .list(let index): return String(format: "l:%020lld", Int64(index))
            }
        }.joined(separator: "/")
    }

    static func deleting(at path: [NBTPathComponent], in root: NBTValue) throws -> NBTValue {
        guard let last = path.last else {
            throw BlocktopographError.unsupported("不能删除 NBT 根节点")
        }
        let parentPath = Array(path.dropLast())
        guard let parent = value(at: parentPath, in: root) else {
            throw BlocktopographError.malformedData("NBT 父路径不存在")
        }
        let replacement: NBTValue
        switch (last, parent) {
        case (.compound(let name), .compound(var tags)):
            guard let index = tags.firstIndex(where: { $0.name == name }) else {
                throw BlocktopographError.malformedData("NBT 标签不存在：\(name)")
            }
            tags.remove(at: index)
            replacement = .compound(tags)
        case (.list(let index), .list(let type, var values)):
            guard values.indices.contains(index) else {
                throw BlocktopographError.malformedData("NBT 列表索引越界：\(index)")
            }
            values.remove(at: index)
            replacement = .list(type, values)
        default:
            throw BlocktopographError.malformedData("NBT 删除路径与父节点类型不匹配")
        }
        return parentPath.isEmpty ? replacement : try replacingValue(at: parentPath, in: root, with: replacement)
    }

    static func renaming(at path: [NBTPathComponent], to newName: String, in root: NBTValue) throws -> NBTValue {
        guard case .compound(let oldName)? = path.last else {
            throw BlocktopographError.unsupported("只有 Compound 标签可以重命名")
        }
        let cleanName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else {
            throw BlocktopographError.malformedData("新名称不能为空")
        }
        let parentPath = Array(path.dropLast())
        guard case .compound(var tags)? = value(at: parentPath, in: root) else {
            throw BlocktopographError.malformedData("NBT 父 Compound 不存在")
        }
        guard let index = tags.firstIndex(where: { $0.name == oldName }) else {
            throw BlocktopographError.malformedData("NBT 标签不存在：\(oldName)")
        }
        guard oldName == cleanName || !tags.contains(where: { $0.name == cleanName }) else {
            throw BlocktopographError.malformedData("同级 Compound 已存在标签：\(cleanName)")
        }
        tags[index].name = cleanName
        let replacement = NBTValue.compound(tags)
        return parentPath.isEmpty ? replacement : try replacingValue(at: parentPath, in: root, with: replacement)
    }

    static func defaultValue(for type: NBTTagType) throws -> NBTValue {
        switch type {
        case .byte: return .byte(0)
        case .short: return .short(0)
        case .int: return .int(0)
        case .long: return .long(0)
        case .float: return .float(0)
        case .double: return .double(0)
        case .byteArray: return .byteArray(Data())
        case .string: return .string("")
        case .list: return .list(.compound, [])
        case .compound: return .compound([])
        case .intArray: return .intArray([])
        case .longArray: return .longArray([])
        case .end: throw BlocktopographError.unsupported("不能创建 End 标签")
        }
    }

    static func parseInitialValue(_ text: String, type: NBTTagType) throws -> NBTValue {
        switch type {
        case .byte: return try parseScalar(text.isEmpty ? "0" : text, matching: .byte(0))
        case .short: return try parseScalar(text.isEmpty ? "0" : text, matching: .short(0))
        case .int: return try parseScalar(text.isEmpty ? "0" : text, matching: .int(0))
        case .long: return try parseScalar(text.isEmpty ? "0" : text, matching: .long(0))
        case .float: return try parseScalar(text.isEmpty ? "0" : text, matching: .float(0))
        case .double: return try parseScalar(text.isEmpty ? "0" : text, matching: .double(0))
        case .string: return .string(text)
        case .byteArray:
            let values = try parseIntegerList(text, range: Int64(Int8.min)...Int64(Int8.max))
            return .byteArray(Data(values.map { UInt8(bitPattern: Int8($0)) }))
        case .intArray:
            return .intArray(try parseIntegerList(text, range: Int64(Int32.min)...Int64(Int32.max)).map(Int32.init))
        case .longArray:
            return .longArray(try parseIntegerList(text, range: Int64.min...Int64.max))
        case .compound: return .compound([])
        case .list: return .list(.compound, [])
        case .end: throw BlocktopographError.unsupported("不能创建 End 标签")
        }
    }

    private static func parseIntegerList(_ text: String, range: ClosedRange<Int64>) throws -> [Int64] {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { return [] }
        return try clean.split(whereSeparator: { $0 == "," || $0 == " " || $0 == ";" }).map { token in
            guard let value = Int64(token), range.contains(value) else {
                throw BlocktopographError.malformedData("数组中包含无效整数：\(token)")
            }
            return value
        }
    }
    static func parseScalar(_ text: String, matching original: NBTValue) throws -> NBTValue {
        switch original {
        case .byte:
            guard let value = Int8(text) else { throw BlocktopographError.malformedData("请输入 -128…127") }
            return .byte(value)
        case .short:
            guard let value = Int16(text) else { throw BlocktopographError.malformedData("请输入 Int16 数值") }
            return .short(value)
        case .int:
            guard let value = Int32(text) else { throw BlocktopographError.malformedData("请输入 Int32 数值") }
            return .int(value)
        case .long:
            guard let value = Int64(text) else { throw BlocktopographError.malformedData("请输入 Int64 数值") }
            return .long(value)
        case .float:
            guard let value = Float(text) else { throw BlocktopographError.malformedData("请输入浮点数") }
            return .float(value)
        case .double:
            guard let value = Double(text) else { throw BlocktopographError.malformedData("请输入双精度浮点数") }
            return .double(value)
        case .string:
            return .string(text)
        default:
            throw BlocktopographError.unsupported("当前节点不支持文本编辑")
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
        case .string(let value): return value
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
