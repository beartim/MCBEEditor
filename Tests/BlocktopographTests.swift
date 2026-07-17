import XCTest
import UIKit
@testable import Blocktopograph

final class BlocktopographTests: XCTestCase {
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
        let batchType = "com.wzn.blocktopograph.nbt-tags-v1"
        let legacyType = "com.wzn.blocktopograph.nbt-tag"
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
        let line = "fill 0 0 0 60 200 16 minecraft:leaves 'String'\"old_leaf_type\"=\"oak\",'Byte'\"persistent_bit\"=\"0\",'Byte'\"update_bit\"=\"0\" minecraft:chest 'Int'\"facing_direction\"=\"3\""
        guard case .fill(let region, let layer0, let layer1) = try WorldCommandParser.parse(line) else {
            return XCTFail("fill was not parsed")
        }
        XCTAssertEqual(region.minimum.x, 0)
        XCTAssertEqual(region.maximum.y, 200)
        XCTAssertEqual(region.maximum.z, 16)
        XCTAssertEqual(layer0.name, "minecraft:leaves")
        XCTAssertEqual(layer0.states.count, 3)
        XCTAssertEqual(layer1.name, "minecraft:chest")
        XCTAssertEqual(layer1.states.count, 1)
        XCTAssertNoThrow(try WorldCommandParser.parse("clone 0 0 0 1 1 1 10 20 30"))
        XCTAssertNoThrow(try WorldCommandParser.parse("help clear"))
        XCTAssertThrowsError(try WorldCommandParser.parse("/help"))
        XCTAssertThrowsError(try WorldCommandParser.parse("fill 0 0 0 1 1 1 minecraft:stone NULL minecraft:air"))
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
