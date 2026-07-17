import Foundation

struct WorldCommandExecutionResult {
    let message: String
    let changedWorld: Bool
}

final class WorldCommandExecutor {
    private let session: WorldSession

    init(session: WorldSession) {
        self.session = session
    }

    func execute(_ command: ParsedWorldCommand, dimension: Int32) throws -> WorldCommandExecutionResult {
        switch command {
        case .help(let target):
            return WorldCommandExecutionResult(message: WorldCommandParser.helpText(for: target), changedWorld: false)
        case .clear(let uniqueID):
            let message = try clearPlayerItems(uniqueID: uniqueID)
            session.invalidateAfterExternalChange()
            return WorldCommandExecutionResult(message: message, changedWorld: true)
        case .clearSpawnPoint(let uniqueID):
            let message = try clearPlayerSpawnPoint(uniqueID: uniqueID)
            session.invalidateAfterExternalChange()
            return WorldCommandExecutionResult(message: message, changedWorld: true)
        case .clone(let source, let destination):
            let result = try CommandBlockStore(session: session, dimension: dimension).clone(source: source, destination: destination)
            session.invalidateAfterExternalChange()
            return WorldCommandExecutionResult(message: result, changedWorld: true)
        case .fill(let region, let layer0, let layer1):
            let result = try CommandBlockStore(session: session, dimension: dimension).fill(region: region, layer0: layer0, layer1: layer1)
            session.invalidateAfterExternalChange()
            return WorldCommandExecutionResult(message: result, changedWorld: true)
        }
    }

    private func clearPlayerItems(uniqueID: Int64?) throws -> String {
        let store = PlayerNBTStore(session: session)
        let record = try resolvePlayer(uniqueID: uniqueID, records: store.records())
        let mutation = clearItemContainers(in: record.document.root)
        guard mutation.containerCount > 0 else {
            throw BlocktopographError.unsupported("玩家 \(record.displayName) 的 NBT 中没有可清除的物品容器")
        }
        var document = record.document
        document.root = mutation.value
        try store.save(record: record, document: document)
        return "已清除玩家 \(record.displayName)（\(playerIdentity(record))）的 \(mutation.itemCount) 个物品条目；处理 \(mutation.containerCount) 个物品容器。"
    }

    private func clearPlayerSpawnPoint(uniqueID: Int64?) throws -> String {
        let store = PlayerNBTStore(session: session)
        let record = try resolvePlayer(uniqueID: uniqueID, records: store.records())
        let mutation = removeSpawnTags(in: record.document.root)
        guard mutation.removedCount > 0 else {
            throw BlocktopographError.unsupported("玩家 \(record.displayName) 当前没有可清除的出生点标签")
        }
        var document = record.document
        document.root = mutation.value
        try store.save(record: record, document: document)
        return "已清除玩家 \(record.displayName)（\(playerIdentity(record))）的出生点；移除 \(mutation.removedCount) 个相关标签。"
    }

    private func resolvePlayer(uniqueID: Int64?, records: [PlayerNBTRecord]) throws -> PlayerNBTRecord {
        if let uniqueID = uniqueID {
            let matches = records.filter { playerUniqueID($0) == uniqueID }
            guard matches.count == 1, let record = matches.first else {
                if matches.isEmpty {
                    throw BlocktopographError.unsupported("没有找到 UniqueID 为 \(uniqueID) 的本地或在线玩家")
                }
                throw BlocktopographError.malformedData("UniqueID \(uniqueID) 对应多个玩家记录，无法安全修改")
            }
            return record
        }
        if let local = records.first(where: { $0.keyText == "~local_player" })
            ?? records.first(where: { $0.keyText == "LocalPlayer" }) {
            return local
        }
        throw BlocktopographError.unsupported("世界中没有本地玩家记录")
    }

    private func playerIdentity(_ record: PlayerNBTRecord) -> String {
        playerUniqueID(record).map { "UniqueID \($0)" } ?? record.keyText
    }

    private func playerUniqueID(_ record: PlayerNBTRecord) -> Int64? {
        if let value = numericTag(in: record.document.root, names: ["UniqueID", "UniqueId", "uniqueID", "uniqueId"]) {
            return value
        }
        let prefixes = ["player_server_", "player_"]
        for prefix in prefixes where record.keyText.hasPrefix(prefix) {
            if let value = Int64(record.keyText.dropFirst(prefix.count)) { return value }
        }
        return nil
    }

    private func numericTag(in value: NBTValue, names: Set<String>) -> Int64? {
        guard case .compound(let tags) = value else { return nil }
        for tag in tags where names.contains(tag.name) {
            if let number = numericValue(tag.value) { return number }
        }
        return nil
    }

