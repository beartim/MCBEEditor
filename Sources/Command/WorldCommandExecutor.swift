import Foundation

struct WorldCommandExecutionResult {
    let message: String
    let changedWorld: Bool
}

private struct ResolvedCommandTargets {
    let players: [PlayerNBTRecord]
    let entities: [BedrockWorldObject]

    var isEmpty: Bool { players.isEmpty && entities.isEmpty }
}

final class WorldCommandExecutor {
    private let session: WorldSession

    init(session: WorldSession) {
        self.session = session
    }

    func execute(_ command: ParsedWorldCommand) throws -> WorldCommandExecutionResult {
        switch command {
        case .help(let target):
            return WorldCommandExecutionResult(message: WorldCommandParser.helpText(for: target), changedWorld: false)
        case .clear(let target):
            return WorldCommandExecutionResult(message: try clearItems(target: target), changedWorld: true)
        case .clearSpawnPoint(let target):
            return WorldCommandExecutionResult(message: try clearSpawnPoints(target: target), changedWorld: true)
        case .give(let target, let itemIdentifier, let count):
            return WorldCommandExecutionResult(
                message: try give(target: target, itemIdentifier: itemIdentifier, count: count),
                changedWorld: true
            )
        case .kill(let target, let killCreativePlayers):
            return WorldCommandExecutionResult(
                message: try kill(target: target, killCreativePlayers: killCreativePlayers),
                changedWorld: true
            )
        case .kick(let target):
            return WorldCommandExecutionResult(message: try kick(target: target), changedWorld: true)
        case .summon(let identifier, let dimension, let position, let additions):
            return WorldCommandExecutionResult(
                message: try summon(identifier: identifier, dimension: dimension, position: position, additions: additions),
                changedWorld: true
            )
        case .clone(let sourceDimension, let source, let targetDimension, let destination):
            let result = try CommandBlockStore.clone(
                session: session,
                sourceDimension: sourceDimension,
                source: source,
                targetDimension: targetDimension,
                destination: destination
            )
            return WorldCommandExecutionResult(message: result, changedWorld: true)
        case .fill(let targetDimension, let region, let layer0, let layer1):
            let result = try CommandBlockStore(session: session, dimension: targetDimension)
                .fill(region: region, layer0: layer0, layer1: layer1)
            return WorldCommandExecutionResult(message: result, changedWorld: true)
        }
    }

    private func summon(
        identifier: String,
        dimension: Int32,
        position: CommandBlockCoordinate,
        additions: [NBTNamedTag]
    ) throws -> String {
        let store = BedrockWorldObjectNBTStore(session: session)
        let uniqueID = try store.suggestedUniqueID()
        let worldPosition = BedrockWorldObjectPosition(
            x: Double(position.x),
            y: Double(position.y),
            z: Double(position.z)
        )
        var root: NBTValue = .compound([
            NBTNamedTag(name: "identifier", value: .string(identifier))
        ] + BedrockEntityCommonNBT.tags(
            identifier: identifier,
            position: worldPosition,
            dimension: dimension,
            uniqueID: uniqueID
        ))
        root = try BedrockEntityCommonNBT.mergingTopLevel(additions, into: root)
        let result = try store.create(
            kind: .entity,
            identifier: identifier,
            position: worldPosition,
            dimension: dimension,
            uniqueID: uniqueID,
            template: nil,
            templateDocument: NBTDocument(rootName: "", root: root)
        )
        return "summon 完成：创建 \(identifier)，维度 \(WorldCommandParser.dimensionName(for: dimension))，坐标 \(position.x) \(position.y) \(position.z)，UniqueID \(uniqueID)，存储方式 \(result.source.rawValue)。"
    }

    // MARK: Target selectors

