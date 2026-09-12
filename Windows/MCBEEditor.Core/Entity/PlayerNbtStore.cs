using System.Globalization;
using System.Text;
using MCBEEditor.Core.Nbt;
using MCBEEditor.Core.World;

namespace MCBEEditor.Core.Entity;

public sealed record PlayerCurrentPosition(double X, double Y, double Z, int Dimension)
{
    public int BlockX => (int)Math.Floor(X);
    public int BlockY => (int)Math.Floor(Y);
    public int BlockZ => (int)Math.Floor(Z);
}

public sealed record PlayerNbtRecord(byte[] Key, string KeyText, string DisplayName, NbtDocument Document, byte[] RawData)
{
    public bool IsLocal => KeyText is "~local_player" or "LocalPlayer";
}

public sealed class PlayerNbtStore
{
    private readonly IWorldDatabase _database;

    public PlayerNbtStore(IWorldDatabase database) => _database = database;

    public IReadOnlyList<PlayerNbtRecord> Records()
    {
        var values = new Dictionary<string, (byte[] Key, byte[] Value)>(StringComparer.Ordinal);
        foreach (var keyText in new[] { "~local_player", "LocalPlayer" })
        {
            var key = Encoding.UTF8.GetBytes(keyText);
            var value = _database.Get(key);
            if (value is not null) values[Convert.ToHexString(key)] = (key, value);
        }
        foreach (var entry in _database.Entries(Encoding.UTF8.GetBytes("player_"), includeValues: true))
            if (entry.Value is not null) values[Convert.ToHexString(entry.Key)] = (entry.Key, entry.Value);

        var output = new List<PlayerNbtRecord>();
        foreach (var pair in values.Values)
        {
            try
            {
                var document = BedrockNbtCodec.Decode(pair.Value, NbtEncoding.LittleEndian);
                var keyText = SafeKeyText(pair.Key);
                output.Add(new PlayerNbtRecord(pair.Key, keyText, DisplayName(document, keyText), document, pair.Value));
            }
            catch (InvalidDataException)
            {
                // Malformed/non-NBT player-prefixed records must not enter the editor.
            }
        }

        return output.OrderByDescending(p => p.IsLocal)
            .ThenBy(p => p.DisplayName, StringComparer.CurrentCultureIgnoreCase)
            .ThenBy(p => p.KeyText, StringComparer.Ordinal)
            .ToArray();
    }

    public PlayerCurrentPosition? CurrentPosition(PlayerNbtRecord record)
    {
        var root = record.Document.Root;
        var position = root.CompoundValueIgnoreCase("Pos", "pos", "Position", "position");
        if (!TryPosition(position, out var x, out var y, out var z)) return null;
        var dimension = ParseDimension(root.CompoundValueIgnoreCase(
            "DimensionId", "DimensionID", "dimension_id", "Dimension", "dimension")) ?? 0;
        return new PlayerCurrentPosition(x, y, z, dimension);
    }

    public long? UniqueId(PlayerNbtRecord record)
    {
        var value = record.Document.Root.CompoundValueIgnoreCase("UniqueID", "UniqueId", "uniqueID", "uniqueId")?.IntegerValue();
        if (value.HasValue) return value.Value;
        foreach (var prefix in new[] { "player_server_", "player_" })
            if (record.KeyText.StartsWith(prefix, StringComparison.Ordinal) && long.TryParse(record.KeyText[prefix.Length..], NumberStyles.Integer, CultureInfo.InvariantCulture, out var parsed))
                return parsed;
        return null;
    }

    public void Save(PlayerNbtRecord record, NbtDocument document)
    {
        if (document.Root is not NbtCompoundValue)
            throw new InvalidDataException("玩家 NBT 根必须是 Compound。");
        _database.Put(record.Key, BedrockNbtCodec.Encode(document, NbtEncoding.LittleEndian), sync: true);
    }

