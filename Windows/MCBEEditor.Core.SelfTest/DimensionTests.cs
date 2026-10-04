using System.Text;
using MCBEEditor.Core.Chunk;
using MCBEEditor.Core.Nbt;
using MCBEEditor.Core.World;

static class DimensionTests
{
    public static void Run()
    {
        using var db = new SelfTestWorldDatabase();
        db.Put(Encoding.UTF8.GetBytes("DimensionNameIdTable"), BedrockNbtCodec.Encode(new NbtDocument("",
            new NbtCompoundValue([new("entries", new NbtCompoundValue([
                new("bear:wzn", new NbtIntValue(1002)), new("wzn:bear", new NbtIntValue(1000)),
                new("wzn:cat", new NbtIntValue(1001))]))]))));
        db.Put(Encoding.UTF8.GetBytes("Overworld"), [10, 0, 0, 0]);
        db.Put(BedrockDbKey.SubChunk(2, -3, 1001, 0), []);
        var before = db.Entries(includeValues: true).Select(x => Convert.ToHexString(x.Key) + Convert.ToHexString(x.Value!)).ToArray();
        var rows = new DimensionStore(db).Snapshot();
        Check(rows.Select(x => x.Id).SequenceEqual(new[] { 0, 1000, 1001, 1002 }), "registered empty dimensions must be listed without inventing Nether/End");
        Check(rows.Single(x => x.Id == 1000).Name == "wzn:bear" && rows.Single(x => x.Id == 1000).ChunkCount == 0, "empty registered dimension");
        Check(rows.Single(x => x.Id == 1001).ChunkCount == 1, "custom chunk count");
        var result = new DimensionCommandStore(db).Execute(DimensionCommandParser.Parse("dimension query"));
        Check(!result.ChangedWorld && result.OutputLines.Any(x => x.Text.StartsWith("wzn:cat=1001", StringComparison.Ordinal)), "query output");
        Check(before.SequenceEqual(db.Entries(includeValues: true).Select(x => Convert.ToHexString(x.Key) + Convert.ToHexString(x.Value!))), "query must not write");
        foreach (var id in new[] { 43, 44, 47, 118, -1, int.MinValue, int.MaxValue })
        {
            var encoded = BedrockDbKey.SubChunk(-2, 3, id, -5);
            Check(BedrockDbKey.TryParse(encoded, out var key) && key.Position == new ChunkPosition(-2, 3, id)
                && key.RecordType == ChunkRecordType.SubChunk && key.SubChunkIndex == -5, "dimension/tag byte collision " + id);
        }
        Check(!BedrockDbKey.TryParse(new byte[12], out _), "invalid prefix length");
        foreach (var invalid in new[] { "dimension", "dimension query extra", "dimension add bear 2147483648" })
        {
            try { DimensionCommandParser.Parse(invalid); throw new Exception("invalid command accepted"); }
            catch (InvalidDataException) { }
        }
        Console.WriteLine("Dimension query tests passed.");
    }
    static void Check(bool ok, string message) { if (!ok) throw new InvalidOperationException(message); }
}