    private func resolveTargets(_ target: CommandTarget) throws -> ResolvedCommandTargets {
        let playerStore = PlayerNBTStore(session: session)
        let allPlayers = try playerStore.records()
        let allEntities: [BedrockWorldObject]
        switch target {
        case .localPlayer, .allPlayers:
            allEntities = []
        case .identifier(let identifier) where normalizedIdentifier(identifier) == "minecraft:player":
            allEntities = []
        default:
            let scan = try BedrockWorldObjectScanner(database: session.database()).scanAll(
                dimensions: nil,
                includeEntities: true,
                includeBlockEntities: false,
                maximumObjects: Int.max
            )
            allEntities = scan.objects.filter { $0.kind == .entity && !isPlayerEntity($0) }
        }

        let players: [PlayerNBTRecord]
        let entities: [BedrockWorldObject]
        switch target {
        case .localPlayer:
            players = allPlayers.filter(isLocalPlayer)
            entities = []
        case .allPlayers:
            players = allPlayers
            entities = []
        case .allEntities:
            players = allPlayers
            entities = allEntities
        case .identifier(let identifier):
            if normalizedIdentifier(identifier) == "minecraft:player" {
                players = allPlayers
                entities = []
            } else {
                players = []
                let wanted = normalizedIdentifier(identifier)
                entities = allEntities.filter { normalizedIdentifier($0.identifier) == wanted }
            }
        case .uniqueID(let uniqueID):
            players = allPlayers.filter { playerUniqueID($0) == uniqueID }
            entities = allEntities.filter { $0.uniqueID == uniqueID }
        }
        let resolved = ResolvedCommandTargets(players: players, entities: entities)
        guard !resolved.isEmpty else {
            throw BlocktopographError.unsupported("目标 \(target.displayText) 没有匹配到玩家或实体")
        }
        return resolved
    }

    private func isPlayerEntity(_ object: BedrockWorldObject) -> Bool {
        normalizedIdentifier(object.identifier) == "minecraft:player"
    }

    private func normalizedIdentifier(_ value: String) -> String {
        let lowered = value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return lowered.contains(":") ? lowered : "minecraft:\(lowered)"
    }

    private func isLocalPlayer(_ record: PlayerNBTRecord) -> Bool {
        record.keyText == "~local_player" || record.keyText == "LocalPlayer"
    }

    private func isOnlinePlayer(_ record: PlayerNBTRecord) -> Bool { !isLocalPlayer(record) }

    private func playerIdentity(_ record: PlayerNBTRecord) -> String {
        playerUniqueID(record).map { "UniqueID \($0)" } ?? record.keyText
    }

    private func playerUniqueID(_ record: PlayerNBTRecord) -> Int64? {
        if let value = numericTag(in: record.document.root, names: ["UniqueID", "UniqueId", "uniqueID", "uniqueId"]) {
            return value
        }
        for prefix in ["player_server_", "player_"] where record.keyText.hasPrefix(prefix) {
            if let value = Int64(record.keyText.dropFirst(prefix.count)) { return value }
        }
        return nil
    }

    // MARK: clear / clearspawnpoint

    private func clearItems(target: CommandTarget) throws -> String {
        let targets = try resolveTargets(target)
        let playerStore = PlayerNBTStore(session: session)
        let entityStore = BedrockWorldObjectNBTStore(session: session)
        var changedPlayers = 0
        var changedEntities = 0
        var removedItems = 0
        var containerCount = 0

        for record in targets.players {
            let mutation = clearItemContainers(in: record.document.root)
            guard mutation.containerCount > 0 else { continue }
            var document = record.document
            document.root = mutation.value
            try playerStore.save(record: record, document: document)
            changedPlayers += 1
            removedItems += mutation.itemCount
            containerCount += mutation.containerCount
        }
        for object in targets.entities {
            let mutation = clearItemContainers(in: object.document.root)
            guard mutation.containerCount > 0 else { continue }
            var document = object.document
            document.root = mutation.value
            _ = try entityStore.save(object: object, document: document)
            changedEntities += 1
            removedItems += mutation.itemCount
            containerCount += mutation.containerCount
        }
        guard changedPlayers + changedEntities > 0 else {
            throw BlocktopographError.unsupported("目标 \(target.displayText) 没有可清除的物品容器")
        }
        return "clear 完成：修改 \(changedPlayers) 个玩家和 \(changedEntities) 个实体，清除 \(removedItems) 个物品条目，处理 \(containerCount) 个容器；村民交易数据保持不变。"
    }

