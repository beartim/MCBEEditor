#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

let entityTag: NBTValue = .compound([
  NBTNamedTag(name: "FallingBlock", value: .compound([
    NBTNamedTag(name: "version", value: .int(17_825_808))
  ])),
  NBTNamedTag(name: "Invulnerable", value: .byte(0)),
  NBTNamedTag(name: "LimboVersion", value: .byte(2)),
  NBTNamedTag(name: "MarkVariant", value: .int(0)),
  NBTNamedTag(name: "Variant", value: .int(5118))
])
let root: NBTValue = .compound([
  NBTNamedTag(name: "data", value: .compound([
    NBTNamedTag(name: "DragonFight", value: .compound([
      NBTNamedTag(name: "DragonFightVersion", value: .byte(1)),
      NBTNamedTag(name: "PreviouslyKilled", value: .byte(0))
    ])),
    NBTNamedTag(name: "LimboEntities", value: .list(.compound, [entityTag, entityTag]))
  ]))
])

let rows = NBTTreeRows.search(in: root, query: "variant")
let names = rows.map(\.name)
precondition(names.count == 4, "unexpected result count: \(names)")
precondition(Set(names) == ["MarkVariant", "Variant"], "unrelated tags leaked: \(names)")
precondition(!names.contains("version"))
precondition(!names.contains("DragonFightVersion"))
precondition(!names.contains("Invulnerable"))
precondition(!names.contains("LimboVersion"))
print("strict variant matching passed")
SWIFT

swiftc \
  "$ROOT/Sources/NBT/NBTTypes.swift" \
  "$ROOT/Sources/Support/Errors.swift" \
  "$ROOT/Sources/UI/NBTNode.swift" \
  "$TMP/main.swift" \
  -o "$TMP/variant-test"
"$TMP/variant-test"

python3 - "$ROOT/Sources/UI/StandaloneNBTEditorViewController.swift" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text()
start = source.index("  private func rebuildRows() {")
end = source.index("\n  private var rootNeedsOwnRow", start)
block = source[start:end]
clear = "rows.removeAll(keepingCapacity: true)"
assert clear in block
assert block.index(clear) < block.index("if query.isEmpty")
assert "rows.append(contentsOf: NBTTreeRows.search" not in block
assert "rows = searchRows" in block
print("incremental-query stale-row regression passed")
PY
