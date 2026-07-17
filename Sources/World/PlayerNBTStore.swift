import Foundation


struct PlayerSpawnPointRecord: Hashable {
    let playerName: String
    let keyText: String
    let x: Int64
    let y: Int64?
    let z: Int64
    let dimension: Int32
    let forced: Bool?
}

struct PlayerNBTRecord: Hashable {
    let key: Data
    let keyText: String
    let displayName: String
    let document: NBTDocument
    let rawData: Data

    static func == (lhs: PlayerNBTRecord, rhs: PlayerNBTRecord) -> Bool { lhs.key == rhs.key }
    func hash(into hasher: inout Hasher) { hasher.combine(key) }
}

final class PlayerNBTStore {
    private let session: WorldSession

    init(session: WorldSession) {
        self.session = session
    }

    func records() throws -> [PlayerNBTRecord] {
        let database = try session.database()
        var values = [Data: Data]()

        let localPlayerKeys = [Data("~local_player".utf8), Data("LocalPlayer".utf8)]
        for key in localPlayerKeys {
            if let value = try database.get(key) { values[key] = value }
        }

        for entry in try database.entries(prefix: Data("player_".utf8), includeValues: true, limit: 0) {
            if let value = entry.value { values[entry.key] = value }
        }

        var decoded = [PlayerNBTRecord]()
        decoded.reserveCapacity(values.count)
        for (key, rawData) in values {
            do {
                let document = try BedrockNBTCodec.decode(rawData, encoding: .littleEndian)
                let keyText = String(data: key, encoding: .utf8) ?? "0x\(key.hexString)"
                decoded.append(PlayerNBTRecord(
                    key: key,
                    keyText: keyText,
                    displayName: playerDisplayName(document: document, keyText: keyText),
                    document: document,
                    rawData: rawData
                ))
            } catch {
                // Keep malformed/non-NBT values out of the editor rather than
                // risking a destructive rewrite.
                continue
            }
        }

        return decoded.sorted { lhs, rhs in
            let lhsLocal = isLocalKey(lhs.keyText)
            let rhsLocal = isLocalKey(rhs.keyText)
            if lhsLocal != rhsLocal { return lhsLocal }
            let order = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
            if order != .orderedSame { return order == .orderedAscending }
            return lhs.keyText < rhs.keyText
        }
    }

    func save(record: PlayerNBTRecord, document: NBTDocument) throws {
        let encoded = try BedrockNBTCodec.encode(document, encoding: .littleEndian)
        try session.database().put(encoded, for: record.key, sync: true)
    }

    func spawnPoints() throws -> [PlayerSpawnPointRecord] {
        try records().compactMap { record in
            guard let coordinate = spawnCoordinate(in: record.document.root) else { return nil }
            return PlayerSpawnPointRecord(
                playerName: record.displayName,
                keyText: record.keyText,
                x: coordinate.x,
                y: coordinate.y,
                z: coordinate.z,
                dimension: coordinate.dimension,
                forced: coordinate.forced
            )
        }
    }

    private func spawnCoordinate(in root: NBTValue) -> (x: Int64, y: Int64?, z: Int64, dimension: Int32, forced: Bool?)? {
        if let direct = directSpawnCoordinate(in: root, acceptsGenericXYZ: false) { return direct }

        guard case .compound(let tags) = root else { return nil }
        let nestedNames = Set([
            "respawn", "spawn", "spawnpoint", "playerspawn", "bedspawn", "respawnpoint"
        ])
        for tag in tags where nestedNames.contains(normalized(tag.name)) {
            if let nested = directSpawnCoordinate(in: tag.value, acceptsGenericXYZ: true) { return nested }
        }
        return nil
    }

