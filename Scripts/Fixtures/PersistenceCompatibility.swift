import Foundation

enum PersistenceCompatibilityChecks {
    static func run() throws {
        var vectors = [[String: Any]]()
        for (version, usesVal) in [(UInt8(0), false), (7, false), (1, true), (8, true), (8, false), (9, false)] {
            let session = WorldSession()
            let db = try session.database()
            let numeric = version == 0 || version == 7
            let format = BedrockPaletteFormat(usesLegacyVal: usesVal, version: usesVal ? nil : 17_825_808)
            let seed = try numeric ? BedrockSubChunk.emptyLegacy(version: version, yIndex: 0)
                : BedrockSubChunk(version: version, yIndex: 0, storages: [.airFilled(with: format.air)], trailingData: Data())
            let seedKey = BedrockDBKey.subChunk(x: 0, z: 0, dimension: 2, index: 0)
            let seedRaw = try seed.encodePersistent()
            db.values[seedKey] = seedRaw
            let versionType: ChunkRecordType = version == 9 ? .version : .legacyVersion
            let versionRaw = Data([version == 9 ? 40 : 19])
            let seedPosition = ChunkPosition(x: 0, z: 0, dimension: 2)
            db.values[BedrockDBKey(position: seedPosition, recordType: versionType, subChunkIndex: nil).encoded()] = versionRaw
            db.values[BedrockDBKey(position: seedPosition, recordType: .finalizedState, subChunkIndex: nil).encoded()] = Data([2, 0, 0, 0])
            db.values[BedrockDBKey(position: seedPosition, recordType: .data2D, subChunkIndex: nil).encoded()] = Data(repeating: 0, count: 768)
            let renderer = ChunkSurfaceRenderer(database: db)
            let store = BedrockBlockNBTStore(session: session)
            for x in [Int64(3), 35] {
                let block = try renderer.block(blockX: x, y: 200, blockZ: 5, dimension: 2)
                precondition(!block.isGenerated)
                var tags: [NBTNamedTag]
                if numeric {
                    tags = [NBTNamedTag(name: "name", value: .string("minecraft:diamond_block")),
                            NBTNamedTag(name: "legacy_id", value: .int(57)),
                            NBTNamedTag(name: "legacy_data", value: .int(0))]
                } else {
                    guard case .compound(let template)? = block.stateForEditing(layer: 0).nbt else { preconditionFailure("palette template missing") }
                    tags = template.map { $0.name == "name" ? NBTNamedTag(name: "name", value: .string("minecraft:diamond_block")) : $0 }
                }
                _ = try store.save(block: block, storageIndex: 0, document: NBTDocument(rootName: "", root: .compound(tags)))
                let key = BedrockDBKey.subChunk(x: Int32(x / 16), z: 0, dimension: 2, index: 12)
                let raw = db.values[key]!
                let saved = try BedrockSubChunk.decode(raw, keyYIndex: 12)
                precondition(saved.version == version)
                let state = saved.storages[0].blockState(x: 3, y: 8, z: 5)!
                precondition(state.name == "minecraft:diamond_block")
                if usesVal {
                    precondition(state.paletteVersion == nil && state.nbt?.compoundValue(named: "val") != nil
                                 && state.nbt?.compoundValue(named: "states") == nil)
                }
                let position = ChunkPosition(x: Int32(x / 16), z: 0, dimension: 2)
                precondition(db.values[BedrockDBKey(position: position, recordType: versionType, subChunkIndex: nil).encoded()] == versionRaw)
                precondition(db.values[BedrockDBKey(position: position, recordType: .finalizedState, subChunkIndex: nil).encoded()] == Data([2, 0, 0, 0]))
                vectors.append(["name": "v\(version)-\(usesVal)-\(x)", "raw": raw.base64EncodedString(),
                    "version": Int(version), "val": usesVal, "x": 3, "y": 8, "z": 5, "block": "minecraft:diamond_block"])
            }
            precondition(db.values[seedKey] == seedRaw)
            let emptyDimension = try BedrockEmptyChunk.profile(database: db, dimension: 1)
            precondition(emptyDimension.subChunkVersion == version)
            if version == 8 || version == 9 {
                let missing = try renderer.block(blockX: 3, y: 220, blockZ: 5, dimension: 2)
                let state = missing.stateForEditing(layer: 1)
                guard case .compound(let template)? = state.nbt else { preconditionFailure("new layer template missing") }
                let tags = template.map { $0.name == "name" ? NBTNamedTag(name: "name", value: .string("minecraft:diamond_block")) : $0 }
                _ = try store.save(block: missing, storageIndex: 1, document: NBTDocument(rootName: "", root: .compound(tags)))
                let raw = db.values[BedrockDBKey.subChunk(x: 0, z: 0, dimension: 2, index: 13)]!
                let saved = try BedrockSubChunk.decode(raw, keyYIndex: 13)
                precondition(saved.storages.count == 2 && saved.storages[0].palette.allSatisfy(\.isAir))
                if version == 8 { precondition(saved.storages.allSatisfy { $0.bitsPerBlock >= 1 }) }
                vectors.append(["name": "v\(version)-\(usesVal)-layer1", "raw": raw.base64EncodedString(),
                    "version": Int(version), "val": usesVal, "x": 3, "y": 12, "z": 5, "block": "minecraft:diamond_block", "layer": 1])
            }
        }
        if let path = ProcessInfo.processInfo.environment["MCBE_AUDIT_VECTORS"] {
            try JSONSerialization.data(withJSONObject: vectors, options: [.sortedKeys]).write(to: URL(fileURLWithPath: path))
        }
        print("Persistence compatibility matrix passed: numeric/v1/v8/v9, val/states, missing chunks/slices and empty layers")
    }
}
