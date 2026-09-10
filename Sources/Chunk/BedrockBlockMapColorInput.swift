import Foundation

/// Shared colour input for top-down maps and X/Z sections. The actual block
/// identifier remains authoritative for Textures/Colors.txt overrides; only
/// the built-in colour lookup receives a name resolved from palette states.
struct BedrockBlockMapColorInput {
    let identifier: String
    let variantIdentifier: String
    let legacyID: UInt16?
    let legacyData: UInt8?

    init(state: BedrockBlockState?) {
        let name = state?.name ?? "minecraft:air"
        identifier = name
        let historicalValue = state.flatMap { BedrockLegacyBlockStateConverter.paletteValue(in: $0) }
        let historicalID = historicalValue.flatMap { _ in
            BedrockLegacyBlockCatalog.block(forIdentifier: name).flatMap { UInt16(exactly: $0.id) }
        }
        legacyID = state?.legacyID ?? historicalID
        legacyData = state?.legacyData ?? historicalValue

        var properties = [String: String]()
        if let nbt = state?.nbt, case .compound(let tags)? = nbt.compoundValue(named: "states") {
            for tag in tags {
                if case .string(let value) = tag.value { properties[tag.name.lowercased()] = value }
            }
        }
        variantIdentifier = BedrockBlockMapColorCatalog.variantIdentifier(for: name, properties: properties)
    }
}
