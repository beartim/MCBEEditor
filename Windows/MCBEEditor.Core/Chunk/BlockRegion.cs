using MCBEEditor.Core.Nbt;

namespace MCBEEditor.Core.Chunk;

public readonly record struct BedrockBlockCoordinate(int X, int Y, int Z);

public readonly record struct BedrockBlockBox
{
    public BedrockBlockCoordinate Minimum { get; }
    public BedrockBlockCoordinate Maximum { get; }

    public BedrockBlockBox(BedrockBlockCoordinate first, BedrockBlockCoordinate second)
    {
        Minimum = new BedrockBlockCoordinate(Math.Min(first.X, second.X), Math.Min(first.Y, second.Y), Math.Min(first.Z, second.Z));
        Maximum = new BedrockBlockCoordinate(Math.Max(first.X, second.X), Math.Max(first.Y, second.Y), Math.Max(first.Z, second.Z));
    }

    private BedrockBlockBox(BedrockBlockCoordinate minimum, BedrockBlockCoordinate maximum, bool alreadyNormalized)
    {
        Minimum = minimum; Maximum = maximum;
    }

    public long Volume
    {
        get
        {
            checked
            {
                return ((long)Maximum.X - Minimum.X + 1)
                     * ((long)Maximum.Y - Minimum.Y + 1)
                     * ((long)Maximum.Z - Minimum.Z + 1);
            }
        }
    }

    public bool Contains(int x, int y, int z)
        => x >= Minimum.X && x <= Maximum.X
        && y >= Minimum.Y && y <= Maximum.Y
        && z >= Minimum.Z && z <= Maximum.Z;

    public BedrockBlockBox TranslateTo(BedrockBlockCoordinate destination)
    {
        checked
        {
            return new BedrockBlockBox(destination,
                new BedrockBlockCoordinate(
                    destination.X + (Maximum.X - Minimum.X),
                    destination.Y + (Maximum.Y - Minimum.Y),
                    destination.Z + (Maximum.Z - Minimum.Z)), alreadyNormalized: true);
        }
    }
}


public sealed record BedrockBlockStorageSpec(string Name, IReadOnlyList<NbtNamedTag> States)
{
    public BedrockBlockState ModernState(int? version)
        => new(new NbtCompoundValue([
            new NbtNamedTag("name", new NbtStringValue(Name)),
            new NbtNamedTag("states", new NbtCompoundValue(States.Select(tag => new NbtNamedTag(tag.Name, NbtDocumentTools.DeepClone(tag.Value))).ToArray())),
            new NbtNamedTag("version", new NbtIntValue(version ?? BedrockBlockState.DefaultPaletteVersion))
        ]), null, null);

    public bool CanRemainLegacy(int layer)
        => layer is 0 or 1 && BedrockLegacyBlockCatalog.NumericIdForIdentifier(Name) is <= byte.MaxValue
            && BedrockLegacyBlockStateConverter.NumericData(ModernState(null)) is byte data
            && (layer == 1 || data <= 15);

    public BedrockBlockState LegacyState()
    {
        var id = BedrockLegacyBlockCatalog.NumericIdForIdentifier(Name)
            ?? throw new NotSupportedException($"方块 {Name} 没有可用的旧版数字 ID。");
        var data = BedrockLegacyBlockStateConverter.NumericData(ModernState(null))
            ?? throw new NotSupportedException($"旧版数字 ID 无法无损表示 {Name} 的 states。");
        return new BedrockBlockState(null, id, data);
    }
}

public sealed record BedrockRegionMutationResult(
    long ChangedBlockPositions,
    int TouchedSubChunks,
    int TouchedChunks,
    int RemovedBlockEntities,
    int CopiedBlockEntities,
    int PutCount,
    int DeleteCount);
