using System.Globalization;
using System.Text;

namespace MCBEEditor.Core.Nbt;

public enum NbtEncoding
{
    BigEndian,
    LittleEndian,
    LittleEndianVarInt
}

public enum NbtTagType : byte
{
    End = 0,
    Byte = 1,
    Short = 2,
    Int = 3,
    Long = 4,
    Float = 5,
    Double = 6,
    ByteArray = 7,
    String = 8,
    List = 9,
    Compound = 10,
    IntArray = 11,
    LongArray = 12
}

public sealed record NbtNamedTag(string Name, NbtValue Value);

public abstract record NbtValue
{
    public abstract NbtTagType Type { get; }

    public virtual string Summary => Type.ToString();

    public virtual IReadOnlyList<NbtNamedTag> Children => Array.Empty<NbtNamedTag>();

    public NbtValue? CompoundValue(string name)
    {
        if (this is not NbtCompoundValue compound)
            return null;

        return compound.Tags.FirstOrDefault(t => t.Name == name)?.Value;
    }

    public NbtValue? CompoundValueIgnoreCase(params string[] names)
    {
        if (this is not NbtCompoundValue compound || names.Length == 0)
            return null;

        foreach (var name in names)
        {
            var exact = compound.Tags.FirstOrDefault(t => t.Name == name);
            if (exact is not null)
                return exact.Value;
        }

        var set = new HashSet<string>(names, StringComparer.OrdinalIgnoreCase);
        return compound.Tags.FirstOrDefault(t => set.Contains(t.Name))?.Value;
    }

    public string? StringValue(string name) => CompoundValue(name) is NbtStringValue value ? value.Value : null;

    public int? IntValue(string name) => CompoundValue(name) switch
    {
        NbtByteValue value => value.Value,
        NbtShortValue value => value.Value,
        NbtIntValue value => value.Value,
        _ => null
    };

    public long? IntegerValue() => this switch
    {
        NbtByteValue value => value.Value,
        NbtShortValue value => value.Value,
        NbtIntValue value => value.Value,
        NbtLongValue value => value.Value,
        NbtFloatValue value => FloatingIntegerValue(value.Value),
        NbtDoubleValue value => FloatingIntegerValue(value.Value),
        _ => null
    };

    private static long? FloatingIntegerValue(double value)
    {
        if (!double.IsFinite(value)) return null;
        var truncated = Math.Truncate(value);
        // 2^63 is the first Double outside Int64's positive range. Using
        // long.MaxValue directly in a Double comparison is unsafe because it
        // rounds to 2^63 as well.
        if (truncated < -9_223_372_036_854_775_808.0 || truncated >= 9_223_372_036_854_775_808.0)
            return null;
        return (long)truncated;
    }
}

public sealed record NbtByteValue(sbyte Value) : NbtValue
{
    public override NbtTagType Type => NbtTagType.Byte;
    public override string Summary => Value.ToString(CultureInfo.InvariantCulture);
}

public sealed record NbtShortValue(short Value) : NbtValue
{
    public override NbtTagType Type => NbtTagType.Short;
    public override string Summary => Value.ToString(CultureInfo.InvariantCulture);
}

public sealed record NbtIntValue(int Value) : NbtValue
{
    public override NbtTagType Type => NbtTagType.Int;
    public override string Summary => Value.ToString(CultureInfo.InvariantCulture);
}

public sealed record NbtLongValue(long Value) : NbtValue
{
    public override NbtTagType Type => NbtTagType.Long;
    public override string Summary => Value.ToString(CultureInfo.InvariantCulture);
}

public sealed record NbtFloatValue(float Value) : NbtValue
{
    public override NbtTagType Type => NbtTagType.Float;
    public override string Summary => Value.ToString("R", CultureInfo.InvariantCulture);
}

public sealed record NbtDoubleValue(double Value) : NbtValue
{
    public override NbtTagType Type => NbtTagType.Double;
    public override string Summary => Value.ToString("R", CultureInfo.InvariantCulture);
}

public sealed record NbtByteArrayValue(byte[] Value) : NbtValue
{
    public override NbtTagType Type => NbtTagType.ByteArray;
    public override string Summary => $"ByteArray[{Value.Length}]";
}

public sealed record NbtStringValue(string Value) : NbtValue
{
    public override NbtTagType Type => NbtTagType.String;
    public override string Summary => NbtRawStringCodec.DisplayText(Value);
}

public sealed record NbtListValue(NbtTagType ElementType, IReadOnlyList<NbtValue> Values) : NbtValue
{
    public override NbtTagType Type => NbtTagType.List;
    public override string Summary => $"List[{Values.Count}]";
    public override IReadOnlyList<NbtNamedTag> Children => Values.Select((value, index) => new NbtNamedTag($"[{index}]", value)).ToArray();
}

public sealed record NbtCompoundValue(IReadOnlyList<NbtNamedTag> Tags) : NbtValue
{
    public override NbtTagType Type => NbtTagType.Compound;
    public override string Summary => $"Compound{{{Tags.Count}}}";
    public override IReadOnlyList<NbtNamedTag> Children => Tags;
}

public sealed record NbtIntArrayValue(IReadOnlyList<int> Values) : NbtValue
{
    public override NbtTagType Type => NbtTagType.IntArray;
    public override string Summary => $"IntArray[{Values.Count}]";
}

public sealed record NbtLongArrayValue(IReadOnlyList<long> Values) : NbtValue
{
    public override NbtTagType Type => NbtTagType.LongArray;
    public override string Summary => $"LongArray[{Values.Count}]";
}

public sealed record NbtDocument(string RootName, NbtValue Root);

public static class NbtRawStringCodec
{
    private const string Sentinel = "\U000F0000\U000F0001MCBE_RAW_NBT_STRING:";
    private static readonly UTF8Encoding StrictUtf8 = new(false, true);

    public static string Decode(ReadOnlySpan<byte> bytes)
    {
        try
        {
            return StrictUtf8.GetString(bytes);
        }
        catch (DecoderFallbackException)
        {
            return Sentinel + Convert.ToHexString(bytes).ToLowerInvariant();
        }
    }

    public static byte[] Encode(string value)
    {
        if (TryRawBytes(value, out var raw))
            return raw;
        return Encoding.UTF8.GetBytes(value);
    }

    public static bool TryRawBytes(string value, out byte[] bytes)
    {
        bytes = Array.Empty<byte>();
        if (!value.StartsWith(Sentinel, StringComparison.Ordinal))
            return false;

        var hex = value[Sentinel.Length..];
        if ((hex.Length & 1) != 0)
            return false;

        try
        {
            bytes = Convert.FromHexString(hex);
            // The sentinel is reserved for byte sequences that are not UTF-8.
            _ = StrictUtf8.GetString(bytes);
            bytes = Array.Empty<byte>();
            return false;
        }
        catch (DecoderFallbackException)
        {
            return true;
        }
        catch (FormatException)
        {
            bytes = Array.Empty<byte>();
            return false;
        }
    }

    public static string DisplayText(string value)
    {
        if (!TryRawBytes(value, out var bytes))
            return value;

        return $"RawString[{bytes.Length}] {string.Join(' ', bytes.Select(b => b.ToString("x2", CultureInfo.InvariantCulture)))}";
    }
}
