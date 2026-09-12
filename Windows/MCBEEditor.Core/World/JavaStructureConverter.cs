using MCBEEditor.Core.Nbt;

namespace MCBEEditor.Core.World;

public enum StructureImportSourceKind { Bedrock, Java }

public sealed record StructureImportResult(
    StructureImportSourceKind SourceKind,
    int PaletteEntryCount,
    int PlacedBlockCount,
    int LossyPaletteEntryCount)
{
    public bool ConvertedFromJava => SourceKind == StructureImportSourceKind.Java;
}

public sealed record StructureConversionResult(NbtDocument Document, StructureImportResult Result);

/// <summary>
/// Converts Java Edition structure NBT into the Bedrock mcstructure schema used by structuretemplate_*.
/// Java entities, water layers and advanced block-entity payloads are intentionally not carried over,
/// matching the iOS compatibility converter.
/// </summary>
public static class JavaStructureConverter
{
    private const int BedrockPaletteVersion = 17_959_425;
    private const int MaximumBlockVolume = 16_777_216;

    private sealed record JavaPaletteEntry(string Name, IReadOnlyDictionary<string, string> Properties)
    {
        public string DynamicIdentifier => Name + "[" + string.Join(',', Properties.OrderBy(p => p.Key, StringComparer.Ordinal).Select(p => p.Key + "=" + p.Value)) + "]";
    }

    private sealed record BedrockPaletteEntry(string Name, IReadOnlyDictionary<string, NbtValue> States, bool Lossy);
    private readonly record struct Dimensions(int X, int Y, int Z, int Volume);

    public static StructureConversionResult ConvertIfNeeded(NbtDocument document)
    {
        ArgumentNullException.ThrowIfNull(document);
        if (document.Root is not NbtCompoundValue) throw new InvalidDataException("结构 NBT 的根标签必须是 Compound。");
        if (IsBedrockStructure(document.Root))
        {
            var normalized = NormalizeBedrockStructure(document);
            var size = DimensionsOf(normalized.Root);
            return new StructureConversionResult(normalized,
                new StructureImportResult(StructureImportSourceKind.Bedrock, BedrockPaletteCount(normalized.Root), size.Volume, 0));
        }
        if (!IsJavaStructure(document.Root)) throw new InvalidDataException("该文件既不是 Java 结构 NBT，也不是 Bedrock mcstructure。");
        return ConvertJavaStructure(document);
    }

    private static bool IsBedrockStructure(NbtValue root)
        => root.IntValue("format_version").HasValue
           && root.CompoundValue("structure") is NbtCompoundValue
           && IntegerVector(root.CompoundValue("size")) is { Count: 3 };

    private static bool IsJavaStructure(NbtValue root)
        => IntegerVector(root.CompoundValue("size")) is { Count: 3 }
           && root.CompoundValue("palette") is NbtListValue { ElementType: NbtTagType.Compound }
           && root.CompoundValue("blocks") is NbtListValue { ElementType: NbtTagType.Compound };

