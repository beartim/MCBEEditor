import XCTest
import UIKit
@testable import MCBEEditor

final class MCBEEditorTests: XCTestCase {
    func testLittleEndianNBTRoundTrip() throws {
        let input = NBTDocument(rootName: "", root: .compound([
            NBTNamedTag(name: "LevelName", value: .string("Test World")),
            NBTNamedTag(name: "SpawnX", value: .int(-128)),
            NBTNamedTag(name: "Seed", value: .long(123456789))
        ]))
        let encoded = try BedrockNBTCodec.encode(input)
        let decoded = try BedrockNBTCodec.decode(encoded)
        XCTAssertEqual(decoded.root.stringValue(named: "LevelName"), "Test World")
        XCTAssertEqual(try BedrockNBTCodec.encode(decoded), encoded)
    }

    func testBatchNBTClipboardRoundTripPreservesEveryTag() throws {
        let documents = [
            NBTDocument(rootName: "A", root: .int(1)),
            NBTDocument(rootName: "B", root: .string("two")),
            NBTDocument(rootName: "C", root: .compound([
                NBTNamedTag(name: "value", value: .long(3))
            ]))
        ]
        let payload = try NBTClipboardCodec.encodeBatch(documents)
        XCTAssertTrue(NBTClipboardCodec.isBatchPayload(payload))
        let decoded = try NBTClipboardCodec.decodeBatch(payload)
        XCTAssertEqual(decoded.count, 3)
        XCTAssertEqual(decoded.map(\.rootName), ["A", "B", "C"])
        if case .int(let value) = decoded[0].root { XCTAssertEqual(value, 1) }
        else { XCTFail("first tag changed type") }
        if case .string(let value) = decoded[1].root { XCTAssertEqual(value, "two") }
        else { XCTFail("second tag changed type") }
        guard case .compound(let tags) = decoded[2].root,
              case .long(let value)? = tags.first(where: { $0.name == "value" })?.value else {
            return XCTFail("third tag changed type")
        }
        XCTAssertEqual(value, 3)
    }

    func testCopyDocumentsWritesBatchAndLegacyRepresentationsTogether() throws {
        let documents = [
            NBTDocument(rootName: "one", root: .int(1)),
            NBTDocument(rootName: "two", root: .int(2)),
            NBTDocument(rootName: "three", root: .int(3))
        ]
        UIPasteboard.general.items = []
        NBTEditingUI.copyDocuments(documents)

        XCTAssertEqual(UIPasteboard.general.items.count, 1)
        let batchType = "com.wzn.mcbeeditor.nbt-tags-v1"
        let legacyType = "com.wzn.mcbeeditor.nbt-tag"
        let item = try XCTUnwrap(UIPasteboard.general.items.first)
        let batch = try XCTUnwrap(item[batchType] as? Data)
        XCTAssertNotNil(item[legacyType] as? Data)
        XCTAssertEqual(try NBTClipboardCodec.decodeBatch(batch).count, 3)
    }

    func testMapCoordinateFlooring() {
        XCTAssertEqual(MapCoordinate.chunk(fromBlock: 15), 0)
        XCTAssertEqual(MapCoordinate.chunk(fromBlock: 16), 1)
        XCTAssertEqual(MapCoordinate.chunk(fromBlock: -1), -1)
        XCTAssertEqual(MapCoordinate.chunk(fromBlock: -17), -2)
        XCTAssertEqual(MapCoordinate.chunk(fromBlock: Int64(Int32.max) * 16), Int32.max)
    }

    func testDimensionChunkKeyRoundTrip() {
        let data = BedrockDBKey.subChunk(x: -4, z: 9, dimension: 1, index: -2)
        let key = BedrockDBKey.parse(data)
        XCTAssertEqual(key?.position.x, -4)
        XCTAssertEqual(key?.position.z, 9)
        XCTAssertEqual(key?.position.dimension, 1)
        XCTAssertEqual(key?.recordType, .subChunk)
        XCTAssertEqual(key?.subChunkIndex, -2)
    }
    func testStructureRecordMetadata() throws {
        let document = NBTDocument(rootName: "", root: .compound([
            NBTNamedTag(name: "format_version", value: .int(1)),
            NBTNamedTag(name: "size", value: .list(.int, [.int(12), .int(6), .int(9)])),
            NBTNamedTag(name: "structure_world_origin", value: .list(.int, [.int(-20), .int(64), .int(30)]))
        ]))
        let record = StructureNBTRecord(
            key: Data("structuretemplate_castle".utf8),
            keyText: "structuretemplate_castle",
            displayName: "castle",
            document: document,
            rawData: try BedrockNBTCodec.encode(document),
            encoding: .littleEndian,
            decodeError: nil
        )
        XCTAssertEqual(record.sizeDescription, "12×6×9")
        XCTAssertEqual(record.originDescription, "(-20, 64, 30)")
        XCTAssertEqual(record.formatVersion, 1)
    }

