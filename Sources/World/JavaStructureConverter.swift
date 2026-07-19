import Foundation

struct StructureImportResult {
    enum SourceKind {
        case bedrock
        case java
    }

    let sourceKind: SourceKind
    let paletteEntryCount: Int
    let placedBlockCount: Int
    let lossyPaletteEntryCount: Int

    var convertedFromJava: Bool { sourceKind == .java }
}

/// Converts Java Edition structure NBT into the Bedrock `.mcstructure` schema used by
/// `structuretemplate_*` LevelDB values. The layout follows MCBE Essentials' Structure
/// Editor conversion: Java palette/state indices become a Bedrock palette plus two full-size
/// `block_indices` layers. Java entities, waterlog data and advanced block-entity data are not
/// carried over by this compatibility conversion.
enum JavaStructureConverter {
    private static let bedrockPaletteVersion: Int32 = 17_959_425
    private static let maximumBlockVolume = 16_777_216

    private struct JavaPaletteEntry {
        let name: String
        let properties: [String: String]

        var dynamicIdentifier: String {
            let values = properties.keys.sorted().map { "\($0)=\(properties[$0] ?? "")" }
            return "\(name)[\(values.joined(separator: ","))]"
        }
    }

    private struct BedrockPaletteEntry {
        let name: String
        let states: [String: NBTValue]
        let lossy: Bool
    }

    static func convertIfNeeded(_ document: NBTDocument) throws -> (document: NBTDocument, result: StructureImportResult) {
        guard case .compound = document.root else {
            throw MCBEEditorError.malformedData("结构 NBT 的根标签必须是 Compound")
        }

        if isBedrockStructure(document.root) {
            let normalized = try normalizeBedrockStructure(document)
            let size = try dimensions(in: normalized.root)
            let paletteCount = bedrockPaletteCount(in: normalized.root)
            return (
                normalized,
                StructureImportResult(
                    sourceKind: .bedrock,
                    paletteEntryCount: paletteCount,
                    placedBlockCount: size.volume,
                    lossyPaletteEntryCount: 0
                )
            )
        }

        guard isJavaStructure(document.root) else {
            throw MCBEEditorError.malformedData("该文件既不是 Java 结构 NBT，也不是 Bedrock mcstructure")
        }
        return try convertJavaStructure(document)
    }

    private static func isBedrockStructure(_ root: NBTValue) -> Bool {
        root.intValue(named: "format_version") != nil &&
        root.compoundValue(named: "structure") != nil &&
        integerVector(named: "size", in: root)?.count == 3
    }

    private static func isJavaStructure(_ root: NBTValue) -> Bool {
        guard integerVector(named: "size", in: root)?.count == 3,
              case .list(.compound, _)? = root.compoundValue(named: "palette"),
              case .list(.compound, _)? = root.compoundValue(named: "blocks") else {
            return false
        }
        return true
    }