    private func clearSpawnPoints(target: CommandTarget) throws -> String {
        let targets = try resolveTargets(target)
        guard !targets.players.isEmpty else {
            throw BlocktopographError.unsupported("目标 \(target.displayText) 没有匹配到玩家；实体不具有玩家出生点")
        }
        let store = PlayerNBTStore(session: session)
        var changed = 0
        var removed = 0
        for record in targets.players {
            let mutation = removeSpawnTags(in: record.document.root)
            guard mutation.removedCount > 0 else { continue }
            var document = record.document
            document.root = mutation.value
            try store.save(record: record, document: document)
            changed += 1
            removed += mutation.removedCount
        }
        guard changed > 0 else {
            throw BlocktopographError.unsupported("目标玩家当前没有可清除的出生点标签")
        }
        return "clearspawnpoint 完成：清除 \(changed) 个玩家的出生点，移除 \(removed) 个相关标签。"
    }

    // MARK: give

    private func give(target: CommandTarget, itemIdentifier: String, count: Int64) throws -> String {
        let targets = try resolveTargets(target)
        let playerStore = PlayerNBTStore(session: session)
        let entityStore = BedrockWorldObjectNBTStore(session: session)
        var changedPlayers = 0
        var changedEntities = 0
        var skippedEntities = 0

        for record in targets.players {
            let mutation = placingPlayerItem(
                in: record.document.root,
                identifier: itemIdentifier,
                count: count
            )
            guard mutation.changed else { continue }
            var document = record.document
            document.root = mutation.value
            try playerStore.save(record: record, document: document)
            changedPlayers += 1
        }
        for object in targets.entities {
            let mutation = replacingMainhandItem(
                in: object.document.root,
                identifier: itemIdentifier,
                count: count
            )
            guard mutation.changed else {
                skippedEntities += 1
                continue
            }
            var document = object.document
            document.root = mutation.value
            _ = try entityStore.save(object: object, document: document)
            changedEntities += 1
        }
        guard changedPlayers + changedEntities > 0 else {
            throw BlocktopographError.unsupported("目标没有可写入的玩家 Inventory 或实体 Mainhand 标签")
        }
        return "give 完成：向 \(changedPlayers) 个玩家物品栏第一个空槽位写入（满时替换最后一格）、替换 \(changedEntities) 个实体主手物品；物品 \(itemIdentifier) × \(count)，跳过 \(skippedEntities) 个没有 Mainhand 标签的实体。"
    }

    private func itemStack(identifier: String, count: Int64, slot: Int8? = nil) -> NBTValue {
        var tags = [
            NBTNamedTag(name: "Name", value: .string(identifier)),
            NBTNamedTag(name: "Count", value: unboundedCountValue(count)),
            NBTNamedTag(name: "Damage", value: .short(0)),
            NBTNamedTag(name: "WasPickedUp", value: .byte(0))
        ]
        if let slot = slot { tags.append(NBTNamedTag(name: "Slot", value: .byte(slot))) }
        return .compound(tags)
    }

    private func unboundedCountValue(_ count: Int64) -> NBTValue {
        if let value = Int8(exactly: count) { return .byte(value) }
        if let value = Int16(exactly: count) { return .short(value) }
        if let value = Int32(exactly: count) { return .int(value) }
        return .long(count)
    }