    func testRawChunkRecordMatchingCoversUnknownModernTags() {
        let overworld = ChunkPosition(x: 8, z: -8, dimension: 0)

        var legacyConversion = Data()
        legacyConversion.appendLE(overworld.x)
        legacyConversion.appendLE(overworld.z)
        legacyConversion.append(UInt8(0x37))
        XCTAssertTrue(BedrockChunkStore.isRawChunkRecordKey(legacyConversion, position: overworld))

        var modernGenerationSeed = Data()
        modernGenerationSeed.appendLE(overworld.x)
        modernGenerationSeed.appendLE(overworld.z)
        modernGenerationSeed.appendLE(overworld.dimension)
        modernGenerationSeed.append(UInt8(0x3c))
        XCTAssertTrue(BedrockChunkStore.isRawChunkRecordKey(modernGenerationSeed, position: overworld))

        var legacyVersion = Data()
        legacyVersion.appendLE(overworld.x)
        legacyVersion.appendLE(overworld.z)
        legacyVersion.append(UInt8(0x76))
        XCTAssertTrue(BedrockChunkStore.isRawChunkRecordKey(legacyVersion, position: overworld))

        var subChunk = Data()
        subChunk.appendLE(overworld.x)
        subChunk.appendLE(overworld.z)
        subChunk.append(UInt8(0x2f))
        subChunk.append(UInt8(bitPattern: Int8(-4)))
        XCTAssertTrue(BedrockChunkStore.isRawChunkRecordKey(subChunk, position: overworld))

        let other = ChunkPosition(x: 9, z: -8, dimension: 0)
        XCTAssertFalse(BedrockChunkStore.isRawChunkRecordKey(legacyConversion, position: other))
    }

    func testRawChunkRecordMatchingIsDimensionAware() {
        let nether = ChunkPosition(x: -3, z: 7, dimension: 1)
        var key = Data()
        key.appendLE(nether.x)
        key.appendLE(nether.z)
        key.appendLE(nether.dimension)
        key.append(UInt8(0x40))
        XCTAssertTrue(BedrockChunkStore.isRawChunkRecordKey(key, position: nether))

        let end = ChunkPosition(x: -3, z: 7, dimension: 2)
        XCTAssertFalse(BedrockChunkStore.isRawChunkRecordKey(key, position: end))
    }

    func testModernLevelChunkTagsAreRecognized() {
        XCTAssertEqual(ChunkRecordType(rawValue: 0x37), .conversionData)
        XCTAssertEqual(ChunkRecordType(rawValue: 0x3c), .generationSeed)
        XCTAssertEqual(ChunkRecordType(rawValue: 0x40), .blendingData)
        XCTAssertEqual(ChunkRecordType(rawValue: 0x41), .actorDigestVersion)
        XCTAssertEqual(ChunkRecordType(rawValue: 0x76), .legacyVersion)
    }

    func testBedrockBiomeCatalogUsesBedrockNumericIDs() {
        XCTAssertEqual(BedrockBiomeCatalog.entry(for: 3)?.identifier, "minecraft:extreme_hills")
        XCTAssertNil(BedrockBiomeCatalog.entry(for: 50))
        XCTAssertEqual(BedrockBiomeCatalog.entry(for: 178)?.identifier, "minecraft:soulsand_valley")
        XCTAssertEqual(BedrockBiomeCatalog.entry(for: 191)?.identifier, "minecraft:mangrove_swamp")
        XCTAssertEqual(BedrockBiomeCatalog.entry(for: 192)?.identifier, "minecraft:cherry_grove")
        XCTAssertEqual(BedrockBiomeCatalog.entry(for: 193)?.identifier, "minecraft:pale_garden")
        XCTAssertEqual(BedrockBiomeCatalog.entry(for: 194)?.identifier, "minecraft:sulfur_caves")
        XCTAssertEqual(BedrockBiomeCatalog.entry(for: 195)?.identifier, "minecraft:dappled_forest")
        XCTAssertEqual(Set(BedrockBiomeCatalog.entries.map(\.id)).count, BedrockBiomeCatalog.entries.count)
    }

    func testBedrockDataValueCatalogs() {
        XCTAssertEqual(BedrockDataValueCatalog.entities.first { $0.id == 44 }?.displayName, "僵尸村民（旧版）")
        XCTAssertEqual(BedrockDataValueCatalog.entities.first { $0.id == 70 }?.displayName, "末影之眼")
        XCTAssertEqual(BedrockDataValueCatalog.entities.first { $0.id == 79 }?.displayName, "末影龙火球")
        XCTAssertEqual(BedrockDataValueCatalog.entities.first { $0.id == 116 }?.displayName, "僵尸村民")
        XCTAssertEqual(BedrockDataValueCatalog.entities.first { $0.id == 145 }?.displayName, "不祥之物生成器")
        XCTAssertEqual(BedrockDataValueCatalog.entities.first { $0.id == 154 }?.identifier, "minecraft:cushion")
        XCTAssertEqual(BedrockDataValueCatalog.entities.first { $0.id == 154 }?.hexadecimalID, "0x9A")
        XCTAssertEqual(BedrockDataValueCatalog.entity(forNumericID: 44)?.identifier, "minecraft:zombie_villager")
        XCTAssertEqual(BedrockDataValueCatalog.entityIdentifier(forRawValue: "70"), "minecraft:eye_of_ender_signal")
        XCTAssertEqual(BedrockDataValueCatalog.entityIdentifier(forRawValue: "0x9A"), "minecraft:cushion")
        XCTAssertEqual(BedrockDataValueCatalog.statusEffects.first { $0.id == 1 }?.displayName, "迅捷")
        XCTAssertEqual(BedrockDataValueCatalog.statusEffects.first { $0.id == 31 }?.identifier, "trial_omen")
        XCTAssertEqual(BedrockDataValueCatalog.statusEffects.first { $0.id == 37 }?.identifier, "breath_of_the_nautilus")
        XCTAssertEqual(BedrockDataValueCatalog.enchantments.first { $0.id == 38 }?.identifier, "wind_burst")
        XCTAssertEqual(BedrockDataValueCatalog.enchantments.first { $0.id == 41 }?.identifier, "lunge")
        XCTAssertEqual(Set(BedrockDataValueCatalog.entities.map(\.id)).count, BedrockDataValueCatalog.entities.count)
        XCTAssertEqual(Set(BedrockDataValueCatalog.statusEffects.map(\.id)).count, BedrockDataValueCatalog.statusEffects.count)
        XCTAssertEqual(Set(BedrockDataValueCatalog.enchantments.map(\.id)).count, BedrockDataValueCatalog.enchantments.count)
    }

