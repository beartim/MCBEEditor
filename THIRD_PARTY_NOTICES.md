# Third-party notices

## Blocktopograph Android

This iOS rewrite is based on the behavior and data-format work of Blocktopograph.
Original project copyright includes Proto Lambda and later community contributors.
The derivative project is distributed under GNU AGPL-3.0-or-later. See `LICENSE`.

The Bedrock slime-chunk coordinate algorithm in `BedrockSlimeChunk.swift` follows
the original Android `SlimeChunkRenderer.java`. The MCPE algorithm comments credit
the reverse-engineering work of `@protolambda` and `@jocopa3`.

- Source: https://github.com/oO0oO0oO0o0o00/blocktopograph/blob/master/app/src/main/java/com/mithrilmania/blocktopograph/map/renderer/SlimeChunkRenderer.java

## leveldb-mcpe

The bootstrap script retrieves `Amulet-Team/leveldb-mcpe`, a Mojang-compatible
fork of LevelDB with Bedrock zlib compression support. That dependency is
BSD-3-Clause licensed. Preserve its bundled license when distributing binaries
or source archives containing the vendored dependency.

## Apple frameworks and zlib

UIKit, Foundation, MobileCoreServices and the system zlib
library are linked as platform/system components and are not redistributed here.
## MCBE Essentials Structure Editor conversion format

The Java structure to Bedrock mcstructure compatibility conversion is an independent Swift implementation based on the public structure schema and conversion behavior documented by the MCBE Essentials Structure Editor project. MCBE Essentials is licensed under CC BY-SA 4.0.

- Project: https://github.com/MCBE-Essentials/mcbe-essentials.github.io
- Structure Editor: https://mcbe-essentials.github.io/structure-editor/


## Bedrock legacy block ID data

The numeric block ID compatibility table is based on the public Minecraft Wiki
Bedrock data-values table and cross-checked against PMMP's
`BedrockBlockUpgradeSchema/block_legacy_id_map.json`. PMMP publishes the schema
repository under CC0-1.0. The Minecraft Wiki page is provided under its site
license and is used here as a factual compatibility reference.

- Minecraft Wiki: https://minecraft.wiki/w/Bedrock_Edition_data_values#Block_IDs
- PMMP schema: https://github.com/pmmp/BedrockBlockUpgradeSchema/blob/master/block_legacy_id_map.json