    private func placingPlayerItem(
        in value: NBTValue,
        identifier: String,
        count: Int64
    ) -> (value: NBTValue, changed: Bool) {
        guard case .compound(var tags) = value else { return (value, false) }
        let inventoryNames: Set<String> = ["inventory", "playerinventory"]
        for index in tags.indices where inventoryNames.contains(normalized(tags[index].name)) {
            if case .list(let type, var values) = tags[index].value, type == .compound || values.isEmpty {
                let occupiedSlots = Set(values.compactMap(itemSlot).filter { (0...35).contains($0) })
                let chosenSlot = Int64((0...35).first(where: { !occupiedSlots.contains(Int64($0)) }) ?? 35)
                let stack = itemStack(identifier: identifier, count: count, slot: Int8(chosenSlot))
                if let slotIndex = values.firstIndex(where: { itemSlot($0) == chosenSlot }) {
                    // All normal slots are occupied only when chosenSlot is 35;
                    // replacing that entry implements the requested full-inventory behavior.
                    values[slotIndex] = stack
                } else {
                    // Slot-indexed Bedrock inventories do not require list order to
                    // match the slot number, so an actually empty slot is appended.
                    values.append(stack)
                }
                tags[index].value = .list(.compound, values)
                return (.compound(tags), true)
            }
        }
        for index in tags.indices {
            if tradeContainerNames.contains(normalized(tags[index].name)) { continue }
            let nested = placingPlayerItem(in: tags[index].value, identifier: identifier, count: count)
            if nested.changed {
                tags[index].value = nested.value
                return (.compound(tags), true)
            }
        }
        return (value, false)
    }

    private func itemSlot(_ value: NBTValue) -> Int64? {
        numericTag(in: value, names: ["Slot", "slot"])
    }

    private func replacingMainhandItem(
        in value: NBTValue,
        identifier: String,
        count: Int64
    ) -> (value: NBTValue, changed: Bool) {
        guard case .compound(var tags) = value else { return (value, false) }
        let names: Set<String> = ["mainhand", "mainhanditem", "mainhandinventory"]
        for index in tags.indices where names.contains(normalized(tags[index].name)) {
            let stack = itemStack(identifier: identifier, count: count)
            switch tags[index].value {
            case .compound:
                tags[index].value = stack
                return (.compound(tags), true)
            case .list(_, var values):
                if values.isEmpty { values.append(stack) }
                else { values[0] = stack }
                tags[index].value = .list(.compound, values)
                return (.compound(tags), true)
            default:
                continue
            }
        }
        for index in tags.indices {
            if tradeContainerNames.contains(normalized(tags[index].name)) { continue }
            let nested = replacingMainhandItem(in: tags[index].value, identifier: identifier, count: count)
            if nested.changed {
                tags[index].value = nested.value
                return (.compound(tags), true)
            }
        }
        return (value, false)
    }

    // MARK: kill / kick

    private func kill(target: CommandTarget, killCreativePlayers: Bool) throws -> String {
        let targets = try resolveTargets(target)
        let playerStore = PlayerNBTStore(session: session)
        let entityStore = BedrockWorldObjectNBTStore(session: session)
        var killedPlayers = 0
        var skippedCreative = 0
        var deletedEntities = 0
        var playersWithoutHealth = 0

        for record in targets.players {
            if isCreativePlayer(record.document.root), !killCreativePlayers {
                skippedCreative += 1
                continue
            }
            let mutation = settingHealthCurrentToZero(in: record.document.root)
            guard mutation.changed else {
                playersWithoutHealth += 1
                continue
            }
            var document = record.document
            document.root = mutation.value
            try playerStore.save(record: record, document: document)
            killedPlayers += 1
        }
        for object in targets.entities {
            try entityStore.delete(object: object)
            deletedEntities += 1
        }
        guard killedPlayers + deletedEntities > 0 else {
            throw BlocktopographError.unsupported("没有可杀死的目标；跳过 \(skippedCreative) 个创造模式玩家，\(playersWithoutHealth) 个玩家缺少 Health Current")
        }
        return "kill 完成：删除 \(deletedEntities) 个非玩家实体，将 \(killedPlayers) 个玩家的生命值 Current 设为 0.0；跳过 \(skippedCreative) 个创造模式玩家和 \(playersWithoutHealth) 个缺少生命值标签的玩家。"
    }

    private func kick(target: CommandTarget) throws -> String {
        let store = PlayerNBTStore(session: session)
        let records = try store.records()
        let selected: [PlayerNBTRecord]
        switch target {
        case .allPlayers:
            selected = records.filter(isOnlinePlayer)
        case .uniqueID(let uniqueID):
            selected = records.filter { isOnlinePlayer($0) && playerUniqueID($0) == uniqueID }
        default:
            throw BlocktopographError.malformedData("kick 目标只能是在线玩家 UniqueID 或 @a")
        }
        guard !selected.isEmpty else { throw BlocktopographError.unsupported("没有匹配到在线玩家数据") }
        let deletedKeys = try store.deleteOnlinePlayerData(records: selected)
        return "kick 完成：删除 \(selected.count) 个在线玩家的全部匹配数据，共移除 \(deletedKeys) 条 LevelDB 记录。"
    }