    private static StructureConversionResult ConvertJavaStructure(NbtDocument document)
    {
        var size = DimensionsOf(document.Root);
        if (document.Root.CompoundValue("palette") is not NbtListValue { ElementType: NbtTagType.Compound } paletteList || paletteList.Values.Count == 0)
            throw new InvalidDataException("Java 结构缺少非空 palette Compound List。");
        if (document.Root.CompoundValue("blocks") is not NbtListValue { ElementType: NbtTagType.Compound } blocksList)
            throw new InvalidDataException("Java 结构缺少 blocks Compound List。");

        var bedrockPalette = new List<NbtValue>(paletteList.Values.Count);
        var lossyCount = 0;
        foreach (var value in paletteList.Values)
        {
            var mapped = MapPaletteEntry(ParseJavaPaletteEntry(value));
            if (mapped.Lossy) lossyCount++;
            bedrockPalette.Add(MakeBedrockPaletteTag(mapped));
        }

        var primary = Enumerable.Repeat(-1, size.Volume).ToArray();
        var secondary = Enumerable.Repeat(-1, size.Volume).ToArray();
        var placedCount = 0;
        foreach (var blockValue in blocksList.Values)
        {
            if (blockValue is not NbtCompoundValue) continue;
            var position = IntegerVector(blockValue.CompoundValue("pos"));
            if (position is not { Count: 3 }) throw new InvalidDataException("Java 结构 blocks 中存在缺少 pos 的方块。");
            var rawState = blockValue.CompoundValue("state")?.IntegerValue();
            if (!rawState.HasValue || rawState.Value < 0 || rawState.Value >= paletteList.Values.Count)
                throw new InvalidDataException("Java 结构方块引用了无效 palette state。");
            var x = CheckedCoordinate(position[0], size.X, "X");
            var y = CheckedCoordinate(position[1], size.Y, "Y");
            var z = CheckedCoordinate(position[2], size.Z, "Z");
            var index = x * size.Y * size.Z + y * size.Z + z;
            primary[index] = checked((int)rawState.Value);
            placedCount++;
        }

        var root = new NbtCompoundValue(new NbtNamedTag[]
        {
            new("format_version", new NbtIntValue(1)),
            new("size", IntList(size.X, size.Y, size.Z)),
            new("structure_world_origin", IntList(0, 0, 0)),
            new("structure", new NbtCompoundValue(new NbtNamedTag[]
            {
                new("block_indices", new NbtListValue(NbtTagType.List, new NbtValue[]
                {
                    new NbtListValue(NbtTagType.Int, primary.Select(v => (NbtValue)new NbtIntValue(v)).ToArray()),
                    new NbtListValue(NbtTagType.Int, secondary.Select(v => (NbtValue)new NbtIntValue(v)).ToArray())
                })),
                new("entities", new NbtListValue(NbtTagType.End, Array.Empty<NbtValue>())),
                new("palette", new NbtCompoundValue(new NbtNamedTag[]
                {
                    new("default", new NbtCompoundValue(new NbtNamedTag[]
                    {
                        new("block_palette", new NbtListValue(NbtTagType.Compound, bedrockPalette)),
                        new("block_position_data", new NbtCompoundValue(Array.Empty<NbtNamedTag>()))
                    }))
                }))
            }))
        });
        return new StructureConversionResult(new NbtDocument(string.Empty, root),
            new StructureImportResult(StructureImportSourceKind.Java, bedrockPalette.Count, placedCount, lossyCount));
    }

    private static NbtDocument NormalizeBedrockStructure(NbtDocument document)
    {
        var size = DimensionsOf(document.Root);
        if (document.Root is not NbtCompoundValue root) throw new InvalidDataException("Bedrock 结构根不是 Compound。");
        if (root.CompoundValue("structure") is not NbtCompoundValue structure) throw new InvalidDataException("Bedrock 结构缺少 structure。");
        var rawIndices = structure.CompoundValue("block_indices") as NbtListValue;
        var layers = new List<int[]>();
        if (rawIndices is { ElementType: NbtTagType.List })
        {
            foreach (var layerValue in rawIndices.Values.Take(2))
            {
                if (layerValue is NbtListValue { ElementType: NbtTagType.Int } list)
                    layers.Add(list.Values.OfType<NbtIntValue>().Select(v => v.Value).ToArray());
            }
        }
        while (layers.Count < 2) layers.Add(Array.Empty<int>());
        for (var i = 0; i < 2; i++)
        {
            var normalized = Enumerable.Repeat(-1, size.Volume).ToArray();
            Array.Copy(layers[i], normalized, Math.Min(layers[i].Length, normalized.Length));
            layers[i] = normalized;
        }
        var indices = new NbtListValue(NbtTagType.List, layers.Select(layer => (NbtValue)new NbtListValue(NbtTagType.Int,
            layer.Select(v => (NbtValue)new NbtIntValue(v)).ToArray())).ToArray());
        var newStructure = ReplaceTag(structure, "block_indices", indices);
        return new NbtDocument(string.Empty, ReplaceTag(root, "structure", newStructure));
    }

    private static JavaPaletteEntry ParseJavaPaletteEntry(NbtValue value)
    {
        if (value is not NbtCompoundValue compound || compound.StringValue("Name") is not { Length: > 0 } name)
            throw new InvalidDataException("Java 结构 palette 中存在缺少 Name 的条目。");
        var properties = new Dictionary<string, string>(StringComparer.Ordinal);
        if (compound.CompoundValue("Properties") is { } propertyValue)
        {
            if (propertyValue is not NbtCompoundValue propertyCompound) throw new InvalidDataException("Java 结构 palette.Properties 不是 Compound。");
            foreach (var tag in propertyCompound.Tags)
            {
                var text = tag.Value switch
                {
                    NbtStringValue v => v.Value,
                    NbtByteValue v => v.Value.ToString(System.Globalization.CultureInfo.InvariantCulture),
                    NbtShortValue v => v.Value.ToString(System.Globalization.CultureInfo.InvariantCulture),
                    NbtIntValue v => v.Value.ToString(System.Globalization.CultureInfo.InvariantCulture),
                    NbtLongValue v => v.Value.ToString(System.Globalization.CultureInfo.InvariantCulture),
                    _ => null
                };
                if (text is not null) properties[tag.Name] = text;
            }
        }
        return new JavaPaletteEntry(Namespaced(name), properties);
    }

