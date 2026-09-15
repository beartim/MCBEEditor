using MCBEEditor.Core.Chunk;
using MCBEEditor.Core.World;
using MCBEEditor.Desktop;

namespace MCBEEditor.Cli;

/// <summary>Headless dispatch over the same stores used by the Windows command tab.</summary>
internal sealed class CliWorldCommandExecutor(WorldDocument document)
{
    public CliCommandResult Execute(object command)
    {
        CliCommandPolicy.RequireExecutable(command);
        if (command is CliStructureFileRequest structureFile) return CliStructureFileCommand.Execute(structureFile, document);
        if (command is HelpCliCommand help)
        {
            if (help.Command is null) return CliCommandResult.Text(CommandHelpCatalog.AllUsageText);
            if (!CommandHelpCatalog.TryGetUsage(help.Command, out var usage))
                throw new InvalidDataException($"不存在的命令：{help.Command}");
            return CliCommandResult.Text(usage);
        }
        if (command is InfoStorageBiomeCommandRequest)
            return new CliCommandResult(false, new WorldInfoService().Inspect(document)
                .Select(row => new CliOutputLine($"{row.Title}={row.Value}", CliOutputKind.Success)).ToArray());
        if (command is SetWorldSpawnTargetingCommandRequest worldSpawn)
            return CliCommandResult.Text(TargetingCommandStore.SetWorldSpawn(document, worldSpawn.Position), true);

        // Every handle is closed before the next command or archive export.
        using var database = document.OpenDatabase(readOnly: !CliCommandPolicy.MayMutate(command));
        return command switch
        {
            GetBlockCommandRequest get => GetBlock(database, get),
            SetBlockCommandRequest set => BlockMutation(new BedrockRegionBlockStore(database)
                .SetBlock(set.Dimension, set.Position, set.Storages)),
            FillBlockCommandRequest fill => BlockMutation(new BedrockRegionBlockStore(database)
                .Fill(fill.Dimension, fill.Region, fill.Storages)),
            CloneBlockCommandRequest clone => BlockMutation(new BedrockRegionBlockStore(database)
                .Clone(clone.SourceDimension, clone.Source, clone.TargetDimension, clone.Destination)),

            StorageQueryStorageBiomeCommandRequest query => StorageQuery(database, query),
            StorageSetStorageBiomeCommandRequest set => StorageMutation(new BedrockStorageCommandStore(database)
                .Set(set.Dimension, set.Position, set.Layer, set.Block)),
            StorageDeleteStorageBiomeCommandRequest delete => StorageMutation(new BedrockStorageCommandStore(database)
                .Delete(delete.Dimension, delete.Position, delete.Layer)),
            StorageClearStorageBiomeCommandRequest clear => StorageMutation(new BedrockStorageCommandStore(database)
                .Clear(clear.Dimension, clear.Position, clear.KeepThroughLayer)),
            FillBiomeStorageBiomeCommandRequest biome => FillBiome(database, biome),

            SpawnPointTargetingCommandRequest spawn => CliCommandResult.FromCore(new TargetingCommandStore(database).SpawnPoint(spawn)),
            ClearSpawnPointTargetingCommandRequest clear => CliCommandResult.FromCore(new TargetingCommandStore(database).ClearSpawnPoint(clear)),
            TeleportTargetingCommandRequest teleport => CliCommandResult.FromCore(new TargetingCommandStore(database).Teleport(teleport)),
            SpreadTargetingCommandRequest spread => CliCommandResult.FromCore(new TargetingCommandStore(database).Spread(spread)),
            ExperienceTargetingCommandRequest experience => CliCommandResult.FromCore(new TargetingCommandStore(database).Experience(experience)),

            ClearEntityActionCommandRequest clear => CliCommandResult.FromCore(new EntityActionCommandStore(database).Clear(clear)),
            GiveEntityActionCommandRequest give => CliCommandResult.FromCore(new EntityActionCommandStore(database).Give(give)),
            KillEntityActionCommandRequest kill => CliCommandResult.FromCore(new EntityActionCommandStore(database).Kill(kill)),
            KickEntityActionCommandRequest kick => CliCommandResult.FromCore(new EntityActionCommandStore(database).Kick(kick)),
            SummonEntityActionCommandRequest summon => CliCommandResult.FromCore(new EntityActionCommandStore(database).Summon(summon)),
            EffectEntityActionCommandRequest effect => CliCommandResult.FromCore(new EntityActionCommandStore(database).Effect(effect)),

            EnvironmentCommandRequest environment => CliCommandResult.FromCore(new EnvironmentCommandStore(document, database).Execute(environment)),
            StructureTemplateStructureCommandRequest structure => CliCommandResult.FromCore(new StructureTemplateCommandStore(database).Execute(structure)),
            ChunkCommandRequest chunk => Chunk(database, chunk),
            _ => throw new InvalidOperationException("无法执行未注册的 CLI 命令。")
        };
    }

    private static CliCommandResult GetBlock(IWorldDatabase database, GetBlockCommandRequest request)
    {
        var text = new BedrockRegionBlockStore(database).GetBlockText(request.Dimension, request.Position);
        return new CliCommandResult(false, text.Split('\n').Select(line => new CliOutputLine(line,
            line.StartsWith("BlockEntity=", StringComparison.Ordinal) ? CliOutputKind.BlockEntity : CliOutputKind.Block)).ToArray());
    }