    func testLegacyBlockNumericIDCatalog() {
        XCTAssertEqual(BedrockLegacyBlockCatalog.blocks.count, 256)
        XCTAssertEqual(BedrockLegacyBlockCatalog.block(forNumericID: 1)?.identifier, "minecraft:stone")
        XCTAssertEqual(BedrockLegacyBlockCatalog.block(forNumericID: 5)?.identifier, "minecraft:planks")
        XCTAssertEqual(BedrockLegacyBlockCatalog.block(forIdentifier: "minecraft:grass")?.id, 2)
        XCTAssertEqual(BedrockLegacyBlockCatalog.block(forIdentifier: "minecraft:oak_planks")?.id, 5)
        XCTAssertEqual(BedrockLegacyBlockCatalog.blockIdentifier(forRawValue: "0xA6"), "minecraft:unused_166")
        XCTAssertEqual(BedrockLegacyBlockCatalog.numericID(forIdentifier: "minecraft:movingBlock"), 250)
        XCTAssertEqual(Set(BedrockLegacyBlockCatalog.blocks.map(\.id)).count, 256)
    }

    func testVillageDwellersReadCurrentIDField() {
        let currentDwellers: NBTValue = .compound([
            NBTNamedTag(name: "Dwellers", value: .list(.compound, [
                .compound([
                    NBTNamedTag(name: "ID", value: .long(101)),
                    NBTNamedTag(name: "LastSeen", value: .long(9999))
                ]),
                .compound([
                    NBTNamedTag(name: "id", value: .string("-202")),
                    NBTNamedTag(name: "Role", value: .int(3))
                ]),
                .compound([
                    NBTNamedTag(name: "UniqueID", value: .long(303))
                ])
            ]))
        ])
        XCTAssertEqual(
            VillageNBTStore.dwellerUniqueIDs(in: currentDwellers, rootIsDwellersRecord: true),
            [-202, 101, 303]
        )

        let legacyVillage: NBTValue = .compound([
            NBTNamedTag(name: "Players", value: .list(.compound, [
                .compound([NBTNamedTag(name: "ID", value: .long(9001))])
            ])),
            NBTNamedTag(name: "Dwellers", value: .list(.compound, [
                .compound([NBTNamedTag(name: "ID", value: .long(404))])
            ]))
        ])
        XCTAssertEqual(
            VillageNBTStore.dwellerUniqueIDs(in: legacyVillage, rootIsDwellersRecord: false),
            [404]
        )
    }

    func testNBTCodecSupportsAllPrismarineEndianFormats() throws {
        let document = NBTDocument(rootName: "", root: .compound([
            NBTNamedTag(name: "format_version", value: .int(1)),
            NBTNamedTag(name: "short", value: .short(-1234)),
            NBTNamedTag(name: "size", value: .list(.int, [.int(2), .int(3), .int(4)])),
            NBTNamedTag(name: "name", value: .string("结构")),
            NBTNamedTag(name: "long", value: .long(0x0102030405060708)),
            NBTNamedTag(name: "float", value: .float(1.25)),
            NBTNamedTag(name: "double", value: .double(2.5)),
            NBTNamedTag(name: "ints", value: .intArray([1, -2, 3])),
            NBTNamedTag(name: "longs", value: .longArray([4, -5, 6]))
        ]))

        for encoding in [NBTEncoding.bigEndian, .littleEndian, .littleEndianVarInt] {
            let encoded = try BedrockNBTCodec.encode(document, encoding: encoding)
            let decoded = try BedrockNBTCodec.decode(encoded, encoding: encoding)
            XCTAssertEqual(decoded.rootName, document.rootName)
            XCTAssertEqual(decoded.root.summary, document.root.summary)
            XCTAssertEqual(decoded.root.intValue(named: "format_version"), 1)
            XCTAssertEqual(decoded.root.stringValue(named: "name"), "结构")
        }
    }

