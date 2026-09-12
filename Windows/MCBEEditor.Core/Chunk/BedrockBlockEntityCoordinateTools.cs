using MCBEEditor.Core.Nbt;

namespace MCBEEditor.Core.Chunk;

internal static class BedrockBlockEntityCoordinateTools
{
    public static byte[] OffsetPayload(byte[] data, long deltaX, long deltaZ)
    {
        var records = ConsecutiveNbtCodec.Decode(data);
        var updated = records.Select(record => record with
        {
            Document = record.Document with { Root = OffsetRoot(record.Document.Root, deltaX, deltaZ) },
            RawData = []
        }).ToArray();
        return ConsecutiveNbtCodec.Encode(updated);
    }

    public static bool TryGetXZ(NbtValue root, out long x, out long z)
    {
        x = z = 0;
        if (root is not NbtCompoundValue compound) return false;
        long? Read(params string[] names)
        {
            foreach (var tag in compound.Tags)
            foreach (var name in names)
                if (tag.Name.Equals(name, StringComparison.OrdinalIgnoreCase) && tag.Value.IntegerValue() is long value)
                    return value;
            return null;
        }
        var readX = Read("x", "pairx");
        var readZ = Read("z", "pairz");
        if (!readX.HasValue || !readZ.HasValue) return false;
        x = readX.Value; z = readZ.Value; return true;
    }

    public static NbtValue OffsetRoot(NbtValue value, long deltaX, long deltaZ)
    {
        if (value is not NbtCompoundValue compound) return value;
        var tags = compound.Tags.Select(tag =>
        {
            var lower = tag.Name.ToLowerInvariant();
            return lower switch
            {
                "x" or "pairx" => tag with { Value = OffsetNumeric(tag.Value, deltaX) },
                "z" or "pairz" => tag with { Value = OffsetNumeric(tag.Value, deltaZ) },
                _ => tag
            };
        }).ToArray();
        return new NbtCompoundValue(tags);
    }

    private static NbtValue OffsetNumeric(NbtValue value, long delta) => value switch
    {
        NbtByteValue number => new NbtByteValue((sbyte)Math.Clamp((long)number.Value + delta, sbyte.MinValue, sbyte.MaxValue)),
        NbtShortValue number => new NbtShortValue((short)Math.Clamp((long)number.Value + delta, short.MinValue, short.MaxValue)),
        NbtIntValue number => new NbtIntValue((int)Math.Clamp((long)number.Value + delta, int.MinValue, int.MaxValue)),
        NbtLongValue number => new NbtLongValue(unchecked(number.Value + delta)),
        NbtFloatValue number => new NbtFloatValue(number.Value + (float)delta),
        NbtDoubleValue number => new NbtDoubleValue(number.Value + delta),
        _ => value
    };
}
