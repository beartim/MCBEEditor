import Foundation

struct BedrockEmptyChunkRecord: Equatable {
    let key: Data
    let value: Data
    let recordType: ChunkRecordType
}

/// Metadata used by Android Blocktopograph's `Chunk.createEmpty` path.
/// A coordinate with these two records and no SubChunk records is considered
/// generated, while every block resolves to air.
enum BedrockEmptyChunk {
    static func metadataRecords(at position: ChunkPosition) -> [BedrockEmptyChunkRecord] {
        let versionType = ChunkRecordType.legacyVersion
        let version = BedrockEmptyChunkRecord(
            key: BedrockDBKey(
                position: position,
                recordType: versionType,
                subChunkIndex: nil
            ).encoded(),
            value: Data([0x0f]),
            recordType: versionType
        )

        var finalizedValue = Data()
        finalizedValue.appendLE(Int32(2))
        let finalizedType = ChunkRecordType.finalizedState
        let finalized = BedrockEmptyChunkRecord(
            key: BedrockDBKey(
                position: position,
                recordType: finalizedType,
                subChunkIndex: nil
            ).encoded(),
            value: finalizedValue,
            recordType: finalizedType
        )
        return [version, finalized]
    }
}
