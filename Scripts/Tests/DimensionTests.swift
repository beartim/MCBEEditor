import Foundation

@main
enum DimensionTests {
    static func main() throws {
        let db = MojangLevelDB()
        let table = NBTDocument(rootName: "", root: .compound([
            NBTNamedTag(name: "entries", value: .compound([
                NBTNamedTag(name: "bear:wzn", value: .int(1002)),
                NBTNamedTag(name: "wzn:bear", value: .int(1000)),
                NBTNamedTag(name: "wzn:cat", value: .int(1001))
            ]))
        ]))
        try db.put(BedrockNBTCodec.encode(table), for: Data("DimensionNameIdTable".utf8))
        try db.put(Data([10, 0, 0, 0]), for: Data("Overworld".utf8))
        try db.put(Data(), for: BedrockDBKey.subChunk(x: 2, z: -3, dimension: 1001, index: 0))
        let before = db.values
        let rows = try DimensionStore(database: db).snapshot()
        precondition(rows.map(\.id) == [0, 1000, 1001, 1002])
        precondition(rows.first { $0.id == 1000 }?.name == "wzn:bear")
        precondition(rows.first { $0.id == 1000 }?.chunkCount == 0)
        precondition(rows.first { $0.id == 1001 }?.chunkCount == 1)
        precondition(db.values == before)
        for id in [Int32(43), 44, 47, 118, -1, Int32.min, Int32.max] {
            let encoded = BedrockDBKey.subChunk(x: -2, z: 3, dimension: id, index: -5)
            let key = BedrockDBKey.parse(encoded)
            precondition(key?.position == ChunkPosition(x: -2, z: 3, dimension: id))
            precondition(key?.recordType == .subChunk && key?.subChunkIndex == -5)
        }
        precondition(BedrockDBKey.parse(Data(repeating: 0, count: 12)) == nil)
        try DimensionAddTests.run()
        try DimensionEmptyTests.run()
        try DimensionPurgeTests.run()
        print("Dimension query tests passed.")
    }
}
