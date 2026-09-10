import Foundation
import CoreGraphics
import ImageIO

/// Loads user-provided block colour overrides from the app's shared
/// Documents/Textures directory.
///
/// PNG filenames use an iOS-safe identifier form. The first underscore is
/// converted to the Bedrock namespace separator, so `minecraft_bedrock.png`
/// targets `minecraft:bedrock`. The old colon-in-filename form is deliberately
/// unsupported.
///
/// `Colors.txt` uses the normal Bedrock identifier form, one entry per line:
/// `minecraft:bedrock #808080`. Valid text entries have higher priority than
/// PNG files, and later duplicate text entries replace earlier ones.
enum BlockTextureOverrideStore {
    private static let lock = NSLock()
    private static var colors: [String: UInt32] = [:]
    private static var revisionValue: UInt64 = 0

    private static let readMeFilename = "ReadMe.txt"
    private static let colorsFilename = "Colors.txt"

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

    static func reload(from directory: URL) {
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

        // Text entries win without decoding PNGs whose colour would be discarded.
        let colorsURL = directory.appendingPathComponent(colorsFilename, isDirectory: false)
        let textColors = parseColorsFile(at: colorsURL) ?? [:]
        var loaded = textColors
        let orderedURLs = urls.sorted { $0.lastPathComponent < $1.lastPathComponent }
        for url in orderedURLs where url.pathExtension.lowercased() == "png" {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true else { continue }
            let stem = url.deletingPathExtension().lastPathComponent
            guard let identifier = identifierFromPNGStem(stem), textColors[identifier] == nil,
                  let color = averageRGB(ofPNGAt: url) else { continue }
            loaded[identifier] = color
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

    /// Parses `Colors.txt` as `identifier #RRGGBB`, one entry per line.
    /// Invalid lines are ignored. Assignment is intentionally sequential so
    /// the last valid occurrence of a duplicated identifier wins.
    private static func parseColorsFile(at url: URL) -> [String: UInt32]? {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return nil }

        return parseColorsText(text)
    }

    static func parseColorsText(_ text: String) -> [String: UInt32] {
        let source = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
        var result: [String: UInt32] = [:]
        source.enumerateLines { line, _ in
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

2. Colors.txt 覆盖
Colors.txt 每行格式必须为：
minecraft:bedrock #808080
即：完整冒号格式方块 ID + 空格 + #RRGGBB 六位十六进制颜色。
一行只能包含一个条目。空行会忽略，格式错误的行会忽略。
同一方块出现多次时，以最后一个有效条目为准。

3. 优先级
Colors.txt 有效条目 > 对应 PNG > MCBEEditor 内置方块颜色。
如果 Colors.txt 中存在某方块的有效条目，则忽略该方块对应 PNG 的颜色。

修改 PNG 或 Colors.txt 后返回 MCBEEditor 并重新渲染地图即可刷新。

注意：本 ReadMe.txt 由 MCBEEditor 自动生成，并会在程序启动/重新激活时恢复为默认内容。
"""

    private static func writeReadMe(in directory: URL) throws {
        let url = directory.appendingPathComponent(readMeFilename, isDirectory: false)
        try Data(readMeText.utf8).write(to: url, options: .atomic)
    }

    private static func averageRGB(ofPNGAt url: URL) -> UInt32? {
        // Decode a bounded thumbnail: opening a large external texture should
        // not allocate its full-resolution bitmap merely to obtain one colour.
        guard let source = CGImageSourceCreateWithURL(
            url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary
        ), let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 64,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary) else { return nil }

        let width = image.width
        let height = image.height
        guard width > 0, height > 0, width <= 64, height <= 64 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        return pixels.withUnsafeMutableBytes { rawBuffer -> UInt32? in
            guard let baseAddress = rawBuffer.baseAddress,
                  let context = CGContext(
                    data: baseAddress, width: width, height: height,
                    bitsPerComponent: 8, bytesPerRow: width * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { return nil }
            context.setBlendMode(.copy)
            context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))

            let bytes = rawBuffer.bindMemory(to: UInt8.self)
            var red = 0, green = 0, blue = 0, alpha = 0
            for offset in stride(from: 0, to: bytes.count, by: 4) {
                red += Int(bytes[offset])
                green += Int(bytes[offset + 1])
                blue += Int(bytes[offset + 2])
                alpha += Int(bytes[offset + 3])
            }
            guard alpha > 0 else { return nil }
            // Average all premultiplied samples, then unpremultiply once. Fully
            // transparent pixels contribute no colour and cannot darken it.
            let r = min(255, (red * 255 + alpha / 2) / alpha)
            let g = min(255, (green * 255 + alpha / 2) / alpha)
            let b = min(255, (blue * 255 + alpha / 2) / alpha)
            return UInt32(r << 16 | g << 8 | b)
        }
    }
}