    private static BedrockPaletteEntry MapPaletteEntry(JavaPaletteEntry java)
    {
        if (ExactMappings.TryGetValue(java.DynamicIdentifier, out var exact)) return exact;
        var name = MappedIdentifier(java.Name, java.Properties);
        var states = new Dictionary<string, NbtValue>(StringComparer.Ordinal);
        var consumed = new HashSet<string>(StringComparer.Ordinal);

        if (java.Properties.TryGetValue("axis", out var axis) && axis is "x" or "y" or "z" && IsPillarLike(name))
        { states["pillar_axis"] = new NbtStringValue(axis); consumed.Add("axis"); }
        if (name == "minecraft:structure_block" && java.Properties.TryGetValue("mode", out var mode))
        { states["structure_block_type"] = new NbtStringValue(mode); consumed.Add("mode"); }
        if (name == "minecraft:brewing_stand")
        {
            var targets = new[] { "brewing_stand_slot_a_bit", "brewing_stand_slot_b_bit", "brewing_stand_slot_c_bit" };
            for (var i = 0; i < 3; i++)
            {
                var source = "has_bottle_" + i;
                if (java.Properties.TryGetValue(source, out var value))
                { states[targets[i]] = new NbtByteValue(BooleanByte(value)); consumed.Add(source); }
            }
        }
        if (name == "minecraft:end_rod" && java.Properties.TryGetValue("facing", out var endFacing) && FacingDirection(endFacing) is { } endDir)
        { states["facing_direction"] = new NbtIntValue(endDir); consumed.Add("facing"); }
        else if (IsStair(name) && java.Properties.TryGetValue("facing", out var stairFacing) && StairDirection(stairFacing) is { } stairDir)
        {
            states["weirdo_direction"] = new NbtIntValue(stairDir); consumed.Add("facing");
            if (java.Properties.TryGetValue("half", out var half)) { states["upside_down_bit"] = new NbtByteValue((sbyte)(half == "top" ? 1 : 0)); consumed.Add("half"); }
            consumed.Add("shape");
        }
        else if (IsFacingDirectionBlock(name) && java.Properties.TryGetValue("facing", out var facing) && FacingDirection(facing) is { } direction)
        { states["facing_direction"] = new NbtIntValue(direction); consumed.Add("facing"); }

        if (IsSlab(name) && (java.Properties.TryGetValue("half", out var slabHalf) || java.Properties.TryGetValue("type", out slabHalf)))
        { states["top_slot_bit"] = new NbtByteValue((sbyte)(slabHalf == "top" ? 1 : 0)); consumed.Add("half"); consumed.Add("type"); consumed.Add("variant"); }
        AddBooleanState(java, states, consumed, "powered", "powered_bit");
        AddBooleanState(java, states, consumed, "open", "open_bit");
        AddBooleanState(java, states, consumed, "lit", "lit");
        if (java.Properties.TryGetValue("age", out var age) && int.TryParse(age, out var ageNumber))
        { states["growth"] = new NbtIntValue(ageNumber); consumed.Add("age"); }
        if ((name == "minecraft:water" || name == "minecraft:lava") && java.Properties.TryGetValue("level", out var level) && int.TryParse(level, out var levelNumber))
        { states["liquid_depth"] = new NbtIntValue(levelNumber); consumed.Add("level"); }

        var lossy = java.Properties.Keys.Any(key => !consumed.Contains(key)) || (name == "minecraft:air" && java.Name != "minecraft:air");
        return new BedrockPaletteEntry(name, states, lossy);
    }

    private static void AddBooleanState(JavaPaletteEntry java, IDictionary<string, NbtValue> states, ISet<string> consumed, string source, string target)
    {
        if (!java.Properties.TryGetValue(source, out var value)) return;
        states[target] = new NbtByteValue(BooleanByte(value));
        consumed.Add(source);
    }

    private static NbtValue MakeBedrockPaletteTag(BedrockPaletteEntry entry)
        => new NbtCompoundValue(new NbtNamedTag[]
        {
            new("name", new NbtStringValue(entry.Name)),
            new("states", new NbtCompoundValue(entry.States.OrderBy(pair => pair.Key, StringComparer.Ordinal).Select(pair => new NbtNamedTag(pair.Key, pair.Value)).ToArray())),
            new("version", new NbtIntValue(BedrockPaletteVersion))
        });