    private func numericValue(_ value: NBTValue) -> Int64? {
        switch value {
        case .byte(let number): return Int64(number)
        case .short(let number): return Int64(number)
        case .int(let number): return Int64(number)
        case .long(let number): return number
        case .float(let number): return number.isFinite ? Int64(number) : nil
        case .double(let number): return number.isFinite ? Int64(number) : nil
        default: return nil
        }
    }

    private func clearItemContainers(in value: NBTValue) -> (value: NBTValue, itemCount: Int, containerCount: Int) {
        let names: Set<String> = [
            "inventory", "armor", "offhand", "mainhand", "hand", "hotbar",
            "playerinventory", "armorinventory", "offhandinventory"
        ]
        switch value {
        case .compound(var tags):
            var itemCount = 0
            var containerCount = 0
            for index in tags.indices {
                if names.contains(normalized(tags[index].name)) {
                    switch tags[index].value {
                    case .list(let type, let values):
                        itemCount += values.filter { !isEmptyItem($0) }.count
                        tags[index].value = .list(type, [])
                        containerCount += 1
                    case .compound(let values):
                        if !values.isEmpty { itemCount += 1 }
                        tags[index].value = .compound([])
                        containerCount += 1
                    default:
                        break
                    }
                } else {
                    let nested = clearItemContainers(in: tags[index].value)
                    tags[index].value = nested.value
                    itemCount += nested.itemCount
                    containerCount += nested.containerCount
                }
            }
            return (.compound(tags), itemCount, containerCount)
        case .list(let type, var values):
            var itemCount = 0
            var containerCount = 0
            for index in values.indices {
                let nested = clearItemContainers(in: values[index])
                values[index] = nested.value
                itemCount += nested.itemCount
                containerCount += nested.containerCount
            }
            return (.list(type, values), itemCount, containerCount)
        default:
            return (value, 0, 0)
        }
    }

    private func isEmptyItem(_ value: NBTValue) -> Bool {
        guard case .compound(let tags) = value else { return false }
        if tags.isEmpty { return true }
        let names = tags.compactMap { tag -> String? in
            guard normalized(tag.name) == "name", case .string(let name) = tag.value else { return nil }
            return name.lowercased()
        }
        return names.contains(where: { $0 == "minecraft:air" || $0.isEmpty })
    }

    private func removeSpawnTags(in value: NBTValue) -> (value: NBTValue, removedCount: Int) {
        let directFields: Set<String> = [
            "spawnx", "spawny", "spawnz", "spawndimension", "spawnforced",
            "spawnblockposition", "respawnx", "respawny", "respawnz",
            "respawndimension", "respawnforced"
        ]
        let containers: Set<String> = [
            "respawn", "spawn", "spawnpoint", "playerspawn", "bedspawn", "respawnpoint"
        ]
        switch value {
        case .compound(let original):
            var tags = [NBTNamedTag]()
            var removed = 0
            for tag in original {
                let name = normalized(tag.name)
                if directFields.contains(name) || containers.contains(name) {
                    removed += 1
                    continue
                }
                let nested = removeSpawnTags(in: tag.value)
                tags.append(NBTNamedTag(name: tag.name, value: nested.value))
                removed += nested.removedCount
            }
            return (.compound(tags), removed)
        case .list(let type, let original):
            var values = [NBTValue]()
            var removed = 0
            for value in original {
                let nested = removeSpawnTags(in: value)
                values.append(nested.value)
                removed += nested.removedCount
            }
            return (.list(type, values), removed)
        default:
            return (value, 0)
        }
    }

    private func normalized(_ name: String) -> String {
        name.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}

// MARK: - Three-dimensional block command engine

private final class CommandBlockStore {
    private struct SubKey: Hashable {
        let chunk: ChunkPosition
        let y: Int8
    }

    private struct BlockEntityCoordinate: Hashable {
        let x: Int64
        let y: Int32
        let z: Int64
    }

    private enum CachedSubChunk {
        case missing
        case value(MutableCommandSubChunk)
    }

    private let session: WorldSession
    private let dimension: Int32
    private let database: MojangLevelDB
    private let loadedChunks: Set<ChunkPosition>
    private var cache = [SubKey: CachedSubChunk]()
    private var changedKeys = Set<SubKey>()
    private var globalPaletteVersion: Int32?
    private var chunkLegacyFormat = [ChunkPosition: Bool]()

    init(session: WorldSession, dimension: Int32) throws {
        self.session = session
        self.dimension = dimension
        self.database = try session.database()
        let summaries = try BedrockChunkStore(session: session).listChunks()
        self.loadedChunks = Set(summaries.filter { summary in
            summary.position.dimension == dimension
                && (summary.subChunkCount > 0 || summary.biomeRecordType != nil
                    || summary.hasBlockEntities || summary.hasLegacyEntities
                    || summary.recordCount > (summary.hasActorDigest ? 1 : 0))
        }.map(\.position))
        self.globalPaletteVersion = nil
    }

