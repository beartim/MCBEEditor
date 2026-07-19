import Foundation

enum MCBEEditorError: LocalizedError {
    case invalidWorld(String)
    case invalidArchive(String)
    case unsupported(String)
    case malformedData(String)
    case io(String)
    case database(String)

    var errorDescription: String? {
        switch self {
        case .invalidWorld(let message): return "无效的 Bedrock 世界：\(message)"
        case .invalidArchive(let message): return "无效的 mcworld 压缩包：\(message)"
        case .unsupported(let message): return "暂不支持：\(message)"
        case .malformedData(let message): return "数据格式错误：\(message)"
        case .io(let message): return "文件操作失败：\(message)"
        case .database(let message): return "LevelDB 错误：\(message)"
        }
    }
}
