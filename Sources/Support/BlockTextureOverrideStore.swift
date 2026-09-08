import Foundation
import UIKit

/// Loads user-provided PNG textures from the app's shared Documents/Textures directory.
///
/// A file named with the complete Bedrock identifier, for example
/// `minecraft:bedrock.png`, overrides the built-in map colour for that block.
/// The visible PNG pixels are downsampled to one alpha-weighted RGB colour so
/// the override works consistently in both 1-pixel-per-block map rendering and
/// X/Z cross sections.
enum BlockTextureOverrideStore {
    private static let lock = NSLock()
    private static var colors: [String: UInt32] = [:]
    private static var revisionValue: UInt64 = 0

    static var revision: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return revisionValue
    }

    static var texturesDirectoryURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Textures", isDirectory: true)
    }

    /// Ensures the shared folder exists and refreshes all overrides.
    /// Safe to call on every launch / foreground activation.
    static func prepareSharedDirectoryAndReload() {
        guard let directory = texturesDirectoryURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: nil
            )
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

        var loaded: [String: UInt32] = [:]
        for url in urls where url.pathExtension.lowercased() == "png" {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true else { continue }
            let stem = url.deletingPathExtension().lastPathComponent
            let identifier = BedrockBlockIdentifier.normalized(stem)
            guard !identifier.isEmpty, let color = averageRGB(ofPNGAt: url) else { continue }
            loaded[identifier] = color
        }

        lock.lock()
        if loaded != colors {
            colors = loaded
            revisionValue &+= 1
        }
        lock.unlock()
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
