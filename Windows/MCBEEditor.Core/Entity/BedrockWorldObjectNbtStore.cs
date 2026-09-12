using System.Buffers.Binary;
using System.Text;
using MCBEEditor.Core.Chunk;
using MCBEEditor.Core.Nbt;
using MCBEEditor.Core.World;

namespace MCBEEditor.Core.Entity;

/// <summary>
/// object NBT writer. Modern actors can move between chunks/dimensions
/// by atomically migrating their 8-byte actor reference between digp records.
/// Legacy Entity(0x32) records are migrated between chunk records. BlockEntity
/// coordinate moves are now coupled to their complete block storage layers in
/// the same LevelDB WriteBatch. Entity UniqueID remains immutable when editing
/// existing objects.
/// </summary>
public sealed class BedrockWorldObjectNbtStore
{
    private enum EntityCreationStorageMode
    {
        LegacyChunkEntity,
        ModernActor
    }

    private readonly IWorldDatabase _database;
    public BedrockWorldObjectNbtStore(IWorldDatabase database) => _database = database;

    public void SaveInPlace(BedrockWorldObject item, NbtDocument edited) => Save(item, edited);

    public void Save(BedrockWorldObject item, NbtDocument edited)
    {
        if (edited.Root is not NbtCompoundValue)
            throw new InvalidDataException("实体与方块实体的 NBT 根必须是 Compound。");

        var parsedPosition = BedrockWorldObjectScanner.ExtractPosition(edited.Root, item.Kind);
        if (item.Position is not null && parsedPosition is null)
            throw new InvalidOperationException(item.Kind == BedrockWorldObjectKind.Entity
                ? "实体 Pos/坐标字段缺失或格式无效，拒绝保存以避免实体与数据库归属失配。"
                : "方块实体坐标字段缺失或格式无效，拒绝保存。");
        var editedPosition = parsedPosition ?? item.Position;
        var originalHasDimension = item.Document.Root.CompoundValueIgnoreCase("DimensionId", "DimensionID", "dimension_id", "Dimension", "dimension") is not null;
        var parsedDimension = BedrockWorldObjectScanner.ExtractDimension(edited.Root);
        if (item.Kind == BedrockWorldObjectKind.Entity && originalHasDimension && parsedDimension is null)
            throw new InvalidOperationException("实体 Dimension 字段缺失或格式无效，拒绝保存以避免 digp 归属失配。");
        var editedDimension = parsedDimension ?? item.Dimension;
        var editedChunkX = editedPosition is null ? item.ChunkX : BedrockWorldObjectScanner.FloorDiv(editedPosition.BlockX, 16);
        var editedChunkZ = editedPosition is null ? item.ChunkZ : BedrockWorldObjectScanner.FloorDiv(editedPosition.BlockZ, 16);
        var moving = editedDimension != item.Dimension || editedChunkX != item.ChunkX || editedChunkZ != item.ChunkZ;
        var blockEntityLocationChanged = item.Kind == BedrockWorldObjectKind.BlockEntity
            && item.Position is { } originalBlockPosition
            && editedPosition is { } newBlockPosition
            && (editedDimension != item.Dimension
                || originalBlockPosition.BlockX != newBlockPosition.BlockX
                || originalBlockPosition.BlockY != newBlockPosition.BlockY
                || originalBlockPosition.BlockZ != newBlockPosition.BlockZ);

        if (item.Kind == BedrockWorldObjectKind.Entity)
        {
            var originalId = item.Document.Root.CompoundValueIgnoreCase("UniqueID", "UniqueId", "uniqueID", "uniqueId")?.IntegerValue();
            var editedId = edited.Root.CompoundValueIgnoreCase("UniqueID", "UniqueId", "uniqueID", "uniqueId")?.IntegerValue();
            if (originalId != editedId)
                throw new InvalidOperationException("暂不允许修改实体 UniqueID；该值与世界内其他引用有关。");
        }
        else if (editedPosition is { } blockPosition)
        {
            ValidateBlockEntityPosition(blockPosition);
        }

        if (blockEntityLocationChanged)
        {
            SaveBlockEntityMove(item, edited, editedDimension);
            return;
        }

        switch (item.Storage)
        {
            case ModernActorStorage modern when item.Kind == BedrockWorldObjectKind.Entity:
                SaveModernActor(item, modern, edited, editedDimension, editedChunkX, editedChunkZ);
                break;
            case ChunkRecordStorage chunk when item.Kind == BedrockWorldObjectKind.Entity && item.Source == BedrockWorldObjectSource.LegacyChunkEntity:
                SaveLegacyEntity(item, chunk, edited, editedDimension, editedChunkX, editedChunkZ);
                break;
            default:
                SaveSingleRecordInPlace(item, edited);
                break;
        }
    }

    public void MoveBlockEntity(BedrockWorldObject item, int targetDimension, int targetX, int targetY, int targetZ)
    {
        if (item.Kind != BedrockWorldObjectKind.BlockEntity || item.Source != BedrockWorldObjectSource.BlockEntity)
            throw new InvalidOperationException("只有方块实体可以使用方块联动迁移。");
        if (item.Position is null) throw new InvalidOperationException("方块实体缺少源坐标，无法迁移。");
        var root = SetTopLevel(item.Document.Root, ["x", "X"], "x", new NbtIntValue(targetX));
        root = SetTopLevel(root, ["y", "Y"], "y", new NbtIntValue(targetY));
        root = SetTopLevel(root, ["z", "Z"], "z", new NbtIntValue(targetZ));
        if (item.Document.Root.CompoundValueIgnoreCase("DimensionId", "DimensionID", "dimensionId", "dimension", "Dimension") is not null)
            root = SetTopLevel(root, ["DimensionId", "DimensionID", "dimensionId", "dimension", "Dimension"], "DimensionId", new NbtIntValue(targetDimension));
        var edited = new NbtDocument(item.Document.RootName, root);
        SaveBlockEntityMove(item, edited, targetDimension);
    }