    func fill(region: CommandBlockBox, layer0: CommandBlockStateSpec, layer1: CommandBlockStateSpec) throws -> String {
        try validateVolume(region)
        var skippedChunks = Set<ChunkPosition>()
        var changedBlocks: UInt64 = 0
        var touchedChunks = Set<ChunkPosition>()

        var x = region.minimum.x
        while x <= region.maximum.x {
            var z = region.minimum.z
            while z <= region.maximum.z {
                let chunk = chunkPosition(x: x, z: z)
                guard loadedChunks.contains(chunk) else {
                    skippedChunks.insert(chunk)
                    if z == Int64.max { break }
                    z += 1
                    continue
                }
                touchedChunks.insert(chunk)
                var y = region.minimum.y
                while y <= region.maximum.y {
                    let coordinate = CommandBlockCoordinate(x: x, y: y, z: z)
                    let key = try subKey(for: coordinate)
                    let formatLegacy = try isLegacyTarget(key)
                    let version = try paletteVersion(for: key)
                    let state0 = try formatLegacy ? layer0.legacyState() : layer0.modernState(version: version)
                    let state1 = try formatLegacy ? layer1.legacyState() : layer1.modernState(version: version)
                    let changed0 = try setState(state0, layer: 0, at: coordinate, createWhenAir: false)
                    let changed1 = try setState(state1, layer: 1, at: coordinate, createWhenAir: false)
                    if changed0 || changed1 { changedBlocks += 1 }
                    if y == Int32.max { break }
                    y += 1
                }
                if z == Int64.max { break }
                z += 1
            }
            if x == Int64.max { break }
            x += 1
        }

        let entityResult = try removeBlockEntities(in: region, onlyLoadedChunks: true)
        let written = try commit(extraPuts: entityResult.puts, extraDeletes: entityResult.deletes)
        guard written > 0 || entityResult.changedCount > 0 else {
            throw BlocktopographError.unsupported("区域内没有产生任何方块变化")
        }
        return "fill 完成：修改 \(changedBlocks) 个方块位置，写入 \(written) 个 SubChunk，移除 \(entityResult.changedCount) 个原方块实体；处理 \(touchedChunks.count) 个已加载区块，跳过 \(skippedChunks.count) 个未加载区块。"
    }

    func clone(source: CommandBlockBox, destination: CommandBlockCoordinate) throws -> String {
        try validateVolume(source)
        let deltaX = destination.x - source.minimum.x
        let deltaY64 = Int64(destination.y) - Int64(source.minimum.y)
        let deltaZ = destination.z - source.minimum.z
        guard let deltaY = Int32(exactly: deltaY64) else {
            throw BlocktopographError.malformedData("目标 Y 偏移超出 Int32 范围")
        }
        var skippedChunks = Set<ChunkPosition>()
        var changedBlocks: UInt64 = 0
        var touchedDestinationChunks = Set<ChunkPosition>()

        let entityState = try loadBlockEntities(for: try cloneRelevantChunks(source: source, destination: destination))
        var blockEntities = entityState.documents
        var changedEntityChunks = Set<ChunkPosition>()

        // Deliberately read and write the same mutable working set in ascending
        // coordinate order. Therefore a destination that overlaps the source
        // immediately overwrites it, matching the requested direct-overwrite behavior.
        var x = source.minimum.x
        while x <= source.maximum.x {
            var y = source.minimum.y
            while y <= source.maximum.y {
                var z = source.minimum.z
                while z <= source.maximum.z {
                    let targetX = x.addingReportingOverflow(deltaX)
                    let targetY = y.addingReportingOverflow(deltaY)
                    let targetZ = z.addingReportingOverflow(deltaZ)
                    guard !targetX.overflow, !targetY.overflow, !targetZ.overflow else {
                        throw BlocktopographError.malformedData("clone 目标坐标溢出")
                    }
                    let sourceCoordinate = CommandBlockCoordinate(x: x, y: y, z: z)
                    let targetCoordinate = CommandBlockCoordinate(x: targetX.partialValue, y: targetY.partialValue, z: targetZ.partialValue)
                    let sourceChunk = chunkPosition(x: x, z: z)
                    let targetChunk = chunkPosition(x: targetCoordinate.x, z: targetCoordinate.z)
                    guard loadedChunks.contains(sourceChunk), loadedChunks.contains(targetChunk) else {
                        if !loadedChunks.contains(sourceChunk) { skippedChunks.insert(sourceChunk) }
                        if !loadedChunks.contains(targetChunk) { skippedChunks.insert(targetChunk) }
                        if z == Int64.max { break }
                        z += 1
                        continue
                    }
                    touchedDestinationChunks.insert(targetChunk)
                    let source0 = try state(layer: 0, at: sourceCoordinate)
                    let source1 = try state(layer: 1, at: sourceCoordinate)
                    let targetKey = try subKey(for: targetCoordinate)
                    let target0 = try adaptedState(source0, for: targetKey)
                    let target1 = try adaptedState(source1, for: targetKey)
                    let changed0 = try setState(target0, layer: 0, at: targetCoordinate, createWhenAir: false)
                    let changed1 = try setState(target1, layer: 1, at: targetCoordinate, createWhenAir: false)
                    if changed0 || changed1 { changedBlocks += 1 }

                    let sourceEntityKey = BlockEntityCoordinate(x: x, y: y, z: z)
                    let targetEntityKey = BlockEntityCoordinate(x: targetCoordinate.x, y: targetCoordinate.y, z: targetCoordinate.z)
                    if let sourceDocument = blockEntities[sourceEntityKey] {
                        blockEntities[targetEntityKey] = offsetBlockEntity(sourceDocument, to: targetCoordinate)
                    } else {
                        blockEntities.removeValue(forKey: targetEntityKey)
                    }
                    changedEntityChunks.insert(targetChunk)

                    if z == Int64.max { break }
                    z += 1
                }
                if y == Int32.max { break }
                y += 1
            }
            if x == Int64.max { break }
            x += 1
        }

        let entityWrites = try encodeBlockEntities(
            documents: blockEntities,
            changedChunks: changedEntityChunks,
            originalKeys: entityState.keysByChunk
        )
        let written = try commit(extraPuts: entityWrites.puts, extraDeletes: entityWrites.deletes)
        guard written > 0 || !entityWrites.puts.isEmpty || !entityWrites.deletes.isEmpty else {
            throw BlocktopographError.unsupported("源区域内没有可复制到已加载目标区块的方块")
        }
        return "clone 完成：复制并写入 \(changedBlocks) 个方块位置，写入 \(written) 个 SubChunk；处理 \(touchedDestinationChunks.count) 个目标区块，跳过 \(skippedChunks.count) 个未加载区块。重叠区域已按坐标顺序直接覆盖。"
    }

