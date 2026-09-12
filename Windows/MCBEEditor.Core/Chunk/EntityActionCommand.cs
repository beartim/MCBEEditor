using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;
using MCBEEditor.Core.Entity;
using MCBEEditor.Core.Nbt;
using MCBEEditor.Core.World;

namespace MCBEEditor.Core.Chunk;

public enum EntityActionGiveSlotKind { Automatic, Indexed }
public sealed record EntityActionGiveSlot(EntityActionGiveSlotKind Kind, sbyte Value = 0)
{
    public string DisplayText => Kind == EntityActionGiveSlotKind.Automatic ? "Auto" : Value.ToString(CultureInfo.InvariantCulture);
}

public enum EntityActionEffectOperationKind { Give, Clear }
public sealed record EntityActionEffectSelection(bool All, int Id = 0, string Identifier = "")
{
    public string DisplayText => All ? "ALL" : Identifier;
}

public abstract record EntityActionCommandRequest;
public sealed record ClearEntityActionCommandRequest(TargetingCommandTarget Target) : EntityActionCommandRequest;
public sealed record GiveEntityActionCommandRequest(TargetingCommandTarget Target, EntityActionGiveSlot Slot, string ItemIdentifier, long Count, IReadOnlyList<NbtNamedTag> ItemTags) : EntityActionCommandRequest;
public sealed record KillEntityActionCommandRequest(TargetingCommandTarget Target, bool KillCreativePlayers) : EntityActionCommandRequest;
public sealed record KickEntityActionCommandRequest(TargetingCommandTarget Target) : EntityActionCommandRequest;
public sealed record SummonEntityActionCommandRequest(string Identifier, int Dimension, double X, double Y, double Z, IReadOnlyList<NbtNamedTag> Additions) : EntityActionCommandRequest;
public sealed record EffectEntityActionCommandRequest(EntityActionEffectOperationKind Operation, TargetingCommandTarget Target, EntityActionEffectSelection Selection, int Duration = 0, byte AmplifierRaw = 0) : EntityActionCommandRequest;

public static class EntityActionCommandParser
{
    private static readonly Regex IdentifierPattern = new("^[a-z0-9_.-]+:[a-z0-9_./-]+$", RegexOptions.Compiled | RegexOptions.CultureInvariant);
    private static readonly IReadOnlyDictionary<string, int> EffectIds = new Dictionary<string, int>(StringComparer.Ordinal)
    {
        ["speed"] = 1, ["slowness"] = 2, ["haste"] = 3, ["mining_fatigue"] = 4, ["strength"] = 5,
        ["instant_health"] = 6, ["instant_damage"] = 7, ["jump_boost"] = 8, ["nausea"] = 9, ["regeneration"] = 10,
        ["resistance"] = 11, ["fire_resistance"] = 12, ["water_breathing"] = 13, ["invisibility"] = 14, ["blindness"] = 15,
        ["night_vision"] = 16, ["hunger"] = 17, ["weakness"] = 18, ["poison"] = 19, ["wither"] = 20,
        ["health_boost"] = 21, ["absorption"] = 22, ["saturation"] = 23, ["levitation"] = 24, ["fatal_poison"] = 25,
        ["conduit_power"] = 26, ["slow_falling"] = 27, ["bad_omen"] = 28, ["village_hero"] = 29, ["darkness"] = 30,
        ["trial_omen"] = 31, ["wind_charged"] = 32, ["weaving"] = 33, ["oozing"] = 34, ["infested"] = 35,
        ["raid_omen"] = 36, ["breath_of_the_nautilus"] = 37
    };

    public const string Usage =
        "clear 目标\n" +
        "give 目标 Slot 物品 数目 物品标签\n" +
        "kill 目标 是否杀死创造模式玩家\n" +
        "kick 在线玩家UniqueID或@a\n" +
        "summon 实体类型 维度 x y z NBT标签或default\n" +
        "effect give 目标 状态效果ID或ALL 持续时间 效果等级\n" +
        "effect clear 目标 状态效果ID或ALL\n" +
        "目标支持非零 UniqueID、@s、@a、@e 或完整实体 identifier。";

    public static bool IsEntityActionCommand(string text)
    {
        var first = FirstToken(text).ToLowerInvariant();
        return first is "clear" or "give" or "kill" or "kick" or "summon" or "effect";
    }

    public static EntityActionCommandRequest Parse(string text)
    {
        var tokens = BlockCommandParser.TokenizeCommand(text);
        if (tokens.Count == 0) throw new InvalidDataException("命令不能为空。");
        var command = tokens[0].ToLowerInvariant();
        var args = tokens.Skip(1).ToArray();
        return command switch
        {
            "clear" => ParseClear(args),
            "give" => ParseGive(args),
            "kill" => ParseKill(args),
            "kick" => ParseKick(args),
            "summon" => ParseSummon(args),
            "effect" => ParseEffect(args),
            _ => throw new InvalidDataException("不存在的命令。\n" + Usage)
        };
    }

    private static EntityActionCommandRequest ParseClear(string[] args)
    {
        if (args.Length != 1) throw UsageError();
        return new ClearEntityActionCommandRequest(TargetingCommandParser.ParseTarget(args[0]));
    }

    private static EntityActionCommandRequest ParseGive(string[] args)
    {
        if (args.Length != 5) throw UsageError();
        return new GiveEntityActionCommandRequest(
            TargetingCommandParser.ParseTarget(args[0]), ParseGiveSlot(args[1]), ParseIdentifier(args[2], "物品"),
            ParseItemCount(args[3]), BlockCommandParser.ParseStates(args[4]));
    }

    private static EntityActionCommandRequest ParseKill(string[] args)
    {
        if (args.Length != 2) throw UsageError();
        return new KillEntityActionCommandRequest(TargetingCommandParser.ParseTarget(args[0]), ParseBooleanFlag(args[1], "是否杀死创造模式玩家"));
    }

    private static EntityActionCommandRequest ParseKick(string[] args)
    {
        if (args.Length != 1) throw UsageError();
        var target = TargetingCommandParser.ParseTarget(args[0]);
        if (target.Kind is not (TargetingCommandTargetKind.UniqueId or TargetingCommandTargetKind.AllPlayers)) throw UsageError();
        return new KickEntityActionCommandRequest(target);
    }