    public int Delete(BedrockWorldObject item) => Delete([item]);

    /// <summary>
    /// Removes a scanned object set in one database batch. Shared consecutive-NBT
    /// values are rewritten once, so deleting several legacy entities from the
    /// same chunk cannot invalidate the later record indexes in the selection.
    /// </summary>
    public int Delete(IEnumerable<BedrockWorldObject> items)
    {
        var selected = items
            .Where(item => item is not null)
            .GroupBy(item => item.StableId, StringComparer.Ordinal)
            .Select(group => group.First())
            .ToArray();
        if (selected.Length == 0) return 0;

        var puts = new List<WorldDatabasePut>();
        var deletes = new List<byte[]>();
        var deletedActorReferences = new List<byte[]>();
        var deletedCount = 0;

        foreach (var group in selected.GroupBy(item => Convert.ToHexString(item.Storage.PrimaryKey), StringComparer.Ordinal))
        {
            var objects = group.ToArray();
            var key = objects[0].Storage.PrimaryKey;
            var current = _database.Get(key) ?? throw new InvalidDataException("对象源记录已经不存在，请重新扫描实体列表。");
            var records = ConsecutiveNbtCodec.Decode(current).ToList();
            var indexes = new HashSet<int>();
            foreach (var item in objects) indexes.Add(Locate(item, records));
            foreach (var index in indexes.OrderByDescending(value => value)) records.RemoveAt(index);
            deletedCount += indexes.Count;

            if (records.Count == 0)
            {
                deletes.Add(key.ToArray());
                if (objects[0].Storage is ModernActorStorage modern && modern.ActorStorageReference is { Length: 8 } reference)
                    deletedActorReferences.Add(reference.ToArray());
            }
            else
            {
                puts.Add(new WorldDatabasePut(key.ToArray(), ConsecutiveNbtCodec.Encode(records)));
            }
        }

        if (deletedActorReferences.Count > 0)
        {
            var digestPrefix = Encoding.ASCII.GetBytes("digp");
            foreach (var entry in _database.Entries(digestPrefix, includeValues: true))
            {
                if (entry.Value is null) continue;
                var references = ParseDigest(entry.Value, "digp");
                var filtered = references.Where(reference =>
                    !deletedActorReferences.Any(deleted => reference.AsSpan().SequenceEqual(deleted))).ToList();
                if (filtered.Count == references.Count) continue;
                if (filtered.Count == 0) deletes.Add(entry.Key.ToArray());
                else puts.Add(new WorldDatabasePut(entry.Key.ToArray(), JoinDigest(filtered)));
            }
        }

        _database.ApplyBatch(CoalescePuts(puts), DistinctKeys(deletes), sync: true);
        return deletedCount;
    }

    /// <summary>
    /// Import preparation deliberately changes only Pos and UniqueID. It does
    /// not synthesize identifier/definitions/DimensionId or any other defaults.
    /// </summary>
    public NbtDocument PrepareImportedEntityDocument(NbtDocument source, BedrockWorldObjectPosition position, long uniqueId)
    {
        if (source.Root is not NbtCompoundValue) throw new InvalidDataException("实体 NBT 根必须是 Compound。");
        ValidatePosition(position);
        if (uniqueId == 0) throw new InvalidDataException("实体 UniqueID 不能为 0。");

        var root = SetTopLevel(source.Root,
            ["Pos", "pos", "Position", "position"], "Pos", BedrockEntityCommonNbt.PositionTag(position));
        root = SetTopLevel(root,
            ["UniqueID", "UniqueId", "uniqueID", "uniqueId"], "UniqueID", new NbtLongValue(uniqueId));
        return new NbtDocument(source.RootName, root);
    }

    /// <summary>
    /// Creates one imported entity as-is. Pos and UniqueID are required. A
    /// missing DimensionId is resolved only at the storage layer by the optional
    /// fallback dimension and is not inserted into the entity NBT.
    /// </summary>
    public BedrockWorldObjectCreateResult CreateEntityFromDocument(NbtDocument document, int? fallbackDimension = null)
    {
        if (document.Root is not NbtCompoundValue) throw new InvalidDataException("导入实体 NBT 根必须是 Compound。");
        var position = BedrockEntityCommonNbt.Position(document.Root)
            ?? throw new InvalidDataException("导入实体 NBT 必须包含有效 Pos。");
        var uniqueId = BedrockEntityCommonNbt.UniqueId(document.Root)
            ?? throw new InvalidDataException("导入实体 NBT 必须包含 UniqueID。");
        ValidatePosition(position);
        if (uniqueId == 0) throw new InvalidDataException("实体 UniqueID 不能为 0。");
        var dimension = BedrockEntityCommonNbt.Dimension(document.Root) ?? fallbackDimension
            ?? throw new InvalidDataException("实体缺少 DimensionId；请选择要写入的维度。");
        EnsureUniqueIdAvailable(uniqueId);

        var chunkX = BedrockWorldObjectScanner.FloorDiv(position.BlockX, 16);
        var chunkZ = BedrockWorldObjectScanner.FloorDiv(position.BlockZ, 16);
        var storageMode = PreferredEntityCreationStorage(null, chunkX, chunkZ, dimension);
        return WriteCreatedEntity(document, position, dimension, uniqueId, storageMode, NbtEncoding.LittleEndian);
    }

    public long SuggestedUniqueId()
    {
        for (var attempt = 0; attempt < 128; attempt++)
        {
            var candidate = Random.Shared.NextInt64(1, long.MaxValue);
            if (!IsEntityUniqueIdAvailable(candidate)) continue;
            var reference = ActorReference(candidate);
            if (_database.Get(BedrockWorldObjectScanner.ActorKey(reference)) is null) return candidate;
        }
        throw new InvalidOperationException("无法生成未占用的实体 UniqueID，请手动填写。");
    }