    private func validateVolume(_ region: CommandBlockBox) throws {
        try validateHorizontal(region.minimum.x, name: "X1")
        try validateHorizontal(region.maximum.x, name: "X2")
        try validateHorizontal(region.minimum.z, name: "Z1")
        try validateHorizontal(region.maximum.z, name: "Z2")
        guard let volume = region.volume else { throw BlocktopographError.malformedData("区域体积溢出") }
        guard volume <= 67_108_864 else {
            throw BlocktopographError.unsupported("一次命令最多处理 67,108,864 个方块；当前为 \(volume)")
        }
        _ = try subChunkY(for: region.minimum.y)
        _ = try subChunkY(for: region.maximum.y)
    }

    private func validateHorizontal(_ coordinate: Int64, name: String) throws {
        let minimum = Int64(Int32.min) * 16
        let maximum = Int64(Int32.max) * 16 + 15
        guard (minimum...maximum).contains(coordinate) else {
            throw BlocktopographError.malformedData("\(name)=\(coordinate) 超出 Bedrock 区块坐标范围")
        }
    }

    private func chunkPosition(x: Int64, z: Int64) -> ChunkPosition {
        ChunkPosition(x: MapCoordinate.chunk(fromBlock: x), z: MapCoordinate.chunk(fromBlock: z), dimension: dimension)
    }

    private func subKey(for coordinate: CommandBlockCoordinate) throws -> SubKey {
        SubKey(chunk: chunkPosition(x: coordinate.x, z: coordinate.z), y: try subChunkY(for: coordinate.y))
    }

    private func subChunkY(for y: Int32) throws -> Int8 {
        let wide = Int64(y)
        let quotient = wide >= 0 ? wide / 16 : (wide - 15) / 16
        guard let value = Int8(exactly: quotient) else {
            throw BlocktopographError.unsupported("Y=\(y) 超出可编码的 SubChunk 范围")
        }
        return value
    }

    private func localIndex(for coordinate: CommandBlockCoordinate) -> Int {
        let chunkX = MapCoordinate.chunk(fromBlock: coordinate.x)
        let chunkZ = MapCoordinate.chunk(fromBlock: coordinate.z)
        let localX = Int(coordinate.x - MapCoordinate.blockOrigin(ofChunk: chunkX))
        let localZ = Int(coordinate.z - MapCoordinate.blockOrigin(ofChunk: chunkZ))
        let wideY = Int64(coordinate.y)
        let subY = wideY >= 0 ? wideY / 16 : (wideY - 15) / 16
        let localY = Int(wideY - subY * 16)
        return (localX << 8) | (localZ << 4) | localY
    }