    private static EntityActionCommandRequest ParseSummon(string[] args)
    {
        if (args.Length != 6) throw UsageError();
        var identifier = ParseIdentifier(args[0], "实体");
        var dimension = BlockCommandParser.ParseDimension(args[1]);
        var x = ParseEntityCoordinate(args[2], "X");
        var y = ParseEntityCoordinate(args[3], "Y");
        var z = ParseEntityCoordinate(args[4], "Z");
        IReadOnlyList<NbtNamedTag> additions;
        if (args[5] == "default") additions = [];
        else
        {
            additions = BlockCommandParser.ParseStates(args[5]);
            if (additions.Count == 0) throw new InvalidDataException("summon 的最后一个参数只能是 default 或非空 NBT 标签。");
        }
        var protectedNames = new HashSet<string>(["uniqueid", "pos", "dimensionid", "dimension", "identifier", "id", "definitions"], StringComparer.OrdinalIgnoreCase);
        var invalid = additions.FirstOrDefault(tag => protectedNames.Contains(tag.Name));
        if (invalid is not null) throw new InvalidDataException($"summon 不能覆盖由命令控制的标签：{invalid.Name}");
        return new SummonEntityActionCommandRequest(identifier, dimension, x, y, z, additions);
    }

    private static EntityActionCommandRequest ParseEffect(string[] args)
    {
        if (args.Length == 0) throw UsageError();
        return args[0] switch
        {
            "give" when args.Length == 5 => new EffectEntityActionCommandRequest(
                EntityActionEffectOperationKind.Give, TargetingCommandParser.ParseTarget(args[1]), ParseEffectSelection(args[2]),
                ParseEffectDuration(args[3]), ParseEffectAmplifier(args[4])),
            "clear" when args.Length == 3 => new EffectEntityActionCommandRequest(
                EntityActionEffectOperationKind.Clear, TargetingCommandParser.ParseTarget(args[1]), ParseEffectSelection(args[2])),
            _ => throw UsageError()
        };
    }

    private static EntityActionGiveSlot ParseGiveSlot(string text)
    {
        if (text == "Auto") return new EntityActionGiveSlot(EntityActionGiveSlotKind.Automatic);
        if (!int.TryParse(text, NumberStyles.Integer, CultureInfo.InvariantCulture, out var value) || value is < 0 or > 35)
            throw new InvalidDataException("give 的 Slot 必须是 Auto 或 0～35 的整数。");
        return new EntityActionGiveSlot(EntityActionGiveSlotKind.Indexed, (sbyte)value);
    }

    private static long ParseItemCount(string text)
    {
        if (!long.TryParse(text, NumberStyles.Integer, CultureInfo.InvariantCulture, out var value) || value <= 0)
            throw new InvalidDataException("give 的物品数目必须是大于 0 的 Int64 整数。");
        return value;
    }

    private static bool ParseBooleanFlag(string text, string name) => text switch
    {
        "0" => false,
        "1" => true,
        _ => throw new InvalidDataException($"{name}只能是 0 或 1。")
    };

    private static string ParseIdentifier(string text, string kind)
    {
        if (!IdentifierPattern.IsMatch(text)) throw new InvalidDataException($"{kind}字符串 ID 格式无效：{text}");
        return text;
    }

    private static double ParseEntityCoordinate(string text, string name)
    {
        if (!double.TryParse(text, NumberStyles.Float, CultureInfo.InvariantCulture, out var value) || !double.IsFinite(value) || value < -float.MaxValue || value > float.MaxValue)
            throw new InvalidDataException($"summon 的 {name} 坐标必须是可写入 Float 的有限整数或浮点数：{text}");
        return value;
    }

    private static EntityActionEffectSelection ParseEffectSelection(string text)
    {
        if (text == "ALL") return new EntityActionEffectSelection(true);
        if (!EffectIds.TryGetValue(text, out var id)) throw new InvalidDataException($"状态效果字符串 ID 没有对应的数字 ID：{text}");
        return new EntityActionEffectSelection(false, id, text);
    }

    private static int ParseEffectDuration(string text)
    {
        if (!int.TryParse(text, NumberStyles.Integer, CultureInfo.InvariantCulture, out var value))
            throw new InvalidDataException("状态效果持续时间必须是 Int32 整数（-2147483648…2147483647）。");
        return value;
    }

    private static byte ParseEffectAmplifier(string text)
    {
        if (!short.TryParse(text, NumberStyles.Integer, CultureInfo.InvariantCulture, out var value) || value is < -128 or > 255)
            throw new InvalidDataException("状态效果等级必须是 -128…255 的整数；按 Bedrock Byte 原始值写入。");
        return unchecked((byte)value);
    }

    private static string FirstToken(string text)
    {
        if (string.IsNullOrWhiteSpace(text)) return string.Empty;
        var trimmed = text.TrimStart();
        var index = 0;
        while (index < trimmed.Length && !char.IsWhiteSpace(trimmed[index])) index++;
        return trimmed[..index];
    }

    private static InvalidDataException UsageError() => new("参数格式错误。\n" + Usage);
}

public sealed class EntityActionCommandStore
{
    private static readonly HashSet<string> TradeContainerNames = new(
        ["offers", "recipes", "tradetable", "tradeoffers", "trades", "economytradeablecomponent"], StringComparer.Ordinal);
    private static readonly HashSet<string> ItemContainerNames = new(
        ["inventory", "items", "chestitems", "hotbar", "armor", "armoritems", "armorinventory", "equipment", "hand", "handitems", "mainhand", "mainhanditem", "mainhandinventory", "offhand", "offhanditem", "offhandinventory", "playerinventory", "enderchestinventory", "cursorselecteditem", "selecteditem"], StringComparer.Ordinal);
    private static readonly HashSet<string> MainhandNames = new(["mainhand", "mainhanditem", "mainhandinventory"], StringComparer.Ordinal);
    private readonly IWorldDatabase _database;
    private readonly TargetingCommandStore _targets;

    public EntityActionCommandStore(IWorldDatabase database)
    {
        _database = database;
        _targets = new TargetingCommandStore(database);
    }