    private static CliCommandResult BlockMutation(BedrockRegionMutationResult result)
    {
        var entities = result.CopiedBlockEntities > 0 || result.RemovedBlockEntities > 0
            ? $"；BlockEntity 删除 {result.RemovedBlockEntities}、复制 {result.CopiedBlockEntities}" : string.Empty;
        return CliCommandResult.Text(
            $"完成：处理 {result.ChangedBlockPositions:N0} 个方块位置，写入 {result.TouchedSubChunks:N0} 个 SubChunk / {result.TouchedChunks:N0} 个区块；WriteBatch 项 Put={result.PutCount}, Delete={result.DeleteCount}{entities}。",
            result.PutCount > 0 || result.DeleteCount > 0);
    }

    private static CliCommandResult StorageQuery(IWorldDatabase database, StorageQueryStorageBiomeCommandRequest request)
        => new(false, new BedrockStorageCommandStore(database).Query(request.Dimension, request.Position)
            .Select(line => new CliOutputLine(line, line == "Block not generated" ? CliOutputKind.Success : CliOutputKind.Block)).ToArray());

    private static CliCommandResult StorageMutation(BedrockStorageMutationResult result)
        => CliCommandResult.Text(result.Message, result.PutCount > 0);

    private static CliCommandResult FillBiome(IWorldDatabase database, FillBiomeStorageBiomeCommandRequest request)
    {
        var result = new BedrockBiomeRegionStore(database).FillBiome(request.Dimension, request.Region, request.BiomeId);
        return CliCommandResult.Text(
            $"fillbiome 完成：ID {request.BiomeDisplayText}，修改 {result.ChangedChunkCount:N0} 个区块、{result.ChangedCellCount:N0} 个生物群系位置；跳过 {result.SkippedChunkCount:N0} 个无记录区块；WriteBatch Put={result.PutCount:N0}。",
            result.PutCount > 0);
    }

    private static CliCommandResult Chunk(IWorldDatabase database, ChunkCommandRequest request)
    {
        var store = new BedrockChunkStore(database);
        if (request.Kind == ChunkCommandKind.Query)
        {
            IReadOnlyList<BedrockChunkSummary> summaries;
            if (request.Dimension.HasValue && request.X.HasValue && request.Z.HasValue)
                summaries = [store.SummaryAt(new ChunkPosition(request.X.Value, request.Z.Value, request.Dimension.Value))];
            else
            {
                var dimensions = request.Dimension.HasValue ? new[] { request.Dimension.Value } : new[] { 0, 1, 2 };
                var order = dimensions.Select((value, index) => (value, index)).ToDictionary(item => item.value, item => item.index);
                summaries = store.ListChunks().Where(item => order.ContainsKey(item.Position.Dimension))
                    .OrderBy(item => order[item.Position.Dimension]).ThenBy(item => item.Position.Z).ThenBy(item => item.Position.X).ToArray();
            }
            return summaries.Count == 0
                ? CliCommandResult.Text("chunk query：没有匹配的已加载区块。", kind: CliOutputKind.Chunk)
                : new CliCommandResult(false, summaries.Select(summary => new CliOutputLine(store.QueryText(summary), CliOutputKind.Chunk)).ToArray());
        }
        var position = new ChunkPosition(request.X!.Value, request.Z!.Value, request.Dimension!.Value);
        var dimension = ChunkCommandParser.DimensionName(position.Dimension);
        if (request.Kind == ChunkCommandKind.Empty)
        {
            var result = store.ClearChunk(position);
            var digests = result.DeletedDigestCount > 0 ? $"、{result.DeletedDigestCount} 条 digp" : string.Empty;
            var actors = result.DeletedActorCount > 0 ? $"、{result.DeletedActorCount} 个 Actor" : string.Empty;
            var metadata = result.VersionRecordType == ChunkRecordType.LegacyTerrain ? "LegacyTerrain 空列"
                : $"{result.VersionRecordType.DisplayName()} + FinalizedState=2";
            return CliCommandResult.Text($"chunk empty 完成：{dimension} ({position.X}, {position.Z})，删除 {result.DeletedChunkRecordCount} 条旧区块记录{digests}{actors}，创建 {result.CreatedMetadataRecordCount} 条纯空气区块元数据（{metadata}）。", true);
        }
        if (request.Kind == ChunkCommandKind.Regenerate)
        {
            var result = store.RegenerateChunk(position);
            var digests = result.DeletedDigestCount > 0 ? $"、{result.DeletedDigestCount} 条 digp" : string.Empty;
            var actors = result.DeletedActorCount > 0 ? $"、{result.DeletedActorCount} 个 Actor" : string.Empty;
            return CliCommandResult.Text($"chunk regenerate 完成：{dimension} ({position.X}, {position.Z})，完整移除 {result.DeletedChunkRecordCount} 条区块记录{digests}{actors}；Minecraft 下次加载时会按种子重新生成。",
                result.DeletedChunkRecordCount > 0 || result.DeletedDigestCount > 0 || result.DeletedActorCount > 0);
        }
        throw new InvalidOperationException("未知 chunk 操作。");
    }
}
