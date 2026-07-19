import Foundation

enum WorldCommandOutputStyle {
    case success
    case localPlayer
    case onlinePlayer
    case entity
}

struct WorldCommandOutputLine {
    let text: String
    let style: WorldCommandOutputStyle
}

struct WorldCommandExecutionResult {
    let message: String
    let changedWorld: Bool
    let outputLines: [WorldCommandOutputLine]

    init(message: String, changedWorld: Bool, outputLines: [WorldCommandOutputLine] = []) {
        self.message = message
        self.changedWorld = changedWorld
        self.outputLines = outputLines
    }
}

private struct SpreadDestination {
    let dimension: Int32
    let x: Int64
    let y: Int32
    let z: Int64
}

private struct ResolvedCommandTargets {
    let players: [PlayerNBTRecord]
    let entities: [BedrockWorldObject]

    var isEmpty: Bool { players.isEmpty && entities.isEmpty }
}

private enum EntitySelectionIdentity: Hashable {
    case uniqueID(Int64)
    case modernActor(Data, Int)
    case chunkRecord(Data, Int)
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
        case .give(let target, let itemIdentifier, let count, let itemTags):
            return WorldCommandExecutionResult(
                message: try give(target: target, itemIdentifier: itemIdentifier, count: count, itemTags: itemTags),
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
        case .effect(let operation, let target, let selection):
            let result = try effect(operation: operation, target: target, selection: selection)
            return WorldCommandExecutionResult(message: result.message, changedWorld: result.changed)
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
        case .setBlock(let targetDimension, let position, let layer0, let layer1):
            let region = CommandBlockBox(position, position)
            let result = try CommandBlockStore(session: session, dimension: targetDimension)
                .fill(region: region, layer0: layer0, layer1: layer1)
            return WorldCommandExecutionResult(
                message: result.replacingOccurrences(of: "fill 完成", with: "setblock 完成"),
                changedWorld: true
            )
        case .setWorldSpawn(let position):
            return WorldCommandExecutionResult(message: try setWorldSpawn(position), changedWorld: true)
        case .spawnPoint(let target, let dimension, let position):
            return WorldCommandExecutionResult(
                message: try setPlayerSpawnPoints(target: target, dimension: dimension, position: position),
                changedWorld: true
            )
        case .teleport(let target, let dimension, let x, let y, let z):
            return WorldCommandExecutionResult(
                message: try teleport(target: target, dimension: dimension, x: x, y: y, z: z),
                changedWorld: true
            )
        case .spread(let target):
            return try spread(target: target)
        case .dayLock(let locked):
            return WorldCommandExecutionResult(message: try setDayLock(locked), changedWorld: true)
        case .weather(let settings):
            return WorldCommandExecutionResult(message: try setWeather(settings), changedWorld: true)
        case .time(let operation):
            let result = try executeTime(operation)
            return WorldCommandExecutionResult(message: result.message, changedWorld: result.changed)
        case .experience(let operation):
            return try executeExperience(operation)
        case .structure(let operation):
            let result = try executeStructure(operation)
            return WorldCommandExecutionResult(message: result.message, changedWorld: result.changed)
        case .tickingArea(let operation):
            let result = try executeTickingArea(operation)
            return WorldCommandExecutionResult(message: result.message, changedWorld: result.changed)
        }
    }

    // MARK: world spawn / player spawn

    private func setWorldSpawn(_ position: CommandBlockCoordinate) throws -> String {
        guard let x = Int32(exactly: position.x), let z = Int32(exactly: position.z) else {
            throw BlocktopographError.malformedData("世界重生点 X/Z 必须在 Int32 范围内")
        }
        var file = try session.document.readLevelDat()
        guard case .compound(var tags) = file.document.root else {
            throw BlocktopographError.malformedData("level.dat 根标签不是 Compound")
        }
        setTopLevelTag(name: "SpawnX", value: .int(x), in: &tags)
        setTopLevelTag(name: "SpawnY", value: .int(position.y), in: &tags)
        setTopLevelTag(name: "SpawnZ", value: .int(z), in: &tags)
        file.document.root = .compound(tags)
        try session.document.writeLevelDat(file)
        return "setworldspawn 完成：世界重生点设为 \(x) \(position.y) \(z)。"
    }

    private func setPlayerSpawnPoints(
        target: CommandTarget,
        dimension: Int32,
        position: CommandBlockCoordinate
    ) throws -> String {
        guard let x = Int32(exactly: position.x), let z = Int32(exactly: position.z) else {
            throw BlocktopographError.malformedData("玩家重生点 X/Z 必须在 Int32 范围内")
        }
        let targets = try resolveTargets(target)
        guard !targets.players.isEmpty else {
            throw BlocktopographError.unsupported("目标 \(target.displayText) 没有匹配到玩家；spawnpoint 不能用于普通实体")
        }
        var puts = [(key: Data, value: Data)]()
        puts.reserveCapacity(targets.players.count)
        for record in targets.players {
            guard case .compound(var tags) = record.document.root else {
                throw BlocktopographError.malformedData("玩家 \(playerIdentity(record)) 的 NBT 根不是 Compound")
            }
            setTopLevelTag(name: "SpawnX", value: .int(x), in: &tags)
            setTopLevelTag(name: "SpawnY", value: .int(position.y), in: &tags)
            setTopLevelTag(name: "SpawnZ", value: .int(z), in: &tags)
            setTopLevelTag(name: "SpawnDimension", value: .int(dimension), in: &tags)
            setTopLevelTag(name: "SpawnForced", value: .byte(1), in: &tags)
            let document = NBTDocument(rootName: record.document.rootName, root: .compound(tags))
            puts.append((record.key, try BedrockNBTCodec.encode(document, encoding: .littleEndian)))
        }
        try session.database().applyBatch(puts: puts, deletes: [], sync: true)
        return "spawnpoint 完成：设置 \(puts.count) 个玩家的重生点为 \(WorldCommandParser.dimensionName(for: dimension)) \(x) \(position.y) \(z)。"
    }

    private func setTopLevelTag(name: String, value: NBTValue, in tags: inout [NBTNamedTag]) {
        let matches = tags.indices.filter { tags[$0].name.caseInsensitiveCompare(name) == .orderedSame }
        if let first = matches.first {
            tags[first] = NBTNamedTag(name: name, value: value)
            for index in matches.dropFirst().reversed() { tags.remove(at: index) }
        } else {
            tags.append(NBTNamedTag(name: name, value: value))
        }
    }

    // MARK: teleport / weather

    private func teleport(
        target: CommandTarget,
        dimension: Int32,
        x: Int64,
        y: CommandTeleportY,
        z: Int64
    ) throws -> String {
        let resolvedY: Int32
        switch y {
        case .fixed(let value):
            resolvedY = value
        case .automatic:
            resolvedY = try automaticTeleportY(x: x, z: z, dimension: dimension)
        }

        let targets = try resolveTargets(target)
        let position = BedrockWorldObjectPosition(x: Double(x), y: Double(resolvedY), z: Double(z))
        var playerPuts = [(key: Data, value: Data)]()
        playerPuts.reserveCapacity(targets.players.count)
        for record in targets.players {
            let document = try teleportedDocument(
                record.document,
                position: position,
                dimension: dimension
            )
            playerPuts.append((
                key: record.key,
                value: try BedrockNBTCodec.encode(document, encoding: .littleEndian)
            ))
        }
        if !playerPuts.isEmpty {
            try session.database().applyBatch(puts: playerPuts, deletes: [], sync: true)
        }

        let entityStore = BedrockWorldObjectNBTStore(session: session)
        var movedEntities = 0
        for object in stableEntityMutationOrder(targets.entities) {
            let document = try teleportedDocument(
                object.document,
                position: position,
                dimension: dimension
            )
            _ = try entityStore.save(object: object, document: document)
            movedEntities += 1
        }

        let yText = y.displayText == "Auto" ? "Auto→\(resolvedY)" : String(resolvedY)
        return "teleport 完成：将 \(targets.players.count) 个玩家和 \(movedEntities) 个实体传送到 \(WorldCommandParser.dimensionName(for: dimension)) 的 \(x) \(yText) \(z)。"
    }

    private func automaticTeleportY(x: Int64, z: Int64, dimension: Int32) throws -> Int32 {
        let renderer = ChunkSurfaceRenderer(database: try session.database())
        return try nonAirTeleportY(x: x, z: z, dimension: dimension, renderer: renderer) ?? 63
    }

    private func nonAirTeleportY(
        x: Int64,
        z: Int64,
        dimension: Int32,
        renderer: ChunkSurfaceRenderer
    ) throws -> Int32? {
        let minimum = Int64(Int32.min) * 16
        let maximum = Int64(Int32.max) * 16 + 15
        guard (minimum...maximum).contains(x), (minimum...maximum).contains(z) else {
            throw BlocktopographError.malformedData("Auto 的 X/Z 超出 Bedrock Int32 区块坐标范围")
        }
        let column = try renderer.blockColumn(blockX: x, blockZ: z, dimension: dimension)
        let blocks = column.blocks
        guard let highestIndex = blocks.firstIndex(where: isGeneratedNonAirBlock) else { return nil }
        let highest = blocks[highestIndex]

        if dimension == 1 {
            let belowHighest = blocks.index(after: highestIndex)..<blocks.endIndex
            if let airIndex = belowHighest.first(where: { isGeneratedAirBlock(blocks[$0]) }) {
                let belowAir = blocks.index(after: airIndex)..<blocks.endIndex
                if let lowerSolidIndex = belowAir.first(where: { isGeneratedNonAirBlock(blocks[$0]) }) {
                    return try blockAboveY(blocks[lowerSolidIndex], context: "下界内部最高非空气方块")
                }
            }
        }
        return try blockAboveY(highest, context: "最高非空气方块")
    }

    private func isGeneratedNonAirBlock(_ block: BedrockBlockRecord) -> Bool {
        block.isGenerated && block.layers.contains(where: { !$0.isAir })
    }

    private func isGeneratedAirBlock(_ block: BedrockBlockRecord) -> Bool {
        block.isGenerated && !block.layers.contains(where: { !$0.isAir })
    }

    private func blockAboveY(_ block: BedrockBlockRecord, context: String) throws -> Int32 {
        guard block.y < Int32.max else {
            throw BlocktopographError.malformedData("\(context)上方的 Y 坐标溢出")
        }
        return block.y + 1
    }

    private func teleportedDocument(
        _ source: NBTDocument,
        position: BedrockWorldObjectPosition,
        dimension: Int32
    ) throws -> NBTDocument {
        guard case .compound(var tags) = source.root else {
            throw BlocktopographError.malformedData("玩家或实体 NBT 根必须是 Compound")
        }
        setTopLevelTag(
            name: "Pos",
            value: .list(.float, [
                .float(Float(position.x)),
                .float(Float(position.y)),
                .float(Float(position.z))
            ]),
            in: &tags
        )
        setTopLevelTag(name: "DimensionId", value: .int(dimension), in: &tags)
        setTopLevelTag(name: "LastDimensionId", value: .int(dimension), in: &tags)
        setTopLevelTag(
            name: "Motion",
            value: .list(.float, [.float(0), .float(0), .float(0)]),
            in: &tags
        )
        return NBTDocument(rootName: source.rootName, root: .compound(tags))
    }

    private func spread(target: CommandTarget) throws -> WorldCommandExecutionResult {
        let targets = try resolveTargets(target)
        let supportedDimensions: Set<Int32> = [0, 1, 2]
        let summaries = try BedrockChunkStore(session: session).listChunks().filter {
            $0.subChunkCount > 0 && supportedDimensions.contains($0.position.dimension)
        }
        let grouped = Dictionary(grouping: summaries, by: { $0.position.dimension })
            .mapValues { $0.map(\.position) }
        let dimensions = grouped.keys.sorted()
        guard !dimensions.isEmpty else {
            throw BlocktopographError.unsupported("世界中没有包含方块数据的已加载区块，无法执行 spread。")
        }

        let renderer = ChunkSurfaceRenderer(database: try session.database())
        var generator = SystemRandomNumberGenerator()
        var lines = [WorldCommandOutputLine]()
        var playerPuts = [(key: Data, value: Data)]()
        playerPuts.reserveCapacity(targets.players.count)

        // PlayerNBTStore already sorts the local player before online players.
        for record in targets.players {
            let destination = try randomSpreadDestination(
                groupedChunks: grouped,
                dimensions: dimensions,
                renderer: renderer,
                generator: &generator
            )
            let position = BedrockWorldObjectPosition(
                x: Double(destination.x), y: Double(destination.y), z: Double(destination.z)
            )
            let document = try teleportedDocument(
                record.document,
                position: position,
                dimension: destination.dimension
            )
            playerPuts.append((
                key: record.key,
                value: try BedrockNBTCodec.encode(document, encoding: .littleEndian)
            ))
            let style: WorldCommandOutputStyle = isLocalPlayer(record) ? .localPlayer : .onlinePlayer
            lines.append(WorldCommandOutputLine(
                text: spreadOutputLine(
                    identifier: "minecraft:player",
                    uniqueID: playerUniqueID(record),
                    destination: destination
                ),
                style: style
            ))
        }
        if !playerPuts.isEmpty {
            try session.database().applyBatch(puts: playerPuts, deletes: [], sync: true)
        }

        let entityStore = BedrockWorldObjectNBTStore(session: session)
        for object in stableEntityMutationOrder(targets.entities) {
            let destination = try randomSpreadDestination(
                groupedChunks: grouped,
                dimensions: dimensions,
                renderer: renderer,
                generator: &generator
            )
            let position = BedrockWorldObjectPosition(
                x: Double(destination.x), y: Double(destination.y), z: Double(destination.z)
            )
            let document = try teleportedDocument(
                object.document,
                position: position,
                dimension: destination.dimension
            )
            _ = try entityStore.save(object: object, document: document)
            lines.append(WorldCommandOutputLine(
                text: spreadOutputLine(
                    identifier: selectableIdentifier(object),
                    uniqueID: object.uniqueID,
                    destination: destination
                ),
                style: .entity
            ))
        }

        return WorldCommandExecutionResult(
            message: lines.map(\.text).joined(separator: "\n"),
            changedWorld: true,
            outputLines: lines
        )
    }

    private func randomSpreadDestination<R: RandomNumberGenerator>(
        groupedChunks: [Int32: [ChunkPosition]],
        dimensions: [Int32],
        renderer: ChunkSurfaceRenderer,
        generator: inout R
    ) throws -> SpreadDestination {
        guard let firstDimension = dimensions.randomElement(using: &generator) else {
            throw BlocktopographError.unsupported("没有可用于 spread 的维度。")
        }
        var dimensionOrder = [firstDimension]
        dimensionOrder.append(contentsOf: dimensions.filter { $0 != firstDimension }.shuffled(using: &generator))

        for dimension in dimensionOrder {
            guard let chunks = groupedChunks[dimension], !chunks.isEmpty else { continue }
            for chunk in chunks.shuffled(using: &generator) {
                var columns = Array(0..<256)
                columns.shuffle(using: &generator)
                for columnIndex in columns {
                    let localX = columnIndex & 15
                    let localZ = columnIndex >> 4
                    let x = MapCoordinate.blockOrigin(ofChunk: chunk.x) + Int64(localX)
                    let z = MapCoordinate.blockOrigin(ofChunk: chunk.z) + Int64(localZ)
                    do {
                        if let y = try nonAirTeleportY(
                            x: x,
                            z: z,
                            dimension: dimension,
                            renderer: renderer
                        ) {
                            return SpreadDestination(dimension: dimension, x: x, y: y, z: z)
                        }
                    } catch {
                        // A damaged column must not prevent trying the remaining
                        // loaded chunks and coordinates.
                        continue
                    }
                }
            }
        }
        throw BlocktopographError.unsupported("所有已加载区块都没有可用的非空气方块列，无法执行 spread。")
    }

    private func spreadOutputLine(identifier: String, uniqueID: Int64?, destination: SpreadDestination) -> String {
        let dimensionName: String
        switch destination.dimension {
        case 0: dimensionName = "主世界"
        case 1: dimensionName = "下界"
        case 2: dimensionName = "末地"
        default: dimensionName = "维度 \(destination.dimension)"
        }
        return "\(identifier) \(uniqueID.map(String.init) ?? "无UniqueID") \(dimensionName) \(destination.x) \(destination.y) \(destination.z)"
    }

    private func setDayLock(_ locked: Bool) throws -> String {
        var file = try session.document.readLevelDat()
        guard case .compound(var tags) = file.document.root else {
            throw BlocktopographError.malformedData("level.dat 根标签不是 Compound")
        }
        let cycleEnabled = !locked
        setTopLevelTag(name: "dodaylightcycle", value: .byte(cycleEnabled ? 1 : 0), in: &tags)
        file.document.root = .compound(tags)
        try session.document.writeLevelDat(file)
        return "daylock 完成：锁定=\(locked ? 1 : 0)，dodaylightcycle=\(cycleEnabled ? 1 : 0)"
    }

    private func setWeather(_ command: CommandWeatherSettings) throws -> String {
        let settings: BedrockWeatherSettings
        switch command.condition {
        case .clear:
            settings = .clear(automaticChange: command.automaticChange)
        case .rain:
            guard let duration = command.duration, let intensity = command.intensity else {
                throw BlocktopographError.malformedData("weather rain 缺少持续时间或强度")
            }
            settings = .rain(
                duration: duration,
                intensity: intensity,
                automaticChange: command.automaticChange
            )
        case .thunder:
            guard let duration = command.duration, let intensity = command.intensity else {
                throw BlocktopographError.malformedData("weather thunder 缺少持续时间或强度")
            }
            settings = .thunder(
                duration: duration,
                intensity: intensity,
                automaticChange: command.automaticChange
            )
        }
        try WeatherStore(session: session).save(settings)
        let automatic = settings.automaticChange ? "允许自动变化" : "禁止自动变化"
        switch command.condition {
        case .clear:
            return "weather 完成：天气设为晴朗，\(automatic)。"
        case .rain, .thunder:
            return String(
                format: "weather 完成：天气设为%@，持续 %d 游戏刻，强度 %.3g，%@。",
                settings.conditionName,
                settings.rainTime,
                Double(settings.rainLevel),
                automatic
            )
        }
    }

    // MARK: experience

    private func executeExperience(_ operation: CommandExperienceOperation) throws -> WorldCommandExecutionResult {
        let target: CommandTarget
        switch operation {
        case .amount(let value, _), .level(let value, _), .percent(let value, _), .query(let value), .set(let value, _):
            target = value
        }
        let targets = try resolveTargets(target)
        guard !targets.players.isEmpty else {
            throw BlocktopographError.unsupported("目标 \(target.displayText) 没有匹配到玩家；experience 不能用于普通实体")
        }

        let store = ExperienceStore(session: session)
        if case .query = operation {
            let lines = try targets.players.map { record -> WorldCommandOutputLine in
                let experience = try ExperienceStore.read(from: record.document)
                let uniqueID = playerUniqueID(record).map(String.init) ?? "无UniqueID"
                let text = String(
                    format: "minecraft:player %@ 经验总数 %lld 经验等级 %d 当前经验条进度 %.3f",
                    uniqueID,
                    experience.total,
                    experience.level,
                    Double(experience.progress)
                )
                return WorldCommandOutputLine(
                    text: text,
                    style: isLocalPlayer(record) ? .localPlayer : .onlinePlayer
                )
            }
            return WorldCommandExecutionResult(
                message: lines.map(\.text).joined(separator: "\n"),
                changedWorld: false,
                outputLines: lines
            )
        }

        var updates = [(record: PlayerNBTRecord, experience: BedrockPlayerExperience)]()
        updates.reserveCapacity(targets.players.count)
        for record in targets.players {
            var experience = try ExperienceStore.read(from: record.document)
            switch operation {
            case .amount(_, let delta):
                let (sum, overflow) = experience.total.addingReportingOverflow(delta)
                guard !overflow else {
                    throw BlocktopographError.malformedData("experience amount 结果超出 Int64 范围")
                }
                let bounded = min(BedrockPlayerExperience.maximumTotal, max(0, sum))
                experience = try BedrockPlayerExperience.fromTotal(bounded)
            case .level(_, let delta):
                let current = Int64(experience.level)
                let (sum, overflow) = current.addingReportingOverflow(delta)
                guard !overflow else {
                    throw BlocktopographError.malformedData("experience level 结果超出 Int64 范围")
                }
                let level = Int32(clamping: min(Int64(BedrockPlayerExperience.maximumLevel), max(0, sum)))
                experience = BedrockPlayerExperience(level: level, progress: experience.progress)
            case .percent(_, let progress):
                experience = BedrockPlayerExperience(level: experience.level, progress: progress)
            case .set(_, let total):
                experience = try BedrockPlayerExperience.fromTotal(total)
            case .query:
                break
            }
            updates.append((record, experience))
        }
        try store.saveBatch(updates)

        let action: String
        switch operation {
        case .amount(_, let delta): action = "amount \(delta)"
        case .level(_, let delta): action = "level \(delta)"
        case .percent(_, let progress): action = String(format: "percent %.3f", Double(progress))
        case .set(_, let total): action = "set \(total)"
        case .query: action = "query"
        }
        return WorldCommandExecutionResult(
            message: "experience \(action) 完成：修改 \(updates.count) 个玩家。",
            changedWorld: true
        )
    }

    // MARK: time

    private func executeTime(_ operation: CommandTimeOperation) throws -> (message: String, changed: Bool) {
        let current = try BedrockTimeStore.read(session: session).time

        switch operation {
        case .query(let query):
            switch query {
            case .gametime:
                return ("gametime=\(current)", false)
            case .day:
                return ("day=\(BedrockTimeStore.floorDivision(current, by: 24_000))", false)
            case .daytime:
                return (BedrockTimeStore.daytimeSummary(current), false)
            }

        case .add(let delta):
            let (updated, overflow) = current.addingReportingOverflow(delta)
            guard !overflow else {
                throw BlocktopographError.malformedData("time add 结果超出 Int64 范围")
            }
            try BedrockTimeStore.saveTime(updated, session: session)
            return ("time add 完成：time=\(updated)", true)

        case .set(let value):
            try BedrockTimeStore.saveTime(value, session: session)
            return ("time set 完成：time=\(value)", true)

        case .ceil(let period):
            let value = try BedrockTimeStore.alignedTime(current, startTick: period.startTick, roundingUp: true)
            try BedrockTimeStore.saveTime(value, session: session)
            return ("time ceil \(period.rawValue) 完成：time=\(value)", true)

        case .floor(let period):
            let value = try BedrockTimeStore.alignedTime(current, startTick: period.startTick, roundingUp: false)
            try BedrockTimeStore.saveTime(value, session: session)
            return ("time floor \(period.rawValue) 完成：time=\(value)", true)
        }
    }

    // MARK: structure

    private func executeStructure(_ operation: CommandStructureOperation) throws -> (message: String, changed: Bool) {
        let store = StructureNBTStore(session: session)
        switch operation {
        case .save(let name, let dimension, let region):
            let document = try CommandBlockStore.makeStructureDocument(
                session: session,
                dimension: dimension,
                region: region
            )
            try store.save(document: document, named: name, overwrite: true)
            return (
                "structure save 完成：\(name)，维度 \(WorldCommandParser.dimensionName(for: dimension))，范围 \(region.minimum.x) \(region.minimum.y) \(region.minimum.z) 至 \(region.maximum.x) \(region.maximum.y) \(region.maximum.z)。",
                true
            )
        case .load(let name, let dimension, let destination):
            guard let record = try store.record(named: name), let document = record.document else {
                throw BlocktopographError.unsupported("不存在结构：\(name)")
            }
            let message = try CommandBlockStore.loadStructure(
                session: session,
                document: document,
                targetDimension: dimension,
                destination: destination
            )
            return ("structure load 完成：\(name)。\n\(message)", true)
        case .delete(let name):
            if let name = name {
                guard try store.delete(named: name) else {
                    throw BlocktopographError.unsupported("不存在结构：\(name)")
                }
                return ("structure delete 完成：已删除 \(name)。", true)
            }
            let count = try store.deleteAll()
            return ("structure delete 完成：删除全部 \(count) 个已保存结构。", count > 0)
        }
    }

    // MARK: tickingarea

    private func executeTickingArea(_ operation: CommandTickingAreaOperation) throws -> (message: String, changed: Bool) {
        let store = TickingAreaStore(session: session)
        var records = try store.records(migratingLegacy: true)
        switch operation {
        case .add(let spec):
            let area = BedrockTickingArea(
                dimension: spec.dimension,
                isCircle: spec.isCircle,
                minimumX: spec.minimumX,
                minimumZ: spec.minimumZ,
                maximumX: spec.maximumX,
                maximumZ: spec.maximumZ,
                name: spec.name,
                preload: spec.preload
            ).normalized
            let removedCount = records.count
            records.removeAll { $0.area.name.caseInsensitiveCompare(area.name) == .orderedSame }
            let replaced = records.count != removedCount
            records.append(try store.makeRecord(area: area))
            try store.save(records)
            let action = replaced ? "覆盖" : "创建"
            return ("tickingarea add 完成：已\(action) \(tickingAreaLine(area, index: records.count))", true)
        case .delete(let name):
            if let name = name {
                let originalCount = records.count
                records.removeAll { $0.area.name.caseInsensitiveCompare(name) == .orderedSame }
                guard records.count != originalCount else {
                    throw BlocktopographError.unsupported("不存在常加载区域：\(name)")
                }
                try store.save(records)
                return ("tickingarea delete 完成：删除名称为 \(name) 的 \(originalCount - records.count) 个区域。", true)
            }
            let count = records.count
            try store.save([])
            return ("tickingarea delete 完成：删除全部 \(count) 个常加载区域。", count > 0)
        case .list(let dimension):
            let filtered = records.filter { dimension == nil || $0.area.dimension == dimension }
            if filtered.isEmpty {
                let scope = dimension.map { WorldCommandParser.dimensionName(for: $0) } ?? "ALL"
                return ("tickingarea list：\(scope) 没有常加载区域。", false)
            }
            let lines = filtered.enumerated().map { tickingAreaLine($0.element.area, index: $0.offset + 1) }
            return (lines.joined(separator: "\n"), false)
        }
    }

    private func tickingAreaLine(_ area: BedrockTickingArea, index: Int) -> String {
        let name = area.name.isEmpty ? "未命名" : area.name
        if area.isCircle {
            let center = area.centerChunk
            return "[\(index)]\(name): \(center.x) \(center.z) radius: \(area.radius)"
        }
        let value = area.normalized
        return "[\(index)]\(name): \(value.minimumX) \(value.minimumZ) to \(value.maximumX) \(value.maximumZ)"
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


    // MARK: effect

    private func effect(
        operation: CommandEffectOperation,
        target: CommandTarget,
        selection: CommandEffectSelection
    ) throws -> (message: String, changed: Bool) {
        let targets = try resolveTargets(target)
        var playerPuts = [(key: Data, value: Data)]()
        var entityReplacements = [(object: BedrockWorldObject, document: NBTDocument)]()
        var changedPlayers = 0
        var changedEntities = 0
        var skippedPlayers = 0
        var skippedEntities = 0

        // Build every mutation before the first write. A malformed ActiveEffects
        // value in any target therefore aborts the whole command instead of
        // leaving a partially modified selector result.
        for record in targets.players {
            let mutation = try CommandEffectNBT.applying(
                operation: operation,
                selection: selection,
                to: record.document.root
            )
            guard mutation.changed else {
                skippedPlayers += 1
                continue
            }
            var document = record.document
            document.root = mutation.value
            playerPuts.append((
                key: record.key,
                value: try BedrockNBTCodec.encode(document, encoding: .littleEndian)
            ))
            changedPlayers += 1
        }

        for object in targets.entities {
            let mutation = try CommandEffectNBT.applying(
                operation: operation,
                selection: selection,
                to: object.document.root
            )
            guard mutation.changed else {
                skippedEntities += 1
                continue
            }
            var document = object.document
            document.root = mutation.value
            entityReplacements.append((object: object, document: document))
            changedEntities += 1
        }

        let entityPuts = try encodedUnmovedEntityReplacements(entityReplacements)
        let allPuts = playerPuts + entityPuts
        if !allPuts.isEmpty {
            try session.database().applyBatch(puts: allPuts, deletes: [], sync: true)
        }

        let effectText = selection.displayText
        switch operation {
        case .give(let duration, let amplifier):
            return (
                "effect give 完成：向 \(changedPlayers) 个玩家和 \(changedEntities) 个实体给予 \(effectText)，持续 \(duration) 游戏刻，等级 \(Int(amplifier) + 1)。",
                !allPuts.isEmpty
            )
        case .clear:
            return (
                "effect clear 完成：从 \(changedPlayers) 个玩家和 \(changedEntities) 个实体移除 \(effectText)；跳过 \(skippedPlayers) 个玩家和 \(skippedEntities) 个没有对应状态效果的实体。",
                !allPuts.isEmpty
            )
        }
    }

    private func encodedUnmovedEntityReplacements(
        _ replacements: [(object: BedrockWorldObject, document: NBTDocument)]
    ) throws -> [(key: Data, value: Data)] {
        guard !replacements.isEmpty else { return [] }
        let database = try session.database()
        var groups = [Data: [(object: BedrockWorldObject, document: NBTDocument)]]()
        for replacement in replacements {
            groups[replacement.object.storage.primaryKey, default: []].append(replacement)
        }

        var puts = [(key: Data, value: Data)]()
        puts.reserveCapacity(groups.count)
        for (key, group) in groups {
            guard let original = try database.get(key) else {
                throw BlocktopographError.malformedData("实体源 NBT 记录已不存在，请重新扫描。")
            }
            var records = try ConsecutiveNBTCodec.decode(original)
            var occupiedIndexes = Set<Int>()
            for replacement in group {
                let object = replacement.object
                let index: Int
                let preferred = object.storage.recordIndex
                if records.indices.contains(preferred), records[preferred].rawData == object.rawData {
                    index = preferred
                } else if let uniqueID = object.uniqueID,
                          let located = records.firstIndex(where: {
                              $0.document.root.int64Value(namedAny: ["UniqueID", "UniqueId", "uniqueID", "uniqueId"]) == uniqueID
                          }) {
                    index = located
                } else if let located = records.firstIndex(where: { $0.rawData == object.rawData }) {
                    index = located
                } else {
                    throw BlocktopographError.malformedData("实体记录已经变化，无法应用状态效果；请重新扫描。")
                }
                guard occupiedIndexes.insert(index).inserted else {
                    throw BlocktopographError.malformedData("同一实体在目标选择器中重复出现。")
                }
                let originalID = object.document.root.int64Value(namedAny: ["UniqueID", "UniqueId", "uniqueID", "uniqueId"])
                let editedID = replacement.document.root.int64Value(namedAny: ["UniqueID", "UniqueId", "uniqueID", "uniqueId"])
                guard originalID == editedID else {
                    throw BlocktopographError.malformedData("effect 命令不能修改实体 UniqueID。")
                }
                records[index].document = replacement.document
                records[index].rawData = try BedrockNBTCodec.encode(
                    replacement.document,
                    encoding: records[index].encoding
                )
            }
            puts.append((key: key, value: try ConsecutiveNBTCodec.encode(records)))
        }
        return puts
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
            allEntities = deduplicatedEntities(
                scan.objects.filter { $0.kind == .entity && !isPlayerEntity($0) }
            )
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
                entities = allEntities.filter { selectableIdentifier($0) == wanted }
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

    private func deduplicatedEntities(_ entities: [BedrockWorldObject]) -> [BedrockWorldObject] {
        var seen = Set<EntitySelectionIdentity>()
        return entities.filter { seen.insert(entitySelectionIdentity($0)).inserted }
    }

    private func stableEntityMutationOrder(_ entities: [BedrockWorldObject]) -> [BedrockWorldObject] {
        entities.sorted { lhs, rhs in
            let left = entityStoragePosition(lhs)
            let right = entityStoragePosition(rhs)
            if left.key != right.key { return left.key.lexicographicallyPrecedes(right.key) }
            return left.recordIndex > right.recordIndex
        }
    }

    private func entitySelectionIdentity(_ object: BedrockWorldObject) -> EntitySelectionIdentity {
        if let uniqueID = object.uniqueID { return .uniqueID(uniqueID) }
        switch object.storage {
        case .modernActor(let actorKey, _, let recordIndex, _):
            return .modernActor(actorKey, recordIndex)
        case .chunkRecord(let sourceKey, let recordIndex, _):
            return .chunkRecord(sourceKey, recordIndex)
        }
    }

    private func entityStoragePosition(_ object: BedrockWorldObject) -> (key: Data, recordIndex: Int) {
        switch object.storage {
        case .modernActor(let actorKey, _, let recordIndex, _): return (actorKey, recordIndex)
        case .chunkRecord(let sourceKey, let recordIndex, _): return (sourceKey, recordIndex)
        }
    }

    private func isPlayerEntity(_ object: BedrockWorldObject) -> Bool {
        selectableIdentifier(object) == "minecraft:player"
    }

    private func selectableIdentifier(_ object: BedrockWorldObject) -> String {
        let root = object.document.root
        if let direct = root.stringValue(namedAny: ["identifier", "Identifier"]), !direct.isEmpty {
            return normalizedIdentifier(direct)
        }
        if let first = root.value(namedAny: ["definitions", "Definitions"])?.listValues?.first,
           case .string(var definition) = first {
            while definition.first == "+" || definition.first == "-" { definition.removeFirst() }
            if !definition.isEmpty { return normalizedIdentifier(definition) }
        }
        return normalizedIdentifier(object.identifier)
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

    private func give(
        target: CommandTarget,
        itemIdentifier: String,
        count: Int64,
        itemTags: [NBTNamedTag]
    ) throws -> String {
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
                count: count,
                itemTags: itemTags
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
                count: count,
                itemTags: itemTags
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

    private func itemStack(
        identifier: String,
        count: Int64,
        slot: Int8? = nil,
        wasPickedUp: Int8 = 0,
        itemTags: [NBTNamedTag] = []
    ) -> NBTValue {
        var tags = [
            NBTNamedTag(name: "Name", value: .string(identifier)),
            NBTNamedTag(name: "Count", value: unboundedCountValue(count)),
            NBTNamedTag(name: "Damage", value: .short(0)),
            NBTNamedTag(name: "WasPickedUp", value: .byte(wasPickedUp))
        ]
        if let slot = slot { tags.append(NBTNamedTag(name: "Slot", value: .byte(slot))) }
        for addition in itemTags {
            if let index = tags.firstIndex(where: {
                $0.name.caseInsensitiveCompare(addition.name) == .orderedSame
            }) {
                tags[index] = addition
            } else {
                tags.append(addition)
            }
        }
        // The dedicated command parameters remain authoritative even when the
        // optional item-NBT argument contains tags with the same names.
        replaceItemTag(named: "Name", with: .string(identifier), in: &tags)
        replaceItemTag(named: "Count", with: unboundedCountValue(count), in: &tags)
        replaceItemTag(named: "WasPickedUp", with: .byte(wasPickedUp), in: &tags)
        if let slot = slot { replaceItemTag(named: "Slot", with: .byte(slot), in: &tags) }
        return .compound(tags)
    }

    private func replaceItemTag(named name: String, with value: NBTValue, in tags: inout [NBTNamedTag]) {
        if let index = tags.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            tags[index] = NBTNamedTag(name: tags[index].name, value: value)
        } else {
            tags.append(NBTNamedTag(name: name, value: value))
        }
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
        count: Int64,
        itemTags: [NBTNamedTag]
    ) -> (value: NBTValue, changed: Bool) {
        guard case .compound(var tags) = value else { return (value, false) }
        let inventoryNames: Set<String> = ["inventory", "playerinventory"]
        for index in tags.indices where inventoryNames.contains(normalized(tags[index].name)) {
            if case .list(let type, var values) = tags[index].value, type == .compound || values.isEmpty {
                // Bedrock player inventories commonly retain one Compound for every
                // slot. A slot is empty only when that Compound's Name tag is an
                // empty string; a missing Slot number alone is not considered empty.
                let emptyCandidates = values.indices.compactMap { valueIndex -> (Int, Int64)? in
                    guard isEmptyInventorySlot(values[valueIndex]),
                          let slot = itemSlot(values[valueIndex]),
                          (0...35).contains(slot) else { return nil }
                    return (valueIndex, slot)
                }.sorted { $0.1 < $1.1 }
                if let firstEmpty = emptyCandidates.first {
                    values[firstEmpty.0] = itemStack(
                        identifier: identifier,
                        count: count,
                        slot: Int8(firstEmpty.1),
                        itemTags: itemTags
                    )
                } else if let slot35 = values.firstIndex(where: { itemSlot($0) == 35 }) {
                    values[slot35] = itemStack(identifier: identifier, count: count, slot: 35, itemTags: itemTags)
                } else if !values.isEmpty {
                    // Malformed/non-slot-indexed inventory: replace the physical last
                    // entry rather than inventing an additional slot.
                    values[values.count - 1] = itemStack(identifier: identifier, count: count, slot: 35, itemTags: itemTags)
                } else {
                    values.append(itemStack(identifier: identifier, count: count, slot: 0, itemTags: itemTags))
                }
                tags[index].value = .list(.compound, values)
                return (.compound(tags), true)
            }
        }
        for index in tags.indices {
            if tradeContainerNames.contains(normalized(tags[index].name)) { continue }
            let nested = placingPlayerItem(in: tags[index].value, identifier: identifier, count: count, itemTags: itemTags)
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

    private func isEmptyInventorySlot(_ value: NBTValue) -> Bool {
        guard case .compound(let tags) = value else { return false }
        return tags.contains { tag in
            guard normalized(tag.name) == "name", case .string(let name) = tag.value else { return false }
            return name.isEmpty
        }
    }

    private func replacingMainhandItem(
        in value: NBTValue,
        identifier: String,
        count: Int64,
        itemTags: [NBTNamedTag]
    ) -> (value: NBTValue, changed: Bool) {
        guard case .compound(var tags) = value else { return (value, false) }
        let names: Set<String> = ["mainhand", "mainhanditem", "mainhandinventory"]
        for index in tags.indices where names.contains(normalized(tags[index].name)) {
            let stack = itemStack(identifier: identifier, count: count, wasPickedUp: 1, itemTags: itemTags)
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
            let nested = replacingMainhandItem(in: tags[index].value, identifier: identifier, count: count, itemTags: itemTags)
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
        if !targets.entities.isEmpty {
            deletedEntities = try entityStore.delete(objects: targets.entities)
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
    private var chunkSubChunkVersion = [ChunkPosition: UInt8]()
    private var emptyChunkProfiles = [Bool: BedrockEmptyChunkProfile]()
    private var pendingMetadataPuts = [Data: Data]()
    private var pendingMetadataDeletes = Set<Data>()
    private var modernizedChunks = Set<ChunkPosition>()

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
            let profile = try emptyChunkProfile(preferLegacy: false)
            let version = profile.subChunkVersion
            let legacy = [UInt8(0), 2, 3, 4, 5, 6, 7].contains(version)
            puts.append(contentsOf: BedrockEmptyChunk.metadataRecords(at: chunk, profile: profile).map { ($0.key, $0.value) })
            chunkLegacyFormat[chunk] = legacy
            chunkSubChunkVersion[chunk] = version
        }
        try database.applyBatch(puts: puts, deletes: [], sync: true)
        for put in puts {
            guard try database.get(put.key) == put.value else {
                throw BlocktopographError.malformedData("空气区块元数据写入后未能从 LevelDB 读回")
            }
        }
        availableChunks.formUnion(missing)
        return missing.count
    }

    private func emptyChunkProfile(preferLegacy: Bool) throws -> BedrockEmptyChunkProfile {
        if let cached = emptyChunkProfiles[preferLegacy] { return cached }
        let profile = try BedrockEmptyChunk.profile(
            database: database,
            dimension: dimension,
            preferLegacy: preferLegacy
        )
        emptyChunkProfiles[preferLegacy] = profile
        if globalPaletteVersion == nil { globalPaletteVersion = profile.blockPaletteVersion }
        return profile
    }

    // MARK: structure save / load

    static func makeStructureDocument(
        session: WorldSession,
        dimension: Int32,
        region: CommandBlockBox
    ) throws -> NBTDocument {
        let store = try CommandBlockStore(session: session, dimension: dimension)
        try store.validateVolume(region)
        guard let volumeValue = region.volume, volumeValue <= 16_777_216 else {
            throw BlocktopographError.unsupported("structure save 一次最多保存 16,777,216 个方块")
        }
        let sizeX = try structureSpan(region.minimum.x, region.maximum.x, name: "X")
        let sizeY = try structureSpan(Int64(region.minimum.y), Int64(region.maximum.y), name: "Y")
        let sizeZ = try structureSpan(region.minimum.z, region.maximum.z, name: "Z")
        let volume = Int(volumeValue)
        var primary = [Int32](repeating: -1, count: volume)
        var secondary = [Int32](repeating: -1, count: volume)
        var palette = [NBTValue]()
        var paletteLookup = [Data: Int32]()

        func paletteIndex(for state: BedrockBlockState, coordinate: CommandBlockCoordinate) throws -> Int32 {
            let key = try store.subKey(for: coordinate)
            let modern = state.nbt != nil
                ? store.normalizedModernState(state, version: try store.paletteVersion(for: key))
                : store.modernState(from: state, version: try store.paletteVersion(for: key))
            guard let nbt = modern.nbt else {
                throw BlocktopographError.malformedData("结构调色板方块缺少现代 NBT 状态")
            }
            let encoded = try BedrockNBTCodec.encode(
                NBTDocument(rootName: "", root: nbt),
                encoding: .littleEndian
            )
            if let existing = paletteLookup[encoded] { return existing }
            guard palette.count < Int(Int32.max) else {
                throw BlocktopographError.unsupported("结构调色板条目过多")
            }
            let index = Int32(palette.count)
            palette.append(nbt)
            paletteLookup[encoded] = index
            return index
        }

        var x = region.minimum.x
        while x <= region.maximum.x {
            var y = region.minimum.y
            while y <= region.maximum.y {
                var z = region.minimum.z
                while z <= region.maximum.z {
                    let coordinate = CommandBlockCoordinate(x: x, y: y, z: z)
                    let dx = Int(x - region.minimum.x)
                    let dy = Int(Int64(y) - Int64(region.minimum.y))
                    let dz = Int(z - region.minimum.z)
                    let flat = dx * sizeY * sizeZ + dy * sizeZ + dz
                    primary[flat] = try paletteIndex(for: store.state(layer: 0, at: coordinate), coordinate: coordinate)
                    secondary[flat] = try paletteIndex(for: store.state(layer: 1, at: coordinate), coordinate: coordinate)
                    if z == Int64.max { break }
                    z += 1
                }
                if y == Int32.max { break }
                y += 1
            }
            if x == Int64.max { break }
            x += 1
        }

        let blockEntityState = try store.loadBlockEntities(for: store.chunks(in: region))
        var positionData = [NBTNamedTag]()
        for (coordinate, document) in blockEntityState.documents {
            let commandCoordinate = CommandBlockCoordinate(x: coordinate.x, y: coordinate.y, z: coordinate.z)
            guard region.contains(commandCoordinate) else { continue }
            let dx = Int(coordinate.x - region.minimum.x)
            let dy = Int(Int64(coordinate.y) - Int64(region.minimum.y))
            let dz = Int(coordinate.z - region.minimum.z)
            let flat = dx * sizeY * sizeZ + dy * sizeZ + dz
            positionData.append(NBTNamedTag(
                name: String(flat),
                value: .compound([
                    NBTNamedTag(name: "block_entity_data", value: document.root)
                ])
            ))
        }
        positionData.sort { (Int($0.name) ?? 0) < (Int($1.name) ?? 0) }
        guard let originX = Int32(exactly: region.minimum.x),
              let originZ = Int32(exactly: region.minimum.z) else {
            throw BlocktopographError.malformedData("structure save 的世界原点 X/Z 必须在 Int32 范围内")
        }

        return NBTDocument(rootName: "", root: .compound([
            NBTNamedTag(name: "format_version", value: .int(1)),
            NBTNamedTag(name: "size", value: .list(.int, [
                .int(Int32(sizeX)), .int(Int32(sizeY)), .int(Int32(sizeZ))
            ])),
            NBTNamedTag(name: "structure_world_origin", value: .list(.int, [
                .int(originX),
                .int(region.minimum.y),
                .int(originZ)
            ])),
            NBTNamedTag(name: "structure", value: .compound([
                NBTNamedTag(name: "block_indices", value: .list(.list, [
                    .list(.int, primary.map(NBTValue.int)),
                    .list(.int, secondary.map(NBTValue.int))
                ])),
                NBTNamedTag(name: "entities", value: .list(.end, [])),
                NBTNamedTag(name: "palette", value: .compound([
                    NBTNamedTag(name: "default", value: .compound([
                        NBTNamedTag(name: "block_palette", value: .list(.compound, palette)),
                        NBTNamedTag(name: "block_position_data", value: .compound(positionData))
                    ]))
                ]))
            ]))
        ]))
    }

    static func loadStructure(
        session: WorldSession,
        document: NBTDocument,
        targetDimension: Int32,
        destination: CommandBlockCoordinate
    ) throws -> String {
        let normalized = try JavaStructureConverter.convertIfNeeded(document).document
        let parsed = try parseStructure(normalized)
        let maxX = destination.x.addingReportingOverflow(Int64(parsed.sizeX - 1))
        let maxY = destination.y.addingReportingOverflow(Int32(parsed.sizeY - 1))
        let maxZ = destination.z.addingReportingOverflow(Int64(parsed.sizeZ - 1))
        guard !maxX.overflow, !maxY.overflow, !maxZ.overflow else {
            throw BlocktopographError.malformedData("structure load 目标坐标溢出")
        }
        let targetRegion = CommandBlockBox(
            destination,
            CommandBlockCoordinate(x: maxX.partialValue, y: maxY.partialValue, z: maxZ.partialValue)
        )
        let store = try CommandBlockStore(session: session, dimension: targetDimension)
        try store.validateVolume(targetRegion)
        let generatedCount = try store.ensureGenerated(store.chunks(in: targetRegion))
        let targetEntityState = try store.loadBlockEntities(for: store.chunks(in: targetRegion))
        var targetBlockEntities = targetEntityState.documents
        var changedEntityChunks = Set<ChunkPosition>()
        var changedBlocks: UInt64 = 0

        for dx in 0..<parsed.sizeX {
            for dy in 0..<parsed.sizeY {
                for dz in 0..<parsed.sizeZ {
                    let flat = dx * parsed.sizeY * parsed.sizeZ + dy * parsed.sizeZ + dz
                    let coordinate = CommandBlockCoordinate(
                        x: destination.x + Int64(dx),
                        y: destination.y + Int32(dy),
                        z: destination.z + Int64(dz)
                    )
                    let targetKey = try store.subKey(for: coordinate)
                    var wroteAnyLayer = false
                    if let state = try parsed.state(layer: 0, flatIndex: flat) {
                        let adapted = try store.adaptedState(state, layer: 0, for: targetKey)
                        if try store.setState(adapted, layer: 0, at: coordinate, createWhenAir: false) {
                            changedBlocks += 1
                        }
                        wroteAnyLayer = true
                    }
                    if let state = try parsed.state(layer: 1, flatIndex: flat) {
                        let adapted = try store.adaptedState(state, layer: 1, for: targetKey)
                        if try store.setState(adapted, layer: 1, at: coordinate, createWhenAir: false) {
                            changedBlocks += 1
                        }
                        wroteAnyLayer = true
                    }
                    guard wroteAnyLayer else { continue }
                    let entityCoordinate = BlockEntityCoordinate(x: coordinate.x, y: coordinate.y, z: coordinate.z)
                    targetBlockEntities.removeValue(forKey: entityCoordinate)
                    if let sourceEntity = parsed.blockEntities[flat] {
                        targetBlockEntities[entityCoordinate] = store.offsetBlockEntity(sourceEntity, to: coordinate)
                    }
                    changedEntityChunks.insert(store.chunkPosition(x: coordinate.x, z: coordinate.z))
                }
            }
        }

        let entityWrites = try store.encodeBlockEntities(
            documents: targetBlockEntities,
            changedChunks: changedEntityChunks,
            originalKeys: targetEntityState.keysByChunk
        )
        let written = try store.commit(extraPuts: entityWrites.puts, extraDeletes: entityWrites.deletes)
        guard written > 0 || !entityWrites.puts.isEmpty || !entityWrites.deletes.isEmpty || generatedCount > 0 else {
            throw BlocktopographError.unsupported("结构没有产生任何方块变化")
        }
        return "写入 \(written) 个 SubChunk，修改 \(changedBlocks) 个图层方块，处理 \(changedEntityChunks.count) 个方块实体区块，先生成 \(generatedCount) 个空气区块。"
    }

    private struct ParsedStructure {
        let sizeX: Int
        let sizeY: Int
        let sizeZ: Int
        let layers: [[Int32]]
        let palette: [BedrockBlockState]
        let blockEntities: [Int: NBTDocument]

        func state(layer: Int, flatIndex: Int) throws -> BedrockBlockState? {
            guard layers.indices.contains(layer), layers[layer].indices.contains(flatIndex) else { return nil }
            let raw = layers[layer][flatIndex]
            if raw == -1 { return nil }
            guard raw >= 0, palette.indices.contains(Int(raw)) else {
                throw BlocktopographError.malformedData("结构方块索引超出调色板范围：\(raw)")
            }
            return palette[Int(raw)]
        }
    }

    private static func parseStructure(_ document: NBTDocument) throws -> ParsedStructure {
        guard case .compound = document.root,
              let sizeValue = document.root.compoundValue(named: "size"),
              let size = integerVector(sizeValue), size.count >= 3,
              size[0] > 0, size[1] > 0, size[2] > 0,
              size[0] <= Int64(Int32.max), size[1] <= Int64(Int32.max), size[2] <= Int64(Int32.max),
              let structure = document.root.compoundValue(named: "structure"),
              let indicesValue = structure.compoundValue(named: "block_indices"),
              case .list(.list, let layerValues) = indicesValue,
              let paletteContainer = structure.compoundValue(named: "palette")?.compoundValue(named: "default"),
              case .list(.compound, let paletteValues)? = paletteContainer.compoundValue(named: "block_palette") else {
            throw BlocktopographError.malformedData("结构缺少 size、structure.block_indices 或 default.block_palette")
        }
        let sizeX = Int(size[0]), sizeY = Int(size[1]), sizeZ = Int(size[2])
        let volumeResult = sizeX.multipliedReportingOverflow(by: sizeY)
        let volumeFinal = volumeResult.partialValue.multipliedReportingOverflow(by: sizeZ)
        guard !volumeResult.overflow, !volumeFinal.overflow, volumeFinal.partialValue <= 16_777_216 else {
            throw BlocktopographError.unsupported("结构体积过大")
        }
        let volume = volumeFinal.partialValue
        var layers = [[Int32]]()
        for value in layerValues.prefix(2) {
            guard case .list(.int, let values) = value else {
                throw BlocktopographError.malformedData("structure.block_indices 图层必须是 Int List")
            }
            let numbers = values.compactMap { item -> Int32? in
                if case .int(let number) = item { return number }
                return nil
            }
            guard numbers.count == values.count else {
                throw BlocktopographError.malformedData("structure.block_indices 包含非 Int 值")
            }
            var normalized = numbers
            if normalized.count < volume { normalized.append(contentsOf: repeatElement(-1, count: volume - normalized.count)) }
            if normalized.count > volume { normalized = Array(normalized.prefix(volume)) }
            layers.append(normalized)
        }
        while layers.count < 2 { layers.append([Int32](repeating: -1, count: volume)) }
        let palette = try paletteValues.map { value -> BedrockBlockState in
            guard case .compound = value else {
                throw BlocktopographError.malformedData("结构 block_palette 条目不是 Compound")
            }
            return BedrockBlockState(nbt: value, legacyID: nil, legacyData: nil)
        }
        guard !palette.isEmpty else { throw BlocktopographError.malformedData("结构调色板为空") }

        var blockEntities = [Int: NBTDocument]()
        if case .compound(let positions)? = paletteContainer.compoundValue(named: "block_position_data") {
            for position in positions {
                guard let flat = Int(position.name), (0..<volume).contains(flat),
                      let entityRoot = position.value.compoundValue(named: "block_entity_data"),
                      case .compound = entityRoot else { continue }
                blockEntities[flat] = NBTDocument(rootName: "", root: entityRoot)
            }
        }
        return ParsedStructure(
            sizeX: sizeX,
            sizeY: sizeY,
            sizeZ: sizeZ,
            layers: layers,
            palette: palette,
            blockEntities: blockEntities
        )
    }

    private static func integerVector(_ value: NBTValue) -> [Int64]? {
        switch value {
        case .intArray(let values): return values.map(Int64.init)
        case .longArray(let values): return values
        case .list(_, let values):
            let result = values.compactMap { item -> Int64? in
                switch item {
                case .byte(let value): return Int64(value)
                case .short(let value): return Int64(value)
                case .int(let value): return Int64(value)
                case .long(let value): return value
                default: return nil
                }
            }
            return result.count == values.count ? result : nil
        default: return nil
        }
    }

    private static func structureSpan(_ minimum: Int64, _ maximum: Int64, name: String) throws -> Int {
        let difference = maximum.subtractingReportingOverflow(minimum)
        guard !difference.overflow, difference.partialValue >= 0 else {
            throw BlocktopographError.malformedData("structure \(name) 轴尺寸溢出")
        }
        let inclusive = difference.partialValue.addingReportingOverflow(1)
        guard !inclusive.overflow, let value = Int(exactly: inclusive.partialValue), value > 0 else {
            throw BlocktopographError.malformedData("structure \(name) 轴尺寸无效")
        }
        return value
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
                    let keepLegacy = formatLegacy
                        && layer0.canRemainLegacy(layer: 0)
                        && layer1.canRemainLegacy(layer: 1)
                    let state0 = try keepLegacy ? layer0.legacyState() : layer0.modernState(version: version)
                    let state1 = try keepLegacy ? layer1.legacyState() : layer1.modernState(version: version)
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
                    let target0 = try adaptedState(source0, layer: 0, for: targetKey)
                    let target1 = try adaptedState(source1, layer: 1, for: targetKey)
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
            chunkSubChunkVersion[key.chunk] = mutable.version
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
        let existing = try load(key)
        let legacyTarget: Bool
        switch existing {
        case .value(let value): legacyTarget = value.isLegacy
        case .missing: legacyTarget = try isLegacyTarget(key)
        }
        let requiresUpgrade = legacyTarget && (state.nbt != nil || (layer == 1 && !state.isAir))
        if requiresUpgrade { try upgradeChunkToModern(key.chunk) }

        var mutable: MutableCommandSubChunk
        switch try load(key) {
        case .value(let value):
            mutable = value
        case .missing:
            if state.isAir && !createWhenAir { return false }
            let persistentVersion = try preferredSubChunkVersion(for: key)
            if try isLegacyTarget(key) {
                mutable = try MutableCommandSubChunk.emptyLegacy(y: key.y, subChunkVersion: persistentVersion)
            } else {
                mutable = try MutableCommandSubChunk.emptyModern(
                    y: key.y,
                    version: state.paletteVersion ?? paletteVersion(for: key),
                    subChunkVersion: persistentVersion
                )
            }
        }

        var writable = state
        if mutable.isLegacy, writable.nbt != nil {
            try upgradeChunkToModern(key.chunk)
            guard case .value(let upgraded) = try load(key) else {
                throw BlocktopographError.malformedData("旧版 SubChunk 升级后未能重新载入")
            }
            mutable = upgraded
        }
        if !mutable.isLegacy, writable.nbt == nil {
            writable = modernState(from: writable, version: try paletteVersion(for: key))
        }
        let changed = try mutable.setState(writable, layer: layer, linearIndex: index)
        if changed {
            cache[key] = .value(mutable)
            changedKeys.insert(key)
        }
        return changed
    }

    private func upgradeChunkToModern(_ chunk: ChunkPosition) throws {
        guard modernizedChunks.insert(chunk).inserted else { return }
        let plan = try BedrockLegacyChunkUpgrade.plan(database: database, position: chunk)
        for put in plan.metadataPuts { pendingMetadataPuts[put.key] = put.value }
        pendingMetadataDeletes.formUnion(plan.metadataDeletes)
        for put in plan.subChunkPuts {
            guard let parsed = BedrockDBKey.parse(put.key), let y = parsed.subChunkIndex else { continue }
            let key = SubKey(chunk: chunk, y: y)
            if case .value(let cached)? = cache[key], cached.isLegacy {
                cache[key] = .value(try cached.upgradedToModern(version: plan.paletteVersion))
            } else {
                switch cache[key] {
                case .value:
                    break
                case .missing, .none:
                    let decoded = try BedrockSubChunk.decode(put.value, keyYIndex: y)
                    cache[key] = .value(try MutableCommandSubChunk(decoded))
                }
            }
            changedKeys.insert(key)
        }
        // Include legacy SubChunks created only in the command cache and not yet
        // present in LevelDB when the format upgrade is triggered.
        let cachedKeys = cache.keys.filter { $0.chunk == chunk }
        for key in cachedKeys {
            guard case .value(let value)? = cache[key], value.isLegacy else { continue }
            cache[key] = .value(try value.upgradedToModern(version: plan.paletteVersion))
            changedKeys.insert(key)
        }
        chunkLegacyFormat[chunk] = false
        chunkSubChunkVersion[chunk] = 9
        globalPaletteVersion = plan.paletteVersion
    }

    private func modernState(from state: BedrockBlockState, version: Int32?) -> BedrockBlockState {
        if state.nbt != nil { return state }
        let identifier = BedrockLegacyBlockCatalog.identifier(forNumericID: state.legacyID ?? 0) ?? state.name
        return CommandBlockStateSpec(name: identifier, states: []).modernState(version: version)
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
                let legacy = decoded.isLegacyNumeric
                chunkLegacyFormat[key.chunk] = legacy
                if globalPaletteVersion == nil {
                    globalPaletteVersion = decoded.storages.flatMap(\.palette).compactMap(\.paletteVersion).first
                }
                return legacy
            }
            let version = try emptyChunkProfile(preferLegacy: false).subChunkVersion
            let legacy = [UInt8(0), 2, 3, 4, 5, 6, 7].contains(version)
            chunkLegacyFormat[key.chunk] = legacy
            chunkSubChunkVersion[key.chunk] = version
            return legacy
        }
    }

    private func preferredSubChunkVersion(for key: SubKey) throws -> UInt8 {
        if let cached = chunkSubChunkVersion[key.chunk] { return cached }
        let profile = try emptyChunkProfile(preferLegacy: false)
        let version = try BedrockEmptyChunk.preferredSubChunkVersion(
            database: database,
            at: key.chunk,
            fallback: profile.subChunkVersion
        )
        chunkSubChunkVersion[key.chunk] = version
        chunkLegacyFormat[key.chunk] = [UInt8(0), 2, 3, 4, 5, 6, 7].contains(version)
        return version
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
        return BedrockEmptyChunk.currentBlockPaletteVersion
    }


    private func adaptedState(
        _ state: BedrockBlockState,
        layer: Int,
        for targetKey: SubKey
    ) throws -> BedrockBlockState {
        let targetLegacy = try isLegacyTarget(targetKey)
        if targetLegacy {
            if state.nbt == nil { return state }
            if layer == 1, state.isAir {
                return BedrockBlockState(nbt: nil, legacyID: 0, legacyData: 0)
            }
            if layer == 0,
               state.stateProperties.isEmpty,
               let block = BedrockLegacyBlockCatalog.block(forIdentifier: state.name) {
                return BedrockBlockState(nbt: nil, legacyID: UInt16(block.id), legacyData: 0)
            }
            // A block without a legacy numeric ID, any non-empty states, or a
            // non-air layer 1 forces the destination chunk to modern storage.
            return normalizedModernState(state, version: try paletteVersion(for: targetKey))
        }
        return state.nbt != nil
            ? normalizedModernState(state, version: try paletteVersion(for: targetKey))
            : modernState(from: state, version: try paletteVersion(for: targetKey))
    }

    private func normalizedModernState(_ state: BedrockBlockState, version: Int32?) -> BedrockBlockState {
        guard case .compound(var tags)? = state.nbt else { return state }
        let resolved = state.paletteVersion ?? version ?? BedrockBlockState.defaultPaletteVersion
        if let index = tags.firstIndex(where: { $0.name.caseInsensitiveCompare("version") == .orderedSame }) {
            tags[index] = NBTNamedTag(name: tags[index].name, value: .int(resolved))
        } else {
            tags.append(NBTNamedTag(name: "version", value: .int(resolved)))
        }
        return BedrockBlockState(nbt: .compound(tags), legacyID: nil, legacyData: nil)
    }

    private func commit(
        extraPuts: [(key: Data, value: Data)] = [],
        extraDeletes: [Data] = []
    ) throws -> Int {
        var puts = pendingMetadataPuts.map { (key: $0.key, value: $0.value) }
        puts.append(contentsOf: extraPuts)
        for key in changedKeys.sorted(by: commandSubKeyOrder) {
            guard case .value(let mutable)? = cache[key] else { continue }
            let data = try mutable.persistentSubChunk().encodePersistent()
            puts.append((BedrockDBKey.subChunk(x: key.chunk.x, z: key.chunk.z, dimension: key.chunk.dimension, index: key.y), data))
        }
        let deletes = Array(pendingMetadataDeletes) + extraDeletes
        try database.applyBatch(puts: puts, deletes: deletes, sync: true)
        for (key, value) in pendingMetadataPuts {
            guard try database.get(key) == value else {
                throw BlocktopographError.malformedData("升级后的区块元数据写入后未能从 LevelDB 读回")
            }
        }
        for key in pendingMetadataDeletes where pendingMetadataPuts[key] == nil {
            guard try database.get(key) == nil else {
                throw BlocktopographError.malformedData("升级前的旧版区块元数据仍然存在")
            }
        }
        // Verify every changed SubChunk through the same LevelDB handle before a
        // success result is returned. This catches rejected/corrupt new records
        // instead of leaving the UI to report a successful but missing change.
        for key in changedKeys {
            let dbKey = BedrockDBKey.subChunk(
                x: key.chunk.x,
                z: key.chunk.z,
                dimension: key.chunk.dimension,
                index: key.y
            )
            guard let stored = try database.get(dbKey) else {
                throw BlocktopographError.malformedData("SubChunk 写入后未能从 LevelDB 读回")
            }
            _ = try BedrockSubChunk.decode(stored, keyYIndex: key.y)
        }
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

    static func emptyModern(y: Int8, version: Int32?, subChunkVersion: UInt8) throws -> MutableCommandSubChunk {
        let air = BedrockBlockState.editableAir(version: version)
        let storage = SubChunkStorage(bitsPerBlock: 0, palette: [air], indices: Array(repeating: 0, count: 4096))
        let persistentVersion: UInt8 = [UInt8(1), 8, 9].contains(subChunkVersion) ? subChunkVersion : 9
        return try MutableCommandSubChunk(BedrockSubChunk(version: persistentVersion, yIndex: y, storages: [storage], trailingData: Data()))
    }

    static func emptyLegacy(y: Int8, subChunkVersion: UInt8) throws -> MutableCommandSubChunk {
        let air = BedrockBlockState(nbt: nil, legacyID: 0, legacyData: 0)
        let storage = SubChunkStorage(bitsPerBlock: 8, palette: [air], indices: Array(repeating: 0, count: 4096))
        let persistentVersion: UInt8 = [UInt8(2), 3, 4, 5, 6, 7].contains(subChunkVersion) ? subChunkVersion : 7
        return try MutableCommandSubChunk(BedrockSubChunk(version: persistentVersion, yIndex: y, storages: [storage], trailingData: Data()))
    }

    var isLegacy: Bool { [UInt8(0), 2, 3, 4, 5, 6, 7].contains(version) }
    var paletteVersion: Int32? { storages.flatMap(\.palette).compactMap(\.paletteVersion).first }

    func upgradedToModern(version: Int32?) throws -> MutableCommandSubChunk {
        let upgraded = try persistentSubChunk().upgradedToModern(paletteVersion: version)
        return try MutableCommandSubChunk(upgraded)
    }

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