    private func isCreativePlayer(_ value: NBTValue) -> Bool {
        numericTag(in: value, names: ["PlayerGameMode", "playerGameMode", "GameMode", "gameMode"]) == 1
    }

    private func settingHealthCurrentToZero(in value: NBTValue) -> (value: NBTValue, changed: Bool) {
        switch value {
        case .compound(var tags):
            let attributeName = tags.first(where: {
                ["name", "id", "identifier"].contains(normalized($0.name))
            }).flatMap { tag -> String? in
                guard case .string(let text) = tag.value else { return nil }
                return normalizedIdentifier(text)
            }
            if attributeName == "minecraft:health" || attributeName == "minecraft:attributehealth" {
                if let index = tags.firstIndex(where: { normalized($0.name) == "current" }) {
                    tags[index].value = .float(0.0)
                } else {
                    tags.append(NBTNamedTag(name: "Current", value: .float(0.0)))
                }
                return (.compound(tags), true)
            }
            for index in tags.indices where ["health", "currenthealth"].contains(normalized(tags[index].name)) {
                switch tags[index].value {
                case .byte, .short, .int, .long, .float, .double:
                    tags[index].value = .float(0.0)
                    return (.compound(tags), true)
                default:
                    break
                }
            }
            for index in tags.indices {
                let nested = settingHealthCurrentToZero(in: tags[index].value)
                if nested.changed {
                    tags[index].value = nested.value
                    return (.compound(tags), true)
                }
            }
            return (value, false)
        case .list(let type, var values):
            for index in values.indices {
                let nested = settingHealthCurrentToZero(in: values[index])
                if nested.changed {
                    values[index] = nested.value
                    return (.list(type, values), true)
                }
            }
            return (value, false)
        default:
            return (value, false)
        }
    }

    // MARK: shared NBT mutations

    private var tradeContainerNames: Set<String> {
        ["offers", "recipes", "tradetable", "tradeoffers", "trades", "economytradeablecomponent"]
    }