    public TargetingCommandExecutionResult Clear(ClearEntityActionCommandRequest request)
    {
        var targets = _targets.ResolveTargets(request.Target);
        var playerPuts = new List<WorldDatabasePut>();
        var entityReplacements = new List<(BedrockWorldObject Object, NbtDocument Document)>();
        var changedPlayers = 0;
        var changedEntities = 0;
        var removedItems = 0;
        var containerCount = 0;

        foreach (var record in targets.Players)
        {
            var mutation = ClearItemContainers(record.Document.Root);
            if (mutation.ContainerCount == 0) continue;
            playerPuts.Add(PlayerPut(record, new NbtDocument(record.Document.RootName, mutation.Value)));
            changedPlayers++; removedItems += mutation.ItemCount; containerCount += mutation.ContainerCount;
        }
        foreach (var item in targets.Entities)
        {
            var mutation = ClearItemContainers(item.Document.Root);
            if (mutation.ContainerCount == 0) continue;
            entityReplacements.Add((item, new NbtDocument(item.Document.RootName, mutation.Value)));
            changedEntities++; removedItems += mutation.ItemCount; containerCount += mutation.ContainerCount;
        }
        if (changedPlayers + changedEntities == 0) throw new InvalidOperationException($"目标 {request.Target.DisplayText} 没有可清除的物品容器。");
        var puts = playerPuts.Concat(EncodeUnmovedEntityReplacements(entityReplacements)).ToArray();
        _database.ApplyBatch(puts, [], sync: true);
        return TargetingCommandExecutionResult.Success(
            $"clear 完成：修改 {changedPlayers} 个玩家和 {changedEntities} 个实体，清除 {removedItems} 个物品条目，处理 {containerCount} 个容器；村民交易数据保持不变。", true);
    }

    public TargetingCommandExecutionResult Give(GiveEntityActionCommandRequest request)
    {
        var targets = _targets.ResolveTargets(request.Target);
        var playerPuts = new List<WorldDatabasePut>();
        var entityReplacements = new List<(BedrockWorldObject Object, NbtDocument Document)>();
        var changedPlayers = 0;
        var changedEntities = 0;
        var chestWrites = 0;
        var mainhandWrites = 0;
        var chestOverflowWrites = 0;
        var skippedEntities = 0;

        foreach (var record in targets.Players)
        {
            sbyte? requestedSlot = request.Slot.Kind == EntityActionGiveSlotKind.Indexed ? request.Slot.Value : null;
            var mutation = PlacePlayerItem(record.Document.Root, requestedSlot, request.ItemIdentifier, request.Count, request.ItemTags);
            if (!mutation.Changed) continue;
            playerPuts.Add(PlayerPut(record, new NbtDocument(record.Document.RootName, mutation.Value)));
            changedPlayers++;
        }
        foreach (var item in targets.Entities)
        {
            if (!HasWritableMainhandTag(item.Document.Root)) { skippedEntities++; continue; }
            EntityItemMutation mutation;
            if (request.Slot.Kind == EntityActionGiveSlotKind.Automatic)
            {
                var mainhand = ReplaceMainhandItem(item.Document.Root, request.ItemIdentifier, request.Count, request.ItemTags);
                mutation = new EntityItemMutation(mainhand.Value, mainhand.Changed, false, mainhand.Changed, false);
            }
            else mutation = PlaceEntityItem(item.Document.Root, request.Slot.Value, request.ItemIdentifier, request.Count, request.ItemTags);
            if (!mutation.Changed) { skippedEntities++; continue; }
            entityReplacements.Add((item, new NbtDocument(item.Document.RootName, mutation.Value)));
            changedEntities++;
            if (mutation.ChestWritten) chestWrites++;
            if (mutation.MainhandWritten) mainhandWrites++;
            if (mutation.ExceededChestSlots) chestOverflowWrites++;
        }
        if (changedPlayers + changedEntities == 0 && skippedEntities == 0)
            throw new InvalidOperationException("目标没有可写入的玩家 Inventory；非玩家实体必须已有 Mainhand 标签。");
        var puts = playerPuts.Concat(EncodeUnmovedEntityReplacements(entityReplacements)).ToArray();
        if (puts.Length > 0) _database.ApplyBatch(puts, [], sync: true);
        return TargetingCommandExecutionResult.Success(
            $"give 完成：Slot={request.Slot.DisplayText}，修改 {changedPlayers} 个玩家和 {changedEntities} 个实体；ChestItems 写入 {chestWrites} 次，Mainhand 写入 {mainhandWrites} 次，其中 {chestOverflowWrites} 个实体因 Slot 超出 ChestItems 槽位数而同时写入最后槽位与已有 Mainhand；物品 {request.ItemIdentifier} × {request.Count}，跳过 {skippedEntities} 个没有可写入 Mainhand 的实体。", puts.Length > 0);
    }

    public TargetingCommandExecutionResult Summon(SummonEntityActionCommandRequest request)
    {
        var store = new BedrockWorldObjectNbtStore(_database);
        var uniqueId = store.SuggestedUniqueId();
        var position = new BedrockWorldObjectPosition(request.X, request.Y, request.Z);
        var tags = new List<NbtNamedTag> { new("identifier", new NbtStringValue(request.Identifier)) };
        tags.AddRange(BedrockEntityCommonNbt.Tags(request.Identifier, position, request.Dimension, uniqueId)
            .Select(tag => new NbtNamedTag(tag.Name, NbtDocumentTools.DeepClone(tag.Value))));
        var root = MergeTopLevel(new NbtCompoundValue(tags), request.Additions);
        var document = new NbtDocument(string.Empty, root);
        var result = store.CreateEntityFromDocument(document, request.Dimension);
        return TargetingCommandExecutionResult.Success(
            $"summon 完成：创建 {request.Identifier}，维度 {DimensionToken(request.Dimension)}，坐标 {TargetingCommandParser.CoordinateText(request.X)} {TargetingCommandParser.CoordinateText(request.Y)} {TargetingCommandParser.CoordinateText(request.Z)}，UniqueID {uniqueId}，存储方式 {SourceText(result.Source)}。", true);
    }

