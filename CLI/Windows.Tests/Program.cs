using System.Globalization;
using System.IO.Compression;
using System.Text;
using MCBEEditor.Core.Chunk;
using MCBEEditor.Core.Entity;
using MCBEEditor.Core.Nbt;
using MCBEEditor.Core.World;
using CliApp = MCBEEditor.Cli.Program;

namespace MCBEEditor.Cli.Tests;

internal static class Program
{
    private static int _runs;
    private static void Check(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException("CLI native integration: " + message);
    }

    private static int Main(string[] args)
    {
        if (args.Length != 1 || !File.Exists(args[0]))
        {
            Console.Error.WriteLine("Pass the built mcbe_cli_create_test_db executable; these tests do not skip missing native dependencies.");
            return 2;
        }
        var root = Path.Combine(Path.GetTempPath(), "mcbe-cli-native-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            RunTests(root, args[0]);
            Console.WriteLine($"PASS Windows CLI native integration: {_runs} invocation cases; real Mojang LevelDB, source integrity, export/reopen and failure recovery.");
            return 0;
        }
        catch (Exception exception) { Console.Error.WriteLine(exception); return 1; }
        finally
        {
            foreach (var file in Directory.EnumerateFiles(root, "*", SearchOption.AllDirectories))
                File.SetAttributes(file, File.GetAttributes(file) & ~FileAttributes.ReadOnly);
            Directory.Delete(root, recursive: true);
        }
    }

