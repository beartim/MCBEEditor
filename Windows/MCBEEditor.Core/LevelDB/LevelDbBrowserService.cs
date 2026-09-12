using System.Text;
using MCBEEditor.Core.Chunk;
using MCBEEditor.Core.World;

namespace MCBEEditor.Core.LevelDB;

public sealed record LevelDbBrowserRow(
    string KeyHex,
    string KeyDescription,
    int ValueLength,
    string ValuePreview);

public static class LevelDbBrowserService
{
    public static IReadOnlyList<LevelDbBrowserRow> Browse(
        IWorldDatabase database,
        string? prefixHex,
        int limit = 500,
        int previewBytes = 48)
    {
        ArgumentNullException.ThrowIfNull(database);
        if (limit is < 1 or > 5000) throw new ArgumentOutOfRangeException(nameof(limit));
        if (previewBytes is < 0 or > 4096) throw new ArgumentOutOfRangeException(nameof(previewBytes));

        byte[]? prefix = null;
        var trimmed = prefixHex?.Trim().Replace(" ", string.Empty, StringComparison.Ordinal);
        if (!string.IsNullOrEmpty(trimmed))
        {
            if (trimmed.Length % 2 != 0)
                throw new InvalidDataException("十六进制前缀必须包含偶数个字符");
            try { prefix = Convert.FromHexString(trimmed); }
            catch (FormatException) { throw new InvalidDataException("十六进制前缀只能包含 0-9、A-F"); }
        }

        ReadOnlyMemory<byte>? prefixMemory = prefix is null ? null : new ReadOnlyMemory<byte>(prefix);
        return database.Entries(prefixMemory, includeValues: true, limit)
            .Select(entry => new LevelDbBrowserRow(
                Convert.ToHexString(entry.Key),
                DescribeKey(entry.Key),
                entry.Value?.Length ?? 0,
                Preview(entry.Value ?? [], previewBytes)))
            .ToArray();
    }

    public static string DescribeKey(ReadOnlySpan<byte> key)
    {
        // Textual/global keys must be recognized before the generic chunk-key
        // parser because arbitrary bytes inside an actor ID can look like a tag.
        if (BedrockChunkStore.TryParseActorDigestKey(key, out var position))
            return $"{position.DimensionName} ({position.X}, {position.Z}) ActorDigest";
        if (key.StartsWith("actorprefix"u8) && key.Length == 19)
            return "Actor " + Convert.ToHexString(key[11..]);
        if (key.StartsWith("player_"u8))
            return "Player " + SafeAscii(key);
        if (key.SequenceEqual("~local_player"u8))
            return "LocalPlayer";
        if (BedrockDbKey.TryParse(key, out var parsed)) return parsed.ToString();
        return SafeAscii(key);
    }

    private static string Preview(ReadOnlySpan<byte> value, int previewBytes)
    {
        if (value.IsEmpty) return "(empty)";
        var count = Math.Min(value.Length, previewBytes);
        var prefix = value[..count];
        var hex = Convert.ToHexString(prefix);
        var suffix = value.Length > count ? "…" : string.Empty;
        return hex + suffix;
    }

    private static string SafeAscii(ReadOnlySpan<byte> key)
    {
        if (key.IsEmpty) return "(empty key)";
        var printable = true;
        foreach (var value in key)
        {
            if (value is < 0x20 or > 0x7e) { printable = false; break; }
        }
        if (printable) return Encoding.ASCII.GetString(key);
        return "Raw key";
    }
}