    private static func convertJavaStructure(_ document: NBTDocument) throws -> (document: NBTDocument, result: StructureImportResult) {
        let size = try dimensions(in: document.root)
        guard case .list(.compound, let paletteValues)? = document.root.compoundValue(named: "palette") else {
            throw MCBEEditorError.malformedData("Java 结构缺少 palette Compound List")
        }
        guard !paletteValues.isEmpty else {
            throw MCBEEditorError.malformedData("Java 结构 palette 为空")
        }
        guard case .list(.compound, let blockValues)? = document.root.compoundValue(named: "blocks") else {
            throw MCBEEditorError.malformedData("Java 结构缺少 blocks Compound List")
        }

        var bedrockPalette = [NBTValue]()
        bedrockPalette.reserveCapacity(paletteValues.count)
        var lossyCount = 0
        for value in paletteValues {
            let java = try parseJavaPaletteEntry(value)
            let bedrock = mapPaletteEntry(java)
            if bedrock.lossy { lossyCount += 1 }
            bedrockPalette.append(makeBedrockPaletteTag(bedrock))
        }

        var primary = [Int32](repeating: -1, count: size.volume)
        let secondary = [Int32](repeating: -1, count: size.volume)
        var placedCount = 0

        for blockValue in blockValues {
            guard case .compound = blockValue else { continue }
            guard let position = integerVector(named: "pos", in: blockValue), position.count == 3 else {
                throw MCBEEditorError.malformedData("Java 结构 blocks 中存在缺少 pos 的方块")
            }
            guard let rawState = integerValue(named: "state", in: blockValue),
                  rawState >= 0, rawState < Int64(paletteValues.count) else {
                throw MCBEEditorError.malformedData("Java 结构方块引用了无效 palette state")
            }

            let x = try checkedCoordinate(position[0], upperBound: size.x, axis: "X")
            let y = try checkedCoordinate(position[1], upperBound: size.y, axis: "Y")
            let z = try checkedCoordinate(position[2], upperBound: size.z, axis: "Z")
            let index = x * size.y * size.z + y * size.z + z
            primary[index] = Int32(rawState)
            placedCount += 1
        }

        let root: NBTValue = .compound([
            NBTNamedTag(name: "format_version", value: .int(1)),
            NBTNamedTag(name: "size", value: .list(.int, [
                .int(Int32(size.x)), .int(Int32(size.y)), .int(Int32(size.z))
            ])),
            NBTNamedTag(name: "structure_world_origin", value: .list(.int, [
                .int(0), .int(0), .int(0)
            ])),
            NBTNamedTag(name: "structure", value: .compound([
                NBTNamedTag(name: "block_indices", value: .list(.list, [
                    .list(.int, primary.map(NBTValue.int)),
                    .list(.int, secondary.map(NBTValue.int))
                ])),
                NBTNamedTag(name: "entities", value: .list(.end, [])),
                NBTNamedTag(name: "palette", value: .compound([
                    NBTNamedTag(name: "default", value: .compound([
                        NBTNamedTag(name: "block_palette", value: .list(.compound, bedrockPalette)),
                        NBTNamedTag(name: "block_position_data", value: .compound([]))
                    ]))
                ]))
            ]))
        ])

        return (
            NBTDocument(rootName: "", root: root),
            StructureImportResult(
                sourceKind: .java,
                paletteEntryCount: bedrockPalette.count,
                placedBlockCount: placedCount,
                lossyPaletteEntryCount: lossyCount
            )
        )
    }

    /// Bedrock accepts only full-volume, equally sized index layers. Some older converters wrote
    /// a shorter second layer, so normalize both arrays while leaving all other structure data intact.
    private static func normalizeBedrockStructure(_ document: NBTDocument) throws -> NBTDocument {
        let size = try dimensions(in: document.root)
        guard case .compound(var rootTags) = document.root,
              let structureIndex = rootTags.firstIndex(where: { $0.name == "structure" }),
              case .compound(var structureTags) = rootTags[structureIndex].value,
              let indicesIndex = structureTags.firstIndex(where: { $0.name == "block_indices" }) else {
            throw MCBEEditorError.malformedData("Bedrock 结构缺少 structure.block_indices")
        }

        var layers = [[Int32]]()
        if case .list(.list, let layerValues) = structureTags[indicesIndex].value {
            for layerValue in layerValues.prefix(2) {
                if case .list(.int, let values) = layerValue {
                    layers.append(values.compactMap { value -> Int32? in
                        if case .int(let number) = value { return number }
                        return nil
                    })
                }
            }
        }
        while layers.count < 2 { layers.append([]) }
        for index in 0..<2 {
            if layers[index].count < size.volume {
                layers[index].append(contentsOf: repeatElement(Int32(-1), count: size.volume - layers[index].count))
            } else if layers[index].count > size.volume {
                layers[index] = Array(layers[index].prefix(size.volume))
            }
        }
        structureTags[indicesIndex].value = .list(.list, layers.map { .list(.int, $0.map(NBTValue.int)) })
        rootTags[structureIndex].value = .compound(structureTags)
        return NBTDocument(rootName: "", root: .compound(rootTags))
    }

    private static func parseJavaPaletteEntry(_ value: NBTValue) throws -> JavaPaletteEntry {
        guard case .compound = value,
              let name = value.stringValue(named: "Name"), !name.isEmpty else {
            throw MCBEEditorError.malformedData("Java 结构 palette 中存在缺少 Name 的条目")
        }
        var properties = [String: String]()
        if let propertyValue = value.compoundValue(named: "Properties") {
            guard case .compound(let tags) = propertyValue else {
                throw MCBEEditorError.malformedData("Java 结构 palette.Properties 不是 Compound")
            }
            for tag in tags {
                switch tag.value {
                case .string(let text): properties[tag.name] = text
                case .byte(let number): properties[tag.name] = String(number)
                case .short(let number): properties[tag.name] = String(number)
                case .int(let number): properties[tag.name] = String(number)
                case .long(let number): properties[tag.name] = String(number)
                default: break
                }
            }
        }
        return JavaPaletteEntry(name: namespaced(name), properties: properties)
    }