    public BedrockWorldObjectCreateResult Create(
        BedrockWorldObjectKind kind,
        string identifier,
        BedrockWorldObjectPosition position,
        int dimension,
        long? uniqueId = null,
        BedrockWorldObject? template = null)
    {
        identifier = identifier?.Trim() ?? string.Empty;
        if (identifier.Length == 0) throw new InvalidDataException("实体或方块实体 ID 不能为空。");
        ValidatePosition(position);
        if (template is not null && template.Kind != kind) throw new InvalidOperationException("模板类型与要创建的对象类型不一致。");

        if (kind == BedrockWorldObjectKind.Entity)
        {
            identifier = BedrockEntityCommonNbt.NormalizeIdentifier(identifier);
            var actorId = uniqueId ?? SuggestedUniqueId();
            if (actorId == 0) throw new InvalidDataException("实体 UniqueID 不能为 0。");
            EnsureUniqueIdAvailable(actorId);
            var chunkX = BedrockWorldObjectScanner.FloorDiv(position.BlockX, 16);
            var chunkZ = BedrockWorldObjectScanner.FloorDiv(position.BlockZ, 16);
            var storageMode = PreferredEntityCreationStorage(template, chunkX, chunkZ, dimension);
            var document = MakeEntityCreationDocument(identifier, position, dimension, actorId, template?.Document, storageMode);
            return WriteCreatedEntity(document, position, dimension, actorId, storageMode, template?.Storage.Encoding ?? NbtEncoding.LittleEndian);
        }

        return CreateBlockEntity(identifier, position, dimension, template);
    }

    private void SaveModernActor(BedrockWorldObject item, ModernActorStorage storage, NbtDocument edited,
        int newDimension, int newChunkX, int newChunkZ)
    {
        var actorKey = storage.ActorKey;
        var current = _database.Get(actorKey) ?? throw new InvalidDataException("actorprefix 记录已经不存在，请重新扫描实体列表。");
        var records = ConsecutiveNbtCodec.Decode(current).ToList();
        var index = Locate(item, records);
        var source = records[index];
        records[index] = source with { Document = edited, RawData = BedrockNbtCodec.Encode(edited, source.Encoding) };
        var actorBytes = ConsecutiveNbtCodec.Encode(records);

        var reference = storage.ActorStorageReference;
        if (reference is null || reference.Length != 8)
            throw new InvalidDataException("现代实体 actorprefix 键缺少有效的 8 字节存储引用。");

        var sameOwner = newDimension == item.Dimension && newChunkX == item.ChunkX && newChunkZ == item.ChunkZ;
        if (sameOwner)
        {
            _database.Put(actorKey, actorBytes, sync: true);
            return;
        }

        var oldDigestKey = storage.DigestKey.Length > 0 ? storage.DigestKey : FindExistingDigestKey(item.ChunkX, item.ChunkZ, item.Dimension) ?? BedrockWorldObjectScanner.DigestKey(item.ChunkX, item.ChunkZ, item.Dimension);
        var oldDigest = _database.Get(oldDigestKey) ?? throw new InvalidDataException("旧 digp 记录已经不存在，请重新扫描实体列表。");
        var oldReferences = ParseDigest(oldDigest, "旧 digp");
        var removed = oldReferences.RemoveAll(value => value.AsSpan().SequenceEqual(reference));
        if (removed == 0) throw new InvalidDataException("旧 digp 中没有找到当前 actorprefix 引用，请重新扫描实体列表。");

        var newDigestKey = FindExistingDigestKey(newChunkX, newChunkZ, newDimension) ?? BedrockWorldObjectScanner.DigestKey(newChunkX, newChunkZ, newDimension);
        var newDigestRaw = _database.Get(newDigestKey);
        var newReferences = newDigestRaw is null ? new List<byte[]>() : ParseDigest(newDigestRaw, "目标 digp");
        if (!newReferences.Any(value => value.AsSpan().SequenceEqual(reference))) newReferences.Add(reference.ToArray());

        var puts = new List<WorldDatabasePut> { new(actorKey.ToArray(), actorBytes) };
        var deletes = new List<byte[]>();
        if (oldReferences.Count == 0) deletes.Add(oldDigestKey.ToArray());
        else puts.Add(new WorldDatabasePut(oldDigestKey.ToArray(), JoinDigest(oldReferences)));
        puts.Add(new WorldDatabasePut(newDigestKey.ToArray(), JoinDigest(newReferences)));
        _database.ApplyBatch(puts, deletes, sync: true);
    }

