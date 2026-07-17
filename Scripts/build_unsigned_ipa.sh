#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED="$ROOT/build/DerivedData"
OUTPUT="$ROOT/build/output"
APP="$DERIVED/Build/Products/Release-iphoneos/Blocktopograph.app"
IPA="$OUTPUT/Blocktopograph-iOS13-unsigned.ipa"

[[ -d "$ROOT/Blocktopograph.xcodeproj" ]] || bash "$ROOT/Scripts/bootstrap.sh"
rm -rf "$DERIVED" "$OUTPUT"
mkdir -p "$OUTPUT/Payload"

xcodebuild \
  -project "$ROOT/Blocktopograph.xcodeproj" \
  -scheme Blocktopograph \
  -configuration Release \
  -sdk iphoneos \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build

[[ -d "$APP" ]] || { echo "错误：未找到 $APP" >&2; exit 1; }

MIN_OS="$(/usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' "$APP/Info.plist" 2>/dev/null || true)"
[[ "$MIN_OS" == "13.0" ]] || {
  printf '错误：构建产物 MinimumOSVersion=%s，预期为 13.0。\n' \
    "${MIN_OS}" >&2
  exit 1
}

printf '已验证 MinimumOSVersion：%s\n' "${MIN_OS}"
cp -R "$APP" "$OUTPUT/Payload/"
(
  cd "$OUTPUT"
  /usr/bin/zip -qry "$(basename "$IPA")" Payload
)
rm -rf "$OUTPUT/Payload"
printf '已生成：%s\n' "${IPA}"
