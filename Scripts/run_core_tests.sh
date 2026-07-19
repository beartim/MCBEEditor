#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="${TMPDIR:-/tmp}/mcbeeditor-core-test"
mkdir -p "$TMP"
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

@main
struct Main {
    static func main() throws {
        let source = NBTDocument(rootName: "", root: .compound([
            NBTNamedTag(name: "LevelName", value: .string("测试世界")),
            NBTNamedTag(name: "Seed", value: .long(-123456789)),
            NBTNamedTag(name: "SpawnX", value: .int(42)),
            NBTNamedTag(name: "List", value: .list(.int, [.int(-1), .int(0), .int(99)]))
        ]))
        let encoded = try BedrockNBTCodec.encode(source)
        let decoded = try BedrockNBTCodec.decode(encoded)
        let reencoded = try BedrockNBTCodec.encode(decoded)
        precondition(reencoded == encoded)
        precondition(decoded.root.stringValue(named: "LevelName") == "测试世界")

        let jsonData = try NBTJSONCodec.encode([source])
        let jsonDocuments = try NBTJSONCodec.decode(jsonData)
        precondition(jsonDocuments.count == 1)
        precondition(jsonDocuments[0].root.stringValue(named: "LevelName") == "测试世界")
        let ordinaryJSON = try NBTJSONCodec.decode(Data("{\"enabled\":true,\"values\":[1,2,3]}".utf8))
        precondition(ordinaryJSON.count == 1)
        precondition(ordinaryJSON[0].root.type == .compound)

        let entityJSON = try NBTJSONCodec.encodeEntityDocument(source)
        let entityDocuments = try NBTJSONCodec.decodeEntityDocuments(entityJSON)
        precondition(entityDocuments.count == 1)
        precondition(entityDocuments[0].root.stringValue(named: "LevelName") == "测试世界")
        let entityJSONObject = try JSONSerialization.jsonObject(with: entityJSON) as? [String: Any]
        let entityTagDocuments = entityJSONObject?["documents"] as? [[String: Any]]
        precondition(entityTagDocuments?.count == 4)
        precondition(entityTagDocuments?.first?["name"] as? String == "LevelName")


        let clipboardDocuments = [
            NBTDocument(rootName: "First", root: .int(1)),
            NBTDocument(rootName: "Second", root: .string("two")),
            NBTDocument(rootName: "Third", root: .compound([
                NBTNamedTag(name: "value", value: .long(3))
            ]))
        ]
        let clipboardPayload = try NBTClipboardCodec.encodeBatch(clipboardDocuments)
        precondition(NBTClipboardCodec.isBatchPayload(clipboardPayload))
        let clipboardRoundTrip = try NBTClipboardCodec.decodeBatch(clipboardPayload)
        precondition(clipboardRoundTrip.count == 3)
        precondition(clipboardRoundTrip.map(\.rootName) == ["First", "Second", "Third"])
        if case .int(let value) = clipboardRoundTrip[0].root { precondition(value == 1) }
        else { preconditionFailure("first clipboard tag changed type") }
        if case .string(let value) = clipboardRoundTrip[1].root { precondition(value == "two") }
        else { preconditionFailure("second clipboard tag changed type") }
        if case .compound(let tags) = clipboardRoundTrip[2].root,
           case .long(let value)? = tags.first(where: { $0.name == "value" })?.value {
            precondition(value == 3)
        } else {
            preconditionFailure("third clipboard tag changed type")
        }

        for value in [Int32.min, -1000, -1, 0, 1, 1000, Int32.max] {
            var writer = BinaryWriter()
            writer.writeSignedVarInt(value)
            var cursor = BinaryCursor(data: writer.data)
            let roundTrip = try cursor.readSignedVarInt32()
            precondition(roundTrip == value)
        }

        let key = BedrockDBKey.subChunk(x: -12, z: 34, dimension: 1, index: -4)
        let parsed = BedrockDBKey.parse(key)
        precondition(parsed?.position.x == -12)
        precondition(parsed?.position.z == 34)
        precondition(parsed?.position.dimension == 1)
        precondition(parsed?.subChunkIndex == -4)

        precondition(MapCoordinate.chunk(fromBlock: 0) == 0)
        precondition(MapCoordinate.chunk(fromBlock: 15) == 0)
        precondition(MapCoordinate.chunk(fromBlock: 16) == 1)
        precondition(MapCoordinate.chunk(fromBlock: -1) == -1)
        precondition(MapCoordinate.chunk(fromBlock: -16) == -1)
        precondition(MapCoordinate.chunk(fromBlock: -17) == -2)
        precondition(MapCoordinate.absoluteBlock(chunk: -2, local: 15) == -17)
        precondition(MapCoordinate.chunk(fromBlock: Int64(-1)) == -1)
        precondition(MapCoordinate.chunk(fromBlock: Int64(-17)) == -2)
        precondition(MapCoordinate.chunk(fromBlock: Int64(Int32.max) * 16) == Int32.max)
        precondition(MapCoordinate.chunkDistance(fromBlockDistance: 64) == 4)
        precondition(MapCoordinate.chunkDistance(fromBlockDistance: 65) == 5)
        precondition(MapCoordinate.blockDistance(fromChunkDistance: 4) == 64)

        let originalCompound: NBTValue = .compound([
            NBTNamedTag(name: "A", value: .int(1)),
            NBTNamedTag(name: "B", value: .int(2))
        ])
        let overwrittenCompound = try NBTTreeMutation.adding(
            .int(9), named: "A", to: [], in: originalCompound, replacingExisting: true
        )
        precondition(overwrittenCompound.intValue(named: "A") == 9)
        precondition(overwrittenCompound.intValue(named: "B") == 2)
        do {
            _ = try NBTTreeMutation.adding(.int(7), named: "A", to: [], in: originalCompound)
            preconditionFailure("duplicate Compound insertion should fail without overwrite")
        } catch {}

        // Reference coordinates from the original Android MCBEEditor
        // Bedrock slime-chunk implementation. The calculation is independent
        // of the world seed and must preserve signed chunk-coordinate wrapping.
        precondition(BedrockSlimeChunk.isSlimeChunk(x: -1, z: 0))
        precondition(BedrockSlimeChunk.isSlimeChunk(x: 3, z: 1))
        precondition(BedrockSlimeChunk.isSlimeChunk(x: 0, z: 4))
        precondition(!BedrockSlimeChunk.isSlimeChunk(x: 0, z: 0))
        precondition(!BedrockSlimeChunk.isSlimeChunk(x: 1, z: 1))

        let region = BedrockMapRegion(minimumX: -17, minimumZ: -1, maximumX: 18, maximumZ: 32, dimension: 0)
        precondition(region.minimumChunkX == -2)
        precondition(region.maximumChunkX == 1)
        precondition(region.minimumChunkZ == -1)
        precondition(region.maximumChunkZ == 2)
        precondition(region.width == 36 && region.depth == 34)
        precondition(region.chunkCount == 16)
        precondition(!region.isChunkAligned)
        let alignedRegion = region.expandedToChunkBounds
        precondition(alignedRegion.minimumX == -32 && alignedRegion.maximumX == 31)
        precondition(alignedRegion.minimumZ == -16 && alignedRegion.maximumZ == 47)
        precondition(alignedRegion.isChunkAligned)
        let translatedRegion = region.translated(toMinimumX: 100, minimumZ: -100, dimension: 2)
        precondition(translatedRegion.minimumX == 100 && translatedRegion.maximumX == 135)
        precondition(translatedRegion.minimumZ == -100 && translatedRegion.maximumZ == -67)
        precondition(translatedRegion.dimension == 2)
        let negativeChunk = ChunkPosition(x: -2, z: -1, dimension: 0)
        let localRanges = region.localRanges(in: negativeChunk)
        precondition(localRanges?.x == 15...15)
        precondition(localRanges?.z == 15...15)

        precondition(BedrockDataValueCatalog.entities.first { $0.id == 44 }?.displayName == "僵尸村民（旧版）")
        precondition(BedrockDataValueCatalog.entities.first { $0.id == 70 }?.displayName == "末影之眼")
        precondition(BedrockDataValueCatalog.entities.first { $0.id == 79 }?.displayName == "末影龙火球")
        precondition(BedrockDataValueCatalog.entities.first { $0.id == 116 }?.displayName == "僵尸村民")
        precondition(BedrockDataValueCatalog.entities.first { $0.id == 145 }?.displayName == "不祥之物生成器")
        precondition(BedrockDataValueCatalog.entities.first { $0.id == 154 }?.identifier == "minecraft:cushion")
        precondition(BedrockDataValueCatalog.entities.first { $0.id == 154 }?.hexadecimalID == "0x9A")
        precondition(BedrockDataValueCatalog.entity(forNumericID: 44)?.identifier == "minecraft:zombie_villager")
        precondition(BedrockDataValueCatalog.entityIdentifier(forRawValue: "70") == "minecraft:eye_of_ender_signal")
        precondition(BedrockDataValueCatalog.entityIdentifier(forRawValue: "0x9A") == "minecraft:cushion")
        precondition(BedrockDataValueCatalog.statusEffects.first { $0.id == 1 }?.displayName == "迅捷")
        precondition(BedrockDataValueCatalog.statusEffects.first { $0.id == 31 }?.identifier == "trial_omen")
        precondition(BedrockDataValueCatalog.statusEffects.first { $0.id == 37 }?.identifier == "breath_of_the_nautilus")
        precondition(BedrockDataValueCatalog.enchantments.first { $0.id == 38 }?.identifier == "wind_burst")
        precondition(BedrockDataValueCatalog.enchantments.first { $0.id == 41 }?.identifier == "lunge")
        precondition(Set(BedrockDataValueCatalog.entities.map(\.id)).count == BedrockDataValueCatalog.entities.count)
        precondition(BedrockLegacyBlockCatalog.blocks.count == 256)
        precondition(BedrockLegacyBlockCatalog.block(forNumericID: 1)?.identifier == "minecraft:stone")
        precondition(BedrockLegacyBlockCatalog.block(forNumericID: 5)?.identifier == "minecraft:planks")
        precondition(BedrockLegacyBlockCatalog.block(forIdentifier: "minecraft:grass")?.id == 2)
        precondition(BedrockLegacyBlockCatalog.block(forIdentifier: "minecraft:oak_planks")?.id == 5)
        precondition(BedrockLegacyBlockCatalog.blockIdentifier(forRawValue: "0xA6") == "minecraft:unused_166")
        let legacyStone = BedrockBlockState(nbt: nil, legacyID: 1, legacyData: 0)
        precondition(legacyStone.name == "minecraft:stone")
        precondition(BedrockLegacyBlockCatalog.searchText(for: legacyStone).contains("0x01"))

        let fillCommand = try WorldCommandParser.parse("fill the_end 0 0 0 60 200 16 minecraft:leaves 'String'\"old_leaf_type\"=\"oak\",'Byte'\"persistent_bit\"=\"0\",'Byte'\"update_bit\"=\"0\" minecraft:chest 'Int'\"facing_direction\"=\"3\"")
        if case .fill(let dimension, let box, let layer0, let layer1) = fillCommand {
            precondition(dimension == 2)
            precondition(box.minimum.x == 0 && box.maximum.y == 200 && box.maximum.z == 16)
            precondition(layer0.name == "minecraft:leaves" && layer0.states.count == 3)
            precondition(layer1.name == "minecraft:chest" && layer1.states.count == 1)
        } else {
            preconditionFailure("fill command parsed as wrong command")
        }
        _ = try WorldCommandParser.parse("clone overworld 0 0 0 1 2 3 nether 10 20 30")
        let overlapSource = CommandBlockBox(
            CommandBlockCoordinate(x: 0, y: 70, z: 0),
            CommandBlockCoordinate(x: 4, y: 70, z: 4)
        )
        let overlapTarget = CommandBlockBox(
            CommandBlockCoordinate(x: 1, y: 70, z: 1),
            CommandBlockCoordinate(x: 5, y: 70, z: 5)
        )
        let traversal = CommandCloneTraversal(source: overlapSource, target: overlapTarget, sameDimension: true)
        precondition(traversal.startX == 4 && traversal.stepX == -1)
        precondition(traversal.startZ == 4 && traversal.stepZ == -1)
        var simulated = [String: Bool]()
        simulated["0,0"] = true
        var sx = traversal.startX
        while sx >= overlapSource.minimum.x {
            var sz = traversal.startZ
            while sz >= overlapSource.minimum.z {
                simulated["\(sx + 1),\(sz + 1)"] = simulated["\(sx),\(sz)"] ?? false
                sz += traversal.stepZ
            }
            sx += traversal.stepX
        }
        let copiedStoneTargets = simulated.compactMap { key, value -> String? in
            guard value, key != "0,0" else { return nil }
            return key
        }
        precondition(copiedStoneTargets == ["1,1"])
        _ = try WorldCommandParser.parse("help fill")
        _ = try WorldCommandParser.parse("clear -123456789")
        _ = try WorldCommandParser.parse("clear @e")
        _ = try WorldCommandParser.parse("clearspawnpoint @a")
        _ = try WorldCommandParser.parse("give minecraft:cow Auto minecraft:redstone_wire 97 NULL")
        _ = try WorldCommandParser.parse("give minecraft:cow 2 minecraft:lit_smoker 99 'Compound'\"tag\"=\"{'Byte'\"Unbreakable\"=\"1\"}\",'Short'\"Damage\"=\"1\"")
        let byteArrayTags = try WorldCommandParser.parseStates("'ByteArray'\"Name\"=\"[0,1]\"")
        precondition(byteArrayTags.count == 1)
        let intArrayListTags = try WorldCommandParser.parseStates("'List''IntArray'\"Name\"=\"[],[5,2]\"")
        if case .list(.intArray, let values) = intArrayListTags[0].value { precondition(values.count == 2) } else { preconditionFailure("List<IntArray> parse failed") }
        let nestedCompoundTags = try WorldCommandParser.parseStates("'Compound'\"Name\"=\"{'String'\"Name\"=\"Tom\",'List''Int'\"Num\"=\"1,2,3,4\"}\"")
        if case .compound(let values) = nestedCompoundTags[0].value { precondition(values.count == 2) } else { preconditionFailure("nested Compound parse failed") }
        let compoundListTags = try WorldCommandParser.parseStates("'List''Compound'\"Name\"=\"{'Int'\"Num\"=\"0\"},{}\"")
        if case .list(.compound, let values) = compoundListTags[0].value { precondition(values.count == 2) } else { preconditionFailure("List<Compound> parse failed") }
        _ = try WorldCommandParser.parse("kill @a 1")
        _ = try WorldCommandParser.parse("kick @a")
        _ = try WorldCommandParser.parse("summon minecraft:pig overworld 0 64 0 'Byte'\"Invulnerable\"=\"1\",'String'\"CustomName\"=\"MyPig\"")
        _ = try WorldCommandParser.parse("summon minecraft:pig overworld 0 64 0 default")
        let effectGive = try WorldCommandParser.parse("effect give @a strength 12000 50")
        guard case .effect(.give(let duration, let amplifier), .allPlayers, .single(let effectEntry)) = effectGive else {
            preconditionFailure("effect give parsed as wrong command")
        }
        precondition(duration == 12000 && amplifier == 50)
        precondition(effectEntry.id == 5 && effectEntry.identifier == "strength")
        let effectClear = try WorldCommandParser.parse("effect clear @e ALL")
        guard case .effect(.clear, .allEntities, .all) = effectClear else {
            preconditionFailure("effect clear parsed as wrong command")
        }
        _ = try WorldCommandParser.parse("setblock overworld 1 64 2 minecraft:stone NULL minecraft:air NULL")
        _ = try WorldCommandParser.parse("setworldspawn 0 80 0")
        _ = try WorldCommandParser.parse("spawnpoint @a the_end 0 100 0")
        _ = try WorldCommandParser.parse("teleport -4294967270 the_end 10 70 10")
        _ = try WorldCommandParser.parse("teleport @a overworld 0 Auto 0")
        _ = try WorldCommandParser.parse("teleport minecraft:cow overworld 0 64 0")
        _ = try WorldCommandParser.parse("spread @e")
        _ = try WorldCommandParser.parse("spread minecraft:cow")
        _ = try WorldCommandParser.parse("daylock 0")
        _ = try WorldCommandParser.parse("daylock 1")
        _ = try WorldCommandParser.parse("experience add @a -100")
        _ = try WorldCommandParser.parse("experience addlevel @s 5")
        _ = try WorldCommandParser.parse("experience level @s 30")
        _ = try WorldCommandParser.parse("experience percent @s 0.5")
        _ = try WorldCommandParser.parse("experience query @a")
        _ = try WorldCommandParser.parse("experience set @s 250")
        _ = try WorldCommandParser.parse("time query daytime")
        _ = try WorldCommandParser.parse("time query gametime")
        _ = try WorldCommandParser.parse("time query day")
        _ = try WorldCommandParser.parse("time add -1000")
        _ = try WorldCommandParser.parse("time set 12013000")
        _ = try WorldCommandParser.parse("time ceil sunset")
        _ = try WorldCommandParser.parse("time floor midnight")
        _ = try WorldCommandParser.parse("weather clear 1")
        _ = try WorldCommandParser.parse("weather rain 6000 0.5 1")
        _ = try WorldCommandParser.parse("weather thunder 12000 1.0 0")
        _ = try WorldCommandParser.parse("structure save mystructure:1 overworld 0 0 0 50 50 50")
        _ = try WorldCommandParser.parse("structure load mystructure:1 nether 9 50 9")
        _ = try WorldCommandParser.parse("structure delete ALL")
        _ = try WorldCommandParser.parse("tickingarea add square nether 0 0 1 1 Base 1")
        _ = try WorldCommandParser.parse("tickingarea add circle overworld 0 0 4 Circle 0")
        _ = try WorldCommandParser.parse("tickingarea delete ALL")
        _ = try WorldCommandParser.parse("tickingarea list overworld")
        let effectRoot = NBTValue.compound([
            NBTNamedTag(name: "UniqueID", value: .long(99))
        ])
        let givenEffect = try CommandEffectNBT.applying(
            operation: .give(duration: 12000, amplifier: 50),
            selection: .single(effectEntry),
            to: effectRoot
        )
        precondition(givenEffect.changed)
        guard case .list(.compound, let activeValues)? = givenEffect.value.compoundValue(named: "ActiveEffects"),
              activeValues.count == 1,
              case .compound(let activeTags) = activeValues[0] else {
            preconditionFailure("effect give did not create ActiveEffects Compound List")
        }
        func effectTag(_ name: String) -> NBTValue? {
            activeTags.first { $0.name == name }?.value
        }
        func effectNumber(_ name: String) -> Int64? {
            switch effectTag(name) {
            case .byte(let value): return Int64(value)
            case .short(let value): return Int64(value)
            case .int(let value): return Int64(value)
            case .long(let value): return value
            default: return nil
            }
        }
        precondition(effectNumber("Id") == 5)
        precondition(effectNumber("Amplifier") == 50)
        precondition(effectNumber("Duration") == 12000)
        precondition(effectNumber("DurationEasy") == 12000)
        precondition(effectNumber("DurationNormal") == 12000)
        precondition(effectNumber("DurationHard") == 12000)
        precondition(effectNumber("Ambient") == 0)
        precondition(effectNumber("DisplayOnScreenTextureAnimation") == 0)
        precondition(effectNumber("ShowParticles") == 0)
        precondition(activeTags.first { $0.name == "FactorCalculationData" } == nil)
        let clearedEffect = try CommandEffectNBT.applying(
            operation: .clear,
            selection: .single(effectEntry),
            to: givenEffect.value
        )
        precondition(clearedEffect.changed)
        precondition(clearedEffect.value.compoundValue(named: "ActiveEffects") == nil)
        let allEffects = try CommandEffectNBT.applying(
            operation: .give(duration: 40, amplifier: 0),
            selection: .all,
            to: effectRoot
        )
        guard case .list(.compound, let allValues)? = allEffects.value.compoundValue(named: "ActiveEffects") else {
            preconditionFailure("effect give ALL did not create ActiveEffects")
        }
        precondition(allValues.count == BedrockDataValueCatalog.statusEffects.count)
        do {
            _ = try WorldCommandParser.parse("effect clear @e ALL 1")
            preconditionFailure("effect clear must reject extra parameters")
        } catch {}
        do {
            _ = try WorldCommandParser.parse("time set -1")
            preconditionFailure("time set must reject negative values")
        } catch {}
        do {
            _ = try WorldCommandParser.parse("daylock 2")
            preconditionFailure("daylock must accept only zero or one")
        } catch {}
        do {
            _ = try WorldCommandParser.parse("spread @e extra")
            preconditionFailure("spread must accept exactly one target")
        } catch {}
        do {
            _ = try WorldCommandParser.parse("experience amount @a 1")
            preconditionFailure("removed experience amount alias must fail")
        } catch {}
        do {
            _ = try WorldCommandParser.parse("experience level @s 24792")
            preconditionFailure("experience level must remain within 0 through 24791")
        } catch {}
        do {
            _ = try WorldCommandParser.parse("give @s 36 minecraft:stone 1 NULL")
            preconditionFailure("give Slot must remain within 0 through 35")
        } catch {}
        do {
            _ = try WorldCommandParser.parse("experience percent @s 1.1")
            preconditionFailure("experience percent must remain within zero and one")
        } catch {}
        do {
            _ = try WorldCommandParser.parse("experience query @a 1")
            preconditionFailure("experience query must reject extra parameters")
        } catch {}
        do {
            _ = try WorldCommandParser.parse("experience set @s -1")
            preconditionFailure("experience set must reject negative total XP")
        } catch {}
        do {
            _ = try WorldCommandParser.parse("time ceil dusk")
            preconditionFailure("time ceil must reject unknown periods")
        } catch {}
        do {
            _ = try WorldCommandParser.parse("weather rain 12000 1.1 0")
            preconditionFailure("weather intensity above one should fail")
        } catch {}
        do {
            _ = try WorldCommandParser.parse("tickingarea add circle overworld 0 0 Circle 0")
            preconditionFailure("circle tickingarea must require a radius")
        } catch {}
        do {
            _ = try WorldCommandParser.parse("tickingarea add circle overworld 0 0 5 Circle 0")
            preconditionFailure("circle tickingarea radius above four should fail")
        } catch {}
        do {
            _ = try WorldCommandParser.parse("effect give @a unknown_effect 20 0")
            preconditionFailure("effect must reject identifiers without numeric IDs")
        } catch {}
        do {
            _ = try WorldCommandParser.parse("clear")
            preconditionFailure("clear must require one target")
        } catch {}
        do {
            _ = try WorldCommandParser.parse("kill @e 2")
            preconditionFailure("kill boolean must be 0 or 1")
        } catch {}
        do {
            _ = try WorldCommandParser.parse("kick @e")
            preconditionFailure("kick must reject non-player selectors")
        } catch {}
        do {
            _ = try WorldCommandParser.parse("fill overworld 0 0 0 1 1 1 minecraft:stone NULL minecraft:air")
            preconditionFailure("fill must reject missing layer 1 states")
        } catch {}
        do {
            _ = try WorldCommandParser.parse("/help")
            preconditionFailure("commands must reject a slash prefix")
        } catch {}
        print("MCBEEditor core tests passed")
    }
}
SWIFT

swiftc \
  "$ROOT/Sources/Support/Errors.swift" \
  "$ROOT/Sources/Support/Hex.swift" \
  "$ROOT/Sources/Support/BedrockDataValueCatalog.swift" \
  "$ROOT/Sources/Support/BedrockLegacyBlockCatalog.swift" \
  "$ROOT/Sources/NBT/NBTTypes.swift" \
  "$ROOT/Sources/NBT/NBTJSONCodec.swift" \
  "$ROOT/Sources/NBT/NBTClipboardCodec.swift" \
  "$ROOT/Sources/NBT/BinaryCursor.swift" \
  "$ROOT/Sources/NBT/BedrockNBTCodec.swift" \
  "$ROOT/Sources/UI/NBTNode.swift" \
  "$ROOT/Sources/Chunk/BedrockDBKey.swift" \
  "$ROOT/Sources/Chunk/MapCoordinate.swift" \
  "$ROOT/Sources/Chunk/BedrockSlimeChunk.swift" \
  "$ROOT/Sources/Chunk/BedrockMapRegion.swift" \
  "$ROOT/Sources/Chunk/BedrockSubChunk.swift" \
  "$ROOT/Sources/Command/WorldCommand.swift" \
  -parse-as-library "$TMP/main.swift" -o "$TMP/core-tests"

# The repository intentionally has one deployment target only.
[[ -f "$ROOT/project.yml" ]] || {
  echo "error: project.yml is missing" >&2
  exit 1
}

for expected in \
  'minimumXcodeGenVersion: "2.45.0"' \
  'xcodeVersion: "15.4"' \
  'projectFormat: xcode15_3'; do
  grep -qF "$expected" "$ROOT/project.yml" || {
    echo "error: project.yml is missing Xcode 15 compatibility setting: $expected" >&2
    exit 1
  }
done

if grep -qE 'projectFormat:[[:space:]]*xcode16_|xcodeVersion:[[:space:]]*"?16' "$ROOT/project.yml"; then
  echo "error: project.yml must not request an Xcode 16 project format" >&2
  exit 1
fi

# Release metadata is validated once and independently from feature checks.
# Exact historical versions must never be embedded in import/map/entity tests,
# otherwise every legitimate release bump breaks CI before compilation.
MARKETING_VERSION="$(awk -F':[[:space:]]*' '/^[[:space:]]+MARKETING_VERSION:/ { gsub(/"/, "", $2); print $2; exit }' "$ROOT/project.yml")"
CURRENT_PROJECT_VERSION="$(awk -F':[[:space:]]*' '/^[[:space:]]+CURRENT_PROJECT_VERSION:/ { gsub(/"/, "", $2); print $2; exit }' "$ROOT/project.yml")"

