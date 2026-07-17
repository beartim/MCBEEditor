import UIKit

enum MapRenderMode: Int, CaseIterable {
    case surface
    case height
    case xray
    case biome
    case tickingAreas
    case slime

    var displayName: String {
        switch self {
        case .surface: return "地表"
        case .height: return "高度"
        case .xray: return "矿物"
        case .biome: return "生物群系"
        case .tickingAreas: return "常加载区块"
        case .slime: return "史莱姆区块"
        }
    }
}

struct ChunkSurfaceResult {
    let image: UIImage
    let blockNames: [String]
    let blockHeights: [Int16]
    let biomeIDs: [UInt32]
    let decodedSubChunks: Int
    let errors: [String]
}

struct ChunkRenderLookup {
    let result: ChunkSurfaceResult
    let cacheHit: Bool
}

private final class CachedChunkBox: NSObject {
    let result: ChunkSurfaceResult
    init(result: ChunkSurfaceResult) { self.result = result }
}

final class ChunkSurfaceCache {
    private let cache = NSCache<NSString, CachedChunkBox>()

    init() {
        cache.countLimit = 768
        cache.totalCostLimit = 64 * 1024 * 1024
    }

    func result(x: Int32, z: Int32, dimension: Int32, mode: MapRenderMode) -> ChunkSurfaceResult? {
        cache.object(forKey: key(x: x, z: z, dimension: dimension, mode: mode))?.result
    }

    func insert(_ result: ChunkSurfaceResult, x: Int32, z: Int32, dimension: Int32, mode: MapRenderMode) {
        let nameBytes = result.blockNames.reduce(0) { $0 + $1.utf8.count }
        let cost = 16 * 16 * 4 + result.blockHeights.count * 2 + result.biomeIDs.count * 4 + nameBytes
        cache.setObject(
            CachedChunkBox(result: result),
            forKey: key(x: x, z: z, dimension: dimension, mode: mode),
            cost: cost
        )
    }

    func removeAll() { cache.removeAllObjects() }

    private func key(x: Int32, z: Int32, dimension: Int32, mode: MapRenderMode) -> NSString {
        "\(dimension):\(x):\(z):\(mode.rawValue)" as NSString
    }
}

final class ChunkSurfaceRenderer {
    let database: MojangLevelDB
    private let cache: ChunkSurfaceCache

    init(database: MojangLevelDB, cache: ChunkSurfaceCache = ChunkSurfaceCache()) {
        self.database = database
        self.cache = cache
    }

    func renderChunk(x: Int32, z: Int32, dimension: Int32, mode: MapRenderMode) throws -> ChunkRenderLookup {
        if let cached = cache.result(x: x, z: z, dimension: dimension, mode: mode) {
            return ChunkRenderLookup(result: cached, cacheHit: true)
        }

        let rendered = try decodeChunk(x: x, z: z, dimension: dimension, mode: mode)
        cache.insert(rendered, x: x, z: z, dimension: dimension, mode: mode)
        return ChunkRenderLookup(result: rendered, cacheHit: false)
    }

    func clearCache() { cache.removeAll() }

