import Foundation
import UIKit

/// Loads user-provided block colour overrides from the app's shared
/// Documents/Textures directory.
///
/// PNG filenames use an iOS-safe identifier form. The first underscore is
/// converted to the Bedrock namespace separator, so `minecraft_bedrock.png`
/// targets `minecraft:bedrock`. The old colon-in-filename form is deliberately
/// unsupported.
///
/// `colors.txt` uses the normal Bedrock identifier form, one entry per line:
/// `minecraft:bedrock #808080`. Valid text entries have higher priority than
/// PNG files, and later duplicate text entries replace earlier ones.
enum BlockTextureOverrideStore {
    private static let lock = NSLock()
    private static var colors: [String: UInt32] = [:]
    private static var revisionValue: UInt64 = 0

    private static let readMeFilename = "ReadMe.txt"
    private static let colorsFilename = "colors.txt"

    static var revision: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return revisionValue
    }

    static var texturesDirectoryURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Textures", isDirectory: true)
    }

    /// Ensures the shared folder exists, restores the fixed ReadMe and refreshes
    /// all overrides. Safe to call on every launch / foreground activation.
    static func prepareSharedDirectoryAndReload() {
        guard let directory = texturesDirectoryURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: nil
            )
            try writeReadMe(in: directory)
        } catch {
            return
        }
        reload(from: directory)
    }

    static func rgbHex(for identifier: String) -> UInt32? {
        let key = BedrockBlockIdentifier.normalized(identifier)
        lock.lock()
        defer { lock.unlock() }
        return colors[key]
    }

    private static func reload(from directory: URL) {
        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            return
        }

        // PNG overrides are loaded first. Any valid colors.txt entry for the
        // same identifier is applied afterwards and therefore completely wins.
        var loaded: [String: UInt32] = [:]
        for url in urls where url.pathExtension.lowercased() == "png" {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true else { continue }
            let stem = url.deletingPathExtension().lastPathComponent
            guard let identifier = identifierFromPNGStem(stem),
                  let color = averageRGB(ofPNGAt: url) else { continue }
            loaded[identifier] = color
        }

        let colorsURL = directory.appendingPathComponent(colorsFilename, isDirectory: false)
        if let textColors = parseColorsFile(at: colorsURL) {
            for (identifier, color) in textColors {
                loaded[identifier] = color
            }
        }

        lock.lock()
        if loaded != colors {
            colors = loaded
            revisionValue &+= 1
        }
        lock.unlock()
    }

    /// Converts only the first underscore to `:`. For example:
    /// `minecraft_polished_blackstone` -> `minecraft:polished_blackstone`.
    /// Filenames already containing `:` are rejected so the former
    /// `minecraft:bedrock.png` convention is no longer supported.
    private static func identifierFromPNGStem(_ stem: String) -> String? {
        let trimmed = stem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(":"),
              let underscore = trimmed.firstIndex(of: "_") else { return nil }

        let namespace = String(trimmed[..<underscore])
        let pathStart = trimmed.index(after: underscore)
        let path = String(trimmed[pathStart...])
        guard isValidIdentifier(namespace: namespace, path: path) else { return nil }
        return BedrockBlockIdentifier.normalized("\(namespace):\(path)")
    }

    /// Parses `colors.txt` as `identifier #RRGGBB`, one entry per line.
    /// Invalid lines are ignored. Assignment is intentionally sequential so
    /// the last valid occurrence of a duplicated identifier wins.
    private static func parseColorsFile(at url: URL) -> [String: UInt32]? {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return nil }

        var result: [String: UInt32] = [:]
        text.enumerateLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }

            let fields = trimmed.split(whereSeparator: { $0.isWhitespace })
            guard fields.count == 2 else { return }

            let identifierText = String(fields[0])
            let colorText = String(fields[1])
            guard let colon = identifierText.firstIndex(of: ":"),
                  identifierText[identifierText.index(after: colon)...].firstIndex(of: ":") == nil
            else { return }

            let namespace = String(identifierText[..<colon])
            let pathStart = identifierText.index(after: colon)
            let blockPath = String(identifierText[pathStart...])
            guard isValidIdentifier(namespace: namespace, path: blockPath),
                  let color = parseRGBHex(colorText) else { return }

            result[BedrockBlockIdentifier.normalized(identifierText)] = color
        }
        return result
    }

    private static func isValidIdentifier(namespace: String, path: String) -> Bool {
        guard !namespace.isEmpty, !path.isEmpty else { return false }
        let namespaceAllowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789._-")
        let pathAllowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789._-/")
        return namespace.lowercased().unicodeScalars.allSatisfy { namespaceAllowed.contains($0) }
            && path.lowercased().unicodeScalars.allSatisfy { pathAllowed.contains($0) }
    }

    private static func parseRGBHex(_ text: String) -> UInt32? {
        guard text.count == 7, text.first == "#" else { return nil }
        let digits = String(text.dropFirst())
        guard digits.unicodeScalars.allSatisfy({
            CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0)
        }) else { return nil }
        return UInt32(digits, radix: 16)
    }

    /// The Textures ReadMe is a fixed text resource embedded in this build and
    /// is intentionally restored verbatim on every launch / activation.
    private static let readMeText = """
MCBEEditor Textures 文件夹说明

此目录用于覆盖地图中方块的默认显示颜色。

1. PNG 覆盖
文件名必须使用 iOS 兼容格式：命名空间_方块名.png。
程序只把文件名中的第一个下划线转换为冒号。
例如：
minecraft_bedrock.png -> minecraft:bedrock
minecraft_polished_blackstone.png -> minecraft:polished_blackstone
文件名中直接使用冒号的格式（如 minecraft:bedrock.png）不受支持。
PNG 的可见像素会被计算为一个代表颜色，用于覆盖该方块显示颜色。

2. colors.txt 覆盖
colors.txt 每行格式必须为：
minecraft:bedrock #808080
即：完整冒号格式方块 ID + 空格 + #RRGGBB 六位十六进制颜色。
一行只能包含一个条目。空行会忽略，格式错误的行会忽略。
同一方块出现多次时，以最后一个有效条目为准。

3. 优先级
colors.txt 有效条目 > 对应 PNG > MCBEEditor 内置方块颜色。
如果 colors.txt 中存在某方块的有效条目，则忽略该方块对应 PNG 的颜色。

修改 PNG 或 colors.txt 后返回 MCBEEditor 并重新渲染地图即可刷新。

注意：本 ReadMe.txt 由 MCBEEditor 自动生成，并会在程序启动/重新激活时恢复为默认内容。
"""

    private static func writeReadMe(in directory: URL) throws {
        let url = directory.appendingPathComponent(readMeFilename, isDirectory: false)
        try Data(readMeText.utf8).write(to: url, options: .atomic)
    }

    private static func averageRGB(ofPNGAt url: URL) -> UInt32? {
        guard let image = UIImage(contentsOfFile: url.path), let cgImage = image.cgImage else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        return pixel.withUnsafeMutableBytes { rawBuffer -> UInt32? in
            guard let baseAddress = rawBuffer.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: 1,
                    height: 1,
                    bitsPerComponent: 8,
                    bytesPerRow: 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { return nil }

            context.interpolationQuality = .high
            context.setBlendMode(.copy)
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))

            let bytes = rawBuffer.bindMemory(to: UInt8.self)
            let alpha = Int(bytes[3])
            guard alpha > 0 else { return nil }
            // CGContext stores premultiplied RGB. Unpremultiply the 1x1 sample so
            // transparent texels do not artificially darken the visible colour.
            let red = min(255, Int(bytes[0]) * 255 / alpha)
            let green = min(255, Int(bytes[1]) * 255 / alpha)
            let blue = min(255, Int(bytes[2]) * 255 / alpha)
            return UInt32(red << 16 | green << 8 | blue)
        }
    }
}
