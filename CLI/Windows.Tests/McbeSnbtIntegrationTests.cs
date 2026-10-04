using System.Text;
using MCBEEditor.Core.Chunk;
using MCBEEditor.Core.Nbt;
using MCBEEditor.Core.World;

namespace MCBEEditor.Cli.Tests;

internal static class McbeSnbtIntegrationTests
{
    public static void Run(string root, string source)
    {
        var folder = Path.Combine(root, "MCBE-SNBT 原生结构");
        Directory.CreateDirectory(folder);
        var original = WorldFixture.Snapshot(source);
        var count = 0;

        string Invoke(string name, int expectedExit, params string[] commands)
        {
            var cache = Path.Combine(folder, "cache-" + name);
            var archive = Path.Combine(folder, name + ".mcworld");
            var args = new List<string> { "--world", source, "--cache-dir", cache, "--output", archive };
            foreach (var command in commands) { args.Add("--command"); args.Add(command); }
            using var output = new StringWriter();
            using var error = new StringWriter();
            var exit = MCBEEditor.Cli.Program.Run(args.ToArray(), output, error);
            Check(exit == expectedExit, $"{name}: exit {exit}, expected {expectedExit}\n{output}\n{error}");
            Check(WorldFixture.SameSnapshot(original, WorldFixture.Snapshot(source)), name + " changed the source world");
            if (expectedExit == 2)
                Check(!Directory.Exists(cache) && !File.Exists(archive), name + " created a working copy before failed preflight");
            count++;
            return archive;
        }

        // Omitting TXT dispatch or mapping its alias to binary must fail this real file/database roundtrip.
        var text = Path.Combine(folder, "house file.txt");
        var uppercase = Path.Combine(folder, "house uppercase.TXT");
        var alias = Path.Combine(folder, "house alias.txt");
        var exportedWorld = Invoke("export", 0,
            "structure save snbt:house overworld 0 64 0 1 64 1",
            $"structure export txt snbt:house --file \"{text}\"",
            $"structure export TXT snbt:house --file \"{uppercase}\"",
            $"structure export mcbe-snbt snbt:house --file \"{alias}\"");
        var exportedText = File.ReadAllBytes(text);
        Check(exportedText.SequenceEqual(File.ReadAllBytes(uppercase))
            && exportedText.SequenceEqual(File.ReadAllBytes(alias)), "TXT spelling/alias changed the output format");
        var decoded = StandaloneNbtFileCodec.Decode(exportedText, text);
        Check(decoded.OriginalWasSnbt && decoded.Documents.Count == 1, "structure export did not produce a single TXT root");
        using (var workspace = PortableWorldWorkspace.Create(Path.Combine(folder, "verify-export"), exportedWorld))
        {
            using var database = new WorldDocument(workspace.WorkingRootPath).OpenDatabase(readOnly: true);
            var stored = database.Get(Encoding.UTF8.GetBytes("structuretemplate_snbt:house"));
            Check(stored is not null && stored.SequenceEqual(StandaloneNbtFileCodec.Encode(decoded.Documents, NbtEncoding.LittleEndian)),
                "TXT export changed persisted structure bytes");
        }

        // Additional tags exercise preservation through SaveNew and reopening a real database.
        var structure = decoded.Documents[0];
        var tags = ((NbtCompoundValue)structure.Root).Tags.Concat(new NbtNamedTag[]
        {
            new("duplicate", new NbtIntValue(1)), new("duplicate", new NbtStringValue("second")),
            new("exactLong", new NbtLongValue(9007199254740993)),
            new("strings", new NbtListValue(NbtTagType.String, [new NbtStringValue(""), new NbtStringValue(" a,b\n\\\" ")])),
            new("nan", new NbtFloatValue(BitConverter.UInt32BitsToSingle(0xFFC12345)))
        }).ToArray();
        var augmented = new NbtDocument(structure.RootName, new NbtCompoundValue(tags));
        var augmentedText = McbeSnbtCodec.Encode([augmented]);
        var augmentedFile = Path.Combine(folder, "preserved.TXT");
        File.WriteAllBytes(augmentedFile, augmentedText);
        var reexport = Path.Combine(folder, "reexport.txt");
        var importedWorld = Invoke("import", 0,
            $"structure import snbt:imported --file \"{augmentedFile}\"",
            "structure load snbt:imported overworld 0 70 0",
            $"structure export txt snbt:imported --file \"{reexport}\"");
        Check(File.ReadAllBytes(reexport).SequenceEqual(augmentedText), "import/reexport lost duplicate tags, string values or NaN bits");
        using (var workspace = PortableWorldWorkspace.Create(Path.Combine(folder, "verify-import"), importedWorld))
        {
            using var database = new WorldDocument(workspace.WorkingRootPath).OpenDatabase(readOnly: true);
            Check(database.Get(Encoding.UTF8.GetBytes("structuretemplate_snbt:imported"))!
                .SequenceEqual(BedrockNbtCodec.Encode(augmented, NbtEncoding.LittleEndian)), "TXT import changed data after world export/reopen");
            Check(new BedrockBlockStore(database).ReadBlock(0, 1, 70, 1).Layers[0].Name == "minecraft:stone",
                "TXT imported structure could not be loaded into the world");
        }

        // TXT must inherit the existing whole-batch file protections before any earlier command executes.
        foreach (var (name, command) in new[]
        {
            ("existing-output", $"structure export txt snbt:house --file \"{text}\""),
            ("extension", $"structure export mcbe-snbt snbt:house --file \"{Path.Combine(folder, "wrong.json")}\""),
            ("missing-input", $"structure import snbt:house --file \"{Path.Combine(folder, "missing.txt")}\""),
            ("source-world", $"structure export TXT snbt:house --file \"{Path.Combine(source, "forbidden.txt")}\""),
            ("cache", $"structure export txt snbt:house --file \"{Path.Combine(folder, "cache-cache", "forbidden.txt")}\"")
        })
            Invoke(name, 2, "time set 222", command);
        Invoke("input-output-conflict", 2, "time set 222",
            $"structure import snbt:house --file \"{text}\"",
            $"structure export txt snbt:house --file \"{text}\" --overwrite");
        Check(File.ReadAllBytes(text).SequenceEqual(exportedText), "failed preflight overwrote a TXT input/output");

        // Failed TXT parsing and multiple roots cannot mutate a real structure record.
        using (var workspace = PortableWorldWorkspace.Create(Path.Combine(folder, "verify-rejection"), importedWorld))
        {
            var world = new WorldDocument(workspace.WorkingRootPath);
            var malformed = Path.Combine(folder, "invalid.txt");
            var multiple = Path.Combine(folder, "multiple.txt");
            File.WriteAllBytes(malformed, [0xFF, 0xFE]);
            File.WriteAllBytes(multiple, McbeSnbtCodec.Encode([augmented, augmented]));
            foreach (var invalid in new[] { malformed, multiple })
            {
                var before = Snapshot(world);
                Check(CliStructureFileCommand.TryParse($"structure import snbt:imported --file \"{invalid}\" --overwrite", out var request),
                    "TXT import parsing failed");
                var rejected = false;
                try { CliStructureFileCommand.Execute(request!, world); }
                catch (InvalidDataException) { rejected = true; }
                Check(rejected && Snapshot(world).SequenceEqual(before), "invalid TXT changed native database records");
                count++;
            }
        }
        Check(WorldFixture.SameSnapshot(original, WorldFixture.Snapshot(source)), "TXT tests changed source-world files");
        Console.WriteLine($"CLI MCBE-SNBT native tests passed: {count} cases; TXT aliases, byte-exact export/reopen, structure loading and preflight/invalid-input protection.");
    }

    private static string[] Snapshot(WorldDocument world)
    {
        using var database = world.OpenDatabase(readOnly: true);
        return database.Entries(includeValues: true)
            .Select(entry => Convert.ToHexString(entry.Key) + ":" + Convert.ToHexString(entry.Value!)).ToArray();
    }

    private static void Check(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException("CLI MCBE-SNBT regression: " + message);
    }
}