    private func decodeChunk(x: Int32, z: Int32, dimension: Int32, mode: MapRenderMode) throws -> ChunkSurfaceResult {
        if mode == .slime {
            let slime = BedrockSlimeChunk.isSlimeChunk(x: x, z: z)
            let name = slime ? "blocktopograph:slime_chunk" : "blocktopograph:non_slime_chunk"
            return ChunkSurfaceResult(
                image: makeSlimeChunkImage(isSlime: slime),
                blockNames: Array(repeating: name, count: 256),
                blockHeights: Array(repeating: 0, count: 256),
                biomeIDs: Array(repeating: UInt32.max, count: 256),
                decodedSubChunks: 0,
                errors: []
            )
        }
        if mode == .tickingAreas {
            return ChunkSurfaceResult(
                image: makeNeutralSyntheticImage(),
                blockNames: Array(repeating: "blocktopograph:non_ticking_chunk", count: 256),
                blockHeights: Array(repeating: 0, count: 256),
                biomeIDs: Array(repeating: UInt32.max, count: 256),
                decodedSubChunks: 0,
                errors: []
            )
        }
        var visibleBlocks = Array<String?>(repeating: nil, count: 256)
        var visibleHeights = Array(repeating: Int16.min, count: 256)
        var unresolved = 256
        var decoded = 0
        var errors = [String]()

        // Bedrock 1.18+ commonly stores subchunks from -4 through 19.
        // Scanning top-down lets surface/height modes stop once all columns
        // have a visible block. X-ray mode deliberately scans the full range.
        for yValue in Array(-4...19).reversed() {
            if mode != .xray, unresolved == 0 { break }
            let yIndex = Int8(yValue)
            let key = BedrockDBKey.subChunk(x: x, z: z, dimension: dimension, index: yIndex)
            guard let raw = try database.get(key) else { continue }
            do {
                let subChunk = try BedrockSubChunk.decode(raw, keyYIndex: yIndex)
                decoded += 1
                guard !subChunk.storages.isEmpty else { continue }

                for localX in 0..<16 {
                    for localZ in 0..<16 {
                        let column = localZ * 16 + localX
                        if mode != .xray, visibleBlocks[column] != nil { continue }

                        for localY in stride(from: 15, through: 0, by: -1) {
                            guard let state = preferredState(in: subChunk, x: localX, y: localY, z: localZ) else { continue }
                            let name = state.name
                            if mode == .xray {
                                guard visibleBlocks[column] == nil, isHighlightedOre(name) else { continue }
                            }

                            visibleBlocks[column] = name
                            visibleHeights[column] = Int16(clamping: yValue * 16 + localY)
                            unresolved -= 1
                            break
                        }
                    }
                }
            } catch {
                errors.append("Y=\(yValue): \(error.localizedDescription)")
            }
        }

        let names = visibleBlocks.map { $0 ?? "minecraft:air" }
        let biomeIDs: [UInt32]
        if mode == .biome {
            do {
                biomeIDs = try decodeBiomeIDs(x: x, z: z, dimension: dimension, heights: visibleHeights)
            } catch {
                biomeIDs = Array(repeating: UInt32.max, count: 256)
                errors.append("生物群系：\(error.localizedDescription)")
            }
        } else {
            biomeIDs = Array(repeating: UInt32.max, count: 256)
        }
        return ChunkSurfaceResult(
            image: makeImage(blockNames: names, heights: visibleHeights, biomeIDs: biomeIDs, mode: mode),
            blockNames: names,
            blockHeights: visibleHeights,
            biomeIDs: biomeIDs,
            decodedSubChunks: decoded,
            errors: errors
        )
    }

    private func preferredState(in subChunk: BedrockSubChunk, x: Int, y: Int, z: Int) -> BedrockBlockState? {
        // Modern Bedrock SubChunks may contain multiple storage layers, for
        // example a primary block and a waterlogged liquid layer. Prefer the
        // first non-air state while retaining later-layer fallback.
        for storage in subChunk.storages {
            guard let state = storage.blockState(x: x, y: y, z: z), !state.isAir else { continue }
            return state
        }
        return nil
    }

