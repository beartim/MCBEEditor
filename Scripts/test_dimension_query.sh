#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/dimension-query.XXXXXX")"
trap 'rm -rf -- "$TMP"' EXIT
cat > "$TMP/Database.swift" <<'SWIFT'
import Foundation
final class MojangLevelDB {
    var values: [Data: Data] = [:]
    var batchCount = 0
    func applyBatch(puts: [(key: Data, value: Data)], deletes: [Data], sync: Bool = true) throws {
        batchCount += 1
        for key in deletes { values.removeValue(forKey: key) }
        for item in puts { values[item.key] = item.value }
    }
    func get(_ key: Data) throws -> Data? { values[key] }
    func put(_ value: Data, for key: Data, sync: Bool = true) throws { values[key] = value }
    func entries(prefix: Data? = nil, includeValues: Bool = false, limit: Int = 0) throws -> [(key: Data, value: Data?)] {
        values.filter { prefix == nil || $0.key.starts(with: prefix!) }.map { (key: $0.key, value: includeValues ? $0.value : nil) }
    }
}
SWIFT
swiftc -parse-as-library "$ROOT/Sources/Support/Errors.swift" "$ROOT/Sources/Support/Hex.swift" \
  "$ROOT/Sources/NBT/NBTTypes.swift" "$ROOT/Sources/NBT/BinaryCursor.swift" \
  "$ROOT/Sources/NBT/ConsecutiveNBTCodec.swift" "$ROOT/Sources/NBT/BedrockNBTCodec.swift" "$ROOT/Sources/Chunk/BedrockDBKey.swift" \
  "$ROOT/Sources/Command/DimensionNameRules.swift" "$ROOT/Sources/World/DimensionContentPlan.swift" "$ROOT/Sources/World/DimensionStore.swift" "$TMP/Database.swift" \
  "$ROOT/Scripts/Tests/DimensionSafetyRegressionTests.swift" "$ROOT/Scripts/Tests/DimensionPurgeTests.swift" "$ROOT/Scripts/Tests/DimensionEmptyTests.swift" "$ROOT/Scripts/Tests/DimensionAddTests.swift" "$ROOT/Scripts/Tests/DimensionTests.swift" -o "$TMP/tests"
"$TMP/tests"