    private func numericTag(in value: NBTValue, names: Set<String>) -> Int64? {
        guard case .compound(let tags) = value else { return nil }
        let normalizedNames = Set(names.map(normalized))
        for tag in tags where normalizedNames.contains(normalized(tag.name)) {
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
            "inventory", "items", "chestitems", "hotbar",
            "armor", "armoritems", "armorinventory", "equipment",
            "hand", "handitems", "mainhand", "mainhanditem", "mainhandinventory",
            "offhand", "offhanditem", "offhandinventory",
            "playerinventory", "enderchestinventory", "cursorselecteditem", "selecteditem"
        ]
        switch value {
        case .compound(var tags):
            var itemCount = 0
            var containerCount = 0
            for index in tags.indices {
                let tagName = normalized(tags[index].name)
                if tradeContainerNames.contains(tagName) { continue }
                if names.contains(tagName) {
                    switch tags[index].value {
                    case .list(let type, let values):
                        itemCount += values.filter { !isEmptyItem($0) }.count
                        tags[index].value = .list(type == .end ? .compound : type, [])
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
        case .list(let type, var values):
            var removed = 0
            for index in values.indices {
                let nested = removeSpawnTags(in: values[index])
                values[index] = nested.value
                removed += nested.removedCount
            }
            return (.list(type, values), removed)
        default:
            return (value, 0)
        }
    }

    private func normalized(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}

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
    private var availableChunks: Set<ChunkPosition>
    private var cache = [SubKey: CachedSubChunk]()
    private var changedKeys = Set<SubKey>()
    private var globalPaletteVersion: Int32?
    private var chunkLegacyFormat = [ChunkPosition: Bool]()

    init(session: WorldSession, dimension: Int32) throws {
        self.session = session
        self.dimension = dimension
        self.database = try session.database()
        let summaries = try BedrockChunkStore(session: session).listChunks()
        self.availableChunks = Set(summaries.filter { summary in
            summary.position.dimension == dimension
                && (summary.subChunkCount > 0 || summary.biomeRecordType != nil
                    || summary.hasBlockEntities || summary.hasLegacyEntities
                    || summary.recordCount > (summary.hasActorDigest ? 1 : 0))
        }.map(\.position))
        self.globalPaletteVersion = nil
    }

    @discardableResult
    private func ensureGenerated(_ chunks: Set<ChunkPosition>) throws -> Int {
        let missing = chunks.subtracting(availableChunks)
        guard !missing.isEmpty else { return 0 }
        var puts = [(key: Data, value: Data)]()
        for chunk in missing.sorted(by: { lhs, rhs in
            if lhs.dimension != rhs.dimension { return lhs.dimension < rhs.dimension }
            if lhs.z != rhs.z { return lhs.z < rhs.z }
            return lhs.x < rhs.x
        }) {
            puts.append(contentsOf: BedrockEmptyChunk.metadataRecords(at: chunk).map { ($0.key, $0.value) })
        }
        try database.applyBatch(puts: puts, deletes: [], sync: true)
        availableChunks.formUnion(missing)
        for chunk in missing { chunkLegacyFormat[chunk] = false }
        return missing.count
    }

    func fill(region: CommandBlockBox, layer0: CommandBlockStateSpec, layer1: CommandBlockStateSpec) throws -> String {
        try validateVolume(region)
        let requestedChunks = chunks(in: region)
        let generatedCount = try ensureGenerated(requestedChunks)
        var changedBlocks: UInt64 = 0
        var touchedChunks = Set<ChunkPosition>()

        var x = region.minimum.x
        while x <= region.maximum.x {
            var z = region.minimum.z
            while z <= region.maximum.z {
                let chunk = chunkPosition(x: x, z: z)
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

        let entityResult = try removeBlockEntities(in: region, onlyLoadedChunks: false)
        let written = try commit(extraPuts: entityResult.puts, extraDeletes: entityResult.deletes)
        guard written > 0 || entityResult.changedCount > 0 || generatedCount > 0 else {
            throw BlocktopographError.unsupported("区域内没有产生任何方块变化")
        }
        return "fill 完成：修改 \(changedBlocks) 个方块位置，写入 \(written) 个 SubChunk，移除 \(entityResult.changedCount) 个原方块实体；处理 \(touchedChunks.count) 个区块，其中先生成 \(generatedCount) 个空气区块。"
    }

    static func clone(
        session: WorldSession,
        sourceDimension: Int32,
        source: CommandBlockBox,
        targetDimension: Int32,
        destination: CommandBlockCoordinate
    ) throws -> String {
        let sourceStore = try CommandBlockStore(session: session, dimension: sourceDimension)
        let targetStore = sourceDimension == targetDimension
            ? sourceStore
            : try CommandBlockStore(session: session, dimension: targetDimension)
        return try targetStore.clone(
            from: sourceStore,
            source: source,
            destination: destination
        )
    }

    private func clone(
        from sourceStore: CommandBlockStore,
        source: CommandBlockBox,
        destination: CommandBlockCoordinate
    ) throws -> String {
        try sourceStore.validateVolume(source)
        let targetRegion = try destinationRegion(for: source, destination: destination)
        try validateVolume(targetRegion)
        let generatedSourceChunks = try sourceStore.ensureGenerated(sourceStore.chunks(in: source))
        let generatedTargetChunks = try ensureGenerated(chunks(in: targetRegion))

        let deltaXResult = destination.x.subtractingReportingOverflow(source.minimum.x)
        let deltaYResult = destination.y.subtractingReportingOverflow(source.minimum.y)
        let deltaZResult = destination.z.subtractingReportingOverflow(source.minimum.z)
        guard !deltaXResult.overflow, !deltaYResult.overflow, !deltaZResult.overflow else {
            throw BlocktopographError.malformedData("clone 目标坐标偏移溢出")
        }
        let deltaX = deltaXResult.partialValue
        let deltaY = deltaYResult.partialValue
        let deltaZ = deltaZResult.partialValue

        var changedBlocks: UInt64 = 0
        var touchedDestinationChunks = Set<ChunkPosition>()

        // Read both entity collections before any write. This gives block entities
        // snapshot semantics even when source and target overlap in one dimension.
        let sourceEntityChunks = sourceStore.chunks(in: source).intersection(sourceStore.availableChunks)
        let targetEntityChunks = chunks(in: targetRegion).intersection(availableChunks)
        let sourceEntityState = try sourceStore.loadBlockEntities(for: sourceEntityChunks)
        let targetEntityState = try loadBlockEntities(for: targetEntityChunks)
        let sourceBlockEntities = sourceEntityState.documents
        var targetBlockEntities = targetEntityState.documents
        var changedEntityChunks = Set<ChunkPosition>()
        // Freeze every source SubChunk before the first target write. This is
        // required not only for overlapping X/Z ranges, but also when Y3 differs
        // from Y1 and source/target share the same CommandBlockStore cache.
        let sourceSnapshot = try sourceStore.snapshotSubChunks(in: source)

        // Equivalent to memmove: when source and target overlap, traverse each
        // shifted axis from the far side toward the near side. Future source reads
        // therefore always see the original source block instead of a block written
        // by an earlier iteration. This prevents one source block from cascading
        // through the entire overlap region.
        let traversal = CommandCloneTraversal(
            source: source,
            target: targetRegion,
            sameDimension: sourceStore.dimension == dimension
        )
        var x = traversal.startX
        while axisContains(x, minimum: source.minimum.x, maximum: source.maximum.x, step: traversal.stepX) {
            var y = traversal.startY
            while axisContains(y, minimum: source.minimum.y, maximum: source.maximum.y, step: traversal.stepY) {
                var z = traversal.startZ
                while axisContains(z, minimum: source.minimum.z, maximum: source.maximum.z, step: traversal.stepZ) {
                    let targetX = x.addingReportingOverflow(deltaX)
                    let targetY = y.addingReportingOverflow(deltaY)
                    let targetZ = z.addingReportingOverflow(deltaZ)
                    guard !targetX.overflow, !targetY.overflow, !targetZ.overflow else {
                        throw BlocktopographError.malformedData("clone 目标坐标溢出")
                    }
                    let sourceCoordinate = CommandBlockCoordinate(x: x, y: y, z: z)
                    let targetCoordinate = CommandBlockCoordinate(
                        x: targetX.partialValue,
                        y: targetY.partialValue,
                        z: targetZ.partialValue
                    )
                    let targetChunk = chunkPosition(x: targetCoordinate.x, z: targetCoordinate.z)
                    touchedDestinationChunks.insert(targetChunk)
                    let source0 = try sourceStore.state(layer: 0, at: sourceCoordinate, snapshot: sourceSnapshot)
                    let source1 = try sourceStore.state(layer: 1, at: sourceCoordinate, snapshot: sourceSnapshot)
                    let targetKey = try subKey(for: targetCoordinate)
                    let target0 = try adaptedState(source0, for: targetKey)
                    let target1 = try adaptedState(source1, for: targetKey)
                    let changed0 = try setState(target0, layer: 0, at: targetCoordinate, createWhenAir: false)
                    let changed1 = try setState(target1, layer: 1, at: targetCoordinate, createWhenAir: false)
                    if changed0 || changed1 { changedBlocks += 1 }

                    let sourceEntityKey = BlockEntityCoordinate(x: x, y: y, z: z)
                    let targetEntityKey = BlockEntityCoordinate(
                        x: targetCoordinate.x,
                        y: targetCoordinate.y,
                        z: targetCoordinate.z
                    )
                    if let sourceDocument = sourceBlockEntities[sourceEntityKey] {
                        targetBlockEntities[targetEntityKey] = offsetBlockEntity(sourceDocument, to: targetCoordinate)
                    } else {
                        targetBlockEntities.removeValue(forKey: targetEntityKey)
                    }
                    changedEntityChunks.insert(targetChunk)
                    z = nextAxisValue(z, step: traversal.stepZ)
                }
                y = nextAxisValue(y, step: traversal.stepY)
            }
            x = nextAxisValue(x, step: traversal.stepX)
        }

        let entityWrites = try encodeBlockEntities(
            documents: targetBlockEntities,
            changedChunks: changedEntityChunks,
            originalKeys: targetEntityState.keysByChunk
        )
        let written = try commit(extraPuts: entityWrites.puts, extraDeletes: entityWrites.deletes)
        guard written > 0 || !entityWrites.puts.isEmpty || !entityWrites.deletes.isEmpty
                || generatedSourceChunks > 0 || generatedTargetChunks > 0 else {
            throw BlocktopographError.unsupported("源区域内没有可复制的方块变化")
        }
        return "clone 完成：从 \(WorldCommandParser.dimensionName(for: sourceStore.dimension)) 复制到 \(WorldCommandParser.dimensionName(for: dimension))；修改 \(changedBlocks) 个方块位置，写入 \(written) 个 SubChunk；处理 \(touchedDestinationChunks.count) 个目标区块，先生成 \(generatedSourceChunks) 个源空气区块和 \(generatedTargetChunks) 个目标空气区块。重叠区域和不同 Y 偏移均按命令开始时的原始源数据复制。"
    }

    private func destinationRegion(
        for source: CommandBlockBox,
        destination: CommandBlockCoordinate
    ) throws -> CommandBlockBox {
        let width = source.maximum.x.subtractingReportingOverflow(source.minimum.x)
        let height = source.maximum.y.subtractingReportingOverflow(source.minimum.y)
        let depth = source.maximum.z.subtractingReportingOverflow(source.minimum.z)
        guard !width.overflow, !height.overflow, !depth.overflow else {
            throw BlocktopographError.malformedData("clone 源区域尺寸溢出")
        }
        let maximumX = destination.x.addingReportingOverflow(width.partialValue)
        let maximumY = destination.y.addingReportingOverflow(height.partialValue)
        let maximumZ = destination.z.addingReportingOverflow(depth.partialValue)
        guard !maximumX.overflow, !maximumY.overflow, !maximumZ.overflow else {
            throw BlocktopographError.malformedData("clone 目标区域坐标溢出")
        }
        return CommandBlockBox(
            destination,
            CommandBlockCoordinate(
                x: maximumX.partialValue,
                y: maximumY.partialValue,
                z: maximumZ.partialValue
            )
        )
    }

    private func axisContains<T: FixedWidthInteger>(
        _ value: T,
        minimum: T,
        maximum: T,
        step: T
    ) -> Bool {
        step > 0 ? value <= maximum : value >= minimum
    }

    private func nextAxisValue<T: FixedWidthInteger>(_ value: T, step: T) -> T {
        value.addingReportingOverflow(step).partialValue
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


    private func snapshotSubChunks(in region: CommandBlockBox) throws -> [SubKey: CachedSubChunk] {
        let minimumSubY = try subChunkY(for: region.minimum.y)
        let maximumSubY = try subChunkY(for: region.maximum.y)
        var snapshot = [SubKey: CachedSubChunk]()
        for chunk in chunks(in: region) where availableChunks.contains(chunk) {
            for rawY in Int(minimumSubY)...Int(maximumSubY) {
                guard let y = Int8(exactly: rawY) else { continue }
                let key = SubKey(chunk: chunk, y: y)
                snapshot[key] = try load(key)
            }
        }
        return snapshot
    }

    private func state(
        layer: Int,
        at coordinate: CommandBlockCoordinate,
        snapshot: [SubKey: CachedSubChunk]
    ) throws -> BedrockBlockState {
        let key = try subKey(for: coordinate)
        switch snapshot[key] ?? .missing {
        case .missing:
            // A missing source SubChunk is air. Use modern air here; adaptedState
            // converts it to numeric ID 0 when the destination is legacy.
            return .editableAir(version: globalPaletteVersion)
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
        for chunk in availableChunks.prefix(32) {
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
        let relevant = chunks(in: region).filter { !onlyLoadedChunks || availableChunks.contains($0) }
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