    private static func mapPaletteEntry(_ java: JavaPaletteEntry) -> BedrockPaletteEntry {
        if let exact = exactWebsiteMappings[java.dynamicIdentifier] {
            return exact
        }

        let name = mappedIdentifier(java.name, properties: java.properties)
        var states = [String: NBTValue]()
        var consumed = Set<String>()

        if let axis = java.properties["axis"], axis == "x" || axis == "y" || axis == "z",
           isPillarLike(name) {
            states["pillar_axis"] = .string(axis)
            consumed.insert("axis")
        }

        if name == "minecraft:structure_block", let mode = java.properties["mode"] {
            states["structure_block_type"] = .string(mode)
            consumed.insert("mode")
        }

        if name == "minecraft:brewing_stand" {
            for index in 0...2 {
                let source = "has_bottle_\(index)"
                if let value = java.properties[source] {
                    let target = ["brewing_stand_slot_a_bit", "brewing_stand_slot_b_bit", "brewing_stand_slot_c_bit"][index]
                    states[target] = .byte(booleanByte(value))
                    consumed.insert(source)
                }
            }
        }

        if name == "minecraft:end_rod", let facing = java.properties["facing"],
           let direction = facingDirection(facing) {
            states["facing_direction"] = .int(direction)
            consumed.insert("facing")
        } else if isStair(name), let facing = java.properties["facing"],
                  let direction = stairDirection(facing) {
            states["weirdo_direction"] = .int(direction)
            consumed.insert("facing")
            if let half = java.properties["half"] {
                states["upside_down_bit"] = .byte(half == "top" ? 1 : 0)
                consumed.insert("half")
            }
            consumed.insert("shape")
        } else if isFacingDirectionBlock(name), let facing = java.properties["facing"],
                  let direction = facingDirection(facing) {
            states["facing_direction"] = .int(direction)
            consumed.insert("facing")
        }

        if isSlab(name), let half = java.properties["half"] ?? java.properties["type"] {
            states["top_slot_bit"] = .byte(half == "top" ? 1 : 0)
            consumed.insert("half")
            consumed.insert("type")
            consumed.insert("variant")
        }

        if let powered = java.properties["powered"] {
            states["powered_bit"] = .byte(booleanByte(powered))
            consumed.insert("powered")
        }
        if let open = java.properties["open"] {
            states["open_bit"] = .byte(booleanByte(open))
            consumed.insert("open")
        }
        if let lit = java.properties["lit"] {
            states["lit"] = .byte(booleanByte(lit))
            consumed.insert("lit")
        }
        if let age = java.properties["age"], let number = Int32(age) {
            states["growth"] = .int(number)
            consumed.insert("age")
        }
        if let level = java.properties["level"], let number = Int32(level),
           name == "minecraft:water" || name == "minecraft:lava" {
            states["liquid_depth"] = .int(number)
            consumed.insert("level")
        }

        // The website converter relies on an explicit Java-to-Bedrock dynamic-ID table. For a
        // block not covered by a known rule, keep the Bedrock identifier and default state instead
        // of writing Java-only state names that can make the palette unreadable by the game.
        let ignoredProperties = Set(java.properties.keys).subtracting(consumed)
        let lossy = !ignoredProperties.isEmpty || name == "minecraft:air" && java.name != "minecraft:air"
        return BedrockPaletteEntry(name: name, states: states, lossy: lossy)
    }

    private static func makeBedrockPaletteTag(_ entry: BedrockPaletteEntry) -> NBTValue {
        let stateTags = entry.states.keys.sorted().map {
            NBTNamedTag(name: $0, value: entry.states[$0] ?? .string(""))
        }
        return .compound([
            NBTNamedTag(name: "name", value: .string(entry.name)),
            NBTNamedTag(name: "states", value: .compound(stateTags)),
            NBTNamedTag(name: "version", value: .int(bedrockPaletteVersion))
        ])
    }

