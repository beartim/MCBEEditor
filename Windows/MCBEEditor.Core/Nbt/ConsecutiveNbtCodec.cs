namespace MCBEEditor.Core.Nbt;

public sealed record ConsecutiveNbtRecord(NbtDocument Document, byte[] RawData, NbtEncoding Encoding);

public static class ConsecutiveNbtCodec
{
    public static IReadOnlyList<ConsecutiveNbtRecord> Decode(ReadOnlySpan<byte> data)
    {
        if (data.Length == 0) return Array.Empty<ConsecutiveNbtRecord>();

        var records = new List<ConsecutiveNbtRecord>();
        var offset = 0;
        while (offset < data.Length)
        {
            var remaining = data[offset..];
            if (AllZero(remaining)) break;

            try
            {
                var document = BedrockNbtCodec.DecodeOne(remaining, out var consumed, NbtEncoding.LittleEndian);
                if (consumed <= 0) throw new InvalidDataException("NBT parser did not advance.");
                records.Add(new ConsecutiveNbtRecord(document, remaining[..consumed].ToArray(), NbtEncoding.LittleEndian));
                offset += consumed;
            }
            catch (Exception littleEndianError)
            {
                if (records.Count != 0)
                    throw new InvalidDataException($"Consecutive NBT failed at offset {offset}: {littleEndianError.Message}", littleEndianError);

                try
                {
                    var fallback = BedrockNbtCodec.Decode(remaining, NbtEncoding.LittleEndianVarInt);
                    var reencoded = BedrockNbtCodec.Encode(fallback, NbtEncoding.LittleEndianVarInt);
                    if (reencoded.Length > remaining.Length || !remaining[..reencoded.Length].SequenceEqual(reencoded) || !AllZero(remaining[reencoded.Length..]))
                        throw new InvalidDataException(
                            $"Little-endian VarInt fallback did not consume a canonical NBT payload at offset {offset}.",
                            littleEndianError);
                    return [new ConsecutiveNbtRecord(fallback, remaining.ToArray(), NbtEncoding.LittleEndianVarInt)];
                }
                catch (Exception)
                {
                    throw new InvalidDataException($"Consecutive NBT failed at offset {offset}: {littleEndianError.Message}", littleEndianError);
                }
            }
        }
        return records;
    }

    public static byte[] Encode(IEnumerable<ConsecutiveNbtRecord> records)
    {
        ArgumentNullException.ThrowIfNull(records);
        using var stream = new MemoryStream();
        foreach (var record in records)
        {
            var encoded = BedrockNbtCodec.Encode(record.Document, record.Encoding);
            stream.Write(encoded);
        }
        return stream.ToArray();
    }

    private static bool AllZero(ReadOnlySpan<byte> data)
    {
        foreach (var value in data) if (value != 0) return false;
        return true;
    }
}