    private func directSpawnCoordinate(
        in value: NBTValue,
        acceptsGenericXYZ: Bool
    ) -> (x: Int64, y: Int64?, z: Int64, dimension: Int32, forced: Bool?)? {
        guard case .compound = value else { return nil }
        let xNames = acceptsGenericXYZ ? ["SpawnX", "spawn_x", "X", "x"] : ["SpawnX", "spawn_x"]
        let yNames = acceptsGenericXYZ ? ["SpawnY", "spawn_y", "Y", "y"] : ["SpawnY", "spawn_y"]
        let zNames = acceptsGenericXYZ ? ["SpawnZ", "spawn_z", "Z", "z"] : ["SpawnZ", "spawn_z"]

        var x = int64Value(in: value, names: xNames)
        var y = int64Value(in: value, names: yNames)
        var z = int64Value(in: value, names: zNames)

        if (x == nil || z == nil),
           let position = compoundValue(in: value, names: ["Pos", "pos", "Position", "position"]),
           let tuple = coordinateTuple(position) {
            x = tuple.x
            y = tuple.y
            z = tuple.z
        }
        guard let spawnX = x, let spawnZ = z else { return nil }

        let dimensionValue = compoundValue(in: value, names: [
            "SpawnDimension", "spawn_dimension", "Dimension", "dimension",
            "DimensionId", "dimension_id", "DimensionID"
        ])
        let dimension = parseDimension(dimensionValue) ?? 0
        let forcedValue = compoundValue(in: value, names: ["SpawnForced", "spawn_forced", "Forced", "forced"])
        let forced = forcedValue.flatMap(numericInt64).map { $0 != 0 }
        return (spawnX, y, spawnZ, dimension, forced)
    }

    private func coordinateTuple(_ value: NBTValue) -> (x: Int64, y: Int64?, z: Int64)? {
        switch value {
        case .list(_, let values) where values.count >= 3:
            guard let x = numericInt64(values[0]), let z = numericInt64(values[2]) else { return nil }
            return (x, numericInt64(values[1]), z)
        case .intArray(let values) where values.count >= 3:
            return (Int64(values[0]), Int64(values[1]), Int64(values[2]))
        case .longArray(let values) where values.count >= 3:
            return (values[0], values[1], values[2])
        case .compound:
            guard let x = int64Value(in: value, names: ["X", "x"]),
                  let z = int64Value(in: value, names: ["Z", "z"]) else { return nil }
            return (x, int64Value(in: value, names: ["Y", "y"]), z)
        default:
            return nil
        }
    }

    private func compoundValue(in value: NBTValue, names: [String]) -> NBTValue? {
        guard case .compound(let tags) = value else { return nil }
        for name in names {
            if let exact = tags.first(where: { $0.name == name }) { return exact.value }
        }
        let lowered = Set(names.map { $0.lowercased() })
        return tags.first(where: { lowered.contains($0.name.lowercased()) })?.value
    }

    private func int64Value(in value: NBTValue, names: [String]) -> Int64? {
        compoundValue(in: value, names: names).flatMap(numericInt64)
    }

    private func numericInt64(_ value: NBTValue) -> Int64? {
        switch value {
        case .byte(let number): return Int64(number)
        case .short(let number): return Int64(number)
        case .int(let number): return Int64(number)
        case .long(let number): return number
        case .float(let number): return Int64(number.rounded())
        case .double(let number): return Int64(number.rounded())
        default: return nil
        }
    }

    private func parseDimension(_ value: NBTValue?) -> Int32? {
        guard let value = value else { return nil }
        if let number = numericInt64(value) { return Int32(clamping: number) }
        guard case .string(let raw) = value else { return nil }
        let text = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if text.contains("nether") { return 1 }
        if text.contains("end") { return 2 }
        if text.contains("overworld") { return 0 }
        return Int32(text)
    }

    private func normalized(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private func playerDisplayName(document: NBTDocument, keyText: String) -> String {
        let candidates = ["PlayerName", "NameTag", "CustomName", "name", "XUID"]
        for name in candidates {
            if let value = document.root.stringValue(named: name)?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return value
            }
        }
        if isLocalKey(keyText) { return "本机玩家" }
        if keyText.hasPrefix("player_server_") {
            return "服务器玩家 \(String(keyText.dropFirst("player_server_".count)))"
        }
        if keyText.hasPrefix("player_") {
            return "远程玩家 \(String(keyText.dropFirst("player_".count)))"
        }
        return keyText
    }

    private func isLocalKey(_ key: String) -> Bool {
        key == "~local_player" || key == "LocalPlayer"
    }

}
