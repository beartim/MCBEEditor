using MCBEEditor.Core.Nbt;

namespace MCBEEditor.Core.Entity;

public enum BedrockWorldObjectKind
{
    Entity,
    BlockEntity
}

public enum BedrockWorldObjectSource
{
    ModernActor,
    LegacyChunkEntity,
    BlockEntity
}

public abstract record BedrockWorldObjectStorage(int RecordIndex, NbtEncoding Encoding)
{
    public abstract byte[] PrimaryKey { get; }
}

public sealed record ModernActorStorage(byte[] ActorKey, byte[] DigestKey, int Index, NbtEncoding SourceEncoding)
    : BedrockWorldObjectStorage(Index, SourceEncoding)
{
    public override byte[] PrimaryKey => ActorKey;
    public byte[]? ActorStorageReference => ActorKey.Length >= 8 ? ActorKey[^8..] : null;
}

public sealed record ChunkRecordStorage(byte[] Key, int Index, NbtEncoding SourceEncoding)
    : BedrockWorldObjectStorage(Index, SourceEncoding)
{
    public override byte[] PrimaryKey => Key;
}

public sealed record BedrockWorldObjectPosition(double X, double Y, double Z)
{
    public int BlockX => ClampFloorToInt(X);
    public int BlockY => ClampFloorToInt(Y);
    public int BlockZ => ClampFloorToInt(Z);

    private static int ClampFloorToInt(double value)
    {
        var floor = Math.Floor(value);
        if (floor <= int.MinValue) return int.MinValue;
        if (floor >= int.MaxValue) return int.MaxValue;
        return (int)floor;
    }
}

public sealed record BedrockWorldObject(
    string StableId,
    BedrockWorldObjectKind Kind,
    string Identifier,
    string? CustomName,
    BedrockWorldObjectPosition? Position,
    int Dimension,
    int ChunkX,
    int ChunkZ,
    BedrockWorldObjectSource Source,
    long? UniqueId,
    int ItemCount,
    NbtDocument Document,
    byte[] RawData,
    BedrockWorldObjectStorage Storage)
{
    public string DisplayName
    {
        get
        {
            if (!string.IsNullOrWhiteSpace(CustomName)) return CustomName.Trim();
            var value = string.IsNullOrWhiteSpace(Identifier) ? (Kind == BedrockWorldObjectKind.Entity ? "实体" : "方块实体") : Identifier;
            return value.StartsWith("minecraft:", StringComparison.OrdinalIgnoreCase) ? value["minecraft:".Length..] : value;
        }
    }

    public string SourceText => Source switch
    {
        BedrockWorldObjectSource.ModernActor => "actorprefix",
        BedrockWorldObjectSource.LegacyChunkEntity => "区块 Entity(0x32)",
        BedrockWorldObjectSource.BlockEntity => "区块 BlockEntity(0x31)",
        _ => Source.ToString()
    };

    public string KindText => Kind == BedrockWorldObjectKind.Entity ? "实体" : "方块实体";
}

public sealed record BedrockWorldObjectScanResult(
    IReadOnlyList<BedrockWorldObject> Objects,
    IReadOnlyList<string> Diagnostics,
    int ActorDigestCount,
    int ActorRecordCount,
    int LegacyEntityRecordCount,
    int BlockEntityRecordCount)
{
    public static readonly BedrockWorldObjectScanResult Empty = new(
        Array.Empty<BedrockWorldObject>(), Array.Empty<string>(), 0, 0, 0, 0);
}

public sealed record BedrockWorldObjectCreateResult(
    BedrockWorldObjectKind Kind,
    int Dimension,
    int ChunkX,
    int ChunkZ,
    long? UniqueId,
    BedrockWorldObjectSource Source);