    private func load(_ key: SubKey) throws -> CachedSubChunk {
        if let cached = cache[key] { return cached }
        let dbKey = BedrockDBKey.subChunk(x: key.chunk.x, z: key.chunk.z, dimension: key.chunk.dimension, index: key.y)
        if let raw = try database.get(dbKey) {
            let decoded = try BedrockSubChunk.decode(raw, keyYIndex: key.y)
            let mutable = try MutableCommandSubChunk(decoded)
            let cached = CachedSubChunk.value(mutable)
            cache[key] = cached
            if globalPaletteVersion == nil { globalPaletteVersion = mutable.paletteVersion }
            chunkLegacyFormat[key.chunk] = mutable.isLegacy
            return cached
        }
        cache[key] = .missing
        return .missing
    }

    private func state(layer: Int, at coordinate: CommandBlockCoordinate) throws -> BedrockBlockState {
        let key = try subKey(for: coordinate)
        switch try load(key) {
        case .missing:
            if try isLegacyTarget(key) {
                return BedrockBlockState(nbt: nil, legacyID: 0, legacyData: 0)
            }
            return .editableAir(version: try paletteVersion(for: key))
        case .value(let subChunk):
            return subChunk.state(layer: layer, linearIndex: localIndex(for: coordinate))
        }
    }

    @discardableResult
    private func setState(
        _ state: BedrockBlockState,
        layer: Int,
        at coordinate: CommandBlockCoordinate,
        createWhenAir: Bool
    ) throws -> Bool {
        let key = try subKey(for: coordinate)
        let index = localIndex(for: coordinate)
        var mutable: MutableCommandSubChunk
        switch try load(key) {
        case .value(let existing):
            mutable = existing
        case .missing:
            if state.isAir && !createWhenAir { return false }
            let legacy = try isLegacyTarget(key)
            if legacy {
                guard state.nbt == nil else {
                    throw BlocktopographError.unsupported("不能把现代方块状态写入旧版数字 ID SubChunk")
                }
                mutable = try MutableCommandSubChunk.emptyLegacy(y: key.y)
            } else {
                mutable = try MutableCommandSubChunk.emptyModern(y: key.y, version: state.paletteVersion ?? paletteVersion(for: key))
            }
        }
        let changed = try mutable.setState(state, layer: layer, linearIndex: index)
        if changed {
            cache[key] = .value(mutable)
            changedKeys.insert(key)
        }
        return changed
    }

    private func isLegacyTarget(_ key: SubKey) throws -> Bool {
        switch try load(key) {
        case .value(let value): return value.isLegacy
        case .missing:
            if let cached = chunkLegacyFormat[key.chunk] { return cached }
            for rawY in -16...31 {
                guard let y = Int8(exactly: rawY) else { continue }
                let dbKey = BedrockDBKey.subChunk(x: key.chunk.x, z: key.chunk.z, dimension: key.chunk.dimension, index: y)
                guard let raw = try database.get(dbKey) else { continue }
                let decoded = try BedrockSubChunk.decode(raw, keyYIndex: y)
                let legacy = decoded.version <= 7
                chunkLegacyFormat[key.chunk] = legacy
                if globalPaletteVersion == nil {
                    globalPaletteVersion = decoded.storages.flatMap(\.palette).compactMap(\.paletteVersion).first
                }
                return legacy
            }
            chunkLegacyFormat[key.chunk] = false
            return false
        }
    }

    private func paletteVersion(for key: SubKey) throws -> Int32? {
        switch try load(key) {
        case .value(let value):
            if let version = value.paletteVersion { return version }
        case .missing:
            break
        }
        if let globalPaletteVersion = globalPaletteVersion { return globalPaletteVersion }
        for chunk in loadedChunks.prefix(32) {
            for rawY in -16...31 {
                guard let y = Int8(exactly: rawY) else { continue }
                let dbKey = BedrockDBKey.subChunk(x: chunk.x, z: chunk.z, dimension: chunk.dimension, index: y)
                guard let raw = try database.get(dbKey),
                      let decoded = try? BedrockSubChunk.decode(raw, keyYIndex: y),
                      let version = decoded.storages.flatMap(\.palette).compactMap(\.paletteVersion).first else { continue }
                globalPaletteVersion = version
                return version
            }
        }
        return nil
    }


