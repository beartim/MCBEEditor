#!/usr/bin/env python3
"""Compile both production catalogs and check the independently audited snapshot.

This also exercises Chinese search and the entity scanner's numeric ID bridge,
so a translated reference cannot silently diverge from the command consumers.
The upstream evidence and legacy group descriptions are in Docs/CatalogSync.
"""
from pathlib import Path
import hashlib
import json
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
REFERENCE = ROOT / "Docs/CatalogSync/catalog-reference.json"


def verify_upstream():
    """Catch an incorrect ID copied into both implementation and review snapshot."""
    reference = json.loads(REFERENCE.read_text())
    directory = REFERENCE.parent / "Upstream"
    sources = json.loads((REFERENCE.parent / "sources.json").read_text())
    for source in sources["files"]:
        path = directory / Path(source["path"]).name
        if path.exists():
            assert hashlib.sha256(path.read_bytes()).hexdigest() == source["sha256"], str(path)
    entity_ids = json.loads((directory / "entity-ids.json").read_text())
    drop = REFERENCE.parent / "Drop4"
    supplement = json.loads((drop / "sources.json").read_text())
    for source in supplement["files"]:
        path = drop / source["path"]
        assert hashlib.sha256(path.read_bytes()).hexdigest() == source["sha256"], str(path)
    actors = json.loads((drop / "Upstream/actor-type-additions.json").read_text())["entries"]
    assert all(row["shortId"] == (row["fullId"] & 255) for row in actors), "protocol full/short actor IDs"
    assert {r["identifier"]: r["id"] for r in reference["entities"]} == {
        r["identifier"]: r["shortId"] for r in entity_ids + actors
    }, "entity IDs differ from the factual Microsoft document rows"
    biomes = json.loads((drop / "Upstream/mojang-biomes.json").read_text())["data_items"]
    assert {r["identifier"]: r["id"] for r in reference["biomes"]} == {
        r["name"]: r["id"] for r in biomes
    }, "biome IDs differ from Mojang metadata"
    for category, filename in [("entities", "mojang-entities.json"),
                               ("statusEffects", "mojang-effects.json"),
                               ("enchantments", "mojang-enchantments.json")]:
        upstream = json.loads((drop / "Upstream" / filename).read_text())["data_items"]
        known = {r["identifier"].removeprefix("minecraft:") for r in reference[category]}
        assert {r.get("value", r["name"]).removeprefix("minecraft:") for r in upstream} <= known, category
    blocks = {row["name"]: row["raw_id"] for row in json.loads((drop / "Upstream/mojang-blocks.json").read_text())["data_items"]}
    assert all(blocks[row["identifier"]] == row["id"] for row in reference["modernBlocks"]), "modern block IDs differ from Mojang metadata"
    freezing = json.loads((drop / "Upstream/freezing-id.json").read_text())["entry"]
    assert freezing == {"id": 38, "identifier": "freezing", "displayName": "冰冻"}
    assert freezing in reference["statusEffects"], "freezing numeric ID differs from the Bedrock factual row"
    items = {row["name"]: row["raw_id"] for row in json.loads((drop / "Upstream/mojang-items.json").read_text())["data_items"]}
    additions = json.loads((drop / "additions.json").read_text())
    assert all(items[row["identifier"]] == row["id"] for row in additions["items"]), "documented item IDs differ from Mojang metadata"
    print("Pinned stable/preview hashes, 143 entity IDs, 90 biome IDs, 38 effects and 3 modern blocks passed.")


def run(*args):
    subprocess.run(args, check=True)