    func testCompressionBridgeInflatesGzipAndZlibNBT() throws {
        let expected = Data([10, 0, 0, 0])
        let gzip = Data([31, 139, 8, 0, 0, 0, 0, 0, 2, 255, 227, 98, 96, 96, 0, 0, 120, 63, 249, 78, 4, 0, 0, 0])
        let zlib = Data([120, 156, 227, 98, 96, 96, 0, 0, 0, 44, 0, 11])
        XCTAssertEqual(try BTCompressionBridge.inflateWrapped(gzip, expectedSize: 64), expected)
        XCTAssertEqual(try BTCompressionBridge.inflateWrapped(zlib, expectedSize: 64), expected)
    }

    func testJavaStructureConvertsToGameReadableBedrockSchema() throws {
        let java = NBTDocument(rootName: "", root: .compound([
            NBTNamedTag(name: "size", value: .list(.int, [.int(2), .int(1), .int(1)])),
            NBTNamedTag(name: "palette", value: .list(.compound, [
                .compound([NBTNamedTag(name: "Name", value: .string("minecraft:stone"))]),
                .compound([
                    NBTNamedTag(name: "Name", value: .string("minecraft:oak_log")),
                    NBTNamedTag(name: "Properties", value: .compound([
                        NBTNamedTag(name: "axis", value: .string("x"))
                    ]))
                ])
            ])),
            NBTNamedTag(name: "blocks", value: .list(.compound, [
                .compound([
                    NBTNamedTag(name: "pos", value: .list(.int, [.int(0), .int(0), .int(0)])),
                    NBTNamedTag(name: "state", value: .int(0))
                ]),
                .compound([
                    NBTNamedTag(name: "pos", value: .list(.int, [.int(1), .int(0), .int(0)])),
                    NBTNamedTag(name: "state", value: .int(1))
                ])
            ])),
            NBTNamedTag(name: "entities", value: .list(.compound, []))
        ]))

        let conversion = try JavaStructureConverter.convertIfNeeded(java)
        XCTAssertTrue(conversion.result.convertedFromJava)
        XCTAssertEqual(conversion.result.placedBlockCount, 2)
        XCTAssertEqual(conversion.document.root.intValue(named: "format_version"), 1)

        let structure = try XCTUnwrap(conversion.document.root.compoundValue(named: "structure"))
        guard case .list(.list, let layers)? = structure.compoundValue(named: "block_indices") else {
            return XCTFail("missing block_indices")
        }
        XCTAssertEqual(layers.count, 2)
        for layer in layers {
            guard case .list(.int, let values) = layer else { return XCTFail("invalid index layer") }
            XCTAssertEqual(values.count, 2)
        }

        let encoded = try BedrockNBTCodec.encode(conversion.document, encoding: .littleEndian)
        XCTAssertNoThrow(try BedrockNBTCodec.decode(encoded, encoding: .littleEndian))
    }