    private static string MappedIdentifier(string identifier, IReadOnlyDictionary<string, string> properties)
    {
        var name = Namespaced(identifier);
        if (!name.StartsWith("minecraft:", StringComparison.Ordinal)) return name;
        var path = name["minecraft:".Length..];
        if (properties.TryGetValue("color", out var color))
        {
            var colorFamilies = new HashSet<string>(new[] { "wool", "carpet", "stained_glass", "stained_glass_pane", "terracotta", "concrete", "concrete_powder", "shulker_box", "glazed_terracotta" }, StringComparer.Ordinal);
            if (colorFamilies.Contains(path)) return "minecraft:" + color + "_" + path;
        }
        return Aliases.TryGetValue(name, out var mapped) ? mapped : name;
    }

    private static string Namespaced(string identifier) => identifier.Contains(':') ? identifier : "minecraft:" + identifier;
    private static bool IsPillarLike(string name) => name.EndsWith("_log", StringComparison.Ordinal) || name.EndsWith("_wood", StringComparison.Ordinal) || name.EndsWith("_stem", StringComparison.Ordinal) || name.EndsWith("_hyphae", StringComparison.Ordinal) || name.EndsWith("_pillar", StringComparison.Ordinal) || name is "minecraft:bone_block" or "minecraft:purpur_block";
    private static bool IsStair(string name) => name.EndsWith("_stairs", StringComparison.Ordinal);
    private static bool IsSlab(string name) => name.EndsWith("_slab", StringComparison.Ordinal);
    private static bool IsFacingDirectionBlock(string name) => FacingBlocks.Contains(name);
    private static int? FacingDirection(string value) => value switch { "down" => 0, "up" => 1, "south" => 2, "north" => 3, "east" => 4, "west" => 5, _ => null };
    private static int? StairDirection(string value) => value switch { "east" => 0, "west" => 1, "south" => 2, "north" => 3, _ => null };
    private static sbyte BooleanByte(string text) => text.Equals("true", StringComparison.OrdinalIgnoreCase) || text == "1" ? (sbyte)1 : (sbyte)0;

    private static int CheckedCoordinate(long value, int upperBound, string axis)
    {
        if (value < 0 || value >= upperBound) throw new InvalidDataException($"Java 结构方块 {axis} 坐标越界：{value}");
        return checked((int)value);
    }

    private static Dimensions DimensionsOf(NbtValue root)
    {
        var values = IntegerVector(root.CompoundValue("size"));
        if (values is not { Count: 3 }) throw new InvalidDataException("结构缺少有效的 size[3]。");
        if (values.Any(v => v <= 0 || v > int.MaxValue)) throw new InvalidDataException("结构尺寸必须是正整数。");
        var x = checked((int)values[0]); var y = checked((int)values[1]); var z = checked((int)values[2]);
        long volume = (long)x * y * z;
        if (volume > MaximumBlockVolume) throw new NotSupportedException($"结构体积过大：{x}×{y}×{z}，最多支持 {MaximumBlockVolume} 个方块。");
        return new Dimensions(x, y, z, checked((int)volume));
    }

    private static IReadOnlyList<long>? IntegerVector(NbtValue? value) => value switch
    {
        NbtIntArrayValue ints => ints.Values.Select(v => (long)v).ToArray(),
        NbtLongArrayValue longs => longs.Values.ToArray(),
        NbtListValue list when list.Values.All(v => v.IntegerValue().HasValue) => list.Values.Select(v => v.IntegerValue()!.Value).ToArray(),
        _ => null
    };

    private static int BedrockPaletteCount(NbtValue root)
    {
        var blockPalette = root.CompoundValue("structure")?.CompoundValue("palette")?.CompoundValue("default")?.CompoundValue("block_palette");
        return blockPalette is NbtListValue { ElementType: NbtTagType.Compound } list ? list.Values.Count : 0;
    }

    private static NbtListValue IntList(params int[] values) => new(NbtTagType.Int, values.Select(v => (NbtValue)new NbtIntValue(v)).ToArray());

    private static NbtCompoundValue ReplaceTag(NbtCompoundValue compound, string name, NbtValue value)
    {
        var tags = compound.Tags.ToList();
        var index = tags.FindIndex(tag => tag.Name == name);
        if (index >= 0) tags[index] = new NbtNamedTag(name, value); else tags.Add(new NbtNamedTag(name, value));
        return new NbtCompoundValue(tags);
    }

