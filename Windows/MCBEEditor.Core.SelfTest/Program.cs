using MCBEEditor.Core.Chunk;
using MCBEEditor.Core.Entity;
using System.Buffers.Binary;
using System.Text;
using System.IO.Compression;
using MCBEEditor.Core.Nbt;
using MCBEEditor.Core.LevelDB;
using MCBEEditor.Core.World;

static void Assert(bool condition, string message)
{
    if (!condition) throw new Exception("SELFTEST FAILED: " + message);
}

var sample = new NbtDocument(
    "",
    new NbtCompoundValue([
        new NbtNamedTag("LevelName", new NbtStringValue("Windows 移植测试")),
        new NbtNamedTag("StorageVersion", new NbtIntValue(10)),
        new NbtNamedTag("RandomSeed", new NbtLongValue(-1234567890123456789)),
        new NbtNamedTag("Version", new NbtListValue(NbtTagType.Int, [
            new NbtIntValue(1), new NbtIntValue(26), new NbtIntValue(30), new NbtIntValue(0)
        ])),
        new NbtNamedTag("Bytes", new NbtByteArrayValue([0, 1, 2, 127, 128, 255])),
        new NbtNamedTag("Ints", new NbtIntArrayValue([-1, 0, 1, int.MaxValue, int.MinValue])),
        new NbtNamedTag("Longs", new NbtLongArrayValue([-1, 0, 1, long.MaxValue, long.MinValue]))
    ]));

var referenceVectors = new Dictionary<NbtEncoding, string>
{
    [NbtEncoding.LittleEndian] = "CgAACAkATGV2ZWxOYW1lFABXaW5kb3dzIOenu+akjea1i+ivlQMOAFN0b3JhZ2VWZXJzaW9uCgAAAAQKAFJhbmRvbVNlZWTrfhaCC+/d7gkHAFZlcnNpb24DBAAAAAEAAAAaAAAAHgAAAAAAAAAHBQBCeXRlcwYAAAAAAQJ/gP8LBABJbnRzBQAAAP////8AAAAAAQAAAP///38AAACADAUATG9uZ3MFAAAA//////////8AAAAAAAAAAAEAAAAAAAAA/////////38AAAAAAAAAgAA=",
    [NbtEncoding.BigEndian] = "CgAACAAJTGV2ZWxOYW1lABRXaW5kb3dzIOenu+akjea1i+ivlQMADlN0b3JhZ2VWZXJzaW9uAAAACgQAClJhbmRvbVNlZWTu3e8LghZ+6wkAB1ZlcnNpb24DAAAABAAAAAEAAAAaAAAAHgAAAAAHAAVCeXRlcwAAAAYAAQJ/gP8LAARJbnRzAAAABf////8AAAAAAAAAAX////+AAAAADAAFTG9uZ3MAAAAF//////////8AAAAAAAAAAAAAAAAAAAABf/////////+AAAAAAAAAAAA=",
    [NbtEncoding.LittleEndianVarInt] = "CgAICUxldmVsTmFtZRRXaW5kb3dzIOenu+akjea1i+ivlQMOU3RvcmFnZVZlcnNpb24UBApSYW5kb21TZWVkqYTM3o+9iKIiCQdWZXJzaW9uAwgCNDwABwVCeXRlcwwAAQJ/gP8LBEludHMKAQAC/v///w//////DwwFTG9uZ3MKAQAC/v//////////Af///////////wEA"
};

foreach (var pair in referenceVectors)
{
    var encoding = pair.Key;
    var encoded = BedrockNbtCodec.Encode(sample, encoding);
    Assert(Convert.ToBase64String(encoded) == pair.Value, $"{encoding}: must match Swift reference vector");

    var decoded = BedrockNbtCodec.Decode(encoded, encoding);
    Assert(decoded.Root is NbtCompoundValue, $"{encoding}: root type");
    Assert(decoded.Root.StringValue("LevelName") == "Windows 移植测试", $"{encoding}: string roundtrip");
    Assert(decoded.Root.CompoundValue("RandomSeed")?.IntegerValue() == -1234567890123456789, $"{encoding}: long roundtrip");
    var encodedAgain = BedrockNbtCodec.Encode(decoded, encoding);
    Assert(encoded.SequenceEqual(encodedAgain), $"{encoding}: byte-identical roundtrip");
}

var invalidUtf8 = new byte[] { 0xFF, 0xFE, 0x80, 0x41 };
var preserved = NbtRawStringCodec.Decode(invalidUtf8);
Assert(NbtRawStringCodec.TryRawBytes(preserved, out var recovered), "raw string marker");
Assert(recovered.SequenceEqual(invalidUtf8), "raw string lossless roundtrip");


Assert(new NbtDoubleValue(-1.75).IntegerValue() == -1, "floating integer truncation");
foreach (var invalid in new[] { double.NaN, double.PositiveInfinity, double.NegativeInfinity, (double)long.MaxValue, 1e100 })
    Assert(new NbtDoubleValue(invalid).IntegerValue() is null, "invalid floating integer must be rejected");

Console.WriteLine("MCBEEditor.Core self-test passed; all Swift parity vectors matched.");

// Bedrock DB key parity.
var overworldSubKey = new BedrockDbKey(new ChunkPosition(-12, 34, 0), ChunkRecordType.SubChunk, -4).Encode();
Assert(overworldSubKey.Length == 10, "overworld SubChunk key length");
Assert(Convert.ToHexString(overworldSubKey) == "F4FFFFFF220000002FFC", "overworld SubChunk key Swift parity bytes");
Assert(BedrockDbKey.TryParse(overworldSubKey, out var parsedOverworld), "parse overworld SubChunk key");
Assert(parsedOverworld.Position == new ChunkPosition(-12, 34, 0), "overworld coordinates");
Assert(parsedOverworld.RecordType == ChunkRecordType.SubChunk && parsedOverworld.SubChunkIndex == -4, "overworld SubChunk suffix");

var netherKey = new BedrockDbKey(new ChunkPosition(7, -9, 1), ChunkRecordType.Version, null).Encode();
Assert(netherKey.Length == 13, "dimension-aware key length");
Assert(Convert.ToHexString(netherKey) == "07000000F7FFFFFF010000002C", "nether Version key Swift parity bytes");
Assert(BedrockDbKey.TryParse(netherKey, out var parsedNether) && parsedNether.Position.Dimension == 1, "parse nether key");
Assert(BedrockRawChunkKey.Matches(netherKey, new ChunkPosition(7, -9, 1)), "raw chunk prefix matcher");
Assert(!BedrockRawChunkKey.Matches(netherKey, new ChunkPosition(7, -9, 0)), "raw chunk matcher dimension isolation");

// SubChunk v0-v9 persistent codec.
var legacy = BedrockSubChunk.EmptyLegacy(0, 0);
var legacyRaw = legacy.EncodePersistent();
var legacyDecoded = BedrockSubChunk.Decode(legacyRaw, 0);
Assert(legacyDecoded.Version == 0 && legacyDecoded.IsLegacyNumeric, "v0 decode");
Assert(legacyDecoded.Storages.Count == 1 && legacyDecoded.Storages[0].Indices.Length == 4096, "v0 storage geometry");
Assert(legacyDecoded.EncodePersistent().SequenceEqual(legacyRaw), "v0 byte-identical all-air roundtrip");

var air = BedrockBlockState.EditableAir();
var modernV1 = new BedrockSubChunk(1, 3, [SubChunkStorage.AirFilled(air)], []);
var modernV1Raw = modernV1.EncodePersistent();
var modernV1Decoded = BedrockSubChunk.Decode(modernV1Raw, 3);
Assert(modernV1Decoded.Version == 1 && modernV1Decoded.Storages.Count == 1, "v1 bits=0 decode");
Assert(modernV1Decoded.Storages[0].Palette[0].Name == "minecraft:air", "v1 palette NBT");
Assert(modernV1Decoded.EncodePersistent().SequenceEqual(modernV1Raw), "v1 roundtrip");

var v8 = new BedrockSubChunk(8, 2, [SubChunkStorage.AirFilled(air), SubChunkStorage.AirFilled(air)], []);
var v8Decoded = BedrockSubChunk.Decode(v8.EncodePersistent(), 2);
Assert(v8Decoded.Version == 8 && v8Decoded.Storages.Count == 2, "v8 multi-storage");

var manyStorages = Enumerable.Range(0, 20).Select(_ => SubChunkStorage.AirFilled(air)).ToArray();
var v9 = new BedrockSubChunk(9, -4, manyStorages, []);
var v9Raw = v9.EncodePersistent();
var v9Decoded = BedrockSubChunk.Decode(v9Raw, 99);
Assert(v9Decoded.Version == 9 && v9Decoded.YIndex == -4, "v9 embedded Y overrides key Y");
Assert(v9Decoded.Storages.Count == 20, "v9 must preserve UInt8 storage count above old artificial 16 limit");
Assert(v9Decoded.EncodePersistent().SequenceEqual(v9Raw), "v9 roundtrip");

var sentinel = new BedrockSubChunk(9, -1, [
    new SubChunkStorage(127, [air], new ushort[4096], SubChunkStoragePersistentKind.EmptySentinel127)
], []);
var sentinelRaw = sentinel.EncodePersistent();
var sentinelDecoded = BedrockSubChunk.Decode(sentinelRaw, -1);
Assert(sentinelDecoded.Storages[0].PersistentKind == SubChunkStoragePersistentKind.EmptySentinel127, "BPB=127 sentinel decode");
Assert(sentinelDecoded.EncodePersistent().SequenceEqual(sentinelRaw), "BPB=127 sentinel roundtrip");

var futureRaw = new byte[] { 10, 0xAA, 0xBB, 0xCC };
var future = BedrockSubChunk.Decode(futureRaw, 5);
Assert(future.IsRawPreservedUnknownVersion, "unknown SubChunk version raw preservation");
Assert(future.EncodePersistent().SequenceEqual(futureRaw), "unknown SubChunk byte preservation");

var legacyTerrainRaw = BedrockLegacyTerrain.EmptyPersistentData;
var legacyTerrain = BedrockLegacyTerrain.Decode(legacyTerrainRaw);
Assert(legacyTerrain.SubChunk(7).Storages[0].BlockState(0, 0, 0)?.LegacyId == 0, "LegacyTerrain virtual slice");
Assert(legacyTerrain.EncodePersistent().SequenceEqual(legacyTerrainRaw), "LegacyTerrain byte-identical roundtrip");

// chunk enumeration/query behavior without requiring the native DLL.
using (var memoryDb = new SelfTestWorldDatabase())
{
    var ow = new ChunkPosition(1, 2, 0);
    var nether = new ChunkPosition(-3, 4, 1);
    memoryDb.Put(new BedrockDbKey(ow, ChunkRecordType.Version, null).Encode(), [40]);
    memoryDb.Put(BedrockDbKey.SubChunk(ow.X, ow.Z, ow.Dimension, 0), modernV1Raw);
    memoryDb.Put(BedrockDbKey.SubChunk(ow.X, ow.Z, ow.Dimension, 1), modernV1Raw);
    memoryDb.Put(BedrockChunkStore.ActorDigestKeys(ow)[0], new byte[8]);
    memoryDb.Put(BedrockDbKey.SubChunk(nether.X, nether.Z, nether.Dimension, -4), v9Raw);
    memoryDb.Put(new BedrockDbKey(nether, ChunkRecordType.BlockEntity, null).Encode(), [10, 0, 0]);

    var chunks = new BedrockChunkStore(memoryDb).ListChunks();
    Assert(chunks.Count == 2, "chunk list count");
    var owSummary = chunks.Single(item => item.Position == ow);
    Assert(owSummary.SubChunkCount == 2 && owSummary.HasActorDigest, "overworld chunk summary");
    var netherSummary = chunks.Single(item => item.Position == nether);
    Assert(netherSummary.SubChunkCount == 1 && netherSummary.HasBlockEntities, "nether chunk summary");
    var owQueryText = new BedrockChunkStore(memoryDb).QueryText(owSummary);
    Assert(owQueryText.Contains($"IsSlimeChunk={BedrockSlimeChunk.IsSlimeChunk(ow.X, ow.Z)}", StringComparison.Ordinal)
           && owQueryText.EndsWith("Ticking=False", StringComparison.Ordinal),
        "chunk query appends IsSlimeChunk=True/False and Ticking=True/False");
}

// destructive chunk operations must delete unknown raw tags and modern actors atomically.
using (var mutationDb = new SelfTestWorldDatabase())
{
    var position = new ChunkPosition(20, 20, 0);
    mutationDb.Put(new BedrockDbKey(position, ChunkRecordType.Version, null).Encode(), [40]);
    mutationDb.Put(BedrockDbKey.SubChunk(position.X, position.Z, 0, 0), modernV1Raw);
    mutationDb.Put(new BedrockDbKey(position, ChunkRecordType.BlockEntity, null).Encode(), [1, 2, 3]);
    var digestKey = BedrockChunkStore.ActorDigestKeys(position)[0];
    var rawActorId = new byte[] { 1, 2, 3, 4, 5, 6, 7, 8 };
    mutationDb.Put(digestKey, rawActorId);
    var actorKey = System.Text.Encoding.ASCII.GetBytes("actorprefix").Concat(rawActorId).ToArray();
    mutationDb.Put(actorKey, [10, 0, 0]);

    var store = new BedrockChunkStore(mutationDb);
    var clear = store.ClearChunk(position);
    Assert(clear.DeletedChunkRecordCount == 3, "chunk empty deletes all old raw chunk records");
    Assert(clear.DeletedDigestCount == 1 && clear.DeletedActorCount == 1, "chunk empty deletes digp and actorprefix");
    Assert(mutationDb.Get(digestKey) is null && mutationDb.Get(actorKey) is null, "actor records removed");
    Assert(mutationDb.Get(new BedrockDbKey(position, ChunkRecordType.Version, null).Encode()) is not null, "chunk empty writes version");
    var finalized = mutationDb.Get(new BedrockDbKey(position, ChunkRecordType.FinalizedState, null).Encode());
    Assert(finalized is { Length: >= 4 } && System.Buffers.Binary.BinaryPrimitives.ReadInt32LittleEndian(finalized) == 2,
        "chunk empty writes FinalizedState=2");
}

using (var regenerateDb = new SelfTestWorldDatabase())
{
    var position = new ChunkPosition(22, 22, 2);
    regenerateDb.Put(new BedrockDbKey(position, ChunkRecordType.Version, null).Encode(), [40]);
    // Deliberately unknown tag with a legal raw chunk suffix length.
    var unknown = BedrockRawChunkKey.Prefixes(position)[0].Concat(new byte[] { 0x99, 0x12 }).ToArray();
    regenerateDb.Put(unknown, [0xAA]);
    var result = new BedrockChunkStore(regenerateDb).RegenerateChunk(position);
    Assert(result.DeletedChunkRecordCount == 2, "regenerate deletes known and unknown raw records");
    Assert(regenerateDb.Get(unknown) is null, "unknown raw chunk tag removed");
    Assert(new BedrockChunkStore(regenerateDb).SummaryAt(position).RecordCount == 0, "regenerated chunk becomes ungenerated");
}

using (var legacyDb = new SelfTestWorldDatabase())
{
    var position = new ChunkPosition(3, -7, 0);
    legacyDb.Put(new BedrockDbKey(position, ChunkRecordType.LegacyTerrain, null).Encode(), BedrockLegacyTerrain.EmptyPersistentData);
    var result = new BedrockChunkStore(legacyDb).ClearChunk(position);
    Assert(result.CreatedMetadataRecordCount == 1 && result.VersionRecordType == ChunkRecordType.LegacyTerrain,
        "legacy terrain world stays in 0x30 terrain family");
    Assert(legacyDb.Get(new BedrockDbKey(position, ChunkRecordType.LegacyTerrain, null).Encode())?.Length == BedrockLegacyTerrain.PersistentByteCount,
        "legacy empty terrain length");
}

var queryCommand = ChunkCommandParser.Parse("chunk query overworld -1 2");
Assert(queryCommand.Kind == ChunkCommandKind.Query && queryCommand.Dimension == 0 && queryCommand.X == -1 && queryCommand.Z == 2,
    "chunk query parser");
var regenerateCommand = ChunkCommandParser.Parse("chunk regenerate the_end 0 0");
Assert(regenerateCommand.IsDestructive && regenerateCommand.Dimension == 2, "chunk regenerate parser");

using (var browserDb = new SelfTestWorldDatabase())
{
    var key = new BedrockDbKey(new ChunkPosition(9, 10, 1), ChunkRecordType.Version, null).Encode();
    browserDb.Put(key, [40]);
    var rows = LevelDbBrowserService.Browse(browserDb, Convert.ToHexString(key.AsSpan(0, 4)), 10);
    Assert(rows.Count == 1 && rows[0].KeyDescription.Contains("Version", StringComparison.Ordinal), "LevelDB browser prefix filter");
}

Console.WriteLine("MCBEEditor.Core self-test passed; write safety, raw chunk deletion, actor cleanup, commands and DB browser behavior matched expectations.");

// top-down Y-surface rendering and map colour parity.
static BedrockBlockState NamedState(string name, params NbtNamedTag[] states)
    => new(new NbtCompoundValue([
        new NbtNamedTag("name", new NbtStringValue(name)),
        new NbtNamedTag("states", new NbtCompoundValue(states)),
        new NbtNamedTag("version", new NbtIntValue(BedrockBlockState.DefaultPaletteVersion))
    ]), null, null);

Assert(BedrockBlockMapColorCatalog.RgbHex("minecraft:sun_flower") == 0xE2B93B, "sun_flower must stay yellow");
Assert(BedrockBlockMapColorCatalog.RgbHex("minecraft:soul_sand") == 0x544034, "soul sand map colour");
Assert(BedrockBlockMapColorCatalog.RgbHex("minecraft:waterlily") == 0x347A38, "waterlily must not be treated as water");
Assert(BedrockBlockMapColorCatalog.IsWater("minecraft:water"), "water exact semantic");
Assert(!BedrockBlockMapColorCatalog.IsWater("minecraft:underwater_torch"), "underwater torch is not water");
Assert(BedrockSurfaceRegionRenderer.FloorDiv(-1, 16) == -1, "negative block -1 belongs to chunk -1");
Assert(BedrockSurfaceRegionRenderer.FloorDiv(-16, 16) == -1, "negative exact chunk boundary");
Assert(BedrockSurfaceRegionRenderer.FloorDiv(-17, 16) == -2, "negative block -17 belongs to chunk -2");
Assert(BedrockSurfaceRegionRenderer.IsUngeneratedStripe(0, 0) == BedrockSurfaceRegionRenderer.IsUngeneratedStripe(16, 16), "ungenerated stripe must stay globally aligned");
Assert(BedrockSurfaceRegionRenderer.IsUngeneratedStripe(15, 7) && BedrockSurfaceRegionRenderer.IsUngeneratedStripe(16, 8), "ungenerated diagonal continues across adjacent chunk boundary");

using (var mapDb = new SelfTestWorldDatabase())
{
    var position = new ChunkPosition(-1, 2, 0);
    var stone = NamedState("minecraft:stone");
    var water = NamedState("minecraft:water");
    var airState = BedrockBlockState.EditableAir();
    var stoneStorage = new SubChunkStorage(0, [stone], new ushort[4096]);
    var airStorage = SubChunkStorage.AirFilled(airState);
    var waterStorage = new SubChunkStorage(0, [water], new ushort[4096]);
    var low = new BedrockSubChunk(9, 0, [stoneStorage], []);
    var high = new BedrockSubChunk(9, 1, [airStorage, waterStorage], []);
    mapDb.Put(new BedrockDbKey(position, ChunkRecordType.Version, null).Encode(), [40]);
    mapDb.Put(BedrockDbKey.SubChunk(position.X, position.Z, position.Dimension, 0), low.EncodePersistent());
    mapDb.Put(BedrockDbKey.SubChunk(position.X, position.Z, position.Dimension, 1), high.EncodePersistent());

    var surface = new BedrockSurfaceRenderer(mapDb).RenderChunk(position);
    Assert(surface.Generated, "surface chunk must be generated");
    Assert(surface.DecodedSubChunks == 2, "surface renderer decodes both subchunks");
    Assert(surface.BlockNames.All(name => name == "minecraft:water"), "second storage non-air state must win over primary air");
    Assert(surface.Heights.All(height => height == 31), "top visible block height from v9 Y index");
    Assert(surface.Rgb.All(color => color == 0x337CCB), "surface water colour");

    var region = new BedrockSurfaceRegionRenderer(mapDb).Render(0, -1, 32, 1, drawChunkGrid: false);
    Assert(region.Width == 48 && region.Height == 48, "radius 1 region geometry");
    Assert(region.OriginBlockX == -32 && region.OriginBlockZ == 16, "negative center region origin");
    Assert(region.GeneratedChunkCount == 1 && region.MissingChunkCount == 8, "region generated/missing chunk counts");
    var targetX = -16 - region.OriginBlockX;
    var targetZ = 32 - region.OriginBlockZ;
    var targetIndex = region.Index(targetX, targetZ);
    Assert(region.Generated[targetIndex] && region.BlockNames[targetIndex] == "minecraft:water", "region copies rendered chunk cells");
}

var redWool = NamedState("minecraft:wool", new NbtNamedTag("color", new NbtStringValue("red")));
Assert(BedrockBlockMapColorCatalog.VariantIdentifier(redWool) == "minecraft:red_wool", "historical palette state resolves render-only colour variant");
Assert(BedrockBlockMapColorCatalog.ColorFor(redWool) == 0xB02E26, "historical red wool colour");

BedrockBlockMapColorCatalog.OverrideProvider = identifier => identifier == "minecraft:stone" ? 0x123456u : null;
Assert(BedrockBlockMapColorCatalog.ColorFor(NamedState("minecraft:stone")) == 0x123456, "external colour override uses original identifier");
BedrockBlockMapColorCatalog.OverrideProvider = null;

Console.WriteLine("MCBEEditor.Core self-test passed; Y-surface rendering, negative coordinates, multi-storage selection, ungenerated texture and core block colours matched expectations.");


// X/Y/Z map modes and orthographic cross-section projection.
Assert(BedrockBlockMapColorCatalog.IsHighlightedOre("minecraft:diamond_ore"), "diamond ore is highlighted");
Assert(BedrockBlockMapColorCatalog.IsHighlightedOre("minecraft:ancient_debris"), "ancient debris is highlighted");
Assert(!BedrockBlockMapColorCatalog.IsHighlightedOre("minecraft:stone"), "stone is not highlighted ore");
Assert(BedrockBlockMapColorCatalog.OreColor("minecraft:diamond_ore") == 0x33EBEB, "diamond ore highlight colour");

using (var crossDb = new SelfTestWorldDatabase())
{
    var position = new ChunkPosition(0, 0, 0);
    var crossAir = BedrockBlockState.EditableAir();
    var stone = NamedState("minecraft:stone");
    var diamond = NamedState("minecraft:diamond_ore");
    var palette = new BedrockBlockState[] { crossAir, stone, diamond };
    var indices = new ushort[4096];
    indices[(2 << 8) | (5 << 4) | 8] = 1; // exact X=2 plane: stone
    indices[(0 << 8) | (5 << 4) | 8] = 2; // x+ view: two blocks behind plane
    indices[(4 << 8) | (5 << 4) | 8] = 2; // x- view: two blocks behind plane
    var storage = new SubChunkStorage(2, palette, indices);
    var subChunk = new BedrockSubChunk(9, 0, [storage], []);
    crossDb.Put(new BedrockDbKey(position, ChunkRecordType.Version, null).Encode(), [40]);
    crossDb.Put(BedrockDbKey.SubChunk(0, 0, 0, 0), subChunk.EncodePersistent());

    var normal = new BedrockCrossSectionRenderer(crossDb).Render(
        BedrockMapAxis.X, fixedX: 2, fixedZ: 5, centerY: 8, sideBlocks: 16,
        dimension: 0, mode: BedrockMapRenderMode.Surface, drawSubChunkGrid: false,
        drawBuildHeightLimits: false, projectionDepth: 128);
    var normalColumn = 5 - normal.OriginHorizontal;
    var normalRow = normal.MaximumY - 8;
    var normalIndex = normal.Index(normalColumn, normalRow);
    Assert(normal.Generated[normalIndex], "X section plane is generated");
    Assert(normal.BlockNames[normalIndex] == "minecraft:stone", "normal X section picks nearest non-air block");
    Assert(normal.BlockX[normalIndex] == 2 && normal.BlockY[normalIndex] == 8 && normal.BlockZ[normalIndex] == 5,
        "normal X section stores projected block coordinates");

    var mineral = new BedrockCrossSectionRenderer(crossDb).Render(
        BedrockMapAxis.X, fixedX: 2, fixedZ: 5, centerY: 8, sideBlocks: 16,
        dimension: 0, mode: BedrockMapRenderMode.Minerals, drawSubChunkGrid: false,
        drawBuildHeightLimits: false, projectionDepth: 129);
    var mineralIndex = mineral.Index(5 - mineral.OriginHorizontal, mineral.MaximumY - 8);
    Assert(mineral.ProjectionDepth == 129, "X/Z mineral projection includes current coordinate through -128");
    Assert(mineral.BlockNames[mineralIndex] == "minecraft:diamond_ore", "mineral section skips stone and finds ore behind plane");
    Assert(mineral.BlockX[mineralIndex] == 0, "mineral section chooses greatest matching X not beyond the current plane");
    Assert(mineral.Rgb[mineralIndex] == BedrockBlockMapColorCatalog.OreColor("minecraft:diamond_ore"), "mineral colour applied");

    var oppositeMineral = new BedrockCrossSectionRenderer(crossDb).Render(
        BedrockMapAxis.X, fixedX: 2, fixedZ: 5, centerY: 8, sideBlocks: 16,
        dimension: 0, mode: BedrockMapRenderMode.Minerals, drawSubChunkGrid: false,
        drawBuildHeightLimits: false, projectionDepth: 129,
        projectionDirection: BedrockProjectionDirection.NegativeToPositive);
    var oppositeIndex = oppositeMineral.Index(5 - oppositeMineral.OriginHorizontal, oppositeMineral.MaximumY - 8);
    Assert(oppositeMineral.BlockX[oppositeIndex] == 4, "opposite X projection scans toward positive coordinates");

    var missingIndex = normal.Index(-2 - normal.OriginHorizontal, normal.MaximumY - 8);
    Assert(!normal.Generated[missingIndex] && normal.BlockNames[missingIndex] == "minecraft:air",
        "X/Z projection remains air when no generated block exists anywhere along that projected column");

    var yMinerals = new BedrockSurfaceRenderer(crossDb).RenderChunk(position, BedrockMapRenderMode.Minerals);
    Assert(yMinerals.BlockNames[yMinerals.Index(0, 5)] == "minecraft:diamond_ore", "Y mineral map finds highest ore");
    Assert(yMinerals.Rgb[yMinerals.Index(0, 5)] == BedrockBlockMapColorCatalog.OreColor("minecraft:diamond_ore"), "Y mineral colour");
}

