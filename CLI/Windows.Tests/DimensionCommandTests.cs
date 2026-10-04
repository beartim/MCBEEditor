using MCBEEditor.Core.Chunk;
using MCBEEditor.Core.World;

namespace MCBEEditor.Cli.Tests;

internal static class DimensionCommandTests
{
    public static void RunParserTests()
    {
        foreach (var text in new[] { "dimension query", " DiMeNsIoN\tQuErY " })
        {
            var request = CliCommandParser.Parse(text);
            if (request is not DimensionCommandRequest || CliCommandPolicy.MayMutate(request))
                throw new InvalidOperationException("dimension query must route as a read-only command");
            CliCommandPolicy.RequireExecutable(request);
        }
        foreach (var text in new[] { "dimension", "dimension query extra", "dimension add bear 2147483648", "dimension empty", "dimension empty bear extra" })
        {
            try { CliCommandParser.Parse(text); throw new InvalidOperationException("invalid dimension command accepted"); }
            catch (InvalidDataException) { }
        }
        foreach (var text in new[] { "dimension add wzn:bear 1000", "dimension add bear 1003", "dimension add nether 1", "dimension add negative -2147483648" })
        {
            var request = CliCommandParser.Parse(text);
            if (request is not DimensionCommandRequest { Kind: DimensionCommandKind.Add } || !CliCommandPolicy.MayMutate(request))
                throw new InvalidOperationException("dimension add must request a write handle");
        }
        foreach(var text in new[]{"dimension empty bear","dimension empty 1000","dimension empty -2147483648"})
        {
            var request=CliCommandParser.Parse(text);
            if(request is not DimensionCommandRequest {Kind:DimensionCommandKind.Empty} || !CliCommandPolicy.MayMutate(request))
                throw new InvalidOperationException("dimension empty must request a write handle");
        }
        foreach(var text in new[]{"dimension purge bear","dimension purge 1000"})
            if(CliCommandParser.Parse(text) is not DimensionCommandRequest {Kind:DimensionCommandKind.Purge} request || !CliCommandPolicy.MayMutate(request))
                throw new InvalidOperationException("dimension purge must request a write handle");
        using var errors = new StringWriter();
        var lines = new[] { new CliCommandLine(1,"dimension add bear 1000"),
            new CliCommandLine(2,"getblock bear 0 64 0"), new CliCommandLine(3,"dimension query"),
            new CliCommandLine(4,"dimension purge bear") };
        var plan = CliCommandPlan.Parse(lines, errors, forExecution:false);
        if (plan is null || plan.Commands[1].Request is not GetBlockCommandRequest {Dimension:1000})
            throw new InvalidOperationException("same-file add must make its name available before writes: " + errors);
        errors.GetStringBuilder().Clear();
        if (CliCommandPlan.Parse([new CliCommandLine(1,"getblock existing:name 0 64 0")],errors,forExecution:false) is null)
            throw new InvalidOperationException("worldless validate must accept a syntactically valid dimension name");
        var initial = new[] {new DimensionRecord("existing:name",800,0)};
        errors.GetStringBuilder().Clear();
        var bound = CliCommandPlan.Parse(lines,errors,forExecution:true,dimensionContext:new DimensionCommandContext(initial));
        if (bound is null || bound.Commands[1].Request is not GetBlockCommandRequest {Dimension:1000})
            throw new InvalidOperationException("bound projection add/use/query/purge failed: " + errors);
        foreach (var bad in new[] {
            new[] {"dimension add bear 1000", "dimension add bear 1001"},
            new[] {"dimension add bear 1000", "dimension add cat 1000"},
            new[] {"dimension purge existing:name", "getblock existing:name 0 0 0"},
            new[] {"dimension add bear 1000", "getblock bear bad 0 0"},
            new[] {"dimension empty missing"} })
        {
            errors.GetStringBuilder().Clear();
            var commands=bad.Select((text,index)=>new CliCommandLine(index+1,text)).ToArray();
            if(CliCommandPlan.Parse(commands,errors,true,dimensionContext:new DimensionCommandContext(initial)) is not null)
                throw new InvalidOperationException("invalid batch passed: "+string.Join(";",bad));
        }
        errors.GetStringBuilder().Clear();
        var reused=CliCommandPlan.Parse([new(1,"dimension purge existing:name"),new(2,"dimension add existing:name 800"),new(3,"getblock existing:name 0 0 0")],
            errors,true,dimensionContext:new DimensionCommandContext(initial));
        if(reused?.Commands[2].Request is not GetBlockCommandRequest {Dimension:800})
            throw new InvalidOperationException("purge/add same name and ID failed");
        if(initial[0].Name!="existing:name" || initial[0].Id!=800) throw new InvalidOperationException("projection changed its snapshot input");
        Console.WriteLine("CLI dimension parser tests passed.");
    }
    public static void RunNativeTests(string root, string fixtureTool)
    {
        var worldPath=WorldFixture.Create(Path.Combine(root, "dimension-add"), fixtureTool);
        var world = new WorldDocument(worldPath);
        var result = new CliWorldCommandExecutor(world).Execute(CliCommandParser.Parse("dimension add persisted 9000001"));
        if (!result.ChangedWorld) throw new InvalidOperationException("add must mark the world changed");
        Dictionary<string,byte[]> controls;
        using(var reopened = world.OpenDatabase(readOnly: true))
        {
            if (!new DimensionStore(reopened).Snapshot().Any(row => row.Name == "persisted" && row.Id == 9000001 && row.ChunkCount == 0))
                throw new InvalidOperationException("added empty dimension did not persist after database reopen");
            controls=reopened.Entries(includeValues:true).Where(entry=>!BedrockDbKey.TryParse(entry.Key,out var parsed) || parsed.Position.Dimension!=0)
                .ToDictionary(entry=>Convert.ToHexString(entry.Key),entry=>entry.Value!);
        }
        var levelBefore=File.ReadAllBytes(Path.Combine(worldPath,"level.dat"));
        var cleared=new CliWorldCommandExecutor(world).Execute(CliCommandParser.Parse("dimension empty overworld"));
        if(!cleared.ChangedWorld) throw new InvalidOperationException("empty must mark the world changed");
        using(var reopened=world.OpenDatabase(readOnly:true))
        {
            var dimensions=new DimensionStore(reopened).Snapshot();
            if(dimensions.Single(row=>row.Id==0).ChunkCount!=0 || dimensions.Single(row=>row.Id==1).ChunkCount!=1)
                throw new InvalidOperationException("empty did not persist or changed another dimension");
            foreach(var (key,bytes) in controls)
                if(reopened.Get(Convert.FromHexString(key)) is not {} actual || !actual.SequenceEqual(bytes))
                    throw new InvalidOperationException("empty changed unrelated data: "+key);
        }
        if(!File.ReadAllBytes(Path.Combine(worldPath,"level.dat")).SequenceEqual(levelBefore)) throw new InvalidOperationException("empty changed level.dat");
        var source=WorldFixture.Create(Path.Combine(root,"dimension-batch-source"),fixtureTool);
        var original=WorldFixture.Snapshot(source);
        var export=Path.Combine(root,"dimension-batch.mcworld");
        using var output=new StringWriter(); using var errors=new StringWriter();
        var code=MCBEEditor.Cli.Program.Run(["--world",source,"--cache-dir",Path.Combine(root,"dimension-batch-cache"),
            "--output",export,"--command","dimension add bear 1000","--command","setblock bear 0 64 0 minecraft:stone NULL",
            "--command","getblock bear 0 64 0","--command","dimension empty bear","--command","dimension query"],output,errors);
        if(code!=0 || !output.ToString().Contains("bear=1000") || !output.ToString().Contains("minecraft:stone"))
            throw new InvalidOperationException("native dimension batch failed: "+output+errors);
        if(!WorldFixture.SameSnapshot(original,WorldFixture.Snapshot(source))) throw new InvalidOperationException("dimension batch changed source");
        var query=MCBEEditor.Cli.Program.Run(["--world",export,"--cache-dir",Path.Combine(root,"dimension-reopen-cache"),
            "--command","dimension query","--command","getblock bear 0 64 0"],output,errors);
        if(query!=0) throw new InvalidOperationException("export/reopen name binding failed: "+errors);
        foreach(var bad in new[]{"getblock bear bad 0 0","dimension add bear 1001"})
        {
            output.GetStringBuilder().Clear();errors.GetStringBuilder().Clear();
            var rejected=MCBEEditor.Cli.Program.Run(["--world",source,"--cache-dir",Path.Combine(root,"dimension-bad-cache"),
                "--output",Path.Combine(root,"dimension-rejected.mcworld"),"--command","dimension add bear 1000","--command",bad],output,errors);
            if(rejected!=2 || File.Exists(Path.Combine(root,"dimension-rejected.mcworld")) || !WorldFixture.SameSnapshot(original,WorldFixture.Snapshot(source)))
                throw new InvalidOperationException("preflight failure executed writes: "+errors);
        }
        Console.WriteLine("CLI dimension add/empty native persistence tests passed.");
    }
}