    private void SaveLegacyEntity(BedrockWorldObject item, ChunkRecordStorage storage, NbtDocument edited,
        int newDimension, int newChunkX, int newChunkZ)
    {
        var sourceKey = storage.Key;
        var current = _database.Get(sourceKey) ?? throw new InvalidDataException("旧式 Entity 记录已经不存在，请重新扫描实体列表。");
        var sourceRecords = ConsecutiveNbtCodec.Decode(current).ToList();
        var sourceIndex = Locate(item, sourceRecords);
        var originalRecord = sourceRecords[sourceIndex];
        var destinationKey = new BedrockDbKey(new ChunkPosition(newChunkX, newChunkZ, newDimension), ChunkRecordType.Entity, null).Encode();

        if (sourceKey.AsSpan().SequenceEqual(destinationKey))
        {
            sourceRecords[sourceIndex] = originalRecord with { Document = edited, RawData = BedrockNbtCodec.Encode(edited, originalRecord.Encoding) };
            _database.Put(sourceKey, ConsecutiveNbtCodec.Encode(sourceRecords), sync: true);
            return;
        }

        sourceRecords.RemoveAt(sourceIndex);
        var destinationRaw = _database.Get(destinationKey);
        var destinationRecords = destinationRaw is null ? new List<ConsecutiveNbtRecord>() : ConsecutiveNbtCodec.Decode(destinationRaw).ToList();
        if (item.UniqueId is long uniqueId && destinationRecords.Any(record =>
                record.Document.Root.CompoundValueIgnoreCase("UniqueID", "UniqueId", "uniqueID", "uniqueId")?.IntegerValue() == uniqueId))
            throw new InvalidOperationException("目标区块已经存在相同 UniqueID 的旧式实体，拒绝重复迁移。");
        var destinationEncoding = destinationRecords.Count > 0 ? destinationRecords[0].Encoding : originalRecord.Encoding;
        if (destinationRecords.Any(record => record.Encoding != destinationEncoding))
            throw new InvalidDataException("目标 Entity 记录包含混合 NBT 编码，无法安全追加实体。");
        destinationRecords.Add(new ConsecutiveNbtRecord(edited, BedrockNbtCodec.Encode(edited, destinationEncoding), destinationEncoding));

        var puts = new List<WorldDatabasePut>
        {
            new(destinationKey, ConsecutiveNbtCodec.Encode(destinationRecords))
        };
        var deletes = new List<byte[]>();
        if (sourceRecords.Count == 0) deletes.Add(sourceKey.ToArray());
        else puts.Add(new WorldDatabasePut(sourceKey.ToArray(), ConsecutiveNbtCodec.Encode(sourceRecords)));
        _database.ApplyBatch(puts, deletes, sync: true);
    }

    private void SaveBlockEntityMove(BedrockWorldObject item, NbtDocument edited, int targetDimension)
    {
        if (item.Storage is not ChunkRecordStorage storage || item.Source != BedrockWorldObjectSource.BlockEntity)
            throw new InvalidOperationException("方块实体存储归属无效，无法执行联动迁移。");
        if (item.Position is not { } sourcePosition)
            throw new InvalidOperationException("方块实体缺少源坐标，无法迁移。");
        var targetPosition = BedrockWorldObjectScanner.ExtractPosition(edited.Root, BedrockWorldObjectKind.BlockEntity)
            ?? throw new InvalidDataException("方块实体目标坐标缺失或格式无效。");
        ValidateBlockEntityPosition(sourcePosition);
        ValidateBlockEntityPosition(targetPosition);

        var sourceKey = storage.Key;
        var sourceRaw = _database.Get(sourceKey) ?? throw new InvalidDataException("源 BlockEntity 记录已经不存在，请重新扫描。");
        var sourceRecords = ConsecutiveNbtCodec.Decode(sourceRaw).ToList();
        var sourceIndex = Locate(item, sourceRecords);
        var sourceRecord = sourceRecords[sourceIndex];

        var targetChunkX = BedrockWorldObjectScanner.FloorDiv(targetPosition.BlockX, 16);
        var targetChunkZ = BedrockWorldObjectScanner.FloorDiv(targetPosition.BlockZ, 16);
        var targetKey = new BedrockDbKey(new ChunkPosition(targetChunkX, targetChunkZ, targetDimension), ChunkRecordType.BlockEntity, null).Encode();

        var blockPlan = new BedrockBlockStore(_database).PlanMoveBlock(
            item.Dimension, sourcePosition.BlockX, sourcePosition.BlockY, sourcePosition.BlockZ,
            targetDimension, targetPosition.BlockX, targetPosition.BlockY, targetPosition.BlockZ);
        if (blockPlan.SourceBefore.Layers.Count == 0 || blockPlan.SourceBefore.Layers.All(layer => layer.IsAir))
            throw new InvalidOperationException("方块实体源坐标对应方块为空气，拒绝只移动 NBT。请先修复源方块后再迁移。");

        var puts = blockPlan.Puts.ToList();
        var deletes = blockPlan.Deletes.Select(key => key.ToArray()).ToList();
        if (sourceKey.AsSpan().SequenceEqual(targetKey))
        {
            for (var index = 0; index < sourceRecords.Count; index++)
            {
                if (index == sourceIndex) continue;
                var coordinate = BedrockWorldObjectScanner.ExtractPosition(sourceRecords[index].Document.Root, BedrockWorldObjectKind.BlockEntity);
                if (coordinate?.BlockX == targetPosition.BlockX && coordinate.BlockY == targetPosition.BlockY && coordinate.BlockZ == targetPosition.BlockZ)
                    throw new InvalidOperationException("目标坐标已经存在另一个方块实体，拒绝覆盖。");
            }
            sourceRecords[sourceIndex] = sourceRecord with
            {
                Document = edited,
                RawData = BedrockNbtCodec.Encode(edited, sourceRecord.Encoding)
            };
            puts.Add(new WorldDatabasePut(sourceKey.ToArray(), ConsecutiveNbtCodec.Encode(sourceRecords)));
        }
        else
        {
            sourceRecords.RemoveAt(sourceIndex);
            var targetRaw = _database.Get(targetKey);
            var targetRecords = targetRaw is null ? new List<ConsecutiveNbtRecord>() : ConsecutiveNbtCodec.Decode(targetRaw).ToList();
            foreach (var record in targetRecords)
            {
                var coordinate = BedrockWorldObjectScanner.ExtractPosition(record.Document.Root, BedrockWorldObjectKind.BlockEntity);
                if (coordinate?.BlockX == targetPosition.BlockX && coordinate.BlockY == targetPosition.BlockY && coordinate.BlockZ == targetPosition.BlockZ)
                    throw new InvalidOperationException("目标坐标已经存在方块实体，拒绝覆盖。");
            }
            var targetEncoding = targetRecords.Count > 0 ? targetRecords[0].Encoding : sourceRecord.Encoding;
            if (targetRecords.Any(record => record.Encoding != targetEncoding))
                throw new InvalidDataException("目标 BlockEntity 记录包含混合 NBT 编码，无法安全追加。");
            targetRecords.Add(new ConsecutiveNbtRecord(edited, BedrockNbtCodec.Encode(edited, targetEncoding), targetEncoding));
            puts.Add(new WorldDatabasePut(targetKey, ConsecutiveNbtCodec.Encode(targetRecords)));
            if (sourceRecords.Count == 0) deletes.Add(sourceKey.ToArray());
            else puts.Add(new WorldDatabasePut(sourceKey.ToArray(), ConsecutiveNbtCodec.Encode(sourceRecords)));
        }

        var finalPuts = CoalescePuts(puts);
        var finalDeletes = DistinctKeys(deletes)
            .Where(key => !finalPuts.Any(put => put.Key.AsSpan().SequenceEqual(key)))
            .ToArray();
        _database.ApplyBatch(finalPuts, finalDeletes, sync: true);

        var persistedBlock = new BedrockBlockStore(_database).ReadBlock(targetDimension, targetPosition.BlockX, targetPosition.BlockY, targetPosition.BlockZ);
        if (!persistedBlock.Generated || persistedBlock.Layers.Count == 0)
            throw new InvalidDataException("方块实体迁移后目标方块未能从 LevelDB 读回。");
        var persistedEntityRaw = _database.Get(targetKey) ?? throw new InvalidDataException("方块实体迁移后目标 BlockEntity 记录未能读回。");
        var persistedEntities = ConsecutiveNbtCodec.Decode(persistedEntityRaw);
        if (!persistedEntities.Any(record =>
        {
            var coordinate = BedrockWorldObjectScanner.ExtractPosition(record.Document.Root, BedrockWorldObjectKind.BlockEntity);
            return coordinate?.BlockX == targetPosition.BlockX && coordinate.BlockY == targetPosition.BlockY && coordinate.BlockZ == targetPosition.BlockZ;
        }))
            throw new InvalidDataException("方块实体迁移后目标 NBT 坐标校验失败。");
    }