using (var directionDb = new SelfTestWorldDatabase())
{
    var position = new ChunkPosition(0, 0, 0);
    var dirAir = BedrockBlockState.EditableAir();
    var dirStone = NamedState("minecraft:stone");
    var dirDiamond = NamedState("minecraft:diamond_ore");
    var palette = new BedrockBlockState[] { dirAir, dirStone, dirDiamond };
    var indices = new ushort[4096];
    indices[(0 << 8) | (0 << 4) | 1] = 1;
    indices[(0 << 8) | (0 << 4) | 14] = 2;
    var storage = new SubChunkStorage(2, palette, indices);
    directionDb.Put(new BedrockDbKey(position, ChunkRecordType.Version, null).Encode(), [40]);
    directionDb.Put(BedrockDbKey.SubChunk(0, 0, 0, 0), new BedrockSubChunk(9, 0, [storage], []).EncodePersistent());

    var fromAbove = new BedrockSurfaceRenderer(directionDb).RenderChunk(position, BedrockMapRenderMode.Surface, BedrockProjectionDirection.PositiveToNegative);
    var fromBelow = new BedrockSurfaceRenderer(directionDb).RenderChunk(position, BedrockMapRenderMode.Surface, BedrockProjectionDirection.NegativeToPositive);
    Assert(fromAbove.BlockNames[fromAbove.Index(0, 0)] == "minecraft:diamond_ore", "y+ projection scans from high Y to low Y");
    Assert(fromBelow.BlockNames[fromBelow.Index(0, 0)] == "minecraft:stone", "y- projection scans from low Y to high Y");
}

using (var emptyCrossDb = new SelfTestWorldDatabase())
{
    var limits = new BedrockCrossSectionRenderer(emptyCrossDb).Render(
        BedrockMapAxis.Z, fixedX: 0, fixedZ: 0, centerY: 64, sideBlocks: 144,
        dimension: 1, mode: BedrockMapRenderMode.Surface, drawSubChunkGrid: false,
        drawBuildHeightLimits: true, projectionDepth: 1);
    Assert(limits.Rgb.Count(color => color == 0xE53935) > 0, "Nether building-height limits draw red dashed lines");
}


// players, modern actors, block entities and in-place object NBT saving.
using (var objectDb = new SelfTestWorldDatabase())
{
    var playerDoc = new NbtDocument("", new NbtCompoundValue([
        new NbtNamedTag("PlayerName", new NbtStringValue("Local Tester")),
        new NbtNamedTag("UniqueID", new NbtLongValue(777)),
        new NbtNamedTag("DimensionId", new NbtIntValue(0)),
        new NbtNamedTag("Pos", new NbtListValue(NbtTagType.Float, [new NbtFloatValue(8.5f), new NbtFloatValue(65f), new NbtFloatValue(9.5f)]))
    ]));
    objectDb.Put(Encoding.UTF8.GetBytes("~local_player"), BedrockNbtCodec.Encode(playerDoc, NbtEncoding.LittleEndian));
    var playerStore = new PlayerNbtStore(objectDb);
    var players = playerStore.Records();
    Assert(players.Count == 1 && players[0].IsLocal, " local player scan");
    var playerPosition = playerStore.CurrentPosition(players[0]);
    Assert(playerPosition is not null && playerPosition.BlockX == 8 && playerPosition.BlockY == 65 && playerPosition.BlockZ == 9,
        " player position decode");

    var actorReference = new byte[8];
    BinaryPrimitives.WriteInt64LittleEndian(actorReference, 123456789);
    var actorKeyPrefix = Encoding.ASCII.GetBytes("actorprefix");
    var actorKey = actorKeyPrefix.Concat(actorReference).ToArray();
    var digestPrefix = Encoding.ASCII.GetBytes("digp");
    var digestKey = new byte[digestPrefix.Length + 8];
    digestPrefix.CopyTo(digestKey, 0);
    BinaryPrimitives.WriteInt32LittleEndian(digestKey.AsSpan(digestPrefix.Length, 4), 0);
    BinaryPrimitives.WriteInt32LittleEndian(digestKey.AsSpan(digestPrefix.Length + 4, 4), 0);

    var actorDoc = new NbtDocument("", new NbtCompoundValue([
        new NbtNamedTag("identifier", new NbtStringValue("minecraft:zombie")),
        new NbtNamedTag("UniqueID", new NbtLongValue(987654321)),
        new NbtNamedTag("DimensionId", new NbtIntValue(0)),
        new NbtNamedTag("Pos", new NbtListValue(NbtTagType.Float, [new NbtFloatValue(2.25f), new NbtFloatValue(64f), new NbtFloatValue(3.75f)]))
    ]));
    objectDb.Put(digestKey, actorReference);
    objectDb.Put(actorKey, ConsecutiveNbtCodec.Encode([new ConsecutiveNbtRecord(actorDoc, Array.Empty<byte>(), NbtEncoding.LittleEndian)]));

    var blockEntityDoc = new NbtDocument("", new NbtCompoundValue([
        new NbtNamedTag("id", new NbtStringValue("Chest")),
        new NbtNamedTag("x", new NbtIntValue(4)),
        new NbtNamedTag("y", new NbtIntValue(63)),
        new NbtNamedTag("z", new NbtIntValue(5))
    ]));
    var blockEntityKey = new BedrockDbKey(new ChunkPosition(0, 0, 0), ChunkRecordType.BlockEntity, null).Encode();
    objectDb.Put(blockEntityKey, ConsecutiveNbtCodec.Encode([new ConsecutiveNbtRecord(blockEntityDoc, Array.Empty<byte>(), NbtEncoding.LittleEndian)]));

    var scan = new BedrockWorldObjectScanner(objectDb).ScanRegion(0, 0, 0, 0, includeEntities: true, includeBlockEntities: true);
    Assert(scan.Objects.Count == 2, " actor + block entity scan count");
    var actor = scan.Objects.Single(item => item.Kind == BedrockWorldObjectKind.Entity);
    Assert(actor.Identifier == "minecraft:zombie" && actor.UniqueId == 987654321, " modern actor identity uses NBT UniqueID");
    Assert(actor.Storage is ModernActorStorage modernStorage && modernStorage.ActorStorageReference!.SequenceEqual(actorReference),
        " actor storage reference kept separate from UniqueID");
    var blockEntity = scan.Objects.Single(item => item.Kind == BedrockWorldObjectKind.BlockEntity);
    var blockEntityPosition = blockEntity.Position;
    Assert(blockEntityPosition is not null && blockEntityPosition.BlockX == 4 && blockEntityPosition.BlockY == 63 && blockEntityPosition.BlockZ == 5,
        " block entity coordinates");

    var editedActor = new NbtDocument("", new NbtCompoundValue([
        new NbtNamedTag("identifier", new NbtStringValue("minecraft:zombie")),
        new NbtNamedTag("UniqueID", new NbtLongValue(987654321)),
        new NbtNamedTag("DimensionId", new NbtIntValue(0)),
        new NbtNamedTag("Pos", new NbtListValue(NbtTagType.Float, [new NbtFloatValue(2.25f), new NbtFloatValue(64f), new NbtFloatValue(3.75f)])),
        new NbtNamedTag("CustomName", new NbtStringValue("Windows Actor"))
    ]));
    new BedrockWorldObjectNbtStore(objectDb).SaveInPlace(actor, editedActor);
    var rescanned = new BedrockWorldObjectScanner(objectDb).ScanRegion(0, 0, 0, 0, includeEntities: true, includeBlockEntities: false);
    Assert(rescanned.Objects.Single().CustomName == "Windows Actor", " in-place actor NBT save");

}

Console.WriteLine("MCBEEditor.Core self-test passed; players, modern actor digp/actorprefix, block entities and safe in-place NBT saving matched expectations.");

// Full NBT tools plus safe entity ownership relocation.
using (var entityMoveDb = new SelfTestWorldDatabase())
{
    var actorReference = new byte[8];
    BinaryPrimitives.WriteInt64LittleEndian(actorReference, 0x112233445566778);
    var actorKey = Encoding.ASCII.GetBytes("actorprefix").Concat(actorReference).ToArray();
    var oldDigestKey = new byte[12];
    Encoding.ASCII.GetBytes("digp").CopyTo(oldDigestKey, 0);
    // overworld chunk 0,0 uses the canonical 4 + 8 byte key.
    var actorDoc = new NbtDocument("", new NbtCompoundValue([
        new NbtNamedTag("identifier", new NbtStringValue("minecraft:skeleton")),
        new NbtNamedTag("UniqueID", new NbtLongValue(456789)),
        new NbtNamedTag("DimensionId", new NbtIntValue(0)),
        new NbtNamedTag("Pos", new NbtListValue(NbtTagType.Float, [new NbtFloatValue(1f), new NbtFloatValue(70f), new NbtFloatValue(1f)]))
    ]));
    entityMoveDb.Put(oldDigestKey, actorReference);
    entityMoveDb.Put(actorKey, BedrockNbtCodec.Encode(actorDoc, NbtEncoding.LittleEndian));
    var original = new BedrockWorldObjectScanner(entityMoveDb).ScanRegion(0, 0, 0, 0, true, false).Objects.Single();

    var moved = new NbtDocument("", new NbtCompoundValue([
        new NbtNamedTag("identifier", new NbtStringValue("minecraft:skeleton")),
        new NbtNamedTag("UniqueID", new NbtLongValue(456789)),
        new NbtNamedTag("DimensionId", new NbtIntValue(1)),
        new NbtNamedTag("Pos", new NbtListValue(NbtTagType.Float, [new NbtFloatValue(40f), new NbtFloatValue(70f), new NbtFloatValue(1f)]))
    ]));
    new BedrockWorldObjectNbtStore(entityMoveDb).Save(original, moved);
    Assert(entityMoveDb.Get(oldDigestKey) is null, "Entity move removes empty source digp");
    var newDigestKey = new byte[16];
    Encoding.ASCII.GetBytes("digp").CopyTo(newDigestKey, 0);
    BinaryPrimitives.WriteInt32LittleEndian(newDigestKey.AsSpan(4, 4), 2);
    BinaryPrimitives.WriteInt32LittleEndian(newDigestKey.AsSpan(8, 4), 0);
    BinaryPrimitives.WriteInt32LittleEndian(newDigestKey.AsSpan(12, 4), 1);
    Assert(entityMoveDb.Get(newDigestKey)?.SequenceEqual(actorReference) == true, "Entity move appends actor reference to destination digp");
    var movedScan = new BedrockWorldObjectScanner(entityMoveDb).ScanRegion(2, 0, 1, 0, true, false);
    Assert(movedScan.Objects.Count == 1 && movedScan.Objects[0].Position?.BlockX == 40 && movedScan.Objects[0].Dimension == 1,
        " modern actor moves across chunk and dimension");

    var changedId = new NbtDocument("", new NbtCompoundValue([
        new NbtNamedTag("identifier", new NbtStringValue("minecraft:skeleton")),
        new NbtNamedTag("UniqueID", new NbtLongValue(456790)),
        new NbtNamedTag("DimensionId", new NbtIntValue(1)),
        new NbtNamedTag("Pos", new NbtListValue(NbtTagType.Float, [new NbtFloatValue(40f), new NbtFloatValue(70f), new NbtFloatValue(1f)]))
    ]));
    var uniqueIdRejected = false;
    try { new BedrockWorldObjectNbtStore(entityMoveDb).Save(movedScan.Objects[0], changedId); }
    catch (InvalidOperationException) { uniqueIdRejected = true; }
    Assert(uniqueIdRejected, " still protects entity UniqueID");
}

using (var legacyMoveDb = new SelfTestWorldDatabase())
{
    var oldKey = new BedrockDbKey(new ChunkPosition(0, 0, 0), ChunkRecordType.Entity, null).Encode();
    var legacyDoc = new NbtDocument("", new NbtCompoundValue([
        new NbtNamedTag("identifier", new NbtStringValue("minecraft:cow")),
        new NbtNamedTag("UniqueID", new NbtLongValue(222)),
        new NbtNamedTag("DimensionId", new NbtIntValue(0)),
        new NbtNamedTag("Pos", new NbtListValue(NbtTagType.Float, [new NbtFloatValue(1f), new NbtFloatValue(64f), new NbtFloatValue(1f)]))
    ]));
    legacyMoveDb.Put(oldKey, BedrockNbtCodec.Encode(legacyDoc, NbtEncoding.LittleEndian));
    var legacyEntity = new BedrockWorldObjectScanner(legacyMoveDb).ScanRegion(0, 0, 0, 0, true, false).Objects.Single();
    var movedLegacyDoc = new NbtDocument("", new NbtCompoundValue([
        new NbtNamedTag("identifier", new NbtStringValue("minecraft:cow")),
        new NbtNamedTag("UniqueID", new NbtLongValue(222)),
        new NbtNamedTag("DimensionId", new NbtIntValue(2)),
        new NbtNamedTag("Pos", new NbtListValue(NbtTagType.Float, [new NbtFloatValue(33f), new NbtFloatValue(70f), new NbtFloatValue(-17f)]))
    ]));
    new BedrockWorldObjectNbtStore(legacyMoveDb).Save(legacyEntity, movedLegacyDoc);
    Assert(legacyMoveDb.Get(oldKey) is null, " removes empty legacy Entity source record");
    var newKey = new BedrockDbKey(new ChunkPosition(2, -2, 2), ChunkRecordType.Entity, null).Encode();
    Assert(legacyMoveDb.Get(newKey) is not null, " writes legacy Entity destination record");
    var movedLegacy = new BedrockWorldObjectScanner(legacyMoveDb).ScanRegion(2, -2, 2, 0, true, false).Objects.Single();
    Assert(movedLegacy.Position?.BlockX == 33 && movedLegacy.Position.BlockZ == -17 && movedLegacy.Dimension == 2,
        " legacy Entity moves across chunk and dimension");
}

var searchDocument = new NbtDocument("", new NbtCompoundValue([
    new NbtNamedTag("targetName", new NbtStringValue("alpha")),
    new NbtNamedTag("other", new NbtStringValue("target value")),
    new NbtNamedTag("number", new NbtIntValue(42))
]));
var searchResults = NbtDocumentTools.Search(searchDocument, "target");
Assert(searchResults.Count == 1 && searchResults[0].Name == "targetName" && searchResults[0].MatchRank == 0,
    " NBT search returns name matches before considering values");
var valueSearchResults = NbtDocumentTools.Search(searchDocument, "target value");
Assert(valueSearchResults.Count == 1 && valueSearchResults[0].Name == "other" && valueSearchResults[0].MatchRank == 1,
    " NBT search falls back to values when no name matches");
var typeSearchResults = NbtDocumentTools.Search(searchDocument, "Int");
Assert(typeSearchResults.Count == 1 && typeSearchResults[0].Name == "number" && typeSearchResults[0].MatchRank == 2,
    " NBT search falls back to type without matching container summaries");
foreach (var encoding in Enum.GetValues<NbtEncoding>())
{
    var bytes = NbtFileCodec.Encode(searchDocument, encoding);
    var decoded = NbtFileCodec.DecodeSingle(bytes, encoding);
    Assert(decoded.Encoding == encoding && decoded.Document.Root.StringValue("other") == "target value", $" NBT file codec {encoding}");
}
var cloneSource = new NbtByteArrayValue([1, 2, 3]);
var clone = (NbtByteArrayValue)NbtDocumentTools.DeepClone(cloneSource);
cloneSource.Value[0] = 9;
Assert(clone.Value[0] == 1, " deep clone isolates mutable arrays");

Console.WriteLine("MCBEEditor.Core self-test passed; NBT search/file tools and modern/legacy entity ownership relocation matched expectations.");

// object creation/import/copy/delete storage behavior.
using (var createDb = new SelfTestWorldDatabase())
{
    var store = new BedrockWorldObjectNbtStore(createDb);
    var created = store.Create(BedrockWorldObjectKind.Entity, "minecraft:pig",
        new BedrockWorldObjectPosition(34.5, 70, -1.25), 0, 9001);
    Assert(created.Source == BedrockWorldObjectSource.ModernActor && created.ChunkX == 2 && created.ChunkZ == -1,
        " blank entity defaults to modern actor storage in a modern/empty database");
    var modernScan = new BedrockWorldObjectScanner(createDb).ScanRegion(2, -1, 0, 0, true, false);
    Assert(modernScan.Objects.Count == 1 && modernScan.Objects[0].Identifier == "minecraft:pig"
           && modernScan.Objects[0].UniqueId == 9001,
        " created modern entity is discoverable through digp/actorprefix");

    var importSource = new NbtDocument("", new NbtCompoundValue([
        new NbtNamedTag("identifier", new NbtStringValue("minecraft:cow")),
        new NbtNamedTag("UniqueID", new NbtLongValue(1)),
        new NbtNamedTag("Pos", new NbtListValue(NbtTagType.Float,
            [new NbtFloatValue(1), new NbtFloatValue(2), new NbtFloatValue(3)])),
        new NbtNamedTag("CustomPayload", new NbtStringValue("keep-me"))
    ]));
    var prepared = store.PrepareImportedEntityDocument(importSource, new BedrockWorldObjectPosition(-33, 80, 48), 9002);
    Assert(BedrockEntityCommonNbt.Dimension(prepared.Root) is null, " import preparation does not synthesize DimensionId");
    Assert(prepared.Root.StringValue("CustomPayload") == "keep-me", " import preparation preserves unrelated tags");
    Assert(BedrockEntityCommonNbt.UniqueId(prepared.Root) == 9002 && BedrockEntityCommonNbt.Position(prepared.Root)?.BlockX == -33,
        " import preparation changes Pos and UniqueID only");
    var imported = store.CreateEntityFromDocument(prepared, fallbackDimension: 2);
    Assert(imported.Dimension == 2 && imported.ChunkX == -3 && imported.ChunkZ == 3,
        " missing DimensionId uses storage-only fallback dimension");
    var importedScan = new BedrockWorldObjectScanner(createDb).ScanRegion(-3, 3, 2, 0, true, false);
    Assert(importedScan.Objects.Count == 1 && BedrockEntityCommonNbt.Dimension(importedScan.Objects[0].Document.Root) is null,
        " fallback dimension is not inserted into imported NBT");

    var allActors = modernScan.Objects.Concat(importedScan.Objects).ToArray();
    Assert(store.Delete(allActors) == 2, " batch delete removes both modern actors");
    Assert(new BedrockWorldObjectScanner(createDb).ScanAll(null, true, false).Objects.Count == 0,
        " batch delete cleans actorprefix and digp ownership");
}

using (var digestCompatibilityDb = new SelfTestWorldDatabase())
{
    var legacyReference = new byte[8];
    BinaryPrimitives.WriteInt64LittleEndian(legacyReference, 7001);
    var actorKey = Encoding.ASCII.GetBytes("actorprefix").Concat(legacyReference).ToArray();
    var legacyActor = new NbtDocument("", new NbtCompoundValue([
        new NbtNamedTag("identifier", new NbtStringValue("minecraft:cow")),
        new NbtNamedTag("UniqueID", new NbtLongValue(7001)),
        new NbtNamedTag("DimensionId", new NbtIntValue(0)),
        new NbtNamedTag("Pos", new NbtListValue(NbtTagType.Float,
            [new NbtFloatValue(81), new NbtFloatValue(64), new NbtFloatValue(97)]))
    ]));
    digestCompatibilityDb.Put(actorKey, ConsecutiveNbtCodec.Encode([
        new ConsecutiveNbtRecord(legacyActor, Array.Empty<byte>(), NbtEncoding.LittleEndian)
    ]));

    var nonStandardDigestKey = new byte[16];
    Encoding.ASCII.GetBytes("digp").CopyTo(nonStandardDigestKey, 0);
    BinaryPrimitives.WriteInt32LittleEndian(nonStandardDigestKey.AsSpan(4, 4), 5);
    BinaryPrimitives.WriteInt32LittleEndian(nonStandardDigestKey.AsSpan(8, 4), 6);
    BinaryPrimitives.WriteInt32LittleEndian(nonStandardDigestKey.AsSpan(12, 4), 0);
    digestCompatibilityDb.Put(nonStandardDigestKey, legacyReference);

    var store = new BedrockWorldObjectNbtStore(digestCompatibilityDb);
    store.Create(BedrockWorldObjectKind.Entity, "minecraft:pig",
        new BedrockWorldObjectPosition(82, 65, 98), 0, 7002);

    var canonicalDigestKey = nonStandardDigestKey.AsSpan(0, 12).ToArray();
    var canonicalDigest = digestCompatibilityDb.Get(canonicalDigestKey);
    Assert(digestCompatibilityDb.Get(nonStandardDigestKey) is { Length: 8 },
        " non-standard historical digp keys are left untouched rather than migrated");
    Assert(canonicalDigest is { Length: 8 },
        " entity creation writes only the standard Bedrock digp key for the new actor");
    Assert(new BedrockWorldObjectScanner(digestCompatibilityDb).ScanRegion(5, 6, 0, 0, true, false).Objects.Count == 1,
        " scanners ignore non-standard historical digp keys and read the canonical key only");
}

using (var legacyCreateDb = new SelfTestWorldDatabase())
{
    var existingKey = new BedrockDbKey(new ChunkPosition(0, 0, 0), ChunkRecordType.Entity, null).Encode();
    var existing = new NbtDocument("", new NbtCompoundValue([
        new NbtNamedTag("id", new NbtShortValue(11)),
        new NbtNamedTag("UniqueID", new NbtLongValue(8100)),
        new NbtNamedTag("DimensionId", new NbtIntValue(0)),
        new NbtNamedTag("Pos", new NbtListValue(NbtTagType.Float,
            [new NbtFloatValue(1), new NbtFloatValue(64), new NbtFloatValue(1)]))
    ]));
    legacyCreateDb.Put(existingKey, BedrockNbtCodec.Encode(existing, NbtEncoding.LittleEndian));
    var store = new BedrockWorldObjectNbtStore(legacyCreateDb);
    var result = store.Create(BedrockWorldObjectKind.Entity, "minecraft:pig",
        new BedrockWorldObjectPosition(18, 65, 2), 0, 8101);
    Assert(result.Source == BedrockWorldObjectSource.LegacyChunkEntity,
        " entity creation detects legacy Entity(0x32) worlds");
    var legacyScan = new BedrockWorldObjectScanner(legacyCreateDb).ScanRegion(1, 0, 0, 0, true, false);
    Assert(legacyScan.Objects.Count == 1 && legacyScan.Objects[0].Identifier == "minecraft:pig",
        " legacy entity identity is encoded with numeric id mapping");
}

using (var blockCreateDb = new SelfTestWorldDatabase())
{
    var store = new BedrockWorldObjectNbtStore(blockCreateDb);
    store.Create(BedrockWorldObjectKind.BlockEntity, "Chest", new BedrockWorldObjectPosition(4, 63, 5), 0);
    var blockScan = new BedrockWorldObjectScanner(blockCreateDb).ScanRegion(0, 0, 0, 0, false, true);
    Assert(blockScan.Objects.Count == 1 && blockScan.Objects[0].Identifier == "Chest", " block entity NBT creation");
    var duplicateRejected = false;
    try { store.Create(BedrockWorldObjectKind.BlockEntity, "Furnace", new BedrockWorldObjectPosition(4, 63, 5), 0); }
    catch (InvalidOperationException) { duplicateRejected = true; }
    Assert(duplicateRejected, " duplicate block entity coordinate is rejected");
    Assert(store.Delete(blockScan.Objects) == 1, " block entity delete rewrites the shared BlockEntity record");
}

var typedEntityJson = Encoding.UTF8.GetBytes("""
{
  "format": "mcbeeditor-nbt-json",
  "documents": [
    { "name": "identifier", "type": "string", "value": "minecraft:pig" },
    { "name": "UniqueID", "type": "long", "value": "123" },
    { "name": "Pos", "type": "list", "value": { "type": "float", "value": [1.5, 64.0, -2.25] } }
  ]
}
""");
var jsonEntities = NbtJsonCodec.DecodeEntityDocuments(typedEntityJson);
Assert(jsonEntities.Count == 1 && BedrockEntityCommonNbt.Identifier(jsonEntities[0].Root) == "minecraft:pig"
       && BedrockEntityCommonNbt.UniqueId(jsonEntities[0].Root) == 123,
    " selected-entity typed JSON import layout");