    public TargetingCommandExecutionResult Effect(EffectEntityActionCommandRequest request)
    {
        var targets = _targets.ResolveTargets(request.Target);
        var playerPuts = new List<WorldDatabasePut>();
        var entityReplacements = new List<(BedrockWorldObject Object, NbtDocument Document)>();
        var changedPlayers = 0;
        var changedEntities = 0;
        var skippedPlayers = 0;
        var skippedEntities = 0;
        foreach (var record in targets.Players)
        {
            var mutation = ApplyEffect(record.Document.Root, request);
            if (!mutation.Changed) { skippedPlayers++; continue; }
            playerPuts.Add(PlayerPut(record, new NbtDocument(record.Document.RootName, mutation.Value)));
            changedPlayers++;
        }
        foreach (var item in targets.Entities)
        {
            var mutation = ApplyEffect(item.Document.Root, request);
            if (!mutation.Changed) { skippedEntities++; continue; }
            entityReplacements.Add((item, new NbtDocument(item.Document.RootName, mutation.Value)));
            changedEntities++;
        }
        var puts = playerPuts.Concat(EncodeUnmovedEntityReplacements(entityReplacements)).ToArray();
        if (puts.Length > 0) _database.ApplyBatch(puts, [], sync: true);
        var message = request.Operation == EntityActionEffectOperationKind.Give
            ? $"effect give 完成：向 {changedPlayers} 个玩家和 {changedEntities} 个实体给予 {request.Selection.DisplayText}，持续 {request.Duration} 游戏刻，等级 {request.AmplifierRaw + 1}。"
            : $"effect clear 完成：从 {changedPlayers} 个玩家和 {changedEntities} 个实体移除 {request.Selection.DisplayText}；跳过 {skippedPlayers} 个玩家和 {skippedEntities} 个没有对应状态效果的实体。";
        return TargetingCommandExecutionResult.Success(message, puts.Length > 0);
    }

    public TargetingCommandExecutionResult Kill(KillEntityActionCommandRequest request)
    {
        var targets = _targets.ResolveTargets(request.Target);
        var playerPuts = new List<WorldDatabasePut>();
        var killedPlayers = 0;
        var skippedCreative = 0;
        var playersWithoutHealth = 0;
        foreach (var record in targets.Players)
        {
            if (IsCreativePlayer(record.Document.Root) && !request.KillCreativePlayers) { skippedCreative++; continue; }
            var mutation = SetHealthCurrentToZero(record.Document.Root);
            if (!mutation.Changed) { playersWithoutHealth++; continue; }
            playerPuts.Add(PlayerPut(record, new NbtDocument(record.Document.RootName, mutation.Value)));
            killedPlayers++;
        }
        if (playerPuts.Count > 0) _database.ApplyBatch(playerPuts, [], sync: true);
        var deletedEntities = targets.Entities.Count > 0 ? new BedrockWorldObjectNbtStore(_database).Delete(targets.Entities) : 0;
        if (killedPlayers + deletedEntities == 0)
            throw new InvalidOperationException($"没有可杀死的目标；跳过 {skippedCreative} 个创造模式玩家，{playersWithoutHealth} 个玩家缺少 Health Current。");
        return TargetingCommandExecutionResult.Success(
            $"kill 完成：删除 {deletedEntities} 个非玩家实体，将 {killedPlayers} 个玩家的生命值 Current 设为 0.0；跳过 {skippedCreative} 个创造模式玩家和 {playersWithoutHealth} 个缺少生命值标签的玩家。", true);
    }

    public TargetingCommandExecutionResult Kick(KickEntityActionCommandRequest request)
    {
        var store = new PlayerNbtStore(_database);
        var records = store.Records();
        IReadOnlyList<PlayerNbtRecord> selected = request.Target.Kind switch
        {
            TargetingCommandTargetKind.AllPlayers => records.Where(record => !record.IsLocal).ToArray(),
            TargetingCommandTargetKind.UniqueId => records.Where(record => !record.IsLocal && store.UniqueId(record) == request.Target.UniqueId).ToArray(),
            _ => throw new InvalidDataException("kick 目标只能是在线玩家 UniqueID 或 @a。")
        };
        if (selected.Count == 0) throw new InvalidOperationException("没有匹配到在线玩家数据。");
        var deletedKeys = store.DeleteOnlinePlayerData(selected);
        return TargetingCommandExecutionResult.Success($"kick 完成：删除 {selected.Count} 个在线玩家的全部匹配数据，共移除 {deletedKeys} 条 LevelDB 记录。", true);
    }

    private sealed record ClearMutation(NbtValue Value, int ItemCount, int ContainerCount);
    private sealed record ValueMutation(NbtValue Value, bool Changed);
    private sealed record ChestMutation(NbtValue Value, bool Found, bool ExceededSlots);
    private sealed record EntityItemMutation(NbtValue Value, bool Changed, bool ChestWritten, bool MainhandWritten, bool ExceededChestSlots);

    private static ClearMutation ClearItemContainers(NbtValue value)
    {
        if (value is NbtCompoundValue compound)
        {
            var tags = compound.Tags.Select(tag => new NbtNamedTag(tag.Name, NbtDocumentTools.DeepClone(tag.Value))).ToList();
            var itemCount = 0; var containerCount = 0;
            for (var i = 0; i < tags.Count; i++)
            {
                var name = Normalized(tags[i].Name);
                if (TradeContainerNames.Contains(name)) continue;
                if (ItemContainerNames.Contains(name))
                {
                    switch (tags[i].Value)
                    {
                        case NbtListValue list:
                            itemCount += list.Values.Count(item => !IsEmptyItem(item));
                            tags[i] = new NbtNamedTag(tags[i].Name, new NbtListValue(list.ElementType == NbtTagType.End ? NbtTagType.Compound : list.ElementType, []));
                            containerCount++;
                            break;
                        case NbtCompoundValue child:
                            if (child.Tags.Count > 0) itemCount++;
                            tags[i] = new NbtNamedTag(tags[i].Name, new NbtCompoundValue([]));
                            containerCount++;
                            break;
                    }
                }
                else
                {
                    var nested = ClearItemContainers(tags[i].Value);
                    tags[i] = new NbtNamedTag(tags[i].Name, nested.Value);
                    itemCount += nested.ItemCount; containerCount += nested.ContainerCount;
                }
            }
            return new ClearMutation(new NbtCompoundValue(tags), itemCount, containerCount);
        }
        if (value is NbtListValue listValue)
        {
            var values = listValue.Values.Select(NbtDocumentTools.DeepClone).ToList();
            var itemCount = 0; var containerCount = 0;
            for (var i = 0; i < values.Count; i++)
            {
                var nested = ClearItemContainers(values[i]);
                values[i] = nested.Value; itemCount += nested.ItemCount; containerCount += nested.ContainerCount;
            }
            return new ClearMutation(new NbtListValue(listValue.ElementType, values), itemCount, containerCount);
        }
        return new ClearMutation(NbtDocumentTools.DeepClone(value), 0, 0);
    }

