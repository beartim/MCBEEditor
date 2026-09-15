using MCBEEditor.Core.Chunk;

namespace MCBEEditor.Cli;

internal static class CliCommandPolicy
{
    public static bool MayMutate(object command) => command switch
    {
        CliStructureFileRequest file => file.Core.Operation == StructureTemplateStructureOperationKind.Import,
        HelpCliCommand => false,
        GetBlockCommandRequest => false,
        BlockCommandRequest => true,
        StorageBiomeCommandRequest request => request.IsDestructive,
        TargetingCommandRequest request => request.IsDestructive,
        EntityActionCommandRequest => true,
        EnvironmentCommandRequest request => request.IsDestructive,
        StructureTemplateStructureCommandRequest request => request.IsDestructive,
        ChunkCommandRequest request => request.IsDestructive,
        _ => throw new InvalidOperationException("未注册的 CLI 命令请求。")
    };

    public static void RequireExecutable(object command)
    {
        if (command is CliStructureFileRequest) return;
        if (command is StructureTemplateStructureCommandRequest
            { Operation: StructureTemplateStructureOperationKind.Import or StructureTemplateStructureOperationKind.Export })
            throw new CliInputException("structure import/export 执行时必须使用 CLI 的 --file 路径接口。");
        _ = MayMutate(command);
    }
}