Console.WriteLine("MCBEEditor.Core self-test passed; entity creation/import, legacy-modern storage selection, batch deletion and block-entity NBT creation matched expectations.");

// single-block persistence and block-entity/block-data atomic relocation.
static NbtDocument BlockStateDocument(string name, int version = BedrockBlockState.DefaultPaletteVersion)
    => new("", new NbtCompoundValue([
        new NbtNamedTag("name", new NbtStringValue(name)),
        new NbtNamedTag("states", new NbtCompoundValue([])),
        new NbtNamedTag("version", new NbtIntValue(version))
    ]));

using (var blockEditDb = new SelfTestWorldDatabase())
{
    var position = new ChunkPosition(0, 0, 0);
    blockEditDb.Put(new BedrockDbKey(position, ChunkRecordType.Version, null).Encode(), [40]);
    var sourceSub = new BedrockSubChunk(9, 4, [SubChunkStorage.AirFilled(BedrockBlockState.EditableAir())], []);
    blockEditDb.Put(BedrockDbKey.SubChunk(0, 0, 0, 4), sourceSub.EncodePersistent());

    var write = new BedrockBlockStore(blockEditDb).SaveModernState(0, 1, 64, 1, 0, BlockStateDocument("minecraft:stone"));
    Assert(write.Block.Layers[0].Name == "minecraft:stone", " modern single-block write reads back the edited state");
    var decoded = BedrockSubChunk.Decode(blockEditDb.Get(BedrockDbKey.SubChunk(0, 0, 0, 4))!, 4);
    Assert(decoded.Storages[0].Palette.Count == 2 && decoded.Storages[0].BitsPerBlock == 1,
        " palette append expands bits-per-block from all-air to 1 bit");
    Assert(decoded.Storages[0].BlockState(1, 0, 1)?.Name == "minecraft:stone",
        " local XYZ index is persisted at the requested coordinate");
}

using (var v1SecondStorageDb = new SelfTestWorldDatabase())
{
    var position = new ChunkPosition(0, 0, 0);
    v1SecondStorageDb.Put(new BedrockDbKey(position, ChunkRecordType.Version, null).Encode(), [40]);
    v1SecondStorageDb.Put(BedrockDbKey.SubChunk(0, 0, 0, 4),
        new BedrockSubChunk(1, 4, [SubChunkStorage.AirFilled(BedrockBlockState.EditableAir())], []).EncodePersistent());
    new BedrockBlockStore(v1SecondStorageDb).SaveModernState(0, 3, 64, 3, 1, BlockStateDocument("minecraft:water"));
    var decoded = BedrockSubChunk.Decode(v1SecondStorageDb.Get(BedrockDbKey.SubChunk(0, 0, 0, 4))!, 4);
    Assert(decoded.Version == 8 && decoded.Storages.Count == 2 && decoded.Storages[1].BlockState(3, 0, 3)?.Name == "minecraft:water",
        " creating modern storage 1 upgrades v1 to v8 and persists the second layer");
}

using (var legacyLayerDb = new SelfTestWorldDatabase())
{
    var position = new ChunkPosition(0, 0, 0);
    legacyLayerDb.Put(new BedrockDbKey(position, ChunkRecordType.Version, null).Encode(), [2]);
    legacyLayerDb.Put(BedrockDbKey.SubChunk(0, 0, 0, 0), BedrockSubChunk.EmptyLegacy(0, 0).EncodePersistent());
    new BedrockBlockStore(legacyLayerDb).SaveLegacyState(0, 1, 5, 1, 1, 8, 42);
    var read = new BedrockBlockStore(legacyLayerDb).ReadBlock(0, 1, 5, 1);
    Assert(read.Layers.Count >= 2 && read.Layers[1].LegacyId == 8 && read.Layers[1].LegacyData == 42,
        " legacy storage 1 roundtrips through 0x34 LegacyBlockExtraData");
    Assert(legacyLayerDb.Get(new BedrockDbKey(position, ChunkRecordType.LegacyBlockExtraData, null).Encode()) is { Length: > 4 },
        " legacy storage 1 creates a non-empty 0x34 record");
}

using (var blockEntityMoveDb = new SelfTestWorldDatabase())
{
    var position = new ChunkPosition(0, 0, 0);
    blockEntityMoveDb.Put(new BedrockDbKey(position, ChunkRecordType.Version, null).Encode(), [40]);
    blockEntityMoveDb.Put(BedrockDbKey.SubChunk(0, 0, 0, 4),
        new BedrockSubChunk(9, 4, [SubChunkStorage.AirFilled(BedrockBlockState.EditableAir())], []).EncodePersistent());
    var blockStore = new BedrockBlockStore(blockEntityMoveDb);
    blockStore.SaveModernState(0, 1, 64, 1, 0, BlockStateDocument("minecraft:chest"));
    var objectStore = new BedrockWorldObjectNbtStore(blockEntityMoveDb);
    objectStore.Create(BedrockWorldObjectKind.BlockEntity, "Chest", new BedrockWorldObjectPosition(1, 64, 1), 0);
    var sourceObject = new BedrockWorldObjectScanner(blockEntityMoveDb).ScanRegion(0, 0, 0, 0, false, true).Objects.Single();
    var batchesBeforeMove = blockEntityMoveDb.ApplyBatchCount;

    objectStore.MoveBlockEntity(sourceObject, 0, 2, 64, 2);
    Assert(blockEntityMoveDb.ApplyBatchCount == batchesBeforeMove + 1,
        " block entity relocation commits block data and NBT in exactly one database batch");
    var sourceAfter = blockStore.ReadBlock(0, 1, 64, 1);
    var targetAfter = blockStore.ReadBlock(0, 2, 64, 2);
    Assert(sourceAfter.Layers.All(layer => layer.IsAir) && targetAfter.Layers.Any(layer => layer.Name == "minecraft:chest"),
        " same-chunk relocation moves every block storage and clears the source coordinate");
    var movedObjects = new BedrockWorldObjectScanner(blockEntityMoveDb).ScanRegion(0, 0, 0, 0, false, true).Objects;
    Assert(movedObjects.Count == 1 && movedObjects[0].Position?.BlockX == 2 && movedObjects[0].Position?.BlockY == 64 && movedObjects[0].Position?.BlockZ == 2,
        " same-chunk BlockEntity coordinate edit is no longer treated as an in-place NBT-only save");
}

using (var blockEntityCrossDimensionDb = new SelfTestWorldDatabase())
{
    var sourceChunk = new ChunkPosition(0, 0, 0);
    blockEntityCrossDimensionDb.Put(new BedrockDbKey(sourceChunk, ChunkRecordType.Version, null).Encode(), [40]);
    blockEntityCrossDimensionDb.Put(BedrockDbKey.SubChunk(0, 0, 0, 4),
        new BedrockSubChunk(9, 4, [SubChunkStorage.AirFilled(BedrockBlockState.EditableAir())], []).EncodePersistent());
    var blockStore = new BedrockBlockStore(blockEntityCrossDimensionDb);
    blockStore.SaveModernState(0, 15, 64, 15, 0, BlockStateDocument("minecraft:barrel"));
    var objectStore = new BedrockWorldObjectNbtStore(blockEntityCrossDimensionDb);
    objectStore.Create(BedrockWorldObjectKind.BlockEntity, "Barrel", new BedrockWorldObjectPosition(15, 64, 15), 0);
    var sourceObject = new BedrockWorldObjectScanner(blockEntityCrossDimensionDb).ScanRegion(0, 0, 0, 0, false, true).Objects.Single();

    objectStore.MoveBlockEntity(sourceObject, 2, 16, 64, 16);
    Assert(blockStore.ReadBlock(0, 15, 64, 15).Layers.All(layer => layer.IsAir),
        " cross-dimension relocation clears the source block");
    Assert(blockStore.ReadBlock(2, 16, 64, 16).Layers.Any(layer => layer.Name == "minecraft:barrel"),
        " cross-dimension relocation creates a compatible target SubChunk and moves the block state");
    var targetObjects = new BedrockWorldObjectScanner(blockEntityCrossDimensionDb).ScanRegion(1, 1, 2, 0, false, true).Objects;
    Assert(targetObjects.Count == 1 && targetObjects[0].Position?.BlockX == 16 && targetObjects[0].Dimension == 2,
        " cross-dimension relocation moves BlockEntity storage ownership without requiring a DimensionId tag");
    Assert(blockEntityCrossDimensionDb.Get(new BedrockDbKey(new ChunkPosition(1, 1, 2), ChunkRecordType.Version, null).Encode()) is not null,
        " newly materialised target chunk receives compatible minimal metadata");
}

using (var blockEntityRejectDb = new SelfTestWorldDatabase())
{
    var position = new ChunkPosition(0, 0, 0);
    blockEntityRejectDb.Put(new BedrockDbKey(position, ChunkRecordType.Version, null).Encode(), [40]);
    blockEntityRejectDb.Put(BedrockDbKey.SubChunk(0, 0, 0, 4),
        new BedrockSubChunk(9, 4, [SubChunkStorage.AirFilled(BedrockBlockState.EditableAir())], []).EncodePersistent());
    var blockStore = new BedrockBlockStore(blockEntityRejectDb);
    blockStore.SaveModernState(0, 1, 64, 1, 0, BlockStateDocument("minecraft:chest"));
    blockStore.SaveModernState(0, 2, 64, 2, 0, BlockStateDocument("minecraft:stone"));
    var objectStore = new BedrockWorldObjectNbtStore(blockEntityRejectDb);
    objectStore.Create(BedrockWorldObjectKind.BlockEntity, "Chest", new BedrockWorldObjectPosition(1, 64, 1), 0);
    objectStore.Create(BedrockWorldObjectKind.BlockEntity, "Furnace", new BedrockWorldObjectPosition(2, 64, 2), 0);
    var sourceObject = new BedrockWorldObjectScanner(blockEntityRejectDb).ScanRegion(0, 0, 0, 0, false, true).Objects
        .Single(item => item.Position?.BlockX == 1);
    var sourceBefore = blockStore.ReadBlock(0, 1, 64, 1).Layers[0].Name;
    var targetBefore = blockStore.ReadBlock(0, 2, 64, 2).Layers[0].Name;
    var batchesBefore = blockEntityRejectDb.ApplyBatchCount;
    var rejected = false;
    try { objectStore.MoveBlockEntity(sourceObject, 0, 2, 64, 2); }
    catch (InvalidOperationException) { rejected = true; }
    Assert(rejected, " target BlockEntity collision is rejected");
    Assert(blockEntityRejectDb.ApplyBatchCount == batchesBefore,
        " target BlockEntity collision is detected before any block/NBT batch is committed");
    Assert(blockStore.ReadBlock(0, 1, 64, 1).Layers[0].Name == sourceBefore
           && blockStore.ReadBlock(0, 2, 64, 2).Layers[0].Name == targetBefore,
        " rejected relocation leaves source and target blocks unchanged");
}


Console.WriteLine("MCBEEditor.Core self-test passed; modern palette edits, legacy 0x34 storage, and atomic block-entity/block relocation matched expectations.");

// region commands, bulk SubChunk edits, overlap-safe clone and BlockEntity snapshot semantics.
var parsedFill = BlockCommandParser.Parse("fill overworld 0 64 0 1 64 1 minecraft:planks 'String'\"wood_type\"=\"oak\"");
Assert(parsedFill is FillBlockCommandRequest parsedFillRequest
       && parsedFillRequest.Region.Volume == 4
       && parsedFillRequest.Storages.Count == 1
       && parsedFillRequest.Storages[0].States.Single().Name == "wood_type"
       && parsedFillRequest.Storages[0].States.Single().Value is NbtStringValue parsedWood
       && parsedWood.Value == "oak",
    " fill parser accepts the iOS typed-NBT state syntax");

using (var regionFillDb = new SelfTestWorldDatabase())
{
    var chunk = new ChunkPosition(0, 0, 0);
    regionFillDb.Put(new BedrockDbKey(chunk, ChunkRecordType.Version, null).Encode(), [40]);
    regionFillDb.Put(BedrockDbKey.SubChunk(0, 0, 0, 4),
        new BedrockSubChunk(9, 4, [
            SubChunkStorage.AirFilled(BedrockBlockState.EditableAir()),
            SubChunkStorage.AirFilled(BedrockBlockState.EditableAir())
        ], []).EncodePersistent());
    var blockStore = new BedrockBlockStore(regionFillDb);
    blockStore.SaveModernState(0, 2, 64, 2, 1, BlockStateDocument("minecraft:water"));
    blockStore.SaveModernState(0, 1, 64, 1, 0, BlockStateDocument("minecraft:chest"));
    new BedrockWorldObjectNbtStore(regionFillDb).Create(BedrockWorldObjectKind.BlockEntity, "Chest", new BedrockWorldObjectPosition(1, 64, 1), 0);
    var beforeBatches = regionFillDb.ApplyBatchCount;

    var regionStore = new BedrockRegionBlockStore(regionFillDb);
    var result = regionStore.Fill(0,
        new BedrockBlockBox(new BedrockBlockCoordinate(1, 64, 1), new BedrockBlockCoordinate(2, 64, 2)),
        [new BedrockBlockStorageSpec("minecraft:stone", [])]);
    Assert(regionFillDb.ApplyBatchCount == beforeBatches + 1,
        " fill commits all SubChunk and BlockEntity changes in exactly one database batch");
    Assert(result.ChangedBlockPositions == 4 && result.RemovedBlockEntities == 1,
        " fill reports the whole selected region and removes overwritten BlockEntity NBT");
    for (var x = 1; x <= 2; x++)
    for (var z = 1; z <= 2; z++)
        Assert(blockStore.ReadBlock(0, x, 64, z).Layers[0].Name == "minecraft:stone", " fill writes every requested position");
    Assert(blockStore.ReadBlock(0, 2, 64, 2).Layers[1].Name == "minecraft:water",
        " fill preserves omitted higher storages");
    Assert(new BedrockWorldObjectScanner(regionFillDb).ScanRegion(0, 0, 0, 0, false, true).Objects.Count == 0,
        " fill removes BlockEntity records inside the overwritten box");
}

using (var legacyPromoteDb = new SelfTestWorldDatabase())
{
    var chunk = new ChunkPosition(0, 0, 0);
    legacyPromoteDb.Put(new BedrockDbKey(chunk, ChunkRecordType.LegacyVersion, null).Encode(), [2]);
    var legacyRedWool = new BedrockBlockState(null, 35, 14);
    legacyPromoteDb.Put(BedrockDbKey.SubChunk(0, 0, 0, 0),
        new BedrockSubChunk(0, 0, [new SubChunkStorage(8, [legacyRedWool], new ushort[4096])], new byte[4096]).EncodePersistent());
    new BedrockRegionBlockStore(legacyPromoteDb).SetBlock(0, new BedrockBlockCoordinate(0, 0, 0),
        [new BedrockBlockStorageSpec("minecraft:planks", [new NbtNamedTag("wood_type", new NbtStringValue("oak"))])]);
    var promoted = BedrockSubChunk.Decode(legacyPromoteDb.Get(BedrockDbKey.SubChunk(0, 0, 0, 0))!, 0);
    Assert(promoted.IsLegacyNumeric && promoted.Version == 0,
        " legacy numeric SubChunk stays readable by the original game for exactly mapped states");
    Assert(promoted.Storages[0].BlockState(0, 0, 0)?.Name == "minecraft:planks",
        " promoted legacy target receives the requested modern state");
    var preservedLegacyCell = promoted.Storages[0].BlockState(1, 0, 0);
    Assert(preservedLegacyCell?.Name == "minecraft:wool"
           && preservedLegacyCell.LegacyId == 35 && preservedLegacyCell.LegacyData == 14,
        " legacy promotion preserves high-confidence metadata on untouched palette entries");
}

using (var cloneDb = new SelfTestWorldDatabase())
{
    var chunk = new ChunkPosition(0, 0, 0);
    cloneDb.Put(new BedrockDbKey(chunk, ChunkRecordType.Version, null).Encode(), [40]);
    cloneDb.Put(BedrockDbKey.SubChunk(0, 0, 0, 4),
        new BedrockSubChunk(9, 4, [
            SubChunkStorage.AirFilled(BedrockBlockState.EditableAir()),
            SubChunkStorage.AirFilled(BedrockBlockState.EditableAir())
        ], []).EncodePersistent());
    var blockStore = new BedrockBlockStore(cloneDb);
    blockStore.SaveModernState(0, 0, 64, 0, 0, BlockStateDocument("minecraft:stone"));
    blockStore.SaveModernState(0, 1, 64, 0, 0, BlockStateDocument("minecraft:dirt"));
    blockStore.SaveModernState(0, 2, 64, 0, 0, BlockStateDocument("minecraft:gold_block"));
    blockStore.SaveModernState(0, 2, 64, 0, 1, BlockStateDocument("minecraft:water"));
    var objectStore = new BedrockWorldObjectNbtStore(cloneDb);
    objectStore.Create(BedrockWorldObjectKind.BlockEntity, "Chest", new BedrockWorldObjectPosition(0, 64, 0), 0);
    objectStore.Create(BedrockWorldObjectKind.BlockEntity, "Furnace", new BedrockWorldObjectPosition(1, 64, 0), 0);
    objectStore.Create(BedrockWorldObjectKind.BlockEntity, "Hopper", new BedrockWorldObjectPosition(2, 64, 0), 0);
    var beforeBatches = cloneDb.ApplyBatchCount;

    var cloneResult = new BedrockRegionBlockStore(cloneDb).Clone(0,
        new BedrockBlockBox(new BedrockBlockCoordinate(0, 64, 0), new BedrockBlockCoordinate(1, 64, 0)),
        0, new BedrockBlockCoordinate(1, 64, 0));
    Assert(cloneDb.ApplyBatchCount == beforeBatches + 1,
        " overlapping clone commits block and BlockEntity changes in one database batch");
    Assert(blockStore.ReadBlock(0, 1, 64, 0).Layers[0].Name == "minecraft:stone"
           && blockStore.ReadBlock(0, 2, 64, 0).Layers[0].Name == "minecraft:dirt",
        " overlapping clone reads the frozen source snapshot instead of cascading earlier target writes");
    Assert(blockStore.ReadBlock(0, 2, 64, 0).Layers[1].IsAir,
        " clone clears target-only higher storage at copied positions");
    Assert(cloneResult.RemovedBlockEntities == 2 && cloneResult.CopiedBlockEntities == 2,
        " clone replaces target-region BlockEntities from the source snapshot");
    var blockEntities = new BedrockWorldObjectScanner(cloneDb).ScanRegion(0, 0, 0, 0, false, true).Objects;
    Assert(blockEntities.Count == 3
           && blockEntities.Any(item => item.Position?.BlockX == 0 && item.Identifier.Contains("Chest", StringComparison.OrdinalIgnoreCase))
           && blockEntities.Any(item => item.Position?.BlockX == 1 && item.Identifier.Contains("Chest", StringComparison.OrdinalIgnoreCase))
           && blockEntities.Any(item => item.Position?.BlockX == 2 && item.Identifier.Contains("Furnace", StringComparison.OrdinalIgnoreCase)),
        " overlapping clone keeps out-of-target source BlockEntity and offsets both source BlockEntities exactly once");
}

using (var unknownSourceCloneDb = new SelfTestWorldDatabase())
{
    var sourceChunk = new ChunkPosition(0, 0, 0);
    unknownSourceCloneDb.Put(new BedrockDbKey(sourceChunk, ChunkRecordType.Version, null).Encode(), [40]);
    unknownSourceCloneDb.Put(BedrockDbKey.SubChunk(0, 0, 0, 4), [10, 0xAA, 0xBB, 0xCC]);
    var beforeBatches = unknownSourceCloneDb.ApplyBatchCount;
    var rejected = false;
    try
    {
        new BedrockRegionBlockStore(unknownSourceCloneDb).Clone(0,
            new BedrockBlockBox(new BedrockBlockCoordinate(0, 64, 0), new BedrockBlockCoordinate(0, 64, 0)),
            2, new BedrockBlockCoordinate(0, 64, 0));
    }
    catch (NotSupportedException) { rejected = true; }
    Assert(rejected && unknownSourceCloneDb.ApplyBatchCount == beforeBatches,
        " clone rejects unknown source SubChunk versions before any database batch instead of treating them as air");
}

using (var mixedFamilyCloneDb = new SelfTestWorldDatabase())
{
    var sourceChunk = new ChunkPosition(0, 0, 0);
    mixedFamilyCloneDb.Put(new BedrockDbKey(sourceChunk, ChunkRecordType.Version, null).Encode(), [40]);
    mixedFamilyCloneDb.Put(BedrockDbKey.SubChunk(0, 0, 0, 0),
        new BedrockSubChunk(0, 0, [new SubChunkStorage(8, [new BedrockBlockState(null, 1, 0)], new ushort[4096])], new byte[4096]).EncodePersistent());
    var modernOak = NamedState("minecraft:planks", new NbtNamedTag("wood_type", new NbtStringValue("oak")));
    mixedFamilyCloneDb.Put(BedrockDbKey.SubChunk(0, 0, 0, 1),
        new BedrockSubChunk(9, 1, [new SubChunkStorage(0, [modernOak], new ushort[4096])], []).EncodePersistent());

    var targetChunk = new ChunkPosition(0, 0, 1);
    mixedFamilyCloneDb.Put(new BedrockDbKey(targetChunk, ChunkRecordType.LegacyVersion, null).Encode(), [2]);
    mixedFamilyCloneDb.Put(BedrockDbKey.SubChunk(0, 0, 1, 0),
        new BedrockSubChunk(0, 0, [SubChunkStorage.AirFilled(new BedrockBlockState(null, 0, 0))], new byte[4096]).EncodePersistent());

    new BedrockRegionBlockStore(mixedFamilyCloneDb).Clone(0,
        new BedrockBlockBox(new BedrockBlockCoordinate(0, 15, 0), new BedrockBlockCoordinate(0, 16, 0)),
        1, new BedrockBlockCoordinate(0, 0, 0));
    var target = new BedrockBlockStore(mixedFamilyCloneDb);
    Assert(target.ReadBlock(1, 0, 0, 0).Layers[0].Name == "minecraft:stone"
           && target.ReadBlock(1, 0, 1, 0).Layers[0].Name == "minecraft:planks",
        " clone fixes the destination family before replacements when one target SubChunk receives mixed legacy/modern source slices");
}

using (var missingSourceCloneDb = new SelfTestWorldDatabase())
{
    var beforeBatches = missingSourceCloneDb.ApplyBatchCount;
    new BedrockRegionBlockStore(missingSourceCloneDb).Clone(0,
        new BedrockBlockBox(new BedrockBlockCoordinate(160, 64, 160), new BedrockBlockCoordinate(160, 64, 160)),
        2, new BedrockBlockCoordinate(0, 64, 0));
    Assert(missingSourceCloneDb.ApplyBatchCount == beforeBatches + 1,
        " missing-source clone still uses one final database batch");
    Assert(missingSourceCloneDb.Get(new BedrockDbKey(new ChunkPosition(10, 10, 0), ChunkRecordType.Version, null).Encode()) is not null,
        " clone materialises completely missing source chunks as generated air metadata");
    Assert(new BedrockBlockStore(missingSourceCloneDb).ReadBlock(2, 0, 64, 0).Generated,
        " missing source is copied as air into a generated target SubChunk");
}

var deepTypedNbt = new NbtCompoundValue([
    new NbtNamedTag("deep", new NbtListValue(NbtTagType.List, [
        new NbtListValue(NbtTagType.List, [
            new NbtListValue(NbtTagType.String, [
                new NbtStringValue("alpha,beta"),
                new NbtStringValue("right]bracket"),
                new NbtStringValue("quote\"slash\\line\nnext\ttab")
            ]),
            new NbtListValue(NbtTagType.String, [new NbtStringValue("second")])
        ]),
        new NbtListValue(NbtTagType.List, [
            new NbtListValue(NbtTagType.String, [new NbtStringValue("third\rline")])
        ])
    ])),
    new NbtNamedTag("compoundList", new NbtListValue(NbtTagType.Compound, [
        new NbtCompoundValue([
            new NbtNamedTag("message", new NbtStringValue("hello, \"world\"\nline2")),
            new NbtNamedTag("values", new NbtListValue(NbtTagType.Int, [new NbtIntValue(1), new NbtIntValue(-2)]))
        ])
    ]))
]);
var deepTypedText = BlockCommandNbtOutputFormatter.Root(deepTypedNbt);
var deepTypedParsed = new NbtCompoundValue(BlockCommandParser.ParseStates(deepTypedText));
var deepOriginalBytes = BedrockNbtCodec.Encode(new NbtDocument(string.Empty, deepTypedNbt), NbtEncoding.LittleEndian);
var deepParsedBytes = BedrockNbtCodec.Encode(new NbtDocument(string.Empty, deepTypedParsed), NbtEncoding.LittleEndian);
Assert(deepOriginalBytes.SequenceEqual(deepParsedBytes),
    " typed-NBT formatter/parser roundtrip preserves nested List<List<List<String>>>, compounds and escaped strings");