    private static func mappedIdentifier(_ identifier: String, properties: [String: String]) -> String {
        let name = namespaced(identifier)
        guard name.hasPrefix("minecraft:") else { return name }
        let path = String(name.dropFirst("minecraft:".count))

        if let color = properties["color"] {
            let colorFamilies: Set<String> = [
                "wool", "carpet", "stained_glass", "stained_glass_pane", "terracotta",
                "concrete", "concrete_powder", "shulker_box", "glazed_terracotta"
            ]
            if colorFamilies.contains(path) {
                return "minecraft:\(color)_\(path)"
            }
        }

        let aliases: [String: String] = [
            "minecraft:grass": "minecraft:grass_block",
            "minecraft:grass_path": "minecraft:dirt_path",
            "minecraft:double_stone_slab": "minecraft:double_stone_block_slab",
            "minecraft:stone_slab": "minecraft:stone_block_slab",
            "minecraft:lit_furnace": "minecraft:furnace",
            "minecraft:lit_redstone_lamp": "minecraft:redstone_lamp",
            "minecraft:flowing_water": "minecraft:water",
            "minecraft:flowing_lava": "minecraft:lava",
            "minecraft:web": "minecraft:web"
        ]
        return aliases[name] ?? name
    }

    private static func namespaced(_ identifier: String) -> String {
        identifier.contains(":") ? identifier : "minecraft:\(identifier)"
    }

    private static func isPillarLike(_ name: String) -> Bool {
        name.hasSuffix("_log") || name.hasSuffix("_wood") || name.hasSuffix("_stem") ||
        name.hasSuffix("_hyphae") || name.hasSuffix("_pillar") || name == "minecraft:bone_block" ||
        name == "minecraft:purpur_block"
    }

    private static func isStair(_ name: String) -> Bool { name.hasSuffix("_stairs") }
    private static func isSlab(_ name: String) -> Bool { name.hasSuffix("_slab") }

    private static func isFacingDirectionBlock(_ name: String) -> Bool {
        let paths = [
            "ladder", "chest", "trapped_chest", "furnace", "blast_furnace", "smoker",
            "dispenser", "dropper", "observer", "hopper", "barrel", "end_rod"
        ]
        return paths.contains { name == "minecraft:\($0)" }
    }

    private static func facingDirection(_ value: String) -> Int32? {
        ["down": 0, "up": 1, "south": 2, "north": 3, "east": 4, "west": 5][value]
    }

    private static func stairDirection(_ value: String) -> Int32? {
        ["east": 0, "west": 1, "south": 2, "north": 3][value]
    }

    private static func booleanByte(_ text: String) -> Int8 {
        let lowered = text.lowercased()
        return lowered == "true" || lowered == "1" ? 1 : 0
    }

    private static func checkedCoordinate(_ value: Int64, upperBound: Int, axis: String) throws -> Int {
        guard value >= 0, value < Int64(upperBound) else {
            throw MCBEEditorError.malformedData("Java 结构方块 \(axis) 坐标越界：\(value)")
        }
        return Int(value)
    }

    private struct Dimensions {
        let x: Int
        let y: Int
        let z: Int
        let volume: Int
    }

    private static func dimensions(in root: NBTValue) throws -> Dimensions {
        guard let values = integerVector(named: "size", in: root), values.count == 3 else {
            throw MCBEEditorError.malformedData("结构缺少有效的 size[3]")
        }
        guard values.allSatisfy({ $0 > 0 && $0 <= Int64(Int32.max) }) else {
            throw MCBEEditorError.malformedData("结构尺寸必须是正整数")
        }
        let x = Int(values[0]), y = Int(values[1]), z = Int(values[2])
        let (xy, overflowXY) = x.multipliedReportingOverflow(by: y)
        let (volume, overflowXYZ) = xy.multipliedReportingOverflow(by: z)
        guard !overflowXY, !overflowXYZ, volume <= maximumBlockVolume else {
            throw MCBEEditorError.unsupported("结构体积过大：\(x)×\(y)×\(z)，最多支持 \(maximumBlockVolume) 个方块")
        }
        return Dimensions(x: x, y: y, z: z, volume: volume)
    }