    private void SaveSingleRecordInPlace(BedrockWorldObject item, NbtDocument edited)
    {
        var key = item.Storage.PrimaryKey;
        var current = _database.Get(key) ?? throw new InvalidDataException("对象记录已经不存在，请重新扫描实体列表。");
        var records = ConsecutiveNbtCodec.Decode(current).ToList();
        var index = Locate(item, records);
        var source = records[index];
        records[index] = source with { Document = edited, RawData = BedrockNbtCodec.Encode(edited, source.Encoding) };
        _database.Put(key, ConsecutiveNbtCodec.Encode(records), sync: true);
    }

    private BedrockWorldObjectCreateResult CreateBlockEntity(string identifier, BedrockWorldObjectPosition position,
        int dimension, BedrockWorldObject? template)
    {
        var chunkX = BedrockWorldObjectScanner.FloorDiv(position.BlockX, 16);
        var chunkZ = BedrockWorldObjectScanner.FloorDiv(position.BlockZ, 16);
        var key = new BedrockDbKey(new ChunkPosition(chunkX, chunkZ, dimension), ChunkRecordType.BlockEntity, null).Encode();
        var original = _database.Get(key);
        var records = original is null ? new List<ConsecutiveNbtRecord>() : ConsecutiveNbtCodec.Decode(original).ToList();
        foreach (var record in records)
        {
            var existing = BedrockWorldObjectScanner.ExtractPosition(record.Document.Root, BedrockWorldObjectKind.BlockEntity);
            if (existing?.BlockX == position.BlockX && existing.BlockY == position.BlockY && existing.BlockZ == position.BlockZ)
                throw new InvalidOperationException("该方块坐标已经存在方块实体。请先编辑或删除原记录。");
        }

        NbtDocument document;
        if (template is null)
        {
            document = new NbtDocument(string.Empty, new NbtCompoundValue([
                new NbtNamedTag("id", new NbtStringValue(identifier)),
                new NbtNamedTag("x", new NbtIntValue(position.BlockX)),
                new NbtNamedTag("y", new NbtIntValue(position.BlockY)),
                new NbtNamedTag("z", new NbtIntValue(position.BlockZ))
            ]));
        }
        else
        {
            var root = NbtDocumentTools.DeepClone(template.Document.Root);
            root = SetTopLevel(root, ["id", "Id", "identifier", "Identifier"], "id", new NbtStringValue(identifier));
            root = SetTopLevel(root, ["x", "X"], "x", new NbtIntValue(position.BlockX));
            root = SetTopLevel(root, ["y", "Y"], "y", new NbtIntValue(position.BlockY));
            root = SetTopLevel(root, ["z", "Z"], "z", new NbtIntValue(position.BlockZ));
            document = new NbtDocument(template.Document.RootName, root);
        }

        var encoding = records.Count > 0 ? records[0].Encoding : template?.Storage.Encoding ?? NbtEncoding.LittleEndian;
        if (records.Any(record => record.Encoding != encoding))
            throw new InvalidDataException("目标 BlockEntity 记录包含混合 NBT 编码，无法安全追加方块实体。");
        records.Add(new ConsecutiveNbtRecord(document, BedrockNbtCodec.Encode(document, encoding), encoding));
        _database.Put(key, ConsecutiveNbtCodec.Encode(records), sync: true);
        return new BedrockWorldObjectCreateResult(BedrockWorldObjectKind.BlockEntity, dimension, chunkX, chunkZ, null,
            BedrockWorldObjectSource.BlockEntity);
    }

