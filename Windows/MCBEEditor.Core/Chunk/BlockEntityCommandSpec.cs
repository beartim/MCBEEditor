using MCBEEditor.Core.Nbt;

namespace MCBEEditor.Core.Chunk;

public enum BlockEntityCommandMode { Preserve, Empty, Template }

/// <summary>A validated entity template, anchored to the command's first input coordinate.</summary>
public sealed class BlockEntityCommandSpec
{
    public static BlockEntityCommandSpec Preserve { get; } = new(BlockEntityCommandMode.Preserve);
    public static BlockEntityCommandSpec Empty { get; } = new(BlockEntityCommandMode.Empty);
    public BlockEntityCommandMode Mode { get; }
    private readonly IReadOnlyList<NbtNamedTag>? _tags;
    private readonly BedrockBlockCoordinate _origin;

    private BlockEntityCommandSpec(BlockEntityCommandMode mode, IReadOnlyList<NbtNamedTag>? tags = null, BedrockBlockCoordinate origin = default)
    {
        Mode = mode;
        _tags = tags;
        _origin = origin;
    }

    public static BlockEntityCommandSpec Parse(string text, BedrockBlockCoordinate origin)
    {
        if (text.Equals("preserve", StringComparison.OrdinalIgnoreCase)) return Preserve;
        if (text.Equals("empty", StringComparison.OrdinalIgnoreCase)) return Empty;
        if (!text.StartsWith('\'')) throw new InvalidDataException("方块实体参数必须为 preserve、empty 或完整 MCBE-SNBT 标签。");
        var tags = BlockCommandParser.ParseStates(text);
        foreach (var (name, expected) in Coordinates(origin))
        {
            var matches = tags.Where(tag => tag.Name.Equals(name, StringComparison.OrdinalIgnoreCase)).ToArray();
            if (matches.Length != 1 || !IsInteger(matches[0].Value) || matches[0].Value.IntegerValue() != expected)
                throw new InvalidDataException($"方块实体必须具有唯一的整数 {name} 标签，且数值等于命令第一组坐标 {expected}。");
        }
        return new BlockEntityCommandSpec(BlockEntityCommandMode.Template,
            tags.Select(tag => new NbtNamedTag(tag.Name, NbtDocumentTools.DeepClone(tag.Value))).ToArray(), origin);
    }

    internal void Validate(BedrockBlockBox region)
    {
        if (Mode != BlockEntityCommandMode.Template) return;
        if (!region.Contains(_origin.X, _origin.Y, _origin.Z))
            throw new InvalidDataException("方块实体模板坐标必须位于目标范围内。");
        // Check coordinate type capacity before staging chunk metadata or terrain.
        _ = DocumentAt(region.Minimum);
        _ = DocumentAt(region.Maximum);
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
        var coordinates = Coordinates(position).ToDictionary(pair => pair.Name, pair => pair.Value, StringComparer.OrdinalIgnoreCase);
        return new NbtDocument(string.Empty, new NbtCompoundValue(_tags.Select(tag =>
            new NbtNamedTag(tag.Name, coordinates.TryGetValue(tag.Name, out var value)
                ? CoordinateValue(tag.Value, value, tag.Name) : NbtDocumentTools.DeepClone(tag.Value))).ToArray()));
    }

    private static IEnumerable<(string Name, int Value)> Coordinates(BedrockBlockCoordinate position)
        => [("x", position.X), ("y", position.Y), ("z", position.Z)];

    private static bool IsInteger(NbtValue value) => value is NbtByteValue or NbtShortValue or NbtIntValue or NbtLongValue;

    private static NbtValue CoordinateValue(NbtValue original, int value, string name) => original switch
    {
        NbtByteValue when value is >= sbyte.MinValue and <= sbyte.MaxValue => new NbtByteValue((sbyte)value),
        NbtShortValue when value is >= short.MinValue and <= short.MaxValue => new NbtShortValue((short)value),
        NbtIntValue => new NbtIntValue(value),
        NbtLongValue => new NbtLongValue(value),
        _ => throw new InvalidDataException($"目标坐标 {name}={value} 超出方块实体模板的整数类型范围。")
    };
}