    func testBedrockStructureImportNormalizesBothIndexLayers() throws {
        let bedrock = NBTDocument(rootName: "source", root: .compound([
            NBTNamedTag(name: "format_version", value: .int(1)),
            NBTNamedTag(name: "size", value: .list(.int, [.int(2), .int(1), .int(1)])),
            NBTNamedTag(name: "structure", value: .compound([
                NBTNamedTag(name: "block_indices", value: .list(.list, [
                    .list(.int, [.int(0), .int(0)]),
                    .list(.int, [])
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

        let conversion = try JavaStructureConverter.convertIfNeeded(bedrock)
        XCTAssertFalse(conversion.result.convertedFromJava)
        XCTAssertEqual(conversion.document.rootName, "")
        let structure = try XCTUnwrap(conversion.document.root.compoundValue(named: "structure"))
        guard case .list(.list, let layers)? = structure.compoundValue(named: "block_indices") else {
            return XCTFail("missing block_indices")
        }
        for layer in layers {
            guard case .list(.int, let values) = layer else { return XCTFail("invalid index layer") }
            XCTAssertEqual(values.count, 2)
        }
    }

    func testStandaloneNBTFileCodecDecodesAndReencodesConsecutiveVarInt() throws {
        let documents = [
            NBTDocument(rootName: "", root: .compound([
                NBTNamedTag(name: "name", value: .string("minecraft:stone")),
                NBTNamedTag(name: "states", value: .compound([])),
                NBTNamedTag(name: "version", value: .int(17_959_425))
            ])),
            NBTDocument(rootName: "", root: .compound([
                NBTNamedTag(name: "name", value: .string("minecraft:dirt")),
                NBTNamedTag(name: "states", value: .compound([])),
                NBTNamedTag(name: "version", value: .int(17_959_425))
            ]))
        ]
        let source = try StandaloneNBTFileCodec.encode(documents, encoding: .littleEndianVarInt)
        let file = try StandaloneNBTFileCodec.decode(
            data: source,
            filename: "canonical_block_states.nbt"
        )
        XCTAssertEqual(file.storageKind, .consecutive)
        XCTAssertEqual(file.originalEncoding, .littleEndianVarInt)
        XCTAssertEqual(file.documents.count, 2)
        XCTAssertEqual(file.documents[0].root.stringValue(named: "name"), "minecraft:stone")
        XCTAssertEqual(
            try StandaloneNBTFileCodec.encode(file.documents, encoding: file.originalEncoding),
            source
        )
    }

    func testStandaloneNBTFileCodecExportsJavaStructureAsMCStructure() throws {
        let java = NBTDocument(rootName: "", root: .compound([
            NBTNamedTag(name: "size", value: .list(.int, [.int(1), .int(1), .int(1)])),
            NBTNamedTag(name: "palette", value: .list(.compound, [
                .compound([NBTNamedTag(name: "Name", value: .string("minecraft:stone"))])
            ])),
            NBTNamedTag(name: "blocks", value: .list(.compound, [
                .compound([
                    NBTNamedTag(name: "pos", value: .list(.int, [.int(0), .int(0), .int(0)])),
                    NBTNamedTag(name: "state", value: .int(0))
                ])
            ]))
        ]))
        let result = try StandaloneNBTFileCodec.encodeAsMCStructure([java])
        let decoded = try BedrockNBTCodec.decode(result.data, encoding: .littleEndian)
        XCTAssertTrue(result.result.convertedFromJava)
        XCTAssertEqual(decoded.root.intValue(named: "format_version"), 1)
        XCTAssertNotNil(decoded.root.compoundValue(named: "structure"))
    }

    func testBedrockSlimeChunkReferenceCoordinates() {
        XCTAssertTrue(BedrockSlimeChunk.isSlimeChunk(x: -1, z: 0))
        XCTAssertTrue(BedrockSlimeChunk.isSlimeChunk(x: 3, z: 1))
        XCTAssertTrue(BedrockSlimeChunk.isSlimeChunk(x: 0, z: 4))
        XCTAssertFalse(BedrockSlimeChunk.isSlimeChunk(x: 0, z: 0))
        XCTAssertFalse(BedrockSlimeChunk.isSlimeChunk(x: 1, z: 1))
    }

    func testTickingAreaMembershipAndLimits() throws {
        let rectangle = BedrockTickingArea(
            dimension: 0, isCircle: false,
            minimumX: -2, minimumZ: 4, maximumX: 1, maximumZ: 5,
            name: "rect", preload: true
        )
        XCTAssertEqual(rectangle.chunkCount, 8)
        XCTAssertTrue(rectangle.contains(chunkX: -2, chunkZ: 4))
        XCTAssertFalse(rectangle.contains(chunkX: 2, chunkZ: 4))
        XCTAssertNoThrow(try TickingAreaStore.validate(rectangle))

        let circle = BedrockTickingArea(
            dimension: 1, isCircle: true,
            minimumX: -32, minimumZ: -32, maximumX: 32, maximumZ: 32,
            name: "circle", preload: false
        )
        XCTAssertEqual(circle.radius, 2)
        XCTAssertEqual(circle.centerChunk.x, 0)
        XCTAssertEqual(circle.centerChunk.z, 0)
        XCTAssertTrue(circle.contains(chunkX: 0, chunkZ: 2))
        XCTAssertFalse(circle.contains(chunkX: 2, chunkZ: 2))
        XCTAssertNoThrow(try TickingAreaStore.validate(circle))

        let nativeFourChunkCircle = BedrockTickingArea(
            dimension: 0, isCircle: true,
            minimumX: -54, minimumZ: -59, maximumX: 74, maximumZ: 69,
            name: "radius4", preload: false
        )
        XCTAssertEqual(nativeFourChunkCircle.radius, 4)
        XCTAssertEqual(nativeFourChunkCircle.centerBlockX, 10)
        XCTAssertEqual(nativeFourChunkCircle.centerBlockZ, 5)
        XCTAssertEqual(nativeFourChunkCircle.centerChunk.x, 0)
        XCTAssertEqual(nativeFourChunkCircle.centerChunk.z, 0)
        XCTAssertTrue(nativeFourChunkCircle.contains(chunkX: 4, chunkZ: 0))
        XCTAssertFalse(nativeFourChunkCircle.contains(chunkX: 5, chunkZ: 0))

        let selection = TickingAreaSelectionContext(
            dimension: 0, minimumX: 4, minimumZ: 0, maximumX: 4, maximumZ: 0
        )
        XCTAssertTrue(selection.intersects(nativeFourChunkCircle))
    }



    func testWorldCommandStrictParsing() throws {
        let line = "fill the_end 0 0 0 60 200 16 minecraft:leaves 'String'\"old_leaf_type\"=\"oak\",'Byte'\"persistent_bit\"=\"0\",'Byte'\"update_bit\"=\"0\" minecraft:chest 'Int'\"facing_direction\"=\"3\""
        guard case .fill(let dimension, let region, let layer0, let layer1) = try WorldCommandParser.parse(line) else {
            return XCTFail("fill was not parsed")
        }
        XCTAssertEqual(dimension, 2)
        XCTAssertEqual(region.minimum.x, 0)
        XCTAssertEqual(region.maximum.y, 200)
        XCTAssertEqual(region.maximum.z, 16)
        XCTAssertEqual(layer0.name, "minecraft:leaves")
        XCTAssertEqual(layer0.states.count, 3)
        XCTAssertEqual(layer1.name, "minecraft:chest")
        XCTAssertEqual(layer1.states.count, 1)
        XCTAssertNoThrow(try WorldCommandParser.parse("clone overworld 0 0 0 1 1 1 nether 10 20 30"))
        XCTAssertThrowsError(try WorldCommandParser.parse("clone 主世界 0 0 0 1 1 1 nether 10 20 30"))
        let source = CommandBlockBox(
            CommandBlockCoordinate(x: 0, y: 70, z: 0),
            CommandBlockCoordinate(x: 4, y: 70, z: 4)
        )
        let target = CommandBlockBox(
            CommandBlockCoordinate(x: 1, y: 70, z: 1),
            CommandBlockCoordinate(x: 5, y: 70, z: 5)
        )
        let traversal = CommandCloneTraversal(source: source, target: target, sameDimension: true)
        XCTAssertEqual(traversal.startX, 4)
        XCTAssertEqual(traversal.startZ, 4)
        XCTAssertEqual(traversal.stepX, -1)
        XCTAssertEqual(traversal.stepZ, -1)
        XCTAssertNoThrow(try WorldCommandParser.parse("help clear"))
        XCTAssertNoThrow(try WorldCommandParser.parse("clear @e"))
        XCTAssertNoThrow(try WorldCommandParser.parse("clearspawnpoint @a"))
        XCTAssertNoThrow(try WorldCommandParser.parse("give minecraft:cow Auto minecraft:redstone_wire 97 NULL"))
        XCTAssertNoThrow(try WorldCommandParser.parse("give minecraft:cow 2 minecraft:lit_smoker 99 'Compound'\"tag\"=\"{'Byte'\"Unbreakable\"=\"1\"}\",'Short'\"Damage\"=\"1\""))
        XCTAssertNoThrow(try WorldCommandParser.parseStates("'ByteArray'\"Name\"=\"[0,1]\""))
        XCTAssertNoThrow(try WorldCommandParser.parseStates("'List''IntArray'\"Name\"=\"[],[5,2]\""))
        XCTAssertNoThrow(try WorldCommandParser.parseStates("'Compound'\"Name\"=\"{'String'\"Name\"=\"Tom\",'List''Int'\"Num\"=\"1,2,3,4\"}\""))
        XCTAssertNoThrow(try WorldCommandParser.parseStates("'List''Compound'\"Name\"=\"{'Int'\"Num\"=\"0\"},{}\""))
        XCTAssertNoThrow(try WorldCommandParser.parse("kill @a 1"))
        XCTAssertNoThrow(try WorldCommandParser.parse("kick @a"))
        XCTAssertNoThrow(try WorldCommandParser.parse("kick -123456789"))
        XCTAssertNoThrow(try WorldCommandParser.parse("summon minecraft:pig overworld 0 64 0 'Byte'\"Invulnerable\"=\"1\",'String'\"CustomName\"=\"MyPig\""))
        XCTAssertNoThrow(try WorldCommandParser.parse("summon minecraft:pig overworld 0 64 0 default"))
        XCTAssertNoThrow(try WorldCommandParser.parse("effect give @a strength 12000 50"))
        XCTAssertNoThrow(try WorldCommandParser.parse("effect clear @e ALL"))
        XCTAssertNoThrow(try WorldCommandParser.parse("setblock overworld 1 64 2 minecraft:stone NULL minecraft:air NULL"))
        XCTAssertNoThrow(try WorldCommandParser.parse("setworldspawn 0 80 0"))
        XCTAssertNoThrow(try WorldCommandParser.parse("spawnpoint @a the_end 0 100 0"))
        XCTAssertNoThrow(try WorldCommandParser.parse("teleport -4294967270 the_end 10 70 10"))
        XCTAssertNoThrow(try WorldCommandParser.parse("teleport @a overworld 0 Auto 0"))
        XCTAssertNoThrow(try WorldCommandParser.parse("teleport minecraft:cow overworld 0 64 0"))
        XCTAssertNoThrow(try WorldCommandParser.parse("spread @e"))
        XCTAssertNoThrow(try WorldCommandParser.parse("spread minecraft:cow"))
        XCTAssertNoThrow(try WorldCommandParser.parse("daylock 0"))
        XCTAssertNoThrow(try WorldCommandParser.parse("daylock 1"))
        XCTAssertNoThrow(try WorldCommandParser.parse("experience add @a -100"))
        XCTAssertNoThrow(try WorldCommandParser.parse("experience addlevel @s 5"))
        XCTAssertNoThrow(try WorldCommandParser.parse("experience level @s 30"))
        XCTAssertNoThrow(try WorldCommandParser.parse("experience percent @s 0.5"))
        XCTAssertNoThrow(try WorldCommandParser.parse("experience query @a"))
        XCTAssertNoThrow(try WorldCommandParser.parse("experience set @s 2500"))
        XCTAssertNoThrow(try WorldCommandParser.parse("time query daytime"))
        XCTAssertNoThrow(try WorldCommandParser.parse("time query gametime"))
        XCTAssertNoThrow(try WorldCommandParser.parse("time query day"))
        XCTAssertNoThrow(try WorldCommandParser.parse("time add -1000"))
        XCTAssertNoThrow(try WorldCommandParser.parse("time set 12013000"))
        XCTAssertNoThrow(try WorldCommandParser.parse("time ceil sunset"))
        XCTAssertNoThrow(try WorldCommandParser.parse("time floor midnight"))
        XCTAssertNoThrow(try WorldCommandParser.parse("weather clear 1"))
        XCTAssertNoThrow(try WorldCommandParser.parse("weather rain 6000 0.5 1"))
        XCTAssertNoThrow(try WorldCommandParser.parse("weather thunder 12000 1.0 0"))
        XCTAssertNoThrow(try WorldCommandParser.parse("structure save mystructure:1 overworld 0 0 0 50 50 50"))
        XCTAssertNoThrow(try WorldCommandParser.parse("structure load mystructure:1 nether 9 50 9"))
        XCTAssertNoThrow(try WorldCommandParser.parse("structure delete mystructure:1"))
        XCTAssertNoThrow(try WorldCommandParser.parse("structure delete ALL"))
        XCTAssertNoThrow(try WorldCommandParser.parse("tickingarea add square nether 0 0 1 1 Base 1"))
        XCTAssertNoThrow(try WorldCommandParser.parse("tickingarea add circle overworld 0 0 4 Circle 0"))
        XCTAssertNoThrow(try WorldCommandParser.parse("tickingarea delete ALL"))
        XCTAssertNoThrow(try WorldCommandParser.parse("tickingarea list overworld"))
        XCTAssertNoThrow(try WorldCommandParser.parse("tickingarea list ALL"))
        XCTAssertThrowsError(try WorldCommandParser.parse("effect clear @e ALL 1"))
        XCTAssertThrowsError(try WorldCommandParser.parse("setblock overworld 0 0 0 minecraft:stone NULL minecraft:air"))
        XCTAssertThrowsError(try WorldCommandParser.parse("setworldspawn 0 80"))
        XCTAssertThrowsError(try WorldCommandParser.parse("spawnpoint minecraft:cow overworld 0 64"))
        XCTAssertThrowsError(try WorldCommandParser.parse("structure save invalidname overworld 0 0 0 1 1 1"))
        XCTAssertThrowsError(try WorldCommandParser.parse("structure load mystructure:1 overworld 0 0"))
        XCTAssertThrowsError(try WorldCommandParser.parse("tickingarea add circle overworld 0 0 5 TooLarge 0"))
        XCTAssertThrowsError(try WorldCommandParser.parse("time set -1"))
        XCTAssertThrowsError(try WorldCommandParser.parse("teleport @a overworld 0 auto 0"))
        XCTAssertThrowsError(try WorldCommandParser.parse("spread"))
        XCTAssertThrowsError(try WorldCommandParser.parse("spread @e extra"))
        XCTAssertThrowsError(try WorldCommandParser.parse("daylock 2"))
        XCTAssertThrowsError(try WorldCommandParser.parse("daylock 1 extra"))
        XCTAssertThrowsError(try WorldCommandParser.parse("experience amount @a 1"))
        XCTAssertThrowsError(try WorldCommandParser.parse("experience addlevel @s"))
        XCTAssertThrowsError(try WorldCommandParser.parse("experience level @s -1"))
        XCTAssertThrowsError(try WorldCommandParser.parse("experience level @s 24792"))
        XCTAssertThrowsError(try WorldCommandParser.parse("give @s auto minecraft:stone 1 NULL"))
        XCTAssertThrowsError(try WorldCommandParser.parse("give @s 36 minecraft:stone 1 NULL"))
        XCTAssertThrowsError(try WorldCommandParser.parse("time ceil dusk"))
        XCTAssertThrowsError(try WorldCommandParser.parse("weather clear 12000 1"))
        XCTAssertThrowsError(try WorldCommandParser.parse("weather rain 12000 1.1 0"))
        XCTAssertThrowsError(try WorldCommandParser.parse("weather thunder -1 1.0 0"))
        XCTAssertThrowsError(try WorldCommandParser.parse("tickingarea add square overworld 0 0 10 10 TooLarge 0"))
        XCTAssertThrowsError(try WorldCommandParser.parse("tickingarea list main"))
        XCTAssertThrowsError(try WorldCommandParser.parse("effect give @a unknown_effect 20 0"))
        XCTAssertThrowsError(try WorldCommandParser.parse("effect give @a strength -1 0"))
        XCTAssertThrowsError(try WorldCommandParser.parse("effect give @a strength 20 256"))
        XCTAssertThrowsError(try WorldCommandParser.parse("summon minecraft:pig overworld 0 64 0 NULL"))
        XCTAssertThrowsError(try WorldCommandParser.parse("summon minecraft:pig overworld 0 64 0 'Long'\"UniqueID\"=\"2\""))
        XCTAssertThrowsError(try WorldCommandParser.parse("clear"))
        XCTAssertThrowsError(try WorldCommandParser.parse("clearspawnpoint"))
        XCTAssertThrowsError(try WorldCommandParser.parse("give @s Auto minecraft:stone 1"))
        XCTAssertThrowsError(try WorldCommandParser.parse("kill @e 2"))
        XCTAssertThrowsError(try WorldCommandParser.parse("kick @e"))
        XCTAssertThrowsError(try WorldCommandParser.parse("/help"))
        XCTAssertThrowsError(try WorldCommandParser.parse("fill overworld 0 0 0 1 1 1 minecraft:stone NULL minecraft:air"))
    }

    func testCommandEffectNBTMutation() throws {
        guard let strength = BedrockDataValueCatalog.statusEffects.first(where: { $0.identifier == "strength" }) else {
            return XCTFail("strength data value missing")
        }
        let root = NBTValue.compound([NBTNamedTag(name: "UniqueID", value: .long(123))])
        let given = try CommandEffectNBT.applying(
            operation: .give(duration: 12000, amplifier: 50),
            selection: .single(strength),
            to: root
        )
        XCTAssertTrue(given.changed)
        guard case .list(.compound, let effects)? = given.value.compoundValue(named: "ActiveEffects"),
              effects.count == 1,
              case .compound(let tags) = effects[0] else {
            return XCTFail("ActiveEffects was not created")
        }
        func value(_ name: String) -> NBTValue? { tags.first(where: { $0.name == name })?.value }
        XCTAssertEqual(value("Id")?.numericInt64Value, 5)
        XCTAssertEqual(value("Amplifier")?.numericInt64Value, 50)
        XCTAssertEqual(value("Duration")?.numericInt64Value, 12000)
        XCTAssertEqual(value("DurationEasy")?.numericInt64Value, 12000)
        XCTAssertEqual(value("DurationNormal")?.numericInt64Value, 12000)
        XCTAssertEqual(value("DurationHard")?.numericInt64Value, 12000)
        XCTAssertEqual(value("Ambient")?.numericInt64Value, 0)
        XCTAssertEqual(value("DisplayOnScreenTextureAnimation")?.numericInt64Value, 0)
        XCTAssertEqual(value("ShowParticles")?.numericInt64Value, 0)
        XCTAssertNil(value("FactorCalculationData"))

        let cleared = try CommandEffectNBT.applying(
            operation: .clear,
            selection: .single(strength),
            to: given.value
        )
        XCTAssertTrue(cleared.changed)
        XCTAssertNil(cleared.value.compoundValue(named: "ActiveEffects"))

        let all = try CommandEffectNBT.applying(
            operation: .give(duration: 100, amplifier: 0),
            selection: .all,
            to: root
        )
        guard case .list(.compound, let allEffects)? = all.value.compoundValue(named: "ActiveEffects") else {
            return XCTFail("ALL effects were not created")
        }
        XCTAssertEqual(allEffects.count, BedrockDataValueCatalog.statusEffects.count)

        let unchanged = try CommandEffectNBT.applying(
            operation: .clear,
            selection: .single(strength),
            to: root
        )
        XCTAssertFalse(unchanged.changed)
    }

    func testCommonEntityNBTTemplate() throws {
        let tags = BedrockEntityCommonNBT.tags(
            identifier: "minecraft:pig",
            position: BedrockWorldObjectPosition(x: 1.5, y: 64, z: -2.5),
            dimension: 0,
            uniqueID: 77
        )
        let root = NBTValue.compound(tags)
        XCTAssertEqual(root.int64Value(namedAny: ["UniqueID"]), 77)
        XCTAssertEqual(root.int64Value(namedAny: ["Air"]), 300)
        XCTAssertEqual(root.int64Value(namedAny: ["Persistent"]), 1)
        XCTAssertEqual(root.value(namedAny: ["Motion"])?.listValues?.count, 3)
        XCTAssertEqual(root.value(namedAny: ["Rotation"])?.listValues?.count, 2)
        XCTAssertEqual(root.int64Value(namedAny: ["IsAutonomous"]), 0)
        XCTAssertEqual(root.int64Value(namedAny: ["ShowBottom"]), 0)
        XCTAssertEqual(root.int64Value(namedAny: ["IsEating"]), 0)
        XCTAssertNil(root.value(namedAny: ["LinksTag"]))
        XCTAssertNil(root.value(namedAny: ["FireImmune"]))
        XCTAssertNil(root.value(namedAny: ["HasCollision"]))
        XCTAssertNil(root.value(namedAny: ["HasGravity"]))
        XCTAssertNil(root.value(namedAny: ["HasOwner"]))
        XCTAssertNil(root.value(namedAny: ["Age"]))
        XCTAssertEqual(root.value(namedAny: ["Tags"])?.listValues?.count, 0)
        XCTAssertEqual(BedrockEntityCommonNBT.identifier(in: root), "minecraft:pig")
        XCTAssertEqual(BedrockEntityCommonNBT.position(in: root)?.blockY, 64)
    }

    func testLegacySubChunkNumericBlockEditRoundTrip() throws {
        var raw = Data([2])
        raw.append(Data(repeating: 1, count: 4096))
        raw.append(Data(repeating: 0, count: 2048))
        raw.append(contentsOf: [0xaa, 0xbb])

        let decoded = try BedrockSubChunk.decode(raw, keyYIndex: 0)
        let changed = try decoded.replacingBlockState(
            x: 3,
            y: 4,
            z: 5,
            storageIndex: 0,
            with: BedrockBlockState(nbt: nil, legacyID: 5, legacyData: 2)
        )
        let encoded = try changed.encodePersistent()
        let roundTrip = try BedrockSubChunk.decode(encoded, keyYIndex: 0)
        let state = try XCTUnwrap(roundTrip.storages.first?.blockState(x: 3, y: 4, z: 5))

        XCTAssertEqual(state.legacyID, 5)
        XCTAssertEqual(state.legacyData, 2)
        XCTAssertEqual(state.name, "minecraft:planks")
        XCTAssertEqual(Data(encoded.suffix(2)), Data([0xaa, 0xbb]))
    }

}