    private BedrockWorldObjectCreateResult WriteCreatedEntity(NbtDocument document, BedrockWorldObjectPosition position,
        int dimension, long uniqueId, EntityCreationStorageMode storageMode, NbtEncoding preferredEncoding)
    {
        var chunkX = BedrockWorldObjectScanner.FloorDiv(position.BlockX, 16);
        var chunkZ = BedrockWorldObjectScanner.FloorDiv(position.BlockZ, 16);
        if (storageMode == EntityCreationStorageMode.LegacyChunkEntity)
        {
            var key = new BedrockDbKey(new ChunkPosition(chunkX, chunkZ, dimension), ChunkRecordType.Entity, null).Encode();
            var original = _database.Get(key);
            var records = original is null ? new List<ConsecutiveNbtRecord>() : ConsecutiveNbtCodec.Decode(original).ToList();
            var encoding = records.Count > 0 ? records[0].Encoding : preferredEncoding;
            if (records.Any(record => record.Encoding != encoding))
                throw new InvalidDataException("目标 Entity 记录包含混合 NBT 编码，无法安全追加实体。");
            records.Add(new ConsecutiveNbtRecord(document, BedrockNbtCodec.Encode(document, encoding), encoding));
            _database.Put(key, ConsecutiveNbtCodec.Encode(records), sync: true);
            return new BedrockWorldObjectCreateResult(BedrockWorldObjectKind.Entity, dimension, chunkX, chunkZ, uniqueId,
                BedrockWorldObjectSource.LegacyChunkEntity);
        }

        var reference = ActorReference(uniqueId);
        var actorKey = BedrockWorldObjectScanner.ActorKey(reference);
        if (_database.Get(actorKey) is not null)
            throw new InvalidOperationException("Actor 存储引用与现有 actorprefix 键冲突，请改用其他 UniqueID。");
        var digestKey = FindExistingDigestKey(chunkX, chunkZ, dimension)
            ?? BedrockWorldObjectScanner.DigestKey(chunkX, chunkZ, dimension);
        var digestRaw = _database.Get(digestKey);
        var references = digestRaw is null ? new List<byte[]>() : ParseDigest(digestRaw, "目标 digp");
        if (!references.Any(item => item.AsSpan().SequenceEqual(reference))) references.Add(reference);
        _database.ApplyBatch(
            [
                new WorldDatabasePut(actorKey, BedrockNbtCodec.Encode(document, preferredEncoding)),
                new WorldDatabasePut(digestKey, JoinDigest(references))
            ],
            Array.Empty<byte[]>(), sync: true);
        return new BedrockWorldObjectCreateResult(BedrockWorldObjectKind.Entity, dimension, chunkX, chunkZ, uniqueId,
            BedrockWorldObjectSource.ModernActor);
    }


    private NbtDocument MakeEntityCreationDocument(string identifier, BedrockWorldObjectPosition position, int dimension,
        long uniqueId, NbtDocument? template, EntityCreationStorageMode storageMode)
    {
        NbtValue root;
        string rootName;
        if (template is null)
        {
            rootName = string.Empty;
            var identity = storageMode == EntityCreationStorageMode.LegacyChunkEntity
                ? LegacyIdentityTag(identifier)
                : new NbtNamedTag("identifier", new NbtStringValue(identifier));
            root = new NbtCompoundValue([identity]);
        }
        else
        {
            if (template.Root is not NbtCompoundValue) throw new InvalidDataException("模板 NBT 根不是 Compound。");
            rootName = template.RootName;
            root = NbtDocumentTools.DeepClone(template.Root);
        }

        var previousIdentifier = BedrockEntityCommonNbt.Identifier(root);
        root = BedrockEntityCommonNbt.AddMissingTopLevel(root, BedrockEntityCommonNbt.Tags(identifier, position, dimension, uniqueId));
        root = UpdateEntityIdentity(root, identifier, storageMode);
        root = EnsureDefinition(root, identifier, previousIdentifier);
        root = SetTopLevel(root, ["UniqueID", "UniqueId", "uniqueID", "uniqueId"], "UniqueID", new NbtLongValue(uniqueId));
        root = SetTopLevel(root, ["Pos", "pos", "Position", "position"], "Pos", BedrockEntityCommonNbt.PositionTag(position));
        root = SetTopLevel(root, ["DimensionId", "DimensionID", "dimensionId", "Dimension", "dimension"], "DimensionId", new NbtIntValue(dimension));
        root = SetTopLevel(root, ["LastDimensionId", "lastDimensionId"], "LastDimensionId", new NbtIntValue(dimension));
        return new NbtDocument(rootName, root);
    }

    private static NbtNamedTag LegacyIdentityTag(string identifier)
    {
        var numeric = BedrockEntityCatalog.NumericIdForIdentifier(identifier)
            ?? throw new InvalidOperationException("旧式区块 Entity 需要可转换的数字实体 ID；请从同类旧实体复制，或使用可映射的实体 ID。");
        if (numeric < short.MinValue || numeric > short.MaxValue)
            throw new InvalidOperationException("旧式实体数字 ID 超出 Int16 范围。");
        return new NbtNamedTag("id", new NbtShortValue((short)numeric));
    }