var getBlockCommand = (GetBlockCommandRequest)BlockCommandParser.Parse("getblock the_end -1 70 2");
Assert(getBlockCommand.Dimension == 2 && getBlockCommand.Position == new BedrockBlockCoordinate(-1, 70, 2),
    " getblock parser preserves signed coordinates and dimension");

// physical storage commands, fillbiome and info parser.
var storageSetCommand = (StorageSetStorageBiomeCommandRequest)StorageBiomeCommandParser.Parse(
    "storage set overworld 1 64 2 8 minecraft:planks 'String'\"wood_type\"=\"oak\"");
Assert(storageSetCommand.Layer == 8 && storageSetCommand.Block.Name == "minecraft:planks"
       && storageSetCommand.Block.States.Count == 1,
    "StorageBiome storage set parser accepts typed states and high storage indices");
var storageAddRejected = false;
try { _ = StorageBiomeCommandParser.Parse("storage add overworld 0 64 0 1 minecraft:stone NULL"); }
catch (InvalidDataException) { storageAddRejected = true; }
Assert(storageAddRejected, "StorageBiome storage add remains explicitly unsupported");
Assert(StorageBiomeCommandParser.Parse("info") is InfoStorageBiomeCommandRequest, "StorageBiome info takes no arguments");
var fillBiomeCommand = (FillBiomeStorageBiomeCommandRequest)StorageBiomeCommandParser.Parse(
    "fillbiome the_end -1 -64 -2 3 80 4 minecraft:plains");
Assert(fillBiomeCommand.Dimension == 2 && fillBiomeCommand.BiomeId == 1
       && fillBiomeCommand.Region.Minimum == new BedrockBlockCoordinate(-1, -64, -2),
    "StorageBiome fillbiome resolves string biome IDs and normalizes coordinates");
var rawBiomeCommand = (FillBiomeStorageBiomeCommandRequest)StorageBiomeCommandParser.Parse(
    "fillbiome overworld 0 0 0 0 0 0 -1");
Assert(rawBiomeCommand.BiomeId == uint.MaxValue, "StorageBiome fillbiome preserves signed numeric biome IDs by raw UInt32 bit pattern");

using (var missingStorageDb = new SelfTestWorldDatabase())
{
    var store = new BedrockStorageCommandStore(missingStorageDb);
    var query = store.Query(0, new BedrockBlockCoordinate(1, 64, 1));
    Assert(query.Count == 1 && query[0] == "Block not generated",
        "StorageBiome storage query returns Block not generated for a completely ungenerated chunk");
    var before = missingStorageDb.ApplyBatchCount;
    var set = store.Set(0, new BedrockBlockCoordinate(1, 64, 1), 8,
        new BedrockBlockStorageSpec("minecraft:stone", []));
    Assert(missingStorageDb.ApplyBatchCount == before + 1 && set.StorageCountAfter == 9,
        "StorageBiome storage set creates compatible v8/v9 air metadata/SubChunk for an ungenerated chunk in one batch");
    var after = store.Query(0, new BedrockBlockCoordinate(1, 64, 1));
    Assert(after.Count == 9 && after[8].Contains("minecraft:stone", StringComparison.Ordinal),
        "StorageBiome storage set on an ungenerated chunk reads back all materialized storages");
}

using (var storageDb = new SelfTestWorldDatabase())
{
    var chunk = new ChunkPosition(0, 0, 0);
    storageDb.Put(new BedrockDbKey(chunk, ChunkRecordType.Version, null).Encode(), [40]);
    storageDb.Put(BedrockDbKey.SubChunk(0, 0, 0, 4),
        new BedrockSubChunk(9, 4, [
            SubChunkStorage.AirFilled(BedrockBlockState.EditableAir()),
            SubChunkStorage.AirFilled(BedrockBlockState.EditableAir())
        ], []).EncodePersistent());
    var store = new BedrockStorageCommandStore(storageDb);
    var before = storageDb.ApplyBatchCount;
    var set = store.Set(0, new BedrockBlockCoordinate(1, 64, 1), 8,
        new BedrockBlockStorageSpec("minecraft:stone", []));
    Assert(storageDb.ApplyBatchCount == before + 1 && set.StorageCountAfter == 9,
        "StorageBiome storage set materializes intermediate air storages in one batch");
    var query = store.Query(0, new BedrockBlockCoordinate(1, 64, 1));
    Assert(query.Count == 9 && query[8].Contains("minecraft:stone", StringComparison.Ordinal),
        "StorageBiome storage query returns every physical storage including storage8");
    var deleted = store.Delete(0, new BedrockBlockCoordinate(1, 64, 1), 1);
    Assert(deleted.StorageCountAfter == 8,
        "StorageBiome storage delete shifts following storages and trims only trailing all-air storages");
    var cleared = store.Clear(0, new BedrockBlockCoordinate(1, 64, 1), 0);
    Assert(cleared.StorageCountAfter == 1,
        "StorageBiome storage clear 0 keeps storage0 only");
}

using (var maxStorageDb = new SelfTestWorldDatabase())
{
    var chunk = new ChunkPosition(0, 0, 0);
    maxStorageDb.Put(new BedrockDbKey(chunk, ChunkRecordType.Version, null).Encode(), [40]);
    maxStorageDb.Put(BedrockDbKey.SubChunk(0, 0, 0, 4),
        new BedrockSubChunk(9, 4, [SubChunkStorage.AirFilled(BedrockBlockState.EditableAir())], []).EncodePersistent());
    var result = new BedrockStorageCommandStore(maxStorageDb).Set(0, new BedrockBlockCoordinate(0, 64, 0), 254,
        new BedrockBlockStorageSpec("minecraft:stone", []));
    var persisted = BedrockSubChunk.Decode(maxStorageDb.Get(BedrockDbKey.SubChunk(0, 0, 0, 4))!, 4);
    Assert(result.StorageCountAfter == byte.MaxValue && persisted.Storages.Count == byte.MaxValue
           && persisted.Storages[254].BlockState(0, 0, 0)?.Name == "minecraft:stone",
        "StorageBiome storage set layer254 persists the full UInt8 255-storage count");
}

using (var unknownStorageDb = new SelfTestWorldDatabase())
{
    var chunk = new ChunkPosition(0, 0, 0);
    unknownStorageDb.Put(new BedrockDbKey(chunk, ChunkRecordType.Version, null).Encode(), [40]);
    unknownStorageDb.Put(BedrockDbKey.SubChunk(0, 0, 0, 4), [10, 0x11, 0x22]);
    var before = unknownStorageDb.ApplyBatchCount;
    var rejected = false;
    try
    {
        new BedrockStorageCommandStore(unknownStorageDb).Set(0, new BedrockBlockCoordinate(0, 64, 0), 0,
            new BedrockBlockStorageSpec("minecraft:stone", []));
    }
    catch (NotSupportedException) { rejected = true; }
    Assert(rejected && unknownStorageDb.ApplyBatchCount == before,
        "StorageBiome storage rejects unknown future SubChunk versions before any batch");
}

using (var biomeDb = new SelfTestWorldDatabase())
{
    var chunk = new ChunkPosition(0, 0, 0);
    var biome = new BedrockBiomeDocument(
        BedrockBiomeFormat.Data3D,
        new short[256],
        [new BedrockBiomeLayer(-64, Enumerable.Repeat(1u, 4096).ToArray(), false)]);
    var biomeKey = new BedrockDbKey(chunk, ChunkRecordType.Data3D, null).Encode();
    var original = biome.Encode();
    Assert(BedrockBiomeDocument.Decode(ChunkRecordType.Data3D, original).Encode().SequenceEqual(original),
        "StorageBiome Data3D biome codec roundtrips a paletted layer");
    biomeDb.Put(biomeKey, original);
    var before = biomeDb.ApplyBatchCount;
    var result = new BedrockBiomeRegionStore(biomeDb).FillBiome(0,
        new BedrockBlockBox(new BedrockBlockCoordinate(0, -64, 0), new BedrockBlockCoordinate(0, -64, 0)), 2);
    Assert(biomeDb.ApplyBatchCount == before + 1 && result.ChangedCellCount == 1,
        "StorageBiome fillbiome commits Data3D edits in one batch");
    var edited = BedrockBiomeDocument.Decode(ChunkRecordType.Data3D, biomeDb.Get(biomeKey)!);
    Assert(edited.BiomeId(0, -64, 0) == 2 && edited.BiomeId(0, -63, 0) == 1,
        "StorageBiome fillbiome changes only Data3D cells inside the inclusive Y range");
}

// Data3D 0xff means inherit the previous explicit layer's top plane for reading,
// while untouched encoding must keep the compact 0xff marker.
var inheritedData3D = new byte[512 + 6];
inheritedData3D[512] = 0; // BPB=0
inheritedData3D[513] = 5; // UInt32 biome ID 5, little endian
inheritedData3D[517] = 0xff;
var inheritedDocument = BedrockBiomeDocument.Decode(ChunkRecordType.Data3D, inheritedData3D);
Assert(inheritedDocument.Layers.Count == 2 && inheritedDocument.Layers[1].IsAbsent
       && inheritedDocument.BiomeId(0, -48, 0) == 5
       && inheritedDocument.Encode().SequenceEqual(inheritedData3D),
    "StorageBiome Data3D materializes 0xff inheritance for reads but preserves untouched absent markers on encode");

using (var legacyBiomeDb = new SelfTestWorldDatabase())
{
    var chunk = new ChunkPosition(0, 0, 0);
    var raw = new byte[512 + 256 * 4 + 2];
    for (var index = 0; index < 256; index++)
    {
        var offset = 512 + index * 4;
        raw[offset] = 1;
        raw[offset + 1] = (byte)(0x40 + index % 16);
        raw[offset + 2] = (byte)(0x80 + index % 16);
        raw[offset + 3] = (byte)(0xc0 + index % 16);
    }
    raw[^2] = 0xaa; raw[^1] = 0x55;
    var key = new BedrockDbKey(chunk, ChunkRecordType.Data2DLegacy, null).Encode();
    legacyBiomeDb.Put(key, raw);
    _ = new BedrockBiomeRegionStore(legacyBiomeDb).FillBiome(0,
        new BedrockBlockBox(new BedrockBlockCoordinate(0, -999, 0), new BedrockBlockCoordinate(0, 999, 0)), 2);
    var editedRaw = legacyBiomeDb.Get(key)!;
    Assert(editedRaw[512] == 2 && editedRaw[513] == raw[513] && editedRaw[514] == raw[514] && editedRaw[515] == raw[515]
           && editedRaw.AsSpan(516, 256 * 4 - 4).SequenceEqual(raw.AsSpan(516, 256 * 4 - 4))
           && editedRaw[^2] == 0xaa && editedRaw[^1] == 0x55,
        "StorageBiome Data2DLegacy fill changes only the biome byte and preserves auxiliary/trailing bytes");
}

using (var data2DBiomeDb = new SelfTestWorldDatabase())
{
    var chunk = new ChunkPosition(0, 0, 0);
    var data2D = new BedrockBiomeDocument(
        BedrockBiomeFormat.Data2D,
        new short[256],
        [new BedrockBiomeLayer(null, Enumerable.Repeat(1u, 256).ToArray(), false)]);
    data2DBiomeDb.Put(new BedrockDbKey(chunk, ChunkRecordType.Data2D, null).Encode(), data2D.Encode());
    var before = data2DBiomeDb.ApplyBatchCount;
    var rejected = false;
    try
    {
        new BedrockBiomeRegionStore(data2DBiomeDb).FillBiome(0,
            new BedrockBlockBox(new BedrockBlockCoordinate(0, 0, 0), new BedrockBlockCoordinate(0, 0, 0)), 300);
    }
    catch (InvalidDataException) { rejected = true; }
    Assert(rejected && data2DBiomeDb.ApplyBatchCount == before,
        "StorageBiome Data2D rejects biome IDs above UInt8 before any write batch");
}



// command target selectors, player spawn/XP and safe player/entity movement.
var targetingTeleportParsed = (TeleportTargetingCommandRequest)TargetingCommandParser.Parse("teleport @a overworld -10.0 64 5");
Assert(targetingTeleportParsed.Y.IntegerLiteral && targetingTeleportParsed.Y.AddsPlayerEyeHeight,
    "Targeting integer teleport Y preserves the +1.62 player-eye-height semantic");
var targetingFloatTeleportParsed = (TeleportTargetingCommandRequest)TargetingCommandParser.Parse("teleport @a overworld 100.0 70.0 100.0");
Assert(!targetingFloatTeleportParsed.Y.IntegerLiteral && !targetingFloatTeleportParsed.Y.AddsPlayerEyeHeight,
    "Targeting floating teleport Y does not add player eye height");
Assert(((TeleportTargetingCommandRequest)TargetingCommandParser.Parse("teleport @s overworld 0 Auto 0")).Y.Automatic,
    "Targeting parses Auto teleport Y");
Assert(((ExperienceTargetingCommandRequest)TargetingCommandParser.Parse("experience level @s 24791")).IntegerValue == 24791,
    "Targeting experience parser accepts the maximum level");
var targetingBadLevelRejected = false;
try { _ = TargetingCommandParser.Parse("experience level @s 24792"); }
catch (InvalidDataException) { targetingBadLevelRejected = true; }
Assert(targetingBadLevelRejected, "Targeting experience parser rejects levels above 24791");

Assert(BedrockPlayerExperience.PointsRequiredForNextLevel(0) == 7
       && BedrockPlayerExperience.PointsRequiredForNextLevel(16) == 42
       && BedrockPlayerExperience.TotalRequired(17) == 394,
    "Targeting XP curve matches Minecraft level formulas");
var xp2500 = BedrockPlayerExperience.FromTotal(2500);
Assert(xp2500.Total == 2500, "Targeting total XP roundtrips through level/progress storage");
var fractionalLevelRejected = false;
try
{
    _ = TargetingCommandStore.ReadExperience(new NbtDocument("", new NbtCompoundValue([
        new NbtNamedTag("PlayerLevel", new NbtDoubleValue(12.5)),
        new NbtNamedTag("PlayerLevelProgress", new NbtFloatValue(0))
    ])));
}
catch (InvalidDataException) { fractionalLevelRejected = true; }
Assert(fractionalLevelRejected, "Targeting rejects non-integral floating PlayerLevel tags instead of truncating them");

using (var targetingDb = new SelfTestWorldDatabase())
{
    var localPlayer = new NbtDocument("", new NbtCompoundValue([
        new NbtNamedTag("PlayerName", new NbtStringValue("Local Targeting")),
        new NbtNamedTag("UniqueID", new NbtLongValue(1001)),
        new NbtNamedTag("DimensionId", new NbtIntValue(0)),
        new NbtNamedTag("Pos", new NbtListValue(NbtTagType.Float,
            [new NbtFloatValue(1.5f), new NbtFloatValue(65f), new NbtFloatValue(1.5f)])),
        new NbtNamedTag("PlayerLevel", new NbtIntValue(3)),
        new NbtNamedTag("PlayerLevelProgress", new NbtFloatValue(0.5f))
    ]));
    var onlinePlayer = new NbtDocument("", new NbtCompoundValue([
        new NbtNamedTag("PlayerName", new NbtStringValue("Online Targeting")),
        new NbtNamedTag("DimensionId", new NbtIntValue(0)),
        new NbtNamedTag("Pos", new NbtListValue(NbtTagType.Float,
            [new NbtFloatValue(2.5f), new NbtFloatValue(65f), new NbtFloatValue(2.5f)]))
    ]));
    targetingDb.Put(Encoding.UTF8.GetBytes("~local_player"), BedrockNbtCodec.Encode(localPlayer, NbtEncoding.LittleEndian));
    targetingDb.Put(Encoding.UTF8.GetBytes("player_server_2002"), BedrockNbtCodec.Encode(onlinePlayer, NbtEncoding.LittleEndian));

    var cowReference = new byte[8];
    BinaryPrimitives.WriteInt64LittleEndian(cowReference, 3003);
    var cowActorKey = Encoding.ASCII.GetBytes("actorprefix").Concat(cowReference).ToArray();
    var cowDigestKey = new byte[12];
    Encoding.ASCII.GetBytes("digp").CopyTo(cowDigestKey, 0);
    var cowDocument = new NbtDocument("", new NbtCompoundValue([
        new NbtNamedTag("definitions", new NbtListValue(NbtTagType.String, [new NbtStringValue("+minecraft:cow")])),
        new NbtNamedTag("UniqueID", new NbtLongValue(3003)),
        new NbtNamedTag("DimensionId", new NbtIntValue(0)),
        new NbtNamedTag("Pos", new NbtListValue(NbtTagType.Float,
            [new NbtFloatValue(3.5f), new NbtFloatValue(65f), new NbtFloatValue(3.5f)]))
    ]));
    targetingDb.Put(cowDigestKey, cowReference);
    targetingDb.Put(cowActorKey, BedrockNbtCodec.Encode(cowDocument, NbtEncoding.LittleEndian));

    // One generated overworld column with stone at Y=64 for teleport Auto/spread.
    var targetingAir = BedrockBlockState.EditableAir();
    var stone = NamedState("minecraft:stone");
    var indices = new ushort[4096];
    indices[(0 << 8) | (0 << 4) | 0] = 1;
    var surfaceStorage = new SubChunkStorage(1, [targetingAir, stone], indices);
    var surfaceChunk = new ChunkPosition(0, 0, 0);
    targetingDb.Put(new BedrockDbKey(surfaceChunk, ChunkRecordType.Version, null).Encode(), [40]);
    targetingDb.Put(BedrockDbKey.SubChunk(0, 0, 0, 4), new BedrockSubChunk(9, 4, [surfaceStorage], []).EncodePersistent());

    // Nether roof at Y=79, generated air Y=78...65 and lower solid Y=64 -> landing Y=65.
    var netherIndices = new ushort[4096];
    netherIndices[(0 << 8) | (0 << 4) | 15] = 1;
    netherIndices[(0 << 8) | (0 << 4) | 0] = 1;
    var netherChunk = new ChunkPosition(0, 0, 1);
    targetingDb.Put(new BedrockDbKey(netherChunk, ChunkRecordType.Version, null).Encode(), [40]);
    targetingDb.Put(BedrockDbKey.SubChunk(0, 0, 1, 4),
        new BedrockSubChunk(9, 4, [new SubChunkStorage(1, [targetingAir, stone], netherIndices)], []).EncodePersistent());

    var targeting = new TargetingCommandStore(targetingDb);
    Assert(targeting.ResolveTargets(TargetingCommandParser.ParseTarget("@s")).Players.Count == 1,
        "Targeting @s selects only the local player");
    Assert(targeting.ResolveTargets(TargetingCommandParser.ParseTarget("@a")).Players.Count == 2,
        "Targeting @a selects local and online players");
    var allTargets = targeting.ResolveTargets(TargetingCommandParser.ParseTarget("@e"));
    Assert(allTargets.Players.Count == 2 && allTargets.Entities.Count == 1,
        "Targeting @e combines players with non-player entities");
    var cowTargets = targeting.ResolveTargets(TargetingCommandParser.ParseTarget("minecraft:cow"));
    Assert(cowTargets.Entities.Count == 1 && cowTargets.Entities[0].UniqueId == 3003,
        "Targeting identifier selection falls back to definitions[0]");
    Assert(targeting.ResolveTargets(TargetingCommandParser.ParseTarget("2002")).Players.Count == 1,
        "Targeting online player UniqueID falls back to player_server_ key");

    var spawnBefore = targetingDb.ApplyBatchCount;
    _ = targeting.SpawnPoint(new SpawnPointTargetingCommandRequest(
        TargetingCommandParser.ParseTarget("@a"), 2, new BedrockBlockCoordinate(10, 80, -10)));
    Assert(targetingDb.ApplyBatchCount == spawnBefore + 1, "Targeting spawnpoint writes all players in one batch");
    var spawnPlayers = new PlayerNbtStore(targetingDb).Records();
    Assert(spawnPlayers.All(player => player.Document.Root.CompoundValueIgnoreCase("SpawnDimension")?.IntegerValue() == 2
                                      && player.Document.Root.CompoundValueIgnoreCase("SpawnForced")?.IntegerValue() == 1),
        "Targeting spawnpoint persists dimension and SpawnForced");
    _ = targeting.ClearSpawnPoint(new ClearSpawnPointTargetingCommandRequest(TargetingCommandParser.ParseTarget("@a")));
    Assert(new PlayerNbtStore(targetingDb).Records().All(player => player.Document.Root.CompoundValueIgnoreCase("SpawnX") is null),
        "Targeting clearspawnpoint removes player spawn tags");

    Assert(targeting.AutomaticTeleportY(0, 0, 0) == 65, "Targeting overworld Auto Y uses highest non-air block + 1");
    Assert(targeting.AutomaticTeleportY(0, 0, 1) == 65, "Targeting nether Auto Y skips roof/air and lands above lower solid");
    Assert(targeting.AutomaticTeleportY(8, 8, 2) is null, "Targeting Auto Y reports no generated solid column for fallback Y=63");

    _ = targeting.Teleport(new TeleportTargetingCommandRequest(
        TargetingCommandParser.ParseTarget("@s"), 0, 0, TargetingTeleportY.Auto, 0));
    var localAfterAuto = new PlayerNbtStore(targetingDb).Records().Single(player => player.IsLocal);
    var localAutoPosition = new PlayerNbtStore(targetingDb).CurrentPosition(localAfterAuto)!;
    Assert(Math.Abs(localAutoPosition.Y - 66.62) < 0.001,
        "Targeting player Auto teleport writes landing Y + 1.62");

    _ = targeting.Teleport((TeleportTargetingCommandRequest)TargetingCommandParser.Parse("teleport @s overworld 0 70.0 0"));
    var localAfterFloatY = new PlayerNbtStore(targetingDb).Records().Single(player => player.IsLocal);
    var localFloatPosition = new PlayerNbtStore(targetingDb).CurrentPosition(localAfterFloatY)!;
    Assert(Math.Abs(localFloatPosition.Y - 70.0) < 0.001,
        "Targeting player floating teleport Y is written verbatim without +1.62");

    _ = targeting.Teleport((TeleportTargetingCommandRequest)TargetingCommandParser.Parse("teleport minecraft:cow the_end 40.5 70.0 1.5"));
    var cowMoved = new BedrockWorldObjectScanner(targetingDb).ScanRegion(2, 0, 2, 0, true, false).Objects.Single();
    Assert(cowMoved.UniqueId == 3003 && cowMoved.Dimension == 2 && Math.Abs(cowMoved.Position!.Y - 70.0) < 0.001,
        "Targeting entity teleport reuses actor/digp relocation and keeps floating Y unchanged");

    var xpQuery = targeting.Experience(new ExperienceTargetingCommandRequest(
        TargetingExperienceOperationKind.Query, TargetingCommandParser.ParseTarget("@s")));
    Assert(!xpQuery.ChangedWorld && xpQuery.OutputLines.Count == 1 && xpQuery.OutputLines[0].Text.Contains("经验总数=", StringComparison.Ordinal),
        "Targeting experience query is read-only and returns player XP details");
    var xpBeforeBatch = targetingDb.ApplyBatchCount;
    _ = targeting.Experience(new ExperienceTargetingCommandRequest(
        TargetingExperienceOperationKind.Set, TargetingCommandParser.ParseTarget("@a"), 2500));
    Assert(targetingDb.ApplyBatchCount == xpBeforeBatch + 1,
        "Targeting experience set batches all player writes atomically");
    foreach (var player in new PlayerNbtStore(targetingDb).Records())
        Assert(TargetingCommandStore.ReadExperience(player.Document).Total == 2500,
            "Targeting experience set roundtrips through PlayerLevel/PlayerLevelProgress");

    var spreadResult = targeting.Spread(new SpreadTargetingCommandRequest(TargetingCommandParser.ParseTarget("@s")));
    Assert(spreadResult.ChangedWorld && spreadResult.OutputLines.Count == 1
           && spreadResult.OutputLines[0].Text.StartsWith("minecraft:player", StringComparison.Ordinal),
        "Targeting spread emits one player-first destination line");
}

