using System.Buffers.Binary;
using System.Text;
using MCBEEditor.Core.Nbt;
using MCBEEditor.Core.World;

internal static class OverallAuditRegressionTests
{
    public static void Run(string scenario)
    {
        if (scenario is "collections" or "all") TruncatedCollections();
        if (scenario is "volume" or "all") OverflowingStructureVolume();
        if (scenario is "dimensions" or "all") DuplicateDimensionNames();
        Console.WriteLine("Overall audit regressions passed: " + scenario);
    }

    private static void Check(bool condition, string message)
    {
        if (!condition) throw new Exception("Overall audit: " + message);
    }

    private static void TruncatedCollections()
    {
        foreach (var encoding in Enum.GetValues<NbtEncoding>())
        foreach (var root in new NbtValue[] {
            new NbtListValue(NbtTagType.Int, []), new NbtIntArrayValue([]), new NbtLongArrayValue([]),
            new NbtListValue(NbtTagType.String, []), new NbtListValue(NbtTagType.List, []),
            new NbtListValue(NbtTagType.Compound, []) })
        {
            var empty = BedrockNbtCodec.Encode(new NbtDocument("", root), encoding);
            var length = new List<byte>();
            const int count = 1_000_000;
            if (encoding == NbtEncoding.LittleEndianVarInt)
            {
                uint raw = count * 2;
                do { length.Add((byte)((raw & 127) | (raw > 127 ? 128u : 0))); raw >>= 7; } while (raw != 0);
            }
            else
            {
                var bytes = new byte[4];
                if (encoding == NbtEncoding.BigEndian) BinaryPrimitives.WriteInt32BigEndian(bytes, count);
                else BinaryPrimitives.WriteInt32LittleEndian(bytes, count);
                length.AddRange(bytes);
            }
            var prefix = empty[..^(encoding == NbtEncoding.LittleEndianVarInt ? 1 : 4)];
            var truncated = prefix.Concat(length).ToArray();
            var before = GC.GetAllocatedBytesForCurrentThread();
            var rejected = false;
            try { _ = BedrockNbtCodec.Decode(truncated, encoding); }
            catch (InvalidDataException) { rejected = true; }
            var allocated = GC.GetAllocatedBytesForCurrentThread() - before;
            Check(rejected && allocated < 1_048_576,
                $"truncated {root.Type}/{encoding} allocated {allocated} bytes before rejection");
            Check(BedrockNbtCodec.Encode(BedrockNbtCodec.Decode(empty, encoding), encoding).SequenceEqual(empty),
                "valid empty collection changed");
        }
    }

    private static void OverflowingStructureVolume()
    {
        var text = "'List''Int'\"size\"=\"1073741824,1073741824,16\",'List''Compound'\"palette\"=\"{'String'\"Name\"=\"minecraft:stone\"}\",'List''Compound'\"blocks\"=\"\"";
        var document = McbeSnbtCodec.Decode(Encoding.UTF8.GetBytes(text)).Single();
        var before = BedrockNbtCodec.Encode(document);
        var rejected = false;
        try { _ = JavaStructureConverter.ConvertIfNeeded(document); }
        catch (NotSupportedException) { rejected = true; }
        Check(rejected && before.SequenceEqual(BedrockNbtCodec.Encode(document)),
            "structure volume overflow was accepted or altered the document");
    }

    private static void DuplicateDimensionNames()
    {
        using var database = new SelfTestWorldDatabase();
        var registry = new NbtDocument("", new NbtCompoundValue([
            new NbtNamedTag("entries", new NbtCompoundValue([
                new NbtNamedTag("bear", new NbtIntValue(3)),
                new NbtNamedTag("bear", new NbtIntValue(4))]))]));
        var bytes = BedrockNbtCodec.Encode(registry);
        database.Put(DimensionStore.RegistryKey, bytes);
        var batches = database.ApplyBatchCount;
        var rejected = false;
        try { _ = new DimensionStore(database).Snapshot(); }
        catch (InvalidDataException) { rejected = true; }
        Check(rejected && batches == database.ApplyBatchCount && database.Get(DimensionStore.RegistryKey)!.SequenceEqual(bytes),
            "duplicate dimension names were accepted or wrote to storage");
    }
}