    private static bool IsEmptyItem(NbtValue value)
    {
        if (value is not NbtCompoundValue compound) return false;
        if (compound.Tags.Count == 0) return true;
        foreach (var tag in compound.Tags)
            if (Normalized(tag.Name) == "name" && tag.Value is NbtStringValue text)
            {
                var name = text.Value.ToLowerInvariant();
                if (name.Length == 0 || BedrockBlockMapColorCatalog.IsAir(name)) return true;
            }
        return false;
    }

    private static ValueMutation PlacePlayerItem(NbtValue value, sbyte? requestedSlot, string identifier, long count, IReadOnlyList<NbtNamedTag> itemTags)
    {
        if (value is not NbtCompoundValue compound) return new ValueMutation(value, false);
        var tags = compound.Tags.Select(tag => new NbtNamedTag(tag.Name, NbtDocumentTools.DeepClone(tag.Value))).ToList();
        for (var i = 0; i < tags.Count; i++)
        {
            var inventoryName = Normalized(tags[i].Name);
            if (inventoryName != "inventory" && inventoryName != "playerinventory") continue;
            if (tags[i].Value is not NbtListValue list || (list.ElementType != NbtTagType.Compound && list.Values.Count != 0)) continue;
            var values = list.Values.Select(NbtDocumentTools.DeepClone).ToList();
            if (requestedSlot.HasValue)
            {
                var slot = requestedSlot.Value;
                var existing = values.FindIndex(item => ItemSlot(item) == slot);
                if (existing >= 0) values[existing] = ItemStack(identifier, count, slot, 0, itemTags);
                else if (slot < values.Count) values[slot] = ItemStack(identifier, count, slot, 0, itemTags);
                else values.Add(ItemStack(identifier, count, slot, 0, itemTags));
            }
            else
            {
                var emptyCandidates = values.Select((item, index) => (item, index, slot: ItemSlot(item)))
                    .Where(x => IsEmptyInventorySlot(x.item) && x.slot.HasValue && x.slot.Value is >= 0 and <= 35)
                    .OrderBy(x => x.slot!.Value)
                    .ToArray();
                if (emptyCandidates.Length > 0)
                {
                    var firstEmpty = emptyCandidates[0];
                    values[firstEmpty.index] = ItemStack(identifier, count, (sbyte)firstEmpty.slot!.Value, 0, itemTags);
                }
                else
                {
                    var slot35 = values.FindIndex(item => ItemSlot(item) == 35);
                    if (slot35 >= 0) values[slot35] = ItemStack(identifier, count, 35, 0, itemTags);
                    else if (values.Count > 0) values[^1] = ItemStack(identifier, count, 35, 0, itemTags);
                    else values.Add(ItemStack(identifier, count, 0, 0, itemTags));
                }
            }
            tags[i] = new NbtNamedTag(tags[i].Name, new NbtListValue(NbtTagType.Compound, values));
            return new ValueMutation(new NbtCompoundValue(tags), true);
        }
        for (var i = 0; i < tags.Count; i++)
        {
            if (TradeContainerNames.Contains(Normalized(tags[i].Name))) continue;
            var nested = PlacePlayerItem(tags[i].Value, requestedSlot, identifier, count, itemTags);
            if (!nested.Changed) continue;
            tags[i] = new NbtNamedTag(tags[i].Name, nested.Value);
            return new ValueMutation(new NbtCompoundValue(tags), true);
        }
        return new ValueMutation(value, false);
    }

    private static EntityItemMutation PlaceEntityItem(NbtValue value, sbyte requestedSlot, string identifier, long count, IReadOnlyList<NbtNamedTag> itemTags)
    {
        var chest = PlaceChestItem(value, requestedSlot, identifier, count, itemTags);
        if (chest.Found)
        {
            if (!chest.ExceededSlots) return new EntityItemMutation(chest.Value, true, true, false, false);
            var mainhand = ReplaceMainhandItem(chest.Value, identifier, count, itemTags);
            if (!mainhand.Changed) return new EntityItemMutation(value, false, false, false, false);
            return new EntityItemMutation(mainhand.Value, true, true, true, true);
        }
        var direct = ReplaceMainhandItem(value, identifier, count, itemTags);
        return new EntityItemMutation(direct.Value, direct.Changed, false, direct.Changed, false);
    }

    private static ChestMutation PlaceChestItem(NbtValue value, sbyte requestedSlot, string identifier, long count, IReadOnlyList<NbtNamedTag> itemTags)
    {
        if (value is not NbtCompoundValue compound) return new ChestMutation(value, false, false);
        var tags = compound.Tags.Select(tag => new NbtNamedTag(tag.Name, NbtDocumentTools.DeepClone(tag.Value))).ToList();
        for (var i = 0; i < tags.Count; i++)
        {
            if (Normalized(tags[i].Name) != "chestitems") continue;
            if (tags[i].Value is not NbtListValue list || (list.ElementType != NbtTagType.Compound && list.Values.Count != 0)) continue;
            var values = list.Values.Select(NbtDocumentTools.DeepClone).ToList();
            var requestedIndex = (int)requestedSlot;
            if (requestedIndex < values.Count)
            {
                var exact = values.FindIndex(item => ItemSlot(item) == requestedSlot);
                if (exact < 0) exact = requestedIndex;
                values[exact] = ItemStack(identifier, count, requestedSlot, 1, itemTags);
                tags[i] = new NbtNamedTag(tags[i].Name, new NbtListValue(NbtTagType.Compound, values));
                return new ChestMutation(new NbtCompoundValue(tags), true, false);
            }
            if (values.Count == 0) values.Add(ItemStack(identifier, count, 0, 1, itemTags));
            else
            {
                var lastIndex = values.Count - 1;
                var rawSlot = ItemSlot(values[lastIndex]);
                var lastSlot = rawSlot.HasValue && rawSlot.Value is >= sbyte.MinValue and <= sbyte.MaxValue
                    ? (sbyte)rawSlot.Value
                    : (sbyte)Math.Clamp(lastIndex, sbyte.MinValue, sbyte.MaxValue);
                values[lastIndex] = ItemStack(identifier, count, lastSlot, 1, itemTags);
            }
            tags[i] = new NbtNamedTag(tags[i].Name, new NbtListValue(NbtTagType.Compound, values));
            return new ChestMutation(new NbtCompoundValue(tags), true, true);
        }
        for (var i = 0; i < tags.Count; i++)
        {
            if (TradeContainerNames.Contains(Normalized(tags[i].Name))) continue;
            var nested = PlaceChestItem(tags[i].Value, requestedSlot, identifier, count, itemTags);
            if (!nested.Found) continue;
            tags[i] = new NbtNamedTag(tags[i].Name, nested.Value);
            return new ChestMutation(new NbtCompoundValue(tags), true, nested.ExceededSlots);
        }
        return new ChestMutation(value, false, false);
    }