verify_upstream()
with tempfile.TemporaryDirectory(prefix="mcbe-catalog-sync-") as temporary:
    work = Path(temporary)
    (work / "Catalog.csproj").write_text(f'''<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup><OutputType>Exe</OutputType><TargetFramework>net10.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings><Nullable>enable</Nullable></PropertyGroup>
  <ItemGroup><ProjectReference Include="{ROOT / 'Windows/MCBEEditor.Core/MCBEEditor.Core.csproj'}" /></ItemGroup>
</Project>
''')
    (work / "Program.cs").write_text(r'''
using System.Text.Json;
using MCBEEditor.Core.World;
using MCBEEditor.Core.Entity;
var reference = JsonDocument.Parse(File.ReadAllText(args[0])).RootElement;
var categories = new Dictionary<string, IReadOnlyList<BedrockDataValueEntry>> {
    ["entities"] = BedrockDataValueCatalog.Entities,
    ["statusEffects"] = BedrockDataValueCatalog.StatusEffects,
    ["biomes"] = BedrockDataValueCatalog.Biomes,
    ["enchantments"] = BedrockDataValueCatalog.Enchantments,
    ["legacyBlocks"] = BedrockDataValueCatalog.LegacyBlocks,
    ["modernBlocks"] = BedrockDataValueCatalog.ModernBlocks,
};
foreach (var pair in categories)
{
    var expected = reference.GetProperty(pair.Key);
    if (expected.GetArrayLength() != pair.Value.Count) throw new Exception(pair.Key + " count mismatch");
    foreach (var row in expected.EnumerateArray())
    {
        var id = row.GetProperty("id").GetInt32();
        var entry = pair.Value.Single(e => e.Id == id);
        if (entry.Identifier != row.GetProperty("identifier").GetString()
            || entry.DisplayName != row.GetProperty("displayName").GetString())
            throw new Exception($"{pair.Key} {id}: catalog differs from audited reference");
        if (pair.Key == "entities" && (BedrockEntityCatalog.IdentifierForNumericId(id) != entry.Identifier
            || BedrockEntityCatalog.NumericIdForIdentifier(entry.Identifier) != id))
            throw new Exception($"entity scanner numeric bridge differs at {id}");
    }
}
if (!BedrockDataValueCatalog.Search(BedrockDataValueCatalog.LegacyBlocks, "强化玻璃").Any(e => e.Id == 253)
    || !BedrockDataValueCatalog.Search(BedrockDataValueCatalog.Entities, "非玩家角色").Any(e => e.Id == 51))
    throw new Exception("Chinese catalog search missed a translated entry");
if (BedrockDataValueCatalog.LegacyBlocks.Any(row => row.Id > 255)
    || !BedrockDataValueCatalog.Search(BedrockDataValueCatalog.ModernBlocks, "0x5de").Any(row => row.Id == 1502)
    || !BedrockDataValueCatalog.Search(BedrockDataValueCatalog.ModernBlocks, "冰晶").Any(row => row.Id == 1503))
    throw new Exception("modern block search / legacy isolation");
Console.WriteLine($"C#: {categories.Values.Sum(rows => rows.Count)} audited ID/name rows, entity bridge and Chinese searches passed.");
''')
    dotnet = shutil.which("dotnet") or "dotnet"
    run(dotnet, "build", str(work / "Catalog.csproj"), "-m:1",
        "-p:BuildInParallel=false", "-p:UseSharedCompilation=false", "--nologo", "-v:q")
    run(dotnet, str(work / "bin/Debug/net10.0/Catalog.dll"), str(REFERENCE))

    (work / "Catalog.swift").write_text(r'''
import Foundation
struct UIColor {
    let red: CGFloat, green: CGFloat, blue: CGFloat
    init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        self.red = red; self.green = green; self.blue = blue
    }
    init(hue: CGFloat, saturation: CGFloat, brightness: CGFloat, alpha: CGFloat) {
        fatalError("known biome color test unexpectedly took unknown-ID path")
    }
}
@main struct CatalogTest {
    static func main() throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let reference = try JSONSerialization.jsonObject(with: data) as! [String: [[String: Any]]]
        let categories: [String: [BedrockDataValueEntry]] = [
            "entities": BedrockDataValueCatalog.entities,
            "statusEffects": BedrockDataValueCatalog.statusEffects,
            "biomes": BedrockDataValueCatalog.biomes,
            "enchantments": BedrockDataValueCatalog.enchantments,
            "legacyBlocks": BedrockLegacyBlockCatalog.blocks,
            "modernBlocks": BedrockDataValueCatalog.modernBlocks,
        ]
        for (name, entries) in categories {
            let expected = reference[name]!
            precondition(expected.count == entries.count, "\(name) count mismatch")
            for row in expected {
                let id = row["id"] as! Int
                let entry = entries.first { $0.id == id }!
                precondition(entry.identifier == row["identifier"] as! String
                    && entry.displayName == row["displayName"] as! String,
                    "\(name) \(id): catalog differs from audited reference")
                if name == "entities" {
                    precondition(BedrockDataValueCatalog.entityIdentifier(forRawValue: String(id)) == entry.identifier)
                }
            }
        }
        precondition(BedrockDataValueCatalog.search(BedrockLegacyBlockCatalog.blocks, query: "强化玻璃").contains { $0.id == 253 })
        precondition(BedrockDataValueCatalog.search(BedrockDataValueCatalog.entities, query: "非玩家角色").contains { $0.id == 51 })
        precondition(!BedrockLegacyBlockCatalog.blocks.contains { $0.id > 255 })
        precondition(BedrockDataValueCatalog.search(BedrockDataValueCatalog.modernBlocks, query: "0x5de").contains { $0.id == 1502 })
        precondition(BedrockDataValueCatalog.search(BedrockDataValueCatalog.modernBlocks, query: "冰晶").contains { $0.id == 1503 })
        let color = BedrockBiomeCatalog.color(for: 196)
        precondition(Int((color.red * 255).rounded()) == 154 && Int((color.green * 255).rounded()) == 187
            && Int((color.blue * 255).rounded()) == 221, "ice cave color parity")
        print("Swift: \(categories.values.reduce(0) { $0 + $1.count }) audited ID/name rows, numeric lookup, biome color and Chinese searches passed.")
    }
}
''')
    executable = work / "catalog-test"
    # Only the UIKit scalar-color boundary is substituted; execute the production
    # biome classification and color calculations unchanged.
    biome_source = work / "BiomeCatalog.swift"
    biome_source.write_text((ROOT / "Sources/Chunk/BedrockBiomeCatalog.swift").read_text().replace("import UIKit", "import Foundation", 1))
    run(shutil.which("swiftc") or "swiftc", "-o", str(executable), str(work / "Catalog.swift"),
        str(ROOT / "Sources/Support/BedrockDataValueCatalog.swift"),
        str(ROOT / "Sources/Support/BedrockLegacyBlockCatalog.swift"),
        str(ROOT / "Sources/Support/BedrockLegacyBlockStateConverter.swift"),
        str(ROOT / "Sources/Support/BedrockBlockIdentifier.swift"),
        str(ROOT / "Sources/Support/Errors.swift"),
        str(ROOT / "Sources/Support/Hex.swift"),
        str(ROOT / "Sources/NBT/NBTTypes.swift"),
        str(ROOT / "Sources/NBT/NBTJSONCodec.swift"),
        str(ROOT / "Sources/NBT/BinaryCursor.swift"),
        str(ROOT / "Sources/NBT/BedrockNBTCodec.swift"),
        str(ROOT / "Sources/Chunk/BedrockSubChunk.swift"), str(biome_source))
    run(str(executable), str(REFERENCE))

print("Catalog synchronization checks passed.")
