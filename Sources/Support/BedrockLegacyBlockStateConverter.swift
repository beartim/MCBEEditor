import Foundation

/// Compatibility bridge between the numeric-ID + data/`val` era and NBT
/// block-state palettes. The converter deliberately prefers a lossless old
/// `val` representation over inventing incorrect modern states when a mapping
/// is not known. Bedrock can upgrade versioned historical palette entries, and
/// MCBEEditor therefore never silently turns a non-zero legacy data value into
/// `states: {}`.
enum BedrockLegacyBlockStateConverter {
    /// Historical block-state version used for the 1.12-era ID/meta -> NBT
    /// bridge. It is old enough to retain `val` semantics and carries an
    /// explicit version so Bedrock's normal block-state upgrader can advance it.
    static let historicalPaletteVersion: Int32 = 0x010C0000

    static func paletteValue(in state: BedrockBlockState) -> UInt8? {
        guard let nbt = state.nbt, let raw = nbt.intValue(named: "val") ?? nbt.intValue(named: "Val") else {
            return nil
        }
        guard (0...255).contains(raw) else { return nil }
        return UInt8(raw)
    }

    static func stateForNumeric(_ state: BedrockBlockState) -> BedrockBlockState {
        let id = state.legacyID ?? 0
        let data = state.legacyData ?? 0
        let identifier = BedrockLegacyBlockCatalog.identifier(forNumericID: id) ?? state.name
        if let states = exactStates(identifier: identifier, legacyID: id, data: data) {
            return nbtState(identifier: identifier, states: states, version: historicalPaletteVersion)
        }
        // Unknown metadata meanings are preserved as the historical `val`
        // field instead of being discarded. This is also the native form that
        // older v1/v8 disk palettes may already contain.
        return BedrockBlockState(
            nbt: .compound([
                NBTNamedTag(name: "name", value: .string(identifier)),
                NBTNamedTag(name: "val", value: .short(Int16(data))),
                NBTNamedTag(name: "version", value: .int(historicalPaletteVersion))
            ]),
            legacyID: nil,
            legacyData: nil
        )
    }

    /// Converts a val-only palette entry to structured states when MCBEEditor
    /// knows the mapping. Returns nil for unrecognised combinations so callers
    /// can preserve `val` unchanged rather than create an invalid mixed form.
    static func structuredStateIfKnown(_ state: BedrockBlockState) -> BedrockBlockState? {
        guard let data = paletteValue(in: state) else { return state.nbt == nil ? nil : state }
        guard let block = BedrockLegacyBlockCatalog.block(forIdentifier: state.name),
              (0...255).contains(block.id) else { return nil }
        let legacyID = UInt16(block.id)
        guard let states = exactStates(identifier: state.name, legacyID: legacyID, data: data) else { return nil }
        return nbtState(
            identifier: state.name,
            states: states,
            version: state.paletteVersion ?? historicalPaletteVersion
        )
    }

    static func visibleProperties(for state: BedrockBlockState) -> [(String, String)]? {
        guard let val = paletteValue(in: state) else { return nil }
        if let structured = structuredStateIfKnown(state), structured.name == state.name,
           let nbt = structured.nbt, case .compound(let tags)? = nbt.compoundValue(named: "states") {
            return tags.map { ($0.name, $0.value.summary) }
                .sorted { $0.0.localizedStandardCompare($1.0) == .orderedAscending }
        }
        return [("legacy_val", String(val))]
    }

    private static func nbtState(
        identifier: String, states: [NBTNamedTag], version: Int32
    ) -> BedrockBlockState {
        BedrockBlockState(
            nbt: .compound([
                NBTNamedTag(name: "name", value: .string(identifier)),
                NBTNamedTag(name: "states", value: .compound(states)),
                NBTNamedTag(name: "version", value: .int(version))
            ]),
            legacyID: nil,
            legacyData: nil
        )
    }

    /// High-confidence mappings for the most common metadata-driven families.
    /// Other combinations intentionally fall back to versioned `val` storage.
    private static func exactStates(
        identifier: String, legacyID: UInt16, data: UInt8
    ) -> [NBTNamedTag]? {
        let value = Int(data)
        let colors = [
            "white", "orange", "magenta", "light_blue", "yellow", "lime", "pink", "gray",
            "silver", "cyan", "purple", "blue", "brown", "green", "red", "black"
        ]
        let normalized = identifier.lowercased()
        // Bedrock IDs differ from Java: 236/237 are concrete/powder;
        // 251/252 are observer/structure_block and must preserve their val.
        if [35, 159, 160, 171, 218, 236, 237, 241, 254].contains(Int(legacyID)), value < colors.count {
            return [NBTNamedTag(name: "color", value: .string(colors[value]))]
        }
        if legacyID == 5 {
            let woods = ["oak", "spruce", "birch", "jungle", "acacia", "dark_oak"]
            guard value < woods.count else { return nil }
            return [NBTNamedTag(name: "wood_type", value: .string(woods[value]))]
        }
        if legacyID == 1 {
            let types = ["stone", "granite", "granite_smooth", "diorite", "diorite_smooth", "andesite", "andesite_smooth"]
            guard value < types.count else { return nil }
            return [NBTNamedTag(name: "stone_type", value: .string(types[value]))]
        }
        if legacyID == 3 {
            let types = ["normal", "coarse"]
            guard value < types.count else { return nil }
            return [NBTNamedTag(name: "dirt_type", value: .string(types[value]))]
        }
        if legacyID == 12 {
            let types = ["normal", "red"]
            guard value < types.count else { return nil }
            return [NBTNamedTag(name: "sand_type", value: .string(types[value]))]
        }
        if legacyID == 24 {
            let types = ["default", "heiroglyphs", "cut", "smooth"]
            guard value < types.count else { return nil }
            return [NBTNamedTag(name: "sand_stone_type", value: .string(types[value]))]
        }
        if legacyID == 155 {
            let types = ["default", "chiseled", "lines", "smooth"]
            guard value < types.count else { return nil }
            return [NBTNamedTag(name: "chisel_type", value: .string(types[value]))]
        }
        if legacyID == 168 {
            let types = ["default", "dark", "bricks"]
            guard value < types.count else { return nil }
            return [NBTNamedTag(name: "prismarine_block_type", value: .string(types[value]))]
        }
        if legacyID == 179 {
            let types = ["default", "heiroglyphs", "cut", "smooth"]
            guard value < types.count else { return nil }
            return [NBTNamedTag(name: "sand_stone_type", value: .string(types[value]))]
        }
        // Data zero for blocks without a special mapping is safe to express as
        // an empty state compound. Non-zero data is never guessed.
        if data == 0, normalized != "minecraft:unknown" {
            return []
        }
        return nil
    }
}