    private static bool HasWritableMainhandTag(NbtValue value)
    {
        if (value is not NbtCompoundValue compound) return false;
        foreach (var tag in compound.Tags.Where(tag => MainhandNames.Contains(Normalized(tag.Name))))
            if (tag.Value is NbtCompoundValue or NbtListValue) return true;
        foreach (var tag in compound.Tags)
        {
            if (TradeContainerNames.Contains(Normalized(tag.Name))) continue;
            if (HasWritableMainhandTag(tag.Value)) return true;
        }
        return false;
    }

    private static ValueMutation ReplaceMainhandItem(NbtValue value, string identifier, long count, IReadOnlyList<NbtNamedTag> itemTags)
    {
        if (value is not NbtCompoundValue compound) return new ValueMutation(value, false);
        var tags = compound.Tags.Select(tag => new NbtNamedTag(tag.Name, NbtDocumentTools.DeepClone(tag.Value))).ToList();
        for (var i = 0; i < tags.Count; i++)
        {
            if (!MainhandNames.Contains(Normalized(tags[i].Name))) continue;
            var stack = ItemStack(identifier, count, null, 1, itemTags);
            if (tags[i].Value is NbtCompoundValue)
            {
                tags[i] = new NbtNamedTag(tags[i].Name, stack);
                return new ValueMutation(new NbtCompoundValue(tags), true);
            }
            if (tags[i].Value is NbtListValue list)
            {
                var values = list.Values.Select(NbtDocumentTools.DeepClone).ToList();
                if (values.Count == 0) values.Add(stack); else values[0] = stack;
                tags[i] = new NbtNamedTag(tags[i].Name, new NbtListValue(NbtTagType.Compound, values));
                return new ValueMutation(new NbtCompoundValue(tags), true);
            }
        }
        for (var i = 0; i < tags.Count; i++)
        {
            if (TradeContainerNames.Contains(Normalized(tags[i].Name))) continue;
            var nested = ReplaceMainhandItem(tags[i].Value, identifier, count, itemTags);
            if (!nested.Changed) continue;
            tags[i] = new NbtNamedTag(tags[i].Name, nested.Value);
            return new ValueMutation(new NbtCompoundValue(tags), true);
        }
        return new ValueMutation(value, false);
    }

    private static NbtCompoundValue ItemStack(string identifier, long count, sbyte? slot, sbyte wasPickedUp, IReadOnlyList<NbtNamedTag> itemTags)
    {
        var tags = new List<NbtNamedTag>
        {
            new("Name", new NbtStringValue(identifier)),
            new("Count", UnboundedCountValue(count)),
            new("Damage", new NbtShortValue(0)),
            new("WasPickedUp", new NbtByteValue(wasPickedUp))
        };
        if (slot.HasValue) tags.Add(new NbtNamedTag("Slot", new NbtByteValue(slot.Value)));
        foreach (var addition in itemTags)
        {
            var index = tags.FindIndex(tag => string.Equals(tag.Name, addition.Name, StringComparison.OrdinalIgnoreCase));
            var copy = new NbtNamedTag(addition.Name, NbtDocumentTools.DeepClone(addition.Value));
            if (index >= 0) tags[index] = copy; else tags.Add(copy);
        }
        ReplaceItemTag(tags, "Name", new NbtStringValue(identifier));
        ReplaceItemTag(tags, "Count", UnboundedCountValue(count));
        ReplaceItemTag(tags, "WasPickedUp", new NbtByteValue(wasPickedUp));
        if (slot.HasValue) ReplaceItemTag(tags, "Slot", new NbtByteValue(slot.Value));
        return new NbtCompoundValue(tags);
    }

    private static void ReplaceItemTag(List<NbtNamedTag> tags, string name, NbtValue value)
    {
        var index = tags.FindIndex(tag => string.Equals(tag.Name, name, StringComparison.OrdinalIgnoreCase));
        var preferred = index >= 0 ? tags[index].Name : name;
        var replacement = new NbtNamedTag(preferred, value);
        if (index >= 0) tags[index] = replacement; else tags.Add(replacement);
    }

    private static NbtValue UnboundedCountValue(long count)
    {
        if (count is >= sbyte.MinValue and <= sbyte.MaxValue) return new NbtByteValue((sbyte)count);
        if (count is >= short.MinValue and <= short.MaxValue) return new NbtShortValue((short)count);
        if (count is >= int.MinValue and <= int.MaxValue) return new NbtIntValue((int)count);
        return new NbtLongValue(count);
    }

    private static long? ItemSlot(NbtValue value)
    {
        if (value is not NbtCompoundValue compound) return null;
        return compound.Tags.FirstOrDefault(tag => Normalized(tag.Name) == "slot")?.Value.IntegerValue();
    }

    private static bool IsEmptyInventorySlot(NbtValue value)
        => value is NbtCompoundValue compound && compound.Tags.Any(tag => Normalized(tag.Name) == "name" && tag.Value is NbtStringValue text && text.Value.Length == 0);

