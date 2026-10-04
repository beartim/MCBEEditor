using MCBEEditor.Core.World;
using System.Globalization;

namespace MCBEEditor.Core.Chunk;

public enum DimensionCommandKind { Query, Add, Empty, Purge }
public sealed record DimensionCommandRequest(DimensionCommandKind Kind = DimensionCommandKind.Query, string? Name = null, int? Id = null)
{
    public bool IsDestructive => Kind != DimensionCommandKind.Query;
}

public static class DimensionCommandParser
{
    public const string Usage = "dimension query\ndimension add 名称 ID\ndimension empty 名称或ID\ndimension purge 名称或ID\nquery 列出存档中存在的维度名称、ID 和区块数，包含已登记的空维度。add 支持有或无 namespace 的名称及 Int32 ID；名称、ID 不得重复。缺失原版维度可用 overworld 0、nether 1、the_end 2 重建。\n示例：dimension query\n示例：dimension add wzn:bear 1000\n示例：dimension add bear 1003\n示例：dimension add nether 1\nempty 清空目标维度内容，保留维度登记；示例：dimension empty wzn:cat\n示例：dimension empty 1001\npurge 彻底删除维度及登记；受影响玩家迁到剩余主世界或最小ID维度，当前位置(0.5,65.62,0.5)，重生点(0,64,0)。无剩余维度且有玩家引用时拒绝。\n示例：dimension purge wzn:bear\n示例：dimension purge 1000";
    public static bool IsDimensionCommand(string text)
        => text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).FirstOrDefault()
            ?.Equals("dimension", StringComparison.OrdinalIgnoreCase) == true;
    public static DimensionCommandRequest Parse(string text)
    {
        var tokens = text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
        if (tokens.Length >= 2 && tokens[0].Equals("dimension", StringComparison.OrdinalIgnoreCase))
        {
            if (tokens.Length == 2 && tokens[1].Equals("query", StringComparison.OrdinalIgnoreCase))
                return new DimensionCommandRequest();
            if (tokens.Length == 3 && tokens[1].Equals("purge", StringComparison.OrdinalIgnoreCase))
                return new DimensionCommandRequest(DimensionCommandKind.Purge, tokens[2]);
            if (tokens.Length == 3 && tokens[1].Equals("empty", StringComparison.OrdinalIgnoreCase))
                return new DimensionCommandRequest(DimensionCommandKind.Empty, tokens[2]);
            if (tokens.Length == 4 && tokens[1].Equals("add", StringComparison.OrdinalIgnoreCase)
                && int.TryParse(tokens[3], NumberStyles.AllowLeadingSign, CultureInfo.InvariantCulture, out var id))
                return new DimensionCommandRequest(DimensionCommandKind.Add, DimensionStore.ValidateAddition(tokens[2], id), id);
        }
        throw new InvalidDataException("参数格式错误。\n" + Usage);
    }
}

public sealed class DimensionCommandStore(IWorldDatabase database)
{
    public TargetingCommandExecutionResult Execute(DimensionCommandRequest request)
    {
        if (request.Kind == DimensionCommandKind.Purge)
        {
            var store = new DimensionStore(database);
            var id = store.Resolve(request.Name ?? throw new InvalidDataException("缺少维度"));
            var result = store.Purge(id);
            return TargetingCommandExecutionResult.Success($"dimension purge 完成：ID={id}；删除键={result.DeletedKeyCount}，actor={result.RemovedActorCount}，迁移玩家记录={result.AffectedPlayerCount}；维度已删除。迁移坐标：当前位置(0.5,65.62,0.5)，重生点(0,64,0)。", true);
        }
        if (request.Kind == DimensionCommandKind.Empty)
        {
            var store = new DimensionStore(database);
            var id = store.Resolve(request.Name ?? throw new InvalidDataException("缺少维度"));
            var result = store.Empty(id);
            return TargetingCommandExecutionResult.Success($"dimension empty 完成：ID={id}；删除键={result.DeletedKeyCount}，actor={result.RemovedActorCount}；维度已保留。", true);
        }
        if (request.Kind == DimensionCommandKind.Add)
        {
            if (request.Name is null || request.Id is null) throw new InvalidDataException("添加维度缺少名称或 ID");
            new DimensionStore(database).Add(request.Name, request.Id.Value);
            return TargetingCommandExecutionResult.Success($"dimension add 完成：{request.Name}={request.Id.Value}。", true);
        }
        if (request.Kind != DimensionCommandKind.Query) throw new InvalidDataException("未知 dimension 操作");
        var rows = new DimensionStore(database).Snapshot();
        var message = $"dimension query：找到 {rows.Count} 个维度。";
        var lines = rows.Select(row => new TargetingOutputLine(row.QueryText, TargetingOutputStyle.Success)).ToList();
        if (lines.Count == 0) lines.Add(new TargetingOutputLine(message, TargetingOutputStyle.Success));
        return new TargetingCommandExecutionResult(message, false, lines);
    }
}
