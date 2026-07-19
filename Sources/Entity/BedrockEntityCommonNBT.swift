import Foundation

/// Common Bedrock entity tags used by the empty-entity creator and the summon
/// command. Type-specific tags are intentionally left to copied/imported NBT.
enum BedrockEntityCommonNBT {
    static func tags(
        identifier: String,
        position: BedrockWorldObjectPosition,
        dimension: Int32,
        uniqueID: Int64
    ) -> [NBTNamedTag] {
        [
            NBTNamedTag(name: "definitions", value: .list(.string, [.string("+\(identifier)")])),
            NBTNamedTag(name: "UniqueID", value: .long(uniqueID)),
            NBTNamedTag(name: "Air", value: .short(300)),
            NBTNamedTag(name: "Chested", value: .byte(0)),
            NBTNamedTag(name: "Color", value: .byte(0)),
            NBTNamedTag(name: "Color2", value: .byte(0)),
            NBTNamedTag(name: "CustomName", value: .string("")),
            NBTNamedTag(name: "CustomNameVisible", value: .byte(0)),
            NBTNamedTag(name: "Dead", value: .byte(0)),
            NBTNamedTag(name: "DeathTime", value: .short(0)),
            NBTNamedTag(name: "DimensionId", value: .int(dimension)),
            NBTNamedTag(name: "FallDistance", value: .float(0)),
            NBTNamedTag(name: "Fire", value: .short(0)),
            NBTNamedTag(name: "HasBoundOrigin", value: .byte(0)),
            NBTNamedTag(name: "Invulnerable", value: .byte(0)),
            NBTNamedTag(name: "IsAngry", value: .byte(0)),
            NBTNamedTag(name: "IsAutonomous", value: .byte(0)),
            NBTNamedTag(name: "IsBaby", value: .byte(0)),
            NBTNamedTag(name: "IsEating", value: .byte(0)),
            NBTNamedTag(name: "IsGliding", value: .byte(0)),
            NBTNamedTag(name: "IsGlobal", value: .byte(0)),
            NBTNamedTag(name: "IsIllagerCaptain", value: .byte(0)),
            NBTNamedTag(name: "IsOrphaned", value: .byte(0)),
            NBTNamedTag(name: "IsOutOfControl", value: .byte(0)),
            NBTNamedTag(name: "IsRoaring", value: .byte(0)),
            NBTNamedTag(name: "IsScared", value: .byte(0)),
            NBTNamedTag(name: "IsStunned", value: .byte(0)),
            NBTNamedTag(name: "IsSwimming", value: .byte(0)),
            NBTNamedTag(name: "IsTamed", value: .byte(0)),
            NBTNamedTag(name: "IsTrusting", value: .byte(0)),
            NBTNamedTag(name: "LastDimensionId", value: .int(dimension)),
            NBTNamedTag(name: "LootDropped", value: .byte(0)),
            NBTNamedTag(name: "MarkVariant", value: .int(0)),
            NBTNamedTag(name: "Motion", value: .list(.float, [.float(0), .float(0), .float(0)])),
            NBTNamedTag(name: "OnGround", value: .byte(1)),
            NBTNamedTag(name: "OwnerNew", value: .long(-1)),
            NBTNamedTag(name: "Persistent", value: .byte(1)),
            NBTNamedTag(name: "PortalCooldown", value: .int(0)),
            NBTNamedTag(name: "Pos", value: .list(.float, [
                .float(Float(position.x)), .float(Float(position.y)), .float(Float(position.z))
            ])),
            NBTNamedTag(name: "Rotation", value: .list(.float, [.float(0), .float(0)])),
            NBTNamedTag(name: "Saddled", value: .byte(0)),
            NBTNamedTag(name: "Sheared", value: .byte(0)),
            NBTNamedTag(name: "ShowBottom", value: .byte(0)),
            NBTNamedTag(name: "Sitting", value: .byte(0)),
            NBTNamedTag(name: "SkinID", value: .int(0)),
            NBTNamedTag(name: "Strength", value: .int(0)),
            NBTNamedTag(name: "StrengthMax", value: .int(0)),
            NBTNamedTag(name: "Tags", value: .list(.string, [])),
            NBTNamedTag(name: "Variant", value: .int(0))
        ]
    }

    static func addingMissingTopLevel(_ defaults: [NBTNamedTag], to root: NBTValue) throws -> NBTValue {
        guard case .compound(var tags) = root else {
            throw MCBEEditorError.malformedData("实体 NBT 根必须是 Compound")
        }
        var existing = Set(tags.map { $0.name.lowercased() })
        for tag in defaults where existing.insert(tag.name.lowercased()).inserted {
            tags.append(tag)
        }
        return .compound(tags)
    }

    static func mergingTopLevel(_ additions: [NBTNamedTag], into root: NBTValue) throws -> NBTValue {
        guard case .compound(var tags) = root else {
            throw MCBEEditorError.malformedData("实体 NBT 根必须是 Compound")
        }
        for addition in additions {
            if let index = tags.firstIndex(where: { $0.name.caseInsensitiveCompare(addition.name) == .orderedSame }) {
                tags[index] = addition
            } else {
                tags.append(addition)
            }
        }
        return .compound(tags)
    }

    static func identifier(in root: NBTValue) -> String? {
        if let raw = root.stringValue(namedAny: ["identifier", "Identifier", "id", "Id"]), raw.contains(":") {
            return normalizedIdentifier(raw)
        }
        if let definitions = root.value(namedAny: ["definitions", "Definitions"])?.listValues {
            for value in definitions.reversed() {
                guard case .string(var text) = value else { continue }
                while text.first == "+" || text.first == "-" { text.removeFirst() }
                if text.contains(":") { return normalizedIdentifier(text) }
            }
        }
        if let numeric = root.int64Value(namedAny: ["id", "Id"]),
           let entry = BedrockDataValueCatalog.entity(forNumericID: numeric) {
            return entry.identifier
        }
        return nil
    }

    static func position(in root: NBTValue) -> BedrockWorldObjectPosition? {
        guard let values = root.value(namedAny: ["Pos", "pos", "Position", "position"])?.listValues,
              values.count >= 3,
              let x = values[0].numericDoubleValue,
              let y = values[1].numericDoubleValue,
              let z = values[2].numericDoubleValue else { return nil }
        return BedrockWorldObjectPosition(x: x, y: y, z: z)
    }

    static func dimension(in root: NBTValue) -> Int32? {
        root.int64Value(namedAny: ["DimensionId", "DimensionID", "Dimension", "dimension"])
            .map { Int32(clamping: $0) }
    }

    static func uniqueID(in root: NBTValue) -> Int64? {
        root.int64Value(namedAny: ["UniqueID", "UniqueId", "uniqueID", "uniqueId"])
    }

    private static func normalizedIdentifier(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.contains(":") ? trimmed : "minecraft:\(trimmed)"
    }
}