if [[ ! "$MARKETING_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: MARKETING_VERSION must be a semantic version, got: ${MARKETING_VERSION:-<missing>}" >&2
  exit 1
fi
if [[ ! "$CURRENT_PROJECT_VERSION" =~ ^[0-9]+$ ]]; then
  echo "error: CURRENT_PROJECT_VERSION must be an integer, got: ${CURRENT_PROJECT_VERSION:-<missing>}" >&2
  exit 1
fi

if [[ "$MARKETING_VERSION" != "1.0.0" || "$CURRENT_PROJECT_VERSION" != "100" ]]; then
  printf 'error: MCBEEditor version is fixed at 1.0.0 (100), got version=%s build=%s\n' \
    "$MARKETING_VERSION" "$CURRENT_PROJECT_VERSION" >&2
  exit 1
fi

IFS='.' read -r VERSION_MAJOR VERSION_MINOR VERSION_PATCH <<< "$MARKETING_VERSION"
if (( VERSION_MAJOR == 0 && VERSION_MINOR < 9 )) || \
   (( VERSION_MAJOR == 0 && VERSION_MINOR == 9 && VERSION_PATCH < 1 )) || \
   (( CURRENT_PROJECT_VERSION < 11 )); then
  printf 'error: release metadata regressed: version=%s build=%s (minimum 0.9.1 build 11)\n' \
    "$MARKETING_VERSION" "$CURRENT_PROJECT_VERSION" >&2
  exit 1
fi
printf 'Release metadata passed: version=%s build=%s\n' \
  "$MARKETING_VERSION" "$CURRENT_PROJECT_VERSION"

# Never pipe `xcodebuild -version` into a consumer that exits after the first
# line. Xcode 15.4 writes a second line and can throw NSFileHandleOperationException
# when stdout has already been closed by `awk ... exit` or `head`.
if grep -R -nE 'xcodebuild[[:space:]]+-version[[:space:]]*\|' \
  "$ROOT/Scripts" "$ROOT/.github/workflows"; then
  echo 'error: unsafe xcodebuild -version pipeline can trigger Broken pipe' >&2
  exit 1
fi
for version_check in \
  "$ROOT/Scripts/bootstrap.sh" \
  "$ROOT/.github/workflows/build-ios.yml"; do
  grep -qF 'XCODE_VERSION_OUTPUT="$(xcodebuild -version 2>&1)"' "$version_check" || {
    echo "error: safe full-output Xcode version capture is missing: ${version_check#$ROOT/}" >&2
    exit 1
  }
done
echo 'Xcode version Broken-pipe regression check passed'

# XcodeGen maps projectFormat xcode15_3 to objectVersion 63. Xcode 15.4 can
# open that format; only newer object versions must be rejected.
grep -qF 'MAX_XCODE15_OBJECT_VERSION=63' "$ROOT/Scripts/bootstrap.sh" || {
  echo "error: bootstrap.sh must allow Xcode 15.3 project objectVersion 63" >&2
  exit 1
}
if grep -qF 'OBJECT_VERSION > 60' "$ROOT/Scripts/bootstrap.sh"; then
  echo "error: bootstrap.sh incorrectly rejects Xcode 15.3 objectVersion 63" >&2
  exit 1
fi
# Obsolete dual-configuration files are not build inputs. A ZIP overlay cannot
# delete already tracked files, so report them without failing CI. The workflow
# removes them from its workspace and Scripts/cleanup_ios13_only.sh can remove
# them from Git permanently.
for obsolete in \
  "$ROOT/project-ios13-legacy.yml" \
  "$ROOT/Scripts/bootstrap_ios13_legacy.sh"; do
  if [[ -e "$obsolete" ]]; then
    echo "warning: obsolete file is still present but is not used: ${obsolete#$ROOT/}" >&2
  fi
done

# Active bootstrap/build scripts must not select an obsolete spec. Cleanup
# mentions in the workflow (`rm -f ...`) are intentionally allowed.
if grep -InE 'project-ios13-legacy\.yml|bootstrap_ios13_legacy\.sh' \
  "$ROOT/Scripts/bootstrap.sh" \
  "$ROOT/Scripts/build_unsigned_ipa.sh" >/dev/null 2>&1; then
  echo "error: active build scripts still reference an obsolete iOS configuration" >&2
  exit 1
fi
if grep -RInE 'bash[[:space:]]+Scripts/bootstrap_ios13_legacy\.sh|\./Scripts/bootstrap_ios13_legacy\.sh' \
  "$ROOT/.github/workflows" >/dev/null 2>&1; then
  echo "error: a workflow still invokes bootstrap_ios13_legacy.sh" >&2
  exit 1
fi
if grep -q '15\.0' "$ROOT/project.yml"; then
  echo "error: project.yml still contains an iOS 15 deployment target" >&2
  exit 1
fi
for expected in \
  'iOS: "13.0"' \
  'IPHONEOS_DEPLOYMENT_TARGET: "13.0"' \
  'deploymentTarget: "13.0"'; do
  grep -q "$expected" "$ROOT/project.yml" || {
    echo "error: project.yml is missing required iOS 13 setting: $expected" >&2
    exit 1
  }
done

# leveldb-mcpe public headers use `class DLLX ...`. Both the static library and
# the application target that compiles BTLevelDBBridge.mm must define DLLX.
count="$(grep -c '"DLLX="' "$ROOT/project.yml" || true)"
if [[ "$count" -lt 2 ]]; then
  echo "error: project.yml must define DLLX for both MojangLevelDB and MCBEEditor targets" >&2
  exit 1
fi
grep -q '^#ifndef DLLX$' "$ROOT/Sources/Bridge/BTLevelDBBridge.mm" || {
  echo "error: BTLevelDBBridge.mm is missing the local DLLX fallback" >&2
  exit 1
}
grep -q '^#include "leveldb/env.h"' "$ROOT/Sources/Bridge/BTLevelDBBridge.mm" || {
  echo "error: BTLevelDBBridge.mm must include leveldb/env.h before subclassing leveldb::Logger" >&2
  exit 1
}


# With `set -u`, an unbraced variable immediately followed by multibyte
# punctuation can be tokenized as a different variable name under some runner
# locales. Diagnostic messages must pass values as separate printf arguments.
for unsafe in \
  '$OBJECT_VERSION，' \
  '$OBJECT_VERSION（' \
  '$XCODE_VERSION。'; do
  if grep -qF "$unsafe" "$ROOT/Scripts/bootstrap.sh"; then
    echo "error: bootstrap.sh contains unsafe multibyte variable interpolation: $unsafe" >&2
    exit 1
  fi
done
if grep -qF '$MIN_OS，' "$ROOT/Scripts/build_unsigned_ipa.sh"; then
  echo "error: build_unsigned_ipa.sh contains unsafe multibyte variable interpolation" >&2
  exit 1
fi


for required in \
  "$ROOT/Sources/World/WorldInspector.swift" \
  "$ROOT/Sources/World/TimeStore.swift" \
  "$ROOT/Sources/World/ExperienceStore.swift" \
  "$ROOT/Sources/UI/WorldToolsViewController.swift" \
  "$ROOT/Sources/UI/TimeEditorViewController.swift" \
  "$ROOT/Sources/UI/ExperienceEditorViewController.swift" \
  "$ROOT/Sources/Chunk/MapCoordinate.swift"; do
  [[ -f "$required" ]] || {
    echo "error: enhanced feature source is missing: ${required#$ROOT/}" >&2
    exit 1
  }
done

grep -q 'WorldToolsViewController(session: session)' "$ROOT/Sources/UI/WorldDetailTabBarController.swift" || {
  echo "error: tools tab is not connected to the world workspace" >&2
  exit 1
}
grep -qF 'TimeEditorViewController(session: session)' "$ROOT/Sources/UI/WorldToolsViewController.swift" && grep -qF 'ExperienceEditorViewController(session: session)' "$ROOT/Sources/UI/WorldToolsViewController.swift" && grep -qF '最后打开的游戏版本' "$ROOT/Sources/World/WorldInspector.swift" && grep -qF '最小兼容的游戏版本' "$ROOT/Sources/World/WorldInspector.swift" || {
  echo "error: time, experience or game-version information UI is incomplete" >&2
  exit 1
}
grep -q 'UISearchResultsUpdating' "$ROOT/Sources/UI/NBTTreeViewController.swift" || {
  echo "error: NBT full-tree search is missing" >&2
  exit 1
}


# v0.9.1: the fourth tab is Information and all NBT trees use a shared
# left-hand type badge. Keep this independent from exact release numbers.
for required in \
  "$ROOT/Sources/UI/NBTTagIcon.swift" \
  "$ROOT/Sources/UI/NBTTreeViewController.swift" \
  "$ROOT/Sources/UI/PlayerNBTEditorViewController.swift" \
  "$ROOT/Sources/UI/ReadOnlyNBTViewController.swift" \
  "$ROOT/Sources/UI/WorldObjectNBTEditorViewController.swift"; do
  [[ -f "$required" ]] || {
    echo "error: NBT icon source is missing: ${required#$ROOT/}" >&2
    exit 1
  }
done
grep -qF 'title = "信息"' "$ROOT/Sources/UI/WorldToolsViewController.swift" || {
  echo "error: the tools tab must be titled 信息" >&2
  exit 1
}
grep -qF 'case 1: return "基岩版数据值"' "$ROOT/Sources/UI/WorldToolsViewController.swift" || {
  echo "error: the Bedrock data-values section is missing" >&2
  exit 1
}
for label in '实体ID' '生物群系ID' '状态效果ID' '魔咒ID'; do
  grep -qF "(\"$label\"," "$ROOT/Sources/UI/WorldToolsViewController.swift" || {
    echo "error: data-values row is missing: $label" >&2
    exit 1
  }
done
grep -qF 'override func numberOfSections(in tableView: UITableView) -> Int { 3 }' "$ROOT/Sources/UI/WorldListViewController.swift" && \
grep -qF 'return "NBT工具"' "$ROOT/Sources/UI/WorldListViewController.swift" && \
grep -qF 'cell.textLabel?.text = "NBT/mcstructure/JSON读取修改和转换"' "$ROOT/Sources/UI/WorldListViewController.swift" && \
grep -qF 'cell.imageView?.image = NBTTagIcon.toolImage()' "$ROOT/Sources/UI/WorldListViewController.swift" && \
grep -qF 'return "基岩版数据值"' "$ROOT/Sources/UI/WorldListViewController.swift" && \
grep -qF 'showBedrockDataValues(row: indexPath.row)' "$ROOT/Sources/UI/WorldListViewController.swift" || {
  echo "error: NBT file tools or Bedrock data-value entries are missing below the world list" >&2
  exit 1
}
for required in \
  "$ROOT/Sources/World/StandaloneNBTFile.swift" \
  "$ROOT/Sources/UI/StandaloneNBTFileViewController.swift" \
  "$ROOT/Sources/UI/StandaloneNBTEditorViewController.swift"; do
  [[ -f "$required" ]] || {
    echo "error: standalone NBT file tool source is missing: ${required#$ROOT/}" >&2
    exit 1
  }
done
grep -qF 'cell.textLabel?.text = file.documents.count == 1 ? name : "#\(index)  \(name)"' "$ROOT/Sources/UI/StandaloneNBTFileViewController.swift" || {
  echo "error: consecutive NBT root numbering must start at 0" >&2
  exit 1
}
grep -qF '@objc private func addRootDocument()' "$ROOT/Sources/UI/StandaloneNBTFileViewController.swift" || {
  echo "error: standalone NBT root creation is missing" >&2
  exit 1
}
grep -qF 'private func renameRoot(documentIndex: Int)' "$ROOT/Sources/UI/StandaloneNBTFileViewController.swift" || {
  echo "error: standalone NBT root renaming is missing" >&2
  exit 1
}
grep -qF 'title: "返回"' "$ROOT/Sources/UI/StandaloneNBTEditorViewController.swift" || {
  echo "error: standalone NBT editor return button is missing" >&2
  exit 1
}
grep -qF 'title: "保存并返回"' "$ROOT/Sources/UI/StandaloneNBTEditorViewController.swift" || {
  echo "error: standalone NBT editor save-and-return flow is missing" >&2
  exit 1
}
for label in '实体ID' '生物群系ID' '状态效果ID' '魔咒ID'; do
  grep -qF "(\"$label\"," "$ROOT/Sources/UI/WorldListViewController.swift" || {
    echo "error: data-values row is missing on world-selection screen: $label" >&2
    exit 1
  }
done
grep -qF 'entry(178, "minecraft:soulsand_valley"' "$ROOT/Sources/Chunk/BedrockBiomeCatalog.swift" || {
  echo "error: corrected modern Bedrock biome IDs are missing" >&2
  exit 1
}
grep -qF 'entry(192, "minecraft:cherry_grove"' "$ROOT/Sources/Chunk/BedrockBiomeCatalog.swift" || {
  echo "error: cherry grove biome ID is missing" >&2
  exit 1
}
for entry in \
  'entry(193, "minecraft:pale_garden"' \
  'entry(194, "minecraft:sulfur_caves"' \
  'entry(195, "minecraft:dappled_forest"'; do
  grep -qF "$entry" "$ROOT/Sources/Chunk/BedrockBiomeCatalog.swift" || {
    echo "error: biome catalogue is missing spreadsheet entry: $entry" >&2
    exit 1
  }
done
if grep -qF 'entry(50, "minecraft:soul_sand_valley"' "$ROOT/Sources/Chunk/BedrockBiomeCatalog.swift"; then
  echo "error: obsolete incorrect biome IDs 50-65 are still present" >&2
  exit 1
fi
grep -qF 'UIImage(systemName: "info.circle")' "$ROOT/Sources/UI/WorldToolsViewController.swift" || {
  echo "error: the information tab icon is missing" >&2
  exit 1
}
for source in \
  "$ROOT/Sources/UI/NBTTreeViewController.swift" \
  "$ROOT/Sources/UI/PlayerNBTEditorViewController.swift" \
  "$ROOT/Sources/UI/ReadOnlyNBTViewController.swift" \
  "$ROOT/Sources/UI/WorldObjectNBTEditorViewController.swift"; do
  grep -qF 'NBTTagIcon' "$source" || {
    echo "error: NBT type badges are not connected: ${source#$ROOT/}" >&2
    exit 1
  }
done

echo "iOS 13-only project configuration passed"
echo "LevelDB bridge header configuration passed"
echo "Enhanced feature configuration passed"
"$TMP/core-tests"

# iOS 13 document providers may expose .mcworld as a dynamic UTI. File and
# directory selection must remain separate, with broad file selection followed
# by strict in-app validation. File pickers use import mode and single selection
# so tapping a file immediately returns instead of waiting for an extra confirm.
grep -q 'documentTypes: \[kUTTypeItem as String\]' "$ROOT/Sources/UI/WorldListViewController.swift" || {
  echo "error: .mcworld picker must use broad public.item selection on iOS 13" >&2
  exit 1
}
grep -q 'documentTypes: \[kUTTypeFolder as String\]' "$ROOT/Sources/UI/WorldListViewController.swift" || {
  echo "error: world directory picker is missing" >&2
  exit 1
}
if grep -q 'kUTTypeZipArchive as String, kUTTypeFolder as String' "$ROOT/Sources/UI/WorldListViewController.swift"; then
  echo "error: file and folder UTIs must not be mixed in one iOS 13 picker" >&2
  exit 1
fi
grep -q 'in: .import' "$ROOT/Sources/UI/StructureNBTListViewController.swift" || {
  echo "error: structure file picker must use import mode on iOS 13" >&2
  exit 1
}
grep -q 'displayOptions.axis = .horizontal' "$ROOT/Sources/UI/WorldMapViewController.swift" || {
  echo "error: map top-row switches must be laid out horizontally" >&2
  exit 1
}
for expected in \
  'in: .import' \
  'allowsMultipleSelection = false' \
  'func importExternalURLs(_ urls: [URL])' \
  'sharedImportCandidates()' \
  'func duplicate(_ world: ImportedWorld)' \
  'func rename(_ world: ImportedWorld, to requestedName: String)'; do
  grep -qF "$expected" "$ROOT/Sources/UI/WorldListViewController.swift" \
    "$ROOT/Sources/World/WorldImportService.swift" \
    "$ROOT/Sources/World/WorldStore.swift" || {
      echo "error: enhanced import/world management feature missing: $expected" >&2
      exit 1
    }
done
for expected in \
  'CFBundleTypeRole: Editor' \
  'com.microsoft.minecraft.mcworld'; do
  grep -qF "$expected" "$ROOT/project.yml" || {
    echo "error: project.yml is missing import compatibility setting: $expected" >&2
    exit 1
  }
done

echo "iOS 13 document import compatibility passed"
echo "World list management enhancements passed"

# Map read regression: a missing LevelDB key is a normal optional result. Do
# not expose it through an Objective-C nullable object + NSError** method,
# because Swift converts nil-without-error into Foundation._GenericObjCError.
for expected in \
  '@interface BTLevelDBReadResult' \
  'readResultForKey:(NSData *)key' \
  'if (status.IsNotFound())' \
  'initWithFound:NO value:nil error:nil'; do
  grep -qF "$expected" \
    "$ROOT/Sources/Bridge/BTLevelDBBridge.h" \
    "$ROOT/Sources/Bridge/BTLevelDBBridge.mm" || {
      echo "error: LevelDB optional-read regression protection is missing: $expected" >&2
      exit 1
    }
done
if grep -q 'dataForKey:.*error:' "$ROOT/Sources/Bridge/BTLevelDBBridge.h"; then
  echo "error: nullable dataForKey:error: must not be exposed to Swift" >&2
  exit 1
fi
grep -qF 'let result = bridge.readResult(forKey: key)' "$ROOT/Sources/LevelDB/MojangLevelDB.swift" || {
  echo "error: MojangLevelDB.get must use the explicit read result" >&2
  exit 1
}
for expected in \
  'jumpToSpawn' \
  'shareRenderedMap' \
  'showRenderDiagnostics' \
  'scheduleAutoRender' \
  'autoRenderAtViewportCenter' \
  'prefetchBorder' \
  'renderGeneration' \
  'dimensionControl.addTarget'; do
  grep -qF "$expected" "$ROOT/Sources/UI/WorldMapViewController.swift" || {
    echo "error: map enhancement is missing: $expected" >&2
    exit 1
  }
done
grep -qF 'for storage in subChunk.storages' "$ROOT/Sources/Chunk/ChunkSurfaceRenderer.swift" || {
  echo "error: multi-storage surface fallback is missing" >&2
  exit 1
}
for expected in \
  'final class ChunkSurfaceCache' \
  'case height' \
  'case xray' \
  'isHighlightedOre'; do
  grep -qF "$expected" "$ROOT/Sources/Chunk/ChunkSurfaceRenderer.swift" || {
    echo "error: dynamic map renderer feature is missing: $expected" >&2
    exit 1
  }
done
for removed in \
  "$ROOT/Sources/Chunk/MapMarker.swift" \
  "$ROOT/Sources/UI/MapMarkerListViewController.swift"; do
  if [[ -e "$removed" ]]; then
    echo "warning: obsolete custom marker source remains after a ZIP overlay: ${removed#$ROOT/}" >&2
  fi
done
! grep -R -qE 'markerStore|showMarkerList|mapLongPressed|创建地图标记|bookmark\.fill' \
  "$ROOT/Sources" || {
    echo "error: custom map marker functionality was not fully removed" >&2
    exit 1
  }

echo "LevelDB optional read regression passed"
echo "Infinite map panning, cache and layer enhancements passed"

# v0.6.0: pinch zoom and entity/block-entity inspection.
for required in \
  "$ROOT/Sources/Support/BedrockDataValueCatalog.swift" \
  "$ROOT/Sources/Entity/BedrockWorldObject.swift" \
  "$ROOT/Sources/Entity/BedrockWorldObjectScanner.swift" \
  "$ROOT/Sources/UI/EntityBrowserViewController.swift" \
  "$ROOT/Sources/UI/ReadOnlyNBTViewController.swift"; do
  [[ -f "$required" ]] || {
    echo "error: entity feature source is missing: ${required#$ROOT/}" >&2
    exit 1
  }
done
for expected in \
  'scrollView.pinchGestureRecognizer?.isEnabled = true' \
  'scrollViewWillBeginZooming' \
  'mapDoubleTapped' \
  'mapTwoFingerTapped' \
  'showOverlayOptions' \
  'BedrockWorldObjectScanner' \
  'locate(worldObject:'; do
  grep -qF "$expected" "$ROOT/Sources/UI/WorldMapViewController.swift" || {
    echo "error: pinch/entity map feature is missing: $expected" >&2
    exit 1
  }
done
grep -qF 'EntityBrowserViewController(session: session)' "$ROOT/Sources/UI/WorldDetailTabBarController.swift" || {
  echo "error: entity browser tab is not connected" >&2
  exit 1
}
for expected in \
  'Data("digp".utf8)' \
  'Data("actorprefix".utf8)' \
  'recordType: .entity' \
  'recordType: .blockEntity' \
  'ConsecutiveNBTCodec.decode'; do
  grep -qF "$expected" "$ROOT/Sources/Entity/BedrockWorldObjectScanner.swift" || {
    echo "error: entity storage compatibility is missing: $expected" >&2
    exit 1
  }
done

cat > "$TMP/MojangLevelDBStub.swift" <<'SWIFT'
import Foundation
final class MojangLevelDB {
    let values: [Data: Data]
    init(values: [Data: Data]) { self.values = values }
    func get(_ key: Data) throws -> Data? { values[key] }
    func entries(prefix: Data? = nil, includeValues: Bool = false, limit: Int = 0) throws -> [(key: Data, value: Data?)] {
        let matches = values.keys.filter { key in
            guard let prefix = prefix else { return true }
            return key.starts(with: prefix)
        }.sorted { $0.lexicographicallyPrecedes($1) }
        let selected = limit > 0 ? Array(matches.prefix(limit)) : matches
        return selected.map { ($0, includeValues ? values[$0] : nil) }
    }
}
SWIFT
cat > "$TMP/entity_test.swift" <<'SWIFT'
import Foundation

@main
struct EntityTest {
    static func main() throws {
        let actorID: Int64 = 123456789
        let actorDocument = NBTDocument(rootName: "", root: .compound([
            NBTNamedTag(name: "id", value: .short(44)),
            NBTNamedTag(name: "UniqueID", value: .long(actorID)),
            NBTNamedTag(name: "Pos", value: .list(.float, [.float(1.5), .float(64), .float(-2.25)]))
        ]))
        let actorData = try BedrockNBTCodec.encode(actorDocument)
        let actorBits = UInt64(bitPattern: actorID)
        var actorKey = Data("actorprefix".utf8)
        var digest = Data()
        for shift in stride(from: 0, through: 56, by: 8) {
            let byte = UInt8(truncatingIfNeeded: actorBits >> shift)
            actorKey.append(byte)
            digest.append(byte)
        }

        let definitionActorID: Int64 = 987654321
        let definitionActorDocument = NBTDocument(rootName: "", root: .compound([
            NBTNamedTag(name: "id", value: .int(199534)),
            NBTNamedTag(name: "definitions", value: .list(.string, [
                .string("+minecraft:drowned"),
                .string("+minecraft:monster")
            ])),
            NBTNamedTag(name: "UniqueID", value: .long(definitionActorID)),
            NBTNamedTag(name: "Pos", value: .list(.float, [.float(3.5), .float(62), .float(-4.25)]))
        ]))
        let definitionActorData = try BedrockNBTCodec.encode(definitionActorDocument)
        let definitionActorBits = UInt64(bitPattern: definitionActorID)
        var definitionActorKey = Data("actorprefix".utf8)
        for shift in stride(from: 0, through: 56, by: 8) {
            let byte = UInt8(truncatingIfNeeded: definitionActorBits >> shift)
            definitionActorKey.append(byte)
            digest.append(byte)
        }
        var digestKey = Data("digp".utf8)
        digestKey.appendLE(Int32(0))
        digestKey.appendLE(Int32(-1))
        digestKey.appendLE(Int32(0))

        let blockDocument = NBTDocument(rootName: "", root: .compound([
            NBTNamedTag(name: "id", value: .string("Chest")),
            NBTNamedTag(name: "x", value: .int(2)),
            NBTNamedTag(name: "y", value: .int(63)),
            NBTNamedTag(name: "z", value: .int(-3)),
            NBTNamedTag(name: "CustomName", value: .string("仓库"))
        ]))
        let blockData = try BedrockNBTCodec.encode(blockDocument)
        let blockKey = BedrockDBKey(
            position: ChunkPosition(x: 0, z: -1, dimension: 0),
            recordType: .blockEntity,
            subChunkIndex: nil
        ).encoded()
        let database = MojangLevelDB(values: [
            actorKey: actorData,
            definitionActorKey: definitionActorData,
            digestKey: digest,
            blockKey: blockData
        ])
        let result = try BedrockWorldObjectScanner(database: database).scanRegion(
            centerX: 0,
            centerZ: -1,
            dimension: 0,
            radius: 0,
            includeEntities: true,
            includeBlockEntities: true
        )
        precondition(result.objects.count == 3)
        precondition(result.objects.first(where: { $0.uniqueID == actorID })?.identifier == "minecraft:zombie_villager")
        precondition(result.objects.first(where: { $0.uniqueID == actorID })?.position?.blockZ == -3)
        precondition(result.objects.first(where: { $0.uniqueID == definitionActorID })?.identifier == "minecraft:drowned")
        precondition(result.objects.first(where: { $0.kind == .blockEntity })?.displayName == "仓库")

        let worldWide = try BedrockWorldObjectScanner(database: database).scanAll(
            dimensions: [0],
            includeEntities: true,
            includeBlockEntities: true
        )
        precondition(worldWide.objects.count == 3)
        precondition(worldWide.actorDigestCount == 1)
        precondition(worldWide.actorRecordCount == 2)
        precondition(worldWide.blockEntityRecordCount == 1)
        let otherDimension = try BedrockWorldObjectScanner(database: database).scanAll(
            dimensions: [1],
            includeEntities: true,
            includeBlockEntities: true
        )
        precondition(otherDimension.objects.isEmpty)
        let blockOnly = try BedrockWorldObjectScanner(database: database).scanAll(
            dimensions: nil,
            includeEntities: false,
            includeBlockEntities: true
        )
        precondition(blockOnly.objects.count == 1)
        precondition(blockOnly.objects[0].kind == .blockEntity)
        print("Entity and block-entity scanner tests passed")
    }
}
SWIFT
swiftc \
  "$ROOT/Sources/Support/Errors.swift" \
  "$ROOT/Sources/Support/Hex.swift" \
  "$ROOT/Sources/Chunk/MapCoordinate.swift" \
  "$ROOT/Sources/Chunk/BedrockMapRegion.swift" \
  "$ROOT/Sources/Chunk/BedrockDBKey.swift" \
  "$ROOT/Sources/NBT/BinaryCursor.swift" \
  "$ROOT/Sources/NBT/NBTTypes.swift" \
  "$ROOT/Sources/NBT/BedrockNBTCodec.swift" \
  "$ROOT/Sources/NBT/ConsecutiveNBTCodec.swift" \
  "$TMP/MojangLevelDBStub.swift" \
  "$ROOT/Sources/Support/BedrockDataValueCatalog.swift" \
  "$ROOT/Sources/Entity/BedrockWorldObject.swift" \
  "$ROOT/Sources/Entity/BedrockWorldObjectScanner.swift" \
  -parse-as-library "$TMP/entity_test.swift" -o "$TMP/entity-tests"
"$TMP/entity-tests"

echo "Pinch zoom and entity/block-entity enhancements passed"

# v0.6.1: minimum-zoom panning and pixel-sharp overlays.
for expected in \
  'private final class MapObjectOverlayView' \
  'private let basePointsPerBlock: CGFloat = 32' \
  'private let panMarginFactor: CGFloat = 0.75' \
  'scrollView.contentInset = insets' \
  'let minOffsetX = -scrollView.contentInset.left' \
  'pixelAlignedZoomScale' \
  'cg.interpolationQuality = .none' \
  'imageView.layer.magnificationFilter = .nearest' \
  'objectOverlayView.update('; do
  grep -qF "$expected" "$ROOT/Sources/UI/WorldMapViewController.swift" || {
    echo "error: v0.6.1 map clarity/panning fix is missing: $expected" >&2
    exit 1
  }
done
if grep -qF 'imageView.widthAnchor.constraint(equalToConstant: 3072)' "$ROOT/Sources/UI/WorldMapViewController.swift"; then
  echo "error: fixed 3072-point map canvas reintroduces fractional block sizes" >&2
  exit 1
fi

echo "Minimum-zoom panning and pixel-sharp overlay fixes passed"


# v0.7.0: vine color, editable player NBT, rectangle selection and blinking object focus.
for required in \
  "$ROOT/Sources/World/PlayerNBTStore.swift" \
  "$ROOT/Sources/UI/PlayerNBTListViewController.swift" \
  "$ROOT/Sources/UI/PlayerNBTEditorViewController.swift" \
  "$ROOT/Sources/UI/MapSelectionOverlayView.swift" \
  "$ROOT/Sources/UI/MapSelectionResultsViewController.swift"; do
  [[ -f "$required" ]] || {
    echo "error: v0.7.0 source is missing: ${required#$ROOT/}" >&2
    exit 1
  }
done
for expected in \
  'name == "minecraft:vine"' \
  'UIColor(red: 0.18, green: 0.64, blue: 0.20'; do
  grep -qF "$expected" "$ROOT/Sources/Chunk/ChunkSurfaceRenderer.swift" || {
    echo "error: minecraft:vine green map color is missing: $expected" >&2
    exit 1
  }
done
for expected in \
  'Data("~local_player".utf8)' \
  'Data("LocalPlayer".utf8)' \
  'Data("player_".utf8)' \
  'session.database().put(encoded, for: record.key, sync: true)'; do
  grep -qF "$expected" "$ROOT/Sources/World/PlayerNBTStore.swift" || {
    echo "error: editable player NBT support is missing: $expected" >&2
    exit 1
  }
done
grep -qF 'PlayerNBTListViewController(session: session)' "$ROOT/Sources/UI/NBTMenuViewController.swift" || {
  echo "error: player NBT editor is not connected to the NBT menu" >&2
  exit 1
}
for expected in \
  'toggleSelectionMode' \
  'handleSelectionPan' \
  'MapSelectionResultsViewController' \
  'selected-object-blink' \
  'selectWorldObject(hit.object)' \
  'clearSelectedWorldObject()'; do
  grep -qF "$expected" "$ROOT/Sources/UI/WorldMapViewController.swift" || {
    echo "error: map selection/blinking feature is missing: $expected" >&2
    exit 1
  }
done

cat > "$TMP/PlayerNBTStoreStubs.swift" <<'SWIFT'
import Foundation
struct ImportedWorld { let id: UUID }
final class BTCompressionBridge {
    static func inflateWrapped(_ data: Data, expectedSize: UInt) throws -> Data {
        throw NSError(domain: "StructureNBTTest", code: 1)
    }
}
final class MojangLevelDB {
    var values: [Data: Data]
    init(values: [Data: Data]) { self.values = values }
    func get(_ key: Data) throws -> Data? { values[key] }
    func put(_ value: Data, for key: Data, sync: Bool = true) throws { values[key] = value }
    func delete(_ key: Data, sync: Bool = true) throws { values.removeValue(forKey: key) }
    func applyBatch(puts: [(key: Data, value: Data)], deletes: [Data], sync: Bool = true) throws {
        for item in puts { values[item.key] = item.value }
        for key in deletes { values.removeValue(forKey: key) }
    }
    func entries(prefix: Data? = nil, includeValues: Bool = false, limit: Int = 0) throws -> [(key: Data, value: Data?)] {
        values.keys.filter { key in
            guard let prefix = prefix else { return true }
            return key.starts(with: prefix)
        }.sorted { $0.lexicographicallyPrecedes($1) }.map { ($0, includeValues ? values[$0] : nil) }
    }
}
final class WorldSession {
    let world = ImportedWorld(id: UUID())
    let db: MojangLevelDB
    init(db: MojangLevelDB) { self.db = db }
    func database() throws -> MojangLevelDB { db }
}
final class WorldStore {
    static let shared = WorldStore()
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("bt-player-test-\(UUID().uuidString)", isDirectory: true)
    func metadataURL(for world: ImportedWorld) -> URL { root.appendingPathComponent(world.id.uuidString, isDirectory: true) }
}
SWIFT
cat > "$TMP/player_nbt_test.swift" <<'SWIFT'
import Foundation
@main
struct PlayerNBTTest {
    static func main() throws {
        let localKey = Data("~local_player".utf8)
        let remoteKey = Data("player_server_1234".utf8)
        let localDoc = NBTDocument(rootName: "", root: .compound([
            NBTNamedTag(name: "NameTag", value: .string("Bear")),
            NBTNamedTag(name: "PlayerGameMode", value: .int(0))
        ]))
        let remoteDoc = NBTDocument(rootName: "", root: .compound([
            NBTNamedTag(name: "PlayerName", value: .string("Remote"))
        ]))
        let db = MojangLevelDB(values: [
            localKey: try BedrockNBTCodec.encode(localDoc),
            remoteKey: try BedrockNBTCodec.encode(remoteDoc)
        ])
        let session = WorldSession(db: db)
        let store = PlayerNBTStore(session: session)
        let records = try store.records()
        precondition(records.count == 2)
        guard let local = records.first(where: { $0.key == localKey }) else { fatalError("missing local player") }
        var edited = local.document
        edited.root = try NBTTreeMutation.replacingValue(
            at: [.compound("PlayerGameMode")],
            in: edited.root,
            with: .int(1)
        )
        try store.save(record: local, document: edited)
        let saved = try BedrockNBTCodec.decode(db.values[localKey]!)
        guard case .int(let savedMode)? = NBTTreeMutation.value(at: [.compound("PlayerGameMode")], in: saved.root) else {
            fatalError("saved mode missing")
        }
        precondition(savedMode == 1)
        print("Player NBT read/write tests passed")
    }
}
SWIFT
swiftc \
  "$ROOT/Sources/Support/Errors.swift" \
  "$ROOT/Sources/Support/Hex.swift" \
  "$ROOT/Sources/Support/AtomicFile.swift" \
  "$ROOT/Sources/NBT/BinaryCursor.swift" \
  "$ROOT/Sources/NBT/NBTTypes.swift" \
  "$ROOT/Sources/NBT/BedrockNBTCodec.swift" \
  "$ROOT/Sources/UI/NBTNode.swift" \
  "$TMP/PlayerNBTStoreStubs.swift" \
  "$ROOT/Sources/World/PlayerNBTStore.swift" \
  -parse-as-library "$TMP/player_nbt_test.swift" -o "$TMP/player-nbt-tests"
"$TMP/player-nbt-tests"

echo "Vine color, player NBT editing, map selection and blinking focus passed"


# Six-tab navigation with dedicated chunk and command tabs, peer NBT menu and saved structure templates.
for required in \
  "$ROOT/Sources/UI/NBTMenuViewController.swift" \
  "$ROOT/Sources/World/StructureNBTStore.swift" \
  "$ROOT/Sources/UI/StructureNBTListViewController.swift"; do
  [[ -f "$required" ]] || {
    echo "error: v0.8.0 source is missing: ${required#$ROOT/}" >&2
    exit 1
  }
done
for expected in \
  'viewControllers = [map, entities, chunks, nbt, commands, tools]' \
  'NBTMenuViewController(session: session)'; do
  grep -qF "$expected" "$ROOT/Sources/UI/WorldDetailTabBarController.swift" || {
    echo "error: v0.8.0 tab layout is missing: $expected" >&2
    exit 1
  }
done
if grep -qF 'DatabaseBrowserViewController(session: session)' "$ROOT/Sources/UI/WorldDetailTabBarController.swift"; then
  echo "error: database browser must not remain a top-level tab" >&2
  exit 1
fi
grep -qF 'DatabaseBrowserViewController(session: session)' "$ROOT/Sources/UI/WorldToolsViewController.swift" || {
  echo "error: database browser is not connected to the tools menu" >&2
  exit 1
}
for expected in \
  'Item(title: "世界 NBT"' \
  'Item(title: "玩家 NBT"' \
  'Item(title: "结构 NBT"' \
  'StructureNBTListViewController(session: session)'; do
  grep -qF "$expected" "$ROOT/Sources/UI/NBTMenuViewController.swift" || {
    echo "error: peer NBT menu entry is missing: $expected" >&2
    exit 1
  }
done
for expected in \
  'static let keyPrefix = "structuretemplate"' \
  'prefix: Data(Self.keyPrefix.utf8)' \
  'NBTEncoding.bigEndian' \
  '.littleEndianVarInt' \
  'BTCompressionBridge.inflateWrapped' \
  'BedrockNBTCodec.encode(conversion.document, encoding: .littleEndian)' \
  'func rename(record: StructureNBTRecord' \
  '.mcstructure'; do
  grep -qF "$expected" "$ROOT/Sources/World/StructureNBTStore.swift" \
    "$ROOT/Sources/UI/StructureNBTListViewController.swift" || {
    echo "error: structure NBT compatibility is missing: $expected" >&2
    exit 1
  }
done

cat > "$TMP/StructureNBTStoreStubs.swift" <<'SWIFT'
import Foundation
struct ImportedWorld { let id: UUID }
final class BTCompressionBridge {
    static func inflateWrapped(_ data: Data, expectedSize: UInt) throws -> Data {
        throw NSError(domain: "StructureNBTTest", code: 1)
    }
}
final class MojangLevelDB {
    var values: [Data: Data]
    init(values: [Data: Data]) { self.values = values }
    func get(_ key: Data) throws -> Data? { values[key] }
    func put(_ value: Data, for key: Data, sync: Bool = true) throws { values[key] = value }
    func delete(_ key: Data, sync: Bool = true) throws { values.removeValue(forKey: key) }
    func applyBatch(puts: [(key: Data, value: Data)], deletes: [Data], sync: Bool = true) throws {
        for item in puts { values[item.key] = item.value }
        for key in deletes { values.removeValue(forKey: key) }
    }
    func entries(prefix: Data? = nil, includeValues: Bool = false, limit: Int = 0) throws -> [(key: Data, value: Data?)] {
        values.keys.filter { key in
            guard let prefix = prefix else { return true }
            return key.starts(with: prefix)
        }.sorted { $0.lexicographicallyPrecedes($1) }.map { ($0, includeValues ? values[$0] : nil) }
    }
}
final class WorldSession {
    let world = ImportedWorld(id: UUID())
    let db: MojangLevelDB
    init(db: MojangLevelDB) { self.db = db }
    func database() throws -> MojangLevelDB { db }
}
final class WorldStore {
    static let shared = WorldStore()
    func metadataURL(for world: ImportedWorld) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("structure-test-\(world.id.uuidString)", isDirectory: true)
    }
}
enum AtomicFile {
    static func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
SWIFT
cat > "$TMP/structure_nbt_test.swift" <<'SWIFT'
import Foundation
@main
struct StructureNBTTest {
    static func main() throws {
        let document = NBTDocument(rootName: "", root: .compound([
            NBTNamedTag(name: "format_version", value: .int(1)),
            NBTNamedTag(name: "size", value: .list(.int, [.int(12), .int(6), .int(9)])),
            NBTNamedTag(name: "structure_world_origin", value: .list(.int, [.int(-20), .int(64), .int(30)])),
            NBTNamedTag(name: "structure", value: .compound([
                NBTNamedTag(name: "block_indices", value: .list(.list, [
                    .list(.int, Array(repeating: .int(-1), count: 648)),
                    .list(.int, Array(repeating: .int(-1), count: 648))
                ])),
                NBTNamedTag(name: "entities", value: .list(.end, [])),
                NBTNamedTag(name: "palette", value: .compound([
                    NBTNamedTag(name: "default", value: .compound([
                        NBTNamedTag(name: "block_palette", value: .list(.compound, [])),
                        NBTNamedTag(name: "block_position_data", value: .compound([]))
                    ]))
                ]))
            ]))
        ]))
        let key = Data("structuretemplate_castle".utf8)
        let raw = try BedrockNBTCodec.encode(document, encoding: .littleEndian)
        let store = StructureNBTStore(session: WorldSession(db: MojangLevelDB(values: [key: raw])))
        let records = try store.records()
        precondition(records.count == 1)
        precondition(records[0].displayName == "castle")
        precondition(records[0].sizeDescription == "12×6×9")
        precondition(records[0].originDescription == "(-20, 64, 30)")
        precondition(records[0].formatVersion == 1)
        precondition(records[0].document != nil)
        var edited = records[0].document!
        edited.root = try NBTTreeMutation.replacingValue(
            at: [.compound("format_version")],
            in: edited.root,
            with: .int(2)
        )
        try store.save(record: records[0], document: edited)
        let saved = try BedrockNBTCodec.decode(store.records()[0].rawData, encoding: .littleEndian)
        precondition(saved.root.intValue(named: "format_version") == 2)
        let importedRaw = try BedrockNBTCodec.encode(document, encoding: .bigEndian)
        try store.importStructure(data: importedRaw, named: "demo:imported", overwrite: false)
        let existsAfterImport = try store.containsStructure(named: "demo:imported")
        precondition(existsAfterImport)
        let imported = try store.records().first { $0.displayName == "demo:imported" }
        precondition(imported != nil)
        precondition(imported?.encoding == .littleEndian)
        try store.rename(record: imported!, to: "demo:renamed", overwrite: false)
        let oldNameStillExists = try store.containsStructure(named: "demo:imported")
        precondition(!oldNameStillExists)
        let renamed = try store.records().first { $0.displayName == "demo:renamed" }
        precondition(renamed != nil)
        try store.delete(record: renamed!)
        let existsAfterDelete = try store.containsStructure(named: "demo:renamed")
        precondition(!existsAfterDelete)
        print("Structure NBT discovery, endian conversion, rename and delete tests passed")
    }
}
SWIFT
swiftc \
  "$ROOT/Sources/Support/Errors.swift" \
  "$ROOT/Sources/Support/Hex.swift" \
  "$ROOT/Sources/NBT/BinaryCursor.swift" \
  "$ROOT/Sources/NBT/NBTTypes.swift" \
  "$ROOT/Sources/NBT/BedrockNBTCodec.swift" \
  "$ROOT/Sources/UI/NBTNode.swift" \
  "$TMP/StructureNBTStoreStubs.swift" \
  "$ROOT/Sources/World/JavaStructureConverter.swift" \
  "$ROOT/Sources/World/StructureNBTStore.swift" \
  -parse-as-library "$TMP/structure_nbt_test.swift" -o "$TMP/structure-nbt-tests"
"$TMP/structure-nbt-tests"

for expected in \
  'StructureNBTEditorViewController(' \
  'func save(record: StructureNBTRecord, document: NBTDocument)' \
  'struct BedrockBlockRecord' \
  'BlockColumnPickerViewController' \
  'MapBlockDetailPanelView' \
  'showBlockColumn(x:' \
  'jumpToBlock(x:'; do
  grep -R -qF "$expected" "$ROOT/Sources" || {
    echo "error: v0.9.2 restored block/structure feature is missing: $expected" >&2
    exit 1
  }
done

echo "Editable structure NBT and restored block inspector passed"

echo "Six-tab navigation, command terminal, peer NBT menu and structure NBT browser passed"

# v0.9.0: editable entity and block-entity NBT with storage migration.
for required in \
  "$ROOT/Sources/NBT/ConsecutiveNBTCodec.swift" \
  "$ROOT/Sources/Entity/BedrockEntityCommonNBT.swift" \
  "$ROOT/Sources/Entity/BedrockWorldObjectNBTStore.swift" \
  "$ROOT/Sources/UI/WorldObjectNBTEditorViewController.swift"; do
  [[ -f "$required" ]] || {
    echo "error: v0.9.0 source is missing: ${required#$ROOT/}" >&2
    exit 1
  }
done
for expected in \
  'case modernActor(actorKey: Data, digestKey: Data' \
  'case chunkRecord(key: Data, recordIndex: Int' \
  'sourceIDs.removeAll { $0 == originalID }' \
  'database.applyBatch(puts: puts, deletes: deletes' \
  'UniqueID 可修改但不能删除或重命名'; do
  grep -qF "$expected" \
    "$ROOT/Sources/Entity/BedrockWorldObject.swift" \
    "$ROOT/Sources/Entity/BedrockEntityCommonNBT.swift" \
  "$ROOT/Sources/Entity/BedrockWorldObjectNBTStore.swift" \
    "$ROOT/Sources/UI/WorldObjectNBTEditorViewController.swift" || {
      echo "error: entity/block-entity editing safety feature missing: $expected" >&2
      exit 1
    }
done
for expected in \
  'func create(' \
  'func delete(object:' \
  'uniqueIDChanged: Bool' \
  'makeActorKey(id: editedActorID)' \
  'WorldObjectCreationViewController(' \
  '复制为新\(object.kind.displayName)' \
  'confirmDelete(_ object:'; do
  grep -R -qF "$expected" \
    "$ROOT/Sources/Entity/BedrockEntityCommonNBT.swift" \
  "$ROOT/Sources/Entity/BedrockWorldObjectNBTStore.swift" \
    "$ROOT/Sources/UI/EntityBrowserViewController.swift" \
    "$ROOT/Sources/UI/WorldObjectCreationViewController.swift" || {
      echo "error: entity/block-entity create/delete or UniqueID migration is missing: $expected" >&2
      exit 1
    }
done

for source in \
  "$ROOT/Sources/UI/EntityBrowserViewController.swift" \
  "$ROOT/Sources/UI/WorldMapViewController.swift" \
  "$ROOT/Sources/UI/MapSelectionResultsViewController.swift"; do
  grep -qF 'WorldObjectNBTEditorViewController(' "$source" || {
    echo "error: object NBT editor is not connected: ${source#$ROOT/}" >&2
    exit 1
  }
done

cat > "$TMP/WorldObjectNBTStoreStubs.swift" <<'SWIFT'
import Foundation
struct ImportedWorld { let id: UUID }
final class BTCompressionBridge {
    static func inflateWrapped(_ data: Data, expectedSize: UInt) throws -> Data {
        throw NSError(domain: "StructureNBTTest", code: 1)
    }
}
final class MojangLevelDB {
    var values: [Data: Data]
    init(values: [Data: Data]) { self.values = values }
    func get(_ key: Data) throws -> Data? { values[key] }
    func put(_ value: Data, for key: Data, sync: Bool = true) throws { values[key] = value }
    func delete(_ key: Data, sync: Bool = true) throws { values.removeValue(forKey: key) }
    func applyBatch(puts: [(key: Data, value: Data)], deletes: [Data], sync: Bool = true) throws {
        for item in puts { values[item.key] = item.value }
        for key in deletes { values.removeValue(forKey: key) }
    }
    func entries(prefix: Data? = nil, includeValues: Bool = false, limit: Int = 0) throws -> [(key: Data, value: Data?)] {
        let keys = values.keys.filter { key in
            guard let prefix = prefix else { return true }
            return key.starts(with: prefix)
        }.sorted { $0.lexicographicallyPrecedes($1) }
        let selected = limit > 0 ? Array(keys.prefix(limit)) : keys
        return selected.map { ($0, includeValues ? values[$0] : nil) }
    }
}
final class WorldSession {
    let world = ImportedWorld(id: UUID())
    let db: MojangLevelDB
    init(db: MojangLevelDB) { self.db = db }
    func database() throws -> MojangLevelDB { db }
}
final class WorldStore {
    static let shared = WorldStore()
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("bt-object-test-\(UUID().uuidString)", isDirectory: true)
    func metadataURL(for world: ImportedWorld) -> URL { root.appendingPathComponent(world.id.uuidString, isDirectory: true) }
}
SWIFT
cat > "$TMP/world_object_nbt_test.swift" <<'SWIFT'
import Foundation
@main
struct WorldObjectNBTTest {
    static func actorKey(_ id: Int64) -> Data {
        var data = Data("actorprefix".utf8)
        let bits = UInt64(bitPattern: id)
        for shift in stride(from: 0, through: 56, by: 8) {
            data.append(UInt8(truncatingIfNeeded: bits >> UInt64(shift)))
        }
        return data
    }
    static func digestKey(_ x: Int32, _ z: Int32, _ dimension: Int32) -> Data {
        var data = Data("digp".utf8)
        data.appendLE(x); data.appendLE(z)
        if dimension != 0 { data.appendLE(dimension) }
        return data
    }
    static func nonCanonicalOverworldDigestKey(_ x: Int32, _ z: Int32) -> Data {
        var data = digestKey(x, z, 0)
        data.appendLE(Int32(0))
        return data
    }
    static func digest(_ id: Int64) -> Data {
        var data = Data()
        let bits = UInt64(bitPattern: id)
        for shift in stride(from: 0, through: 56, by: 8) {
            data.append(UInt8(truncatingIfNeeded: bits >> UInt64(shift)))
        }
        return data
    }

    static func main() throws {
        let actorID: Int64 = 42
        let actorDocument = NBTDocument(rootName: "", root: .compound([
            NBTNamedTag(name: "identifier", value: .string("minecraft:pig")),
            NBTNamedTag(name: "UniqueID", value: .long(actorID)),
            NBTNamedTag(name: "Pos", value: .list(.float, [.float(1.5), .float(64), .float(1.5)]))
        ]))
        let actorStorageKey = actorKey(actorID)
        let oldDigestKey = nonCanonicalOverworldDigestKey(0, 0)
        let database = MojangLevelDB(values: [
            actorStorageKey: try BedrockNBTCodec.encode(actorDocument),
            oldDigestKey: digest(actorID)
        ])
        let session = WorldSession(db: database)
        let store = BedrockWorldObjectNBTStore(session: session)
        let repairedDigestCount = try store.repairAppCreatedOverworldActorDigests()
        precondition(repairedDigestCount == 1)
        precondition(database.values[oldDigestKey] == nil)
        precondition(database.values[digestKey(0, 0, 0)] == digest(actorID))
        let scanner = BedrockWorldObjectScanner(database: database)
        let actor = try scanner.scanRegion(
            centerX: 0, centerZ: 0, dimension: 0, radius: 0,
            includeEntities: true, includeBlockEntities: false
        ).objects[0]
        var editedActor = actor.document
        editedActor.root = try NBTTreeMutation.replacingValue(
            at: [.compound("Pos"), .list(0)], in: editedActor.root, with: .float(33.5)
        )
        let actorResult = try BedrockWorldObjectNBTStore(session: session).save(object: actor, document: editedActor)
        precondition(actorResult.moved && actorResult.destinationChunkX == 2)
        precondition(database.values[oldDigestKey] == nil)
        precondition(database.values[digestKey(2, 0, 0)] == digest(actorID))

        let chest = NBTDocument(rootName: "", root: .compound([
            NBTNamedTag(name: "id", value: .string("Chest")),
            NBTNamedTag(name: "x", value: .int(2)),
            NBTNamedTag(name: "y", value: .int(64)),
            NBTNamedTag(name: "z", value: .int(2))
        ]))
        let furnace = NBTDocument(rootName: "", root: .compound([
            NBTNamedTag(name: "id", value: .string("Furnace")),
            NBTNamedTag(name: "x", value: .int(3)),
            NBTNamedTag(name: "y", value: .int(64)),
            NBTNamedTag(name: "z", value: .int(3))
        ]))
        let sourceKey = BedrockDBKey(
            position: ChunkPosition(x: 0, z: 0, dimension: 0),
            recordType: .blockEntity, subChunkIndex: nil
        ).encoded()
        database.values[sourceKey] = try BedrockNBTCodec.encode(chest) + BedrockNBTCodec.encode(furnace)
        let blockObjects = try scanner.scanRegion(
            centerX: 0, centerZ: 0, dimension: 0, radius: 0,
            includeEntities: false, includeBlockEntities: true
        ).objects
        let chestObject = blockObjects.first { $0.identifier == "Chest" }!
        var editedChest = chestObject.document
        editedChest.root = try NBTTreeMutation.replacingValue(
            at: [.compound("x")], in: editedChest.root, with: .int(34)
        )
        let blockResult = try BedrockWorldObjectNBTStore(session: session).save(object: chestObject, document: editedChest)
        precondition(blockResult.moved && blockResult.destinationChunkX == 2)
        let sourceRecords = try ConsecutiveNBTCodec.decode(database.values[sourceKey]!)
        precondition(sourceRecords.count == 1)
        precondition(sourceRecords[0].document.root.stringValue(namedAny: ["id"]) == "Furnace")
        let targetKey = BedrockDBKey(
            position: ChunkPosition(x: 2, z: 0, dimension: 0),
            recordType: .blockEntity, subChunkIndex: nil
        ).encoded()
        let targetRecords = try ConsecutiveNBTCodec.decode(database.values[targetKey]!)
        precondition(targetRecords.count == 1)
        precondition(targetRecords[0].document.root.stringValue(namedAny: ["id"]) == "Chest")

        // UniqueID changes must migrate both actorprefix and digp references.
        let movedActor = try scanner.scanRegion(
            centerX: 2, centerZ: 0, dimension: 0, radius: 0,
            includeEntities: true, includeBlockEntities: false
        ).objects[0]
        var identityEdited = movedActor.document
        identityEdited.root = try NBTTreeMutation.replacingValue(
            at: [.compound("UniqueID")], in: identityEdited.root, with: .long(84)
        )
        let identityResult = try BedrockWorldObjectNBTStore(session: session).save(
            object: movedActor,
            document: identityEdited
        )
        precondition(identityResult.uniqueIDChanged && identityResult.destinationUniqueID == 84)
        precondition(database.values[actorKey(actorID)] == nil)
        precondition(database.values[actorKey(84)] != nil)
        precondition(database.values[digestKey(2, 0, 0)] == digest(84))

        let renamedActor = try scanner.scanRegion(
            centerX: 2, centerZ: 0, dimension: 0, radius: 0,
            includeEntities: true, includeBlockEntities: false
        ).objects[0]
        try BedrockWorldObjectNBTStore(session: session).delete(object: renamedActor)
        precondition(database.values[actorKey(84)] == nil)
        precondition(database.values[digestKey(2, 0, 0)] == nil)

        let createdActor = try BedrockWorldObjectNBTStore(session: session).create(
            kind: .entity,
            identifier: "minecraft:cow",
            position: BedrockWorldObjectPosition(x: 80, y: 70, z: 16),
            dimension: 0,
            uniqueID: 1001,
            template: nil
        )
        precondition(createdActor.uniqueID == 1001)
        precondition(database.values[actorKey(1001)] != nil)
        precondition(database.values[digestKey(5, 1, 0)] == digest(1001))
        let createdActorDocument = try BedrockNBTCodec.decode(database.values[actorKey(1001)]!)
        precondition(createdActorDocument.root.stringValue(namedAny: ["identifier"]) == "minecraft:cow")
        let createdDefinitions = createdActorDocument.root.value(namedAny: ["definitions"])?.listValues ?? []
        precondition(createdDefinitions.contains { value in
            if case .string(let definition) = value { return definition == "+minecraft:cow" }
            return false
        })
        precondition(createdActorDocument.root.int64Value(namedAny: ["Persistent"]) == 1)
        precondition(createdActorDocument.root.int64Value(namedAny: ["Air"]) == 300)
        precondition(createdActorDocument.root.int64Value(namedAny: ["DimensionId"]) == 0)
        precondition(createdActorDocument.root.value(namedAny: ["Motion"])?.listValues?.count == 3)
        precondition(createdActorDocument.root.value(namedAny: ["Rotation"])?.listValues?.count == 2)
        precondition(createdActorDocument.root.int64Value(namedAny: ["IsAutonomous"]) == 0)
        precondition(createdActorDocument.root.int64Value(namedAny: ["ShowBottom"]) == 0)
        precondition(createdActorDocument.root.int64Value(namedAny: ["IsEating"]) == 0)
        precondition(createdActorDocument.root.value(namedAny: ["LinksTag"]) == nil)
        precondition(createdActorDocument.root.value(namedAny: ["FireImmune"]) == nil)
        precondition(createdActorDocument.root.value(namedAny: ["HasCollision"]) == nil)
        precondition(createdActorDocument.root.value(namedAny: ["HasGravity"]) == nil)
        precondition(createdActorDocument.root.value(namedAny: ["HasOwner"]) == nil)
        precondition(createdActorDocument.root.value(namedAny: ["Age"]) == nil)
        precondition(createdActorDocument.root.value(namedAny: ["Tags"])?.listValues?.isEmpty == true)

        // The game removes an actor ID from digp when the actor dies. A stale
        // actorprefix value alone must not continue to appear as a live entity.
        database.values.removeValue(forKey: digestKey(5, 1, 0))
        let orphanScan = try scanner.scanAll(
            dimensions: [0], includeEntities: true, includeBlockEntities: false
        )
        precondition(!orphanScan.objects.contains { $0.uniqueID == 1001 })
        precondition(orphanScan.diagnostics.contains { $0.contains("孤立 actorprefix") })
        database.values[digestKey(5, 1, 0)] = digest(1001)

        let createdBlockEntity = try BedrockWorldObjectNBTStore(session: session).create(
            kind: .blockEntity,
            identifier: "Chest",
            position: BedrockWorldObjectPosition(x: 96, y: 64, z: 16),
            dimension: 0,
            uniqueID: nil,
            template: nil
        )
        let createdBlockKey = BedrockDBKey(
            position: ChunkPosition(x: createdBlockEntity.chunkX, z: createdBlockEntity.chunkZ, dimension: 0),
            recordType: .blockEntity,
            subChunkIndex: nil
        ).encoded()
        let createdBlockRecord = try ConsecutiveNBTCodec.decode(database.values[createdBlockKey]!)[0]
        let createdBlockObject = BedrockWorldObject(
            stableID: "created-block", kind: .blockEntity, identifier: "Chest", customName: nil,
            position: BedrockWorldObjectPosition(x: 96, y: 64, z: 16), dimension: 0,
            chunkX: createdBlockEntity.chunkX, chunkZ: createdBlockEntity.chunkZ,
            source: .blockEntity, uniqueID: nil, itemCount: 0,
            document: createdBlockRecord.document, rawData: createdBlockRecord.rawData,
            storage: .chunkRecord(key: createdBlockKey, recordIndex: 0, encoding: createdBlockRecord.encoding)
        )
        try BedrockWorldObjectNBTStore(session: session).delete(object: createdBlockObject)
        precondition(database.values[createdBlockKey] == nil)

        // v1.1.7: worlds that still contain per-chunk Entity(0x32) records
        // must create new actors in that same format. Numeric entity id tags
        // are preserved when copying unusual legacy entities.
        let legacyKey = BedrockDBKey(
            position: ChunkPosition(x: 0, z: 0, dimension: 0),
            recordType: .entity,
            subChunkIndex: nil
        ).encoded()
        let legacyDocument = NBTDocument(rootName: "", root: .compound([
            NBTNamedTag(name: "id", value: .short(12)),
            NBTNamedTag(name: "definitions", value: .list(.string, [.string("+minecraft:pig")])),
            NBTNamedTag(name: "UniqueID", value: .long(7001)),
            NBTNamedTag(name: "Pos", value: .list(.float, [.float(1), .float(64), .float(1)]))
        ]))
        let legacyRaw = try BedrockNBTCodec.encode(legacyDocument)
        let strayActorID: Int64 = 7099
        let strayActorDocument = NBTDocument(rootName: "", root: .compound([
            NBTNamedTag(name: "identifier", value: .string("minecraft:pig")),
            NBTNamedTag(name: "UniqueID", value: .long(strayActorID)),
            NBTNamedTag(name: "Pos", value: .list(.float, [.float(40), .float(64), .float(8)]))
        ]))
        let legacyDatabase = MojangLevelDB(values: [
            legacyKey: try ConsecutiveNBTCodec.encode([
                ConsecutiveNBTRecord(document: legacyDocument, rawData: legacyRaw, encoding: .littleEndian)
            ]),
            actorKey(strayActorID): try BedrockNBTCodec.encode(strayActorDocument),
            digestKey(2, 0, 0): digest(strayActorID)
        ])
        let legacySession = WorldSession(db: legacyDatabase)
        let legacyCreated = try BedrockWorldObjectNBTStore(session: legacySession).create(
            kind: .entity,
            identifier: "minecraft:cow",
            position: BedrockWorldObjectPosition(x: 40, y: 70, z: 8),
            dimension: 0,
            uniqueID: 7002,
            template: nil
        )
        precondition(legacyCreated.source == .legacyChunkEntity)
        precondition(legacyDatabase.values[actorKey(7002)] == nil)
        let legacyTargetKey = BedrockDBKey(
            position: ChunkPosition(x: 2, z: 0, dimension: 0),
            recordType: .entity,
            subChunkIndex: nil
        ).encoded()
        let legacyCreatedRecord = try ConsecutiveNBTCodec.decode(legacyDatabase.values[legacyTargetKey]!)[0]
        guard case .short(let legacyNumericID)? = legacyCreatedRecord.document.root.value(namedAny: ["id"]) else {
            preconditionFailure("legacy entity id is not numeric")
        }
        precondition(legacyNumericID == 11)

        // v1.1.14: kill @e may target several entities stored as consecutive
        // roots in the same Entity(0x32) value. They must be removed from one
        // decoded snapshot and committed in a single batch, otherwise indexes
        // from the original scan become stale after the first deletion.
        let crowdedKey = BedrockDBKey(
            position: ChunkPosition(x: 7, z: 7, dimension: 0),
            recordType: .entity,
            subChunkIndex: nil
        ).encoded()
        func crowdedEntity(_ identifier: String, _ uniqueID: Int64, _ x: Float) -> NBTDocument {
            NBTDocument(rootName: "", root: .compound([
                NBTNamedTag(name: "identifier", value: .string(identifier)),
                NBTNamedTag(name: "definitions", value: .list(.string, [.string("+\(identifier)")])),
                NBTNamedTag(name: "UniqueID", value: .long(uniqueID)),
                NBTNamedTag(name: "DimensionId", value: .int(0)),
                NBTNamedTag(name: "Pos", value: .list(.float, [.float(x), .float(70), .float(113)]))
            ]))
        }
        let crowdedDocuments = [
            crowdedEntity("minecraft:pig", 8101, 113),
            crowdedEntity("minecraft:cow", 8102, 114),
            crowdedEntity("minecraft:sheep", 8103, 115)
        ]
        let crowdedRecords = try crowdedDocuments.map { document -> ConsecutiveNBTRecord in
            let raw = try BedrockNBTCodec.encode(document)
            return ConsecutiveNBTRecord(document: document, rawData: raw, encoding: .littleEndian)
        }
        database.values[crowdedKey] = try ConsecutiveNBTCodec.encode(crowdedRecords)
        let crowdedObjects = try scanner.scanRegion(
            centerX: 7, centerZ: 7, dimension: 0, radius: 0,
            includeEntities: true, includeBlockEntities: false
        ).objects.filter { [8101, 8102, 8103].contains($0.uniqueID ?? 0) }
        precondition(crowdedObjects.count == 3)
        let crowdedDeleted = try store.delete(objects: crowdedObjects)
        precondition(crowdedDeleted == 3)
        precondition(database.values[crowdedKey] == nil)

        print("Entity/block-entity create, atomic multi-delete, UniqueID, storage mode and position migration tests passed")
    }
}
SWIFT
swiftc \
  "$ROOT/Sources/Support/Errors.swift" \
  "$ROOT/Sources/Support/Hex.swift" \
  "$ROOT/Sources/Support/AtomicFile.swift" \
  "$ROOT/Sources/NBT/NBTTypes.swift" \
  "$ROOT/Sources/NBT/BinaryCursor.swift" \
  "$ROOT/Sources/NBT/BedrockNBTCodec.swift" \
  "$ROOT/Sources/NBT/ConsecutiveNBTCodec.swift" \
  "$ROOT/Sources/Chunk/MapCoordinate.swift" \
  "$ROOT/Sources/Chunk/BedrockDBKey.swift" \
  "$ROOT/Sources/UI/NBTNode.swift" \
  "$TMP/WorldObjectNBTStoreStubs.swift" \
  "$ROOT/Sources/Support/BedrockDataValueCatalog.swift" \
  "$ROOT/Sources/Entity/BedrockWorldObject.swift" \
  "$ROOT/Sources/Entity/BedrockWorldObjectScanner.swift" \
  "$ROOT/Sources/Entity/BedrockEntityCommonNBT.swift" \
  "$ROOT/Sources/Entity/BedrockWorldObjectNBTStore.swift" \
  -parse-as-library "$TMP/world_object_nbt_test.swift" -o "$TMP/world-object-nbt-tests"
"$TMP/world-object-nbt-tests"

echo "Editable entity and block-entity NBT with index-safe migration passed"

# v0.10.0: unified NBT mutation, editable block palette NBT and bundle identity.
grep -q 'PRODUCT_BUNDLE_IDENTIFIER: com.wzn.mcbeeditor$' "$ROOT/project.yml" || {
  echo 'error: app bundle identifier must be com.wzn.mcbeeditor' >&2
  exit 1
}
grep -q 'PRODUCT_BUNDLE_IDENTIFIER: com.wzn.mcbeeditor.tests$' "$ROOT/project.yml" || {
  echo 'error: test bundle identifier must use com.wzn.mcbeeditor.tests' >&2
  exit 1
}
! grep -R -q 'com\.beartim\.mcbeeditor' "$ROOT/project.yml" "$ROOT/Sources" || {
  echo 'error: stale com.beartim.mcbeeditor identifier remains' >&2
  exit 1
}
grep -q 'static func presentEdit' "$ROOT/Sources/UI/NBTEditingUI.swift" || {
  echo 'error: generic NBT value editor is missing' >&2
  exit 1
}
for editor in \
  NBTTreeViewController.swift \
  PlayerNBTEditorViewController.swift \
  StructureNBTEditorViewController.swift \
  WorldObjectNBTEditorViewController.swift; do
  grep -q 'contextMenuConfigurationForRowAt' "$ROOT/Sources/UI/$editor" || {
    echo "error: $editor is missing add/delete/rename context actions" >&2
    exit 1
  }
  grep -q 'NBTEditingUI.presentEdit' "$ROOT/Sources/UI/$editor" || {
    echo "error: $editor is missing generic value modification" >&2
    exit 1
  }
done
! grep -R -q 'ReadOnlyNBTViewController(title: object.displayName' \
  "$ROOT/Sources/UI/EntityBrowserViewController.swift" \
  "$ROOT/Sources/UI/MapSelectionResultsViewController.swift" \
  "$ROOT/Sources/UI/WorldMapViewController.swift" || {
  echo 'error: known entity records still expose a separate read-only NBT editor' >&2
  exit 1
}
grep -q 'final class BedrockBlockNBTStore' "$ROOT/Sources/Chunk/BedrockSubChunkEditor.swift" || {
  echo 'error: block NBT SubChunk writer is missing' >&2
  exit 1
}
grep -q 'final class MapBlockDetailPanelView: UIView.*UITableViewDataSource' "$ROOT/Sources/UI/MapBlockDetailPanelView.swift" || {
  echo 'error: map block detail panel is not an NBT tree editor' >&2
  exit 1
}
grep -q 'blockDetailPanel.onSave' "$ROOT/Sources/UI/WorldMapViewController.swift" || {
  echo 'error: map block NBT save callback is not connected' >&2
  exit 1
}

cat > "$TMP/BlockNBTEditorStubs.swift" <<'SWIFT'
import Foundation
struct ImportedWorld { let id = UUID() }
final class MojangLevelDB {
    var values: [Data: Data] = [:]
    func get(_ key: Data) throws -> Data? { values[key] }
    func put(_ value: Data, for key: Data, sync: Bool = true) throws { values[key] = value }
    func applyBatch(puts: [(key: Data, value: Data)], deletes: [Data], sync: Bool = true) throws {
        for key in deletes { values.removeValue(forKey: key) }
        for put in puts { values[put.key] = put.value }
    }
    func entries(prefix: Data? = nil, includeValues: Bool = false, limit: Int = 0) throws -> [(key: Data, value: Data?)] {
        let matches = values.keys.filter { key in
            guard let prefix = prefix else { return true }
            return key.starts(with: prefix)
        }.sorted { $0.lexicographicallyPrecedes($1) }
        let selected = limit > 0 ? Array(matches.prefix(limit)) : matches
        return selected.map { ($0, includeValues ? values[$0] : nil) }
    }
}
final class WorldSession {
    let world = ImportedWorld()
    private let db = MojangLevelDB()
    func database() throws -> MojangLevelDB { db }
}
final class WorldStore {
    static let shared = WorldStore()
    func metadataURL(for world: ImportedWorld) -> URL { FileManager.default.temporaryDirectory }
}
enum AtomicFile { static func write(_ data: Data, to url: URL) throws { try data.write(to: url) } }
enum MapCoordinate {
    static func chunk(fromBlock coordinate: Int64) -> Int32 { Int32(floor(Double(coordinate) / 16.0)) }
    static func blockOrigin(ofChunk chunk: Int32) -> Int64 { Int64(chunk) * 16 }
}
struct BedrockBlockRecord {
    static let editableLayerCount = 2
    let x: Int64; let y: Int32; let z: Int64; let dimension: Int32
    let layers: [BedrockBlockState]; let isGenerated: Bool
}
SWIFT
cat > "$TMP/block_nbt_editor_test.swift" <<'SWIFT'
import Foundation
@main
struct BlockNBTEditorTest {
    static func state(_ name: String, property: Int32) -> BedrockBlockState {
        BedrockBlockState(nbt: .compound([
            NBTNamedTag(name: "name", value: .string(name)),
            NBTNamedTag(name: "states", value: .compound([
                NBTNamedTag(name: "test_property", value: .int(property))
            ])),
            NBTNamedTag(name: "version", value: .int(18168865))
        ]), legacyID: nil, legacyData: nil)
    }
    static func main() throws {
        let air = state("minecraft:air", property: 0)
        let stone = state("minecraft:stone", property: 1)
        let vine = state("minecraft:vine", property: 2)
        var indices = Array(repeating: UInt16(0), count: 4096)
        indices[(2 << 8) | (4 << 4) | 3] = 1
        let storage = SubChunkStorage(bitsPerBlock: 1, palette: [air, stone], indices: indices)
        let chunk = BedrockSubChunk(version: 9, yIndex: 0, storages: [storage], trailingData: Data([0xaa, 0xbb]))
        let changed = try chunk.replacingBlockState(x: 2, y: 3, z: 4, storageIndex: 0, with: vine)
        precondition(changed.storages[0].bitsPerBlock == 2)
        let encoded = try changed.encodePersistent()
        let decoded = try BedrockSubChunk.decode(encoded, keyYIndex: 0)
        precondition(decoded.trailingData == Data([0xaa, 0xbb]))
        precondition(decoded.storages[0].blockState(x: 2, y: 3, z: 4)?.name == "minecraft:vine")
        precondition(decoded.storages[0].blockState(x: 0, y: 0, z: 0)?.name == "minecraft:air")

        let water = state("minecraft:water", property: 3)
        let withSecondLayer = try decoded.replacingBlockState(
            x: 2, y: 3, z: 4, storageIndex: 1, with: water
        )
        precondition(withSecondLayer.storages.count == 2)
        let secondDecoded = try BedrockSubChunk.decode(try withSecondLayer.encodePersistent(), keyYIndex: 0)
        precondition(secondDecoded.storages.count == 2)
        precondition(secondDecoded.storages[1].blockState(x: 2, y: 3, z: 4)?.name == "minecraft:water")
        precondition(secondDecoded.storages[1].blockState(x: 0, y: 0, z: 0)?.name == "minecraft:air")

        let v1 = BedrockSubChunk(version: 1, yIndex: 0, storages: [storage], trailingData: Data())
        let upgraded = try v1.replacingBlockState(x: 1, y: 1, z: 1, storageIndex: 1, with: water)
        precondition(upgraded.version == 8)
        precondition(upgraded.storages.count == 2)

        let criteria = BedrockBlockSearchCriteria(
            nameContains: "stone",
            stateCriteria: [BedrockBlockStateCriterion(keyContains: "test_", valueContains: "1")],
            layers: [0]
        )
        let replacement = BedrockBlockReplacement(
            name: "minecraft:polished_andesite",
            stateAssignments: ["test_property": "9", "new_flag": "true"],
            replaceAllStates: false
        )
        let searched = try chunk.replacingBlocks(criteria: criteria, replacement: replacement)
        precondition(searched.matchedBlockCount == 1)
        let replacedState = searched.subChunk.storages[0].blockState(x: 2, y: 3, z: 4)
        precondition(replacedState?.name == "minecraft:polished_andesite")
        precondition(replacedState?.stateProperties.contains(where: { $0.0 == "test_property" && $0.1 == "9" }) == true)
        precondition(replacedState?.stateProperties.contains(where: { $0.0 == "new_flag" && $0.1 == "1" }) == true)

        let layer0Operation = BedrockLayerBlockOperation(
            layer: 0,
            criteria: BedrockBlockSearchCriteria(
                nameContains: "vine",
                stateCriteria: [],
                layers: [0]
            ),
            replacement: BedrockBlockReplacement(
                name: "minecraft:diamond_block",
                typedStateAssignments: ["powered_bit": .byte(1)],
                replaceAllStates: true
            )
        )
        let layer1Operation = BedrockLayerBlockOperation(
            layer: 1,
            criteria: BedrockBlockSearchCriteria(
                nameContains: "water",
                stateCriteria: [],
                layers: [1]
            ),
            replacement: BedrockBlockReplacement(
                name: nil,
                typedStateAssignments: ["liquid_depth": .int(7)],
                replaceAllStates: true
            )
        )
        let layered = try withSecondLayer.replacingBlocks(operations: [layer0Operation, layer1Operation])
        precondition(layered.matchedBlockCount == 2)
        let layer0Result = layered.subChunk.storages[0].blockState(x: 2, y: 3, z: 4)
        precondition(layer0Result?.name == "minecraft:diamond_block")
        precondition(layer0Result?.stateProperties.count == 1)
        precondition(layer0Result?.stateProperties.contains(where: { $0.0 == "powered_bit" && $0.1 == "1" }) == true)
        let layer1Result = layered.subChunk.storages[1].blockState(x: 2, y: 3, z: 4)
        precondition(layer1Result?.name == "minecraft:water")
        precondition(layer1Result?.stateProperties.count == 1)
        precondition(layer1Result?.stateProperties.contains(where: { $0.0 == "liquid_depth" && $0.1 == "7" }) == true)

        // v0.11.2 coordinate-aware search: two filled search columns are
        // combined at the same block coordinate, then layer 0 is replaced and
        // an empty enabled layer-1 replacement deletes the original layer 1.
        var layer1Indices = Array(repeating: UInt16(0), count: 4096)
        layer1Indices[(2 << 8) | (4 << 4) | 3] = 1
        let waterStorage = SubChunkStorage(bitsPerBlock: 1, palette: [air, water], indices: layer1Indices)
        let dualLayerChunk = BedrockSubChunk(
            version: 8,
            yIndex: 0,
            storages: [storage, waterStorage],
            trailingData: Data([0x44])
        )
        let coordinated = BedrockCoordinatedBlockOperation(
            searchLayer0: BedrockBlockSearchCriteria(
                nameContains: "stone",
                stateCriteria: [],
                layers: [0]
            ),
            searchLayer1: BedrockBlockSearchCriteria(
                nameContains: "water",
                stateCriteria: [],
                layers: [1]
            ),
            searchScope: .both,
            layer0Replacement: BedrockBlockReplacement(
                name: "minecraft:gold_block",
                typedStateAssignments: [:],
                replaceAllStates: true
            ),
            changeLayer1: true,
            layer1Replacement: nil
        )
        let coordinatedResult = try dualLayerChunk.replacingBlocks(coordinatedOperation: coordinated)
        precondition(coordinatedResult.matchedBlockCount == 1)
        precondition(coordinatedResult.subChunk.storages[0].blockState(x: 2, y: 3, z: 4)?.name == "minecraft:gold_block")
        precondition(coordinatedResult.subChunk.storages.count == 1)
        precondition(coordinatedResult.subChunk.trailingData == Data([0x44]))

        let keepLayer1 = BedrockCoordinatedBlockOperation(
            searchLayer0: BedrockBlockSearchCriteria(nameContains: "stone", stateCriteria: [], layers: [0]),
            searchLayer1: nil,
            searchScope: .both,
            layer0Replacement: BedrockBlockReplacement(
                name: "minecraft:diamond_block",
                typedStateAssignments: [:],
                replaceAllStates: true
            ),
            changeLayer1: false,
            layer1Replacement: nil
        )
        let keepResult = try dualLayerChunk.replacingBlocks(coordinatedOperation: keepLayer1)
        precondition(keepResult.matchedBlockCount == 1)
        precondition(keepResult.subChunk.storages.count == 2)
        precondition(keepResult.subChunk.storages[1].blockState(x: 2, y: 3, z: 4)?.name == "minecraft:water")

        // v0.11.3 whole-layer operations: layer 1 is created for every
        // eligible coordinate, fully-air cells are optional, and layer clear
        // removes layer 1 or fills mandatory layer 0 with air.
        let bulkReplacement = BedrockBlockReplacement(
            name: "minecraft:water",
            typedStateAssignments: [:],
            replaceAllStates: true
        )
        let nonAirOnly = try v1.bulkReplacingLayer(
            1,
            replacement: bulkReplacement,
            includeCompletelyAirCells: false
        )
        precondition(nonAirOnly.affectedBlockCount == 1)
        precondition(nonAirOnly.subChunk.version == 8)
        precondition(nonAirOnly.subChunk.storages.count == 2)
        precondition(nonAirOnly.subChunk.storages[1].blockState(x: 2, y: 3, z: 4)?.name == "minecraft:water")
        precondition(nonAirOnly.subChunk.storages[1].blockState(x: 0, y: 0, z: 0)?.isAir == true)

        let includeAir = try v1.bulkReplacingLayer(
            1,
            replacement: bulkReplacement,
            includeCompletelyAirCells: true
        )
        precondition(includeAir.affectedBlockCount == 4096)
        precondition(includeAir.subChunk.storages[1].blockState(x: 0, y: 0, z: 0)?.name == "minecraft:water")

        let selectedColumnsOnly = try v1.bulkReplacingLayer(
            1,
            replacement: bulkReplacement,
            includeCompletelyAirCells: true,
            localXRange: 2...3,
            localZRange: 4...5
        )
        precondition(selectedColumnsOnly.affectedBlockCount == 64)
        precondition(selectedColumnsOnly.subChunk.storages[1].blockState(x: 2, y: 0, z: 4)?.name == "minecraft:water")
        precondition(selectedColumnsOnly.subChunk.storages[1].blockState(x: 1, y: 0, z: 4)?.isAir == true)
        precondition(selectedColumnsOnly.subChunk.storages[1].blockState(x: 2, y: 0, z: 3)?.isAir == true)

        let clearedLayer1 = try nonAirOnly.subChunk.clearingLayer(1)
        precondition(clearedLayer1.subChunk.storages.count == 1)
        let clearedLayer0 = try v1.clearingLayer(0)
        precondition(clearedLayer0.subChunk.storages[0].blockState(x: 2, y: 3, z: 4)?.isAir == true)
        precondition(clearedLayer0.subChunk.trailingData == v1.trailingData)

        // v1.1.14: editing a block in an unloaded chunk copies a compatible
        // version/palette/terrain profile from the same dimension, writes
        // FinalizedState=2, and persists the target SubChunk in one batch.
        let missingSession = WorldSession()
        let missingDB = try missingSession.database()
        let templatePosition = ChunkPosition(x: 0, z: 0, dimension: 0)
        let templateVersion = Data([42])
        let templateTerrain = Data(repeating: 0x2a, count: 640)
        try missingDB.put(templateVersion, for: BedrockDBKey(
            position: templatePosition, recordType: .version, subChunkIndex: nil
        ).encoded())
        try missingDB.put(templateTerrain, for: BedrockDBKey(
            position: templatePosition, recordType: .data3D, subChunkIndex: nil
        ).encoded())
        try missingDB.put(try chunk.encodePersistent(), for: BedrockDBKey.subChunk(
            x: 0, z: 0, dimension: 0, index: 0
        ))
        let missingBlock = BedrockBlockRecord(
            x: 160, y: 64, z: -32, dimension: 0,
            layers: [.editableAir(version: 18168865)],
            isGenerated: false
        )
        let diamond = state("minecraft:diamond_block", property: 9)
        let missingResult = try BedrockBlockNBTStore(session: missingSession).save(
            block: missingBlock,
            storageIndex: 0,
            document: NBTDocument(rootName: "", root: diamond.nbt!)
        )
        precondition(missingResult.block.isGenerated)
        let missingPosition = ChunkPosition(x: 10, z: -2, dimension: 0)
        let selectedProfile = try BedrockEmptyChunk.profile(
            database: missingDB, dimension: 0, preferLegacy: false
        )
        precondition(selectedProfile.versionValue == templateVersion)
        precondition(selectedProfile.terrainRecordType == .data3D)
        precondition(selectedProfile.terrainValue == templateTerrain)
        for record in BedrockEmptyChunk.metadataRecords(at: missingPosition, profile: selectedProfile) {
            let storedMetadata = try missingDB.get(record.key)
            precondition(storedMetadata == record.value)
        }
        let missingSubKey = BedrockDBKey.subChunk(x: 10, z: -2, dimension: 0, index: 4)
        guard let missingRaw = try missingDB.get(missingSubKey) else {
            preconditionFailure("missing SubChunk was not created")
        }
        let missingDecoded = try BedrockSubChunk.decode(missingRaw, keyYIndex: 4)
        precondition(missingDecoded.storages[0].blockState(x: 0, y: 0, z: 0)?.name == "minecraft:diamond_block")

        // v1.1.17: LegacyVersion/Data2D can legitimately contain paletted
        // SubChunk v8. Creating a missing Y=80 SubChunk must preserve v8 and
        // must not migrate the existing chunk metadata to Version/Data3D.
        let v8Session = WorldSession()
        let v8DB = try v8Session.database()
        let v8Position = ChunkPosition(x: 0, z: 0, dimension: 0)
        let v8Terrain = Data(repeating: 0x33, count: 768)
        try v8DB.put(Data([19]), for: BedrockDBKey(
            position: v8Position, recordType: .legacyVersion, subChunkIndex: nil
        ).encoded())
        try v8DB.put(v8Terrain, for: BedrockDBKey(
            position: v8Position, recordType: .data2D, subChunkIndex: nil
        ).encoded())
        let v8Sibling = BedrockSubChunk(
            version: 8,
            yIndex: 4,
            storages: [.airFilled(with: .editableAir(version: 17_825_808))],
            trailingData: Data()
        )
        try v8DB.put(try v8Sibling.encodePersistent(), for: BedrockDBKey.subChunk(
            x: 0, z: 0, dimension: 0, index: 4
        ))
        let v8Block = BedrockBlockRecord(
            x: 0, y: 80, z: 0, dimension: 0,
            layers: [.editableAir(version: 17_825_808)],
            isGenerated: false
        )
        _ = try BedrockBlockNBTStore(session: v8Session).save(
            block: v8Block,
            storageIndex: 0,
            document: NBTDocument(rootName: "", root: diamond.nbt!)
        )
        let v8CreatedKey = BedrockDBKey.subChunk(x: 0, z: 0, dimension: 0, index: 5)
        guard let v8CreatedRaw = try v8DB.get(v8CreatedKey) else {
            preconditionFailure("v8 Y=80 SubChunk was not created")
        }
        let v8Created = try BedrockSubChunk.decode(v8CreatedRaw, keyYIndex: 5)
        precondition(v8Created.version == 8)
        precondition(v8Created.storages[0].blockState(x: 0, y: 0, z: 0)?.name == "minecraft:diamond_block")
        let preservedV8LegacyVersion = try v8DB.get(BedrockDBKey(
            position: v8Position, recordType: .legacyVersion, subChunkIndex: nil
        ).encoded())
        let preservedV8Terrain = try v8DB.get(BedrockDBKey(
            position: v8Position, recordType: .data2D, subChunkIndex: nil
        ).encoded())
        let unexpectedV8ModernVersion = try v8DB.get(BedrockDBKey(
            position: v8Position, recordType: .version, subChunkIndex: nil
        ).encoded())
        precondition(preservedV8LegacyVersion == Data([19]))
        precondition(preservedV8Terrain == v8Terrain)
        precondition(unexpectedV8ModernVersion == nil)

        let missingLegacyBlock = BedrockBlockRecord(
            x: 176, y: 64, z: -32, dimension: 0,
            layers: [BedrockBlockState(nbt: nil, legacyID: 1, legacyData: 0)],
            isGenerated: false
        )
        let legacyDocument = NBTDocument(rootName: "", root: .compound([
            NBTNamedTag(name: "legacy_id", value: .int(5)),
            NBTNamedTag(name: "legacy_data", value: .byte(2)),
            NBTNamedTag(name: "name", value: .string("minecraft:planks"))
        ]))
        _ = try BedrockBlockNBTStore(session: missingSession).save(
            block: missingLegacyBlock, storageIndex: 0, document: legacyDocument
        )
        let missingLegacyKey = BedrockDBKey.subChunk(x: 11, z: -2, dimension: 0, index: 4)
        guard let missingLegacyRaw = try missingDB.get(missingLegacyKey) else {
            preconditionFailure("missing legacy SubChunk was not created")
        }
        let missingLegacyDecoded = try BedrockSubChunk.decode(missingLegacyRaw, keyYIndex: 4)
        let missingLegacyState = missingLegacyDecoded.storages[0].blockState(x: 0, y: 0, z: 0)
        // The dimension is modern, so a numeric placeholder is converted to a
        // compatible modern palette state instead of mixing v7 data with Version.
        precondition(missingLegacyDecoded.version == 9)
        precondition(missingLegacyState?.name == "minecraft:planks")
        precondition(missingLegacyState?.legacyID == nil)

        // A genuinely legacy-only dimension keeps LegacyVersion/Data2D and v7
        // numeric SubChunks when an unloaded chunk is materialized.
        let legacyOnlySession = WorldSession()
        let legacyOnlyDB = try legacyOnlySession.database()
        let legacyTemplate = ChunkPosition(x: 0, z: 0, dimension: 0)
        try legacyOnlyDB.put(Data([15]), for: BedrockDBKey(
            position: legacyTemplate, recordType: .legacyVersion, subChunkIndex: nil
        ).encoded())
        let legacyTerrain = Data(repeating: 0x11, count: 768)
        try legacyOnlyDB.put(legacyTerrain, for: BedrockDBKey(
            position: legacyTemplate, recordType: .data2D, subChunkIndex: nil
        ).encoded())
        let legacyOnlyBlock = BedrockBlockRecord(
            x: 192, y: 64, z: -32, dimension: 0,
            layers: [BedrockBlockState(nbt: nil, legacyID: 1, legacyData: 0)],
            isGenerated: false
        )
        _ = try BedrockBlockNBTStore(session: legacyOnlySession).save(
            block: legacyOnlyBlock, storageIndex: 0, document: legacyDocument
        )
        let legacyOnlyPosition = ChunkPosition(x: 12, z: -2, dimension: 0)
        let legacyVersionKey = BedrockDBKey(
            position: legacyOnlyPosition, recordType: .legacyVersion, subChunkIndex: nil
        ).encoded()
        let legacyTerrainKey = BedrockDBKey(
            position: legacyOnlyPosition, recordType: .data2D, subChunkIndex: nil
        ).encoded()
        let persistedLegacyVersion = try legacyOnlyDB.get(legacyVersionKey)
        let persistedLegacyTerrain = try legacyOnlyDB.get(legacyTerrainKey)
        precondition(persistedLegacyVersion == Data([15]))
        precondition(persistedLegacyTerrain == legacyTerrain)
        let legacyOnlySubKey = BedrockDBKey.subChunk(x: 12, z: -2, dimension: 0, index: 4)
        guard let legacyOnlyRaw = try legacyOnlyDB.get(legacyOnlySubKey) else {
            preconditionFailure("legacy-only missing SubChunk was not created")
        }
        let legacyOnlyDecoded = try BedrockSubChunk.decode(legacyOnlyRaw, keyYIndex: 4)
        let legacyOnlyState = legacyOnlyDecoded.storages[0].blockState(x: 0, y: 0, z: 0)
        precondition(legacyOnlyDecoded.version == 7)
        precondition(legacyOnlyState?.legacyID == 5)
        precondition(legacyOnlyState?.legacyData == 2)

        // v1.1.15: a modern block or any non-empty states upgrades the whole
        // legacy chunk to Version/Data3D plus v9 SubChunks before editing.
        let upperLegacy = BedrockSubChunk(
            version: 7, yIndex: 5, storages: legacyOnlyDecoded.storages, trailingData: Data()
        )
        let upperLegacyKey = BedrockDBKey.subChunk(x: 12, z: -2, dimension: 0, index: 5)
        try legacyOnlyDB.put(try upperLegacy.encodePersistent(), for: upperLegacyKey)
        let statefulDocument = NBTDocument(rootName: "", root: .compound([
            NBTNamedTag(name: "name", value: .string("minecraft:leaves")),
            NBTNamedTag(name: "states", value: .compound([
                NBTNamedTag(name: "old_leaf_type", value: .string("oak")),
                NBTNamedTag(name: "persistent_bit", value: .byte(1))
            ])),
            NBTNamedTag(name: "version", value: .int(18_153_728))
        ]))
        let legacyExistingBlock = BedrockBlockRecord(
            x: 192, y: 64, z: -32, dimension: 0,
            layers: [legacyOnlyState ?? BedrockBlockState(nbt: nil, legacyID: 5, legacyData: 2)],
            isGenerated: true
        )
        _ = try BedrockBlockNBTStore(session: legacyOnlySession).save(
            block: legacyExistingBlock, storageIndex: 0, document: statefulDocument
        )
        let modernVersionKey = BedrockDBKey(
            position: legacyOnlyPosition, recordType: .version, subChunkIndex: nil
        ).encoded()
        let data3DKey = BedrockDBKey(
            position: legacyOnlyPosition, recordType: .data3D, subChunkIndex: nil
        ).encoded()
        let savedModernVersion = try legacyOnlyDB.get(modernVersionKey)
        let removedLegacyVersion = try legacyOnlyDB.get(legacyVersionKey)
        let savedData3D = try legacyOnlyDB.get(data3DKey)
        let removedData2D = try legacyOnlyDB.get(legacyTerrainKey)
        precondition(savedModernVersion != nil)
        precondition(removedLegacyVersion == nil)
        precondition(savedData3D != nil)
        precondition(removedData2D == nil)
        guard let upgradedTargetRaw = try legacyOnlyDB.get(legacyOnlySubKey),
              let upgradedUpperRaw = try legacyOnlyDB.get(upperLegacyKey) else {
            preconditionFailure("legacy chunk upgrade did not persist all SubChunks")
        }
        let upgradedTarget = try BedrockSubChunk.decode(upgradedTargetRaw, keyYIndex: 4)
        let upgradedUpper = try BedrockSubChunk.decode(upgradedUpperRaw, keyYIndex: 5)
        precondition(upgradedTarget.version == 9 && upgradedUpper.version == 9)
        let upgradedState = upgradedTarget.storages[0].blockState(x: 0, y: 0, z: 0)
        precondition(upgradedState?.name == "minecraft:leaves")
        precondition(upgradedState?.stateProperties.count == 2)
        print("Editable block NBT, recursive command NBT, legacy-to-modern chunk upgrade and bulk layer operations passed")
    }
}
SWIFT
swiftc \
  "$ROOT/Sources/Support/Errors.swift" \
  "$ROOT/Sources/Support/Hex.swift" \
  "$ROOT/Sources/Support/BedrockDataValueCatalog.swift" \
  "$ROOT/Sources/Support/BedrockLegacyBlockCatalog.swift" \
  "$ROOT/Sources/NBT/BinaryCursor.swift" \
  "$ROOT/Sources/NBT/NBTTypes.swift" \
  "$ROOT/Sources/NBT/BedrockNBTCodec.swift" \
  "$ROOT/Sources/Chunk/BedrockDBKey.swift" \
  "$ROOT/Sources/Chunk/BedrockSubChunk.swift" \
  "$ROOT/Sources/Chunk/BedrockBiomeData.swift" \
  "$TMP/BlockNBTEditorStubs.swift" \
  "$ROOT/Sources/Chunk/BedrockEmptyChunk.swift" \
  "$ROOT/Sources/Chunk/BedrockLegacyChunkUpgrade.swift" \
  "$ROOT/Sources/Chunk/BedrockSubChunkEditor.swift" \
  -parse-as-library "$TMP/block_nbt_editor_test.swift" -o "$TMP/block-nbt-editor-tests"
"$TMP/block-nbt-editor-tests"

# v0.10.1: compact empty map layout, fixed layer 0/1 editing and no custom markers.
grep -q 'controls.setContentHuggingPriority(.required, for: .vertical)' "$ROOT/Sources/UI/WorldMapViewController.swift" || {
  echo 'error: map controls can stretch and recreate the empty top gap' >&2
  exit 1
}
! grep -q 'tableView.heightAnchor.constraint(greaterThanOrEqualToConstant: 180)' "$ROOT/Sources/UI/MapBlockDetailPanelView.swift" || {
  echo 'error: hidden block table still forces an oversized map header' >&2
  exit 1
}
grep -q 'for index in 0..<BedrockBlockRecord.editableLayerCount' "$ROOT/Sources/UI/MapBlockDetailPanelView.swift" || {
  echo 'error: block NBT panel does not expose fixed layer 0/layer 1 controls' >&2
  exit 1
}
grep -q 'while updatedStorages.count <= storageIndex' "$ROOT/Sources/Chunk/BedrockSubChunkEditor.swift" || {
  echo 'error: missing block storage creation for layer 1' >&2
  exit 1
}

# v0.11.0+: chunk list, map chunk selection, clear and regeneration tools.
for required in \
  "$ROOT/Sources/Chunk/BedrockChunkStore.swift" \
  "$ROOT/Sources/UI/ChunkListViewController.swift"; do
  [[ -f "$required" ]] || { echo "error: missing chunk management source: ${required#$ROOT/}" >&2; exit 1; }
done
grep -q 'func listChunks()' "$ROOT/Sources/Chunk/BedrockChunkStore.swift" || {
  echo 'error: chunk database discovery is missing' >&2; exit 1;
}
grep -q 'func copyChunk(from source: ChunkPosition, to destination: ChunkPosition)' "$ROOT/Sources/Chunk/BedrockChunkStore.swift" || {
  echo 'error: chunk copy operation is missing' >&2; exit 1;
}
grep -q 'func clearChunk(_ position: ChunkPosition)' "$ROOT/Sources/Chunk/BedrockChunkStore.swift" && \
grep -q 'func regenerateChunk(_ position: ChunkPosition)' "$ROOT/Sources/Chunk/BedrockChunkStore.swift" || {
  echo 'error: chunk clear or seed-regeneration operation is missing' >&2; exit 1;
}
grep -q 'func replaceBlocks(' "$ROOT/Sources/Chunk/BedrockChunkStore.swift" || {
  echo 'error: chunk block search/replace operation is missing' >&2; exit 1;
}
grep -q 'applyBatchWithPuts' "$ROOT/Sources/Bridge/BTLevelDBBridge.mm" || {
  echo 'error: atomic LevelDB WriteBatch bridge is missing' >&2; exit 1;
}
grep -q 'batch.Delete' "$ROOT/Sources/Bridge/BTLevelDBBridge.mm" && \
grep -q 'batch.Put' "$ROOT/Sources/Bridge/BTLevelDBBridge.mm" || {
  echo 'error: LevelDB batch does not include delete and put operations' >&2; exit 1;
}
grep -q 'private let selectedChunkLayer = CAShapeLayer()' "$ROOT/Sources/UI/WorldMapViewController.swift" || {
  echo 'error: selected chunk blinking overlay is missing' >&2; exit 1;
}
grep -q 'private let chunkSelectionSwitch = UISwitch()' "$ROOT/Sources/UI/WorldMapViewController.swift" || {
  echo 'error: map chunk-selection switch is missing' >&2; exit 1;
}
grep -q 'ChunkSearchReplaceViewController' "$ROOT/Sources/UI/ChunkListViewController.swift" || {
  echo 'error: chunk search/replace UI is missing' >&2; exit 1;
}

# v0.11.1: compact map controls, inline switches, compact block coordinates and NBT-style per-layer search/replace.
grep -q 'compactSwitch(title: "自动渲染"' "$ROOT/Sources/UI/WorldMapViewController.swift" && \
grep -q 'compactSwitch(title: "区块网格"' "$ROOT/Sources/UI/WorldMapViewController.swift" && \
grep -q 'compactSwitch(title: "选择区块"' "$ROOT/Sources/UI/WorldMapViewController.swift" || {
  echo 'error: the three map switches are missing from the map top row' >&2; exit 1;
}
grep -q 'renderButton.backgroundColor = .systemBlue' "$ROOT/Sources/UI/WorldMapViewController.swift" && \
grep -q 'controls.heightAnchor.constraint(equalToConstant:' "$ROOT/Sources/UI/WorldMapViewController.swift" || {
  echo 'error: compact blue render button or fixed map control height is missing' >&2; exit 1;
}
grep -q 'let coordinateRow = UIStackView(arrangedSubviews: \[xField, yField, zField\])' "$ROOT/Sources/UI/MapBlockDetailPanelView.swift" && \
grep -q 'jumpButton.backgroundColor = .systemBlue' "$ROOT/Sources/UI/MapBlockDetailPanelView.swift" || {
  echo 'error: compact one-line XYZ editor or blue jump button is missing' >&2; exit 1;
}
[[ -f "$ROOT/Sources/UI/BlockSearchReplaceNBTEditorView.swift" ]] || {
  echo 'error: NBT-style layer search/replace editor is missing' >&2; exit 1;
}
grep -q 'BlockSearchReplaceNBTEditorView(layerIndex: 0, mode: .search)' "$ROOT/Sources/UI/ChunkListViewController.swift" && \
grep -q 'BlockSearchReplaceNBTEditorView(layerIndex: 1, mode: .search)' "$ROOT/Sources/UI/ChunkListViewController.swift" && \
grep -q 'replaceAllStates: true' "$ROOT/Sources/UI/BlockSearchReplaceNBTEditorView.swift" || {
  echo 'error: layer 0/layer 1 NBT search UI or clear-states replacement default is missing' >&2; exit 1;
}
! grep -q 'replaceAllStatesSwitch' "$ROOT/Sources/UI/ChunkListViewController.swift" || {
  echo 'error: obsolete clear-states switch is still present' >&2; exit 1;
}
! grep -q 'private let layerControl = UISegmentedControl(items: \["层 0", "层 1", "层 0 + 1"\])' "$ROOT/Sources/UI/ChunkListViewController.swift" || {
  echo 'error: obsolete search-layer segmented control is still present' >&2; exit 1;
}

echo 'Compact map layout and NBT-style per-layer search/replace passed'

# v0.11.7 follow-up: numeric entity IDs, selected-position filters and chunk batch mode.
for expected in \
  '使用选中方块位置' \
  '使用选中实体/方块实体位置'; do
  grep -qF "$expected" "$ROOT/Sources/UI/EntityBrowserViewController.swift" || {
    echo "error: selected-position entity filter button is missing: $expected" >&2; exit 1;
  }
done
if grep -qF '使用地图位置' "$ROOT/Sources/UI/EntityBrowserViewController.swift"; then
  echo 'error: obsolete 使用地图位置 entity option is still present' >&2; exit 1;
fi
for expected in \
  'label("渲染中心坐标")' \
  'compactSwitch(title: "区块网格"' \
  'compactSwitch(title: "选择区块"'; do
  grep -qF "$expected" "$ROOT/Sources/UI/WorldMapViewController.swift" || {
    echo "error: renamed map control is missing: $expected" >&2; exit 1;
  }
done
for expected in \
  'beginBatchMode' \
  'showBatchActions' \
  'ChunkSearchReplaceViewController(session: self.session, chunks: chunks)' \
  'BulkLayerReplaceViewController(session: self.session, chunks: chunks)' \
  '统一修改生物群系' \
  '删除 HardcodedSpawners'; do
  grep -qF "$expected" "$ROOT/Sources/UI/ChunkListViewController.swift" || {
    echo "error: chunk batch processing feature is missing: $expected" >&2; exit 1;
  }
done
echo 'Numeric entity ID mapping, selected-position filters and chunk batch processing passed'

# v0.11.2 / v1.0.0: zoom-driven dynamic chunk windows without a fixed
# side-length cap. The UIScrollView zoom range expands as either boundary is
# reached so the application does not impose a fixed zoom limit.
! grep -q 'maximumDynamicSideChunks' "$ROOT/Sources/UI/WorldMapViewController.swift" && grep -q 'dynamicRenderSideChunks(forZoomScale:' "$ROOT/Sources/UI/WorldMapViewController.swift" && grep -q 'refreshForZoomDrivenRadiusIfNeeded()' "$ROOT/Sources/UI/WorldMapViewController.swift" && grep -q 'expandZoomRangeIfNeeded(for:' "$ROOT/Sources/UI/WorldMapViewController.swift" && grep -q 'maximum < CGFloat.greatestFiniteMagnitude / zoomRangeGrowthFactor' "$ROOT/Sources/UI/WorldMapViewController.swift" && grep -q 'maximumMapRasterSidePixels' "$ROOT/Sources/UI/WorldMapViewController.swift" && grep -q 'keepsPerBlockMetadata' "$ROOT/Sources/UI/WorldMapViewController.swift" && grep -q 'let rightChunks = sideChunks - leftChunks - 1' "$ROOT/Sources/UI/WorldMapViewController.swift" || {
  echo 'error: uncapped zoom-driven dynamic chunk rendering is missing' >&2; exit 1;
}
grep -q 'private let searchScopeControl = UISegmentedControl(items: \["层 0", "层 1", "层 0 和层 1"\])' "$ROOT/Sources/UI/ChunkListViewController.swift" && grep -q 'private let changeLayer1Switch = UISwitch()' "$ROOT/Sources/UI/ChunkListViewController.swift" || {
  echo 'error: layered search scope or layer-1 replacement switch is missing' >&2; exit 1;
}
grep -q 'struct BedrockCoordinatedBlockOperation' "$ROOT/Sources/Chunk/BedrockSubChunkEditor.swift" && grep -q 'coordinatedOperation operation: BedrockCoordinatedBlockOperation' "$ROOT/Sources/Chunk/BedrockChunkStore.swift" || {
  echo 'error: coordinate-aware layered search/replace core is missing' >&2; exit 1;
}
grep -q 'replacementLayer1.setEditorEnabled(false)' "$ROOT/Sources/UI/ChunkListViewController.swift" && grep -q 'layer1Replacement: changeLayer1Switch.isOn && replacementLayer1.hasContent' "$ROOT/Sources/UI/ChunkListViewController.swift" || {
  echo 'error: default layer-1 preservation behavior is missing' >&2; exit 1;
}

echo 'Zoom-driven chunk expansion and coordinated layered replacement passed'

# Fixed v1.0.0 follow-up: viewport state is kept only in memory per dimension,
# the radius filter buttons occupy exactly the center/radius rows, and spread
# output exposes the requested player colors.
grep -qF 'private var dimensionViewportStates = [Int32: MapDimensionViewportState]()' "$ROOT/Sources/UI/WorldMapViewController.swift" && \
grep -qF 'rememberCurrentViewportState(for: activeDimension)' "$ROOT/Sources/UI/WorldMapViewController.swift" && \
grep -qF 'for key in ["centerX", "centerZ", "dimension", "radius", "zoomScale"]' "$ROOT/Sources/UI/WorldMapViewController.swift" && \
grep -qF 'dimensionViewportStates.removeAll()' "$ROOT/Sources/UI/WorldMapViewController.swift" || {
  echo 'error: session-only per-dimension map viewport state is incomplete' >&2; exit 1;
}
grep -qF 'let primaryRadiusRows = UIStackView(arrangedSubviews: [center, radiusValueRow])' "$ROOT/Sources/UI/EntityBrowserViewController.swift" && \
grep -qF 'radiusPanel.addArrangedSubview(radiusYRow)' "$ROOT/Sources/UI/EntityBrowserViewController.swift" || {
  echo 'error: radius-mode action buttons are not aligned to the center/radius rows' >&2; exit 1;
}
grep -qF 'case .localPlayer: return .systemYellow' "$ROOT/Sources/UI/WorldCommandViewController.swift" && \
grep -qF 'case .onlinePlayer: return .systemBlue' "$ROOT/Sources/UI/WorldCommandViewController.swift" || {
  echo 'error: spread player output colors are incomplete' >&2; exit 1;
}
echo 'Session-only map viewport, radius layout and spread output colors passed'

# v0.11.3: persistent backup mechanisms are removed and the current chunk
# exposes full-layer replacement tools without persistent backup.
[[ ! -f "$ROOT/Sources/World/WorldBackupService.swift" ]] || {
  echo 'error: obsolete world snapshot service is still present' >&2; exit 1;
}
for forbidden in \
  'PlayerNBTBackups' 'StructureNBTBackups' 'EntityNBTBackups' \
  'BlockEntityNBTBackups' 'BlockNBTBackups' 'ChunkBackups' 'level.dat_old'; do
  if grep -R -qF "$forbidden" "$ROOT/Sources"; then
    echo "error: persistent backup mechanism remains in Sources: $forbidden" >&2
    exit 1
  fi
done
[[ -f "$ROOT/Sources/UI/BulkLayerReplaceViewController.swift" ]] || {
  echo 'error: bulk layer replacement UI is missing' >&2; exit 1;
}
grep -q 'func bulkReplaceLayer(' "$ROOT/Sources/Chunk/BedrockChunkStore.swift" && \
grep -q 'func bulkReplacingLayer(' "$ROOT/Sources/Chunk/BedrockSubChunkEditor.swift" && \
grep -q 'func clearingLayer(_ layer: Int)' "$ROOT/Sources/Chunk/BedrockSubChunkEditor.swift" || {
  echo 'error: bulk layer replacement or chunk-clear core is missing' >&2; exit 1;
}
grep -q '批量层0层1替换' "$ROOT/Sources/UI/ChunkListViewController.swift" && \
grep -q 'targetLayerControl.selectedSegmentIndex = 1' "$ROOT/Sources/UI/BulkLayerReplaceViewController.swift" && \
grep -q 'includeAirSwitch.isOn = false' "$ROOT/Sources/UI/BulkLayerReplaceViewController.swift" || {
  echo 'error: bulk layer replacement defaults or entry point are missing' >&2; exit 1;
}

echo 'No-backup policy and bulk layer replacement passed'

# v0.11.4: per-layer destructive buttons are gone; chunk clear and seed
# regeneration are separate operations in the five-item chunk action menu.
! grep -q '删除所有层0内容\|删除所有层1内容' "$ROOT/Sources/UI/BulkLayerReplaceViewController.swift" || {
  echo 'error: obsolete per-layer delete buttons remain in bulk replacement UI' >&2; exit 1;
}
grep -q 'UIAlertAction(title: "清空区块…"' "$ROOT/Sources/UI/ChunkListViewController.swift" && \
grep -q 'UIAlertAction(title: "重新生成区块…"' "$ROOT/Sources/UI/ChunkListViewController.swift" && \
grep -q 'func clearChunk(_ position: ChunkPosition)' "$ROOT/Sources/Chunk/BedrockChunkStore.swift" && \
grep -q 'func regenerateChunk(_ position: ChunkPosition)' "$ROOT/Sources/Chunk/BedrockChunkStore.swift" || {
  echo 'error: chunk clear/regenerate menu or store operations are missing' >&2; exit 1;
}
! grep -q 'func deleteChunk(_ position: ChunkPosition)' "$ROOT/Sources/Chunk/BedrockChunkStore.swift" || {
  echo 'error: obsolete deleteChunk API is still exposed' >&2; exit 1;
}

echo 'Chunk clear and seed-based regeneration passed'

# v0.11.5: clear removes invalid dependent objects; regeneration deletes all
# raw chunk-prefix records instead of only a whitelist of known tags.
grep -q 'case conversionData = 0x37' "$ROOT/Sources/Chunk/BedrockDBKey.swift" && \
grep -q 'case generationSeed = 0x3c' "$ROOT/Sources/Chunk/BedrockDBKey.swift" && \
grep -q 'case actorDigestVersion = 0x41' "$ROOT/Sources/Chunk/BedrockDBKey.swift" && \
grep -q 'case legacyVersion = 0x76' "$ROOT/Sources/Chunk/BedrockDBKey.swift" || {
  echo 'error: modern LevelChunkTag coverage is incomplete' >&2; exit 1;
}
grep -q 'enum BedrockRawChunkKey' "$ROOT/Sources/Chunk/BedrockDBKey.swift" && \
grep -q 'rawChunkRecords(at: position' "$ROOT/Sources/Chunk/BedrockChunkStore.swift" && \
grep -q 'BedrockRawChunkKey.matches' "$ROOT/Sources/Chunk/BedrockChunkStore.swift" || {
  echo 'error: Android-style raw chunk-prefix regeneration is missing' >&2; exit 1;
}
grep -q 'actorRecordsForRemoval' "$ROOT/Sources/Chunk/BedrockChunkStore.swift" && \
grep -q 'Data("actorprefix".utf8)' "$ROOT/Sources/Chunk/BedrockChunkStore.swift" || {
  echo 'error: chunk clear/regeneration does not remove referenced modern actors' >&2; exit 1;
}
grep -q 'BedrockEmptyChunk.metadataRecords(at: position, profile: profile)' "$ROOT/Sources/Chunk/BedrockChunkStore.swift" && \
grep -q 'static let legacyDefault' "$ROOT/Sources/Chunk/BedrockEmptyChunk.swift" && \
grep -q 'finalizedValue.appendLE(Int32(2))' "$ROOT/Sources/Chunk/BedrockEmptyChunk.swift" || {
  echo 'error: clear chunk does not recreate the Android-style minimal pure-air skeleton' >&2; exit 1;
}

cat > "$TMP/raw_chunk_key_test.swift" <<'SWIFT'
import Foundation

@main
enum RawChunkKeyTests {
    static func main() {
        let overworld = ChunkPosition(x: 8, z: -8, dimension: 0)
        var conversion = Data()
        conversion.appendLE(overworld.x)
        conversion.appendLE(overworld.z)
        conversion.append(UInt8(0x37))
        precondition(BedrockRawChunkKey.matches(conversion, position: overworld))

        var generationSeed = Data()
        generationSeed.appendLE(overworld.x)
        generationSeed.appendLE(overworld.z)
        generationSeed.appendLE(overworld.dimension)
        generationSeed.append(UInt8(0x3c))
        precondition(BedrockRawChunkKey.matches(generationSeed, position: overworld))

        var legacyVersion = Data()
        legacyVersion.appendLE(overworld.x)
        legacyVersion.appendLE(overworld.z)
        legacyVersion.append(UInt8(0x76))
        precondition(BedrockRawChunkKey.matches(legacyVersion, position: overworld))

        let nether = ChunkPosition(x: -3, z: 7, dimension: 1)
        var blending = Data()
        blending.appendLE(nether.x)
        blending.appendLE(nether.z)
        blending.appendLE(nether.dimension)
        blending.append(UInt8(0x40))
        precondition(BedrockRawChunkKey.matches(blending, position: nether))
        precondition(!BedrockRawChunkKey.matches(blending, position: ChunkPosition(x: -3, z: 7, dimension: 2)))
        precondition(ChunkRecordType(rawValue: 0x41) == .actorDigestVersion)
        print("Raw chunk key deletion coverage passed")
    }
}
SWIFT
swiftc \
  "$ROOT/Sources/Support/Errors.swift" \
  "$ROOT/Sources/Support/Hex.swift" \
  "$ROOT/Sources/Chunk/BedrockDBKey.swift" \
  "$TMP/raw_chunk_key_test.swift" \
  -o "$TMP/raw-chunk-key-tests"
"$TMP/raw-chunk-key-tests"

echo 'Crash-safe chunk clear and complete seed regeneration passed'

# v0.11.6: clear recreates an Android-style pure-air chunk and chunk details
# expose structured biome and HardcodedSpawners editors.
for required in \
  "$ROOT/Sources/Chunk/BedrockBiomeData.swift" \
  "$ROOT/Sources/Chunk/HardcodedSpawners.swift" \
  "$ROOT/Sources/UI/ChunkBiomeEditorViewController.swift" \
  "$ROOT/Sources/UI/HardcodedSpawnersViewController.swift"; do
  [[ -f "$required" ]] || {
    echo "error: missing v0.11.6 chunk-data source: ${required#$ROOT/}" >&2
    exit 1
  }
done
grep -q 'UIAlertAction(title: "生物群系…"' "$ROOT/Sources/UI/ChunkListViewController.swift" && \
grep -q 'UIAlertAction(title: "HardcodedSpawners…"' "$ROOT/Sources/UI/ChunkListViewController.swift" || {
  echo 'error: biome or HardcodedSpawners action is missing from the chunk list' >&2
  exit 1
}
grep -q 'func biomeRecord(at position: ChunkPosition)' "$ROOT/Sources/Chunk/BedrockChunkStore.swift" && \
grep -q 'func saveBiomeRecord' "$ROOT/Sources/Chunk/BedrockChunkStore.swift" && \
grep -q 'func hardcodedSpawnersRecord(at position: ChunkPosition)' "$ROOT/Sources/Chunk/BedrockChunkStore.swift" && \
grep -q 'func saveHardcodedSpawnersRecord' "$ROOT/Sources/Chunk/BedrockChunkStore.swift" || {
  echo 'error: chunk biome or HardcodedSpawners persistence APIs are missing' >&2
  exit 1
}

cat > "$TMP/chunk_auxiliary_data_test.swift" <<'SWIFT'
import Foundation

@main
enum ChunkAuxiliaryDataTests {
    static func main() throws {
        let heights = Array(repeating: Int16(0), count: 256)

        var data2DIDs = (0..<256).map { UInt32($0 & 0xff) }
        let data2D = BedrockBiomeDocument(
            format: .data2D,
            heightMap: heights,
            layers: [BedrockBiomeLayer(baseY: nil, biomeIDs: data2DIDs, isAbsent: false)]
        )
        let data2DRoundTrip = try BedrockBiomeDocument.decode(
            recordType: .data2D,
            data: data2D.encoded()
        )
        precondition(data2DRoundTrip == data2D)
        precondition(data2DRoundTrip.biomeID(localX: 1, y: 70, localZ: 1) == 17)
        data2DIDs[17] = 9

        var threeDValues = Array(repeating: UInt32(1), count: 4096)
        threeDValues[0] = 2
        threeDValues[4095] = 255
        var data3D = BedrockBiomeDocument(
            format: .data3D,
            heightMap: heights,
            layers: [
                BedrockBiomeLayer(baseY: -64, biomeIDs: threeDValues, isAbsent: false),
                BedrockBiomeLayer(baseY: -48, biomeIDs: Array(repeating: 0, count: 4096), isAbsent: true)
            ]
        )
        try data3D.updateBiomeID(layerIndex: 1, valueIndex: 15, id: 7)
        let encoded3D = try data3D.encoded()
        let decoded3D = try BedrockBiomeDocument.decode(recordType: .data3D, data: encoded3D)
        precondition(decoded3D == data3D)
        precondition(decoded3D.layers[1].isAbsent == false)
        precondition(decoded3D.layers[1].biomeIDs[15] == 7)
        precondition(decoded3D.biomeID(localX: 0, y: -64, localZ: 0) == 2)
        precondition(decoded3D.biomeID(localX: 15, y: -49, localZ: 15) == 255)

        let hsa = HardcodedSpawnersDocument(areas: [
            HardcodedSpawnerArea(
                minimumX: -16, minimumY: 48, minimumZ: 32,
                maximumX: -1, maximumY: 90, maximumZ: 47,
                kind: .netherFortress
            ),
            HardcodedSpawnerArea(
                minimumX: 0, minimumY: 60, minimumZ: 0,
                maximumX: 15, maximumY: 80, maximumZ: 15,
                kind: .custom(99)
            )
        ])
        let hsaData = try hsa.encoded()
        precondition(hsaData.count == 4 + 25 * 2)
        let decodedHSA = try HardcodedSpawnersDocument.decode(hsaData)
        precondition(decodedHSA == hsa)
        print("Biome and HardcodedSpawners codec tests passed")
    }
}
SWIFT
swiftc \
  "$ROOT/Sources/Support/Errors.swift" \
  "$ROOT/Sources/Support/Hex.swift" \
  "$ROOT/Sources/Support/BedrockDataValueCatalog.swift" \
  "$ROOT/Sources/NBT/BinaryCursor.swift" \
  "$ROOT/Sources/Chunk/BedrockDBKey.swift" \
  "$ROOT/Sources/Chunk/BedrockBiomeData.swift" \
  "$ROOT/Sources/Chunk/HardcodedSpawners.swift" \
  "$TMP/chunk_auxiliary_data_test.swift" \
  -o "$TMP/chunk-auxiliary-data-tests"
"$TMP/chunk-auxiliary-data-tests"

cat > "$TMP/EmptyChunkProfileStubs.swift" <<'SWIFT'
import Foundation

final class MojangLevelDB {
    func entries(prefix: Data? = nil, includeValues: Bool = false, limit: Int = 0) throws -> [(key: Data, value: Data?)] { [] }
}
struct EmptyChunkPaletteState { let paletteVersion: Int32? }
struct SubChunkStorage { let palette: [EmptyChunkPaletteState] }
struct BedrockSubChunk {
    let version: UInt8
    let storages: [SubChunkStorage]
    static func decode(_ data: Data, keyYIndex: Int8? = nil) throws -> BedrockSubChunk {
        BedrockSubChunk(version: data.first ?? 9, storages: [])
    }
}
SWIFT

cat > "$TMP/pure_air_chunk_test.swift" <<'SWIFT'
import Foundation

@main
enum PureAirChunkTests {
    static func main() throws {
        let position = ChunkPosition(x: 4, z: -2, dimension: 0)
        let terrain = Data(repeating: 0x2a, count: 640)
        let profile = BedrockEmptyChunkProfile(
            versionRecordType: .version,
            versionValue: Data([40]),
            blockPaletteVersion: 18_153_728,
            subChunkVersion: 9,
            terrainRecordType: .data3D,
            terrainValue: terrain
        )
        let records = BedrockEmptyChunk.metadataRecords(at: position, profile: profile)
        precondition(records.count == 3)

        let version = records.first(where: { $0.recordType == .version })
        let finalized = records.first(where: { $0.recordType == .finalizedState })
        let data3D = records.first(where: { $0.recordType == .data3D })
        precondition(version?.value == Data([40]))
        precondition(data3D?.value == terrain)
        let finalizedValue = try finalized?.value.littleEndianInt32(at: 0)
        precondition(finalizedValue == 2)

        let parsedVersion = version.flatMap { BedrockDBKey.parse($0.key) }
        let parsedFinalized = finalized.flatMap { BedrockDBKey.parse($0.key) }
        precondition(parsedVersion?.position == position)
        precondition(parsedFinalized?.position == position)
        precondition(parsedVersion?.recordType == .version)
        precondition(parsedFinalized?.recordType == .finalizedState)
        print("Pure-air chunk metadata test passed")
    }
}
SWIFT

swiftc \
  "$ROOT/Sources/Support/Errors.swift" \
  "$ROOT/Sources/Support/Hex.swift" \
  "$ROOT/Sources/Chunk/BedrockDBKey.swift" \
  "$TMP/EmptyChunkProfileStubs.swift" \
  "$ROOT/Sources/Chunk/BedrockEmptyChunk.swift" \
  "$TMP/pure_air_chunk_test.swift" \
  -o "$TMP/pure-air-chunk-tests"
"$TMP/pure-air-chunk-tests"

echo 'Pure-air chunk recreation, biome editing and HardcodedSpawners editing passed'
# v0.11.7: biome map layer, searchable ID/name catalogue and optional
# HardcodedSpawners map overlay.
for required in \
  "$ROOT/Sources/Chunk/BedrockBiomeCatalog.swift" \
  "$ROOT/Sources/UI/BiomeIDPickerViewController.swift"; do
  [[ -f "$required" ]] || {
    echo "error: missing v0.11.7 biome-map source: ${required#$ROOT/}" >&2
    exit 1
  }
done
grep -q 'case biome' "$ROOT/Sources/Chunk/ChunkSurfaceRenderer.swift" && \
grep -q 'case \.biome: return "生物群系"' "$ROOT/Sources/Chunk/ChunkSurfaceRenderer.swift" && \
grep -q 'BedrockBiomeCatalog.color' "$ROOT/Sources/Chunk/ChunkSurfaceRenderer.swift" || {
  echo 'error: biome render mode is not wired into the map renderer' >&2
  exit 1
}
grep -q 'showHardcodedSpawners' "$ROOT/Sources/UI/WorldMapViewController.swift" && \
grep -q 'hardcodedSpawnerLayer' "$ROOT/Sources/UI/WorldMapViewController.swift" && \
grep -q '显示 HardcodedSpawners' "$ROOT/Sources/UI/WorldMapViewController.swift" || {
  echo 'error: HardcodedSpawners map overlay switch is missing' >&2
  exit 1
}
grep -q '搜索数字 ID、名称或 identifier' "$ROOT/Sources/UI/BiomeIDPickerViewController.swift" && \
grep -q 'BiomeIDPickerViewController' "$ROOT/Sources/UI/ChunkBiomeEditorViewController.swift" || {
  echo 'error: searchable biome ID/name picker is missing' >&2
  exit 1
}
CATALOG_ENTRY_COUNT="$(grep -c 'entry(' "$ROOT/Sources/Chunk/BedrockBiomeCatalog.swift")"
if (( CATALOG_ENTRY_COUNT < 60 )); then
  echo "error: biome ID/name catalogue is unexpectedly small: $CATALOG_ENTRY_COUNT" >&2
  exit 1
fi
echo 'Biome map, HardcodedSpawners overlay and ID/name lookup passed'
# v0.11.7: editable village NBT and a shared chunk action menu opened by
# long-pressing the selected map chunk.
for required in \
  "$ROOT/Sources/World/VillageNBTStore.swift" \
  "$ROOT/Sources/UI/VillageNBTListViewController.swift" \
  "$ROOT/Sources/UI/VillageNBTEditorViewController.swift"; do
  [[ -f "$required" ]] || {
    echo "error: missing editable village NBT source: ${required#$ROOT/}" >&2
    exit 1
  }
done
grep -q '村庄 NBT' "$ROOT/Sources/UI/NBTMenuViewController.swift" && \
grep -q 'VillageNBTListViewController' "$ROOT/Sources/UI/NBTMenuViewController.swift" && \
grep -q '所有可解析的 NBT 均支持修改' "$ROOT/Sources/UI/NBTMenuViewController.swift" || {
  echo 'error: village NBT is not wired into the editable NBT menu' >&2
  exit 1
}
grep -q 'static let legacyKey = Data("mVillages".utf8)' "$ROOT/Sources/World/VillageNBTStore.swift" && \
grep -q 'static let modernPrefix = Data("VILLAGE_".utf8)' "$ROOT/Sources/World/VillageNBTStore.swift" && \
grep -q 'ConsecutiveNBTCodec.decode' "$ROOT/Sources/World/VillageNBTStore.swift" && \
grep -q 'database.put(encoded, for: record.key, sync: true)' "$ROOT/Sources/World/VillageNBTStore.swift" || {
  echo 'error: village LevelDB records are not fully decoded and saved' >&2
  exit 1
}
grep -q 'UILongPressGestureRecognizer' "$ROOT/Sources/UI/WorldMapViewController.swift" && \
grep -q 'handleChunkLongPress' "$ROOT/Sources/UI/WorldMapViewController.swift" && \
grep -q 'ChunkActionMenu.present' "$ROOT/Sources/UI/WorldMapViewController.swift" && \
grep -q 'enum ChunkActionMenu' "$ROOT/Sources/UI/ChunkListViewController.swift" && \
grep -q 'func summary(at position' "$ROOT/Sources/Chunk/BedrockChunkStore.swift" || {
  echo 'error: selected map chunks do not expose the shared long-press menu' >&2
  exit 1
}
echo 'Editable village NBT and map long-press chunk menu passed'
# v0.11.7 village/NBT map refinement: all four NBT categories have icons,
# villages are grouped individually, and village/HardcodedSpawners overlays
# support exact long-press editing.
NBT_MENU="$ROOT/Sources/UI/NBTMenuViewController.swift"
VILLAGE_LIST="$ROOT/Sources/UI/VillageNBTListViewController.swift"
VILLAGE_STORE="$ROOT/Sources/World/VillageNBTStore.swift"
MAP_VIEW="$ROOT/Sources/UI/WorldMapViewController.swift"
SPAWNER_EDITOR="$ROOT/Sources/UI/HardcodedSpawnersViewController.swift"

for title in '世界 NBT' '玩家 NBT' '村庄 NBT' '结构 NBT'; do
  grep -q "Item(title: \"$title\"" "$NBT_MENU" || {
    echo "error: NBT menu entry lacks an icon-backed item: $title" >&2
    exit 1
  }
done
grep -q 'menuIcon(systemName: item.icon, fallback: item.fallback)' "$NBT_MENU" && \
grep -q 'UIGraphicsImageRenderer' "$NBT_MENU" || {
  echo 'error: NBT menu does not guarantee icons on iOS 13' >&2
  exit 1
}

grep -q 'Dictionary(grouping: allRecords, by: \\.villageIdentifier)' "$VILLAGE_LIST" && \
grep -q 'override func numberOfSections(in tableView: UITableView) -> Int { shownSections.count }' "$VILLAGE_LIST" || {
  echo 'error: village NBT records are not grouped into table sections' >&2
  exit 1
}
grep -q '不同村庄已分开显示' "$VILLAGE_LIST" || {
  echo 'error: village NBT records are not separated into village sections' >&2
  exit 1
}
grep -q 'documentPath: \[NBTPathComponent\]' "$VILLAGE_STORE" && \
grep -q 'legacyVillageRecords' "$VILLAGE_STORE" && \
grep -q 'NBTTreeMutation.replacingValue' "$VILLAGE_STORE" || {
  echo 'error: split legacy villages cannot be saved back to their nested NBT path' >&2
  exit 1
}

grep -q 'private var showVillages = false' "$MAP_VIEW" && \
grep -q 'VillageNBTStore(session: self.session).mapFeatures()' "$MAP_VIEW" && \
grep -q 'villageBoundsLayer' "$MAP_VIEW" && \
grep -q 'villageCenterLayer' "$MAP_VIEW" && \
grep -q 'villagePOILayer' "$MAP_VIEW" && \
grep -q '绿色虚线框为村庄边界' "$MAP_VIEW" || {
  echo 'error: default-off village boundary/center/POI map layer is incomplete' >&2
  exit 1
}

grep -q 'villagePOILayer.zPosition = 95' "$MAP_VIEW" && \
grep -q 'private func pointOfInterestHit' "$MAP_VIEW" && \
grep -q 'annotation: "兴趣点方块"' "$MAP_VIEW" && \
grep -q 'private func drawVillagePOILinks' "$MAP_VIEW" && \
grep -q 'private func showVillageCenterInformation' "$MAP_VIEW" && \
grep -q '玩家声望：' "$MAP_VIEW" && \
grep -q '村民数目：' "$MAP_VIEW" || {
  echo 'error: village POI priority, villager arrows or center information is incomplete' >&2
  exit 1
}

grep -q 'private func villageHit(atX' "$MAP_VIEW" && \
grep -q 'let controller = VillageNBTListViewController(' "$MAP_VIEW" && \
grep -q 'villageIdentifier: hit.feature.identifier' "$MAP_VIEW" && \
grep -q '信息、兴趣点、居民和声望' "$MAP_VIEW" && \
grep -q 'private func hardcodedSpawnerHit(atX' "$MAP_VIEW" && \
grep -q 'selectedAreaIndex: hit.areaIndex' "$MAP_VIEW" && \
grep -q 'init(session: WorldSession, chunk: ChunkPosition, selectedAreaIndex: Int? = nil)' "$SPAWNER_EDITOR" && \
grep -q 'openInitialAreaIfNeeded' "$SPAWNER_EDITOR" || {
  echo 'error: map long-press does not open all four village records or the exact HardcodedSpawners editor' >&2
  exit 1
}
echo 'NBT icons, per-village grouping and editable village/spawner map overlays passed'
# v0.11.7 village boundary/population/POI-link correction.
grep -q 'coordinateBounds(in root: NBTValue)' "$VILLAGE_STORE" && \
grep -q 'scalar(namedAny: \["X0"\]' "$VILLAGE_STORE" && \
grep -q 'scalar(namedAny: \["Z0"\]' "$VILLAGE_STORE" && \
grep -q 'scalar(namedAny: \["X1"\]' "$VILLAGE_STORE" && \
grep -q 'scalar(namedAny: \["Z1"\]' "$VILLAGE_STORE" || {
  echo 'error: village boundary is not sourced from X0/Z0 -> X1/Z1' >&2
  exit 1
}
grep -q 'inheritedLinkedEntityIDs: \[Int64\]' "$VILLAGE_STORE" && \
grep -q 'inheritedLinkedEntityIDs: linkedIDs' "$VILLAGE_STORE" && \
grep -q 'POI entries keep VillagerID on the parent' "$VILLAGE_STORE" || {
  echo 'error: VillagerID is not propagated into nested POI instances' >&2
  exit 1
}
grep -q 'static func dwellerUniqueIDs(' "$VILLAGE_STORE" && \
grep -q 'scanEntities(uniqueIDs: uniqueIDs)' "$VILLAGE_STORE" && \
grep -q 'name == "id"' "$VILLAGE_STORE" && \
grep -q 'rootIsDwellersRecord: record.kind == .dwellers' "$VILLAGE_STORE" && \
grep -q 'case "villager", "villager_v2": return .villager' "$VILLAGE_STORE" && \
grep -q 'case "cat": return .cat' "$VILLAGE_STORE" && \
grep -q 'case "iron_golem", "irongolem": return .ironGolem' "$VILLAGE_STORE" && \
grep -Fq '村民数目：\(hit.feature.villagerCount)' "$MAP_VIEW" || {
  echo 'error: village residents are not resolved from Dwellers ID against all world entities' >&2
  exit 1
}

grep -q 'private func presentVillageCenterPOIChoice' "$MAP_VIEW" && \
grep -q '村庄中心与兴趣点方块位于同一坐标' "$MAP_VIEW" && \
grep -q 'hit.feature.villagerEntities + hit.feature.ironGolemEntities' "$MAP_VIEW" && \
grep -q 'selectedVillageEntityIDs.contains(hit.object.stableID)' "$MAP_VIEW" || {
  echo 'error: overlapping village-center/POI selection or village resident blinking is missing' >&2
  exit 1
}

RESIDENT_EDITOR="$ROOT/Sources/UI/VillageNBTEditorViewController.swift"
RESIDENT_LIST="$ROOT/Sources/UI/VillageResidentEntitiesViewController.swift"
[[ -f "$RESIDENT_LIST" ]] && \
grep -q '查看该村庄的全部居民实体' "$RESIDENT_EDITOR" && \
grep -Fq '查看全部\(kind.displayName)' "$RESIDENT_EDITOR" && \
grep -q 'residentOptionKinds: \[VillageResidentEntityKind\] = \[.villager, .cat, .ironGolem\]' "$RESIDENT_EDITOR" && \
grep -q 'WorldObjectNBTEditorViewController(' "$RESIDENT_LIST" || {
  echo 'error: village DWELLERS page does not expose villager/cat/iron-golem entity lists' >&2
  exit 1
}
echo 'Village X0/Z0 boundary, Dwellers-based resident resolution, overlap chooser and POI arrows passed'

# v0.11.7 interactive rectangular map-region selection and operations.
REGION_MODEL="$ROOT/Sources/Chunk/BedrockMapRegion.swift"
REGION_STORE="$ROOT/Sources/Chunk/BedrockRegionStore.swift"
REGION_UI="$ROOT/Sources/UI/MapRegionOperationsViewControllers.swift"
SELECTION_UI="$ROOT/Sources/UI/MapSelectionOverlayView.swift"
for required in "$REGION_MODEL" "$REGION_STORE" "$REGION_UI" "$SELECTION_UI"; do
  [[ -f "$required" ]] || {
    echo "error: map-region source is missing: ${required#$ROOT/}" >&2
    exit 1
  }
done
grep -q 'case left, right, top, bottom' "$SELECTION_UI" && \
grep -q 'onCoordinatesChanged' "$SELECTION_UI" && \
grep -q 'actionButton.setTitle("操作…"' "$SELECTION_UI" && \
grep -q 'selectionEdgeDragOrigin' "$MAP_VIEW" && \
grep -q 'presentSelectionActions' "$MAP_VIEW" || {
  echo 'error: draggable four-edge selection or editable coordinate panel is incomplete' >&2
  exit 1
}
for action in \
  '查看区域内实体…' \
  '复制区域内容到等大区域…' \
  '区域内方块搜索替换…' \
  '生物群系修改…' \
  'HardcodedSpawners 修改…' \
  '清空区域…' \
  '重新生成区域…'; do
  grep -qF "$action" "$MAP_VIEW" || {
    echo "error: region action is missing: $action" >&2
    exit 1
  }
done
grep -q 'expandedToChunkBounds' "$REGION_STORE" && \
grep -q 'func clearRegion' "$REGION_STORE" && \
grep -q 'func regenerateRegion' "$REGION_STORE" && \
grep -q 'func copyRegion' "$REGION_STORE" && \
grep -q 'func setBiomeID' "$REGION_STORE" && \
grep -q 'func replaceBlocks' "$REGION_STORE" || {
  echo 'error: one or more rectangular region operations are missing' >&2
  exit 1
}
echo 'Interactive map-region selection, editing, copy, biome, spawner, clear and regeneration passed'

# v0.11.7 improved region gestures, region bulk replacement, dedicated chunk tab, and world-wide entity filters.
ENTITY_BROWSER="$ROOT/Sources/UI/EntityBrowserViewController.swift"
ENTITY_SCANNER="$ROOT/Sources/Entity/BedrockWorldObjectScanner.swift"
TAB_CONTROLLER="$ROOT/Sources/UI/WorldDetailTabBarController.swift"
BULK_UI="$ROOT/Sources/UI/BulkLayerReplaceViewController.swift"
SUBCHUNK_EDITOR="$ROOT/Sources/Chunk/BedrockSubChunkEditor.swift"
for required in "$ENTITY_BROWSER" "$ENTITY_SCANNER" "$TAB_CONTROLLER" "$BULK_UI" "$SUBCHUNK_EDITOR"; do
  [[ -f "$required" ]] || {
    echo "error: improved selection/entity source is missing: ${required#$ROOT/}" >&2
    exit 1
  }
done

grep -q 'final class MapSelectionEdgeHandleView' "$SELECTION_UI" && \
grep -q 'setBackgroundPassThrough' "$SELECTION_UI" && \
grep -q 'selectionMapPanGesture' "$MAP_VIEW" && \
grep -q 'selectionMapPinchGesture' "$MAP_VIEW" && \
grep -q 'selection-mode-blink' "$MAP_VIEW" && \
grep -q 'guard isSelectionMode, selectedRegion == nil' "$MAP_VIEW" || {
  echo 'error: improved edge hit targets, map pan/zoom, blinking selection button or reselection guard is missing' >&2
  exit 1
}

grep -q 'func bulkReplaceLayer(' "$REGION_STORE" && \
grep -q 'localXRange: ClosedRange<Int>' "$SUBCHUNK_EDITOR" && \
grep -q 'init(session: WorldSession, region:' "$BULK_UI" && \
grep -q '框选区域批量层0层1替换' "$ROOT/Sources/UI/ChunkListViewController.swift" || {
  echo 'error: region-scoped bulk layer replacement is incomplete' >&2
  exit 1
}

grep -q 'ChunkListViewController(session: session, initialDimension: 0)' "$TAB_CONTROLLER" && \
grep -q 'viewControllers = \[map, entities, chunks, nbt, commands, tools\]' "$TAB_CONTROLLER" && \
grep -q 'tabBarItem = UITabBarItem(title: "区块"' "$ROOT/Sources/UI/ChunkListViewController.swift" || {
  echo 'error: the dedicated chunk tab is missing or ordered incorrectly' >&2
  exit 1
}

grep -q '\["全部"\] + BedrockDimension.allCases' "$ENTITY_BROWSER" && \
grep -q 'rangeModeControl' "$ENTITY_BROWSER" && \
grep -q 'rectangleYSwitch' "$ENTITY_BROWSER" && \
grep -q 'radiusYSwitch' "$ENTITY_BROWSER" && \
grep -q 'scanner.scanAll' "$ENTITY_BROWSER" && \
grep -q 'func scanAll(' "$ENTITY_SCANNER" && \
! grep -q 'radiusControl' "$ENTITY_BROWSER" || {
  echo 'error: world-wide entity browser or box/radius optional-Y filters are incomplete' >&2
  exit 1
}

echo 'Improved selection gestures, region bulk replacement, chunk tab and world-wide entity range filters passed'
echo 'Unified NBT mutation, editable block layers, chunk management and com.wzn bundle identity passed'

TICKING_STORE="$ROOT/Sources/World/TickingAreaStore.swift"
TICKING_UI="$ROOT/Sources/UI/TickingAreaViewControllers.swift"
CHUNK_UI="$ROOT/Sources/UI/ChunkListViewController.swift"

grep -q 'databaseKeyPrefix = Data("tickingarea_".utf8)' "$TICKING_STORE" && \
grep -q 'BedrockNBTCodec.encode(source.document' "$TICKING_STORE" && \
grep -q 'database.applyBatch(puts: puts, deletes: deletes' "$TICKING_STORE" && \
grep -q 'records(migratingLegacy: true)' "$TICKING_UI" && \
grep -q 'TickingAreaSelectionContext(region: region)' "$MAP_VIEW" && \
grep -q '常加载区域编辑…' "$CHUNK_UI" && \
! grep -q 'ConsecutiveNBTCodec.encode(updated)' "$TICKING_STORE" || {
  echo 'error: native per-key tickingarea storage, legacy migration or contextual editors are incomplete' >&2
  exit 1
}

echo 'Native tickingarea_ storage, legacy migration and map/chunk contextual editing passed'


# Circular tickingarea bounds are persisted in blocks, but the command/editor
# radius is measured in chunks. NBT batch paste must keep all copied items and
# only ask how to resolve actual Compound name conflicts.
TICKING_STORE="$ROOT/Sources/World/TickingAreaStore.swift"
TICKING_UI="$ROOT/Sources/UI/TickingAreaViewControllers.swift"
NBT_EDITING_UI="$ROOT/Sources/UI/NBTEditingUI.swift"
NBT_NODE="$ROOT/Sources/UI/NBTNode.swift"
grep -q 'chunkDistance(fromBlockDistance: halfExtent)' "$TICKING_STORE" && grep -q 'blockDistance(fromChunkDistance: radiusChunks)' "$TICKING_UI" && grep -q 'centerBlockX' "$TICKING_STORE" && grep -q '半径（区块）' "$TICKING_UI" && grep -q 'title: "存在同名标签"' "$NBT_EDITING_UI" && grep -q 'title: "保留"' "$NBT_EDITING_UI" && grep -q 'title: "覆盖"' "$NBT_EDITING_UI" && ! grep -q '可修改粘贴后的标签名称' "$NBT_EDITING_UI" && grep -q 'replacingExisting: Bool = false' "$NBT_NODE" || {
  echo 'error: tickingarea radius conversion or batch NBT conflict paste is incomplete' >&2
  exit 1
}
echo 'Tickingarea chunk-radius conversion and batch NBT conflict paste passed'

# v1.1.5: both pasteboard representations must be written atomically into one
# item, and every NBT creation surface must offer nbt/mcstructure/json import.
NBT_CLIPBOARD_CODEC="$ROOT/Sources/NBT/NBTClipboardCodec.swift"
NBT_EDITING_UI="$ROOT/Sources/UI/NBTEditingUI.swift"
STANDALONE_LIST="$ROOT/Sources/UI/StandaloneNBTFileViewController.swift"
METADATA_UI="$ROOT/Sources/UI/MetadataNBTViewControllers.swift"

grep -q 'UIPasteboard.general.setItems' "$NBT_EDITING_UI" && \
grep -q 'batchTagPasteboardType: batch' "$NBT_EDITING_UI" && \
grep -q 'tagPasteboardType: encoded\[0\]' "$NBT_EDITING_UI" && \
! grep -q 'setData(batch, forPasteboardType: batchTagPasteboardType)' "$NBT_EDITING_UI" && \
grep -q 'NBTClipboardCodec.encodeBatch(documents)' "$NBT_EDITING_UI" && \
grep -q 'NBTClipboardCodec.decodeBatch(batch)' "$NBT_EDITING_UI" && \
grep -q 'static func encodeBatch' "$NBT_CLIPBOARD_CODEC" && \
grep -q 'static func decodeBatch' "$NBT_CLIPBOARD_CODEC" || {
  echo 'error: atomic multi-tag pasteboard payload or clipboard codec is incomplete' >&2
  exit 1
}

grep -q '导入 NBT／mcstructure／JSON…' "$NBT_EDITING_UI" && \
grep -q 'StandaloneNBTFileCodec.decode' "$NBT_EDITING_UI" && \
grep -q 'ext == "nbt" || ext == "mcstructure" || ext == "json"' "$NBT_EDITING_UI" && \
grep -q 'completion: @escaping (\[NBTDocument\]) -> Void' "$NBT_EDITING_UI" && \
grep -q 'append(contentsOf: documents)' "$STANDALONE_LIST" && \
grep -q 'documents.map' "$METADATA_UI" || {
  echo 'error: NBT/mcstructure/json tag and root import integration is incomplete' >&2
  exit 1
}

echo 'Atomic multi-tag clipboard and NBT/mcstructure/json tag import passed'


# v1.1.6: canonical actor digests and numeric block ID correspondence.
grep -q 'if dimension != 0 { key.appendLE(dimension) }' "$ROOT/Sources/Entity/BedrockWorldObjectNBTStore.swift" || {
  echo 'error: overworld actor digest still appends DimensionID 0' >&2
  exit 1
}
grep -q 'repairAppCreatedOverworldActorDigests' "$ROOT/Sources/Entity/BedrockWorldObjectNBTStore.swift" || {
  echo 'error: invalid overworld actor digest migration is missing' >&2
  exit 1
}
grep -q '未被 digp 引用的孤立 actorprefix' "$ROOT/Sources/Entity/BedrockWorldObjectScanner.swift" || {
  echo 'error: orphan actorprefix records are still shown as live entities' >&2
  exit 1
}
grep -q 'enum BedrockLegacyBlockCatalog' "$ROOT/Sources/Support/BedrockLegacyBlockCatalog.swift" || {
  echo 'error: legacy numeric block ID catalog is missing' >&2
  exit 1
}
grep -q '("方块ID", "旧版数字 ID、字符串 ID 与十六进制值")' "$ROOT/Sources/UI/WorldToolsViewController.swift" || {
  echo 'error: block data-value list is not connected' >&2
  exit 1
}
grep -q 'BedrockDataValueEntry(id: 5, identifier: "minecraft:planks"' "$ROOT/Sources/Support/BedrockLegacyBlockCatalog.swift" || {
  echo 'error: legacy numeric block IDs are not paired with their legacy string IDs' >&2
  exit 1
}
echo 'Canonical actor digest repair, orphan filtering and numeric block ID correspondence passed'


# v1.1.7: entity creation follows the world's actual storage generation,
# legacy block NBT can rewrite numeric ID/data, and block-coordinate rendering
# keeps the exact selected block at the viewport center.
ENTITY_STORE="$ROOT/Sources/Entity/BedrockWorldObjectNBTStore.swift"
ENTITY_CREATE_UI="$ROOT/Sources/UI/WorldObjectCreationViewController.swift"
BLOCK_DETAIL_UI="$ROOT/Sources/UI/MapBlockDetailPanelView.swift"
SUBCHUNK_EDITOR="$ROOT/Sources/Chunk/BedrockSubChunkEditor.swift"
MAP_VIEW="$ROOT/Sources/UI/WorldMapViewController.swift"

grep -q 'enum EntityCreationStorageMode' "$ENTITY_STORE" && \
grep -q 'preferredEntityCreationStorage' "$ENTITY_STORE" && \
grep -q 'updateEntityIdentity' "$ENTITY_STORE" && \
grep -q 'case \.legacyChunkEntity' "$ENTITY_STORE" && \
grep -q 'recordType: \.entity' "$ENTITY_STORE" && \
grep -q '自动识别世界的实体存储格式' "$ENTITY_CREATE_UI" || {
  echo 'error: legacy/modern entity creation storage auto-detection is incomplete' >&2
  exit 1
}

grep -q 'NBTNamedTag(name: "legacy_id"' "$BLOCK_DETAIL_UI" && \
grep -q 'NBTNamedTag(name: "legacy_data"' "$BLOCK_DETAIL_UI" && \
grep -q 'legacyBlockState(from:' "$SUBCHUNK_EDITOR" && \
grep -q 'encodeLegacyPersistent' "$SUBCHUNK_EDITOR" || {
  echo 'error: legacy numeric block NBT editing or persistence is incomplete' >&2
  exit 1
}

grep -q 'blockX: Double(inputX) + 0.5' "$MAP_VIEW" && \
grep -q 'blockZ: Double(inputZ) + 0.5' "$MAP_VIEW" || {
  echo 'error: block-coordinate rendering still snaps to the chunk center' >&2
  exit 1
}

echo 'World-aware entity storage, legacy numeric block NBT editing and exact block viewport centering passed'

# v1.1.11: local-player map center, integrated terminal input and entity selectors.
for required in \
  "$ROOT/Sources/Command/WorldCommand.swift" \
  "$ROOT/Sources/Command/WorldCommandExecutor.swift" \
  "$ROOT/Sources/UI/WorldCommandViewController.swift"; do
  [[ -f "$required" ]] || { echo "error: command source is missing: ${required#$ROOT/}" >&2; exit 1; }
done
COMMAND_PARSER="$ROOT/Sources/Command/WorldCommand.swift"
COMMAND_EXECUTOR="$ROOT/Sources/Command/WorldCommandExecutor.swift"
COMMAND_UI="$ROOT/Sources/UI/WorldCommandViewController.swift"
TAB_CONTROLLER="$ROOT/Sources/UI/WorldDetailTabBarController.swift"
PLAYER_STORE="$ROOT/Sources/World/PlayerNBTStore.swift"
for expected in \
  'case "help"' \
  'case "clear"' \
  'case "clearspawnpoint"' \
  'case "clone"' \
  'case "effect"' \
  'case "fill"' \
  'case "give"' \
  'case "kill"' \
  'case "kick"' \
  'case "summon"' \
  'case "@s": return .localPlayer' \
  'case "@a": return .allPlayers' \
  'case "@e": return .allEntities' \
  'guard arguments.count == 1 else' \
  'guard arguments.count == 4 else' \
  'guard arguments.count == 2 else' \
  'guard arguments.count == 11 else' \
  'parseDimension(arguments[0])' \
  'if text == "NULL"' \
  'case "ByteArray": return .byteArray' \
  'case "List": return .list' \
  'case "Compound": return .compound' \
  'case "IntArray": return .intArray' \
  'case "LongArray": return .longArray'; do
  grep -qF "$expected" "$COMMAND_PARSER" || {
    echo "error: strict command parser/selector support is missing: $expected" >&2
    exit 1
  }
done
for expected in \
  'snapshotSubChunks(in: source)' \
  'state(layer: 0, at: sourceCoordinate, snapshot: sourceSnapshot)' \
  'ensureGenerated(sourceStore.chunks(in: source))' \
  'ensureGenerated(chunks(in: targetRegion))' \
  'sourceDimension: Int32' \
  'targetDimension: Int32' \
  'layer: 1' \
  'removeBlockEntities(in:' \
  'clearItems(target:' \
  'clearSpawnPoints(target:' \
  'effect(operation:' \
  'CommandEffectNBT.applying' \
  'give(target:' \
  'kill(target:' \
  'kick(target:' \
  'summon(identifier:' \
  'tradeContainerNames' \
  'settingHealthCurrentToZero' \
  'deleteOnlinePlayerData(records:'; do
  grep -qF "$expected" "$COMMAND_EXECUTOR" || {
    echo "error: command execution behavior is missing: $expected" >&2
    exit 1
  }
done
grep -qF 'func localPlayerPosition()' "$PLAYER_STORE" && \
grep -qF 'deleteOnlinePlayerData(records' "$PLAYER_STORE" && \
grep -qF 'PlayerNBTStore(session: session).localPlayerPosition()' "$MAP_VIEW" && \
grep -qF 'local.dimension == dimension' "$MAP_VIEW" && \
grep -qF 'blockX: 0.5' "$MAP_VIEW" && \
grep -qF 'blockZ: 0.5' "$MAP_VIEW" && \
grep -qF 'renderDefaultCenter(' "$MAP_VIEW" || {
  echo 'error: per-dimension player/origin map centering or online-player deletion is incomplete' >&2
  exit 1
}
grep -qF 'WorldCommandViewController(session: session)' "$TAB_CONTROLLER" && \
grep -qF 'viewControllers = [map, entities, chunks, nbt, commands, tools]' "$TAB_CONTROLLER" && \
grep -qF 'UITabBarItem(title: "命令"' "$COMMAND_UI" && \
grep -qF 'terminalContainer.addSubview(outputView)' "$COMMAND_UI" && \
grep -qF 'terminalContainer.addSubview(inputContainer)' "$COMMAND_UI" && \
grep -qF 'visibleTerminalInput' "$COMMAND_UI" && \
grep -qF '\u{00A0}' "$COMMAND_UI" && \
grep -qF 'startCursorBlinking()' "$COMMAND_UI" && \
grep -qF 'self.session.notifyAfterDatabaseMutation()' "$COMMAND_UI" && \
grep -qF 'guard Thread.isMainThread' "$ROOT/Sources/World/WorldSession.swift" || {
  echo 'error: integrated terminal UI, visible spaces, cursor or main-thread invalidation is incomplete' >&2
  exit 1
}
if grep -qF 'dimensionControl' "$COMMAND_UI"; then
  echo 'error: command tab still contains the removed dimension selector' >&2
  exit 1
fi
if grep -qF 'session.invalidateAfterExternalChange()' "$COMMAND_EXECUTOR"; then
  echo 'error: command executor must not notify UIKit observers from its worker queue' >&2
  exit 1
fi
echo 'Local-player map center, integrated terminal, target selectors and Y-safe clone passed'

# v1.1.13: common entity NBT, consecutive entity import/export, summon,
# generated-air fallback for unloaded chunks, Y=0 map taps and safe object refresh.
ENTITY_COMMON="$ROOT/Sources/Entity/BedrockEntityCommonNBT.swift"
ENTITY_IMPORT_UI="$ROOT/Sources/UI/EntityNBTImportReviewViewController.swift"
ENTITY_CREATE_UI="$ROOT/Sources/UI/WorldObjectCreationViewController.swift"
ENTITY_BROWSER_UI="$ROOT/Sources/UI/EntityBrowserViewController.swift"
BLOCK_STORE="$ROOT/Sources/Chunk/BedrockSubChunkEditor.swift"
for required in "$ENTITY_COMMON" "$ENTITY_IMPORT_UI"; do
  [[ -f "$required" ]] || { echo "error: v1.1.13 source missing: ${required#$ROOT/}" >&2; exit 1; }
done
for tag in '"Air"' '"Motion"' '"Rotation"' '"IsEating"' '"Tags"' '"PortalCooldown"' '"Persistent"'; do
  grep -qF "$tag" "$ENTITY_COMMON" || { echo "error: common entity NBT tag missing: $tag" >&2; exit 1; }
done
grep -qF 'NBTJSONCodec.decodeEntityDocuments' "$ENTITY_CREATE_UI" && \
grep -qF 'EntityNBTImportReviewViewController' "$ENTITY_CREATE_UI" && \
grep -qF 'StandaloneNBTEditorViewController' "$ENTITY_IMPORT_UI" && \
grep -qF 'createEntity(from:' "$ENTITY_IMPORT_UI" || {
  echo 'error: entity NBT/JSON review and import flow is incomplete' >&2
  exit 1
}
grep -qF '导出实体 NBT' "$ENTITY_BROWSER_UI" && \
grep -qF 'objectStore.document(for:' "$ENTITY_BROWSER_UI" && \
grep -qF 'presentEntityFormatChooser' "$ENTITY_BROWSER_UI" || {
  echo 'error: selected-entity format export is incomplete' >&2
  exit 1
}
grep -qF 'BedrockEmptyChunk.metadataRecords(at: position, profile: profile)' "$BLOCK_STORE" && \
grep -qF 'let allPuts = metadataPuts + upgradedSubChunkPuts + [(key: key, value: encoded)]' "$BLOCK_STORE" && \
grep -qF 'ensureGenerated(sourceStore.chunks(in: source))' "$COMMAND_EXECUTOR" && \
grep -qF 'ensureGenerated(chunks(in: targetRegion))' "$COMMAND_EXECUTOR" || {
  echo 'error: unloaded-chunk air generation is incomplete' >&2
  exit 1
}
grep -qF ': 0' "$MAP_VIEW" && grep -qF 'lastBlockHeights[index] != Int16.min' "$MAP_VIEW" || {
  echo 'error: map tap without rendered Y does not default to Y=0' >&2
  exit 1
}
grep -qF 'inputContainer.topAnchor.constraint(equalTo: terminalContainer.topAnchor)' "$COMMAND_UI" && \
grep -qF 'outputView.topAnchor.constraint(equalTo: inputContainer.bottomAnchor)' "$COMMAND_UI" && \
grep -qF 'notifyAfterDatabaseMutation()' "$ROOT/Sources/World/WorldSession.swift" || {
  echo 'error: top terminal cursor or safe command refresh is incomplete' >&2
  exit 1
}
grep -qF 'isEmptyInventorySlot' "$COMMAND_EXECUTOR" && \
grep -qF 'wasPickedUp: 1' "$COMMAND_EXECUTOR" && \
grep -qF 'case .summon' "$COMMAND_EXECUTOR" && \
grep -qF 'BedrockEntityCommonNBT.mergingTopLevel' "$COMMAND_EXECUTOR" || {
  echo 'error: first-empty-slot give or summon implementation is incomplete' >&2
  exit 1
}
grep -qF 'color: .systemGreen' "$COMMAND_UI" && \
grep -qF 'delete(objects: targets.entities)' "$COMMAND_EXECUTOR" && \
grep -qF 'terrainRecordType' "$ROOT/Sources/Chunk/BedrockEmptyChunk.swift" && \
grep -qF 'summon minecraft:pig overworld 0 64 0 default' "$ROOT/Sources/Command/WorldCommand.swift" || {
  echo 'error: v1.1.14 command color, bulk kill, complete chunk metadata or summon default is incomplete' >&2
  exit 1
}
for removed in '"LinksTag"' '"FireImmune"' '"HasCollision"' '"HasGravity"' '"HasOwner"' '"Age"'; do
  if grep -qF "$removed" "$ENTITY_COMMON"; then
    echo "error: removed common entity tag still exists: $removed" >&2
    exit 1
  fi
done
echo 'Common entity NBT, entity import/export, summon, generated chunks and safe command refresh passed'

# v1.1.15: recursive command NBT, give item tags and legacy chunk modernization.
LEGACY_UPGRADE="$ROOT/Sources/Chunk/BedrockLegacyChunkUpgrade.swift"
[[ -f "$LEGACY_UPGRADE" ]] || { echo 'error: legacy chunk upgrade source is missing' >&2; exit 1; }
for expected in \
  'case "ByteArray": return .byteArray' \
  'case "List": return .list' \
  'case "Compound": return .compound' \
  'case "IntArray": return .intArray' \
  'case "LongArray": return .longArray' \
  'private indirect enum CommandNBTTypeDescriptor' \
  'guard arguments.count == 5 else' \
  'slot: try parseGiveSlot(arguments[1])' \
  'itemTags: try parseStates(arguments[4])'; do
  grep -qF "$expected" "$COMMAND_PARSER" || {
    echo "error: recursive command NBT or Slot-aware give is incomplete: $expected" >&2
    exit 1
  }
done
for expected in \
  'BedrockLegacyChunkUpgrade.plan' \
  'pendingMetadataDeletes.formUnion' \
  'pendingMetadataPuts' \
  'itemTags: [NBTNamedTag]' \
  'replaceItemTag(named: "Name"' \
  'replaceItemTag(named: "Count"'; do
  grep -qF "$expected" "$COMMAND_EXECUTOR" || {
    echo "error: command legacy upgrade or give item-tag merge is incomplete: $expected" >&2
    exit 1
  }
done
for expected in \
  'func upgradedToModern(paletteVersion:' \
  'expandedToData3D' \
  'recordType: .data3D' \
  'recordType: .legacyVersion' \
  'recordType: .data2D'; do
  grep -qF "$expected" "$LEGACY_UPGRADE" || {
    echo "error: legacy SubChunk metadata migration is incomplete: $expected" >&2
    exit 1
  }
done
grep -qF 'existing.isLegacyNumeric && initiallyRequested.nbt != nil' "$BLOCK_STORE" && \
grep -qF 'upgradedSubChunkPuts' "$BLOCK_STORE" || {
  echo 'error: block NBT does not trigger whole-chunk legacy upgrade' >&2
  exit 1
}
if grep -qF 'NSRegularExpression(pattern: pattern)' "$COMMAND_PARSER"; then
  echo 'error: command NBT parser still depends on the old flat regular expression' >&2
  exit 1
fi
echo 'Recursive command NBT, give item tags and legacy chunk modernization passed'
grep -qF 'case "add"' "$COMMAND_PARSER" && \
grep -qF 'case "addlevel"' "$COMMAND_PARSER" && \
grep -qF 'case "level"' "$COMMAND_PARSER" && \
grep -qF 'value: try parseExperienceLevel(arguments[2])' "$COMMAND_PARSER" && \
grep -qF '经验总数=%lld 经验等级=%d 当前经验条进度=%.3f' "$COMMAND_EXECUTOR" && \
grep -qF 'case .level(_, let value)' "$COMMAND_EXECUTOR" && \
grep -qF 'progress: 0' "$COMMAND_EXECUTOR" || {
  echo 'error: renamed experience operations, direct level or query equals output is incomplete' >&2
  exit 1
}
for command_name in help clear clearspawnpoint clone daylock effect experience fill give kill kick setblock setworldspawn spawnpoint spread structure summon teleport tickingarea time weather; do
  python3 - "$COMMAND_PARSER" "$command_name" <<'PY_CHECK' || exit 1
import re, sys
text=open(sys.argv[1],encoding='utf-8').read()
name=re.escape(sys.argv[2])
match=re.search(r'^\s*"'+name+r'":\s*"((?:[^"\\]|\\.)*)",?$', text, re.M)
if not match or '示例：' not in match.group(1):
    print('error: command help is missing an example:', sys.argv[2], file=sys.stderr)
    raise SystemExit(1)
PY_CHECK
done
grep -qF 'return 5' "$ROOT/Sources/UI/WorldListViewController.swift" && \
grep -qF '("方块ID", "旧版数字 ID、字符串 ID 与十六进制值")' "$ROOT/Sources/UI/WorldListViewController.swift" && \
grep -qF 'entries: BedrockLegacyBlockCatalog.blocks' "$ROOT/Sources/UI/WorldListViewController.swift" || {
  echo 'error: home-page Bedrock block-ID entry is incomplete' >&2
  exit 1
}
grep -qF 'placingChestItem(' "$COMMAND_EXECUTOR" && \
grep -qF 'requestedSlot: Int8?' "$COMMAND_EXECUTOR" && \
grep -qF 'exceededChestSlots' "$COMMAND_EXECUTOR" && \
grep -qF 'hasWritableMainhandTag(' "$COMMAND_EXECUTOR" && \
! grep -qF 'createIfMissing' "$COMMAND_EXECUTOR" && \
! grep -qF 'tags.append(NBTNamedTag(name: "Mainhand"' "$COMMAND_EXECUTOR" || {
  echo 'error: Slot-aware give must require an existing entity Mainhand and must never create it' >&2
  exit 1
}


# Fixed v1.0.0: world/structure/tickingarea plus teleport, spread, daylock,
# time and weather commands.
grep -qF 'case setBlock(' "$COMMAND_PARSER" && grep -qF 'case setWorldSpawn(' "$COMMAND_PARSER" && grep -qF 'case spawnPoint(' "$COMMAND_PARSER" && grep -qF 'case teleport(target:' "$COMMAND_PARSER" && grep -qF 'case spread(target:' "$COMMAND_PARSER" && grep -qF 'case dayLock(locked:' "$COMMAND_PARSER" && grep -qF 'case experience(operation:' "$COMMAND_PARSER" && grep -qF 'case weather(settings:' "$COMMAND_PARSER" && grep -qF 'case structure(operation:' "$COMMAND_PARSER" && grep -qF 'case tickingArea(operation:' "$COMMAND_PARSER" && grep -qF 'guard arguments.count == 8 else { throw usageError(command) }' "$COMMAND_PARSER" && grep -qF 'automaticTeleportY' "$COMMAND_EXECUTOR" && grep -qF 'randomSpreadDestination' "$COMMAND_EXECUTOR" && grep -qF 'setTopLevelTag(name: "dodaylightcycle"' "$COMMAND_EXECUTOR" && grep -qF 'case time(operation: CommandTimeOperation)' "$COMMAND_PARSER" && grep -qF 'executeTime(operation)' "$COMMAND_EXECUTOR" && grep -qF 'executeExperience(operation)' "$COMMAND_EXECUTOR" && grep -qF 'WeatherStore(session: session).save(settings)' "$COMMAND_EXECUTOR" && grep -qF 'static func makeStructureDocument(' "$COMMAND_EXECUTOR" && grep -qF 'static func loadStructure(' "$COMMAND_EXECUTOR" && grep -qF 'func save(document: NBTDocument, named name: String, overwrite: Bool = true)' "$ROOT/Sources/World/StructureNBTStore.swift" && grep -qF 'records.removeAll { $0.area.name.caseInsensitiveCompare(area.name) == .orderedSame }' "$COMMAND_EXECUTOR" || {
  echo 'error: world/structure/tickingarea/teleport/spread/daylock/time/weather command support is incomplete' >&2
  exit 1
}
echo 'World spawn, setblock, structure, tickingarea, teleport, spread, daylock, time, experience and weather command support passed'

# v1.1.18: effect command with status-effect IDs and complete ActiveEffects NBT.
grep -qF 'case effect(operation: CommandEffectOperation' "$COMMAND_PARSER" && grep -qF 'case "effect"' "$COMMAND_PARSER" && grep -qF 'effect give @a strength 12000 50' "$COMMAND_PARSER" && grep -qF 'effect clear @e ALL' "$COMMAND_PARSER" && grep -qF 'NBTNamedTag(name: "DurationEasy"' "$COMMAND_PARSER" && grep -qF 'NBTNamedTag(name: "DurationNormal"' "$COMMAND_PARSER" && grep -qF 'NBTNamedTag(name: "DurationHard"' "$COMMAND_PARSER" && ! grep -qF 'FactorCalculationData' "$COMMAND_PARSER" && grep -qF 'encodedUnmovedEntityReplacements' "$COMMAND_EXECUTOR" && grep -qF 'session.database().applyBatch(puts: allPuts' "$COMMAND_EXECUTOR" || {
  echo 'error: effect command parser, NBT schema or atomic target update is incomplete' >&2
  exit 1
}
echo 'Status-effect give/clear/ALL command support passed'


cat > "$TMP/EffectCommandStubs.swift" <<'SWIFT'
import Foundation
struct ImportedWorld { let id: UUID }
final class MojangLevelDB {
    var values: [Data: Data] = [:]
    init() {}
    convenience init(path: URL, readOnly: Bool) throws { self.init() }
    func get(_ key: Data) throws -> Data? { values[key] }
    func put(_ value: Data, for key: Data, sync: Bool = true) throws { values[key] = value }
    func delete(_ key: Data, sync: Bool = true) throws { values.removeValue(forKey: key) }
    func applyBatch(puts: [(key: Data, value: Data)], deletes: [Data], sync: Bool = true) throws {
        for key in deletes { values.removeValue(forKey: key) }
        for item in puts { values[item.key] = item.value }
    }
    func entries(prefix: Data? = nil, includeValues: Bool = false, limit: Int = 0) throws -> [(key: Data, value: Data?)] {
        let keys = values.keys.filter { prefix == nil || $0.starts(with: prefix!) }
        return keys.map { ($0, includeValues ? values[$0] : nil) }
    }
}
enum AtomicFile {
    static func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }
}
enum BTCompressionBridge {
    static func inflateWrapped(_ data: Data, expectedSize: UInt) throws -> Data {
        throw MCBEEditorError.unsupported("portable test does not inflate compressed NBT")
    }
}
final class WorldSession {
    let world = ImportedWorld(id: UUID())
    let db = MojangLevelDB()
    let document: WorldDocument
    init() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("bt-command-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        document = WorldDocument(rootURL: root)
        let initial = LevelDatFile(
            version: 10,
            document: NBTDocument(rootName: "", root: .compound([
                NBTNamedTag(name: "SpawnX", value: .int(0)),
                NBTNamedTag(name: "SpawnY", value: .int(64)),
                NBTNamedTag(name: "SpawnZ", value: .int(0)),
                NBTNamedTag(name: "Time", value: .long(12_013_000))
            ]))
        )
        try? document.writeLevelDat(initial)
    }
    func database() throws -> MojangLevelDB { db }
}
final class WorldStore {
    static let shared = WorldStore()
    func metadataURL(for world: ImportedWorld) -> URL { FileManager.default.temporaryDirectory }
}
struct BedrockBlockRecord {
    static let editableLayerCount = 2
    let x: Int64
    let y: Int32
    let z: Int64
    let dimension: Int32
    let layers: [BedrockBlockState]
    let isGenerated: Bool
}
struct BedrockBlockColumnResult {
    let blocks: [BedrockBlockRecord]
    let diagnostics: [String]
}
final class ChunkSurfaceRenderer {
    init(database: MojangLevelDB) {}
    func blockColumn(blockX: Int64, blockZ: Int64, dimension: Int32) throws -> BedrockBlockColumnResult {
        if blockX == 999 && blockZ == 999 {
            return BedrockBlockColumnResult(blocks: [], diagnostics: ["测试空列"])
        }
        let stone = BedrockBlockState(
            nbt: .compound([
                NBTNamedTag(name: "name", value: .string("minecraft:stone")),
                NBTNamedTag(name: "states", value: .compound([])),
                NBTNamedTag(name: "version", value: .int(BedrockBlockState.defaultPaletteVersion))
            ]),
            legacyID: nil,
            legacyData: nil
        )
        if dimension == 1 {
            return BedrockBlockColumnResult(
                blocks: [
                    BedrockBlockRecord(x: blockX, y: 127, z: blockZ, dimension: dimension, layers: [stone], isGenerated: true),
                    BedrockBlockRecord(x: blockX, y: 126, z: blockZ, dimension: dimension, layers: [], isGenerated: true),
                    BedrockBlockRecord(x: blockX, y: 60, z: blockZ, dimension: dimension, layers: [stone], isGenerated: true)
                ],
                diagnostics: []
            )
        }
        return BedrockBlockColumnResult(
            blocks: [BedrockBlockRecord(
                x: blockX, y: 70, z: blockZ, dimension: dimension,
                layers: [stone], isGenerated: true
            )],
            diagnostics: []
        )
    }
}
SWIFT

cat > "$TMP/effect_command_test.swift" <<'SWIFT'
import Foundation
@main
struct EffectCommandTest {
    static func emptyItem(_ slot: Int8) -> NBTValue {
        .compound([
            NBTNamedTag(name: "Name", value: .string("")),
            NBTNamedTag(name: "Count", value: .byte(0)),
            NBTNamedTag(name: "Slot", value: .byte(slot))
        ])
    }
    static func entity(_ identifier: String, _ uniqueID: Int64, _ x: Float, definitionsOnly: Bool = false) -> NBTDocument {
        var tags = [
            NBTNamedTag(name: "definitions", value: .list(.string, [.string("+\(identifier)")])),
            NBTNamedTag(name: "UniqueID", value: .long(uniqueID)),
            NBTNamedTag(name: "DimensionId", value: .int(0)),
            NBTNamedTag(name: "Pos", value: .list(.float, [.float(x), .float(64), .float(1)]))
        ]
        if !definitionsOnly {
            tags.insert(NBTNamedTag(name: "identifier", value: .string(identifier)), at: 0)
        }
        if uniqueID == 2 {
            tags.append(NBTNamedTag(name: "ChestItems", value: .list(.compound, [emptyItem(0), emptyItem(1), emptyItem(2)])))
            tags.append(NBTNamedTag(name: "Mainhand", value: .list(.compound, [emptyItem(0)])))
        } else if uniqueID == 4 {
            tags.append(NBTNamedTag(name: "ChestItems", value: .list(.compound, [emptyItem(0), emptyItem(1)])))
        }
        return NBTDocument(rootName: "", root: .compound(tags))
    }
    static func effectCount(_ root: NBTValue) -> Int? {
        guard case .list(.compound, let values)? = root.compoundValue(named: "ActiveEffects") else { return nil }
        return values.count
    }
    static func itemName(in root: NBTValue, container: String, slot: Int64? = nil) -> String? {
        guard case .list(.compound, let values)? = root.compoundValue(named: container) else { return nil }
        let item: NBTValue?
        if let slot = slot {
            item = values.first { value in
                guard case .compound(let tags) = value else { return false }
                return tags.first(where: { $0.name == "Slot" })?.value.numericInt64Value == slot
            }
        } else {
            item = values.first
        }
        guard case .compound(let tags)? = item,
              case .string(let name)? = tags.first(where: { $0.name == "Name" })?.value else { return nil }
        return name
    }
    static func main() throws {
        let session = WorldSession()
        let localKey = Data("~local_player".utf8)
        session.db.values[localKey] = try BedrockNBTCodec.encode(NBTDocument(rootName: "", root: .compound([
            NBTNamedTag(name: "UniqueID", value: .long(1)),
            NBTNamedTag(name: "PlayerLevel", value: .int(2)),
            NBTNamedTag(name: "PlayerLevelProgress", value: .float(0.25)),
            NBTNamedTag(name: "Inventory", value: .list(.compound, (0..<36).map { emptyItem(Int8($0)) })),
            NBTNamedTag(name: "Pos", value: .list(.float, [.float(0), .float(64), .float(0)]))
        ])))
        let onlineKey = Data("player_server_5".utf8)
        session.db.values[onlineKey] = try BedrockNBTCodec.encode(NBTDocument(rootName: "", root: .compound([
            NBTNamedTag(name: "UniqueID", value: .long(5)),
            NBTNamedTag(name: "PlayerLevel", value: .int(3)),
            NBTNamedTag(name: "PlayerLevelProgress", value: .float(0.75)),
            NBTNamedTag(name: "DimensionId", value: .int(0)),
            NBTNamedTag(name: "Pos", value: .list(.float, [.float(4), .float(64), .float(4)]))
        ])))
        let entityKey = BedrockDBKey(
            position: ChunkPosition(x: 0, z: 0, dimension: 0),
            recordType: .entity,
            subChunkIndex: nil
        ).encoded()
        let documents = [
            entity("minecraft:cow", 2, 1),
            entity("minecraft:pig", 3, 2),
            entity("minecraft:cow", 4, 3, definitionsOnly: true)
        ]
        let records = try documents.map { document -> ConsecutiveNBTRecord in
            let raw = try BedrockNBTCodec.encode(document)
            return ConsecutiveNBTRecord(document: document, rawData: raw, encoding: .littleEndian)
        }
        session.db.values[entityKey] = try ConsecutiveNBTCodec.encode(records)
        let executor = WorldCommandExecutor(session: session)

        let given = try executor.execute(try WorldCommandParser.parse("effect give @e strength 12000 50"))
        precondition(given.changedWorld)
        let localAfterGive = try BedrockNBTCodec.decode(session.db.values[localKey]!).root
        precondition(effectCount(localAfterGive) == 1)
        let entitiesAfterGive = try ConsecutiveNBTCodec.decode(session.db.values[entityKey]!)
        precondition(entitiesAfterGive.count == 3)
        precondition(entitiesAfterGive.allSatisfy { effectCount($0.document.root) == 1 })

        let cleared = try executor.execute(try WorldCommandParser.parse("effect clear @e strength"))
        precondition(cleared.changedWorld)
        let localAfterClear = try BedrockNBTCodec.decode(session.db.values[localKey]!).root
        precondition(localAfterClear.compoundValue(named: "ActiveEffects") == nil)
        let entitiesAfterClear = try ConsecutiveNBTCodec.decode(session.db.values[entityKey]!)
        precondition(entitiesAfterClear.allSatisfy { $0.document.root.compoundValue(named: "ActiveEffects") == nil })

        let skipped = try executor.execute(try WorldCommandParser.parse("effect clear @e strength"))
        precondition(!skipped.changedWorld)

        let all = try executor.execute(try WorldCommandParser.parse("effect give @e ALL 40 0"))
        precondition(all.changedWorld)
        let localAfterAll = try BedrockNBTCodec.decode(session.db.values[localKey]!).root
        precondition(effectCount(localAfterAll) == BedrockDataValueCatalog.statusEffects.count)
        let allEntities = try ConsecutiveNBTCodec.decode(session.db.values[entityKey]!)
        precondition(allEntities.allSatisfy { effectCount($0.document.root) == BedrockDataValueCatalog.statusEffects.count })

        let worldSpawn = try executor.execute(try WorldCommandParser.parse("setworldspawn 7 80 -9"))
        precondition(worldSpawn.changedWorld)
        let level = try session.document.readLevelDat().document.root
        precondition(level.intValue(named: "SpawnX") == 7)
        precondition(level.intValue(named: "SpawnY") == 80)
        precondition(level.intValue(named: "SpawnZ") == -9)

        let spawnPoint = try executor.execute(try WorldCommandParser.parse("spawnpoint @s the_end 2 100 3"))
        precondition(spawnPoint.changedWorld)
        let localAfterSpawn = try BedrockNBTCodec.decode(session.db.values[localKey]!).root
        precondition(localAfterSpawn.intValue(named: "SpawnDimension") == 2)
        precondition(localAfterSpawn.intValue(named: "SpawnX") == 2)
        precondition(localAfterSpawn.intValue(named: "SpawnY") == 100)
        precondition(localAfterSpawn.intValue(named: "SpawnZ") == 3)

        let teleported = try executor.execute(try WorldCommandParser.parse("teleport @s nether 10 72 -4"))
        precondition(teleported.changedWorld)
        let localAfterTeleport = try BedrockNBTCodec.decode(session.db.values[localKey]!).root
        precondition(localAfterTeleport.intValue(named: "DimensionId") == 1)
        guard let teleportedPos = localAfterTeleport.value(namedAny: ["Pos"])?.listValues else {
            preconditionFailure("teleport did not write Pos")
        }
        precondition(teleportedPos[0].numericDoubleValue == 10)
        precondition(teleportedPos[1].numericDoubleValue == 72)
        precondition(teleportedPos[2].numericDoubleValue == -4)

        let identifierTeleport = try executor.execute(try WorldCommandParser.parse("teleport minecraft:cow overworld 8 65 8"))
        precondition(identifierTeleport.changedWorld)
        let entitiesAfterIdentifierTeleport = try ConsecutiveNBTCodec.decode(session.db.values[entityKey]!)
        let cowPositions = entitiesAfterIdentifierTeleport.filter {
            BedrockEntityCommonNBT.identifier(in: $0.document.root) == "minecraft:cow"
        }.compactMap { BedrockEntityCommonNBT.position(in: $0.document.root) }
        let pigPosition = entitiesAfterIdentifierTeleport.first {
            BedrockEntityCommonNBT.identifier(in: $0.document.root) == "minecraft:pig"
        }.flatMap { BedrockEntityCommonNBT.position(in: $0.document.root) }
        precondition(cowPositions.count == 2)
        precondition(cowPositions.allSatisfy { $0.x == 8 && $0.y == 65 && $0.z == 8 })
        precondition(pigPosition?.x == 2)

        let autoTeleported = try executor.execute(try WorldCommandParser.parse("teleport @s overworld 0 Auto 0"))
        precondition(autoTeleported.changedWorld)
        let localAfterAuto = try BedrockNBTCodec.decode(session.db.values[localKey]!).root
        guard let autoPos = localAfterAuto.value(namedAny: ["Pos"])?.listValues else {
            preconditionFailure("Auto teleport did not write Pos")
        }
        precondition(autoPos[1].numericDoubleValue == 71)

        let netherAuto = try executor.execute(try WorldCommandParser.parse("teleport @s nether 4 Auto 4"))
        precondition(netherAuto.changedWorld)
        let localAfterNetherAuto = try BedrockNBTCodec.decode(session.db.values[localKey]!).root
        guard let netherAutoPos = localAfterNetherAuto.value(namedAny: ["Pos"])?.listValues else {
            preconditionFailure("Nether Auto teleport did not write Pos")
        }
        precondition(localAfterNetherAuto.intValue(named: "DimensionId") == 1)
        precondition(netherAutoPos[1].numericDoubleValue == 61)

        let fallbackAuto = try executor.execute(try WorldCommandParser.parse("teleport @s overworld 999 Auto 999"))
        precondition(fallbackAuto.changedWorld)
        let localAfterFallback = try BedrockNBTCodec.decode(session.db.values[localKey]!).root
        guard let fallbackPos = localAfterFallback.value(namedAny: ["Pos"])?.listValues else {
            preconditionFailure("fallback Auto teleport did not write Pos")
        }
        precondition(fallbackPos[1].numericDoubleValue == 63)

        let daytimeQuery = try executor.execute(try WorldCommandParser.parse("time query daytime"))
        precondition(!daytimeQuery.changedWorld)
        precondition(daytimeQuery.message == "daytime=13000，日落56%，全天54%")
        let gametimeQuery = try executor.execute(try WorldCommandParser.parse("time query gametime"))
        precondition(gametimeQuery.message == "gametime=12013000")
        let dayQuery = try executor.execute(try WorldCommandParser.parse("time query day"))
        precondition(dayQuery.message == "day=500")

        let ceilSunset = try executor.execute(try WorldCommandParser.parse("time ceil sunset"))
        precondition(ceilSunset.changedWorld)
        let timeAfterCeil = try session.document.readLevelDat().document.root.int64Value(namedAny: ["Time"])
        precondition(timeAfterCeil == 12_036_001)
        _ = try executor.execute(try WorldCommandParser.parse("time set 12013000"))
        let floorMidnight = try executor.execute(try WorldCommandParser.parse("time floor midnight"))
        precondition(floorMidnight.changedWorld)
        let timeAfterFloor = try session.document.readLevelDat().document.root.int64Value(namedAny: ["Time"])
        precondition(timeAfterFloor == 12_018_000)
        let addNegative = try executor.execute(try WorldCommandParser.parse("time add -18000"))
        precondition(addNegative.changedWorld)
        let timeAfterAdd = try session.document.readLevelDat().document.root.int64Value(namedAny: ["Time"])
        precondition(timeAfterAdd == 12_000_000)

        let weather = try executor.execute(try WorldCommandParser.parse("weather thunder 12000 1.0 0"))
        precondition(weather.changedWorld)
        let weatherRoot = try session.document.readLevelDat().document.root
        precondition(weatherRoot.intValue(named: "rainTime") == 12000)
        precondition(weatherRoot.intValue(named: "lightningTime") == 12000)
        precondition(weatherRoot.intValue(named: "doWeatherCycle") == 0)

        let daylock = try executor.execute(try WorldCommandParser.parse("daylock 0"))
        precondition(daylock.changedWorld)
        let daylockRoot = try session.document.readLevelDat().document.root
        precondition(daylockRoot.intValue(named: "dodaylightcycle") == 1)
        precondition(daylockRoot.int64Value(namedAny: ["Time"]) == 12_000_000)
        _ = try executor.execute(try WorldCommandParser.parse("daylock 1"))
        let lockedRoot = try session.document.readLevelDat().document.root
        precondition(lockedRoot.intValue(named: "dodaylightcycle") == 0)

        let uploadedSaveExperience = BedrockPlayerExperience(level: 37, progress: 0.79348814)
        precondition(uploadedSaveExperience.total == 2507)
        let uploadedSaveRoundTrip = try BedrockPlayerExperience.fromTotal(uploadedSaveExperience.total)
        precondition(uploadedSaveRoundTrip.level == 37)
        precondition(abs(uploadedSaveRoundTrip.progress - Float(139.0 / 175.0)) < 0.0001)
        precondition(BedrockPlayerExperience.totalRequired(toReach: 16) == 352)
        precondition(BedrockPlayerExperience.totalRequired(toReach: 17) == 394)
        precondition(BedrockPlayerExperience.totalRequired(toReach: 31) == 1507)
        precondition(BedrockPlayerExperience.totalRequired(toReach: 32) == 1628)

        let experienceAmount = try executor.execute(try WorldCommandParser.parse("experience add @a 100"))
        precondition(experienceAmount.changedWorld)
        var localExperience = try ExperienceStore.read(from: BedrockNBTCodec.decode(session.db.values[localKey]!))
        var onlineExperience = try ExperienceStore.read(from: BedrockNBTCodec.decode(session.db.values[onlineKey]!))
        precondition(localExperience.total == 119 && onlineExperience.total == 137)
        _ = try executor.execute(try WorldCommandParser.parse("experience addlevel @s 5"))
        _ = try executor.execute(try WorldCommandParser.parse("experience level @s 13"))
        let levelResetExperience = try ExperienceStore.read(from: BedrockNBTCodec.decode(session.db.values[localKey]!))
        precondition(levelResetExperience.level == 13 && levelResetExperience.progress == 0)
        _ = try executor.execute(try WorldCommandParser.parse("experience percent @s 0.5"))
        _ = try executor.execute(try WorldCommandParser.parse("experience set 5 250"))
        let localExperienceDocument = try BedrockNBTCodec.decode(session.db.values[localKey]!)
        let onlineExperienceDocument = try BedrockNBTCodec.decode(session.db.values[onlineKey]!)
        localExperience = try ExperienceStore.read(from: localExperienceDocument)
        onlineExperience = try ExperienceStore.read(from: onlineExperienceDocument)
        precondition(localExperience.level == 13)
        precondition(abs(localExperience.progress - 0.5) < 0.0001)
        precondition(localExperience.total == 264)
        precondition(onlineExperience.total == 250)
        precondition(onlineExperience.level == 13)
        precondition(localExperienceDocument.root.intValue(named: "PlayerLevel") == 13)
        precondition(localExperienceDocument.root.compoundValue(named: "PlayerLevelProgress") != nil)
        precondition(localExperienceDocument.root.compoundValue(named: "XpTotal") == nil)
        precondition(localExperienceDocument.root.compoundValue(named: "XpLevel") == nil)
        precondition(localExperienceDocument.root.compoundValue(named: "XpP") == nil)
        let experienceQuery = try executor.execute(try WorldCommandParser.parse("experience query @a"))
        precondition(!experienceQuery.changedWorld && experienceQuery.outputLines.count == 2)
        precondition(experienceQuery.outputLines[0].text.contains("minecraft:player 1 经验总数=") && experienceQuery.outputLines[0].text.contains("经验等级=") && experienceQuery.outputLines[0].text.contains("当前经验条进度="))
        precondition(experienceQuery.outputLines[1].text.contains("minecraft:player 5 经验总数="))
        switch experienceQuery.outputLines[0].style { case .localPlayer: break; default: preconditionFailure("local experience output must be yellow") }
        switch experienceQuery.outputLines[1].style { case .onlinePlayer: break; default: preconditionFailure("online experience output must be blue") }
        do {
            _ = try executor.execute(try WorldCommandParser.parse("experience query minecraft:cow"))
            preconditionFailure("experience must reject non-player targets")
        } catch {}

        let playerSlotGive = try executor.execute(try WorldCommandParser.parse("give @s 5 minecraft:diamond 3 NULL"))
        precondition(playerSlotGive.changedWorld)
        var playerAfterGive = try BedrockNBTCodec.decode(session.db.values[localKey]!).root
        precondition(itemName(in: playerAfterGive, container: "Inventory", slot: 5) == "minecraft:diamond")
        _ = try executor.execute(try WorldCommandParser.parse("give @s Auto minecraft:stone 64 NULL"))
        playerAfterGive = try BedrockNBTCodec.decode(session.db.values[localKey]!).root
        precondition(itemName(in: playerAfterGive, container: "Inventory", slot: 0) == "minecraft:stone")

        _ = try executor.execute(try WorldCommandParser.parse("give 2 1 minecraft:gold_ingot 2 NULL"))
        var giveEntities = try ConsecutiveNBTCodec.decode(session.db.values[entityKey]!)
        let cowWithChest = giveEntities.first { $0.document.root.int64Value(namedAny: ["UniqueID"]) == 2 }!.document.root
        precondition(itemName(in: cowWithChest, container: "ChestItems", slot: 1) == "minecraft:gold_ingot")
        precondition(itemName(in: cowWithChest, container: "Mainhand") == "")

        _ = try executor.execute(try WorldCommandParser.parse("give 2 5 minecraft:emerald 1 NULL"))
        giveEntities = try ConsecutiveNBTCodec.decode(session.db.values[entityKey]!)
        let overflowingCow = giveEntities.first { $0.document.root.int64Value(namedAny: ["UniqueID"]) == 2 }!.document.root
        precondition(itemName(in: overflowingCow, container: "ChestItems", slot: 2) == "minecraft:emerald")
        precondition(itemName(in: overflowingCow, container: "Mainhand") == "minecraft:emerald")

        let missingMainhandChestResult = try executor.execute(try WorldCommandParser.parse("give 4 1 minecraft:iron_ingot 1 NULL"))
        precondition(missingMainhandChestResult.message.contains("跳过 1 个没有可写入 Mainhand 的实体"))
        giveEntities = try ConsecutiveNBTCodec.decode(session.db.values[entityKey]!)
        let cowWithoutMainhand = giveEntities.first { $0.document.root.int64Value(namedAny: ["UniqueID"]) == 4 }!.document.root
        precondition(itemName(in: cowWithoutMainhand, container: "ChestItems", slot: 1) == "")
        precondition(itemName(in: cowWithoutMainhand, container: "Mainhand") == nil)

        let missingMainhandResult = try executor.execute(try WorldCommandParser.parse("give 3 2 minecraft:apple 1 NULL"))
        precondition(missingMainhandResult.message.contains("跳过 1 个没有可写入 Mainhand 的实体"))
        giveEntities = try ConsecutiveNBTCodec.decode(session.db.values[entityKey]!)
        let pigWithoutChest = giveEntities.first { $0.document.root.int64Value(namedAny: ["UniqueID"]) == 3 }!.document.root
        precondition(itemName(in: pigWithoutChest, container: "Mainhand") == nil)

        let setBlock = try executor.execute(try WorldCommandParser.parse("setblock overworld 0 0 0 minecraft:stone NULL minecraft:air NULL"))
        precondition(setBlock.changedWorld)
        let sourceKey = BedrockDBKey.subChunk(x: 0, z: 0, dimension: 0, index: 0)
        let sourceRaw = try session.db.get(sourceKey)!
        let sourceSub = try BedrockSubChunk.decode(sourceRaw, keyYIndex: 0)
        precondition(sourceSub.storages[0].blockState(x: 0, y: 0, z: 0)?.name == "minecraft:stone")

        let spread = try executor.execute(try WorldCommandParser.parse("spread @e"))
        precondition(spread.changedWorld)
        precondition(spread.outputLines.count == 5)
        switch spread.outputLines[0].style {
        case .localPlayer: break
        default: preconditionFailure("spread must display the local player first")
        }
        switch spread.outputLines[1].style {
        case .onlinePlayer: break
        default: preconditionFailure("spread must display online players after the local player")
        }
        precondition(spread.outputLines[0].text.contains("minecraft:player 1 主世界"))
        precondition(spread.outputLines[1].text.contains("minecraft:player 5 主世界"))
        precondition(spread.outputLines.dropFirst(2).allSatisfy { $0.text.contains("minecraft:") && !$0.text.contains("无UniqueID") })
        precondition(spread.outputLines.allSatisfy { $0.text.contains("主世界") && $0.text.contains(" 71 ") })
        let localAfterSpread = try BedrockNBTCodec.decode(session.db.values[localKey]!).root
        let onlineAfterSpread = try BedrockNBTCodec.decode(session.db.values[onlineKey]!).root
        precondition(localAfterSpread.intValue(named: "DimensionId") == 0)
        precondition(onlineAfterSpread.intValue(named: "DimensionId") == 0)
        precondition(localAfterSpread.value(namedAny: ["Pos"])?.listValues?[1].numericDoubleValue == 71)
        precondition(onlineAfterSpread.value(namedAny: ["Pos"])?.listValues?[1].numericDoubleValue == 71)

        let saved = try executor.execute(try WorldCommandParser.parse("structure save test:one overworld 0 0 0 0 0 0"))
        precondition(saved.changedWorld)
        let savedStructureValue = try session.db.get(Data("structuretemplate_test:one".utf8))
        precondition(savedStructureValue != nil)
        let loaded = try executor.execute(try WorldCommandParser.parse("structure load test:one overworld 1 0 0"))
        precondition(loaded.changedWorld)
        let loadedSub = try BedrockSubChunk.decode(try session.db.get(sourceKey)!, keyYIndex: 0)
        precondition(loadedSub.storages[0].blockState(x: 1, y: 0, z: 0)?.name == "minecraft:stone")
        let deletedStructure = try executor.execute(try WorldCommandParser.parse("structure delete test:one"))
        precondition(deletedStructure.changedWorld)
        let deletedStructureValue = try session.db.get(Data("structuretemplate_test:one".utf8))
        precondition(deletedStructureValue == nil)

        let addedArea = try executor.execute(try WorldCommandParser.parse("tickingarea add square overworld 0 0 1 1 Base 1"))
        precondition(addedArea.changedWorld)
        let listedArea = try executor.execute(try WorldCommandParser.parse("tickingarea list overworld"))
        precondition(!listedArea.changedWorld)
        precondition(listedArea.message.contains("[1]Base: 0 0 to 1 1"))
        let addedCircle = try executor.execute(try WorldCommandParser.parse("tickingarea add circle overworld 3 -2 4 Circle 0"))
        precondition(addedCircle.changedWorld)
        let overwrittenCircle = try executor.execute(try WorldCommandParser.parse("tickingarea add circle nether -8 7 2 Circle 1"))
        precondition(overwrittenCircle.changedWorld)
        precondition(overwrittenCircle.message.contains("覆盖"))
        let listedCircle = try executor.execute(try WorldCommandParser.parse("tickingarea list ALL"))
        precondition(!listedCircle.message.contains("Circle: 3 -2 radius: 4"))
        precondition(listedCircle.message.contains("Circle: -8 7 radius: 2"))
        let deletedArea = try executor.execute(try WorldCommandParser.parse("tickingarea delete ALL"))
        precondition(deletedArea.changedWorld)

        print("Effect and world command executor tests passed")
    }
}
SWIFT

swiftc -j 4 \
  "$ROOT/Sources/Support/Errors.swift" \
  "$ROOT/Sources/Support/Hex.swift" \
  "$ROOT/Sources/Support/BedrockDataValueCatalog.swift" \
  "$ROOT/Sources/Support/BedrockLegacyBlockCatalog.swift" \
  "$ROOT/Sources/NBT/NBTTypes.swift" \
  "$ROOT/Sources/NBT/BinaryCursor.swift" \
  "$ROOT/Sources/NBT/BedrockNBTCodec.swift" \
  "$ROOT/Sources/NBT/ConsecutiveNBTCodec.swift" \
  "$ROOT/Sources/Chunk/MapCoordinate.swift" \
  "$ROOT/Sources/Chunk/BedrockMapRegion.swift" \
  "$ROOT/Sources/Chunk/BedrockDBKey.swift" \
  "$ROOT/Sources/Chunk/BedrockSubChunk.swift" \
  "$ROOT/Sources/Chunk/BedrockBiomeData.swift" \
  "$ROOT/Sources/Chunk/HardcodedSpawners.swift" \
  "$ROOT/Sources/Chunk/BedrockEmptyChunk.swift" \
  "$ROOT/Sources/Chunk/BedrockLegacyChunkUpgrade.swift" \
  "$ROOT/Sources/Chunk/BedrockSubChunkEditor.swift" \
  "$ROOT/Sources/Chunk/BedrockChunkStore.swift" \
  "$ROOT/Sources/UI/NBTNode.swift" \
  "$ROOT/Sources/Entity/BedrockWorldObject.swift" \
  "$ROOT/Sources/Entity/BedrockWorldObjectScanner.swift" \
  "$ROOT/Sources/Entity/BedrockEntityCommonNBT.swift" \
  "$ROOT/Sources/Entity/BedrockWorldObjectNBTStore.swift" \
  "$ROOT/Sources/World/WorldDocument.swift" \
  "$ROOT/Sources/World/JavaStructureConverter.swift" \
  "$ROOT/Sources/World/StructureNBTStore.swift" \
  "$ROOT/Sources/World/TickingAreaStore.swift" \
  "$ROOT/Sources/World/WeatherStore.swift" \
  "$ROOT/Sources/World/TimeStore.swift" \
  "$ROOT/Sources/World/PlayerNBTStore.swift" \
  "$ROOT/Sources/World/ExperienceStore.swift" \
  "$ROOT/Sources/Command/WorldCommand.swift" \
  "$ROOT/Sources/Command/WorldCommandExecutor.swift" \
  "$TMP/EffectCommandStubs.swift" \
  -parse-as-library "$TMP/effect_command_test.swift" -o "$TMP/effect-command-tests"
"$TMP/effect-command-tests"
