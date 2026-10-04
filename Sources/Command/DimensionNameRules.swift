import Foundation

enum DimensionNameRules {
    static func validateAddition(name: String, id: Int32) throws -> String {
        guard !name.isEmpty, name.utf8.count <= 65535,
              !name.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) }),
              name.range(of: "^[+-]?[0-9]+$", options: .regularExpression) == nil else {
            throw MCBEEditorError.malformedData("维度名称必须非空，不含空白/控制字符，且不能为纯数字")
        }
        let builtin: (String, Int32)?
        switch name.lowercased() {
        case "overworld", "minecraft:overworld": builtin = ("overworld", 0)
        case "nether", "minecraft:nether": builtin = ("nether", 1)
        case "the_end", "minecraft:the_end": builtin = ("the_end", 2)
        default: builtin = nil
        }
        if let builtin = builtin {
            guard id == builtin.1 else { throw MCBEEditorError.malformedData("\(builtin.0) 的 ID 必须为 \(builtin.1)") }
            return builtin.0
        }
        guard id < 0 || id > 2 else { throw MCBEEditorError.malformedData("ID 0、1、2 保留给原版维度") }
        let reserved = DimensionDatabaseKeys.globalNames
        guard !reserved.contains(name), !["actorprefix", "digp", "tickingarea", "VILLAGE_", "structuretemplate", "player_", "legacy_console_player_", "map_", "PosTrackDB-", "RealmsStoriesData_", "chunk_loaded_request_", "portals"].contains(where: { name.hasPrefix($0) }) else {
            throw MCBEEditorError.malformedData("维度名称与保留数据库键冲突：\(name)")
        }
        return name
    }

}

enum DimensionDatabaseKeys {
    static let globalNames: Set<String> = ["DimensionNameIdTable", "AutonomousEntities", "BiomeData", "BiomeIdsTable", "WorldClocks", "scoreboard", "mobevents", "mVillages", "villages", "dimension0", "dimension1", "dimension2", "schedulerWT", "portals", "LevelChunkMetaDataDictionary", "DynamicProperties", "PositionTrackDB-LastId", "LevelSpawnWasFixed", "game_flatworldlayers", "SST_SALOG", "SST_WORD", "SST_WORD_", "DedicatedServerForcedCorruption", "~local_player", "LocalPlayer", "TheEnd"]
    static let preservedPrefixes = ["player_", "legacy_console_player_", "map_", "PosTrackDB-", "RealmsStoriesData_", "structuretemplate"]
}
