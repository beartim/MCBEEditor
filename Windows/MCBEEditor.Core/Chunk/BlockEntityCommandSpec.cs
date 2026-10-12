using MCBEEditor.Core.Nbt;

namespace MCBEEditor.Core.Chunk;

public enum BlockEntityCommandMode { Preserve, Empty, Template }

/// <summary>An entity template whose root coordinates come from each command destination.</summary>
public sealed class BlockEntityCommandSpec
{
    public static BlockEntityCommandSpec Preserve { get; } = new(BlockEntityCommandMode.Preserve);
    public static BlockEntityCommandSpec Empty { get; } = new(BlockEntityCommandMode.Empty);
    public BlockEntityCommandMode Mode { get; }
    private readonly IReadOnlyList<NbtNamedTag>? _tags;

    private BlockEntityCommandSpec(BlockEntityCommandMode mode, IReadOnlyList<NbtNamedTag>? tags = null)
    {
        Mode = mode;
        _tags = tags;
    }

    public static BlockEntityCommandSpec Parse(string text)
    {
        if (text.Equals("preserve", StringComparison.OrdinalIgnoreCase)) return Preserve;
        if (text.Equals("empty", StringComparison.OrdinalIgnoreCase)) return Empty;
        if (!text.StartsWith('\'')) throw new InvalidDataException("方块实体参数必须为 preserve、empty 或完整 MCBE-SNBT 标签。");
        var tags = BlockCommandParser.ParseStates(text);
        return new BlockEntityCommandSpec(BlockEntityCommandMode.Template,
            tags.Where(tag => !IsCoordinateName(tag.Name))
                .Select(tag => new NbtNamedTag(tag.Name, NbtDocumentTools.DeepClone(tag.Value))).ToArray());
    }

    internal static BedrockBlockCoordinate? Coordinate(NbtValue root)
    {
        if (root is not NbtCompoundValue compound) return null;
        var values = new List<int>(3);
        foreach (var name in new[] { "x", "y", "z" })
        {
            var matches = compound.Tags.Where(tag => tag.Name.Equals(name, StringComparison.OrdinalIgnoreCase)).ToArray();
            if (matches.Length != 1 || !IsInteger(matches[0].Value) || matches[0].Value.IntegerValue() is not long number
                || number < int.MinValue || number > int.MaxValue) return null;
            values.Add((int)number);
        }
        return new BedrockBlockCoordinate(values[0], values[1], values[2]);
    }

    internal NbtDocument DocumentAt(BedrockBlockCoordinate position)
    {
        if (_tags is null) throw new InvalidOperationException("没有方块实体模板。");
        var tags = _tags.Select(tag => new NbtNamedTag(tag.Name, NbtDocumentTools.DeepClone(tag.Value)))
            .Concat(Coordinates(position).Select(pair => new NbtNamedTag(pair.Name, new NbtIntValue(pair.Value)))).ToArray();
        return new NbtDocument(string.Empty, new NbtCompoundValue(tags));
    }

    private static IEnumerable<(string Name, int Value)> Coordinates(BedrockBlockCoordinate position)
        => [("x", position.X), ("y", position.Y), ("z", position.Z)];

    private static bool IsInteger(NbtValue value) => value is NbtByteValue or NbtShortValue or NbtIntValue or NbtLongValue;

    private static bool IsCoordinateName(string name)
        => name.Equals("x", StringComparison.OrdinalIgnoreCase)
            || name.Equals("y", StringComparison.OrdinalIgnoreCase)
            || name.Equals("z", StringComparison.OrdinalIgnoreCase);
}