    private static ValueMutation ApplyEffect(NbtValue root, EffectEntityActionCommandRequest request)
    {
        if (root is not NbtCompoundValue compound) throw new InvalidDataException("实体或玩家的 NBT 根必须是 Compound。");
        var tags = compound.Tags.Select(tag => new NbtNamedTag(tag.Name, NbtDocumentTools.DeepClone(tag.Value))).ToList();
        var matching = tags.Select((tag, index) => (tag, index)).Where(x => string.Equals(x.tag.Name, "ActiveEffects", StringComparison.OrdinalIgnoreCase)).ToArray();
        if (matching.Length > 1) throw new InvalidDataException("NBT 根中存在多个 ActiveEffects 标签。");
        var activeIndex = matching.Length == 1 ? matching[0].index : -1;
        var requested = request.Selection.All ? EffectCatalog.Select(item => item.Id).ToHashSet() : new HashSet<int> { request.Selection.Id };
        if (request.Operation == EntityActionEffectOperationKind.Give)
        {
            var existing = activeIndex >= 0 ? EffectValues(tags[activeIndex].Value).ToList() : new List<NbtValue>();
            existing.RemoveAll(value => { try { return requested.Contains(EffectId(value)); } catch { return false; } });
            IEnumerable<EffectEntry> effectsToAdd = request.Selection.All
                ? EffectCatalog
                : new[] { new EffectEntry(request.Selection.Id, request.Selection.Identifier) };
            foreach (var effect in effectsToAdd)
                existing.Add(EffectCompound(effect.Id, request.Duration, request.AmplifierRaw));
            var list = new NbtListValue(NbtTagType.Compound, existing);
            if (activeIndex >= 0) tags[activeIndex] = new NbtNamedTag(tags[activeIndex].Name, list);
            else tags.Add(new NbtNamedTag("ActiveEffects", list));
            return new ValueMutation(new NbtCompoundValue(tags), true);
        }
        if (activeIndex < 0) return new ValueMutation(root, false);
        if (request.Selection.All)
        {
            tags.RemoveAt(activeIndex);
            return new ValueMutation(new NbtCompoundValue(tags), true);
        }
        var values = EffectValues(tags[activeIndex].Value).ToList();
        var removed = values.RemoveAll(value => requested.Contains(EffectId(value))) > 0;
        if (!removed) return new ValueMutation(root, false);
        if (values.Count == 0) tags.RemoveAt(activeIndex);
        else tags[activeIndex] = new NbtNamedTag(tags[activeIndex].Name, new NbtListValue(NbtTagType.Compound, values));
        return new ValueMutation(new NbtCompoundValue(tags), true);
    }

    private sealed record EffectEntry(int Id, string Identifier);
    private static readonly EffectEntry[] EffectCatalog =
    [
        new(1,"speed"),new(2,"slowness"),new(3,"haste"),new(4,"mining_fatigue"),new(5,"strength"),new(6,"instant_health"),new(7,"instant_damage"),new(8,"jump_boost"),new(9,"nausea"),new(10,"regeneration"),
        new(11,"resistance"),new(12,"fire_resistance"),new(13,"water_breathing"),new(14,"invisibility"),new(15,"blindness"),new(16,"night_vision"),new(17,"hunger"),new(18,"weakness"),new(19,"poison"),new(20,"wither"),
        new(21,"health_boost"),new(22,"absorption"),new(23,"saturation"),new(24,"levitation"),new(25,"fatal_poison"),new(26,"conduit_power"),new(27,"slow_falling"),new(28,"bad_omen"),new(29,"village_hero"),new(30,"darkness"),
        new(31,"trial_omen"),new(32,"wind_charged"),new(33,"weaving"),new(34,"oozing"),new(35,"infested"),new(36,"raid_omen"),new(37,"breath_of_the_nautilus")
    ];

    private static NbtValue EffectCompound(int id, int duration, byte amplifierRaw) => new NbtCompoundValue(
    [
        new("Ambient", new NbtByteValue(0)),
        new("Amplifier", new NbtByteValue(unchecked((sbyte)amplifierRaw))),
        new("DisplayOnScreenTextureAnimation", new NbtByteValue(0)),
        new("Duration", new NbtIntValue(duration)), new("DurationEasy", new NbtIntValue(duration)), new("DurationNormal", new NbtIntValue(duration)), new("DurationHard", new NbtIntValue(duration)),
        new("Id", new NbtByteValue((sbyte)Math.Clamp(id, sbyte.MinValue, sbyte.MaxValue))),
        new("ShowParticles", new NbtByteValue(0))
    ]);

    private static IReadOnlyList<NbtValue> EffectValues(NbtValue value)
    {
        if (value is not NbtListValue list) throw new InvalidDataException("ActiveEffects 必须是 Compound List。");
        if (list.ElementType == NbtTagType.End && list.Values.Count == 0) return [];
        if (list.ElementType != NbtTagType.Compound || list.Values.Any(item => item is not NbtCompoundValue)) throw new InvalidDataException("ActiveEffects 必须是 Compound List。");
        foreach (var item in list.Values) _ = EffectId(item);
        return list.Values.Select(NbtDocumentTools.DeepClone).ToArray();
    }

    private static int EffectId(NbtValue value)
    {
        if (value is not NbtCompoundValue compound) throw new InvalidDataException("状态效果必须是 Compound。");
        var tag = compound.Tags.FirstOrDefault(tag => string.Equals(tag.Name, "Id", StringComparison.OrdinalIgnoreCase))
                  ?? throw new InvalidDataException("状态效果 Compound 缺少数字 Id 标签。");
        long raw = tag.Value switch
        {
            NbtByteValue b => unchecked((byte)b.Value),
            NbtShortValue s => s.Value,
            NbtIntValue i => i.Value,
            NbtLongValue l => l.Value,
            _ => throw new InvalidDataException("状态效果 Id 必须是数字标签。")
        };
        if (raw < 0 || raw > int.MaxValue) throw new InvalidDataException("状态效果 Id 超出有效范围。");
        return (int)raw;
    }

    private static bool IsCreativePlayer(NbtValue value)
        => NumericTag(value, ["PlayerGameMode", "playerGameMode", "GameMode", "gameMode"]) == 1;