    /// <summary>
    /// Deletes selected non-local player records together with related online-player
    /// key families. This mirrors the iOS kick command and never deletes the local
    /// player record.
    /// </summary>
    public int DeleteOnlinePlayerData(IEnumerable<PlayerNbtRecord> selectedRecords)
    {
        var records = selectedRecords.Where(record => !record.IsLocal).ToArray();
        if (records.Length == 0) return 0;

        var deleteKeys = new Dictionary<string, byte[]>(StringComparer.Ordinal);
        foreach (var record in records) deleteKeys[Convert.ToHexString(record.Key)] = record.Key.ToArray();
        var keyTexts = new HashSet<string>(records.Select(record => record.KeyText), StringComparer.Ordinal);
        var uniqueIds = records.Select(record => UniqueId(record))
            .Where(value => value.HasValue)
            .Select(value => value!.Value)
            .ToHashSet();
        var prefixes = new[] { "player_", "player_server_", "player_data_", "player_storage_" };
        var strictUtf8 = new UTF8Encoding(false, true);

        foreach (var entry in _database.Entries(includeValues: false))
        {
            string text;
            try { text = strictUtf8.GetString(entry.Key); }
            catch (DecoderFallbackException) { continue; }

            if (keyTexts.Contains(text) || keyTexts.Any(keyText =>
                    text.StartsWith(keyText + "_", StringComparison.Ordinal)
                    || text.StartsWith(keyText + ":", StringComparison.Ordinal)
                    || text.StartsWith(keyText + "/", StringComparison.Ordinal)))
            {
                deleteKeys[Convert.ToHexString(entry.Key)] = entry.Key.ToArray();
                continue;
            }
            if (!prefixes.Any(prefix => text.StartsWith(prefix, StringComparison.Ordinal))) continue;
            foreach (var id in uniqueIds)
            {
                var token = id.ToString(CultureInfo.InvariantCulture);
                if (text == token || text.EndsWith("_" + token, StringComparison.Ordinal) || text.EndsWith(":" + token, StringComparison.Ordinal)
                    || text.Contains("_" + token + "_", StringComparison.Ordinal) || text.Contains(":" + token + ":", StringComparison.Ordinal))
                {
                    deleteKeys[Convert.ToHexString(entry.Key)] = entry.Key.ToArray();
                    break;
                }
            }
        }

        _database.ApplyBatch([], deleteKeys.Values, sync: true);
        return deleteKeys.Count;
    }

    private static string SafeKeyText(byte[] key)
    {
        try { return new UTF8Encoding(false, true).GetString(key); }
        catch (DecoderFallbackException) { return "0x" + Convert.ToHexString(key).ToLowerInvariant(); }
    }

    private static string DisplayName(NbtDocument document, string keyText)
    {
        foreach (var name in new[] { "PlayerName", "NameTag", "CustomName", "name", "XUID" })
            if (document.Root.CompoundValue(name) is NbtStringValue text && !string.IsNullOrWhiteSpace(text.Value))
                return text.Value.Trim();
        if (keyText is "~local_player" or "LocalPlayer") return "本机玩家";
        if (keyText.StartsWith("player_server_", StringComparison.Ordinal)) return "服务器玩家 " + keyText["player_server_".Length..];
        if (keyText.StartsWith("player_", StringComparison.Ordinal)) return "远程玩家 " + keyText["player_".Length..];
        return keyText;
    }

    private static bool TryPosition(NbtValue? value, out double x, out double y, out double z)
    {
        x = y = z = 0;
        switch (value)
        {
            case NbtListValue list when list.Values.Count >= 3:
                return TryNumber(list.Values[0], out x) && TryNumber(list.Values[1], out y) && TryNumber(list.Values[2], out z);
            case NbtIntArrayValue ints when ints.Values.Count >= 3:
                x = ints.Values[0]; y = ints.Values[1]; z = ints.Values[2]; return true;
            case NbtLongArrayValue longs when longs.Values.Count >= 3:
                x = longs.Values[0]; y = longs.Values[1]; z = longs.Values[2]; return true;
            case NbtCompoundValue compound:
                return TryNumber(compound.CompoundValueIgnoreCase("X", "x"), out x)
                    && TryNumber(compound.CompoundValueIgnoreCase("Y", "y"), out y)
                    && TryNumber(compound.CompoundValueIgnoreCase("Z", "z"), out z);
            default:
                return false;
        }
    }

    internal static bool TryNumber(NbtValue? value, out double number)
    {
        number = value switch
        {
            NbtByteValue v => v.Value,
            NbtShortValue v => v.Value,
            NbtIntValue v => v.Value,
            NbtLongValue v => v.Value,
            NbtFloatValue v => v.Value,
            NbtDoubleValue v => v.Value,
            _ => double.NaN
        };
        return double.IsFinite(number);
    }

    internal static int? ParseDimension(NbtValue? value)
    {
        if (value?.IntegerValue() is long number)
            return (int)Math.Clamp(number, int.MinValue, int.MaxValue);
        if (value is not NbtStringValue textValue) return null;
        var text = textValue.Value.Trim().ToLowerInvariant();
        if (text.Contains("nether", StringComparison.Ordinal)) return 1;
        if (text.Contains("end", StringComparison.Ordinal)) return 2;
        if (text.Contains("overworld", StringComparison.Ordinal)) return 0;
        return int.TryParse(text, NumberStyles.Integer, CultureInfo.InvariantCulture, out var parsed) ? parsed : null;
    }
}
