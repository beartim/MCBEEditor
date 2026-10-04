using MCBEEditor.Core.Entity;
using MCBEEditor.Core.World;

namespace MCBEEditor.Core.Chunk;

public sealed record EntityQueryBounds(double MinX, double MinY, double MinZ, double MaxX, double MaxY, double MaxZ)
{
    public bool Contains(BedrockWorldObjectPosition position)
        => position.X >= MinX && position.X <= MaxX
           && position.Y >= MinY && position.Y <= MaxY
           && position.Z >= MinZ && position.Z <= MaxZ;
}

public sealed record EntityQueryCommandRequest(int? Dimension = null, EntityQueryBounds? Bounds = null);

public static class EntityQueryCommandParser
{
    public const string Usage = "entity [维度 [x1 y1 z1 x2 y2 z2]]";

    public static bool IsEntityQueryCommand(string text)
        => text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).FirstOrDefault()
            ?.Equals("entity", StringComparison.OrdinalIgnoreCase) == true;

    public static EntityQueryCommandRequest Parse(string text, Func<string,int>? dimensionResolver = null)
    {
        var tokens = BlockCommandParser.TokenizeCommand(text);
        if (tokens.Count == 0 || !tokens[0].Equals("entity", StringComparison.OrdinalIgnoreCase)
            || tokens.Count is not (1 or 2 or 8))
            throw new InvalidDataException("参数格式错误。\n" + Usage);
        if (tokens.Count == 1) return new EntityQueryCommandRequest();
        var dimension = BlockCommandParser.ParseDimension(tokens[1], dimensionResolver);
        if (tokens.Count == 2) return new EntityQueryCommandRequest(dimension);
        var x1 = Coordinate(tokens[2], "X1");
        var y1 = Coordinate(tokens[3], "Y1");
        var z1 = Coordinate(tokens[4], "Z1");
        var x2 = Coordinate(tokens[5], "X2");
        var y2 = Coordinate(tokens[6], "Y2");
        var z2 = Coordinate(tokens[7], "Z2");
        return new EntityQueryCommandRequest(dimension, new EntityQueryBounds(
            Math.Min(x1, x2), Math.Min(y1, y2), Math.Min(z1, z2),
            Math.Max(x1, x2), Math.Max(y1, y2), Math.Max(z1, z2)));
    }

    private static double Coordinate(string text, string name)
        => EntityActionCommandParser.ParseEntityCoordinate(text, name, "entity");
}

public sealed class EntityQueryCommandStore(IWorldDatabase database)
{
    public TargetingCommandExecutionResult Execute(EntityQueryCommandRequest request)
    {
        // NBT may override the owning digp/chunk dimension; filter the same
        // resolved objects shown by the entity browser after scanning all records.
        var scan = new BedrockWorldObjectScanner(database).ScanAll(
            dimensions: null, includeEntities: true, includeBlockEntities: false, maximumObjects: int.MaxValue);
        var lines = scan.Objects
            .Where(item => !request.Dimension.HasValue || item.Dimension == request.Dimension.Value)
            .Where(item => request.Bounds is null || item.Position is not null && request.Bounds.Contains(item.Position))
            .Select(item => new TargetingOutputLine(
                $"{item.Identifier}=[{BlockCommandNbtOutputFormatter.Root(item.Document.Root)}]", TargetingOutputStyle.Entity))
            .ToList();
        var message = lines.Count == 0 ? "entity：没有匹配的实体。" : $"entity：找到 {lines.Count} 个实体。";
        if (lines.Count == 0) lines.Add(new TargetingOutputLine(message, TargetingOutputStyle.Entity));
        lines.AddRange(scan.Diagnostics.Select(diagnostic =>
            new TargetingOutputLine("entity 扫描提示：" + diagnostic, TargetingOutputStyle.Entity)));
        return new TargetingCommandExecutionResult(message, false, lines);
    }
}