    private func adaptedState(_ state: BedrockBlockState, for targetKey: SubKey) throws -> BedrockBlockState {
        let targetLegacy = try isLegacyTarget(targetKey)
        if targetLegacy {
            if state.nbt == nil { return state }
            guard state.stateProperties.isEmpty,
                  let block = BedrockLegacyBlockCatalog.block(forIdentifier: state.name) else {
                throw BlocktopographError.unsupported("方块 \(state.name) 的现代 states 无法复制到旧版数字 ID SubChunk")
            }
            return BedrockBlockState(nbt: nil, legacyID: UInt16(block.id), legacyData: 0)
        }
        if state.nbt != nil { return state }
        let identifier = BedrockLegacyBlockCatalog.identifier(forNumericID: state.legacyID ?? 0) ?? state.name
        return CommandBlockStateSpec(name: identifier, states: []).modernState(version: try paletteVersion(for: targetKey))
    }

    private func commit(
        extraPuts: [(key: Data, value: Data)] = [],
        extraDeletes: [Data] = []
    ) throws -> Int {
        var puts = extraPuts
        for key in changedKeys.sorted(by: commandSubKeyOrder) {
            guard case .value(let mutable)? = cache[key] else { continue }
            let data = try mutable.persistentSubChunk().encodePersistent()
            puts.append((BedrockDBKey.subChunk(x: key.chunk.x, z: key.chunk.z, dimension: key.chunk.dimension, index: key.y), data))
        }
        try database.applyBatch(puts: puts, deletes: extraDeletes, sync: true)
        return changedKeys.count
    }

    private func commandSubKeyOrder(_ lhs: SubKey, _ rhs: SubKey) -> Bool {
        if lhs.chunk.z != rhs.chunk.z { return lhs.chunk.z < rhs.chunk.z }
        if lhs.chunk.x != rhs.chunk.x { return lhs.chunk.x < rhs.chunk.x }
        return lhs.y < rhs.y
    }

    // MARK: Block entities

    private func cloneRelevantChunks(source: CommandBlockBox, destination: CommandBlockCoordinate) throws -> Set<ChunkPosition> {
        let targetMaximumXResult = destination.x.addingReportingOverflow(source.maximum.x - source.minimum.x)
        let targetMaximumZResult = destination.z.addingReportingOverflow(source.maximum.z - source.minimum.z)
        guard !targetMaximumXResult.overflow, !targetMaximumZResult.overflow else {
            throw BlocktopographError.malformedData("clone 目标区域坐标溢出")
        }
        let targetMaximumX = targetMaximumXResult.partialValue
        let targetMaximumZ = targetMaximumZResult.partialValue
        try validateHorizontal(destination.x, name: "目标X")
        try validateHorizontal(destination.z, name: "目标Z")
        try validateHorizontal(targetMaximumX, name: "目标最大X")
        try validateHorizontal(targetMaximumZ, name: "目标最大Z")
        let target = CommandBlockBox(
            destination,
            CommandBlockCoordinate(x: targetMaximumX, y: destination.y, z: targetMaximumZ)
        )
        return chunks(in: source).union(chunks(in: target)).intersection(loadedChunks)
    }

    private func chunks(in box: CommandBlockBox) -> Set<ChunkPosition> {
        let minX = MapCoordinate.chunk(fromBlock: box.minimum.x)
        let maxX = MapCoordinate.chunk(fromBlock: box.maximum.x)
        let minZ = MapCoordinate.chunk(fromBlock: box.minimum.z)
        let maxZ = MapCoordinate.chunk(fromBlock: box.maximum.z)
        var result = Set<ChunkPosition>()
        for z in minZ...maxZ {
            for x in minX...maxX { result.insert(ChunkPosition(x: x, z: z, dimension: dimension)) }
        }
        return result
    }

    private func loadBlockEntities(
        for chunks: Set<ChunkPosition>
    ) throws -> (documents: [BlockEntityCoordinate: NBTDocument], keysByChunk: [ChunkPosition: Data]) {
        var documents = [BlockEntityCoordinate: NBTDocument]()
        var keys = [ChunkPosition: Data]()
        for chunk in chunks {
            let key = BedrockDBKey(position: chunk, recordType: .blockEntity, subChunkIndex: nil).encoded()
            keys[chunk] = key
            guard let raw = try database.get(key) else { continue }
            for record in try ConsecutiveNBTCodec.decode(raw) {
                guard let coordinate = blockEntityCoordinate(record.document.root) else { continue }
                documents[coordinate] = record.document
            }
        }
        return (documents, keys)
    }

    private func removeBlockEntities(
        in region: CommandBlockBox,
        onlyLoadedChunks: Bool
    ) throws -> (puts: [(key: Data, value: Data)], deletes: [Data], changedCount: Int) {
        let relevant = chunks(in: region).filter { !onlyLoadedChunks || loadedChunks.contains($0) }
        let loaded = try loadBlockEntities(for: Set(relevant))
        var documents = loaded.documents
        let removeKeys = documents.keys.filter { region.contains(CommandBlockCoordinate(x: $0.x, y: $0.y, z: $0.z)) }
        for key in removeKeys { documents.removeValue(forKey: key) }
        let writes = try encodeBlockEntities(documents: documents, changedChunks: Set(relevant), originalKeys: loaded.keysByChunk)
        return (writes.puts, writes.deletes, removeKeys.count)
    }

