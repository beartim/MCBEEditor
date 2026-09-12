using MCBEEditor.Core.Nbt;

namespace MCBEEditor.Core.Entity;

/// <summary>
/// Common Bedrock entity tags shared by the Windows entity creator/importer.
/// Type-specific data is intentionally preserved from copied/imported NBT.
/// </summary>
public static class BedrockEntityCommonNbt
{
    public static IReadOnlyList<NbtNamedTag> Tags(string identifier, BedrockWorldObjectPosition position, int dimension, long uniqueId)
        =>
        [
            new("definitions", new NbtListValue(NbtTagType.String, [new NbtStringValue("+" + NormalizeIdentifier(identifier))])),
            new("UniqueID", new NbtLongValue(uniqueId)),
            new("Air", new NbtShortValue(300)),
            new("Chested", new NbtByteValue(0)),
            new("Color", new NbtByteValue(0)),
            new("Color2", new NbtByteValue(0)),
            new("CustomName", new NbtStringValue(string.Empty)),
            new("CustomNameVisible", new NbtByteValue(0)),
            new("Dead", new NbtByteValue(0)),
            new("DeathTime", new NbtShortValue(0)),
            new("DimensionId", new NbtIntValue(dimension)),
            new("FallDistance", new NbtFloatValue(0)),
            new("Fire", new NbtShortValue(0)),
            new("HasBoundOrigin", new NbtByteValue(0)),
            new("Invulnerable", new NbtByteValue(0)),
            new("IsAngry", new NbtByteValue(0)),
            new("IsAutonomous", new NbtByteValue(0)),
            new("IsBaby", new NbtByteValue(0)),
            new("IsEating", new NbtByteValue(0)),
            new("IsGliding", new NbtByteValue(0)),
            new("IsGlobal", new NbtByteValue(0)),
            new("IsIllagerCaptain", new NbtByteValue(0)),
            new("IsOrphaned", new NbtByteValue(0)),
            new("IsOutOfControl", new NbtByteValue(0)),
            new("IsRoaring", new NbtByteValue(0)),
            new("IsScared", new NbtByteValue(0)),
            new("IsStunned", new NbtByteValue(0)),
            new("IsSwimming", new NbtByteValue(0)),
            new("IsTamed", new NbtByteValue(0)),
            new("IsTrusting", new NbtByteValue(0)),
            new("LastDimensionId", new NbtIntValue(dimension)),
            new("LootDropped", new NbtByteValue(0)),
            new("MarkVariant", new NbtIntValue(0)),
            new("Motion", new NbtListValue(NbtTagType.Float, [new NbtFloatValue(0), new NbtFloatValue(0), new NbtFloatValue(0)])),
            new("OnGround", new NbtByteValue(1)),
            new("OwnerNew", new NbtLongValue(-1)),
            new("Persistent", new NbtByteValue(1)),
            new("PortalCooldown", new NbtIntValue(0)),
            new("Pos", PositionTag(position)),
            new("Rotation", new NbtListValue(NbtTagType.Float, [new NbtFloatValue(0), new NbtFloatValue(0)])),
            new("Saddled", new NbtByteValue(0)),
            new("Sheared", new NbtByteValue(0)),
            new("ShowBottom", new NbtByteValue(0)),
            new("Sitting", new NbtByteValue(0)),
            new("SkinID", new NbtIntValue(0)),
            new("Strength", new NbtIntValue(0)),
            new("StrengthMax", new NbtIntValue(0)),
            new("Tags", new NbtListValue(NbtTagType.String, [])),
            new("Variant", new NbtIntValue(0))
        ];

    public static NbtListValue PositionTag(BedrockWorldObjectPosition position)
        => new(NbtTagType.Float,
        [
            new NbtFloatValue(CheckedFloat(position.X, "X")),
            new NbtFloatValue(CheckedFloat(position.Y, "Y")),
            new NbtFloatValue(CheckedFloat(position.Z, "Z"))
        ]);

    public static NbtValue AddMissingTopLevel(NbtValue root, IEnumerable<NbtNamedTag> defaults)
    {
        if (root is not NbtCompoundValue compound) throw new InvalidDataException("实体 NBT 根必须是 Compound。");
        var tags = compound.Tags.Select(tag => new NbtNamedTag(tag.Name, NbtDocumentTools.DeepClone(tag.Value))).ToList();
        var names = new HashSet<string>(tags.Select(tag => tag.Name), StringComparer.OrdinalIgnoreCase);
        foreach (var tag in defaults)
            if (names.Add(tag.Name)) tags.Add(new NbtNamedTag(tag.Name, NbtDocumentTools.DeepClone(tag.Value)));
        return new NbtCompoundValue(tags);
    }

    public static string? Identifier(NbtValue root)
    {
        var direct = root.CompoundValueIgnoreCase("identifier", "Identifier", "id", "Id");
        if (direct is NbtStringValue text && !string.IsNullOrWhiteSpace(text.Value))
        {
            var raw = text.Value.Trim();
            if (raw.Contains(':')) return NormalizeIdentifier(raw);
            if (long.TryParse(raw, out var numericText)) return BedrockEntityCatalog.IdentifierForNumericId(numericText);
        }
        if (direct?.IntegerValue() is long numeric) return BedrockEntityCatalog.IdentifierForNumericId(numeric);
        if (root.CompoundValueIgnoreCase("definitions", "Definitions") is NbtListValue list)
        {
            for (var i = list.Values.Count - 1; i >= 0; i--)
            {
                if (list.Values[i] is not NbtStringValue definition) continue;
                var value = definition.Value.TrimStart('+', '-').Trim();
                if (value.Contains(':')) return NormalizeIdentifier(value);
            }
        }
        return null;
    }

    public static BedrockWorldObjectPosition? Position(NbtValue root)
        => BedrockWorldObjectScanner.ExtractPosition(root, BedrockWorldObjectKind.Entity);

    public static int? Dimension(NbtValue root) => BedrockWorldObjectScanner.ExtractDimension(root);

    public static long? UniqueId(NbtValue root)
        => root.CompoundValueIgnoreCase("UniqueID", "UniqueId", "uniqueID", "uniqueId")?.IntegerValue();

    public static string NormalizeIdentifier(string identifier)
    {
        var value = identifier.Trim().ToLowerInvariant();
        return value.Contains(':') ? value : "minecraft:" + value;
    }

    private static float CheckedFloat(double value, string axis)
    {
        if (!double.IsFinite(value) || value < -float.MaxValue || value > float.MaxValue)
            throw new InvalidDataException($"实体 {axis} 坐标无法写入 Float。");
        return (float)value;
    }
}
