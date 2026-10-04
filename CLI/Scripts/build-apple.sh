#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MODE="${1:-host}"
OUT="${2:-$ROOT/CLI/build/apple-$MODE}"
CHECK="${3:-}"
if [[ $# -gt 3 || ( "$MODE" != host && "$MODE" != ios ) || ( -n "$CHECK" && "$CHECK" != --test ) || ( "$MODE" == ios && -n "$CHECK" ) ]]; then
  echo 'Usage: build-apple.sh host|ios [output-directory] [--test (host only)]' >&2
  exit 2
fi
[[ "$(uname -s)" == Darwin ]] || { echo 'macOS with Xcode is required.' >&2; exit 1; }
for tool in xcrun cmake; do
  command -v "$tool" >/dev/null 2>&1 || { echo "$tool is required." >&2; exit 127; }
done
bash "$ROOT/CLI/Scripts/bootstrap-apple-native.sh"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
# Keep the last validated artifact intact until compilation, tests and signing pass.
STAGING="$(mktemp -d "$OUT/.mcbe-build.XXXXXX")"
trap 'rm -rf -- "$STAGING"' EXIT
BINARY="$STAGING/mcbe-cli"
SDK_NAME=macosx
ARCH="$(uname -m)"
MINIMUM=11.0
TARGET="$ARCH-apple-macosx$MINIMUM"
if [[ "$MODE" == ios ]]; then
  SDK_NAME=iphoneos
  ARCH=arm64
  MINIMUM=13.0
  TARGET=arm64-apple-ios13.0
fi
SDK="$(xcrun --sdk "$SDK_NAME" --show-sdk-path)"
NATIVE="$OUT/native"
TEST_TOOLS=OFF
[[ "$CHECK" != --test ]] || TEST_TOOLS=ON
configure_native() {
  cmake -S "$ROOT/CLI/Native/Apple" -B "$NATIVE" \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    "-DLEVELDB_MCPE_ROOT=$ROOT/CLI/build/deps/leveldb-mcpe" \
    "-DZLIB_SOURCE_ROOT=$ROOT/CLI/build/deps/zlib" \
    "-DMCBE_BUILD_CLI_TEST_TOOLS=$TEST_TOOLS" \
    "-DCMAKE_OSX_SYSROOT=$SDK" "-DCMAKE_OSX_ARCHITECTURES=$ARCH" \
    "-DCMAKE_OSX_DEPLOYMENT_TARGET=$MINIMUM" \
    "-DCMAKE_C_COMPILER=$(xcrun --sdk "$SDK_NAME" --find clang)" \
    "-DCMAKE_CXX_COMPILER=$(xcrun --sdk "$SDK_NAME" --find clang++)" \
    "-DCMAKE_OBJCXX_COMPILER=$(xcrun --sdk "$SDK_NAME" --find clang++)" \
    "$@"
}
if [[ "$MODE" == ios ]]; then
  configure_native -DCMAKE_SYSTEM_NAME=iOS
else
  configure_native
fi
cmake --build "$NATIVE" --config Release --target mcbe_cli_apple_bridge --parallel 3
sources=()
test_sources=()
while IFS= read -r relative || [[ -n "$relative" ]]; do
  [[ -z "$relative" ]] && continue
  sources+=("$ROOT/$relative")
  [[ "$relative" == CLI/iOS/CliEntry.swift ]] || test_sources+=("$ROOT/$relative")
done < "$ROOT/CLI/iOS/sources.txt"
swift_options=(-swift-version 5 -D MCBE_CLI -parse-as-library -O -sdk "$SDK" -target "$TARGET"
  -import-objc-header "$ROOT/Sources/MCBEEditor-Bridging-Header.h")
libraries=("$NATIVE/lib/libmcbe_cli_apple_bridge.a" "$NATIVE/lib/libmcbe_leveldb_core.a" "$NATIVE/lib/libmcbe_cli_zlib.a" -lc++ -framework Foundation)
xcrun --sdk "$SDK_NAME" swiftc "${swift_options[@]}" "${sources[@]}" "${libraries[@]}" -o "$BINARY"
if [[ "$CHECK" == --test ]]; then
  bash "$ROOT/Scripts/test_end_missing_subchunks.sh"
  python3 "$ROOT/CLI/Tests/source_audit.py"
  python3 "$ROOT/CLI/Tests/build_audit.py"
  python3 "$ROOT/CLI/Tests/apple_build_lifecycle.py"
  python3 "$ROOT/CLI/Tests/smoke.py" --backend swift -- "$BINARY"
  python3 "$ROOT/CLI/Tests/session_smoke.py" -- "$BINARY"
  python3 "$ROOT/CLI/Tests/environment_smoke.py" -- "$BINARY"
  python3 "$ROOT/CLI/Tests/nbt_conversion_smoke.py" -- "$BINARY"
  python3 "$ROOT/CLI/Tests/mcbe_snbt_smoke.py" --backend cli -- "$BINARY"
  python3 "$ROOT/CLI/Tests/structure_file_smoke.py" -- "$BINARY"
  cmake --build "$NATIVE" --config Release --target mcbe_cli_create_test_db --parallel 3
  xcrun --sdk macosx swiftc "${swift_options[@]}" "${test_sources[@]}" \
    "$ROOT/CLI/iOS.Tests/NativeIntegration.swift" "${libraries[@]}" -o "$OUT/cli-native-tests"
  "$OUT/cli-native-tests" "$NATIVE/tools/mcbe_cli_create_test_db" "$ROOT/Tests/Fixtures/end_missing_subchunks.json"
fi
if [[ "$MODE" == ios ]]; then
  [[ "$(xcrun lipo -archs "$BINARY")" == arm64 ]] || { echo 'Expected iOS arm64 binary.' >&2; exit 1; }
  xcrun vtool -show-build "$BINARY" > "$STAGING/build-platform.txt"
  awk '/platform/ && $2 == "IOS" { platform=1 } /minos/ && $2 == "13.0" { minimum=1 } END { exit !(platform && minimum) }' "$STAGING/build-platform.txt"

  # Ship the executable itself rather than a deb. Give the bare Mach-O an
  # ad-hoc code signature so it is structurally signed before users copy it to a device.
  command -v codesign >/dev/null 2>&1 || { echo 'codesign is required for the iOS bare binary.' >&2; exit 127; }
  codesign --force --sign - --timestamp=none "$BINARY"
  codesign --verify --strict --verbose=2 "$BINARY"
  codesign --display --verbose=2 "$BINARY" > "$STAGING/codesign.txt" 2>&1
  (cd "$STAGING" && shasum -a 256 mcbe-cli > mcbe-cli.sha256)
  for report in build-platform.txt codesign.txt mcbe-cli.sha256; do
    mv -f "$STAGING/$report" "$OUT/$report"
  done
fi
mv -f "$BINARY" "$OUT/mcbe-cli"
printf 'Built CLI: %s\n' "$OUT/mcbe-cli"