    private static NbtValue UpdateEntityIdentity(NbtValue root, string identifier, EntityCreationStorageMode storageMode)
    {
        if (root is not NbtCompoundValue compound) throw new InvalidDataException("实体 NBT 根必须是 Compound。");
        var tags = compound.Tags.Select(tag => new NbtNamedTag(tag.Name, NbtDocumentTools.DeepClone(tag.Value))).ToList();
        if (storageMode == EntityCreationStorageMode.ModernActor)
        {
            var index = tags.FindIndex(tag => string.Equals(tag.Name, "identifier", StringComparison.OrdinalIgnoreCase));
            var replacement = new NbtNamedTag(index >= 0 ? tags[index].Name : "identifier", new NbtStringValue(identifier));
            if (index >= 0) tags[index] = replacement;
            else tags.Add(replacement);
        }
        else
        {
            var numeric = BedrockEntityCatalog.NumericIdForIdentifier(identifier)
                ?? throw new InvalidOperationException("旧式区块 Entity 需要可转换的数字实体 ID。");
            var index = tags.FindIndex(tag => string.Equals(tag.Name, "id", StringComparison.OrdinalIgnoreCase));
            NbtValue value = index >= 0 ? NumericEntityIdValue(numeric, tags[index].Value) : new NbtShortValue((short)numeric);
            var replacement = new NbtNamedTag(index >= 0 ? tags[index].Name : "id", value);
            if (index >= 0) tags[index] = replacement;
            else tags.Add(replacement);
            var identifierIndex = tags.FindIndex(tag => string.Equals(tag.Name, "identifier", StringComparison.OrdinalIgnoreCase));
            if (identifierIndex >= 0)
                tags[identifierIndex] = new NbtNamedTag(tags[identifierIndex].Name, new NbtStringValue(identifier));
        }
        return new NbtCompoundValue(tags);
    }

    private static NbtValue NumericEntityIdValue(long value, NbtValue preserving)
        => preserving switch
        {
            NbtByteValue when value >= sbyte.MinValue && value <= sbyte.MaxValue => new NbtByteValue((sbyte)value),
            NbtShortValue when value >= short.MinValue && value <= short.MaxValue => new NbtShortValue((short)value),
            NbtIntValue when value >= int.MinValue && value <= int.MaxValue => new NbtIntValue((int)value),
            NbtLongValue => new NbtLongValue(value),
            _ when value >= short.MinValue && value <= short.MaxValue => new NbtShortValue((short)value),
            _ => new NbtLongValue(value)
        };

    private static NbtValue EnsureDefinition(NbtValue root, string identifier, string? previousIdentifier)
    {
        if (root is not NbtCompoundValue compound) return root;
        var tags = compound.Tags.Select(tag => new NbtNamedTag(tag.Name, NbtDocumentTools.DeepClone(tag.Value))).ToList();
        var index = tags.FindIndex(tag => string.Equals(tag.Name, "definitions", StringComparison.OrdinalIgnoreCase));
        var target = "+" + identifier;
        if (index < 0)
        {
            tags.Add(new NbtNamedTag("definitions", new NbtListValue(NbtTagType.String, [new NbtStringValue(target)])));
            return new NbtCompoundValue(tags);
        }
        if (tags[index].Value is not NbtListValue list || (list.ElementType != NbtTagType.String && list.Values.Count > 0))
            return new NbtCompoundValue(tags);

        var previousDefinition = string.IsNullOrWhiteSpace(previousIdentifier) ? null : "+" + previousIdentifier;
        var values = new List<NbtValue>();
        var includedTarget = false;
        foreach (var value in list.Values)
        {
            if (value is NbtStringValue text)
            {
                if (string.Equals(text.Value, target, StringComparison.OrdinalIgnoreCase))
                {
                    if (!includedTarget) values.Add(new NbtStringValue(target));
                    includedTarget = true;
                    continue;
                }
                if (previousDefinition is not null
                    && !string.Equals(previousDefinition, target, StringComparison.OrdinalIgnoreCase)
                    && string.Equals(text.Value, previousDefinition, StringComparison.OrdinalIgnoreCase))
                    continue;
            }
            values.Add(NbtDocumentTools.DeepClone(value));
        }
        if (!includedTarget) values.Insert(0, new NbtStringValue(target));
        tags[index] = new NbtNamedTag(tags[index].Name, new NbtListValue(NbtTagType.String, values));
        return new NbtCompoundValue(tags);
    }

    private EntityCreationStorageMode PreferredEntityCreationStorage(BedrockWorldObject? template, int chunkX, int chunkZ, int dimension)
    {
        if (template?.Source == BedrockWorldObjectSource.LegacyChunkEntity) return EntityCreationStorageMode.LegacyChunkEntity;

        var entries = _database.Entries(includeValues: false).ToArray();
        if (entries.Any(entry => BedrockDbKey.TryParse(entry.Key, out var parsed) && parsed.RecordType == ChunkRecordType.ActorDigestVersion))
            return EntityCreationStorageMode.ModernActor;

        var legacyKey = new BedrockDbKey(new ChunkPosition(chunkX, chunkZ, dimension), ChunkRecordType.Entity, null).Encode();
        if (_database.Get(legacyKey) is not null || entries.Any(entry =>
                BedrockDbKey.TryParse(entry.Key, out var parsed) && parsed.RecordType == ChunkRecordType.Entity))
            return EntityCreationStorageMode.LegacyChunkEntity;

        var targetDigest = FindExistingDigestKey(chunkX, chunkZ, dimension);
        if (targetDigest is not null && _database.Get(targetDigest) is { } digest && DigestContainsExistingActor(digest))
            return EntityCreationStorageMode.ModernActor;
        if (template?.Source == BedrockWorldObjectSource.ModernActor) return EntityCreationStorageMode.ModernActor;
        return EntityCreationStorageMode.ModernActor;
    }

    private bool DigestContainsExistingActor(byte[] digest)
    {
        if ((digest.Length & 7) != 0) return false;
        foreach (var reference in ParseDigest(digest, "digp"))
            if (_database.Get(BedrockWorldObjectScanner.ActorKey(reference)) is not null) return true;
        return false;
    }

    private void EnsureUniqueIdAvailable(long uniqueId)
    {
        if (!IsEntityUniqueIdAvailable(uniqueId))
            throw new InvalidOperationException($"UniqueID {uniqueId} 已被其他实体占用。");
    }