    private func encodeBlockEntities(
        documents: [BlockEntityCoordinate: NBTDocument],
        changedChunks: Set<ChunkPosition>,
        originalKeys: [ChunkPosition: Data]
    ) throws -> (puts: [(key: Data, value: Data)], deletes: [Data]) {
        var puts = [(key: Data, value: Data)]()
        var deletes = [Data]()
        for chunk in changedChunks {
            let key = originalKeys[chunk] ?? BedrockDBKey(position: chunk, recordType: .blockEntity, subChunkIndex: nil).encoded()
            let records = documents
                .filter { chunkPosition(x: $0.key.x, z: $0.key.z) == chunk }
                .sorted { lhs, rhs in
                    if lhs.key.y != rhs.key.y { return lhs.key.y < rhs.key.y }
                    if lhs.key.z != rhs.key.z { return lhs.key.z < rhs.key.z }
                    return lhs.key.x < rhs.key.x
                }
                .map { ConsecutiveNBTRecord(document: $0.value, rawData: Data(), encoding: .littleEndian) }
            if records.isEmpty { deletes.append(key) }
            else { puts.append((key, try ConsecutiveNBTCodec.encode(records))) }
        }
        return (puts, deletes)
    }

    private func blockEntityCoordinate(_ root: NBTValue) -> BlockEntityCoordinate? {
        guard case .compound(let tags) = root else { return nil }
        func number(_ names: Set<String>) -> Int64? {
            for tag in tags where names.contains(tag.name.lowercased()) {
                switch tag.value {
                case .byte(let value): return Int64(value)
                case .short(let value): return Int64(value)
                case .int(let value): return Int64(value)
                case .long(let value): return value
                case .float(let value): return Int64(value)
                case .double(let value): return Int64(value)
                default: continue
                }
            }
            return nil
        }
        guard let x = number(["x"]), let y = number(["y"]), let z = number(["z"]),
              let y32 = Int32(exactly: y) else { return nil }
        return BlockEntityCoordinate(x: x, y: y32, z: z)
    }

    private func offsetBlockEntity(_ document: NBTDocument, to coordinate: CommandBlockCoordinate) -> NBTDocument {
        var document = document
        guard case .compound(var tags) = document.root else { return document }
        for index in tags.indices {
            switch tags[index].name.lowercased() {
            case "x": tags[index].value = numericLike(tags[index].value, value: coordinate.x)
            case "y": tags[index].value = numericLike(tags[index].value, value: Int64(coordinate.y))
            case "z": tags[index].value = numericLike(tags[index].value, value: coordinate.z)
            default: break
            }
        }
        document.root = .compound(tags)
        return document
    }

    private func numericLike(_ original: NBTValue, value: Int64) -> NBTValue {
        switch original {
        case .byte: return .byte(Int8(clamping: value))
        case .short: return .short(Int16(clamping: value))
        case .int: return .int(Int32(clamping: value))
        case .long: return .long(value)
        case .float: return .float(Float(value))
        case .double: return .double(Double(value))
        default: return .int(Int32(clamping: value))
        }
    }
}

private struct MutableCommandStorage {
    var palette: [BedrockBlockState]
    var indices: [UInt16]
    private var lookup: [Data: UInt16]

    init(_ storage: SubChunkStorage) throws {
        self.palette = storage.palette
        self.indices = storage.indices
        self.lookup = [:]
        for (index, state) in palette.enumerated() {
            lookup[try Self.key(for: state)] = UInt16(index)
        }
    }

    mutating func set(_ state: BedrockBlockState, at index: Int) throws -> Bool {
        guard indices.indices.contains(index) else { return false }
        let key = try Self.key(for: state)
        let paletteIndex: UInt16
        if let existing = lookup[key] {
            paletteIndex = existing
        } else {
            guard palette.count < Int(UInt16.max) else {
                throw BlocktopographError.unsupported("方块调色板条目过多")
            }
            paletteIndex = UInt16(palette.count)
            palette.append(state)
            lookup[key] = paletteIndex
        }
        guard indices[index] != paletteIndex else { return false }
        indices[index] = paletteIndex
        return true
    }

    func state(at index: Int) -> BedrockBlockState? {
        guard indices.indices.contains(index), Int(indices[index]) < palette.count else { return nil }
        return palette[Int(indices[index])]
    }

    var isEntirelyAir: Bool {
        indices.allSatisfy { index in
            Int(index) < palette.count && palette[Int(index)].isAir
        }
    }

