import XCTest
import UIKit
@testable import MCBEEditor

final class SourceAuditTests: XCTestCase {
    func testRawDeflateRequiresExactZIPSize() throws {
        // Larger than one inflater output window to exercise repeated appends.
        let payload = Data(repeating: 0x41, count: 200_000)
        let compressed = try BTCompressionBridge.deflateRaw(payload, level: 6)
        XCTAssertEqual(try BTCompressionBridge.inflateRaw(compressed, expectedSize: UInt(payload.count)), payload)
        XCTAssertThrowsError(try BTCompressionBridge.inflateRaw(compressed, expectedSize: 1))
        XCTAssertThrowsError(try BTCompressionBridge.inflateRaw(compressed, expectedSize: UInt(payload.count + 1)))
        XCTAssertThrowsError(try BTCompressionBridge.inflateRaw(Data(compressed.dropLast()), expectedSize: UInt(payload.count)))
        let empty = try BTCompressionBridge.deflateRaw(Data(), level: 6)
        XCTAssertEqual(try BTCompressionBridge.inflateRaw(empty, expectedSize: 0), Data())
    }

    func testWrappedNBTSizeRemainsAnEstimate() throws {
        let payload = Data([10, 0, 0, 0])
        let zlib = Data([120, 156, 227, 98, 96, 96, 0, 0, 0, 44, 0, 11])
        XCTAssertEqual(try BTCompressionBridge.inflateWrapped(zlib, expectedSize: 1), payload)
        XCTAssertEqual(try BTCompressionBridge.inflateWrapped(zlib, expectedSize: 1_000_000), payload)
    }

    func testColorsTextBOMAndLastValidEntry() {
        let colors = BlockTextureOverrideStore.parseColorsText(
            "\u{FEFF}minecraft:stone #112233\r\n" +
            "minecraft:stone #ABCDEF\r\n" +
            "minecraft:stone #invalid\r\n" +
            "minecraft:dirt #123456 extra\n" +
            "minecraft::air #000000\n"
        )
        XCTAssertEqual(colors, ["minecraft:stone": 0xABCDEF])
    }

    func testPNGAlphaAverageAndTextPriority() throws {
        let manager = FileManager.default
        let directory = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? manager.removeItem(at: directory)
            BlockTextureOverrideStore.prepareSharedDirectoryAndReload()
        }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 1), format: format).image { context in
            UIColor(red: 1, green: 0, blue: 0, alpha: 0.5).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        let png = try XCTUnwrap(image.pngData())
        try png.write(to: directory.appendingPathComponent("minecraft_stone.png"))
        BlockTextureOverrideStore.reload(from: directory)
        XCTAssertEqual(BlockTextureOverrideStore.rgbHex(for: "minecraft:stone"), 0xFF0000)

        try Data("\u{FEFF}minecraft:stone #123456\r\n".utf8)
            .write(to: directory.appendingPathComponent("Colors.txt"))
        BlockTextureOverrideStore.reload(from: directory)
        XCTAssertEqual(BlockTextureOverrideStore.rgbHex(for: "minecraft:stone"), 0x123456)
    }

    func testInvalidPlayerLevelDoesNotTrap() {
        for number in [Double.nan, Double.infinity, 1e100, 3.5] {
            let document = NBTDocument(rootName: "", root: .compound([
                NBTNamedTag(name: "PlayerLevel", value: .double(number))
            ]))
            XCTAssertThrowsError(try ExperienceStore.read(from: document))
        }
    }
}