    private static BedrockPaletteEntry Air(bool lossy) => new("minecraft:air", new Dictionary<string, NbtValue>(), lossy);
    private static BedrockPaletteEntry Entry(string name, bool lossy = false, params (string Name, NbtValue Value)[] states)
        => new(name, states.ToDictionary(item => item.Name, item => item.Value, StringComparer.Ordinal), lossy);

    private static readonly HashSet<string> FacingBlocks = new(new[]
    {
        "minecraft:ladder", "minecraft:chest", "minecraft:trapped_chest", "minecraft:furnace", "minecraft:blast_furnace", "minecraft:smoker",
        "minecraft:dispenser", "minecraft:dropper", "minecraft:observer", "minecraft:hopper", "minecraft:barrel", "minecraft:end_rod"
    }, StringComparer.Ordinal);

    private static readonly Dictionary<string, string> Aliases = new(StringComparer.Ordinal)
    {
        ["minecraft:grass"] = "minecraft:grass_block", ["minecraft:grass_path"] = "minecraft:dirt_path",
        ["minecraft:double_stone_slab"] = "minecraft:double_stone_block_slab", ["minecraft:stone_slab"] = "minecraft:stone_block_slab",
        ["minecraft:lit_furnace"] = "minecraft:furnace", ["minecraft:lit_redstone_lamp"] = "minecraft:redstone_lamp",
        ["minecraft:flowing_water"] = "minecraft:water", ["minecraft:flowing_lava"] = "minecraft:lava", ["minecraft:web"] = "minecraft:web"
    };

    private static readonly Dictionary<string, BedrockPaletteEntry> ExactMappings = new(StringComparer.Ordinal)
    {
        ["minecraft:air[]"] = Entry("minecraft:air"),
        ["minecraft:purpur_pillar[axis=z]"] = Entry("minecraft:purpur_pillar", false, ("pillar_axis", new NbtStringValue("z"))),
        ["minecraft:purpur_block[]"] = Entry("minecraft:purpur_block", false, ("pillar_axis", new NbtStringValue("y"))),
        ["minecraft:obsidian[]"] = Entry("minecraft:obsidian"),
        ["minecraft:purpur_pillar[axis=y]"] = Entry("minecraft:purpur_pillar", false, ("pillar_axis", new NbtStringValue("y"))),
        ["minecraft:end_bricks[]"] = Air(true),
        ["minecraft:skull[facing=north,nodrop=false]"] = Air(true),
        ["minecraft:chest[facing=south]"] = Air(true),
        ["minecraft:structure_block[mode=save]"] = Entry("minecraft:structure_block", false, ("structure_block_type", new NbtStringValue("save"))),
        ["minecraft:structure_block[mode=data]"] = Entry("minecraft:structure_block", false, ("structure_block_type", new NbtStringValue("data"))),
        ["minecraft:brewing_stand[has_bottle_0=true,has_bottle_1=false,has_bottle_2=true]"] = Entry("minecraft:brewing_stand", false,
            ("brewing_stand_slot_a_bit", new NbtByteValue(1)), ("brewing_stand_slot_b_bit", new NbtByteValue(0)), ("brewing_stand_slot_c_bit", new NbtByteValue(1))),
        ["minecraft:purpur_stairs[facing=north,half=bottom,shape=straight]"] = Air(true),
        ["minecraft:purpur_slab[half=top,variant=default]"] = Air(true),
        ["minecraft:end_rod[facing=up]"] = Entry("minecraft:end_rod", false, ("facing_direction", new NbtIntValue(1))),
        ["minecraft:end_rod[facing=south]"] = Entry("minecraft:end_rod", false, ("facing_direction", new NbtIntValue(2))),
        ["minecraft:purpur_stairs[facing=east,half=bottom,shape=straight]"] = Air(true),
        ["minecraft:purpur_stairs[facing=west,half=bottom,shape=straight]"] = Air(true),
        ["minecraft:purpur_stairs[facing=south,half=bottom,shape=straight]"] = Air(true),
        ["minecraft:purpur_stairs[facing=south,half=top,shape=straight]"] = Air(true),
        ["minecraft:purpur_stairs[facing=west,half=top,shape=straight]"] = Air(true),
        ["minecraft:purpur_stairs[facing=east,half=top,shape=straight]"] = Air(true),
        ["minecraft:stained_glass[color=magenta]"] = Air(true),
        ["minecraft:ladder[facing=south]"] = Air(true),
        ["minecraft:purpur_stairs[facing=north,half=top,shape=straight]"] = Air(true)
    };
}
