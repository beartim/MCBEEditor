using System.Globalization;
using MCBEEditor.Core.Chunk;

namespace MCBEEditor.Core.World;

/// <summary>A memory-only projection used while checking a whole command file.</summary>
public sealed class DimensionCommandContext
{
    private readonly bool worldBound;
    private readonly Dictionary<string, int> names;
    private readonly HashSet<string> occupiedKeys;

    public DimensionCommandContext(IReadOnlyList<DimensionRecord>? dimensions = null, IEnumerable<byte[]>? databaseKeys = null)
    {
        worldBound = dimensions is not null;
        names = dimensions?.ToDictionary(row => row.Name, row => row.Id, StringComparer.Ordinal) ?? new(StringComparer.Ordinal);
        occupiedKeys = (databaseKeys ?? []).Select(Convert.ToHexString).ToHashSet(StringComparer.Ordinal);
    }

    public static DimensionCommandContext FromDatabase(IWorldDatabase database)
        => new(new DimensionStore(database).Snapshot(), database.Entries().Select(entry => entry.Key));

    public int Resolve(string token)
    {
        if (names.TryGetValue(token, out var id)) return id;
        try { return BlockCommandParser.ParseDimension(token); }
        catch (InvalidDataException) when (!worldBound)
        {
            // validate has no world: check the token, then bind it again before execution.
            DimensionStore.ValidateAddition(token, 3);
            return 0;
        }
    }

    public void Apply(DimensionCommandRequest request)
    {
        if (request.Kind == DimensionCommandKind.Query) return;
        if (request.Kind == DimensionCommandKind.Add)
        {
            var id = request.Id ?? throw new InvalidDataException("添加维度缺少 ID");
            var name = DimensionStore.ValidateAddition(request.Name ?? "", id);
            var key = Convert.ToHexString(DimensionStore.DataKey(name));
            if (names.ContainsKey(name) || names.ContainsValue(id))
                throw new InvalidDataException($"维度名称或 ID 已存在：{name}={id}");
            if (occupiedKeys.Contains(key)) throw new InvalidDataException($"数据库键已存在：{name}");
            names.Add(name, id);
            occupiedKeys.Add(key);
            return;
        }

        var target = Resolve(request.Name ?? throw new InvalidDataException("缺少维度"));
        var rows = names.Where(row => row.Value == target).ToArray();
        if (rows.Length == 0)
        {
            if (worldBound) throw new InvalidDataException($"维度不存在：{target}");
            return;
        }
        if (request.Kind == DimensionCommandKind.Purge)
        {
            foreach (var row in rows)
            {
                names.Remove(row.Key);
                occupiedKeys.Remove(Convert.ToHexString(DimensionStore.DataKey(row.Key)));
            }
            if (target is >= 0 and <= 2)
                occupiedKeys.Remove(Convert.ToHexString(System.Text.Encoding.UTF8.GetBytes($"dimension{target}")));
        }
        else if (request.Kind == DimensionCommandKind.Empty && target is < 0 or > 2
            && int.TryParse(rows[0].Key, NumberStyles.AllowLeadingSign, CultureInfo.InvariantCulture, out _))
        {
            // Empty gives an unregistered numeric dimension a persistent name.
            var name = $"dimension_{target}";
            while (names.ContainsKey(name) || occupiedKeys.Contains(Convert.ToHexString(DimensionStore.DataKey(name)))) name += "_";
            names.Remove(rows[0].Key);
            names.Add(name, target);
            occupiedKeys.Add(Convert.ToHexString(DimensionStore.DataKey(name)));
        }
    }
}
