import UIKit

/// Small, iOS 13-compatible NBT type badges shown to the left of every NBT node.
/// The badge is rendered locally so the UI does not depend on symbols introduced
/// by newer iOS releases.
enum NBTTagIcon {
    private static let size = CGSize(width: 24, height: 24)
    private static var cache: [UInt8: UIImage] = [:]


    private static var cachedToolImage: UIImage?

    /// Custom NBT file-tool icon used on the Blocktopograph home screen.
    /// It deliberately avoids newer SF Symbols so it remains available on iOS 13.
    static func toolImage() -> UIImage {
        if let cachedToolImage = cachedToolImage { return cachedToolImage }

        let iconSize = CGSize(width: 30, height: 30)
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        format.scale = UIScreen.main.scale
        let renderer = UIGraphicsImageRenderer(size: iconSize, format: format)
        let image = renderer.image { _ in
            let outerRect = CGRect(x: 1.5, y: 1.5, width: 27, height: 27)
            let body = UIBezierPath(roundedRect: outerRect, cornerRadius: 9)
            UIColor(red: 0.42, green: 0.22, blue: 0.74, alpha: 1).setFill()
            body.fill()

            let highlightRect = CGRect(x: 4, y: 4, width: 22, height: 8)
            let highlight = UIBezierPath(roundedRect: highlightRect, cornerRadius: 4)
            UIColor(red: 0.68, green: 0.52, blue: 0.91, alpha: 0.78).setFill()
            highlight.fill()

            let bracesAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 10.5, weight: .bold),
                .foregroundColor: UIColor.white.withAlphaComponent(0.96)
            ]
            ("{}" as NSString).draw(at: CGPoint(x: 6.2, y: 5.2), withAttributes: bracesAttributes)

            let text = "NBT" as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 8.5, weight: .heavy),
                .foregroundColor: UIColor.white
            ]
            let measured = text.size(withAttributes: attributes)
            text.draw(
                at: CGPoint(x: (iconSize.width - measured.width) / 2, y: 17.3),
                withAttributes: attributes
            )
        }
        cachedToolImage = image
        return image
    }

    static func image(for type: NBTTagType) -> UIImage {
        if let cached = cache[type.rawValue] { return cached }

        let rendererFormat = UIGraphicsImageRendererFormat.default()
        rendererFormat.opaque = false
        rendererFormat.scale = UIScreen.main.scale

        let renderer = UIGraphicsImageRenderer(size: size, format: rendererFormat)
        let image = renderer.image { _ in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
            backgroundColor(for: type).setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: 5).fill()

            let label = abbreviation(for: type)
            let fontSize: CGFloat
            switch label.count {
            case 1: fontSize = 13
            case 2: fontSize = 11
            default: fontSize = 8
            }

            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: fontSize, weight: .bold),
                .foregroundColor: foregroundColor(for: type)
            ]
            let measured = (label as NSString).size(withAttributes: attributes)
            let origin = CGPoint(
                x: (size.width - measured.width) / 2,
                y: (size.height - measured.height) / 2 - 0.5
            )
            (label as NSString).draw(at: origin, withAttributes: attributes)
        }

        cache[type.rawValue] = image
        return image
    }

    private static func abbreviation(for type: NBTTagType) -> String {
        switch type {
        case .end: return "E"
        case .byte: return "B"
        case .short: return "S"
        case .int: return "I"
        case .long: return "L"
        case .float: return "F"
        case .double: return "D"
        case .byteArray: return "B[]"
        case .string: return "T"
        case .list: return "[]"
        case .compound: return "{}"
        case .intArray: return "I[]"
        case .longArray: return "L[]"
        }
    }

    private static func backgroundColor(for type: NBTTagType) -> UIColor {
        switch type {
        case .end: return UIColor(red: 0.45, green: 0.49, blue: 0.53, alpha: 1)
        case .byte: return UIColor(red: 0.84, green: 0.20, blue: 0.22, alpha: 1)
        case .short: return UIColor(red: 0.91, green: 0.39, blue: 0.10, alpha: 1)
        case .int: return UIColor(red: 0.82, green: 0.61, blue: 0.03, alpha: 1)
        case .long: return UIColor(red: 0.55, green: 0.34, blue: 0.16, alpha: 1)
        case .float: return UIColor(red: 0.16, green: 0.60, blue: 0.31, alpha: 1)
        case .double: return UIColor(red: 0.05, green: 0.53, blue: 0.56, alpha: 1)
        case .byteArray: return UIColor(red: 0.55, green: 0.27, blue: 0.67, alpha: 1)
        case .string: return UIColor(red: 0.12, green: 0.43, blue: 0.78, alpha: 1)
        case .list: return UIColor(red: 0.34, green: 0.34, blue: 0.82, alpha: 1)
        case .compound: return UIColor(red: 0.76, green: 0.19, blue: 0.51, alpha: 1)
        case .intArray: return UIColor(red: 0.31, green: 0.37, blue: 0.43, alpha: 1)
        case .longArray: return UIColor(red: 0.18, green: 0.25, blue: 0.31, alpha: 1)
        }
    }

    private static func foregroundColor(for type: NBTTagType) -> UIColor {
        type == .int ? .black : .white
    }
}