    func persistentStorage() throws -> SubChunkStorage {
        SubChunkStorage(bitsPerBlock: try Self.bitsRequired(paletteCount: palette.count), palette: palette, indices: indices)
    }

    private static func key(for state: BedrockBlockState) throws -> Data {
        if let nbt = state.nbt {
            var data = Data([1])
            data.append(try BedrockNBTCodec.encode(NBTDocument(rootName: "", root: nbt), encoding: .littleEndian))
            return data
        }
        var data = Data([0])
        data.appendLE(state.legacyID ?? 0)
        data.append(state.legacyData ?? 0)
        return data
    }

    private static func bitsRequired(paletteCount: Int) throws -> Int {
        guard paletteCount > 0 else { throw BlocktopographError.malformedData("方块调色板不能为空") }
        if paletteCount == 1 { return 0 }
        let needed = Int(ceil(log2(Double(paletteCount))))
        for allowed in [1, 2, 3, 4, 5, 6, 8, 16] where allowed >= needed { return allowed }
        throw BlocktopographError.unsupported("方块调色板条目过多")
    }
}

private struct MutableCommandSubChunk {
    let version: UInt8
    let yIndex: Int8?
    var storages: [MutableCommandStorage]
    let trailingData: Data
    let fallbackAir: BedrockBlockState

    init(_ subChunk: BedrockSubChunk) throws {
        self.version = subChunk.version
        self.yIndex = subChunk.yIndex
        self.storages = try subChunk.storages.map(MutableCommandStorage.init)
        self.trailingData = subChunk.trailingData
        let paletteVersion = subChunk.storages.flatMap(\.palette).compactMap(\.paletteVersion).first
        self.fallbackAir = subChunk.storages.flatMap(\.palette).first(where: { $0.isAir }) ?? .editableAir(version: paletteVersion)
    }

    static func emptyModern(y: Int8, version: Int32?) throws -> MutableCommandSubChunk {
        let air = BedrockBlockState.editableAir(version: version)
        let storage = SubChunkStorage(bitsPerBlock: 0, palette: [air], indices: Array(repeating: 0, count: 4096))
        return try MutableCommandSubChunk(BedrockSubChunk(version: 9, yIndex: y, storages: [storage], trailingData: Data()))
    }

    static func emptyLegacy(y: Int8) throws -> MutableCommandSubChunk {
        let air = BedrockBlockState(nbt: nil, legacyID: 0, legacyData: 0)
        let storage = SubChunkStorage(bitsPerBlock: 8, palette: [air], indices: Array(repeating: 0, count: 4096))
        return try MutableCommandSubChunk(BedrockSubChunk(version: 7, yIndex: y, storages: [storage], trailingData: Data()))
    }

    var isLegacy: Bool { version <= 7 }
    var paletteVersion: Int32? { storages.flatMap(\.palette).compactMap(\.paletteVersion).first }

    func state(layer: Int, linearIndex: Int) -> BedrockBlockState {
        guard storages.indices.contains(layer), let state = storages[layer].state(at: linearIndex) else { return fallbackAir }
        return state
    }

    mutating func setState(_ state: BedrockBlockState, layer: Int, linearIndex: Int) throws -> Bool {
        guard layer == 0 || layer == 1 else { throw BlocktopographError.malformedData("只支持层 0 和层 1") }
        if isLegacy {
            guard layer == 0 || state.isAir else {
                throw BlocktopographError.unsupported("旧版数字 ID SubChunk 不支持非空气层 1")
            }
            if layer == 1 { return false }
            guard state.nbt == nil else {
                throw BlocktopographError.unsupported("不能把现代方块状态写入旧版数字 ID SubChunk")
            }
        } else if state.nbt == nil {
            throw BlocktopographError.unsupported("不能把旧版数字 ID 方块写入现代 SubChunk")
        }
        if layer == 1, storages.count <= 1, state.isAir { return false }
        while storages.count <= layer {
            let storage = SubChunkStorage(bitsPerBlock: 0, palette: [fallbackAir], indices: Array(repeating: 0, count: 4096))
            storages.append(try MutableCommandStorage(storage))
        }
        let changed = try storages[layer].set(state, at: linearIndex)
        if changed, layer == 1, storages.count > 1, storages[1].isEntirelyAir {
            storages.removeLast()
        }
        return changed
    }

    func persistentSubChunk() throws -> BedrockSubChunk {
        let outputVersion: UInt8 = version == 1 && storages.count > 1 ? 8 : version
        return BedrockSubChunk(
            version: outputVersion,
            yIndex: yIndex,
            storages: try storages.map { try $0.persistentStorage() },
            trailingData: trailingData
        )
    }
}