var targetingWorldRoot = Path.Combine(Path.GetTempPath(), "MCBEEditor-Targeting-" + Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(targetingWorldRoot);
try
{
    var world = new WorldDocument(targetingWorldRoot);
    world.WriteLevelDat(new LevelDatFile(9, new NbtDocument("", new NbtCompoundValue([
        new NbtNamedTag("SpawnX", new NbtIntValue(0)),
        new NbtNamedTag("SpawnY", new NbtIntValue(64)),
        new NbtNamedTag("SpawnZ", new NbtIntValue(0))
    ]))));
    _ = TargetingCommandStore.SetWorldSpawn(world, new BedrockBlockCoordinate(-5, 90, 7));
    var spawnRoot = world.ReadLevelDat().Document.Root;
    Assert(spawnRoot.CompoundValueIgnoreCase("SpawnX")?.IntegerValue() == -5
           && spawnRoot.CompoundValueIgnoreCase("SpawnY")?.IntegerValue() == 90
           && spawnRoot.CompoundValueIgnoreCase("SpawnZ")?.IntegerValue() == 7,
        "Targeting setworldspawn writes all three level.dat spawn coordinates");
}
finally
{
    if (Directory.Exists(targetingWorldRoot)) Directory.Delete(targetingWorldRoot, recursive: true);
}

Console.WriteLine("MCBEEditor.Core self-test passed; selectors, spawn points, Auto teleport/spread, actor relocation and XP storage matched iOS command semantics.");

// item containers, entity lifecycle and ActiveEffects command parity.
var entityActionEffectParsed = (EffectEntityActionCommandRequest)EntityActionCommandParser.Parse("effect give @a strength -1 -1");
Assert(entityActionEffectParsed.Duration == -1 && entityActionEffectParsed.AmplifierRaw == 255 && entityActionEffectParsed.Selection.Id == 5,
    "EntityAction effect parser preserves Int32 duration and raw signed/unsigned Byte amplifier semantics");
var entityActionGiveParsed = (GiveEntityActionCommandRequest)EntityActionCommandParser.Parse("give @s 5 minecraft:diamond 3 'Short'\"Damage\"=\"1\"");
Assert(entityActionGiveParsed.Slot.Kind == EntityActionGiveSlotKind.Indexed && entityActionGiveParsed.Slot.Value == 5
       && entityActionGiveParsed.ItemTags.Count == 1 && entityActionGiveParsed.ItemTags[0].Name == "Damage",
    "EntityAction give parser accepts fixed slots and typed item NBT");
var entityActionProtectedSummonRejected = false;
try { _ = EntityActionCommandParser.Parse("summon minecraft:pig overworld 0 64 0 'Long'\"UniqueID\"=\"1\""); }
catch (InvalidDataException) { entityActionProtectedSummonRejected = true; }
Assert(entityActionProtectedSummonRejected, "EntityAction summon rejects command-controlled NBT tags");
var entityActionKickTargetRejected = false;
try { _ = EntityActionCommandParser.Parse("kick @s"); }
catch (InvalidDataException) { entityActionKickTargetRejected = true; }
Assert(entityActionKickTargetRejected, "EntityAction kick accepts only @a or an online-player UniqueID");

using (var entityActionDb = new SelfTestWorldDatabase())
{
    var inventory = Enumerable.Range(0, 36).Select(index => (NbtValue)new NbtCompoundValue([
        new NbtNamedTag("Name", new NbtStringValue(string.Empty)),
        new NbtNamedTag("Count", new NbtByteValue(0)),
        new NbtNamedTag("Slot", new NbtByteValue((sbyte)index))
    ])).ToArray();
    var localPlayer = new NbtDocument("", new NbtCompoundValue([
        new NbtNamedTag("PlayerName", new NbtStringValue("Local EntityAction")),
        new NbtNamedTag("UniqueID", new NbtLongValue(1001)),
        new NbtNamedTag("PlayerGameMode", new NbtIntValue(1)),
        new NbtNamedTag("DimensionId", new NbtIntValue(0)),
        new NbtNamedTag("Pos", new NbtListValue(NbtTagType.Float, [new NbtFloatValue(0.5f), new NbtFloatValue(65), new NbtFloatValue(0.5f)])),
        new NbtNamedTag("Inventory", new NbtListValue(NbtTagType.Compound, inventory)),
        new NbtNamedTag("Attributes", new NbtListValue(NbtTagType.Compound, [(NbtValue)new NbtCompoundValue([
            new NbtNamedTag("Name", new NbtStringValue("minecraft:health")),
            new NbtNamedTag("Current", new NbtFloatValue(20))
        ])]))
    ]));
    var onlinePlayer = new NbtDocument("", new NbtCompoundValue([
        new NbtNamedTag("PlayerName", new NbtStringValue("Online EntityAction")),
        new NbtNamedTag("UniqueID", new NbtLongValue(2002)),
        new NbtNamedTag("DimensionId", new NbtIntValue(0)),
        new NbtNamedTag("Pos", new NbtListValue(NbtTagType.Float, [new NbtFloatValue(1.5f), new NbtFloatValue(65), new NbtFloatValue(1.5f)])),
        new NbtNamedTag("Inventory", new NbtListValue(NbtTagType.Compound, inventory.Select(item => NbtDocumentTools.DeepClone(item)).ToArray())),
        new NbtNamedTag("Attributes", new NbtListValue(NbtTagType.Compound, [(NbtValue)new NbtCompoundValue([
            new NbtNamedTag("Name", new NbtStringValue("minecraft:health")),
            new NbtNamedTag("Current", new NbtFloatValue(20))
        ])]))
    ]));
    entityActionDb.Put(Encoding.UTF8.GetBytes("~local_player"), BedrockNbtCodec.Encode(localPlayer, NbtEncoding.LittleEndian));
    entityActionDb.Put(Encoding.UTF8.GetBytes("player_server_2002"), BedrockNbtCodec.Encode(onlinePlayer, NbtEncoding.LittleEndian));
    entityActionDb.Put(Encoding.UTF8.GetBytes("player_server_2002_meta"), [1, 2, 3]);
    entityActionDb.Put(Encoding.UTF8.GetBytes("player_data_2002"), [4, 5, 6]);

    var cowReference = new byte[8];
    BinaryPrimitives.WriteInt64LittleEndian(cowReference, 3003);
    var cowActorKey = Encoding.ASCII.GetBytes("actorprefix").Concat(cowReference).ToArray();
    var cowDigestKey = new byte[12];
    Encoding.ASCII.GetBytes("digp").CopyTo(cowDigestKey, 0);
    var cowDocument = new NbtDocument("", new NbtCompoundValue([
        new NbtNamedTag("identifier", new NbtStringValue("minecraft:cow")),
        new NbtNamedTag("definitions", new NbtListValue(NbtTagType.String, [new NbtStringValue("+minecraft:cow")])),
        new NbtNamedTag("UniqueID", new NbtLongValue(3003)),
        new NbtNamedTag("DimensionId", new NbtIntValue(0)),
        new NbtNamedTag("Pos", new NbtListValue(NbtTagType.Float, [new NbtFloatValue(2.5f), new NbtFloatValue(65), new NbtFloatValue(2.5f)])),
        new NbtNamedTag("Mainhand", new NbtCompoundValue([
            new NbtNamedTag("Name", new NbtStringValue("minecraft:stick")), new NbtNamedTag("Count", new NbtByteValue(1))
        ])),
        new NbtNamedTag("ChestItems", new NbtListValue(NbtTagType.Compound, [
            (NbtValue)new NbtCompoundValue([new NbtNamedTag("Name", new NbtStringValue("minecraft:stone")), new NbtNamedTag("Slot", new NbtByteValue(0))]),
            (NbtValue)new NbtCompoundValue([new NbtNamedTag("Name", new NbtStringValue("minecraft:dirt")), new NbtNamedTag("Slot", new NbtByteValue(1))])
        ])),
        new NbtNamedTag("Offers", new NbtCompoundValue([new NbtNamedTag("marker", new NbtIntValue(123))])),
        new NbtNamedTag("Attributes", new NbtListValue(NbtTagType.Compound, [(NbtValue)new NbtCompoundValue([
            new NbtNamedTag("Name", new NbtStringValue("minecraft:health")), new NbtNamedTag("Current", new NbtFloatValue(10))
        ])]))
    ]));
    entityActionDb.Put(cowDigestKey, cowReference);
    entityActionDb.Put(cowActorKey, BedrockNbtCodec.Encode(cowDocument, NbtEncoding.LittleEndian));

    var entityAction = new EntityActionCommandStore(entityActionDb);
    var giveBefore = entityActionDb.ApplyBatchCount;
    _ = entityAction.Give((GiveEntityActionCommandRequest)EntityActionCommandParser.Parse("give @a Auto minecraft:diamond 64 NULL"));
    Assert(entityActionDb.ApplyBatchCount == giveBefore + 1, "EntityAction give batches all selected player inventory writes");
    foreach (var player in new PlayerNbtStore(entityActionDb).Records())
    {
        var playerInventory = (NbtListValue)player.Document.Root.CompoundValueIgnoreCase("Inventory")!;
        var slot0 = (NbtCompoundValue)playerInventory.Values[0];
        Assert((slot0.CompoundValueIgnoreCase("Name") as NbtStringValue)?.Value == "minecraft:diamond"
               && slot0.CompoundValueIgnoreCase("Count")?.IntegerValue() == 64,
            "EntityAction player give Auto fills the first empty Inventory slot");
    }

    _ = entityAction.Give((GiveEntityActionCommandRequest)EntityActionCommandParser.Parse("give minecraft:cow 5 minecraft:emerald 9 NULL"));
    var cowAfterGive = new BedrockWorldObjectScanner(entityActionDb).ScanAll(null, true, false, int.MaxValue).Objects.Single(item => item.UniqueId == 3003);
    var chestAfterGive = (NbtListValue)cowAfterGive.Document.Root.CompoundValueIgnoreCase("ChestItems")!;
    var lastChest = (NbtCompoundValue)chestAfterGive.Values[^1];
    var mainhandAfterGive = (NbtCompoundValue)cowAfterGive.Document.Root.CompoundValueIgnoreCase("Mainhand")!;
    Assert((lastChest.CompoundValueIgnoreCase("Name") as NbtStringValue)?.Value == "minecraft:emerald"
           && (mainhandAfterGive.CompoundValueIgnoreCase("Name") as NbtStringValue)?.Value == "minecraft:emerald",
        "EntityAction entity give overflows ChestItems into the last slot and existing Mainhand together");

    _ = entityAction.Effect((EffectEntityActionCommandRequest)EntityActionCommandParser.Parse("effect give @e strength 12000 50"));
    var effectedPlayers = new PlayerNbtStore(entityActionDb).Records();
    Assert(effectedPlayers.All(player => player.Document.Root.CompoundValueIgnoreCase("ActiveEffects") is NbtListValue),
        "EntityAction effect give writes ActiveEffects for players");
    var effectedCow = new BedrockWorldObjectScanner(entityActionDb).ScanAll(null, true, false, int.MaxValue).Objects.Single(item => item.UniqueId == 3003);
    var cowEffects = (NbtListValue)effectedCow.Document.Root.CompoundValueIgnoreCase("ActiveEffects")!;
    var strength = (NbtCompoundValue)cowEffects.Values.Single();
    Assert(strength.CompoundValueIgnoreCase("Id")?.IntegerValue() == 5
           && strength.CompoundValueIgnoreCase("Duration")?.IntegerValue() == 12000
           && strength.CompoundValueIgnoreCase("Amplifier")?.IntegerValue() == 50,
        "EntityAction effect give persists Bedrock effect ID/duration/amplifier fields");
    _ = entityAction.Effect((EffectEntityActionCommandRequest)EntityActionCommandParser.Parse("effect clear minecraft:cow strength"));
    var cowAfterEffectClear = new BedrockWorldObjectScanner(entityActionDb).ScanAll(null, true, false, int.MaxValue).Objects.Single(item => item.UniqueId == 3003);
    Assert(cowAfterEffectClear.Document.Root.CompoundValueIgnoreCase("ActiveEffects") is null,
        "EntityAction effect clear removes an empty ActiveEffects list");

    _ = entityAction.Clear(new ClearEntityActionCommandRequest(TargetingCommandParser.ParseTarget("minecraft:cow")));
    var cowAfterClear = new BedrockWorldObjectScanner(entityActionDb).ScanAll(null, true, false, int.MaxValue).Objects.Single(item => item.UniqueId == 3003);
    Assert(((NbtListValue)cowAfterClear.Document.Root.CompoundValueIgnoreCase("ChestItems")!).Values.Count == 0
           && ((NbtCompoundValue)cowAfterClear.Document.Root.CompoundValueIgnoreCase("Mainhand")!).Tags.Count == 0
           && cowAfterClear.Document.Root.CompoundValueIgnoreCase("Offers") is NbtCompoundValue offers && offers.Tags.Count == 1,
        "EntityAction clear empties item containers while preserving villager trade containers");

    _ = entityAction.Kill((KillEntityActionCommandRequest)EntityActionCommandParser.Parse("kill @e 0"));
    var localAfterKill = new PlayerNbtStore(entityActionDb).Records().Single(record => record.IsLocal);
    var onlineAfterKill = new PlayerNbtStore(entityActionDb).Records().Single(record => !record.IsLocal);
    Assert(localAfterKill.Document.Root.CompoundValueIgnoreCase("Attributes") is NbtListValue localAttributes
           && ((NbtCompoundValue)localAttributes.Values[0]).CompoundValueIgnoreCase("Current")?.IntegerValue() == 20,
        "EntityAction kill skips creative players when the second parameter is 0");
    Assert(onlineAfterKill.Document.Root.CompoundValueIgnoreCase("Attributes") is NbtListValue onlineAttributes
           && ((NbtCompoundValue)onlineAttributes.Values[0]).CompoundValueIgnoreCase("Current") is NbtFloatValue onlineHealth
           && onlineHealth.Value == 0,
        "EntityAction kill sets non-creative player Health Current to 0.0");
    Assert(new BedrockWorldObjectScanner(entityActionDb).ScanAll(null, true, false, int.MaxValue).Objects.All(item => item.UniqueId != 3003),
        "EntityAction kill deletes non-player entities and cleans their actor ownership");

    var kickResult = entityAction.Kick((KickEntityActionCommandRequest)EntityActionCommandParser.Parse("kick 2002"));
    Assert(kickResult.ChangedWorld && new PlayerNbtStore(entityActionDb).Records().All(record => record.IsLocal)
           && entityActionDb.Get(Encoding.UTF8.GetBytes("player_server_2002_meta")) is null
           && entityActionDb.Get(Encoding.UTF8.GetBytes("player_data_2002")) is null,
        "EntityAction kick removes the selected online player and related player-key families but keeps local player data");
}

using (var entityActionSummonDb = new SelfTestWorldDatabase())
{
    var entityAction = new EntityActionCommandStore(entityActionSummonDb);
    var summonResult = entityAction.Summon((SummonEntityActionCommandRequest)EntityActionCommandParser.Parse(
        "summon minecraft:pig overworld 10.5 64.25 -3.75 'Byte'\"Invulnerable\"=\"1\",'String'\"CustomName\"=\"MyPig\""));
    Assert(summonResult.ChangedWorld, "EntityAction summon reports a world mutation");
    var pig = new BedrockWorldObjectScanner(entityActionSummonDb).ScanAll(null, true, false, int.MaxValue).Objects.Single();
    Assert(pig.Identifier == "minecraft:pig" && Math.Abs(pig.Position!.X - 10.5) < 0.001
           && pig.Document.Root.CompoundValueIgnoreCase("Invulnerable")?.IntegerValue() == 1
           && (pig.Document.Root.CompoundValueIgnoreCase("CustomName") as NbtStringValue)?.Value == "MyPig",
        "EntityAction summon creates a selectable entity with floating Pos and top-level NBT additions");
}

Console.WriteLine("MCBEEditor.Core self-test passed; clear/give/effect/kill/kick/summon matched current iOS command semantics.");

// level.dat world state plus native tickingarea persistence.
var environmentQuery = (TimeEnvironmentCommandRequest)EnvironmentCommandParser.Parse("time query daytime");
Assert(!environmentQuery.IsDestructive && environmentQuery.Query == EnvironmentTimeQueryKind.Daytime,
    "Environment time query is read-only and parses daytime");
var environmentWeather = (WeatherEnvironmentCommandRequest)EnvironmentCommandParser.Parse("weather thunder 12000 1.0 0");
Assert(environmentWeather.Condition == EnvironmentWeatherCondition.Thunder && environmentWeather.Duration == 12000
       && environmentWeather.Intensity == 1.0f && !environmentWeather.AutomaticChange,
    "Environment weather parser preserves duration/intensity/cycle flag");
var environmentCircle = (TickingAreaEnvironmentCommandRequest)EnvironmentCommandParser.Parse("tickingarea add circle overworld -2 3 4 Spawn 1");
var environmentCircleArea = environmentCircle.Area ?? throw new InvalidOperationException("Environment circle parse did not return an area");
Assert(environmentCircleArea is { IsCircle: true, MinimumX: -96, MaximumX: 32, MinimumZ: -16, MaximumZ: 112, Preload: true }
       && environmentCircleArea.CenterChunk == (-2, 3) && environmentCircleArea.Radius == 4,
    "Environment circle tickingarea converts chunk center/radius to persisted block bounds");
var environmentOversizedRejected = false;
try { _ = EnvironmentCommandParser.Parse("tickingarea add square overworld 0 0 10 9 TooBig 0"); }
catch (InvalidDataException) { environmentOversizedRejected = true; }
Assert(environmentOversizedRejected, "Environment tickingarea parser rejects areas larger than 100 chunks");
Assert(EnvironmentCommandStore.FloorDivision(-1, 24_000) == -1
       && EnvironmentCommandStore.PositiveRemainder(-1, 24_000) == 23_999
       && EnvironmentCommandStore.AlignedTime(5_000, 12_001, true) == 36_001,
    "Environment negative-time floor/remainder and iOS ceil alignment semantics match");

var environmentWorldRoot = Path.Combine(Path.GetTempPath(), "MCBEEditor-Environment-" + Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(environmentWorldRoot);
try
{
    var world = new WorldDocument(environmentWorldRoot);
    world.WriteLevelDat(new LevelDatFile(9, new NbtDocument("", new NbtCompoundValue([
        new NbtNamedTag("Time", new NbtLongValue(-1_000)),
        new NbtNamedTag("dodaylightcycle", new NbtByteValue(1)),
        new NbtNamedTag("rainLevel", new NbtFloatValue(0)),
        new NbtNamedTag("rainTime", new NbtIntValue(0)),
        new NbtNamedTag("lightningLevel", new NbtFloatValue(0)),
        new NbtNamedTag("lightningTime", new NbtIntValue(0)),
        new NbtNamedTag("doWeatherCycle", new NbtByteValue(1))
    ]))));

    using var environmentDb = new SelfTestWorldDatabase();
    static NbtDocument MakeTickingAreaDocument(int dimension, bool isCircle, int minX, int minZ, int maxX, int maxZ, string name, bool preload) =>
        new("", new NbtCompoundValue([
            new NbtNamedTag("Dimension", new NbtIntValue(dimension)),
            new NbtNamedTag("IsCircle", new NbtByteValue(isCircle ? (sbyte)1 : (sbyte)0)),
            new NbtNamedTag("MinX", new NbtIntValue(minX)),
            new NbtNamedTag("MinZ", new NbtIntValue(minZ)),
            new NbtNamedTag("MaxX", new NbtIntValue(maxX)),
            new NbtNamedTag("MaxZ", new NbtIntValue(maxZ)),
            new NbtNamedTag("Name", new NbtStringValue(name)),
            new NbtNamedTag("Preload", new NbtByteValue(preload ? (sbyte)1 : (sbyte)0))
        ]));
    environmentDb.Put(Encoding.UTF8.GetBytes("tickingarea_test_a"),
        BedrockNbtCodec.Encode(MakeTickingAreaDocument(0, false, 0, 0, 1, 1, "AreaA", false), NbtEncoding.LittleEndian));
    environmentDb.Put(Encoding.UTF8.GetBytes("tickingarea_test_b"),
        BedrockNbtCodec.Encode(MakeTickingAreaDocument(1, true, -16, -16, 16, 16, "AreaB", true), NbtEncoding.LittleEndian));

    var environment = new EnvironmentCommandStore(world, environmentDb);
    var dayQuery = environment.Execute(EnvironmentCommandParser.Parse("time query day"));
    Assert(!dayQuery.ChangedWorld && dayQuery.Message == "day=-1", "Environment time day query floors negative game time like iOS");
    var daytimeQuery = environment.Execute(EnvironmentCommandParser.Parse("time query daytime"));
    Assert(daytimeQuery.Message.StartsWith("daytime=23000，日出", StringComparison.Ordinal),
        "Environment daytime query uses positive 0..23999 remainder");

    _ = environment.Execute(EnvironmentCommandParser.Parse("time set 5000"));
    _ = environment.Execute(EnvironmentCommandParser.Parse("time ceil sunset"));
    Assert(world.ReadLevelDat().Document.Root.CompoundValueIgnoreCase("Time")?.IntegerValue() == 36_001,
        "Environment time ceil persists the iOS day-alignment result");
    _ = environment.Execute(EnvironmentCommandParser.Parse("daylock 1"));
    Assert(world.ReadLevelDat().Document.Root.CompoundValueIgnoreCase("dodaylightcycle")?.IntegerValue() == 0,
        "Environment daylock disables dodaylightcycle");
    _ = environment.Execute(EnvironmentCommandParser.Parse("weather thunder 12000 0.75 0"));
    var weatherRoot = world.ReadLevelDat().Document.Root;
    Assert(weatherRoot.CompoundValueIgnoreCase("rainLevel") is NbtFloatValue { Value: 0.75f }
           && weatherRoot.CompoundValueIgnoreCase("lightningLevel") is NbtFloatValue { Value: 0.75f }
           && weatherRoot.CompoundValueIgnoreCase("rainTime")?.IntegerValue() == 12000
           && weatherRoot.CompoundValueIgnoreCase("doWeatherCycle")?.IntegerValue() == 0,
        "Environment thunder writes both rain/lightning state and doWeatherCycle");

    var nativeList = environment.Execute(EnvironmentCommandParser.Parse("tickingarea list ALL"));
    Assert(!nativeList.ChangedWorld && nativeList.OutputLines.Count == 2,
        "Environment tickingarea list reads native tickingarea_* records");

    _ = environment.Execute(EnvironmentCommandParser.Parse("tickingarea add square the_end 4 5 6 7 Base 1"));
    var nativeAreas = environmentDb.Entries(Encoding.UTF8.GetBytes("tickingarea_"), includeValues: true).ToArray();
    Assert(nativeAreas.Length == 3 && nativeAreas.All(entry => entry.Value is { Length: > 0 } && ConsecutiveNbtCodec.Decode(entry.Value!).Count == 1),
        "Environment tickingarea writes one ordinary NBT document per tickingarea_* key");

    _ = environment.Execute(EnvironmentCommandParser.Parse("tickingarea add square overworld 8 8 8 8 base 0"));
    var afterReplace = environment.Execute(EnvironmentCommandParser.Parse("tickingarea list ALL"));
    Assert(afterReplace.OutputLines.Count == 3 && afterReplace.OutputLines.Any(line => line.Text.Contains("base", StringComparison.Ordinal)),
        "Environment tickingarea add replaces same-name areas case-insensitively");
    _ = environment.Execute(EnvironmentCommandParser.Parse("tickingarea delete ALL"));
    Assert(!environmentDb.Entries(Encoding.UTF8.GetBytes("tickingarea_"), includeValues: false).Any(),
        "Environment tickingarea delete ALL removes native records");
}
finally
{
    if (Directory.Exists(environmentWorldRoot)) Directory.Delete(environmentWorldRoot, recursive: true);
}

Console.WriteLine("MCBEEditor.Core self-test passed; daylock/time/weather and tickingarea persistence matched current iOS command semantics.");


// Bedrock structuretemplate save/load/delete command parity.
var structureTemplateSaveRequest = StructureTemplateCommandParser.Parse("structure save test:house overworld 0 0 0 1 0 0");
Assert(structureTemplateSaveRequest.Operation == StructureTemplateStructureOperationKind.Save && structureTemplateSaveRequest.Name == "test:house"
       && structureTemplateSaveRequest.Region?.Volume == 2,
    "StructureTemplate structure save parser preserves namespaced name/dimension/region");
var structureTemplateLoadRequest = StructureTemplateCommandParser.Parse("structure load test:house the_end -10 64 20");
Assert(structureTemplateLoadRequest.Operation == StructureTemplateStructureOperationKind.Load && structureTemplateLoadRequest.Dimension == 2
       && structureTemplateLoadRequest.Destination == new BedrockBlockCoordinate(-10, 64, 20),
    "StructureTemplate structure load parser preserves target dimension/destination");
var structureTemplateBadNameRejected = false;
try { _ = StructureTemplateCommandParser.Parse("structure save House overworld 0 0 0 0 0 0"); }
catch (InvalidDataException) { structureTemplateBadNameRejected = true; }
Assert(structureTemplateBadNameRejected, "StructureTemplate structure names require namespace:name syntax like iOS");

using (var structureTemplateDb = new SelfTestWorldDatabase())
{
    var structureTemplateRegions = new BedrockRegionBlockStore(structureTemplateDb);
    var structureTemplateStone = new BedrockBlockStorageSpec("minecraft:stone", []);
    var structureTemplateDirt = new BedrockBlockStorageSpec("minecraft:dirt", []);
    _ = structureTemplateRegions.Fill(0,
        new BedrockBlockBox(new BedrockBlockCoordinate(0, 0, 0), new BedrockBlockCoordinate(0, 0, 0)),
        [structureTemplateStone]);
    _ = structureTemplateRegions.Fill(0,
        new BedrockBlockBox(new BedrockBlockCoordinate(1, 0, 0), new BedrockBlockCoordinate(1, 0, 0)),
        [structureTemplateDirt]);

    var structureTemplateSourceChunk = new ChunkPosition(0, 0, 0);
    var structureTemplateSourceBeKey = new BedrockDbKey(structureTemplateSourceChunk, ChunkRecordType.BlockEntity, null).Encode();
    var structureTemplateSourceBe = new NbtDocument("", new NbtCompoundValue([
        new NbtNamedTag("id", new NbtStringValue("Chest")),
        new NbtNamedTag("x", new NbtIntValue(0)),
        new NbtNamedTag("y", new NbtIntValue(0)),
        new NbtNamedTag("z", new NbtIntValue(0)),
        new NbtNamedTag("CustomName", new NbtStringValue("StructureTemplateChest"))
    ]));
    structureTemplateDb.Put(structureTemplateSourceBeKey, BedrockNbtCodec.Encode(structureTemplateSourceBe, NbtEncoding.LittleEndian));

    var structureTemplateStore = new StructureTemplateCommandStore(structureTemplateDb);
    var structureTemplateSaved = structureTemplateStore.Execute(StructureTemplateCommandParser.Parse("structure save test:pair overworld 0 0 0 1 0 0"));
    Assert(structureTemplateSaved.ChangedWorld && structureTemplateStore.Contains("test:pair"),
        "StructureTemplate structure save writes a structuretemplate_<name> record");
    var structureTemplateRaw = structureTemplateDb.Get(StructureTemplateCommandStore.StructureKey("test:pair"))!;
    var structureTemplateDocument = NbtFileCodec.DecodeSingle(structureTemplateRaw).Document;
    Assert(structureTemplateDocument.Root.CompoundValue("size") is NbtListValue structureTemplateSize && structureTemplateSize.Values.Count == 3
           && structureTemplateDocument.Root.CompoundValue("structure")?.CompoundValue("palette") is NbtCompoundValue,
        "StructureTemplate saved structure uses Bedrock mcstructure size/structure/palette schema");

    _ = structureTemplateStore.Execute(StructureTemplateCommandParser.Parse("structure load test:pair overworld 32 16 32"));
    var structureTemplateBlocks = new BedrockBlockStore(structureTemplateDb);
    var structureTemplatePlaced0 = structureTemplateBlocks.ReadBlock(0, 32, 16, 32);
    var structureTemplatePlaced1 = structureTemplateBlocks.ReadBlock(0, 33, 16, 32);
    Assert(structureTemplatePlaced0.Generated && structureTemplatePlaced0.Layers[0].Name == "minecraft:stone"
           && structureTemplatePlaced1.Generated && structureTemplatePlaced1.Layers[0].Name == "minecraft:dirt",
        "StructureTemplate structure load restores palette-backed blocks at destination offset");
    var structureTemplateTargetBeKey = new BedrockDbKey(new ChunkPosition(2, 2, 0), ChunkRecordType.BlockEntity, null).Encode();
    var structureTemplateTargetBeRaw = structureTemplateDb.Get(structureTemplateTargetBeKey);
    Assert(structureTemplateTargetBeRaw is not null && ConsecutiveNbtCodec.Decode(structureTemplateTargetBeRaw).Any(record =>
        record.Document.Root.CompoundValue("x")?.IntegerValue() == 32
        && record.Document.Root.CompoundValue("y")?.IntegerValue() == 16
        && record.Document.Root.CompoundValue("z")?.IntegerValue() == 32
        && (record.Document.Root.CompoundValue("CustomName") as NbtStringValue)?.Value == "StructureTemplateChest"),
        "StructureTemplate structure load offsets BlockEntity coordinates with the placed structure");

    _ = structureTemplateStore.Execute(StructureTemplateCommandParser.Parse("structure save test:second overworld 0 0 0 0 0 0"));
    _ = structureTemplateStore.Execute(StructureTemplateCommandParser.Parse("structure delete test:pair"));
    Assert(!structureTemplateStore.Contains("test:pair") && structureTemplateStore.Contains("test:second"),
        "StructureTemplate structure delete removes only the selected structure");
    _ = structureTemplateStore.Execute(StructureTemplateCommandParser.Parse("structure delete ALL"));
    Assert(!structureTemplateDb.Entries(System.Text.Encoding.UTF8.GetBytes(StructureTemplateCommandStore.StructureKeyPrefix), false).Any(),
        "StructureTemplate structure delete ALL removes every structuretemplate record");
}

Console.WriteLine("MCBEEditor.Core self-test passed; structuretemplate save/load/delete, palette blocks and BlockEntity offsets matched current iOS semantics.");


// iOS NBT workspace parity stores (metadata, structure, village).
using (var metadataWorkspaceMetadataDb = new SelfTestWorldDatabase())
{
    var metadataWorkspaceMetadataDocA = new NbtDocument("", new NbtCompoundValue([
        new NbtNamedTag("Value", new NbtIntValue(1))
    ]));
    var metadataWorkspaceMetadataDocB = new NbtDocument("", new NbtCompoundValue([
        new NbtNamedTag("Name", new NbtStringValue("second"))
    ]));
    var metadataWorkspaceScoreboardKey = Encoding.UTF8.GetBytes("scoreboard");
    metadataWorkspaceMetadataDb.Put(metadataWorkspaceScoreboardKey, ConsecutiveNbtCodec.Encode([
        new ConsecutiveNbtRecord(metadataWorkspaceMetadataDocA, [], NbtEncoding.LittleEndian),
        new ConsecutiveNbtRecord(metadataWorkspaceMetadataDocB, [], NbtEncoding.LittleEndian)
    ]));
    metadataWorkspaceMetadataDb.Put(Encoding.UTF8.GetBytes("map_7"), BedrockNbtCodec.Encode(metadataWorkspaceMetadataDocA, NbtEncoding.LittleEndian));
    metadataWorkspaceMetadataDb.Put(Encoding.UTF8.GetBytes("not_metadata"), BedrockNbtCodec.Encode(metadataWorkspaceMetadataDocA, NbtEncoding.LittleEndian));

    var metadataWorkspaceMetadataStore = new MetadataNbtStore(metadataWorkspaceMetadataDb);
    var metadataWorkspaceMetadataRecords = metadataWorkspaceMetadataStore.Records();
    Assert(metadataWorkspaceMetadataRecords.Count == 2 && metadataWorkspaceMetadataRecords.Any(record => record.KeyText == "scoreboard")
           && metadataWorkspaceMetadataRecords.Any(record => record.KeyText == "map_7"),
        " metadata workspace filters exact world-data and map_* keys only");
    var metadataWorkspaceScoreboard = metadataWorkspaceMetadataRecords.Single(record => record.KeyText == "scoreboard");
    Assert(metadataWorkspaceScoreboard.Roots?.Count == 2, " metadata workspace decodes consecutive NBT roots");
    var metadataWorkspaceEditedRoots = metadataWorkspaceScoreboard.Roots!.ToArray();
    metadataWorkspaceEditedRoots[0] = metadataWorkspaceEditedRoots[0] with
    {
        Document = new NbtDocument("", new NbtCompoundValue([new NbtNamedTag("Value", new NbtIntValue(9))]))
    };
    metadataWorkspaceMetadataStore.Save(metadataWorkspaceScoreboard, metadataWorkspaceEditedRoots);
    Assert(ConsecutiveNbtCodec.Decode(metadataWorkspaceMetadataDb.Get(metadataWorkspaceScoreboardKey)!)[0].Document.Root.CompoundValue("Value")?.IntegerValue() == 9,
        " metadata consecutive-root edits persist without dropping sibling roots");

    var metadataWorkspaceCreatedMetadata = metadataWorkspaceMetadataStore.Create("map_8", [metadataWorkspaceMetadataDocB]);
    metadataWorkspaceMetadataStore.Rename(metadataWorkspaceCreatedMetadata, "map_9");
    Assert(metadataWorkspaceMetadataDb.Get(Encoding.UTF8.GetBytes("map_8")) is null
           && metadataWorkspaceMetadataDb.Get(Encoding.UTF8.GetBytes("map_9")) is not null,
        " metadata rename atomically moves the raw LevelDB value");
    var metadataWorkspaceRenamedMetadata = metadataWorkspaceMetadataStore.Record(Encoding.UTF8.GetBytes("map_9"))!;
    metadataWorkspaceMetadataStore.Delete(metadataWorkspaceRenamedMetadata);
    Assert(metadataWorkspaceMetadataDb.Get(Encoding.UTF8.GetBytes("map_9")) is null,
        " metadata delete removes the selected key");

    var metadataWorkspaceBatchA = metadataWorkspaceMetadataStore.Create("map_10", [metadataWorkspaceMetadataDocA]);
    var metadataWorkspaceBatchB = metadataWorkspaceMetadataStore.Create("map_11", [metadataWorkspaceMetadataDocB]);
    metadataWorkspaceMetadataStore.RenameBatch([
        new MetadataNbtRename(metadataWorkspaceBatchA, "map_11"),
        new MetadataNbtRename(metadataWorkspaceBatchB, "map_10")
    ]);
    Assert(metadataWorkspaceMetadataStore.Record(Encoding.UTF8.GetBytes("map_10"))?.Roots?[0].Document.Root.StringValue("Name") == "second"
           && metadataWorkspaceMetadataStore.Record(Encoding.UTF8.GetBytes("map_11"))?.Roots?[0].Document.Root.CompoundValue("Value")?.IntegerValue() == 1,
        " metadata batch rename supports selected-source swaps without losing raw values");

    var metadataWorkspaceInvalidMetadataRejected = false;
    try { _ = MetadataNbtStore.ValidateKeyText("random_key"); }
    catch (NotSupportedException) { metadataWorkspaceInvalidMetadataRejected = true; }
    Assert(metadataWorkspaceInvalidMetadataRejected, " metadata creation rejects keys outside the iOS supported metadata families");
}

using (var metadataWorkspaceStructureDb = new SelfTestWorldDatabase())
{
    var metadataWorkspaceStructureDocument = new NbtDocument("", new NbtCompoundValue([
        new NbtNamedTag("format_version", new NbtIntValue(1)),
        new NbtNamedTag("size", new NbtListValue(NbtTagType.Int, [new NbtIntValue(1), new NbtIntValue(1), new NbtIntValue(1)])),
        new NbtNamedTag("structure_world_origin", new NbtListValue(NbtTagType.Int, [new NbtIntValue(4), new NbtIntValue(5), new NbtIntValue(6)])),
        new NbtNamedTag("structure", new NbtCompoundValue([
            new NbtNamedTag("block_indices", new NbtListValue(NbtTagType.List, [
                new NbtListValue(NbtTagType.Int, [new NbtIntValue(0)]),
                new NbtListValue(NbtTagType.Int, [new NbtIntValue(-1)])
            ])),
            new NbtNamedTag("entities", new NbtListValue(NbtTagType.End, [])),
            new NbtNamedTag("palette", new NbtCompoundValue([
                new NbtNamedTag("default", new NbtCompoundValue([
                    new NbtNamedTag("block_palette", new NbtListValue(NbtTagType.Compound, [
                        new NbtCompoundValue([
                            new NbtNamedTag("name", new NbtStringValue("minecraft:stone")),
                            new NbtNamedTag("states", new NbtCompoundValue([])),
                            new NbtNamedTag("version", new NbtIntValue(17_959_425))
                        ])
                    ])),
                    new NbtNamedTag("block_position_data", new NbtCompoundValue([]))
                ]))
            ]))
        ]))
    ]));
    var metadataWorkspaceStructureStore = new StructureNbtStore(metadataWorkspaceStructureDb);
    var metadataWorkspaceMalformedStructureRejected = false;
    try
    {
        metadataWorkspaceStructureStore.SaveNew(new NbtDocument("", new NbtCompoundValue([
            new NbtNamedTag("size", new NbtListValue(NbtTagType.Int, [new NbtIntValue(1), new NbtIntValue(1), new NbtIntValue(1)])),
            new NbtNamedTag("palette", new NbtListValue(NbtTagType.Compound, [])),
            new NbtNamedTag("blocks", new NbtListValue(NbtTagType.Compound, []))
        ])), "test:java", overwrite: false);
    }
    catch (InvalidDataException) { metadataWorkspaceMalformedStructureRejected = true; }
    Assert(metadataWorkspaceMalformedStructureRejected && !metadataWorkspaceStructureStore.Contains("test:java"),
        "Structure workspace rejects malformed empty Java palettes instead of writing an invalid structuretemplate");

    metadataWorkspaceStructureStore.SaveNew(metadataWorkspaceStructureDocument, "test:nbt", overwrite: false);
    var metadataWorkspaceStructureRecord = metadataWorkspaceStructureStore.Records().Single();
    Assert(metadataWorkspaceStructureRecord.DisplayName == "test:nbt" && metadataWorkspaceStructureRecord.DetailText.Contains("1×1×1", StringComparison.Ordinal),
        " structure NBT workspace scans structuretemplate records and exposes dimensions");
    var metadataWorkspaceEditedStructure = new NbtDocument("", new NbtCompoundValue([
        new NbtNamedTag("format_version", new NbtIntValue(2)),
        new NbtNamedTag("size", new NbtListValue(NbtTagType.Int, [new NbtIntValue(1), new NbtIntValue(1), new NbtIntValue(1)])),
        new NbtNamedTag("structure", new NbtCompoundValue([]))
    ]));
    metadataWorkspaceStructureStore.Save(metadataWorkspaceStructureRecord, metadataWorkspaceEditedStructure);
    var metadataWorkspaceStructureAfterSave = metadataWorkspaceStructureStore.Records().Single();
    Assert(metadataWorkspaceStructureAfterSave.Document?.Root.IntValue("format_version") == 2,
        " structure NBT edits preserve the detected NBT encoding and persist");
    metadataWorkspaceStructureStore.Rename(metadataWorkspaceStructureAfterSave, "test:renamed", overwrite: false);
    Assert(!metadataWorkspaceStructureStore.Contains("test:nbt") && metadataWorkspaceStructureStore.Contains("test:renamed"),
        " structure NBT rename moves the structuretemplate key");
    var metadataWorkspaceRenamedStructure = metadataWorkspaceStructureStore.Records().Single();
    metadataWorkspaceStructureStore.Delete(metadataWorkspaceRenamedStructure);
    Assert(metadataWorkspaceStructureStore.Records().Count == 0, " structure NBT delete removes the selected template");
}

using (var metadataWorkspaceVillageDb = new SelfTestWorldDatabase())
{
    var metadataWorkspaceModernVillageDoc = new NbtDocument("", new NbtCompoundValue([
        new NbtNamedTag("Name", new NbtStringValue("before")),
        new NbtNamedTag("Dimension", new NbtIntValue(0))
    ]));
    var metadataWorkspaceModernVillageKey = Encoding.UTF8.GetBytes("VILLAGE_alpha_INFO");
    metadataWorkspaceVillageDb.Put(metadataWorkspaceModernVillageKey, ConsecutiveNbtCodec.Encode([
        new ConsecutiveNbtRecord(metadataWorkspaceModernVillageDoc, [], NbtEncoding.LittleEndian)
    ]));

    var metadataWorkspaceLegacyVillageRoot = new NbtDocument("", new NbtCompoundValue([
        new NbtNamedTag("Villages", new NbtListValue(NbtTagType.Compound, [
            new NbtCompoundValue([new NbtNamedTag("UUID", new NbtStringValue("legacy-a")), new NbtNamedTag("Population", new NbtIntValue(3))]),
            new NbtCompoundValue([new NbtNamedTag("UUID", new NbtStringValue("legacy-b")), new NbtNamedTag("Population", new NbtIntValue(4))])
        ]))
    ]));
    metadataWorkspaceVillageDb.Put(Encoding.UTF8.GetBytes("mVillages"), ConsecutiveNbtCodec.Encode([
        new ConsecutiveNbtRecord(metadataWorkspaceLegacyVillageRoot, [], NbtEncoding.LittleEndian)
    ]));

    var metadataWorkspaceVillageStore = new VillageNbtStore(metadataWorkspaceVillageDb);
    var metadataWorkspaceVillageScan = metadataWorkspaceVillageStore.ScanRecords();
    Assert(metadataWorkspaceVillageScan.Diagnostics.Count == 0
           && metadataWorkspaceVillageScan.Records.Count(record => record.Kind == VillageNbtRecordKind.Legacy) == 2
           && metadataWorkspaceVillageScan.Records.Any(record => record.Kind == VillageNbtRecordKind.Info && record.VillageIdentifier == "alpha"),
        " village workspace splits legacy mVillages while also scanning modern VILLAGE_* records");

    var metadataWorkspaceModernVillageRecord = metadataWorkspaceVillageScan.Records.Single(record => record.Kind == VillageNbtRecordKind.Info);
    metadataWorkspaceVillageStore.Save(metadataWorkspaceModernVillageRecord, new NbtDocument("", new NbtCompoundValue([
        new NbtNamedTag("Name", new NbtStringValue("after")),
        new NbtNamedTag("Dimension", new NbtIntValue(0))
    ])));
    Assert(ConsecutiveNbtCodec.Decode(metadataWorkspaceVillageDb.Get(metadataWorkspaceModernVillageKey)!)[0].Document.Root.StringValue("Name") == "after",
        " modern village NBT edit writes back to its VILLAGE_* record");

    var metadataWorkspaceLegacyVillageRecord = metadataWorkspaceVillageStore.ScanRecords().Records
        .Single(record => record.Kind == VillageNbtRecordKind.Legacy && record.LegacyVillageIndex == 1);
    metadataWorkspaceVillageStore.Save(metadataWorkspaceLegacyVillageRecord, new NbtDocument("Village 2", new NbtCompoundValue([
        new NbtNamedTag("UUID", new NbtStringValue("legacy-b")),
        new NbtNamedTag("Population", new NbtIntValue(99))
    ])));
    var metadataWorkspaceLegacyDecoded = ConsecutiveNbtCodec.Decode(metadataWorkspaceVillageDb.Get(Encoding.UTF8.GetBytes("mVillages"))!)[0].Document;
    var metadataWorkspaceLegacyList = metadataWorkspaceLegacyDecoded.Root.CompoundValue("Villages") as NbtListValue;
    Assert(metadataWorkspaceLegacyList is not null && metadataWorkspaceLegacyList.Values.Count == 2
           && metadataWorkspaceLegacyList.Values[0].CompoundValue("Population")?.IntegerValue() == 3
           && metadataWorkspaceLegacyList.Values[1].CompoundValue("Population")?.IntegerValue() == 99,
        " legacy village nested edit replaces only the selected village subtree");
}

Console.WriteLine("MCBEEditor.Core self-test passed; metadata/structure/village NBT workspace stores and legacy nested writes matched current iOS semantics.");


// map render parity (height / biome / ticking areas / slime chunks).
Assert(BedrockBiomeCatalog.ColorForId(1) == 0x7AAD52, " plains biome colour matches iOS catalog");
Assert(BedrockBiomeCatalog.ColorForId(0) == 0x1A61B8, " ocean biome colour matches iOS catalog");
Assert(!BedrockSlimeChunk.IsSlimeChunk(0, 0) && BedrockSlimeChunk.IsSlimeChunk(-1, 0)
       && BedrockSlimeChunk.IsSlimeChunk(3, 0),
    " Bedrock slime-chunk MT19937 coordinate vectors");

using (var mapRenderMapDb = new SelfTestWorldDatabase())
{
    var mapRenderPosition = new ChunkPosition(0, 0, 0);
    var mapRenderWater = NamedState("minecraft:water");
    var mapRenderStorage = new SubChunkStorage(0, [mapRenderWater], new ushort[4096]);
    var mapRenderSubChunk = new BedrockSubChunk(9, 0, [mapRenderStorage], []);
    mapRenderMapDb.Put(new BedrockDbKey(mapRenderPosition, ChunkRecordType.Version, null).Encode(), [40]);
    mapRenderMapDb.Put(BedrockDbKey.SubChunk(0, 0, 0, 0), mapRenderSubChunk.EncodePersistent());

    var mapRenderBiomeIds = Enumerable.Repeat(1u, 256).ToArray();
    var mapRenderBiomeDocument = new BedrockBiomeDocument(
        BedrockBiomeFormat.Data2D,
        new short[256],
        [new BedrockBiomeLayer(null, mapRenderBiomeIds, false)]);
    mapRenderMapDb.Put(new BedrockDbKey(mapRenderPosition, ChunkRecordType.Data2D, null).Encode(), mapRenderBiomeDocument.Encode());

    var mapRenderHeight = new BedrockSurfaceRenderer(mapRenderMapDb).RenderChunk(mapRenderPosition, BedrockMapRenderMode.Height);
    Assert(mapRenderHeight.Generated && mapRenderHeight.Heights.All(value => value == 15)
           && mapRenderHeight.Rgb.Distinct().Count() == 1
           && mapRenderHeight.Rgb[0] != BedrockBlockMapColorCatalog.ColorFor(mapRenderWater),
        " height mode uses visible Y and height gradient instead of surface block colour");

    var mapRenderBiome = new BedrockSurfaceRenderer(mapRenderMapDb).RenderChunk(mapRenderPosition, BedrockMapRenderMode.Biome);
    Assert(mapRenderBiome.BiomeIds.All(value => value == 1)
           && mapRenderBiome.Rgb.All(value => value == BedrockBiomeCatalog.ColorForId(1)),
        " biome mode reads Data2D at visible columns and applies catalog colours");

    var mapRenderCrossBiome = new BedrockCrossSectionRenderer(mapRenderMapDb).Render(
        BedrockMapAxis.X, fixedX: 0, fixedZ: 0, centerY: 8, sideBlocks: 16,
        dimension: 0, mode: BedrockMapRenderMode.Biome, drawSubChunkGrid: false,
        drawBuildHeightLimits: false);
    var mapRenderCrossIndex = mapRenderCrossBiome.Index(0 - mapRenderCrossBiome.OriginHorizontal, mapRenderCrossBiome.MaximumY - 8);
    Assert(mapRenderCrossBiome.BiomeIds[mapRenderCrossIndex] == 1
           && mapRenderCrossBiome.Rgb[mapRenderCrossIndex] == BedrockBiomeCatalog.ColorForId(1),
        " X/Z biome property mode reads the exact selected plane");
}

using (var mapRenderSyntheticDb = new SelfTestWorldDatabase())
{
    static NbtDocument TickingAreaDocument(bool preload, int minX, int minZ, int maxX, int maxZ, string name) =>
        new("", new NbtCompoundValue([
            new NbtNamedTag("Dimension", new NbtIntValue(0)),
            new NbtNamedTag("IsCircle", new NbtByteValue(0)),
            new NbtNamedTag("MinX", new NbtIntValue(minX)),
            new NbtNamedTag("MinZ", new NbtIntValue(minZ)),
            new NbtNamedTag("MaxX", new NbtIntValue(maxX)),
            new NbtNamedTag("MaxZ", new NbtIntValue(maxZ)),
            new NbtNamedTag("Name", new NbtStringValue(name)),
            new NbtNamedTag("Preload", new NbtByteValue(preload ? (sbyte)1 : (sbyte)0))
        ]));

    mapRenderSyntheticDb.Put(Encoding.UTF8.GetBytes("tickingarea_mapRender_a"),
        BedrockNbtCodec.Encode(TickingAreaDocument(false, 0, 0, 1, 1, "normal"), NbtEncoding.LittleEndian));
    mapRenderSyntheticDb.Put(Encoding.UTF8.GetBytes("tickingarea_mapRender_b"),
        BedrockNbtCodec.Encode(TickingAreaDocument(true, 0, 0, 0, 0, "preload"), NbtEncoding.LittleEndian));

    var mapRenderTicking = new BedrockSurfaceRegionRenderer(mapRenderSyntheticDb).Render(
        0, 0, 0, 1, drawChunkGrid: false, mode: BedrockMapRenderMode.TickingAreas);
    Assert(mapRenderTicking.TickingAreaCount == 2 && mapRenderTicking.TickingDefinedChunkCount == 5
           && mapRenderTicking.VisibleTickingChunkCount == 4,
        " ticking-area map reports area/defined/visible chunk counts");
    var mapRenderChunk00 = mapRenderTicking.Index(16, 16);
    var mapRenderChunk11 = mapRenderTicking.Index(32, 32);
    Assert(mapRenderTicking.BlockNames[mapRenderChunk00] == "mcbeeditor:overlap_ticking_chunk"
           && mapRenderTicking.BlockNames[mapRenderChunk11] == "mcbeeditor:ticking_chunk",
        " ticking-area map distinguishes overlap and ordinary chunks");

    var mapRenderSlime = new BedrockSurfaceRegionRenderer(mapRenderSyntheticDb).Render(
        0, 0, 0, 1, drawChunkGrid: false, mode: BedrockMapRenderMode.Slime);
    var mapRenderMinusOneZero = mapRenderSlime.Index(0, 16);
    var mapRenderZeroZero = mapRenderSlime.Index(16, 16);
    Assert(mapRenderSlime.GeneratedChunkCount == 9 && mapRenderSlime.MissingChunkCount == 0
           && mapRenderSlime.BlockNames[mapRenderMinusOneZero] == "mcbeeditor:slime_chunk"
           && mapRenderSlime.BlockNames[mapRenderZeroZero] == "mcbeeditor:non_slime_chunk",
        " slime mode is synthetic for generated and ungenerated chunks alike");
}

Console.WriteLine("MCBEEditor.Core self-test passed; height/biome/ticking/slime map modes matched current iOS semantics.");


// static map overlays and selected-region advanced operations.
using (var regionSearchDb = new SelfTestWorldDatabase())
{
    var area = new HardcodedSpawnerArea(-16, 40, 32, -1, 80, 47, 5);
    var encoded = new HardcodedSpawnersDocument([area]).Encode();
    var decoded = HardcodedSpawnersDocument.Decode(encoded);
    Assert(decoded.Areas.Count == 1 && decoded.Areas[0] == area && encoded.Length == 29,
        " HardcodedSpawners 25-byte area binary round-trip");
    var spawnerStore = new HardcodedSpawnersStore(regionSearchDb);
    var spawnerPosition = new ChunkPosition(-1, 2, 0);
    var emptyRecord = spawnerStore.Read(spawnerPosition);
    spawnerStore.Save(emptyRecord with { Document = new HardcodedSpawnersDocument([area]) });
    Assert(spawnerStore.Read(spawnerPosition).Document.Areas.Single() == area,
        " HardcodedSpawners chunk record saves and reads 0x39 payload");
    spawnerStore.Save(spawnerStore.Read(spawnerPosition) with { Document = new HardcodedSpawnersDocument([]) });
    Assert(regionSearchDb.Get(new BedrockDbKey(spawnerPosition, ChunkRecordType.HardcodedSpawners, null).Encode()) is null,
        " saving an empty HardcodedSpawners document deletes the 0x39 key");

    var villageKey = Encoding.UTF8.GetBytes("VILLAGE_regionSearch_INFO");
    var villageInfo = new NbtDocument("", new NbtCompoundValue([
        new NbtNamedTag("Dimension", new NbtIntValue(0)),
        new NbtNamedTag("X0", new NbtIntValue(10)), new NbtNamedTag("Z0", new NbtIntValue(20)),
        new NbtNamedTag("X1", new NbtIntValue(30)), new NbtNamedTag("Z1", new NbtIntValue(40)),
        new NbtNamedTag("Center", new NbtCompoundValue([
            new NbtNamedTag("X", new NbtIntValue(20)), new NbtNamedTag("Y", new NbtIntValue(64)), new NbtNamedTag("Z", new NbtIntValue(30))
        ]))
    ]));
    regionSearchDb.Put(villageKey, ConsecutiveNbtCodec.Encode([new ConsecutiveNbtRecord(villageInfo, [], NbtEncoding.LittleEndian)]));
    var villagePoiKey = Encoding.UTF8.GetBytes("VILLAGE_regionSearch_POI");
    var villagePoi = new NbtDocument("", new NbtCompoundValue([
        new NbtNamedTag("pois", new NbtListValue(NbtTagType.Compound, [
            new NbtCompoundValue([
                new NbtNamedTag("X", new NbtIntValue(14)),
                new NbtNamedTag("Y", new NbtIntValue(65)),
                new NbtNamedTag("Z", new NbtIntValue(24))
            ])
        ]))
    ]));
    regionSearchDb.Put(villagePoiKey, ConsecutiveNbtCodec.Encode([new ConsecutiveNbtRecord(villagePoi, [], NbtEncoding.LittleEndian)]));
    var villageFeature = new VillageMapFeatureStore(regionSearchDb).Features().Single();
    Assert(villageFeature.Bounds is { MinimumX: 10, MinimumZ: 20, MaximumX: 30, MaximumZ: 40 }
           && villageFeature.Center is { X: 20, Y: 64, Z: 30 },
        " village overlay extracts explicit X0/Z0/X1/Z1 bounds and center");
    Assert(villageFeature.PointsOfInterest.Any(point => point is { X: 14, Y: 65, Z: 24 }),
        " village overlay parses POI coordinates from the matching VILLAGE_*_POI record");

    var overlayTempWorld = Path.Combine(Path.GetTempPath(), "mcbe-overlay-spawn-" + Guid.NewGuid().ToString("N"));
    Directory.CreateDirectory(overlayTempWorld);
    try
    {
        var spawnWorld = new WorldDocument(overlayTempWorld);
        spawnWorld.WriteLevelDat(new LevelDatFile(10, new NbtDocument("", new NbtCompoundValue([
            new NbtNamedTag("SpawnX", new NbtIntValue(11)),
            new NbtNamedTag("SpawnY", new NbtIntValue(70)),
            new NbtNamedTag("SpawnZ", new NbtIntValue(-9))
        ]))));
        var localPlayer = new NbtDocument("", new NbtCompoundValue([
            new NbtNamedTag("SpawnX", new NbtIntValue(4)),
            new NbtNamedTag("SpawnY", new NbtIntValue(65)),
            new NbtNamedTag("SpawnZ", new NbtIntValue(6)),
            new NbtNamedTag("SpawnDimension", new NbtIntValue(1)),
            new NbtNamedTag("SpawnForced", new NbtByteValue(1))
        ]));
        regionSearchDb.Put(Encoding.UTF8.GetBytes("~local_player"), BedrockNbtCodec.Encode(localPlayer, NbtEncoding.LittleEndian));
        var spawnFeatures = SpawnMapFeatureStore.Read(spawnWorld, regionSearchDb);
        Assert(spawnFeatures.Any(feature => feature is { IsWorldSpawn: true, Dimension: 0, X: 11, Y: 70, Z: -9 })
               && spawnFeatures.Any(feature => !feature.IsWorldSpawn && feature is { Dimension: 1, X: 4, Y: 65, Z: 6, Forced: true }),
            " spawn overlay reads world level.dat and per-player Spawn* fields including dimension/forced state");
    }
    finally
    {
        try { Directory.Delete(overlayTempWorld, recursive: true); } catch { }
    }

    var position = new ChunkPosition(0, 0, 0);
    var stone = NamedState("minecraft:stone");
    var air16 = NamedState("minecraft:air");
    var indices = new ushort[4096];
    Array.Fill(indices, (ushort)0);
    var palette = new[] { stone, air16 };
    var storage = new SubChunkStorage(1, palette, indices);
    var sub = new BedrockSubChunk(9, 0, [storage], []);
    regionSearchDb.Put(BedrockDbKey.SubChunk(0, 0, 0, 0), sub.EncodePersistent());
    regionSearchDb.Put(new BedrockDbKey(position, ChunkRecordType.Version, null).Encode(), [40]);
    var advanced = new BedrockRegionAdvancedStore(regionSearchDb);
    var search = advanced.Search(0, 0, 0, 1, 1, "stone", BedrockRegionStorageScope.Layer0, maximumHits: 1000);
    Assert(search.Hits.Count == 64 && search.Hits.All(hit => hit.StorageIndex == 0 && hit.Name == "minecraft:stone"),
        " region search returns exact X/Y/Z/storage hits within the selected X/Z columns");
    var replaced = advanced.ReplaceCoordinated(0, 0, 0, 0, 0, new BedrockRegionCoordinatedOperation(
        new BedrockRegionBlockSearchCriteria("minecraft:stone", []), null, BedrockRegionStorageScope.Layer0,
        new BedrockRegionBlockReplacement("minecraft:diamond_block", [], ReplaceAllStates: true), false, null));
    Assert(replaced.MatchedPositions == 16,
        " region search/replace only changes matching blocks inside the selected X/Z columns");
    var readBack = new BedrockBlockStore(regionSearchDb).ReadBlock(0, 0, 0, 0);
    Assert(readBack.Layers[0].Name == "minecraft:diamond_block",
        " region replacement persists through the normal SubChunk storage codec");

    // iOS parity: bulk layer replacement skips completely-air cells by default and creates a missing layer 1 on demand.
    var sparsePosition = new ChunkPosition(1, 0, 0);
    var sparseIndices = new ushort[4096];
    sparseIndices[0] = 1;
    var sparseStorage = new SubChunkStorage(1, [NamedState("minecraft:air"), NamedState("minecraft:stone")], sparseIndices);
    var sparseSub = new BedrockSubChunk(9, 0, [sparseStorage], []);
    regionSearchDb.Put(BedrockDbKey.SubChunk(1, 0, 0, 0), sparseSub.EncodePersistent());
    regionSearchDb.Put(new BedrockDbKey(sparsePosition, ChunkRecordType.Version, null).Encode(), [40]);
    var bulkLayer = advanced.ReplaceWholeStorage(0, 16, 0, 16, 0, 1, "minecraft:gold_block", includeCompletelyAirCells: false);
    Assert(bulkLayer.MatchedPositions == 1,
        " bulk layer replacement skips coordinates where layer 0 and layer 1 are both air");
    var sparseRead = new BedrockBlockStore(regionSearchDb).ReadBlock(0, 16, 0, 0);
    Assert(sparseRead.Layers.Count >= 2 && sparseRead.Layers[1].Name == "minecraft:gold_block",
        " bulk layer replacement creates a missing storage 1 when the selected coordinate is eligible");

    // iOS parity: a layer-1 search can select a coordinate while the replacement is applied to layer 0.
    var goldCriteria = new BedrockRegionBlockSearchCriteria("gold", []);
    var coordinated = new BedrockRegionCoordinatedOperation(
        null, goldCriteria, BedrockRegionStorageScope.Layer1,
        new BedrockRegionBlockReplacement("minecraft:emerald_block", [], ReplaceAllStates: true),
        false, null);
    var coordinatedResult = advanced.ReplaceCoordinated(0, 16, 0, 16, 0, coordinated);
    Assert(coordinatedResult.MatchedPositions == 1,
        " coordinated search selects one X/Y/Z coordinate from storage 1");
    sparseRead = new BedrockBlockStore(regionSearchDb).ReadBlock(0, 16, 0, 0);
    Assert(sparseRead.Layers[0].Name == "minecraft:emerald_block" && sparseRead.Layers[1].Name == "minecraft:gold_block",
        " coordinated replacement changes storage 0 at a coordinate selected by storage 1 without altering storage 1");

    var copiedRegion = advanced.CopyRegion(0, 16, 0, 16, 0, 0, 32, 0);
    var copiedRead = new BedrockBlockStore(regionSearchDb).ReadBlock(0, 32, 0, 0);
    Assert(!copiedRegion.UsedWholeChunkCopy && copiedRead.Layers.Count >= 2
           && copiedRead.Layers[0].Name == "minecraft:emerald_block"
           && copiedRead.Layers[1].Name == "minecraft:gold_block",
        " partial region copy snapshots and writes both editable storages to an equally-sized target region");
}


// information/tool parity: data-value catalogs, dedicated weather/time/experience stores and .mcworld export.
Assert(BedrockDataValueCatalog.Entities.Count == 141
       && BedrockDataValueCatalog.StatusEffects.Count == 37
       && BedrockDataValueCatalog.Enchantments.Count == 42
       && BedrockDataValueCatalog.LegacyBlocks.Count == 256,
    " data-value catalogs match the current iOS table sizes");
var slimeValues = BedrockDataValueCatalog.Search(BedrockDataValueCatalog.Entities, "0x25");
Assert(slimeValues.Any(item => item.Id == 37 && item.Identifier == "minecraft:slime"),
    " data-value search accepts hexadecimal IDs");

var worldToolsTempRoot = Path.Combine(Path.GetTempPath(), "MCBEEditor--" + Guid.NewGuid().ToString("N"));
var worldToolsWorldRoot = Path.Combine(worldToolsTempRoot, "World");
var worldToolsArchive = Path.Combine(worldToolsTempRoot, "World.mcworld");
Directory.CreateDirectory(worldToolsWorldRoot);
try
{
    var worldToolsWorld = new WorldDocument(worldToolsWorldRoot);
    worldToolsWorld.WriteLevelDat(new LevelDatFile(10, new NbtDocument("", new NbtCompoundValue([
        new NbtNamedTag("LevelName", new NbtStringValue("")),
        new NbtNamedTag("rainLevel", new NbtFloatValue(0.25f)),
        new NbtNamedTag("rainTime", new NbtIntValue(200)),
        new NbtNamedTag("lightningLevel", new NbtFloatValue(0)),
        new NbtNamedTag("lightningTime", new NbtIntValue(100)),
        new NbtNamedTag("doWeatherCycle", new NbtByteValue(1)),
        new NbtNamedTag("Time", new NbtLongValue(-1)),
        new NbtNamedTag("dodaylightcycle", new NbtByteValue(1))
    ]))));
    File.WriteAllText(Path.Combine(worldToolsWorldRoot, "levelname.txt"), "");
    Directory.CreateDirectory(Path.Combine(worldToolsWorldRoot, ".mcbeeditor"));
    File.WriteAllText(Path.Combine(worldToolsWorldRoot, ".mcbeeditor", "settings.json"), "{}");
    File.WriteAllText(Path.Combine(worldToolsWorldRoot, "map-display-preferences.json"), "{}");
    Directory.CreateDirectory(Path.Combine(worldToolsWorldRoot, "resource_packs", "example"));
    File.WriteAllText(Path.Combine(worldToolsWorldRoot, "resource_packs", "example", "manifest.json"), "{}");

    var weather = WorldWeatherStore.Read(worldToolsWorld);
    Assert(weather.RainLevel == 0.25f && weather.RainTime == 200 && weather.AutomaticChange,
        " weather editor store reads current level.dat fields");
    WorldWeatherStore.Save(worldToolsWorld, BedrockWeatherSettings.Thunder(12_000, 0.75f, false));
    weather = WorldWeatherStore.Read(worldToolsWorld);
    Assert(Math.Abs(weather.RainLevel - 0.75f) < 0.0001f && Math.Abs(weather.LightningLevel - 0.75f) < 0.0001f
           && weather.RainTime == 12_000 && weather.LightningTime == 12_000 && !weather.AutomaticChange,
        " weather editor store writes thunder fields exactly");

    var timeSettings = WorldTimeStore.Read(worldToolsWorld);
    Assert(timeSettings.Time == -1 && timeSettings.Day == -1 && timeSettings.Daytime == 23_999,
        " time editor preserves negative Int64 time floor/remainder semantics");
    WorldTimeStore.Save(worldToolsWorld, new BedrockTimeSettings(18_000, false));
    timeSettings = WorldTimeStore.Read(worldToolsWorld);
    Assert(timeSettings.Time == 18_000 && !timeSettings.AutomaticProgression && timeSettings.Summary.Contains("夜晚", StringComparison.Ordinal),
        " time editor writes Time and dodaylightcycle");

    WorldArchiveService.ExportMcworld(worldToolsWorld, worldToolsArchive);
    using (var archive = ZipFile.OpenRead(worldToolsArchive))
    {
        Assert(archive.Entries.Any(entry => entry.FullName == "level.dat")
               && archive.Entries.Any(entry => entry.FullName == "levelname.txt")
               && archive.Entries.Any(entry => entry.FullName == "resource_packs/example/manifest.json"),
            ".mcworld export archives ordinary world contents without an extra directory level");
        Assert(!archive.Entries.Any(entry => entry.FullName.Contains("mcbeeditor", StringComparison.OrdinalIgnoreCase)
                                             || entry.FullName.EndsWith("map-display-preferences.json", StringComparison.OrdinalIgnoreCase)),
            ".mcworld export excludes editor-owned settings and metadata");
    }
}
finally
{
    try { Directory.Delete(worldToolsTempRoot, recursive: true); } catch { }
}

using (var worldToolsDb = new SelfTestWorldDatabase())
{
    var xpPlayer = new NbtDocument("", new NbtCompoundValue([
        new NbtNamedTag("UniqueID", new NbtLongValue(777)),
        new NbtNamedTag("PlayerLevel", new NbtIntValue(10)),
        new NbtNamedTag("PlayerLevelProgress", new NbtFloatValue(0.5f)),
        new NbtNamedTag("XpTotal", new NbtIntValue(123))
    ]));
    worldToolsDb.Put(Encoding.UTF8.GetBytes("~local_player"), BedrockNbtCodec.Encode(xpPlayer, NbtEncoding.LittleEndian));
    var xpRecords = WorldExperienceStore.Records(worldToolsDb);
    Assert(xpRecords.Count == 1 && xpRecords[0].UniqueId == 777 && xpRecords[0].Experience.Level == 10,
        " experience editor lists player records and reads stored level/progress");
    var worldToolsXp2500 = BedrockPlayerExperience.FromTotal(2500);
    WorldExperienceStore.Save(worldToolsDb, xpRecords[0].Player, worldToolsXp2500);
    var savedXp = PlayerNbtStoreForWorldTools(worldToolsDb);
    Assert(TargetingCommandStore.ReadExperience(savedXp.Document).Total == 2500
           && savedXp.Document.Root.IntValue("XpTotal") == 123,
        "Experience editor updates Bedrock level/progress fields without migrating unrelated historical tags");
}

RunPortableWorkspaceLegacyTerrainSelfTest();
RunStandaloneNbtConversionSelfTest();
RunChunkConvenienceSelfTest();
RunDynamicMapVillagePoiSelfTest();
RunMapViewportPolicySelfTest();
RunMapPickerTextureSelfTest();
RunCrossSectionProjectionSelfTest();

static void RunMapViewportPolicySelfTest()
{
    var exactPlan = MapRenderSamplingPlan.Create(sideChunks: 511, leftChunks: 255, maximumSamplesPerAxis: 512);
    Assert(exactPlan.Stride == 1 && !exactPlan.IsDownsampled && exactPlan.XAxis.Count == 511,
        " Windows detail-first sampling remains exact through 511 chunks per axis");

    var hugePlan = MapRenderSamplingPlan.Create(sideChunks: 513, leftChunks: 256, maximumSamplesPerAxis: 512);
    Assert(hugePlan.Stride == 2 && hugePlan.IsDownsampled && hugePlan.XAxis.Count <= 512,
        " representative sampling begins only after the 512-chunk desktop detail budget is exceeded");

    Assert(MapViewportPolicy.NeedsRecentering(
            visibleMinimumA: 320, visibleMaximumA: 995,
            visibleMinimumB: 320, visibleMaximumB: 680,
            renderedMinimumA: 0, renderedMaximumA: 1024,
            renderedMinimumB: 0, renderedMaximumB: 1024),
        " viewport reload detects a visible edge entering the preload band even when the viewport center is still safe");

    Assert(!MapViewportPolicy.NeedsRecentering(
            visibleMinimumA: 128, visibleMaximumA: 896,
            visibleMinimumB: 128, visibleMaximumB: 896,
            renderedMinimumA: 0, renderedMaximumA: 1024,
            renderedMinimumB: 0, renderedMaximumB: 1024),
        " viewport reload remains idle while every visible edge stays inside the preload band");

    Console.WriteLine("MCBEEditor.Core self-test passed; desktop edge-preload and detail-first map sampling policies matched the Windows parity target.");
}

static void RunMapPickerTextureSelfTest()
{
    using var pickerDb = new SelfTestWorldDatabase();
    var picker = new BedrockBlockPickerService(pickerDb);
    var column = picker.BlockColumn(3, -5, 2);
    Assert(column.Blocks.Count == 384 && column.Blocks[0].Y == 319 && column.Blocks[^1].Y == -64,
        " block-column picker keeps the iOS default -4...19 SubChunk range in descending Y order");
    Assert(column.Blocks.All(block => block.X == 3 && block.Z == -5 && block.Dimension == 2 && !block.Generated),
        " missing block-column cells remain selectable editable-air records");
    var axisLine = picker.BlockAxisLine(BedrockMapAxis.X, fixedY: 70, fixedX: 0, fixedZ: 9,
        minimumCoordinate: -128, maximumCoordinate: 128, dimension: 0);
    Assert(axisLine.Blocks.Count == 257 && axisLine.Blocks[0].X == 128 && axisLine.Blocks[^1].X == -128
           && axisLine.Blocks.All(block => block.Y == 70 && block.Z == 9),
        " X/Z picker exposes the complete +/-128 manual-selection line in descending axis order");

    var texturedMissing = new BedrockSurfaceRegionRenderer(pickerDb).Render(
        dimension: 0, centerBlockX: 0, centerBlockZ: 0, chunkRadius: 1,
        drawChunkGrid: false, mode: BedrockMapRenderMode.Surface,
        maximumSamplesPerAxis: 16, maximumRasterSide: 256, showUngeneratedTexture: true);
    Assert(texturedMissing.Rgb.Contains(BedrockBlockMapColorCatalog.UngeneratedLineRgb),
        " ungenerated top-down layer paints the shared diagonal texture when enabled");
    var texturedCross = new BedrockCrossSectionRenderer(pickerDb).Render(
        BedrockMapAxis.X, fixedX: 0, fixedZ: 0, centerY: 64, sideBlocks: 48,
        dimension: 0, mode: BedrockMapRenderMode.Surface, drawSubChunkGrid: false,
        drawBuildHeightLimits: false, maximumRasterSide: 256, showUngeneratedTexture: true);
    Assert(texturedCross.Rgb.Contains(BedrockBlockMapColorCatalog.UngeneratedLineRgb),
        " ungenerated X/Z layer paints missing SubChunks with the matching diagonal texture");

    Console.WriteLine("MCBEEditor.Core self-test passed; block pickers and ungenerated map textures matched the iOS parity target.");
}


static void RunCrossSectionProjectionSelfTest()
{
    using var db = new SelfTestWorldDatabase();
    var air = BedrockBlockState.EditableAir();
    var stone = NamedState("minecraft:stone");
    var diamond = NamedState("minecraft:diamond_ore");

    // Current X section plane is X=2, so its chunk is X=0..15. Put a stone at
    // the positive edge of that same chunk and a diamond immediately behind
    // the plane in chunk -1. iOS parity requires the ungenerated layer to
    // project only the current 16-block chunk, while the normal view scans
    // from the current plane toward negative X.
    var currentIndices = new ushort[4096];
    currentIndices[(15 << 8) | (5 << 4) | 8] = 1;
    var currentStorage = new SubChunkStorage(1, [air, stone], currentIndices);
    var currentSub = new BedrockSubChunk(9, 0, [currentStorage], []);
    var currentPos = new ChunkPosition(0, 0, 0);
    db.Put(new BedrockDbKey(currentPos, ChunkRecordType.Version, null).Encode(), [40]);
    db.Put(BedrockDbKey.SubChunk(0, 0, 0, 0), currentSub.EncodePersistent());

    var behindIndices = new ushort[4096];
    behindIndices[(15 << 8) | (5 << 4) | 8] = 1; // world X=-1
    var behindStorage = new SubChunkStorage(1, [air, diamond], behindIndices);
    var behindSub = new BedrockSubChunk(9, 0, [behindStorage], []);
    var behindPos = new ChunkPosition(-1, 0, 0);
    db.Put(new BedrockDbKey(behindPos, ChunkRecordType.Version, null).Encode(), [40]);
    db.Put(BedrockDbKey.SubChunk(-1, 0, 0, 0), behindSub.EncodePersistent());

    var normal = new BedrockCrossSectionRenderer(db).Render(
        BedrockMapAxis.X, fixedX: 2, fixedZ: 5, centerY: 8, sideBlocks: 16,
        dimension: 0, mode: BedrockMapRenderMode.Surface, drawSubChunkGrid: false,
        drawBuildHeightLimits: false, projectionDepth: 128, showUngeneratedTexture: false);
    var normalIndex = normal.Index(5 - normal.OriginHorizontal, normal.MaximumY - 8);
    Assert(normal.BlockNames[normalIndex] == "minecraft:diamond_ore" && normal.BlockX[normalIndex] == -1,
        " normal X/Z view projects from the current plane toward the negative axis");

    var chunkOnly = new BedrockCrossSectionRenderer(db).Render(
        BedrockMapAxis.X, fixedX: 2, fixedZ: 5, centerY: 8, sideBlocks: 16,
        dimension: 0, mode: BedrockMapRenderMode.Surface, drawSubChunkGrid: false,
        drawBuildHeightLimits: false, projectionDepth: 128, showUngeneratedTexture: true);
    var chunkOnlyIndex = chunkOnly.Index(5 - chunkOnly.OriginHorizontal, chunkOnly.MaximumY - 8);
    Assert(chunkOnly.BlockNames[chunkOnlyIndex] == "minecraft:stone" && chunkOnly.BlockX[chunkOnlyIndex] == 15,
        " ungenerated X/Z view projects only the selected plane's current 16-block chunk");

    var explicitExportRange = new BedrockCrossSectionRenderer(db).Render(
        BedrockMapAxis.X, fixedX: 2, fixedZ: 5, centerY: 8, sideBlocks: 16,
        dimension: 0, mode: BedrockMapRenderMode.Surface, drawSubChunkGrid: false,
        drawBuildHeightLimits: false, projectionDepth: 128,
        projectionDirection: BedrockProjectionDirection.PositiveToNegative,
        showUngeneratedTexture: false,
        projectionMinimumCoordinateOverride: -1,
        projectionMaximumCoordinateOverride: 15);
    var explicitExportIndex = explicitExportRange.Index(5 - explicitExportRange.OriginHorizontal, explicitExportRange.MaximumY - 8);
    Assert(explicitExportRange.ProjectionDepth == 17
           && explicitExportRange.BlockNames[explicitExportIndex] == "minecraft:stone"
           && explicitExportRange.BlockX[explicitExportIndex] == 15,
        " explicit PNG projection range overrides the live-view 128-block ray without changing live map semantics");

    // Regression: if the selected X plane itself has no SubChunk, hiding the
    // ungenerated layer must still project through the missing front section
    // and find generated terrain within the 128-block negative-direction ray.
    using (var missingFrontDb = new SelfTestWorldDatabase())
    {
        var projectedIndices = new ushort[4096];
        projectedIndices[(15 << 8) | (5 << 4) | 8] = 1; // world X=15, Z=5, Y=8
        var projectedStorage = new SubChunkStorage(1, [air, stone], projectedIndices);
        var projectedSub = new BedrockSubChunk(9, 0, [projectedStorage], []);
        var projectedPos = new ChunkPosition(0, 0, 0);
        missingFrontDb.Put(new BedrockDbKey(projectedPos, ChunkRecordType.Version, null).Encode(), [40]);
        missingFrontDb.Put(BedrockDbKey.SubChunk(0, 0, 0, 0), projectedSub.EncodePersistent());

        var fullProjection = new BedrockCrossSectionRenderer(missingFrontDb).Render(
            BedrockMapAxis.X, fixedX: 32, fixedZ: 5, centerY: 8, sideBlocks: 16,
            dimension: 0, mode: BedrockMapRenderMode.Surface, drawSubChunkGrid: false,
            drawBuildHeightLimits: false, projectionDepth: 128, showUngeneratedTexture: false);
        var projectedIndex = fullProjection.Index(5 - fullProjection.OriginHorizontal, fullProjection.MaximumY - 8);
        Assert(fullProjection.Generated[projectedIndex]
               && fullProjection.BlockNames[projectedIndex] == "minecraft:stone"
               && fullProjection.BlockX[projectedIndex] == 15,
            " hidden ungenerated layer keeps the full 128-block X/Z projection even when the front SubChunk is missing");

        var frontOnly = new BedrockCrossSectionRenderer(missingFrontDb).Render(
            BedrockMapAxis.X, fixedX: 32, fixedZ: 5, centerY: 8, sideBlocks: 16,
            dimension: 0, mode: BedrockMapRenderMode.Surface, drawSubChunkGrid: false,
            drawBuildHeightLimits: false, projectionDepth: 128, showUngeneratedTexture: true);
        var frontOnlyIndex = frontOnly.Index(5 - frontOnly.OriginHorizontal, frontOnly.MaximumY - 8);
        Assert(!frontOnly.Generated[frontOnlyIndex] && frontOnly.BlockNames[frontOnlyIndex] == "minecraft:air",
            " visible ungenerated layer stops at the missing current-chunk projection instead of borrowing terrain behind it");
    }

    Console.WriteLine("MCBEEditor.Core self-test passed; X/Z current-chunk and 128-block projection rules matched iOS.");
}

static void RunDynamicMapVillagePoiSelfTest()
{
    var dynamicMapPlan = MapRenderSamplingPlan.Create(sideChunks: 129, leftChunks: 64, maximumSamplesPerAxis: 64);
    Assert(dynamicMapPlan.Stride == 3 && dynamicMapPlan.XAxis.Count <= 64 && dynamicMapPlan.ZAxis.Count <= 64,
        " top-down sampling caps each axis and uses ceiling representative stride");
    Assert(dynamicMapPlan.XAxis.Any(sample => sample.StartOffset <= 0 && sample.EndOffset >= 0 && sample.RepresentativeOffset == 0),
        " sampling keeps the center chunk as the representative for the center tile");

    using var dynamicMapDb = new SelfTestWorldDatabase();
    var dynamicMapSurface = new BedrockSurfaceRegionRenderer(dynamicMapDb).Render(
        dimension: 0, centerBlockX: 0, centerBlockZ: 0, chunkRadius: 40,
        drawChunkGrid: false, mode: BedrockMapRenderMode.Slime,
        maximumSamplesPerAxis: 64, maximumRasterSide: 512);
    Assert(dynamicMapSurface.IsDownsampled && dynamicMapSurface.LogicalWidthBlocks == 1296
           && dynamicMapSurface.Width == 512 && dynamicMapSurface.SampledChunkCount <= 4096,
        " Y map keeps a large logical world range behind a bounded raster");
    var dynamicMapWorldX = 123.5;
    var dynamicMapWorldZ = -210.5;
    Assert(Math.Abs(dynamicMapSurface.WorldXAtPixel(dynamicMapSurface.PixelXForWorld(dynamicMapWorldX)) - dynamicMapWorldX) < 0.0001
           && Math.Abs(dynamicMapSurface.WorldZAtPixel(dynamicMapSurface.PixelZForWorld(dynamicMapWorldZ)) - dynamicMapWorldZ) < 0.0001,
        " Y map logical-world/raster coordinate conversion round-trips exact click coordinates");

    var dynamicMapCross = new BedrockCrossSectionRenderer(dynamicMapDb).Render(
        BedrockMapAxis.X, fixedX: 0, fixedZ: 0, centerY: 64, sideBlocks: 1024,
        dimension: 0, mode: BedrockMapRenderMode.Slime, drawSubChunkGrid: false,
        drawBuildHeightLimits: false, maximumRasterSide: 256);
    Assert(dynamicMapCross.IsDownsampled && dynamicMapCross.SampleStride == 4
           && dynamicMapCross.LogicalHorizontalBlocks == 1024 && dynamicMapCross.Width == 256,
        " X/Z cross section uses a power-of-two stride for huge logical ranges");
    var dynamicMapHorizontal = dynamicMapCross.OriginHorizontal + 333.25;
    var dynamicMapY = dynamicMapCross.MinimumY + 444.75;
    Assert(Math.Abs(dynamicMapCross.WorldHorizontalAtPixel(dynamicMapCross.PixelXForWorld(dynamicMapHorizontal)) - dynamicMapHorizontal) < 0.0001
           && Math.Abs(dynamicMapCross.WorldYAtPixel(dynamicMapCross.PixelYForWorld(dynamicMapY)) - dynamicMapY) < 0.0001,
        " X/Z logical-world/raster coordinate conversion round-trips exact click coordinates");

    var dynamicMapResidentRoot = new NbtCompoundValue([
        new NbtNamedTag("Home", new NbtCompoundValue([
            new NbtNamedTag("x", new NbtIntValue(12)),
            new NbtNamedTag("y", new NbtIntValue(70)),
            new NbtNamedTag("z", new NbtIntValue(-8))
        ])),
        new NbtNamedTag("WorkStation", new NbtIntArrayValue([30, 71, 40]))
    ]);
    var dynamicMapReferences = VillageMapFeatureStore.ReferencePositionKeys(dynamicMapResidentRoot);
    Assert(dynamicMapReferences.Contains("12:70:-8") && dynamicMapReferences.Contains("30:71:40"),
        " village relationship parser resolves resident home/work POI coordinates");

    Console.WriteLine("MCBEEditor.Core self-test passed; dynamic-map sampling, exact coordinate mapping and village POI relationship references matched current iOS semantics.");
}

static void RunChunkConvenienceSelfTest()
{
    using var db = new SelfTestWorldDatabase();
    var position = new ChunkPosition(3, -2, 0);
    var biomeKey = new BedrockDbKey(position, ChunkRecordType.Data2D, null).Encode();
    var heights = new short[256];
    var biomeDoc = new BedrockBiomeDocument(BedrockBiomeFormat.Data2D, heights,
        [new BedrockBiomeLayer(null, Enumerable.Repeat<uint>(1, 256).ToArray(), false)]);
    db.Put(biomeKey, biomeDoc.Encode());
    var chunkQueryWorldRoot = Path.Combine(Path.GetTempPath(), "MCBEEditor-ChunkQuery-" + Guid.NewGuid().ToString("N"));
    Directory.CreateDirectory(chunkQueryWorldRoot);
    try
    {
        var chunkQueryWorld = new WorldDocument(chunkQueryWorldRoot);
        _ = new EnvironmentCommandStore(chunkQueryWorld, db).SaveTickingArea(new EnvironmentTickingAreaSpec(
            position.Dimension, false, position.X, position.Z, position.X, position.Z, "SelfTest", false));
    }
    finally
    {
        try { Directory.Delete(chunkQueryWorldRoot, recursive: true); } catch { }
    }
    var chunkStore = new BedrockChunkStore(db);
    var chunkSummary = chunkStore.SummaryAt(position);
    var chunkQueryText = chunkStore.QueryText(chunkSummary);
    var expectedSlimeText = BedrockSlimeChunk.IsSlimeChunk(position.X, position.Z) ? "True" : "False";
    Assert(chunkQueryText.Contains($"IsSlimeChunk={expectedSlimeText}", StringComparison.Ordinal)
           && chunkQueryText.EndsWith("Ticking=True", StringComparison.Ordinal),
        " chunk query summaries include the Bedrock slime-chunk and ticking-area flags");

    var biomeStore = new BedrockChunkBiomeStore(db);
    var biomeRecord = biomeStore.Read(position);
    Assert(biomeRecord is not null && biomeRecord.Document.BiomeId(0, 64, 0) == 1,
        " per-chunk biome store reads Data2D");
    biomeRecord!.Document.FillLayer(0, 2);
    biomeStore.Save(biomeRecord);
    var biomeReloaded = biomeStore.Read(position)!;
    Assert(biomeReloaded.Document.BiomeId(15, 0, 15) == 2,
        " per-chunk biome editor writes a whole Data2D layer");

    var data3d = new BedrockBiomeDocument(BedrockBiomeFormat.Data3D, heights,
        [new BedrockBiomeLayer(-64, new uint[4096], true), new BedrockBiomeLayer(-48, Enumerable.Repeat<uint>(4, 4096).ToArray(), false)]);
    data3d.FillAllData3DLayers(192);
    Assert(data3d.Layers.All(layer => !layer.IsAbsent && layer.BiomeIds.All(id => id == 192)),
        " Data3D whole-chunk biome fill materializes inherited layers");

    var tempWorldRoot = Path.Combine(Path.GetTempPath(), "MCBEEditor--" + Guid.NewGuid().ToString("N"));
    Directory.CreateDirectory(tempWorldRoot);
    try
    {
        using var tickingDb = new SelfTestWorldDatabase();
        var world = new WorldDocument(tempWorldRoot);
        var ticking = new EnvironmentCommandStore(world, tickingDb);
        ticking.SaveTickingArea(new EnvironmentTickingAreaSpec(0, false, 3, -2, 4, -1, "base", false));
        ticking.SaveTickingArea(new EnvironmentTickingAreaSpec(0, true, 16, 16, 48, 48, "circle", true));
        var areas = ticking.TickingAreas();
        Assert(areas.Count == 2 && areas.Any(area => area.Name == "base") && areas.Any(area => area.Name == "circle" && area.Preload),
            " structured ticking-area manager lists saved areas");
        ticking.SaveTickingArea(new EnvironmentTickingAreaSpec(1, false, 8, 9, 8, 9, "renamed", false), "base");
        areas = ticking.TickingAreas();
        Assert(areas.Count == 2 && areas.All(area => area.Name != "base") && areas.Any(area => area.Name == "renamed" && area.Dimension == 1),
            " ticking-area editor renames/replaces one area without duplicating it");
        ticking.SetTickingAreaPreload(["renamed", "circle"], true);
        areas = ticking.TickingAreas();
        Assert(areas.Where(area => area.Name is "renamed" or "circle").All(area => area.Preload),
            " ticking-area manager batch-enables preload in one persisted record set");
        ticking.SetTickingAreaPreload(["renamed", "circle"], false);
        areas = ticking.TickingAreas();
        Assert(areas.Where(area => area.Name is "renamed" or "circle").All(area => !area.Preload),
            " ticking-area manager batch-disables preload");
        ticking.DeleteTickingAreas(["renamed", "circle"]);
        Assert(ticking.TickingAreas().Count == 0, " ticking-area manager batch-deletes selected areas");
    }
    finally
    {
        try { Directory.Delete(tempWorldRoot, recursive: true); } catch { }
    }

    var dwellers = new NbtDocument("", new NbtCompoundValue([
        new NbtNamedTag("Dwellers", new NbtListValue(NbtTagType.Compound, [
            new NbtCompoundValue([new NbtNamedTag("ID", new NbtLongValue(100))]),
            new NbtCompoundValue([new NbtNamedTag("UniqueID", new NbtLongValue(200))])
        ]))
    ]));
    db.Put(Encoding.UTF8.GetBytes("VILLAGE_test_DWELLERS"), BedrockNbtCodec.Encode(dwellers, NbtEncoding.LittleEndian));
    var villager = new NbtDocument("", new NbtCompoundValue([
        new NbtNamedTag("identifier", new NbtStringValue("minecraft:villager_v2")),
        new NbtNamedTag("UniqueID", new NbtLongValue(100)),
        new NbtNamedTag("Pos", new NbtListValue(NbtTagType.Float, [new NbtFloatValue(1), new NbtFloatValue(64), new NbtFloatValue(1)]))
    ]));
    var entityKey = new BedrockDbKey(new ChunkPosition(0, 0, 0), ChunkRecordType.Entity, null).Encode();
    db.Put(entityKey, BedrockNbtCodec.Encode(villager, NbtEncoding.LittleEndian));
    var residents = new VillageNbtStore(db).ResidentResolution("test");
    Assert(residents.RequestedUniqueIds.SequenceEqual(new long[] { 100, 200 })
           && residents.Entities.Count == 1 && residents.UnresolvedUniqueIds.SequenceEqual(new long[] { 200 })
           && residents.EntitiesOf(VillageResidentEntityKind.Villager).Count == 1,
        " village resident shortcuts resolve Dwellers UniqueID values to world entities and classify villagers");

    Console.WriteLine("MCBEEditor.Core self-test passed; per-chunk biome editing, contextual ticking-area management and village resident shortcuts matched current iOS semantics.");
}

static void RunStandaloneNbtConversionSelfTest()
{
    var fileConversionJavaStructure = new NbtDocument("", new NbtCompoundValue([
        new NbtNamedTag("size", new NbtListValue(NbtTagType.Int, [new NbtIntValue(2), new NbtIntValue(1), new NbtIntValue(1)])),
        new NbtNamedTag("palette", new NbtListValue(NbtTagType.Compound, [
            new NbtCompoundValue([new NbtNamedTag("Name", new NbtStringValue("minecraft:stone"))]),
            new NbtCompoundValue([
                new NbtNamedTag("Name", new NbtStringValue("minecraft:oak_log")),
                new NbtNamedTag("Properties", new NbtCompoundValue([new NbtNamedTag("axis", new NbtStringValue("x"))]))
            ])
        ])),
        new NbtNamedTag("blocks", new NbtListValue(NbtTagType.Compound, [
            new NbtCompoundValue([
                new NbtNamedTag("pos", new NbtListValue(NbtTagType.Int, [new NbtIntValue(0), new NbtIntValue(0), new NbtIntValue(0)])),
                new NbtNamedTag("state", new NbtIntValue(0))
            ]),
            new NbtCompoundValue([
                new NbtNamedTag("pos", new NbtListValue(NbtTagType.Int, [new NbtIntValue(1), new NbtIntValue(0), new NbtIntValue(0)])),
                new NbtNamedTag("state", new NbtIntValue(1))
            ])
        ]))
    ]));
    var fileConversionConversion = JavaStructureConverter.ConvertIfNeeded(fileConversionJavaStructure);
    Assert(fileConversionConversion.Result.ConvertedFromJava && fileConversionConversion.Result.PaletteEntryCount == 2 && fileConversionConversion.Result.PlacedBlockCount == 2,
        "Java structure conversion produces a Bedrock palette and placed-block count");
    Assert(fileConversionConversion.Document.Root.IntValue("format_version") == 1
           && fileConversionConversion.Document.Root.CompoundValue("structure") is NbtCompoundValue,
        "Java structure conversion emits Bedrock mcstructure root schema");

    var fileConversionBigEndian = BedrockNbtCodec.Encode(fileConversionJavaStructure, NbtEncoding.BigEndian);
    byte[] fileConversionGzip;
    using (var fileConversionCompressed = new MemoryStream())
    {
        using (var fileConversionGzipWriter = new GZipStream(fileConversionCompressed, CompressionLevel.Optimal, leaveOpen: true))
            fileConversionGzipWriter.Write(fileConversionBigEndian);
        fileConversionGzip = fileConversionCompressed.ToArray();
    }
    var fileConversionStandalone = StandaloneNbtFileCodec.Decode(fileConversionGzip, "java_structure.nbt");
    Assert(fileConversionStandalone.WasCompressed && fileConversionStandalone.OriginalEncoding == NbtEncoding.BigEndian && fileConversionStandalone.Documents.Count == 1,
        "Standalone codec auto-detects GZip-wrapped Big Endian NBT");
    byte[] fileConversionZlib;
    using (var fileConversionZlibStream = new MemoryStream())
    {
        using (var fileConversionZlibWriter = new ZLibStream(fileConversionZlibStream, CompressionLevel.Optimal, leaveOpen: true))
            fileConversionZlibWriter.Write(fileConversionBigEndian);
        fileConversionZlib = fileConversionZlibStream.ToArray();
    }
    var fileConversionZlibDecoded = StandaloneNbtFileCodec.Decode(fileConversionZlib, "java_structure.nbt");
    Assert(fileConversionZlibDecoded.WasCompressed && fileConversionZlibDecoded.OriginalEncoding == NbtEncoding.BigEndian,
        "Standalone codec auto-detects Zlib-wrapped Big Endian NBT");
    var fileConversionMcstructure = StandaloneNbtFileCodec.EncodeAsMcStructure(fileConversionStandalone.Documents);
    Assert(fileConversionMcstructure.Result.ConvertedFromJava && BedrockNbtCodec.Decode(fileConversionMcstructure.Data, NbtEncoding.LittleEndian).Root.IntValue("format_version") == 1,
        "Standalone codec exports Java structure as Little Endian Bedrock mcstructure");

    var fileConversionRoots = new[]
    {
        new NbtDocument("a", new NbtCompoundValue([new NbtNamedTag("value", new NbtIntValue(1))])),
        new NbtDocument("b", new NbtCompoundValue([new NbtNamedTag("value", new NbtIntValue(2))]))
    };
    var fileConversionConsecutiveBytes = StandaloneNbtFileCodec.Encode(fileConversionRoots, NbtEncoding.LittleEndian);
    var fileConversionConsecutive = StandaloneNbtFileCodec.Decode(fileConversionConsecutiveBytes, "roots.nbt");
    Assert(fileConversionConsecutive.Documents.Count == 2 && fileConversionConsecutive.StorageKind == StandaloneNbtStorageKind.Consecutive,
        "Standalone codec reads consecutive NBT roots");
    var fileConversionJsonBytes = StandaloneNbtFileCodec.EncodeJson(fileConversionRoots);
    Assert(NbtJsonCodec.Decode(fileConversionJsonBytes).Count == 2, "Standalone JSON export round-trips multiple NBT roots");

    using var fileConversionDatabase = new SelfTestWorldDatabase();
    var fileConversionImport = new StructureNbtStore(fileConversionDatabase).Import(fileConversionGzip, "java_structure.nbt", "test:java", overwrite: false);
    Assert(fileConversionImport.ConvertedFromJava && fileConversionDatabase.Get(StructureNbtStore.KeyForName("test:java")) is { Length: > 0 },
        "Structure workspace imports compressed Java NBT and stores converted mcstructure");

    Console.WriteLine("MCBEEditor.Core self-test passed; standalone/compressed NBT and Java-to-Bedrock mcstructure conversion matched current iOS semantics.");
}

static void RunPortableWorkspaceLegacyTerrainSelfTest()
{
    var legacyGrass = new BedrockBlockState(null, 2, 0);
    Assert(legacyGrass.Name == "minecraft:grass", "LegacyTerrain numeric ID maps to the catalog identifier");
    Assert(BedrockBlockMapColorCatalog.ColorFor(legacyGrass) == 0x5E9B3Bu,
        "LegacyTerrain map colour uses numeric-ID mapping instead of hashed legacy:* fallback colour");

    var tempRoot = Path.Combine(Path.GetTempPath(), "MCBEEditor--" + Guid.NewGuid().ToString("N"));
    var cacheRoot = Path.Combine(tempRoot, "Cache", "Worlds");
    var sourceRoot = Path.Combine(tempRoot, "SourceWorld");
    var archivePath = Path.Combine(tempRoot, "Portable.mcworld");
    Directory.CreateDirectory(Path.Combine(sourceRoot, "db"));
    File.WriteAllBytes(Path.Combine(sourceRoot, "db", "000001.ldb"), [1, 2, 3]);
    try
    {
        var sourceWorld = new WorldDocument(sourceRoot);
        sourceWorld.WriteLevelDat(new LevelDatFile(10, new NbtDocument("", new NbtCompoundValue([
            new NbtNamedTag("LevelName", new NbtStringValue("Original"))
        ]))));
        File.WriteAllText(Path.Combine(sourceRoot, "levelname.txt"), "Original");
        var originalLevelBytes = File.ReadAllBytes(sourceWorld.LevelDatPath);
        var originalDbBytes = File.ReadAllBytes(Path.Combine(sourceRoot, "db", "000001.ldb"));

        using (var workspace = PortableWorldWorkspace.Create(cacheRoot, sourceRoot))
        {
            Assert(!string.Equals(workspace.WorkingRootPath, sourceRoot, StringComparison.OrdinalIgnoreCase)
                   && workspace.SourcePath == Path.GetFullPath(sourceRoot),
                "Folder opening creates a distinct Cache working copy and retains the source path");
            var working = new WorldDocument(workspace.WorkingRootPath);
            var level = working.ReadLevelDat();
            working.WriteLevelDat(level with { Document = new NbtDocument("", new NbtCompoundValue([
                new NbtNamedTag("LevelName", new NbtStringValue("EditedCopy"))
            ])) });
            Assert(File.ReadAllBytes(sourceWorld.LevelDatPath).SequenceEqual(originalLevelBytes)
                   && File.ReadAllBytes(Path.Combine(sourceRoot, "db", "000001.ldb")).SequenceEqual(originalDbBytes),
                "Editing the Cache copy never mutates the original source world");

            File.WriteAllText(Path.Combine(working.DatabasePath, "LOCK"), "ephemeral lock");
            Directory.CreateDirectory(Path.Combine(working.RootPath, ".mcbeeditor"));
            File.WriteAllText(Path.Combine(working.RootPath, ".mcbeeditor", "settings.json"), "{}");
            WorldArchiveService.ExportMcworld(working, archivePath);
            Assert(File.Exists(archivePath), "working-copy export creates .mcworld");
            using (var archive = ZipFile.OpenRead(archivePath))
            {
                var names = archive.Entries.Select(entry => entry.FullName.Replace('\\', '/')).ToArray();
                Assert(!names.Any(name => name.Equals("db/LOCK", StringComparison.OrdinalIgnoreCase))
                       && !names.Any(name => name.StartsWith(".mcbeeditor/", StringComparison.OrdinalIgnoreCase)),
                    "portable export excludes LevelDB LOCK and MCBEEditor-private files");
            }
        }

        using (var imported = PortableWorldWorkspace.Create(cacheRoot, archivePath))
        {
            Assert(imported.SourceIsArchive && File.Exists(Path.Combine(imported.WorkingRootPath, "level.dat"))
                   && Directory.Exists(Path.Combine(imported.WorkingRootPath, "db")),
                ".mcworld opening extracts a disposable writable Cache copy");
            var importedLevel = new WorldDocument(imported.WorkingRootPath).ReadLevelDat();
            Assert(importedLevel.Document.Root.CompoundValue("LevelName") is NbtStringValue importedName && importedName.Value == "EditedCopy",
                ".mcworld workspace contains the exported edited snapshot");
        }
    }
    finally
    {
        try { Directory.Delete(tempRoot, recursive: true); } catch { }
    }

    Console.WriteLine("MCBEEditor.Core self-test passed; LegacyTerrain mapping and source-isolated portable working copies matched expectations.");
}

static PlayerNbtRecord PlayerNbtStoreForWorldTools(IWorldDatabase database)
    => new PlayerNbtStore(database).Records().Single();

Console.WriteLine("MCBEEditor.Core self-test passed; data-value catalogs, weather/time/experience tools and .mcworld export matched current iOS semantics.");

Console.WriteLine("MCBEEditor.Core self-test passed; map overlay stores and selected-region search/replace matched the Windows parity layer.");

Console.WriteLine("MCBEEditor.Core self-test passed; storage array mutation, biome codecs/fill and command parsing matched the iOS semantics.");
Console.WriteLine("MCBEEditor.Core self-test passed; typed state parsing, bulk fill, legacy promotion, overlap-safe clone, BlockEntity snapshot replacement and missing-source generation matched expectations.");

Console.WriteLine("MCBEEditor.Core self-test passed; X/Y/Z modes, 129-block mineral projection, missing-section air fallback, projected selection coordinates and height limits matched expectations.");
Console.WriteLine("MCBEEditor.Core self-test passed; external colour override routing and bidirectional x/y/z projection matched expectations.");

EndMissingSubChunkTests.Run();
PersistenceCompatibilityTests.Run();

sealed class SelfTestWorldDatabase : MCBEEditor.Core.World.IWorldDatabase
{
    private readonly Dictionary<string, (byte[] Key, byte[] Value)> _values = new(StringComparer.Ordinal);
    public int ApplyBatchCount { get; private set; }

    public byte[]? Get(ReadOnlySpan<byte> key)
        => _values.TryGetValue(Convert.ToHexString(key), out var item) ? item.Value.ToArray() : null;

    public void Put(ReadOnlySpan<byte> key, ReadOnlySpan<byte> value, bool sync = true)
    {
        var rawKey = key.ToArray();
        _values[Convert.ToHexString(rawKey)] = (rawKey, value.ToArray());
    }

    public void Delete(ReadOnlySpan<byte> key, bool sync = true) => _values.Remove(Convert.ToHexString(key));

    public void ApplyBatch(IEnumerable<MCBEEditor.Core.World.WorldDatabasePut> puts, IEnumerable<byte[]> deletes, bool sync = true)
    {
        ApplyBatchCount++;
        foreach (var key in deletes) Delete(key, false);
        foreach (var put in puts) Put(put.Key, put.Value, false);
    }

    public IEnumerable<MCBEEditor.Core.World.WorldDatabaseEntry> Entries(ReadOnlyMemory<byte>? prefix = null, bool includeValues = false, int limit = 0)
    {
        var rawPrefix = prefix?.ToArray();
        var query = _values.Values
            .Where(item => rawPrefix is null || item.Key.AsSpan().StartsWith(rawPrefix))
            .OrderBy(item => Convert.ToHexString(item.Key), StringComparer.Ordinal);
        if (limit > 0) query = query.Take(limit).OrderBy(item => Convert.ToHexString(item.Key), StringComparer.Ordinal);
        return query.Select(item => new MCBEEditor.Core.World.WorldDatabaseEntry(item.Key.ToArray(), includeValues ? item.Value.ToArray() : null)).ToArray();
    }

    public void Dispose() { }
}
