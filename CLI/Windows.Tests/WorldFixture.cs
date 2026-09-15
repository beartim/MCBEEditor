using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;
using MCBEEditor.Core.Chunk;
using MCBEEditor.Core.LevelDB;
using MCBEEditor.Core.Nbt;
using MCBEEditor.Core.World;

namespace MCBEEditor.Cli.Tests;

internal static class WorldFixture
{
    public static string Create(string root, string nativeFixtureTool)
    {
        var source = Path.Combine(root, "源世界");
        Directory.CreateDirectory(source);
        var start = new ProcessStartInfo(Path.GetFullPath(nativeFixtureTool))
        {
            UseShellExecute = false, WorkingDirectory = source,
            RedirectStandardOutput = true, RedirectStandardError = true
        };
        // Keep the narrow C++ argv ASCII; the Unicode current directory is set by CreateProcess.
        start.ArgumentList.Add("db");
        using (var process = Process.Start(start) ?? throw new IOException("Cannot launch native fixture tool"))
        {
            if (!process.WaitForExit(30_000)) { process.Kill(entireProcessTree: true); throw new TimeoutException("Native fixture creation timed out"); }
            if (process.ExitCode != 0) throw new IOException("Native fixture failed: " + process.StandardError.ReadToEnd());
        }
        var world = new WorldDocument(source);
        world.WriteLevelDat(new LevelDatFile(8, new NbtDocument("", new NbtCompoundValue([
            new("LevelName", new NbtStringValue("CLI 原生测试")),
            new("StorageVersion", new NbtIntValue(8)),
            new("RandomSeed", new NbtLongValue(1234567)),
            new("Time", new NbtLongValue(100)),
            new("SpawnX", new NbtIntValue(0)), new("SpawnY", new NbtIntValue(65)), new("SpawnZ", new NbtIntValue(0)),
            new("GameType", new NbtIntValue(0))
        ]))));
        using (var database = world.OpenDatabase(readOnly: false))
        {
            SeedFloor(database, 0, 4);
            SeedFloor(database, 2, 0);
            database.Put(Encoding.UTF8.GetBytes("~local_player"), BedrockNbtCodec.Encode(Player(1001), NbtEncoding.LittleEndian));
            database.Put(Encoding.UTF8.GetBytes("player_server_2002"), BedrockNbtCodec.Encode(Player(2002), NbtEncoding.LittleEndian));
            database.Put(Encoding.UTF8.GetBytes("cli_unknown_record"), [0, 128, 255, 1]);
        }
        File.WriteAllBytes(Path.Combine(source, "untouched.bin"), [0, 1, 2, 127, 128, 255]);
        Directory.CreateDirectory(Path.Combine(source, ".mcbeeditor"));
        File.WriteAllText(Path.Combine(source, ".mcbeeditor", "private.txt"), "editor-only");
        return source;
    }

    private static void SeedFloor(IWorldDatabase database, int dimension, sbyte y)
    {
        var position = new ChunkPosition(0, 0, dimension);
        var indices = new ushort[4096];
        for (var x = 0; x < 16; x++) for (var z = 0; z < 16; z++) indices[(x << 8) | (z << 4)] = 1;
        var air = BedrockBlockState.EditableAir(17825808);
        var stone = new BedrockBlockStorageSpec("minecraft:stone", []).ModernState(17825808);
        database.Put(BedrockDbKey.SubChunk(0, 0, dimension, y),
            new BedrockSubChunk(8, y, [new SubChunkStorage(1, [air, stone], indices)], []).EncodePersistent());
        database.Put(new BedrockDbKey(position, ChunkRecordType.LegacyVersion, null).Encode(), [19]);
        database.Put(new BedrockDbKey(position, ChunkRecordType.FinalizedState, null).Encode(), [2, 0, 0, 0]);
        database.Put(new BedrockDbKey(position, ChunkRecordType.Data2D, null).Encode(), new byte[768]);
    }

    private static NbtDocument Player(long id)
    {
        var inventory = Enumerable.Range(0, 36).Select(slot => (NbtValue)new NbtCompoundValue([
            new("Name", new NbtStringValue("")), new("Count", new NbtByteValue(0)), new("Slot", new NbtByteValue((sbyte)slot))
        ])).ToArray();
        return new NbtDocument("", new NbtCompoundValue([
            new("PlayerName", new NbtStringValue("CLI Player " + id)), new("UniqueID", new NbtLongValue(id)),
            new("DimensionId", new NbtIntValue(0)), new("PlayerGameMode", new NbtIntValue(0)),
            new("Pos", new NbtListValue(NbtTagType.Float, [new NbtFloatValue(0.5f), new NbtFloatValue(65), new NbtFloatValue(0.5f)])),
            new("PlayerLevel", new NbtIntValue(3)), new("PlayerLevelProgress", new NbtFloatValue(0.5f)),
            new("Inventory", new NbtListValue(NbtTagType.Compound, inventory)),
            new("Attributes", new NbtListValue(NbtTagType.Compound, [new NbtCompoundValue([
                new("Name", new NbtStringValue("minecraft:health")), new("Current", new NbtFloatValue(20))
            ])]))
        ]));
    }

    public static IReadOnlyDictionary<string, string> Snapshot(string root)
        => Directory.EnumerateFiles(root, "*", SearchOption.AllDirectories).ToDictionary(
            file => Path.GetRelativePath(root, file), file => Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(file))), StringComparer.Ordinal);

    public static bool SameSnapshot(IReadOnlyDictionary<string, string> left, IReadOnlyDictionary<string, string> right)
        => left.Count == right.Count && left.All(pair => right.TryGetValue(pair.Key, out var digest) && digest == pair.Value);
}