    private static void RunTests(string root, string fixtureTool)
    {
        var source = WorldFixture.Create(root, fixtureTool);
        var original = WorldFixture.Snapshot(source);

        var inheritedPortableRoot = Environment.GetEnvironmentVariable("MCBEEDITOR_PORTABLE_ROOT");
        var inheritedPortableCache = Environment.GetEnvironmentVariable("MCBEEDITOR_CACHE_ROOT");
        var portableRoot = Path.Combine(root, "portable root");
        var portableCache = Path.Combine(portableRoot, "custom cache");
        try
        {
            Environment.SetEnvironmentVariable("MCBEEDITOR_PORTABLE_ROOT", portableRoot);
            Environment.SetEnvironmentVariable("MCBEEDITOR_CACHE_ROOT", portableCache);
            Check(MCBEEditor.Cli.CliPortablePaths.RootDirectory == Path.GetFullPath(portableRoot), "portable root environment was ignored");
            Check(MCBEEditor.Cli.CliPortablePaths.CommandsDirectory == Path.Combine(Path.GetFullPath(portableRoot), "Commands"), "portable Commands path drifted");
            Check(MCBEEditor.Cli.CliPortablePaths.WorldCacheDirectory == Path.Combine(Path.GetFullPath(portableCache), "Worlds"), "portable world cache environment was ignored");
            var portableOptions = MCBEEditor.Cli.CliRunOptions.Parse(["--world", source, "--command", "weather query"]);
            Check(portableOptions.CacheDirectory == MCBEEditor.Cli.CliPortablePaths.WorldCacheDirectory, "default run options did not use portable world cache");
            _runs++;
        }
        finally
        {
            Environment.SetEnvironmentVariable("MCBEEDITOR_PORTABLE_ROOT", inheritedPortableRoot);
            Environment.SetEnvironmentVariable("MCBEEDITOR_CACHE_ROOT", inheritedPortableCache);
        }
        var invalidScript = Path.Combine(root, "语法错误.txt");
        File.WriteAllText(invalidScript, "time set 222\r\n\r\nweather nope\r\nunknown-command\r\n", new UTF8Encoding(true));

        RunResult Invoke(string name, int expected, string[] options, string? input = null,
            Action<string?>? onOutput = null, CancellationToken token = default, Action<string?>? onError = null)
        {
            var cache = Path.Combine(root, "Cache", name);
            var argv = new[] { "--world", input ?? source, "--cache-dir", cache }.Concat(options).ToArray();
            using var output = new ObservedWriter(onOutput);
            using var error = new ObservedWriter(onError);
            var exit = CliApp.Run(argv, output, error, token);
            Check(exit == expected, $"{name}: exit={exit}, expected={expected}\n{output}\n{error}");
            Check(WorldFixture.SameSnapshot(original, WorldFixture.Snapshot(source)), name + " changed the input world");
            _runs++;
            return new RunResult(output.ToString(), error.ToString(), cache);
        }

        RunResult InvokeStandalone(string name, int expected, string[] argv)
        {
            using var output = new ObservedWriter();
            using var error = new ObservedWriter();
            var exit = CliApp.Run(argv, output, error);
            Check(exit == expected, $"{name}: exit={exit}, expected={expected}\n{output}\n{error}");
            Check(WorldFixture.SameSnapshot(original, WorldFixture.Snapshot(source)), name + " changed the input world");
            _runs++;
            return new RunResult(output.ToString(), error.ToString(), string.Empty);
        }

        var syntax = Invoke("syntax", 2, ["--script", invalidScript, "--output", Path.Combine(root, "syntax.mcworld")]);
        Check(!Directory.Exists(syntax.Cache), "syntax failure created a working copy");
        Check(syntax.Error.Contains("第 3 行") && syntax.Error.Contains("第 4 行"), "physical syntax line numbers");
        var required = Invoke("required-output", 2, ["--command", "time set 222"]);
        Check(!Directory.Exists(required.Cache), "missing output started work");
        var unsupported = Invoke("structure-io", 2, ["--command", "time set 222", "--command", "structure import test:house", "--output", Path.Combine(root, "unsupported.mcworld")]);
        Check(!Directory.Exists(unsupported.Cache), "unsupported file command ran the preceding command");

        var query = Invoke("queries", 0, ["--command", "help weather", "--command", "info", "--command", "weather query", "--command", "time query daytime", "--command", "chunk query", "--command", "structure query"]);
        Check(query.Output.Contains("doWeatherCycle=1") && query.Output.Contains("SubChunk v8"), "default weather and chunk version query output");
        Check(query.Output.Contains("IsSlimeChunk=") && query.Output.Contains("Ticking="), "chunk query flags");
        Check(Directory.GetDirectories(query.Cache).Length == 0, "successful queries leaked a session");

        var script = Path.Combine(root, "命令 file.txt");
        var commands = new[]
        {
            "daylock 1", "time set 12345", "time query gametime", "weather thunder 12000 0.5 0",
            "tickingarea add circle overworld 0 0 0 home 1", "tickingarea list ALL",
            "setworldspawn 0 70 0", "spawnpoint @s overworld 0 70 0", "clearspawnpoint @s",
            "experience level @s 30", "experience percent @s 0.5", "experience query @s",
            "give @s Auto minecraft:diamond 3 NULL", "effect give @s strength 1000 255", "effect clear @s ALL", "clear @s",
            "summon minecraft:pig overworld 0.5 65 0.5 default", "kill minecraft:pig 0", "kick @a",
            "fill overworld 0 65 0 3 65 0 minecraft:stone NULL", "setblock overworld 1 65 0 minecraft:dirt NULL",
            "clone overworld 0 65 0 2 65 0 overworld 1 65 0", "fillbiome overworld 0 0 0 15 127 15 9",
            "setblock the_end 35 200 5 minecraft:diamond_block NULL", "storage set the_end 3 220 5 254 minecraft:stone NULL",
            "storage query the_end 3 220 5", "storage set the_end 3 240 5 2 minecraft:stone NULL",
            "storage delete the_end 3 240 5 2", "storage clear the_end 3 240 5 0",
            "structure save cli:house overworld 0 65 0 3 65 0", "structure query", "structure load cli:house overworld 0 70 0",
            "structure delete cli:house", "chunk empty nether 1 1", "chunk regenerate nether 1 1",
            "spread @s", "teleport @s overworld 2.0 64 3.0", "getblock the_end 35 200 5", "chunk query"
        };
        File.WriteAllText(script, "\uFEFF" + string.Join("\r\n", commands) + "\r\n", new UTF8Encoding(false));
        var scriptBytes = File.ReadAllBytes(script);
        var exported = Path.Combine(root, "edited.mcworld");
        var edited = Invoke("all-families", 0, ["--script", script, "--output", exported]);
        Check(File.Exists(exported) && Directory.GetDirectories(edited.Cache).Length == 0, "successful edit/export cleanup");
        Check(File.ReadAllBytes(script).SequenceEqual(scriptBytes), "script was changed");

        var structureFolder = Path.Combine(root, "structure files");
        Directory.CreateDirectory(structureFolder);
        var structureFile = Path.Combine(structureFolder, "house file.nbt");
        var structureWorld = Path.Combine(root, "structure-export.mcworld");
        Invoke("structure-file-export", 0, [
            "--command", "structure save cli:file overworld 0 65 0 3 65 0",
            "--command", $"structure export nbt cli:file --file \"{structureFile}\"",
            "--output", structureWorld]);
        Check(File.Exists(structureFile), "structure export did not create path-with-spaces file");

        var convertHelp = InvokeStandalone("convert-help", 0, ["--help", "convert"]);
        Check(convertHelp.Output.Contains("little-varint") && convertHelp.Output.Contains("mcstructure"), "convert help is incomplete");
        var littleFile = Path.Combine(structureFolder, "house little.nbt");
        var varIntFile = Path.Combine(structureFolder, "house varint.nbt");
        var jsonFile = Path.Combine(structureFolder, "house.json");
        var mcstructureFile = Path.Combine(structureFolder, "house.mcstructure");
        InvokeStandalone("convert-little", 0, ["--convert", structureFile, "--to", "little-endian", "--output", littleFile]);
        Check(StandaloneNbtFileCodec.Decode(File.ReadAllBytes(littleFile), littleFile).OriginalEncoding == NbtEncoding.LittleEndian, "little-endian conversion encoding");
        InvokeStandalone("convert-varint", 0, ["--convert", littleFile, "--to", "little-varint", "--output", varIntFile]);
        Check(StandaloneNbtFileCodec.Decode(File.ReadAllBytes(varIntFile), varIntFile).OriginalEncoding == NbtEncoding.LittleEndianVarInt, "little-varint conversion encoding");
        InvokeStandalone("convert-json", 0, ["--convert", varIntFile, "--to", "json", "--output", jsonFile]);
        Check(StandaloneNbtFileCodec.Decode(File.ReadAllBytes(jsonFile), jsonFile).OriginalWasJson, "JSON conversion format");
        InvokeStandalone("convert-mcstructure", 0, ["--convert", structureFile, "--to", "mcstructure", "--output", mcstructureFile]);
        Check(StandaloneNbtFileCodec.Decode(File.ReadAllBytes(mcstructureFile), mcstructureFile).OriginalEncoding == NbtEncoding.LittleEndian, "mcstructure conversion encoding");
        InvokeStandalone("convert-no-overwrite", 3, ["--convert", structureFile, "--to", "json", "--output", jsonFile]);
        InvokeStandalone("convert-overwrite", 0, ["--convert", structureFile, "--to", "json", "--output", jsonFile, "--overwrite"]);
        var rootDocument = StandaloneNbtFileCodec.Decode(File.ReadAllBytes(structureFile), structureFile).Documents.Single();
        var consecutiveFile = Path.Combine(structureFolder, "two roots.nbt");
        File.WriteAllBytes(consecutiveFile, StandaloneNbtFileCodec.Encode([rootDocument, rootDocument], NbtEncoding.LittleEndian));
        var consecutiveJson = Path.Combine(structureFolder, "two roots.json");
        InvokeStandalone("convert-consecutive-json", 0, ["--convert", consecutiveFile, "--to", "json", "--output", consecutiveJson]);
        Check(StandaloneNbtFileCodec.Decode(File.ReadAllBytes(consecutiveJson), consecutiveJson).Documents.Count == 2, "consecutive NBT conversion lost roots");
        InvokeStandalone("convert-consecutive-mcstructure", 3, ["--convert", consecutiveFile, "--to", "mcstructure", "--output", Path.Combine(structureFolder, "invalid.mcstructure")]);
        var importedWorld = Path.Combine(root, "structure-import.mcworld");
        Invoke("structure-file-import", 0, [
            "--command", $"structure import cli:imported --file \"{structureFile}\"",
            "--output", importedWorld]);
        using (var importedWorkspace = PortableWorldWorkspace.Create(Path.Combine(root, "VerifyImport"), importedWorld))
        {
            var importedDocument = new WorldDocument(importedWorkspace.WorkingRootPath);
            using var importedDb = importedDocument.OpenDatabase(readOnly: true);
            Check(new StructureNbtStore(importedDb).Contains("cli:imported"), "structure import was not persisted");
        }
        var noName = Invoke("structure-file-missing-name", 2, [
            "--command", "time set 222",
            "--command", $"structure import --file \"{structureFile}\"",
            "--output", Path.Combine(root, "missing-name.mcworld")]);
        Check(!Directory.Exists(noName.Cache), "missing structure name did not fail during whole-batch preflight");
        using (var archive = ZipFile.OpenRead(exported))
        {
            Check(archive.GetEntry("level.dat") is not null && archive.GetEntry("untouched.bin") is not null, "world archive entries");
            Check(archive.GetEntry("db/LOCK") is null && !archive.Entries.Any(entry => entry.FullName.StartsWith(".mcbeeditor/")), "editor private data was exported");
        }
        using (var verification = PortableWorldWorkspace.Create(Path.Combine(root, "Verify"), exported))
        {
            var document = new WorldDocument(verification.WorkingRootPath);
            Check(WorldTimeStore.Read(document).Time == 12345 && !WorldTimeStore.Read(document).AutomaticProgression, "time and daylock persistence");
            Check(WorldWeatherStore.Read(document).LightningLevel == 0.5f && !WorldWeatherStore.Read(document).AutomaticChange, "weather persistence");
            using var database = document.OpenDatabase(readOnly: true);
            var blocks = new BedrockBlockStore(database);
            Check(blocks.ReadBlock(0, 2, 65, 0).Layers[0].Name == "minecraft:dirt", "overlapping clone reused modified source data");
            Check(blocks.ReadBlock(0, 0, 70, 0).Layers[0].Name == "minecraft:stone", "structure load was not persisted");
            Check(blocks.ReadBlock(2, 35, 200, 5).Layers[0].Name == "minecraft:diamond_block", "new End chunk/high slice was not persisted");
            var raw = database.Get(BedrockDbKey.SubChunk(0, 0, 2, 13))!;
            var subchunk = BedrockSubChunk.Decode(raw, 13);
            Check(subchunk.Version == 8 && subchunk.Storages.Count == 255 && subchunk.Storages.All(storage => storage.BitsPerBlock >= 1), "v8 255-storage compatibility");
            Check(blocks.ReadBlock(2, 3, 220, 5).Layers[254].Name == "minecraft:stone", "storage254 was lost");
            Check(database.Get(new BedrockDbKey(new ChunkPosition(2, 0, 2), ChunkRecordType.FinalizedState, null).Encode())!.SequenceEqual(new byte[] { 2, 0, 0, 0 }), "new chunk finalization metadata");
            Check(database.Get(Encoding.UTF8.GetBytes("cli_unknown_record"))!.SequenceEqual(new byte[] { 0, 128, 255, 1 }), "unknown record changed");
            var players = new PlayerNbtStore(database);
            var local = players.Records().Single(player => player.IsLocal);
            Check(Math.Abs(players.CurrentPosition(local)!.Y - 65.62) < 0.001, "integer player Y must add 1.62");
            Check(players.Records().Count == 1 && TargetingCommandStore.ReadExperience(local.Document).Level == 30, "player kick or experience persistence");
        }
        var interactiveArchive = Path.Combine(root, "interactive.mcworld");
        File.Copy(exported, interactiveArchive);
        using (var interactiveOutput = new StringWriter())
        using (var interactiveError = new StringWriter())
        using (var interactiveInput = new StringReader($":open \"{interactiveArchive}\" --in-place\ntime set 1111\n:save\ntime set 2222\n:save\n:quit\n"))
        {
            var interactiveExit = CliApp.Run(["--interactive"], interactiveOutput, interactiveError, default, interactiveInput);
            Check(interactiveExit == 0, "interactive session failed: " + interactiveError);
        }
        using (var interactiveVerify = PortableWorldWorkspace.Create(Path.Combine(root, "VerifyInteractive"), interactiveArchive))
            Check(WorldTimeStore.Read(new WorldDocument(interactiveVerify.WorkingRootPath)).Time == 2222, "second interactive in-place save failed or source stamp was not refreshed");

        // Stage04c: injected/redirected interactive input must remain plain text while meta history/clear stay usable.
        using (var plainOutput = new StringWriter())
        using (var plainError = new StringWriter())
        using (var plainInput = new StringReader(":history\n:clear\n:quit\n"))
        {
            var plainExit = CliApp.Run(["--interactive"], plainOutput, plainError, default, plainInput, terminalFeatures: false);
            Check(plainExit == 0 && plainOutput.ToString().Contains(":history") && !plainOutput.ToString().Contains("\u001b"),
                "redirected interactive history/clear emitted ANSI or failed");
            Check(plainError.ToString().Length == 0, "redirected interactive history/clear wrote unexpected stderr");
        }

        // Stage04d: ReadMe is fixed metadata, while Command.txt is always user-owned.
        var commandsDirectory = Path.Combine(root, "Commands");
        Directory.CreateDirectory(commandsDirectory);
        var commandFile = CliSharedCommandStore.CommandFilePath(commandsDirectory);
        File.WriteAllText(commandFile, "time set 3333\nstructure load cli:missing overworld 0 64 0\ntime set 4444\n", new UTF8Encoding(false));
        var commandFileBeforePrepare = File.ReadAllBytes(commandFile);
        CliSharedCommandStore.Prepare(commandsDirectory);
        Check(File.ReadAllBytes(commandFile).SequenceEqual(commandFileBeforePrepare), "preparing Commands changed Command.txt");
        var commandReadMe = File.ReadAllText(CliSharedCommandStore.ReadMeFilePath(commandsDirectory));
        Check(commandReadMe.Contains("--script") && commandReadMe.Contains(":clear") && commandReadMe.Contains("structure export"),
            "fixed Commands ReadMe is incomplete");

        // A runtime error in Command.txt must not stop later commands; saving keeps successful edits but the session exits failed.
        var commandBatchArchive = Path.Combine(root, "command-batch.mcworld");
        File.Copy(exported, commandBatchArchive);
        using (var batchOutput = new StringWriter())
        using (var batchError = new StringWriter())
        using (var batchInput = new StringReader($":open \"{commandBatchArchive}\" --in-place\ny\n:save\n:quit\n"))
        {
            var batchExit = CliApp.Run(["--interactive"], batchOutput, batchError, default, batchInput,
                terminalFeatures: false, commandsDirectory: commandsDirectory);
            Check(batchExit == 1, "Command.txt runtime failure did not propagate final exit status");
            Check(batchOutput.ToString().Contains("Command.txt 语法检查通过") && batchOutput.ToString().Contains("time set 完成"),
                "Command.txt runtime batch did not continue successful commands");
            Check(batchError.ToString().Contains("第 2 行执行失败") && batchError.ToString().Contains("其余命令已继续执行"),
                "Command.txt runtime failure summary missing");
        }
        using (var batchVerify = PortableWorldWorkspace.Create(Path.Combine(root, "VerifyCommandBatch"), commandBatchArchive))
            Check(WorldTimeStore.Read(new WorldDocument(batchVerify.WorkingRootPath)).Time == 4444,
                "Command.txt runtime failure stopped later command or partial save");

        // A syntax error rejects the whole Command.txt before any command changes the world.
        File.WriteAllText(commandFile, "time set 5555\nweather nope\ntime set 6666\n", new UTF8Encoding(false));
        var commandPreflightArchive = Path.Combine(root, "command-preflight.mcworld");
        File.Copy(exported, commandPreflightArchive);
        using (var preflightOutput = new StringWriter())
        using (var preflightError = new StringWriter())
        using (var preflightInput = new StringReader($":open \"{commandPreflightArchive}\" --in-place\ny\n:quit\n"))
        {
            var preflightExit = CliApp.Run(["--interactive"], preflightOutput, preflightError, default, preflightInput,
                terminalFeatures: false, commandsDirectory: commandsDirectory);
            Check(preflightExit == 2, "Command.txt preflight failure did not propagate exit status");
            Check(preflightError.ToString().Contains("第 2 行") && preflightError.ToString().Contains("本次没有执行任何命令"),
                "Command.txt whole-batch preflight diagnostics missing");
        }
        using (var preflightVerify = PortableWorldWorkspace.Create(Path.Combine(root, "VerifyCommandPreflight"), commandPreflightArchive))
            Check(WorldTimeStore.Read(new WorldDocument(preflightVerify.WorkingRootPath)).Time == 12345,
                "Command.txt syntax failure executed an earlier command");

        var originalArchive = File.ReadAllBytes(exported);
        Invoke("archive-input", 0, ["--command", "weather query"], exported);
        Check(File.ReadAllBytes(exported).SequenceEqual(originalArchive), "archive source changed when opening");

        var preserved = Path.Combine(root, "existing.mcworld");
        File.WriteAllText(preserved, "existing-content");
        Invoke("no-overwrite", 2, ["--command", "weather query", "--output", preserved]);
        Check(File.ReadAllText(preserved) == "existing-content", "no-overwrite clobbered destination");
        Invoke("explicit-overwrite", 0, ["--command", "weather query", "--output", preserved, "--overwrite"]);
        using (var archive = ZipFile.OpenRead(preserved)) Check(archive.GetEntry("level.dat") is not null, "explicit overwrite failed");
        var lockedOutputBytes = File.ReadAllBytes(preserved);
        using (var lockedOutput = new FileStream(preserved, FileMode.Open, FileAccess.Read, FileShare.Read))
        {
            var blocked = Invoke("save-as-publish-blocked", 3, ["--command", "time set 4321", "--output", preserved, "--overwrite"]);
            Check(File.ReadAllBytes(preserved).SequenceEqual(lockedOutputBytes), "failed save-as replaced the locked output");
            var recovery = Path.Combine(Directory.GetDirectories(blocked.Cache).Single(), "World");
            Check(WorldTimeStore.Read(new WorldDocument(recovery)).Time == 4321 && blocked.Error.Contains("工作副本已保留"), "failed save-as lost edits or recovery path");
        }
        Invoke("source-archive-output", 2, ["--command", "weather query", "--output", exported, "--overwrite"], exported);
        Check(File.ReadAllBytes(exported).SequenceEqual(originalArchive), "input archive overwritten");
        Invoke("source-folder-output", 2, ["--command", "weather query", "--output", Path.Combine(source, "bad.mcworld")]);

        using (var output = new StringWriter())
        using (var error = new StringWriter())
        {
            var nested = Path.Combine(source, "new-cache");
            var exit = CliApp.Run(["--world", source, "--cache-dir", nested, "--command", "weather query"], output, error);
            Check(exit == 2 && !Directory.Exists(nested), "nested cache modified the source before being rejected");
            try { using var unexpected = PortableWorldWorkspace.Create(nested, source); throw new Exception("nested core workspace was accepted"); }
            catch (InvalidOperationException) { }
            Check(!Directory.Exists(nested), "core workspace created nested cache before rejecting it");
        }

        var runtimeOutput = Path.Combine(root, "runtime-errors.mcworld");
        var runtime = Invoke("runtime-errors", 1, ["--command", "structure load cli:missing overworld 0 64 0", "--command", "weather rain 200 0.25 1", "--output", runtimeOutput]);
        Check(runtime.Error.Contains("第 1 行执行失败") && File.Exists(runtimeOutput), "runtime error/continue/export behavior");
        Check(Directory.GetDirectories(runtime.Cache).Length == 1 && runtime.Error.Contains("工作副本已保留"), "runtime error discarded recovery copy");
        using (var verification = PortableWorldWorkspace.Create(Path.Combine(root, "Verify"), runtimeOutput))
            Check(WorldWeatherStore.Read(new WorldDocument(verification.WorkingRootPath)).RainLevel == 0.25f, "runtime failure stopped subsequent command");

        var racedOutput = Path.Combine(root, "output-race.mcworld");
        var race = Invoke("export-race", 3, ["--command", "weather rain 300 0.75 0", "--output", racedOutput], onOutput: line =>
        {
            if (line?.StartsWith("weather 完成", StringComparison.Ordinal) == true) File.WriteAllText(racedOutput, "concurrent-content");
        });
        Check(File.ReadAllText(racedOutput) == "concurrent-content", "output race overwrote an unapproved file");
        var recoveryRoot = Path.Combine(Directory.GetDirectories(race.Cache).Single(), "World");
        Check(WorldWeatherStore.Read(new WorldDocument(recoveryRoot)).RainLevel == 0.75f, "export failure lost edits");
        Invoke("recover-export", 0, ["--command", "weather query", "--output", Path.Combine(root, "recovered.mcworld")], recoveryRoot);

        var kept = Invoke("keep", 0, ["--command", "weather query", "--keep-work"]);
        Check(Directory.GetDirectories(kept.Cache).Length == 1 && kept.Error.Contains("工作副本已保留"), "keep-work ignored");
        using (var cancellation = new CancellationTokenSource())
        {
            var cancelled = Invoke("cancel", 130, ["--command", "time set 333", "--command", "time set 444", "--output", Path.Combine(root, "cancelled.mcworld")], onOutput: line =>
            {
                if (line == "> time set 333") cancellation.Cancel();
            }, token: cancellation.Token);
            var recovery = Path.Combine(Directory.GetDirectories(cancelled.Cache).Single(), "World");
            Check(WorldTimeStore.Read(new WorldDocument(recovery)).Time == 333 && !File.Exists(Path.Combine(root, "cancelled.mcworld")), "cancellation boundary or recovery");
        }
        var levelDat = Path.Combine(source, "level.dat");
        File.SetAttributes(levelDat, File.GetAttributes(levelDat) | FileAttributes.ReadOnly);
        try
        {
            Invoke("read-only-source", 0, ["--command", "time set 555", "--output", Path.Combine(root, "readonly.mcworld")]);
            Check((File.GetAttributes(levelDat) & FileAttributes.ReadOnly) != 0, "input read-only attribute changed");
        }
        finally { File.SetAttributes(levelDat, File.GetAttributes(levelDat) & ~FileAttributes.ReadOnly); }

        var inheritedCache = Environment.GetEnvironmentVariable("MCBEEDITOR_CACHE_ROOT");
        var disallowedTemporary = Path.Combine(source, "inherited-export-cache");
        try
        {
            Environment.SetEnvironmentVariable("MCBEEDITOR_CACHE_ROOT", disallowedTemporary);
            Invoke("export-environment", 0, ["--command", "weather query", "--output", Path.Combine(root, "environment.mcworld")]);
            Check(!Directory.Exists(disallowedTemporary), "inherited GUI export cache modified the source");
        }
        finally { Environment.SetEnvironmentVariable("MCBEEDITOR_CACHE_ROOT", inheritedCache); }

        var wrapped = Path.Combine(root, "wrapped.zip");
        using (var archive = ZipFile.Open(wrapped, ZipArchiveMode.Create))
            foreach (var file in Directory.EnumerateFiles(source, "*", SearchOption.AllDirectories))
                archive.CreateEntryFromFile(file, "World/" + Path.GetRelativePath(source, file).Replace('\\', '/'));
        Invoke("wrapped-zip", 0, ["--command", "weather query"], wrapped);
        var traversal = Path.Combine(root, "traversal.zip");
        using (var archive = ZipFile.Open(traversal, ZipArchiveMode.Create))
        using (var writer = new StreamWriter(archive.CreateEntry("../escaped.txt").Open())) writer.Write("bad");
        var rejected = Invoke("zip-traversal", 3, ["--command", "weather query"], traversal);
        Check(!Directory.EnumerateFiles(rejected.Cache, "escaped.txt", SearchOption.AllDirectories).Any(), "archive traversal escaped extraction");

        Invoke("save-mode-conflict", 2, ["--command", "time set 6000", "--in-place", "--output", Path.Combine(root, "conflict.mcworld")]);
        Invoke("zip-in-place", 2, ["--command", "time set 6000", "--in-place"], wrapped);
        using (var candidate = PortableWorldWorkspace.Create(Path.Combine(root, "InPlaceInputs"), source))
        {
            var target = candidate.WorkingRootPath;
            var savedFolder = Invoke("in-place-folder", 0, ["--command", "time set 6789", "--command", "setblock the_end 35 200 5 minecraft:diamond_block NULL", "--in-place"], target + Path.DirectorySeparatorChar);
            Check(Directory.GetDirectories(savedFolder.Cache).Length == 0, "successful in-place folder leaked its working copy");
            Check(WorldTimeStore.Read(new WorldDocument(target)).Time == 6789, "folder in-place time not persisted");
            using (var db = new WorldDocument(target).OpenDatabase())
                Check(new BedrockBlockStore(db).ReadBlock(2, 35, 200, 5).Layers[0].Name == "minecraft:diamond_block", "folder in-place database not persisted");
            Check(File.ReadAllText(Path.Combine(target, ".mcbeeditor", "private.txt")) == "editor-only", "folder in-place lost unrelated files");
            var unchanged = WorldFixture.Snapshot(target);
            var failed = Invoke("in-place-command-error", 1, ["--command", "time set 777", "--command", "structure load cli:missing overworld 0 64 0", "--in-place"], target);
            Check(WorldFixture.SameSnapshot(unchanged, WorldFixture.Snapshot(target)) && Directory.GetDirectories(failed.Cache).Length == 1, "failed in-place batch committed or lost recovery");
            var changed = false;
            var conflict = Invoke("in-place-source-change", 3, ["--command", "time set 888", "--in-place"], target, onOutput: line =>
            {
                if (!changed && line?.StartsWith("time set 完成", StringComparison.Ordinal) == true)
                {
                    File.WriteAllText(Path.Combine(target, "external-change.txt"), "preserve-me");
                    changed = true;
                }
            });
            Check(WorldTimeStore.Read(new WorldDocument(target)).Time == 6789 && File.Exists(Path.Combine(target, "external-change.txt")), "source conflict overwritten");
            Check(Directory.GetDirectories(conflict.Cache).Length == 1, "conflict recovery copy lost");
            var beforeCancel = WorldFixture.Snapshot(target);
            using (var cancellation = new CancellationTokenSource())
            {
                var cancelled = Invoke("in-place-folder-cancel", 130, ["--command", "time set 333", "--command", "time set 444", "--in-place"], target,
                    onOutput: line => { if (line == "> time set 333") cancellation.Cancel(); }, token: cancellation.Token);
                var recovery = Path.Combine(Directory.GetDirectories(cancelled.Cache).Single(), "World");
                Check(WorldFixture.SameSnapshot(beforeCancel, WorldFixture.Snapshot(target)), "cancelled folder batch changed the source");
                Check(WorldTimeStore.Read(new WorldDocument(recovery)).Time == 333 && cancelled.Error.Contains("未导出或提交"), "cancelled folder lost recovery or ran the next command");
            }
            string? collidingBackup = null;
            var moveBlocked = Invoke("in-place-folder-move-blocked", 3, ["--command", "time set 999", "--in-place"], target, onError: line =>
            {
                const string prefix = "原位替换前的恢复目录：";
                if (line?.StartsWith(prefix, StringComparison.Ordinal) != true) return;
                collidingBackup = line[prefix.Length..];
                Directory.CreateDirectory(collidingBackup);
                File.WriteAllText(Path.Combine(collidingBackup, "concurrent.txt"), "do-not-overwrite");
            });
            Check(WorldFixture.SameSnapshot(beforeCancel, WorldFixture.Snapshot(target)), "blocked directory move changed the source");
            Check(collidingBackup is not null && File.ReadAllText(Path.Combine(collidingBackup, "concurrent.txt")) == "do-not-overwrite", "blocked directory move replaced a conflicting directory");
            var moveRecovery = Path.Combine(Directory.GetDirectories(moveBlocked.Cache).Single(), "World");
            Check(WorldTimeStore.Read(new WorldDocument(moveRecovery)).Time == 999 && moveBlocked.Error.Contains("工作副本已保留"), "blocked directory move lost edits");
        }
        var inplaceArchive = Path.Combine(root, "in-place.mcworld");
        using (var zip = ZipFile.Open(inplaceArchive, ZipArchiveMode.Create))
        {
            foreach (var file in Directory.EnumerateFiles(source, "*", SearchOption.AllDirectories))
                zip.CreateEntryFromFile(file, "World/" + Path.GetRelativePath(source, file).Replace('\\', '/'));
            using var writer = new StreamWriter(zip.CreateEntry("outside.txt").Open());
            writer.Write("outside-world");
        }
        var savedArchive = Invoke("in-place-archive", 0, ["--command", "time set 2468", "--in-place"], inplaceArchive);
        Check(Directory.GetDirectories(savedArchive.Cache).Length == 0, "successful in-place archive leaked its working copy");
        using (var zip = ZipFile.OpenRead(inplaceArchive))
        {
            Check(zip.GetEntry("World/level.dat") is not null && zip.GetEntry("World/.mcbeeditor/private.txt") is not null, "in-place archive lost layout/private data");
            using var reader = new StreamReader(zip.GetEntry("outside.txt")!.Open());
            Check(reader.ReadToEnd() == "outside-world", "in-place archive lost outer files");
        }
        using (var verification = PortableWorldWorkspace.Create(Path.Combine(root, "Verify"), inplaceArchive))
            Check(WorldTimeStore.Read(new WorldDocument(verification.WorkingRootPath)).Time == 2468, "archive in-place time not persisted");
        var beforeFailure = File.ReadAllBytes(inplaceArchive);
        Invoke("in-place-archive-error", 1, ["--command", "time set 111", "--command", "structure load cli:missing overworld 0 64 0", "--in-place"], inplaceArchive);
        Check(File.ReadAllBytes(inplaceArchive).SequenceEqual(beforeFailure), "failed batch changed the original archive");
        using (var cancellation = new CancellationTokenSource())
        {
            var cancelled = Invoke("in-place-archive-cancel", 130, ["--command", "time set 333", "--command", "time set 444", "--in-place"], inplaceArchive,
                onOutput: line => { if (line == "> time set 333") cancellation.Cancel(); }, token: cancellation.Token);
            var recovery = Path.Combine(Directory.GetDirectories(cancelled.Cache).Single(), "World");
            Check(File.ReadAllBytes(inplaceArchive).SequenceEqual(beforeFailure), "cancelled archive batch changed the source");
            Check(WorldTimeStore.Read(new WorldDocument(recovery)).Time == 333, "cancelled archive lost edits or ran the next command");
        }
        // Windows allows the original to be read but denies replacement while Delete sharing is absent.
        using (var lockedSource = new FileStream(inplaceArchive, FileMode.Open, FileAccess.Read, FileShare.Read))
        {
            var blocked = Invoke("in-place-archive-publish-blocked", 3, ["--command", "time set 1357", "--in-place"], inplaceArchive);
            Check(File.ReadAllBytes(inplaceArchive).SequenceEqual(beforeFailure), "failed archive publish changed the original bytes");
            var recovery = Path.Combine(Directory.GetDirectories(blocked.Cache).Single(), "World");
            Check(WorldTimeStore.Read(new WorldDocument(recovery)).Time == 1357 && blocked.Error.Contains("工作副本已保留"), "failed archive publish lost edits or recovery path");
        }
        byte[]? externalArchiveBytes = null;
        var archiveConflict = Invoke("in-place-archive-source-change", 3, ["--command", "time set 888", "--in-place"], inplaceArchive, onOutput: line =>
        {
            if (externalArchiveBytes is not null || line?.StartsWith("time set 完成", StringComparison.Ordinal) != true) return;
            using (var zip = ZipFile.Open(inplaceArchive, ZipArchiveMode.Update))
            using (var writer = new StreamWriter(zip.CreateEntry("external.txt").Open())) writer.Write("external-change");
            externalArchiveBytes = File.ReadAllBytes(inplaceArchive);
        });
        Check(externalArchiveBytes is not null && File.ReadAllBytes(inplaceArchive).SequenceEqual(externalArchiveBytes), "archive conflict overwrote the external version");
        var conflictRecovery = Path.Combine(Directory.GetDirectories(archiveConflict.Cache).Single(), "World");
        Check(WorldTimeStore.Read(new WorldDocument(conflictRecovery)).Time == 888 && archiveConflict.Error.Contains("原存档在本次处理期间发生变化"), "archive conflict lost edits or failed for the wrong reason");

        var aliasedArchive = Path.Combine(root, "aliased-world.mcworld");
        var obsoleteNames = new[] { "old-dot.bin", "old-parent.bin", "old-separator.bin" };
        using (var zip = ZipFile.Open(aliasedArchive, ZipArchiveMode.Create))
        {
            foreach (var file in Directory.EnumerateFiles(source, "*", SearchOption.AllDirectories))
                zip.CreateEntryFromFile(file, "./World/" + Path.GetRelativePath(source, file).Replace('\\', '/'));
            foreach (var name in new[] { "./World/old-dot.bin", "Wrapper/../World/old-parent.bin", "World//old-separator.bin", "./outside.txt", "World2/keep.txt" })
            {
                using var writer = new StreamWriter(zip.CreateEntry(name).Open());
                writer.Write("marker:" + name);
            }
        }
        Invoke("in-place-archive-normalized-paths", 0, ["--command", "time set 5432", "--in-place"], aliasedArchive, onError: line =>
        {
            const string prefix = "工作副本：";
            if (line?.StartsWith(prefix, StringComparison.Ordinal) != true) return;
            var working = line[prefix.Length..];
            // Simulate obsolete files removed during database editing, then verify by real archive extraction.
            foreach (var name in obsoleteNames)
            {
                var file = Path.Combine(working, name);
                Check(File.Exists(file), "aliased entry did not extract to the expected world path");
                File.Delete(file);
            }
        });
        using (var verification = PortableWorldWorkspace.Create(Path.Combine(root, "Verify"), aliasedArchive))
        {
            Check(WorldTimeStore.Read(new WorldDocument(verification.WorkingRootPath)).Time == 5432, "normalized archive lost the edited world");
            Check(obsoleteNames.All(name => !File.Exists(Path.Combine(verification.WorkingRootPath, name))), "normalized archive resurrected a deleted working file");
        }
        using (var zip = ZipFile.OpenRead(aliasedArchive))
        {
            Check(zip.GetEntry("World/level.dat") is not null && zip.GetEntry("./World/level.dat") is null, "old alias of a replaced world entry was retained");
            foreach (var name in new[] { "./outside.txt", "World2/keep.txt" })
            {
                using var reader = new StreamReader(zip.GetEntry(name)!.Open());
                Check(reader.ReadToEnd() == "marker:" + name, "normalization changed an unrelated archive entry");
            }
        }
        Check(WorldFixture.SameSnapshot(original, WorldFixture.Snapshot(source)), "final original-world bytes changed");
    }

    private sealed record RunResult(string Output, string Error, string Cache);
    private sealed class ObservedWriter(Action<string?>? observer = null) : StringWriter(CultureInfo.InvariantCulture)
    {
        public override void WriteLine(string? value) { base.WriteLine(value); observer?.Invoke(value); }
    }
}