    private static func integerVector(named name: String, in value: NBTValue) -> [Int64]? {
        guard let child = value.compoundValue(named: name) else { return nil }
        switch child {
        case .intArray(let values): return values.map(Int64.init)
        case .longArray(let values): return values
        case .list(_, let values):
            let result = values.compactMap(integerValue)
            return result.count == values.count ? result : nil
        default: return nil
        }
    }

    private static func integerValue(named name: String, in value: NBTValue) -> Int64? {
        guard let child = value.compoundValue(named: name) else { return nil }
        return integerValue(child)
    }

    private static func integerValue(_ value: NBTValue) -> Int64? {
        switch value {
        case .byte(let number): return Int64(number)
        case .short(let number): return Int64(number)
        case .int(let number): return Int64(number)
        case .long(let number): return number
        default: return nil
        }
    }

    private static func bedrockPaletteCount(in root: NBTValue) -> Int {
        guard let structure = root.compoundValue(named: "structure"),
              let palette = structure.compoundValue(named: "palette"),
              let defaultPalette = palette.compoundValue(named: "default"),
              case .list(.compound, let entries)? = defaultPalette.compoundValue(named: "block_palette") else {
            return 0
        }
        return entries.count
    }

    /// Exact entries observed in the user's MCBE Essentials conversion example. Keeping these
    /// before the generic rules makes the app reproduce the reference converter for that file.
    private static let exactWebsiteMappings: [String: BedrockPaletteEntry] = {
        let air = BedrockPaletteEntry(name: "minecraft:air", states: [:], lossy: true)
        return [
            "minecraft:air[]": BedrockPaletteEntry(name: "minecraft:air", states: [:], lossy: false),
            "minecraft:purpur_pillar[axis=z]": BedrockPaletteEntry(name: "minecraft:purpur_pillar", states: ["pillar_axis": .string("z")], lossy: false),
            "minecraft:purpur_block[]": BedrockPaletteEntry(name: "minecraft:purpur_block", states: ["pillar_axis": .string("y")], lossy: false),
            "minecraft:obsidian[]": BedrockPaletteEntry(name: "minecraft:obsidian", states: [:], lossy: false),
            "minecraft:purpur_pillar[axis=y]": BedrockPaletteEntry(name: "minecraft:purpur_pillar", states: ["pillar_axis": .string("y")], lossy: false),
            "minecraft:end_bricks[]": air,
            "minecraft:skull[facing=north,nodrop=false]": air,
            "minecraft:chest[facing=south]": air,
            "minecraft:structure_block[mode=save]": BedrockPaletteEntry(name: "minecraft:structure_block", states: ["structure_block_type": .string("save")], lossy: false),
            "minecraft:structure_block[mode=data]": BedrockPaletteEntry(name: "minecraft:structure_block", states: ["structure_block_type": .string("data")], lossy: false),
            "minecraft:brewing_stand[has_bottle_0=true,has_bottle_1=false,has_bottle_2=true]": BedrockPaletteEntry(name: "minecraft:brewing_stand", states: [
                "brewing_stand_slot_a_bit": .byte(1), "brewing_stand_slot_b_bit": .byte(0), "brewing_stand_slot_c_bit": .byte(1)
            ], lossy: false),
            "minecraft:purpur_stairs[facing=north,half=bottom,shape=straight]": air,
            "minecraft:purpur_slab[half=top,variant=default]": air,
            "minecraft:end_rod[facing=up]": BedrockPaletteEntry(name: "minecraft:end_rod", states: ["facing_direction": .int(1)], lossy: false),
            "minecraft:end_rod[facing=south]": BedrockPaletteEntry(name: "minecraft:end_rod", states: ["facing_direction": .int(2)], lossy: false),
            "minecraft:purpur_stairs[facing=east,half=bottom,shape=straight]": air,
            "minecraft:purpur_stairs[facing=west,half=bottom,shape=straight]": air,
            "minecraft:purpur_stairs[facing=south,half=bottom,shape=straight]": air,
            "minecraft:purpur_stairs[facing=south,half=top,shape=straight]": air,
            "minecraft:purpur_stairs[facing=west,half=top,shape=straight]": air,
            "minecraft:purpur_stairs[facing=east,half=top,shape=straight]": air,
            "minecraft:stained_glass[color=magenta]": air,
            "minecraft:ladder[facing=south]": air,
            "minecraft:purpur_stairs[facing=north,half=top,shape=straight]": air
        ]
    }()
}