    private static ValueMutation SetHealthCurrentToZero(NbtValue value)
    {
        if (value is NbtCompoundValue compound)
        {
            var tags = compound.Tags.Select(tag => new NbtNamedTag(tag.Name, NbtDocumentTools.DeepClone(tag.Value))).ToList();
            var attributeName = tags.FirstOrDefault(tag => Normalized(tag.Name) is "name" or "id" or "identifier")?.Value as NbtStringValue;
            var normalizedAttribute = attributeName is null ? string.Empty : NormalizeIdentifier(attributeName.Value);
            if (normalizedAttribute is "minecraft:health" or "minecraft:attributehealth")
            {
                var index = tags.FindIndex(tag => Normalized(tag.Name) == "current");
                if (index >= 0) tags[index] = new NbtNamedTag(tags[index].Name, new NbtFloatValue(0));
                else tags.Add(new NbtNamedTag("Current", new NbtFloatValue(0)));
                return new ValueMutation(new NbtCompoundValue(tags), true);
            }
            for (var i = 0; i < tags.Count; i++)
            {
                var healthName = Normalized(tags[i].Name);
                if (healthName != "health" && healthName != "currenthealth") continue;
                if (tags[i].Value is not (NbtByteValue or NbtShortValue or NbtIntValue or NbtLongValue or NbtFloatValue or NbtDoubleValue)) continue;
                tags[i] = new NbtNamedTag(tags[i].Name, new NbtFloatValue(0));
                return new ValueMutation(new NbtCompoundValue(tags), true);
            }
            for (var i = 0; i < tags.Count; i++)
            {
                var nested = SetHealthCurrentToZero(tags[i].Value);
                if (!nested.Changed) continue;
                tags[i] = new NbtNamedTag(tags[i].Name, nested.Value);
                return new ValueMutation(new NbtCompoundValue(tags), true);
            }
            return new ValueMutation(value, false);
        }
        if (value is NbtListValue list)
        {
            var values = list.Values.Select(NbtDocumentTools.DeepClone).ToList();
            for (var i = 0; i < values.Count; i++)
            {
                var nested = SetHealthCurrentToZero(values[i]);
                if (!nested.Changed) continue;
                values[i] = nested.Value;
                return new ValueMutation(new NbtListValue(list.ElementType, values), true);
            }
        }
        return new ValueMutation(value, false);
    }

    private static long? NumericTag(NbtValue value, IEnumerable<string> names)
    {
        if (value is not NbtCompoundValue compound) return null;
        var wanted = new HashSet<string>(names.Select(Normalized), StringComparer.Ordinal);
        return compound.Tags.FirstOrDefault(tag => wanted.Contains(Normalized(tag.Name)))?.Value.IntegerValue();
    }

    private IReadOnlyList<WorldDatabasePut> EncodeUnmovedEntityReplacements(IReadOnlyList<(BedrockWorldObject Object, NbtDocument Document)> replacements)
    {
        if (replacements.Count == 0) return [];
        var puts = new List<WorldDatabasePut>();
        foreach (var group in replacements.GroupBy(item => Convert.ToHexString(item.Object.Storage.PrimaryKey), StringComparer.Ordinal))
        {
            var entries = group.ToArray();
            var key = entries[0].Object.Storage.PrimaryKey;
            var original = _database.Get(key) ?? throw new InvalidDataException("实体源 NBT 记录已不存在，请重新扫描。");
            var records = ConsecutiveNbtCodec.Decode(original).ToList();
            var occupied = new HashSet<int>();
            foreach (var replacement in entries)
            {
                var index = LocateEntityRecord(replacement.Object, records, occupied);
                occupied.Add(index);
                var source = records[index];
                var raw = BedrockNbtCodec.Encode(replacement.Document, source.Encoding);
                records[index] = new ConsecutiveNbtRecord(replacement.Document, raw, source.Encoding);
            }
            puts.Add(new WorldDatabasePut(key.ToArray(), ConsecutiveNbtCodec.Encode(records)));
        }
        return puts;
    }

    private static int LocateEntityRecord(BedrockWorldObject item, IReadOnlyList<ConsecutiveNbtRecord> records, HashSet<int> occupied)
    {
        var preferred = item.Storage.RecordIndex;
        if (preferred >= 0 && preferred < records.Count && !occupied.Contains(preferred) && records[preferred].RawData.AsSpan().SequenceEqual(item.RawData)) return preferred;
        if (item.UniqueId.HasValue)
        {
            var matching = records.Select((record, index) => (record, index)).Where(x => !occupied.Contains(x.index) && BedrockEntityCommonNbt.UniqueId(x.record.Document.Root) == item.UniqueId).Select(x => x.index).ToArray();
            if (matching.Length == 1) return matching[0];
            if (matching.Length > 1) throw new InvalidDataException("实体源记录中存在重复 UniqueID，无法安全批量写回。");
        }
        var rawMatches = records.Select((record, index) => (record, index)).Where(x => !occupied.Contains(x.index) && x.record.RawData.AsSpan().SequenceEqual(item.RawData)).Select(x => x.index).ToArray();
        if (rawMatches.Length == 1) return rawMatches[0];
        throw new InvalidDataException("无法在实体源记录中唯一定位目标，请重新扫描实体列表。");
    }

    private static WorldDatabasePut PlayerPut(PlayerNbtRecord record, NbtDocument document)
        => new(record.Key.ToArray(), BedrockNbtCodec.Encode(document, NbtEncoding.LittleEndian));

    private static NbtCompoundValue MergeTopLevel(NbtCompoundValue root, IReadOnlyList<NbtNamedTag> additions)
    {
        var tags = root.Tags.Select(tag => new NbtNamedTag(tag.Name, NbtDocumentTools.DeepClone(tag.Value))).ToList();
        foreach (var addition in additions)
        {
            var index = tags.FindIndex(tag => string.Equals(tag.Name, addition.Name, StringComparison.OrdinalIgnoreCase));
            var copy = new NbtNamedTag(addition.Name, NbtDocumentTools.DeepClone(addition.Value));
            if (index >= 0) tags[index] = copy; else tags.Add(copy);
        }
        return new NbtCompoundValue(tags);
    }

    private static string Normalized(string value) => value.Trim().ToLowerInvariant();
    private static string NormalizeIdentifier(string value)
    {
        var normalized = value.Trim().ToLowerInvariant();
        return normalized.Contains(':') ? normalized : "minecraft:" + normalized;
    }
    private static string DimensionToken(int dimension) => dimension switch { 0 => "overworld", 1 => "nether", 2 => "the_end", _ => dimension.ToString(CultureInfo.InvariantCulture) };
    private static string SourceText(BedrockWorldObjectSource source) => source switch { BedrockWorldObjectSource.ModernActor => "actorprefix", BedrockWorldObjectSource.LegacyChunkEntity => "Entity(0x32)", _ => source.ToString() };
}