    private bool IsEntityUniqueIdAvailable(long uniqueId)
    {
        var actorPrefix = Encoding.ASCII.GetBytes("actorprefix");
        foreach (var entry in _database.Entries(actorPrefix, includeValues: true))
        {
            if (entry.Value is null) continue;
            IReadOnlyList<ConsecutiveNbtRecord> records;
            try { records = ConsecutiveNbtCodec.Decode(entry.Value); }
            catch { continue; }
            if (records.Any(record => BedrockEntityCommonNbt.UniqueId(record.Document.Root) == uniqueId)) return false;
        }

        foreach (var entry in _database.Entries(includeValues: false))
        {
            if (!BedrockDbKey.TryParse(entry.Key, out var parsed) || parsed.RecordType != ChunkRecordType.Entity) continue;
            var data = _database.Get(entry.Key);
            if (data is null) continue;
            IReadOnlyList<ConsecutiveNbtRecord> records;
            try { records = ConsecutiveNbtCodec.Decode(data); }
            catch { continue; }
            if (records.Any(record => BedrockEntityCommonNbt.UniqueId(record.Document.Root) == uniqueId)) return false;
        }
        return true;
    }

    private static void ValidateBlockEntityPosition(BedrockWorldObjectPosition position)
    {
        if (!double.IsFinite(position.X) || !double.IsFinite(position.Y) || !double.IsFinite(position.Z)
            || position.X != Math.Truncate(position.X)
            || position.Y != Math.Truncate(position.Y)
            || position.Z != Math.Truncate(position.Z)
            || position.X < int.MinValue || position.X > int.MaxValue
            || position.Y < int.MinValue || position.Y > int.MaxValue
            || position.Z < int.MinValue || position.Z > int.MaxValue)
            throw new InvalidDataException("方块实体 x/y/z 必须是 Int32 范围内的整数坐标。");
    }

    private static void ValidatePosition(BedrockWorldObjectPosition position)
    {
        if (!double.IsFinite(position.X) || !double.IsFinite(position.Y) || !double.IsFinite(position.Z)
            || position.X < -float.MaxValue || position.X > float.MaxValue
            || position.Y < -float.MaxValue || position.Y > float.MaxValue
            || position.Z < -float.MaxValue || position.Z > float.MaxValue)
            throw new InvalidDataException("实体坐标必须是可写入 Float 的有限数字。");
    }

    private static byte[] ActorReference(long uniqueId)
    {
        var reference = new byte[8];
        BinaryPrimitives.WriteInt64LittleEndian(reference, uniqueId);
        return reference;
    }

    private static NbtValue SetTopLevel(NbtValue root, IReadOnlyList<string> names, string preferredName, NbtValue value)
    {
        if (root is not NbtCompoundValue compound) throw new InvalidDataException("NBT 根必须是 Compound。");
        var tags = compound.Tags.Select(tag => new NbtNamedTag(tag.Name, NbtDocumentTools.DeepClone(tag.Value))).ToList();
        var index = tags.FindIndex(tag => names.Any(name => string.Equals(tag.Name, name, StringComparison.OrdinalIgnoreCase)));
        var replacement = new NbtNamedTag(index >= 0 ? tags[index].Name : preferredName, NbtDocumentTools.DeepClone(value));
        if (index >= 0) tags[index] = replacement;
        else tags.Add(replacement);
        return new NbtCompoundValue(tags);
    }

    private static IReadOnlyList<WorldDatabasePut> CoalescePuts(IEnumerable<WorldDatabasePut> puts)
        => puts.GroupBy(item => Convert.ToHexString(item.Key), StringComparer.Ordinal)
            .Select(group => group.Last()).ToArray();

    private static IReadOnlyList<byte[]> DistinctKeys(IEnumerable<byte[]> keys)
        => keys.GroupBy(key => Convert.ToHexString(key), StringComparer.Ordinal).Select(group => group.First()).ToArray();

    private byte[]? FindExistingDigestKey(int x, int z, int dimension)
    {
        var key = BedrockWorldObjectScanner.DigestKey(x, z, dimension);
        return _database.Get(key) is null ? null : key;
    }

    private static List<byte[]> ParseDigest(byte[] data, string label)
    {
        if ((data.Length & 7) != 0) throw new InvalidDataException($"{label} 长度 {data.Length} 不是 8 的倍数。");
        var result = new List<byte[]>(data.Length / 8);
        for (var offset = 0; offset < data.Length; offset += 8) result.Add(data.AsSpan(offset, 8).ToArray());
        return result;
    }

    private static byte[] JoinDigest(IReadOnlyList<byte[]> references)
    {
        var result = new byte[checked(references.Count * 8)];
        for (var index = 0; index < references.Count; index++)
        {
            if (references[index].Length != 8) throw new InvalidDataException("Actor storage reference must be 8 bytes.");
            references[index].CopyTo(result, index * 8);
        }
        return result;
    }

    private static int Locate(BedrockWorldObject item, IReadOnlyList<ConsecutiveNbtRecord> records)
    {
        var preferred = item.Storage.RecordIndex;
        if (preferred >= 0 && preferred < records.Count && records[preferred].RawData.SequenceEqual(item.RawData)) return preferred;

        if (item.UniqueId is long uniqueId)
        {
            for (var index = 0; index < records.Count; index++)
                if (records[index].Document.Root.CompoundValueIgnoreCase("UniqueID", "UniqueId", "uniqueID", "uniqueId")?.IntegerValue() == uniqueId) return index;
        }
        if (item.Position is { } position)
        {
            for (var index = 0; index < records.Count; index++)
            {
                var candidate = BedrockWorldObjectScanner.ExtractPosition(records[index].Document.Root, item.Kind);
                if (candidate?.BlockX == position.BlockX && candidate.BlockY == position.BlockY && candidate.BlockZ == position.BlockZ) return index;
            }
        }
        throw new InvalidDataException("对象记录已经变化，无法确认要修改的 NBT。请重新扫描后再编辑。");
    }
}
