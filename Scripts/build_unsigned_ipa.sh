#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED="$ROOT/build/DerivedData"
OUTPUT="$ROOT/build/output"
APP="$DERIVED/Build/Products/Release-iphoneos/MCBEEditor.app"
IPA="$OUTPUT/MCBEEditor-iOS13-unsigned.ipa"

[[ -d "$ROOT/MCBEEditor.xcodeproj" ]] || bash "$ROOT/Scripts/bootstrap.sh"
rm -rf "$DERIVED" "$OUTPUT"
mkdir -p "$OUTPUT/Payload"

xcodebuild \
  -project "$ROOT/MCBEEditor.xcodeproj" \
  -scheme MCBEEditor \
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

# Check the deployment target recorded by the linker before packaging.
BUILD_VERSION="$(xcrun vtool -show-build "$APP/MCBEEditor")"
printf '%s\n' "$BUILD_VERSION"
if ! awk '
  $1 == "platform" && $2 == "IOS" { ios = 1 }
  $1 == "minos" && $2 == "13.0" { minimum = 1 }
  END { exit !(ios && minimum) }
' <<< "$BUILD_VERSION"; then
  echo '错误：应用主程序的 Mach-O 目标必须为 iOS 13.0。' >&2
  exit 1
fi

cp -R "$APP" "$OUTPUT/Payload/"
(
  cd "$OUTPUT"
  /usr/bin/zip -qry "$(basename "$IPA")" Payload
)
rm -rf "$OUTPUT/Payload"
printf '已生成：%s\n' "${IPA}"