    private func makeImage(blockNames: [String], heights: [Int16], biomeIDs: [UInt32], mode: MapRenderMode) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16), format: format).image { context in
            UIColor.systemGray5.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
            for z in 0..<16 {
                for x in 0..<16 {
                    let index = z * 16 + x
                    color(for: blockNames[index], height: heights[index], biomeID: biomeIDs[index], mode: mode).setFill()
                    context.fill(CGRect(x: x, y: z, width: 1, height: 1))
                }
            }
        }
    }

    private func color(for blockName: String, height: Int16, biomeID: UInt32, mode: MapRenderMode) -> UIColor {
        switch mode {
        case .surface:
            return surfaceColor(for: blockName)
        case .height:
            guard height != Int16.min else { return .systemGray5 }
            if blockName.lowercased().contains("water") {
                let value = normalizedHeight(height)
                return UIColor(red: 0.08 + value * 0.12, green: 0.25 + value * 0.25, blue: 0.55 + value * 0.35, alpha: 1)
            }
            let value = 0.12 + normalizedHeight(height) * 0.82
            return UIColor(white: value, alpha: 1)
        case .xray:
            return oreColor(for: blockName)
        case .biome:
            return BedrockBiomeCatalog.color(for: biomeID)
        case .tickingAreas, .slime:
            return .systemGray5
        }
    }

    private func makeSlimeChunkImage(isSlime: Bool) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16), format: format).image { context in
            let base = isSlime ? UIColor(red: 0.25, green: 0.72, blue: 0.25, alpha: 1) : UIColor(white: 0.24, alpha: 1)
            base.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
            let accent = isSlime ? UIColor(red: 0.48, green: 0.90, blue: 0.40, alpha: 1) : UIColor(white: 0.29, alpha: 1)
            accent.setFill()
            for z in stride(from: 1, to: 16, by: 4) {
                for x in stride(from: 1, to: 16, by: 4) {
                    context.fill(CGRect(x: x, y: z, width: 2, height: 2))
                }
            }
        }
    }

    private func makeNeutralSyntheticImage() -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16), format: format).image { context in
            UIColor(white: 0.20, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        }
    }

    private func decodeBiomeIDs(x: Int32, z: Int32, dimension: Int32, heights: [Int16]) throws -> [UInt32] {
        let position = ChunkPosition(x: x, z: z, dimension: dimension)
        let preferredTypes: [ChunkRecordType] = [.data3D, .data2D, .data2DLegacy]
        var document: BedrockBiomeDocument?
        for type in preferredTypes {
            let key = BedrockDBKey(position: position, recordType: type, subChunkIndex: nil).encoded()
            guard let raw = try database.get(key) else { continue }
            document = try BedrockBiomeDocument.decode(recordType: type, data: raw)
            break
        }
        guard let biomeDocument = document else {
            return Array(repeating: UInt32.max, count: 256)
        }
        var result = Array(repeating: UInt32.max, count: 256)
        for localZ in 0..<16 {
            for localX in 0..<16 {
                let index = localZ * 16 + localX
                let surfaceY = heights[index] == Int16.min ? 64 : Int(heights[index])
                result[index] = biomeDocument.biomeID(localX: localX, y: surfaceY, localZ: localZ) ?? UInt32.max
            }
        }
        return result
    }

    private func normalizedHeight(_ height: Int16) -> CGFloat {
        min(1, max(0, CGFloat(Int(height) + 64) / 384.0))
    }

    private func isHighlightedOre(_ blockName: String) -> Bool {
        let name = blockName.lowercased()
        return name.contains("_ore")
            || name.contains("ancient_debris")
            || name.contains("raw_iron_block")
            || name.contains("raw_gold_block")
            || name.contains("raw_copper_block")
            || name.contains("amethyst_cluster")
    }

    private func oreColor(for blockName: String) -> UIColor {
        let name = blockName.lowercased()
        if name.contains("diamond") { return UIColor(red: 0.20, green: 0.92, blue: 0.92, alpha: 1) }
        if name.contains("emerald") { return UIColor(red: 0.10, green: 0.85, blue: 0.32, alpha: 1) }
        if name.contains("redstone") { return UIColor(red: 0.90, green: 0.10, blue: 0.08, alpha: 1) }
        if name.contains("lapis") { return UIColor(red: 0.15, green: 0.30, blue: 0.90, alpha: 1) }
        if name.contains("gold") { return UIColor(red: 0.98, green: 0.76, blue: 0.08, alpha: 1) }
        if name.contains("iron") { return UIColor(red: 0.82, green: 0.68, blue: 0.58, alpha: 1) }
        if name.contains("copper") { return UIColor(red: 0.78, green: 0.38, blue: 0.18, alpha: 1) }
        if name.contains("coal") { return UIColor(red: 0.18, green: 0.18, blue: 0.18, alpha: 1) }
        if name.contains("quartz") { return UIColor(red: 0.92, green: 0.86, blue: 0.80, alpha: 1) }
        if name.contains("ancient_debris") { return UIColor(red: 0.42, green: 0.22, blue: 0.16, alpha: 1) }
        if name.contains("amethyst") { return UIColor(red: 0.58, green: 0.30, blue: 0.86, alpha: 1) }
        return blockName == "minecraft:air" ? .black : .systemPurple
    }

    private func rgb(_ hex: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: 1
        )
    }

    private func dyedBlockColor(for name: String) -> UIColor? {
        let families = ["wool", "carpet", "concrete", "concrete_powder", "terracotta", "stained_glass", "glazed_terracotta", "shulker_box", "candle"]
        guard families.contains(where: { name.contains($0) }) else { return nil }
        let colors: [(String, UInt32)] = [
            ("light_blue", 0x3AAFD9), ("light_gray", 0x9D9D97), ("lime", 0x70B919),
            ("magenta", 0xC64FBD), ("orange", 0xF9801D), ("purple", 0x8932B8),
            ("yellow", 0xFED83D), ("green", 0x5E7C16), ("brown", 0x835432),
            ("cyan", 0x169C9C), ("blue", 0x3C44AA), ("red", 0xB02E26),
            ("pink", 0xF38BAA), ("gray", 0x474F52), ("black", 0x1D1D21),
            ("white", 0xF4F4F4)
        ]
        for (token, value) in colors where name.contains(token) { return rgb(value) }
        return nil
    }

    private func surfaceColor(for blockName: String) -> UIColor {
        let name = blockName.lowercased()
        if name == "minecraft:air" || name.hasSuffix(":cave_air") || name.hasSuffix(":void_air") { return rgb(0xE5E5E5) }
        if name.contains("water") || name.contains("bubble_column") { return rgb(0x337CCB) }
        if name.contains("lava") { return rgb(0xF05A19) }
        if let dyed = dyedBlockColor(for: name) { return dyed }

        // Plants and natural ground.
        if name == "minecraft:vine" || name.hasSuffix(":vine") { return UIColor(red: 0.18, green: 0.64, blue: 0.20, alpha: 1) }
        if name.contains("mangrove_leaves") { return rgb(0x3E7138) }
        if name.contains("azalea_leaves") { return rgb(0x4F8A3A) }
        if name.contains("cherry_leaves") || name.contains("pink_petals") { return rgb(0xECA7B7) }
        if name.contains("leaves") { return rgb(0x3F7D32) }
        if name.contains("moss") || name.contains("grass_block") || name.contains("short_grass") || name.contains("tall_grass") || name.contains("fern") { return rgb(0x5E9B3B) }
        if name.contains("mycelium") { return rgb(0x705A6A) }
        if name.contains("podzol") { return rgb(0x6B4B2A) }
        if name.contains("mud") { return rgb(0x4B4648) }
        if name.contains("dirt") || name.contains("farmland") || name.contains("grass_path") || name.contains("dirt_path") { return rgb(0x76502B) }
        if name.contains("clay") { return rgb(0x9AA6B1) }
        if name.contains("gravel") { return rgb(0x77716D) }

        // Sand, snow and ice.
        if name.contains("red_sand") { return rgb(0xB65A27) }
        if name.contains("sandstone") { return name.contains("red_") ? rgb(0xB96A39) : rgb(0xD9C58B) }
        if name.contains("sand") { return rgb(0xDEC98A) }
        if name.contains("powder_snow") || name.contains("snow") { return rgb(0xF1F6F7) }
        if name.contains("blue_ice") { return rgb(0x74A9FF) }
        if name.contains("packed_ice") { return rgb(0x8DB4EA) }
        if name.contains("ice") { return rgb(0xB6D7F2) }

        // Stone families.
        if name.contains("calcite") || name.contains("diorite") || name.contains("quartz") { return rgb(0xD7D4CB) }
        if name.contains("granite") { return rgb(0x95604C) }
        if name.contains("andesite") { return rgb(0x7D7D7D) }
        if name.contains("tuff") { return rgb(0x59645D) }
        if name.contains("deepslate") { return rgb(0x3F4245) }
        if name.contains("blackstone") { return rgb(0x2F292F) }
        if name.contains("cobblestone") { return rgb(0x686868) }
        // Wood families. Keep species visibly distinct on large maps.
        if name.contains("crimson_stem") || name.contains("crimson_hyphae") || name.contains("crimson_planks") { return rgb(0x7C334A) }
        if name.contains("warped_stem") || name.contains("warped_hyphae") || name.contains("warped_planks") { return rgb(0x247A75) }
        if name.contains("mangrove") && (name.contains("log") || name.contains("wood") || name.contains("planks")) { return rgb(0x74332F) }
        if name.contains("cherry") && (name.contains("log") || name.contains("wood") || name.contains("planks")) { return rgb(0xD28E8E) }
        if name.contains("dark_oak") { return rgb(0x4B3422) }
        if name.contains("spruce") { return rgb(0x6B4A2B) }
        if name.contains("acacia") { return rgb(0xA85A32) }
        if name.contains("birch") { return rgb(0xC4B87A) }
        if name.contains("jungle") { return rgb(0x9A6B36) }
        if name.contains("bamboo") { return rgb(0xA9B744) }
        if name.contains("wood") || name.contains("log") || name.contains("planks") || name.contains("stem") || name.contains("hyphae") { return rgb(0x8B6336) }

        // Nether and End.
        if name.contains("netherrack") { return rgb(0x6E2B2B) }
        if name.contains("soul_sand") || name.contains("soul_soil") { return rgb(0x544034) }
        if name.contains("basalt") { return rgb(0x4D4A4A) }
        if name.contains("magma") { return rgb(0xA44720) }
        if name.contains("glowstone") || name.contains("shroomlight") { return rgb(0xD89B4B) }
        if name.contains("nether_wart") || name.contains("nether_brick") { return rgb(0x4A1E25) }
        if name.contains("end_stone") { return rgb(0xD5D69A) }
        if name.contains("purpur") { return rgb(0xA86F9E) }

        // Metals and distinctive decorative blocks.
        if name.contains("oxidized_copper") { return rgb(0x4F9C85) }
        if name.contains("weathered_copper") { return rgb(0x6D8F75) }
        if name.contains("exposed_copper") { return rgb(0xA66B4A) }
        if name.contains("copper") { return rgb(0xC46C43) }
        if name.contains("gold") { return rgb(0xE5BE32) }
        if name.contains("iron") { return rgb(0xC8C5BC) }
        if name.contains("diamond") { return rgb(0x53C8C2) }
        if name.contains("emerald") { return rgb(0x32B85A) }
        if name.contains("redstone") { return rgb(0xB52A24) }
        if name.contains("lapis") { return rgb(0x3459A8) }
        if name.contains("coal") { return rgb(0x303030) }
        if name.contains("obsidian") { return rgb(0x241B35) }
        if name.contains("amethyst") { return rgb(0x8B5CB5) }
        if name.contains("brick") { return rgb(0x9B5146) }
        if name.contains("prismarine") { return rgb(0x5E9B8B) }
        if name.contains("sea_lantern") { return rgb(0xC8DED2) }
        if name.contains("stone") || name.contains("ore") { return rgb(0x777777) }

        // Deterministic fallback keeps custom blocks recognizable without neon colors.
        var hash: UInt32 = 2166136261
        for byte in name.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16777619
        }
        let hue = CGFloat(hash % 360) / 360.0
        let saturation = CGFloat(28 + (hash >> 8) % 28) / 100.0
        let brightness = CGFloat(48 + (hash >> 16) % 28) / 100.0
        return UIColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1)
    }
}
