import Foundation

struct BedrockBlockStateCriterion: Hashable {
    let keyContains: String
    let valueContains: String?
}

struct BedrockBlockSearchCriteria {
    let nameContains: String?
    let stateCriteria: [BedrockBlockStateCriterion]
    let layers: Set<Int>

    var isEmpty: Bool {
        (nameContains?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            && stateCriteria.isEmpty
    }

    func matches(_ state: BedrockBlockState) -> Bool {
        if let nameContains = nameContains?.trimmingCharacters(in: .whitespacesAndNewlines), !nameContains.isEmpty {
            let searchable = BedrockLegacyBlockCatalog.searchText(for: state)
            guard searchable.range(of: nameContains, options: [.caseInsensitive, .diacriticInsensitive]) != nil else {
                return false
            }
        }

        let properties = state.stateProperties
        for criterion in stateCriteria {
            let keyNeedle = criterion.keyContains.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !keyNeedle.isEmpty else { continue }
            let matches = properties.filter {
                $0.0.range(of: keyNeedle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
            guard !matches.isEmpty else { return false }
            if let valueNeedle = criterion.valueContains?.trimmingCharacters(in: .whitespacesAndNewlines), !valueNeedle.isEmpty {
                guard matches.contains(where: {
                    $0.1.range(of: valueNeedle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                }) else { return false }
            }
        }
        return true
    }
}

enum BedrockBlockStateAssignment {
    case value(NBTValue)
    case text(String)
    case delete
}

struct BedrockBlockReplacement {
    let name: String?
    let stateAssignments: [String: BedrockBlockStateAssignment]
    let replaceAllStates: Bool

    init(name: String?, stateAssignments: [String: String], replaceAllStates: Bool) {
        self.name = name
        self.replaceAllStates = replaceAllStates
        self.stateAssignments = stateAssignments.mapValues { value in
            value == "__DELETE__" ? .delete : .text(value)
        }
    }

    init(name: String?, typedStateAssignments: [String: NBTValue], replaceAllStates: Bool) {
        self.name = name
        self.replaceAllStates = replaceAllStates
        self.stateAssignments = typedStateAssignments.mapValues(BedrockBlockStateAssignment.value)
    }

    var isEmpty: Bool {
        (name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            && stateAssignments.isEmpty
            && !replaceAllStates
    }

    func applying(to state: BedrockBlockState) throws -> BedrockBlockState {
        guard case .compound(var rootTags)? = state.nbt else {
            throw BlocktopographError.unsupported("旧版数字 ID 方块不能进行 name/states 搜索替换")
        }

        if let rawReplacementName = name?.trimmingCharacters(in: .whitespacesAndNewlines), !rawReplacementName.isEmpty {
            let replacementName = BedrockLegacyBlockCatalog.blockIdentifier(forRawValue: rawReplacementName) ?? rawReplacementName
            let nameIndex = rootTags.firstIndex { $0.name.caseInsensitiveCompare("name") == .orderedSame }
                ?? rootTags.firstIndex { $0.name.caseInsensitiveCompare("Name") == .orderedSame }
            if let nameIndex = nameIndex {
                rootTags[nameIndex].value = .string(replacementName)
            } else {
                rootTags.append(NBTNamedTag(name: "name", value: .string(replacementName)))
            }
        }

        let statesIndex = rootTags.firstIndex { $0.name.caseInsensitiveCompare("states") == .orderedSame }
        var states: [NBTNamedTag]
        if replaceAllStates {
            states = []
        } else if let statesIndex = statesIndex, case .compound(let current) = rootTags[statesIndex].value {
            states = current
        } else {
            states = []
        }

        for assignment in stateAssignments.sorted(by: { $0.key.localizedStandardCompare($1.key) == .orderedAscending }) {
            let key = assignment.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            switch assignment.value {
            case .delete:
                states.removeAll { $0.name.caseInsensitiveCompare(key) == .orderedSame }
            case .value(let value):
                if let existingIndex = states.firstIndex(where: { $0.name.caseInsensitiveCompare(key) == .orderedSame }) {
                    states[existingIndex].value = value
                } else {
                    states.append(NBTNamedTag(name: key, value: value))
                }
            case .text(let source):
                if let existingIndex = states.firstIndex(where: { $0.name.caseInsensitiveCompare(key) == .orderedSame }) {
                    states[existingIndex].value = try Self.parseValue(source, preserving: states[existingIndex].value)
                } else {
                    states.append(NBTNamedTag(name: key, value: try Self.parseValue(source, preserving: nil)))
                }
            }
        }
        states.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        if let statesIndex = statesIndex {
            rootTags[statesIndex].value = .compound(states)
        } else {
            rootTags.append(NBTNamedTag(name: "states", value: .compound(states)))
        }
        return BedrockBlockState(nbt: .compound(rootTags), legacyID: nil, legacyData: nil)
    }

    private static func parseValue(_ source: String, preserving existing: NBTValue?) throws -> NBTValue {
        let text = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let unquoted: String = {
            guard text.count >= 2 else { return text }
            if (text.hasPrefix("\"") && text.hasSuffix("\"")) || (text.hasPrefix("'") && text.hasSuffix("'")) {
                return String(text.dropFirst().dropLast())
            }
            return text
        }()

        switch existing {
        case .byte:
            if unquoted.caseInsensitiveCompare("true") == .orderedSame { return .byte(1) }
            if unquoted.caseInsensitiveCompare("false") == .orderedSame { return .byte(0) }
            guard let value = Int8(unquoted) else { throw BlocktopographError.malformedData("Byte 状态值无效：\(source)") }
            return .byte(value)
        case .short:
            guard let value = Int16(unquoted) else { throw BlocktopographError.malformedData("Short 状态值无效：\(source)") }
            return .short(value)
        case .int:
            guard let value = Int32(unquoted) else { throw BlocktopographError.malformedData("Int 状态值无效：\(source)") }
            return .int(value)
        case .long:
            guard let value = Int64(unquoted) else { throw BlocktopographError.malformedData("Long 状态值无效：\(source)") }
            return .long(value)
        case .float:
            guard let value = Float(unquoted) else { throw BlocktopographError.malformedData("Float 状态值无效：\(source)") }
            return .float(value)
        case .double:
            guard let value = Double(unquoted) else { throw BlocktopographError.malformedData("Double 状态值无效：\(source)") }
            return .double(value)
        case .string:
            return .string(unquoted)
        default:
            if unquoted.caseInsensitiveCompare("true") == .orderedSame { return .byte(1) }
            if unquoted.caseInsensitiveCompare("false") == .orderedSame { return .byte(0) }
            if let value = Int32(unquoted) { return .int(value) }
            if let value = Double(unquoted), unquoted.contains(".") { return .double(value) }
            return .string(unquoted)
        }
    }
}


struct BedrockBlockSaveResult {
    let block: BedrockBlockRecord
}

extension SubChunkStorage {
    func replacingBlockState(
        x: Int,
        y: Int,
        z: Int,
        with newState: BedrockBlockState
    ) throws -> SubChunkStorage {
        guard (0..<16).contains(x), (0..<16).contains(y), (0..<16).contains(z) else {
            throw BlocktopographError.malformedData("方块局部坐标越界")
        }
        guard let newNBT = newState.nbt else {
            throw BlocktopographError.unsupported("旧版数字 ID 方块不能使用 NBT 调色板编辑器写回")
        }
        let blockIndex = (x << 8) | (z << 4) | y
        guard indices.indices.contains(blockIndex) else {
            throw BlocktopographError.malformedData("方块索引越界")
        }

        let encodedNew = try BedrockNBTCodec.encode(
            NBTDocument(rootName: "", root: newNBT),
            encoding: .littleEndian
        )
        var updatedPalette = palette
        let paletteIndex: UInt16
        if let existing = try updatedPalette.firstIndex(where: { state in
            guard let nbt = state.nbt else { return false }
            let data = try BedrockNBTCodec.encode(
                NBTDocument(rootName: "", root: nbt),
                encoding: .littleEndian
            )
            return data == encodedNew
        }) {
            paletteIndex = UInt16(existing)
        } else {
            guard updatedPalette.count < Int(UInt16.max) else {
                throw BlocktopographError.unsupported("方块调色板条目过多，无法追加新状态")
            }
            paletteIndex = UInt16(updatedPalette.count)
            updatedPalette.append(newState)
        }

        var updatedIndices = indices
        updatedIndices[blockIndex] = paletteIndex
        let updatedBits = try Self.bitsRequired(
            paletteCount: updatedPalette.count,
            preferred: bitsPerBlock
        )
        return SubChunkStorage(
            bitsPerBlock: updatedBits,
            palette: updatedPalette,
            indices: updatedIndices
        )
    }

    private static func bitsRequired(paletteCount: Int, preferred: Int) throws -> Int {
        guard paletteCount > 0 else {
            throw BlocktopographError.malformedData("方块调色板不能为空")
        }
        if paletteCount == 1 { return 0 }
        let allowed = [1, 2, 3, 4, 5, 6, 8, 16]
        if allowed.contains(preferred), (1 << preferred) >= paletteCount { return preferred }
        guard let selected = allowed.first(where: { (1 << $0) >= paletteCount }) else {
            throw BlocktopographError.unsupported("方块调色板大小超出持久化格式范围：\(paletteCount)")
        }
        return selected
    }
}

extension SubChunkStorage {
    static func airFilled(with airState: BedrockBlockState) -> SubChunkStorage {
        SubChunkStorage(
            bitsPerBlock: 0,
            palette: [airState],
            indices: Array(repeating: UInt16(0), count: 4096)
        )
    }
}

extension BedrockSubChunk {
    func replacingBlockState(
        x: Int,
        y: Int,
        z: Int,
        storageIndex: Int,
        with newState: BedrockBlockState
    ) throws -> BedrockSubChunk {
        guard (0..<BedrockBlockRecord.editableLayerCount).contains(storageIndex) else {
            throw BlocktopographError.malformedData("仅支持编辑方块层 0 和层 1")
        }
        guard [UInt8(1), 8, 9].contains(version) else {
            throw BlocktopographError.unsupported("旧版 SubChunk v\(version) 暂不支持方块状态写回")
        }

        var updatedStorages = storages
        let fallbackVersion = updatedStorages
            .flatMap(\.palette)
            .compactMap(\.paletteVersion)
            .first ?? newState.paletteVersion
        let existingAir = updatedStorages
            .flatMap(\.palette)
            .first(where: { $0.isAir && $0.nbt != nil })
        let airState = existingAir ?? .editableAir(version: fallbackVersion)

        while updatedStorages.count <= storageIndex {
            updatedStorages.append(.airFilled(with: airState))
        }
        updatedStorages[storageIndex] = try updatedStorages[storageIndex].replacingBlockState(
            x: x,
            y: y,
            z: z,
            with: newState
        )

        // v1 encodes exactly one storage. Adding layer 1 upgrades the record to
        // v8, which stores an explicit storage count while retaining the same
        // LevelDB key and SubChunk Y supplied by that key.
        let outputVersion: UInt8 = version == 1 && updatedStorages.count > 1 ? 8 : version
        return BedrockSubChunk(
            version: outputVersion,
            yIndex: yIndex,
            storages: updatedStorages,
            trailingData: trailingData
        )
    }

    func encodePersistent() throws -> Data {
        guard [UInt8(1), 8, 9].contains(version) else {
            throw BlocktopographError.unsupported("旧版 SubChunk v\(version) 暂不支持重新编码")
        }
        if version == 1, storages.count != 1 {
            throw BlocktopographError.malformedData("SubChunk v1 必须恰好包含一个 storage")
        }
        guard storages.count <= Int(UInt8.max) else {
            throw BlocktopographError.malformedData("SubChunk storage 数量过多")
        }

        var writer = BinaryWriter()
        writer.writeByte(version)
        if version == 8 || version == 9 {
            writer.writeByte(UInt8(storages.count))
        }
        if version == 9 {
            writer.writeByte(UInt8(bitPattern: yIndex ?? 0))
        }
        for storage in storages {
            try Self.encode(storage: storage, writer: &writer)
        }
        writer.writeData(trailingData)
        return writer.data
    }

    private static func encode(storage: SubChunkStorage, writer: inout BinaryWriter) throws {
        let bits = storage.bitsPerBlock
        let allowed = [0, 1, 2, 3, 4, 5, 6, 8, 16]
        guard allowed.contains(bits) else {
            throw BlocktopographError.malformedData("不支持的每方块位数：\(bits)")
        }
        guard storage.indices.count == 4096 else {
            throw BlocktopographError.malformedData("storage 必须包含 4096 个方块索引")
        }
        guard !storage.palette.isEmpty, storage.palette.count <= Int(Int32.max) else {
            throw BlocktopographError.malformedData("方块调色板大小无效")
        }
        let capacity = bits == 0 ? 1 : (1 << bits)
        guard storage.palette.count <= capacity else {
            throw BlocktopographError.malformedData("调色板大小超过 \(bits) 位索引容量")
        }

        // Persistence palette: low bit is 0. The high seven bits store bits-per-block.
        writer.writeByte(UInt8(bits << 1))
        if bits > 0 {
            let entriesPerWord = 32 / bits
            let wordCount = (4096 + entriesPerWord - 1) / entriesPerWord
            let mask: UInt32 = (UInt32(1) << UInt32(bits)) - 1
            for wordIndex in 0..<wordCount {
                var word: UInt32 = 0
                for slot in 0..<entriesPerWord {
                    let sourceIndex = wordIndex * entriesPerWord + slot
                    guard sourceIndex < storage.indices.count else { break }
                    let paletteIndex = UInt32(storage.indices[sourceIndex])
                    guard paletteIndex < UInt32(storage.palette.count) else {
                        throw BlocktopographError.malformedData("方块调色板索引越界：\(paletteIndex)")
                    }
                    word |= (paletteIndex & mask) << UInt32(slot * bits)
                }
                writer.writeUInt32LE(word)
            }
        }

        writer.writeInt32LE(Int32(storage.palette.count))
        for state in storage.palette {
            guard let nbt = state.nbt else {
                throw BlocktopographError.unsupported("现代持久化调色板不能写入旧版数字 ID 方块")
            }
            writer.writeData(try BedrockNBTCodec.encode(
                NBTDocument(rootName: "", root: nbt),
                encoding: .littleEndian
            ))
        }
    }
}


enum BedrockBlockSearchScope: Int {
    case layer0
    case layer1
    case both

    var displayName: String {
        switch self {
        case .layer0: return "层 0"
        case .layer1: return "层 1"
        case .both: return "层 0 和层 1"
        }
    }
}

/// Coordinate-aware search/replace plan. Search conditions select X/Y/Z cells;
/// replacements are then applied to layer 0 and, optionally, layer 1 at the
/// same cells rather than treating the two storages as unrelated scans.
struct BedrockCoordinatedBlockOperation {
    let searchLayer0: BedrockBlockSearchCriteria?
    let searchLayer1: BedrockBlockSearchCriteria?
    let searchScope: BedrockBlockSearchScope
    let layer0Replacement: BedrockBlockReplacement
    let changeLayer1: Bool
    let layer1Replacement: BedrockBlockReplacement?

    var confirmationText: String {
        let searchText: String
        if searchLayer0 != nil && searchLayer1 != nil {
            searchText = "同一坐标的层 0 与层 1 必须分别满足两列搜索条件。"
        } else {
            searchText = "使用已填写的一列条件，在\(searchScope.displayName)中查找；选择两层时任意一层匹配即可。"
        }
        let layer1Text: String
        if !changeLayer1 {
            layer1Text = "只改变层 0，层 1 保持原样。"
        } else if layer1Replacement == nil {
            layer1Text = "同时改变层 1，层 1 留空时删除匹配位置的原层 1。"
        } else {
            layer1Text = "同时按层 1 替换栏写入层 1。"
        }
        return searchText + " " + layer1Text
    }

    func matches(layer0: BedrockBlockState, layer1: BedrockBlockState) -> Bool {
        if let criteria0 = searchLayer0, let criteria1 = searchLayer1 {
            return criteria0.matches(layer0) && criteria1.matches(layer1)
        }
        guard let single = searchLayer0 ?? searchLayer1 else { return false }
        switch searchScope {
        case .layer0:
            return single.matches(layer0)
        case .layer1:
            return single.matches(layer1)
        case .both:
            return single.matches(layer0) || single.matches(layer1)
        }
    }
}

struct BedrockLayerBlockOperation {
    let layer: Int
    let criteria: BedrockBlockSearchCriteria
    let replacement: BedrockBlockReplacement
}

struct BedrockSubChunkReplaceResult {
    let subChunk: BedrockSubChunk
    let matchedBlockCount: Int
}

extension SubChunkStorage {
    func replacingMatchingBlocks(
        criteria: BedrockBlockSearchCriteria,
        replacement: BedrockBlockReplacement
    ) throws -> (storage: SubChunkStorage, matchedBlockCount: Int) {
        var updatedPalette = palette
        var paletteMapping = [UInt16: UInt16]()
        var matchingPaletteIndexes = Set<UInt16>()

        for paletteIndex in palette.indices {
            let source = palette[paletteIndex]
            guard criteria.matches(source) else { continue }
            let replacementState = try replacement.applying(to: source)
            let encodedReplacement = try Self.encodedState(replacementState)
            let targetIndex: UInt16
            if let existing = try updatedPalette.firstIndex(where: { candidate in
                try Self.encodedState(candidate) == encodedReplacement
            }) {
                targetIndex = UInt16(existing)
            } else {
                guard updatedPalette.count < Int(UInt16.max) else {
                    throw BlocktopographError.unsupported("方块调色板条目过多，无法追加替换状态")
                }
                targetIndex = UInt16(updatedPalette.count)
                updatedPalette.append(replacementState)
            }
            let sourceIndex = UInt16(paletteIndex)
            paletteMapping[sourceIndex] = targetIndex
            matchingPaletteIndexes.insert(sourceIndex)
        }

        guard !paletteMapping.isEmpty else { return (self, 0) }
        var updatedIndices = indices
        var matched = 0
        for index in updatedIndices.indices {
            let source = updatedIndices[index]
            guard matchingPaletteIndexes.contains(source), let target = paletteMapping[source] else { continue }
            updatedIndices[index] = target
            matched += 1
        }
        guard matched > 0 else { return (self, 0) }
        let updatedBits = try Self.bitsRequired(paletteCount: updatedPalette.count, preferred: bitsPerBlock)
        return (
            SubChunkStorage(bitsPerBlock: updatedBits, palette: updatedPalette, indices: updatedIndices),
            matched
        )
    }

    private static func encodedState(_ state: BedrockBlockState) throws -> Data {
        guard let nbt = state.nbt else {
            throw BlocktopographError.unsupported("旧版数字 ID 方块不能进行调色板搜索替换")
        }
        return try BedrockNBTCodec.encode(
            NBTDocument(rootName: "", root: nbt),
            encoding: .littleEndian
        )
    }
}

extension SubChunkStorage {
    fileprivate func state(atLinearIndex index: Int) -> BedrockBlockState? {
        guard indices.indices.contains(index) else { return nil }
        let paletteIndex = Int(indices[index])
        guard palette.indices.contains(paletteIndex) else { return nil }
        return palette[paletteIndex]
    }

    fileprivate var isEntirelyAir: Bool {
        indices.allSatisfy { rawIndex in
            let paletteIndex = Int(rawIndex)
            return palette.indices.contains(paletteIndex) && palette[paletteIndex].isAir
        }
    }

    fileprivate func replacingBlocks(
        atLinearIndices targetIndices: Set<Int>,
        replacement: BedrockBlockReplacement
    ) throws -> SubChunkStorage {
        try replacingBlocks(atLinearIndices: targetIndices) { source in
            try replacement.applying(to: source)
        }
    }

    fileprivate func replacingBlocks(
        atLinearIndices targetIndices: Set<Int>,
        with constantState: BedrockBlockState
    ) throws -> SubChunkStorage {
        try replacingBlocks(atLinearIndices: targetIndices) { _ in constantState }
    }

    private func replacingBlocks(
        atLinearIndices targetIndices: Set<Int>,
        transform: (BedrockBlockState) throws -> BedrockBlockState
    ) throws -> SubChunkStorage {
        guard !targetIndices.isEmpty else { return self }
        var updatedPalette = palette
        var updatedIndices = indices
        var paletteMapping = [UInt16: UInt16]()

        for blockIndex in targetIndices.sorted() {
            guard updatedIndices.indices.contains(blockIndex) else { continue }
            let sourceIndex = updatedIndices[blockIndex]
            let targetIndex: UInt16
            if let cached = paletteMapping[sourceIndex] {
                targetIndex = cached
            } else {
                let sourcePaletteIndex = Int(sourceIndex)
                guard palette.indices.contains(sourcePaletteIndex) else {
                    throw BlocktopographError.malformedData("方块调色板索引越界：\(sourceIndex)")
                }
                let replacementState = try transform(palette[sourcePaletteIndex])
                let encodedReplacement = try Self.encodedState(replacementState)
                if let existing = try updatedPalette.firstIndex(where: { candidate in
                    try Self.encodedState(candidate) == encodedReplacement
                }) {
                    targetIndex = UInt16(existing)
                } else {
                    guard updatedPalette.count < Int(UInt16.max) else {
                        throw BlocktopographError.unsupported("方块调色板条目过多，无法追加替换状态")
                    }
                    targetIndex = UInt16(updatedPalette.count)
                    updatedPalette.append(replacementState)
                }
                paletteMapping[sourceIndex] = targetIndex
            }
            updatedIndices[blockIndex] = targetIndex
        }

        let updatedBits = try Self.bitsRequired(paletteCount: updatedPalette.count, preferred: bitsPerBlock)
        return SubChunkStorage(bitsPerBlock: updatedBits, palette: updatedPalette, indices: updatedIndices)
    }
}

extension BedrockSubChunk {
    func replacingBlocks(
        criteria: BedrockBlockSearchCriteria,
        replacement: BedrockBlockReplacement
    ) throws -> BedrockSubChunkReplaceResult {
        let operations = criteria.layers.sorted().map { layer in
            BedrockLayerBlockOperation(
                layer: layer,
                criteria: BedrockBlockSearchCriteria(
                    nameContains: criteria.nameContains,
                    stateCriteria: criteria.stateCriteria,
                    layers: [layer]
                ),
                replacement: replacement
            )
        }
        return try replacingBlocks(operations: operations)
    }

    func replacingBlocks(
        coordinatedOperation operation: BedrockCoordinatedBlockOperation
    ) throws -> BedrockSubChunkReplaceResult {
        guard [UInt8(1), 8, 9].contains(version) else {
            throw BlocktopographError.unsupported("旧版 SubChunk v\(version) 暂不支持区块搜索替换")
        }

        var updatedStorages = storages
        let fallbackVersion = updatedStorages.flatMap(\.palette).compactMap(\.paletteVersion).first
        let existingAir = updatedStorages.flatMap(\.palette).first(where: { $0.isAir && $0.nbt != nil })
        let airState = existingAir ?? .editableAir(version: fallbackVersion)
        while updatedStorages.isEmpty { updatedStorages.append(.airFilled(with: airState)) }

        let layer0Storage = updatedStorages[0]
        let layer1Storage = updatedStorages.count > 1
            ? updatedStorages[1]
            : SubChunkStorage.airFilled(with: airState)
        var matches = Set<Int>()
        matches.reserveCapacity(256)
        for blockIndex in 0..<4096 {
            guard let layer0State = layer0Storage.state(atLinearIndex: blockIndex),
                  let layer1State = layer1Storage.state(atLinearIndex: blockIndex) else { continue }
            if operation.matches(layer0: layer0State, layer1: layer1State) {
                matches.insert(blockIndex)
            }
        }
        guard !matches.isEmpty else {
            return BedrockSubChunkReplaceResult(subChunk: self, matchedBlockCount: 0)
        }

        updatedStorages[0] = try updatedStorages[0].replacingBlocks(
            atLinearIndices: matches,
            replacement: operation.layer0Replacement
        )

        if operation.changeLayer1 {
            if let layer1Replacement = operation.layer1Replacement {
                while updatedStorages.count <= 1 {
                    updatedStorages.append(.airFilled(with: airState))
                }
                updatedStorages[1] = try updatedStorages[1].replacingBlocks(
                    atLinearIndices: matches,
                    replacement: layer1Replacement
                )
            } else if updatedStorages.count > 1 {
                updatedStorages[1] = try updatedStorages[1].replacingBlocks(
                    atLinearIndices: matches,
                    with: airState
                )
                // If layer 1 was the final storage and every cell is now air,
                // remove it entirely so worlds that did not need a second
                // storage remain single-layer.
                while updatedStorages.count > 1, updatedStorages.last?.isEntirelyAir == true {
                    updatedStorages.removeLast()
                }
            }
        }

        let outputVersion: UInt8 = version == 1 && updatedStorages.count > 1 ? 8 : version
        return BedrockSubChunkReplaceResult(
            subChunk: BedrockSubChunk(
                version: outputVersion,
                yIndex: yIndex,
                storages: updatedStorages,
                trailingData: trailingData
            ),
            matchedBlockCount: matches.count
        )
    }

    func replacingBlocks(operations: [BedrockLayerBlockOperation]) throws -> BedrockSubChunkReplaceResult {
        guard [UInt8(1), 8, 9].contains(version) else {
            throw BlocktopographError.unsupported("旧版 SubChunk v\(version) 暂不支持区块搜索替换")
        }

        var updatedStorages = storages
        var matched = 0
        let fallbackVersion = updatedStorages.flatMap(\.palette).compactMap(\.paletteVersion).first
        let existingAir = updatedStorages.flatMap(\.palette).first(where: { $0.isAir && $0.nbt != nil })
        let airState = existingAir ?? .editableAir(version: fallbackVersion)

        for operation in operations.sorted(by: { $0.layer < $1.layer }) {
            let layer = operation.layer
            guard (0..<BedrockBlockRecord.editableLayerCount).contains(layer) else { continue }
            while updatedStorages.count <= layer {
                updatedStorages.append(.airFilled(with: airState))
            }
            let result = try updatedStorages[layer].replacingMatchingBlocks(
                criteria: operation.criteria,
                replacement: operation.replacement
            )
            updatedStorages[layer] = result.storage
            matched += result.matchedBlockCount
        }

        guard matched > 0 else { return BedrockSubChunkReplaceResult(subChunk: self, matchedBlockCount: 0) }
        let outputVersion: UInt8 = version == 1 && updatedStorages.count > 1 ? 8 : version
        return BedrockSubChunkReplaceResult(
            subChunk: BedrockSubChunk(
                version: outputVersion,
                yIndex: yIndex,
                storages: updatedStorages,
                trailingData: trailingData
            ),
            matchedBlockCount: matched
        )
    }
}

struct BedrockSubChunkBulkEditResult {
    let subChunk: BedrockSubChunk
    let affectedBlockCount: Int
    let changed: Bool
}

extension BedrockSubChunk {
    /// Replaces the selected layer for every eligible cell in this existing
    /// SubChunk. Missing layer 1 is represented as air and created on demand.
    func bulkReplacingLayer(
        _ layer: Int,
        replacement: BedrockBlockReplacement,
        includeCompletelyAirCells: Bool,
        localXRange: ClosedRange<Int> = 0...15,
        localZRange: ClosedRange<Int> = 0...15
    ) throws -> BedrockSubChunkBulkEditResult {
        guard (0..<BedrockBlockRecord.editableLayerCount).contains(layer) else {
            throw BlocktopographError.malformedData("只支持层 0 和层 1")
        }
        guard [UInt8(1), 8, 9].contains(version) else {
            throw BlocktopographError.unsupported("旧版 SubChunk v\(version) 暂不支持批量层替换")
        }

        var updatedStorages = storages
        let fallbackVersion = updatedStorages.flatMap(\.palette).compactMap(\.paletteVersion).first
        let existingAir = updatedStorages.flatMap(\.palette).first(where: { $0.isAir && $0.nbt != nil })
        let airState = existingAir ?? .editableAir(version: fallbackVersion)
        while updatedStorages.isEmpty { updatedStorages.append(.airFilled(with: airState)) }

        let layer0 = updatedStorages[0]
        let layer1 = updatedStorages.count > 1 ? updatedStorages[1] : .airFilled(with: airState)
        let safeX = max(0, localXRange.lowerBound)...min(15, localXRange.upperBound)
        let safeZ = max(0, localZRange.lowerBound)...min(15, localZRange.upperBound)
        var targets = Set<Int>()
        targets.reserveCapacity(max(0, safeX.count * safeZ.count * 16))
        for x in safeX {
            for z in safeZ {
                for y in 0..<16 {
                    let index = (x << 8) | (z << 4) | y
                    guard let state0 = layer0.state(atLinearIndex: index),
                          let state1 = layer1.state(atLinearIndex: index) else { continue }
                    if includeCompletelyAirCells || !state0.isAir || !state1.isAir {
                        targets.insert(index)
                    }
                }
            }
        }
        guard !targets.isEmpty else {
            return BedrockSubChunkBulkEditResult(subChunk: self, affectedBlockCount: 0, changed: false)
        }

        while updatedStorages.count <= layer { updatedStorages.append(.airFilled(with: airState)) }
        updatedStorages[layer] = try updatedStorages[layer].replacingBlocks(
            atLinearIndices: targets,
            replacement: replacement
        )
        let outputVersion: UInt8 = version == 1 && updatedStorages.count > 1 ? 8 : version
        return BedrockSubChunkBulkEditResult(
            subChunk: BedrockSubChunk(version: outputVersion, yIndex: yIndex, storages: updatedStorages, trailingData: trailingData),
            affectedBlockCount: targets.count,
            changed: true
        )
    }

    /// Clears one complete storage layer. Layer 0 is mandatory in the format,
    /// so it is filled with air. Layer 1 is removed when it is the final
    /// storage; otherwise it is filled with air to preserve higher storage
    /// indexes.
    func clearingLayer(_ layer: Int) throws -> BedrockSubChunkBulkEditResult {
        guard (0..<BedrockBlockRecord.editableLayerCount).contains(layer) else {
            throw BlocktopographError.malformedData("只支持层 0 和层 1")
        }
        guard [UInt8(1), 8, 9].contains(version) else {
            throw BlocktopographError.unsupported("旧版 SubChunk v\(version) 暂不支持清空方块层")
        }
        var updatedStorages = storages
        let fallbackVersion = updatedStorages.flatMap(\.palette).compactMap(\.paletteVersion).first
        let existingAir = updatedStorages.flatMap(\.palette).first(where: { $0.isAir && $0.nbt != nil })
        let airState = existingAir ?? .editableAir(version: fallbackVersion)

        if layer == 0 {
            while updatedStorages.isEmpty { updatedStorages.append(.airFilled(with: airState)) }
            updatedStorages[0] = .airFilled(with: airState)
        } else {
            guard updatedStorages.count > 1 else {
                return BedrockSubChunkBulkEditResult(subChunk: self, affectedBlockCount: 0, changed: false)
            }
            if updatedStorages.count == 2 {
                updatedStorages.removeLast()
            } else {
                updatedStorages[1] = .airFilled(with: airState)
            }
        }
        let outputVersion: UInt8 = version == 1 && updatedStorages.count > 1 ? 8 : version
        return BedrockSubChunkBulkEditResult(
            subChunk: BedrockSubChunk(version: outputVersion, yIndex: yIndex, storages: updatedStorages, trailingData: trailingData),
            affectedBlockCount: 4096,
            changed: true
        )
    }
}

final class BedrockBlockNBTStore {
    private let session: WorldSession

    init(session: WorldSession) {
        self.session = session
    }

    func save(
        block: BedrockBlockRecord,
        storageIndex: Int,
        document: NBTDocument
    ) throws -> BedrockBlockSaveResult {
        guard document.root.type == .compound else {
            throw BlocktopographError.malformedData("方块状态 NBT 根节点必须是 Compound")
        }
        let chunkX = MapCoordinate.chunk(fromBlock: block.x)
        let chunkZ = MapCoordinate.chunk(fromBlock: block.z)
        let subChunkY = Int8(floorDiv16(block.y))
        let localX = Int(block.x - MapCoordinate.blockOrigin(ofChunk: chunkX))
        let localZ = Int(block.z - MapCoordinate.blockOrigin(ofChunk: chunkZ))
        let localY = Int(block.y) - Int(subChunkY) * 16
        let key = BedrockDBKey.subChunk(
            x: chunkX,
            z: chunkZ,
            dimension: block.dimension,
            index: subChunkY
        )
        let database = try session.database()
        guard let raw = try database.get(key) else {
            throw BlocktopographError.unsupported("目标 SubChunk 尚未生成，不能写入方块状态")
        }
        let decoded = try BedrockSubChunk.decode(raw, keyYIndex: subChunkY)
        let replacement = BedrockBlockState(nbt: document.root, legacyID: nil, legacyData: nil)
        let updated = try decoded.replacingBlockState(
            x: localX,
            y: localY,
            z: localZ,
            storageIndex: storageIndex,
            with: replacement
        )
        try database.put(try updated.encodePersistent(), for: key, sync: true)

        var layers = block.layers
        let fallbackVersion = layers.compactMap(\.paletteVersion).first ?? replacement.paletteVersion
        while layers.count <= storageIndex {
            layers.append(.editableAir(version: fallbackVersion))
        }
        layers[storageIndex] = replacement
        return BedrockBlockSaveResult(
            block: BedrockBlockRecord(
                x: block.x,
                y: block.y,
                z: block.z,
                dimension: block.dimension,
                layers: layers,
                isGenerated: true
            )
        )
    }

    private func floorDiv16(_ y: Int32) -> Int32 {
        if y >= 0 { return y / 16 }
        return (y - 15) / 16
    }

}

// MARK: - Rectangular map-region edits

extension SubChunkStorage {
    fileprivate func replacingBlockStates(atLinearIndices replacements: [Int: BedrockBlockState]) throws -> SubChunkStorage {
        guard !replacements.isEmpty else { return self }
        var updatedPalette = palette
        var updatedIndices = indices
        var encodedLookup = [Data: UInt16]()
        for index in updatedPalette.indices {
            guard let nbt = updatedPalette[index].nbt else { continue }
            let encoded = try BedrockNBTCodec.encode(NBTDocument(rootName: "", root: nbt), encoding: .littleEndian)
            encodedLookup[encoded] = UInt16(index)
        }
        for (linearIndex, state) in replacements.sorted(by: { $0.key < $1.key }) {
            guard updatedIndices.indices.contains(linearIndex) else { continue }
            guard let nbt = state.nbt else {
                throw BlocktopographError.unsupported("旧版数字 ID 方块不能复制到现代区域")
            }
            let encoded = try BedrockNBTCodec.encode(NBTDocument(rootName: "", root: nbt), encoding: .littleEndian)
            let paletteIndex: UInt16
            if let existing = encodedLookup[encoded] {
                paletteIndex = existing
            } else {
                guard updatedPalette.count < Int(UInt16.max) else {
                    throw BlocktopographError.unsupported("方块调色板条目过多，无法复制区域")
                }
                paletteIndex = UInt16(updatedPalette.count)
                updatedPalette.append(state)
                encodedLookup[encoded] = paletteIndex
            }
            updatedIndices[linearIndex] = paletteIndex
        }
        let updatedBits = try Self.bitsRequired(paletteCount: updatedPalette.count, preferred: bitsPerBlock)
        return SubChunkStorage(bitsPerBlock: updatedBits, palette: updatedPalette, indices: updatedIndices)
    }
}

extension BedrockSubChunk {
    func replacingBlocks(
        coordinatedOperation operation: BedrockCoordinatedBlockOperation,
        localXRange: ClosedRange<Int>,
        localZRange: ClosedRange<Int>
    ) throws -> BedrockSubChunkReplaceResult {
        guard [UInt8(1), 8, 9].contains(version) else {
            throw BlocktopographError.unsupported("旧版 SubChunk v\(version) 暂不支持区域搜索替换")
        }
        var updatedStorages = storages
        let fallbackVersion = updatedStorages.flatMap(\.palette).compactMap(\.paletteVersion).first
        let existingAir = updatedStorages.flatMap(\.palette).first(where: { $0.isAir && $0.nbt != nil })
        let airState = existingAir ?? .editableAir(version: fallbackVersion)
        while updatedStorages.isEmpty { updatedStorages.append(.airFilled(with: airState)) }
        let layer0 = updatedStorages[0]
        let layer1 = updatedStorages.count > 1 ? updatedStorages[1] : .airFilled(with: airState)
        var matches = Set<Int>()
        for x in localXRange where (0..<16).contains(x) {
            for z in localZRange where (0..<16).contains(z) {
                for y in 0..<16 {
                    let index = (x << 8) | (z << 4) | y
                    guard let state0 = layer0.state(atLinearIndex: index),
                          let state1 = layer1.state(atLinearIndex: index) else { continue }
                    if operation.matches(layer0: state0, layer1: state1) { matches.insert(index) }
                }
            }
        }
        guard !matches.isEmpty else { return BedrockSubChunkReplaceResult(subChunk: self, matchedBlockCount: 0) }
        updatedStorages[0] = try updatedStorages[0].replacingBlocks(atLinearIndices: matches, replacement: operation.layer0Replacement)
        if operation.changeLayer1 {
            if let replacement = operation.layer1Replacement {
                while updatedStorages.count <= 1 { updatedStorages.append(.airFilled(with: airState)) }
                updatedStorages[1] = try updatedStorages[1].replacingBlocks(atLinearIndices: matches, replacement: replacement)
            } else if updatedStorages.count > 1 {
                updatedStorages[1] = try updatedStorages[1].replacingBlocks(atLinearIndices: matches, with: airState)
                while updatedStorages.count > 1, updatedStorages.last?.isEntirelyAir == true { updatedStorages.removeLast() }
            }
        }
        let outputVersion: UInt8 = version == 1 && updatedStorages.count > 1 ? 8 : version
        return BedrockSubChunkReplaceResult(
            subChunk: BedrockSubChunk(version: outputVersion, yIndex: yIndex, storages: updatedStorages, trailingData: trailingData),
            matchedBlockCount: matches.count
        )
    }

    func replacingBlockStates(_ replacementsByLayer: [Int: [Int: BedrockBlockState]]) throws -> BedrockSubChunk {
        guard [UInt8(1), 8, 9].contains(version) else {
            throw BlocktopographError.unsupported("旧版 SubChunk v\(version) 暂不支持区域复制")
        }
        guard !replacementsByLayer.isEmpty else { return self }
        var updatedStorages = storages
        let replacementStates = replacementsByLayer.values.flatMap { $0.values }
        let fallbackVersion = updatedStorages.flatMap(\.palette).compactMap(\.paletteVersion).first
            ?? replacementStates.compactMap(\.paletteVersion).first
        let existingAir = updatedStorages.flatMap(\.palette).first(where: { $0.isAir && $0.nbt != nil })
        let airState = existingAir ?? .editableAir(version: fallbackVersion)
        for layer in replacementsByLayer.keys.sorted() {
            guard (0..<BedrockBlockRecord.editableLayerCount).contains(layer),
                  let replacements = replacementsByLayer[layer], !replacements.isEmpty else { continue }
            while updatedStorages.count <= layer { updatedStorages.append(.airFilled(with: airState)) }
            updatedStorages[layer] = try updatedStorages[layer].replacingBlockStates(atLinearIndices: replacements)
        }
        let outputVersion: UInt8 = version == 1 && updatedStorages.count > 1 ? 8 : version
        return BedrockSubChunk(version: outputVersion, yIndex: yIndex, storages: updatedStorages, trailingData: trailingData)
    }
}

struct BedrockSubChunkSearchMatch {
    let localX: Int
    let localY: Int
    let localZ: Int
    let layer0: BedrockBlockState
    let layer1: BedrockBlockState
    let matchedLayers: [Int]
}

extension BedrockSubChunk {
    func matchingBlocks(
        coordinatedOperation operation: BedrockCoordinatedBlockOperation,
        localXRange: ClosedRange<Int> = 0...15,
        localZRange: ClosedRange<Int> = 0...15
    ) throws -> [BedrockSubChunkSearchMatch] {
        guard [UInt8(1), 8, 9].contains(version) else {
            throw BlocktopographError.unsupported("旧版 SubChunk v\(version) 暂不支持方块搜索")
        }
        let fallbackVersion = storages.flatMap(\.palette).compactMap(\.paletteVersion).first
        let existingAir = storages.flatMap(\.palette).first(where: { $0.isAir && $0.nbt != nil })
        let airState = existingAir ?? .editableAir(version: fallbackVersion)
        let layer0 = storages.indices.contains(0) ? storages[0] : .airFilled(with: airState)
        let layer1 = storages.indices.contains(1) ? storages[1] : .airFilled(with: airState)
        var result = [BedrockSubChunkSearchMatch]()
        result.reserveCapacity(128)

        for x in localXRange where (0..<16).contains(x) {
            for z in localZRange where (0..<16).contains(z) {
                for y in 0..<16 {
                    let index = (x << 8) | (z << 4) | y
                    guard let state0 = layer0.state(atLinearIndex: index),
                          let state1 = layer1.state(atLinearIndex: index),
                          operation.matches(layer0: state0, layer1: state1) else { continue }
                    var matchedLayers = [Int]()
                    if let criteria0 = operation.searchLayer0, criteria0.matches(state0) { matchedLayers.append(0) }
                    if let criteria1 = operation.searchLayer1, criteria1.matches(state1) { matchedLayers.append(1) }
                    if operation.searchLayer0 == nil || operation.searchLayer1 == nil {
                        let single = operation.searchLayer0 ?? operation.searchLayer1
                        switch operation.searchScope {
                        case .layer0:
                            matchedLayers = single?.matches(state0) == true ? [0] : []
                        case .layer1:
                            matchedLayers = single?.matches(state1) == true ? [1] : []
                        case .both:
                            matchedLayers = []
                            if single?.matches(state0) == true { matchedLayers.append(0) }
                            if single?.matches(state1) == true { matchedLayers.append(1) }
                        }
                    }
                    result.append(BedrockSubChunkSearchMatch(
                        localX: x, localY: y, localZ: z,
                        layer0: state0, layer1: state1,
                        matchedLayers: matchedLayers
                    ))
                }
            }
        }
        return result
    }
}
