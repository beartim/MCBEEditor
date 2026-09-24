using System.Text;
using MCBEEditor.Core.Chunk;
using MCBEEditor.Core.Nbt;

internal static class PlayerTargetingAuditTests
{
    private static void Check(bool value, string message)
    {
        if (!value) throw new Exception("Player targeting regression: " + message);
    }

    public static void Run()
    {
        using var database = new SelfTestWorldDatabase();
        byte[] Key(string name) => Encoding.UTF8.GetBytes(name);
        byte[] Player(long id) => BedrockNbtCodec.Encode(new NbtDocument("", new NbtCompoundValue([
            new("UniqueID", new NbtLongValue(id)), new("PlayerLevel", new NbtIntValue(0)),
            new("PlayerLevelProgress", new NbtFloatValue(0)), new("Keep", new NbtStringValue("unchanged"))
        ])), NbtEncoding.LittleEndian);
        var local = Player(1001);
        var other = Player(9002);
        database.Put(Key("~local_player"), local);
        database.Put(Key("player_server_2002"), Player(2002));
        database.Put(Key("player_server_9002"), other);
        string[] deleted = ["player_server_2002_meta", "player_data_2002", "player_storage_2002:inventory", "player_2002/extra"];
        string[] kept = ["player_server_9002_meta_2002", "player_data_9002:2002", "player_storage_9002_2002_meta", "player_data_12002", "player_data_20020", "unrelated_2002"];
        foreach (var name in deleted.Concat(kept)) database.Put(Key(name), [1, 2, 3]);
        var kick = new EntityActionCommandStore(database).Kick(
            (KickEntityActionCommandRequest)EntityActionCommandParser.Parse("kick 2002"));
        Check(kick.ChangedWorld && database.Get(Key("player_server_2002")) is null && deleted.All(name => database.Get(Key(name)) is null),
            "kick must delete only the selected owner and its known key families");
        Check(kept.All(name => database.Get(Key(name))!.SequenceEqual(new byte[] { 1, 2, 3 }))
              && database.Get(Key("~local_player"))!.SequenceEqual(local) && database.Get(Key("player_server_9002"))!.SequenceEqual(other),
            "kick must preserve other owners, similar IDs, unrelated keys and the local player byte-for-byte");

        var targeting = new TargetingCommandStore(database);
        foreach (var input in new[] { (Y: "64", Expected: 65.62), (Y: "64.0", Expected: 64.0), (Y: "Auto", Expected: 64.62) })
        {
            targeting.Teleport((TeleportTargetingCommandRequest)TargetingCommandParser.Parse($"teleport @s overworld -0.5 {input.Y} -16.5"));
            var root = BedrockNbtCodec.Decode(database.Get(Key("~local_player"))!, NbtEncoding.LittleEndian).Root;
            var pos = (NbtListValue)root.CompoundValue("Pos")!;
            Check(Math.Abs(((NbtFloatValue)pos.Values[1]).Value - input.Expected) < 0.001
                  && ((NbtFloatValue)pos.Values[0]).Value == -0.5f && root.StringValue("Keep") == "unchanged",
                "teleport integer/float/Auto height and unrelated tags");
        }
        foreach (var total in new long[] { 0, 7, 352, 394, BedrockPlayerExperience.MaximumTotal })
            Check(BedrockPlayerExperience.FromTotal(total).Total == total, "XP boundary roundtrip");

        var before = database.Get(Key("~local_player"))!;
        var spreadRejected = false;
        try { targeting.Spread(new SpreadTargetingCommandRequest(TargetingCommandParser.ParseTarget("@s"))); }
        catch (InvalidOperationException) { spreadRejected = true; }
        Check(spreadRejected && database.Get(Key("~local_player"))!.SequenceEqual(before), "spread without terrain must fail without writing");
        var missingRejected = false;
        try { targeting.ResolveTargets(TargetingCommandParser.ParseTarget("987654")); }
        catch (InvalidOperationException) { missingRejected = true; }
        Check(missingRejected && database.Get(Key("player_server_9002"))!.SequenceEqual(other), "missing target must not change an unselected player");
        Console.WriteLine("Player targeting audit scenarios passed.");
    }
}
