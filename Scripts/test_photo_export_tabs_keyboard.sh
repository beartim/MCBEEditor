#!/usr/bin/env bash
set -euo pipefail

# GitHub's macOS runner uses BSD grep, while local development commonly uses
# GNU grep.  These checks are source-string assertions, not regular
# expressions, so force byte-wise fixed-string matching to keep the result
# identical on both platforms and to make failures self-describing.
export LC_ALL=C

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MAP="$ROOT/Sources/UI/WorldMapViewController.swift"
INFO="$ROOT/Resources/Info.plist"
TABS="$ROOT/Sources/UI/WorldDetailTabBarController.swift"
ENTITY="$ROOT/Sources/UI/EntityBrowserViewController.swift"
CHUNK="$ROOT/Sources/UI/ChunkListViewController.swift"
COMMAND="$ROOT/Sources/UI/WorldCommandViewController.swift"

require_contains() {
  local file="$1"
  local needle="$2"
  local label="$3"
  if ! grep -Fq "$needle" "$file"; then
    printf 'Photo/tab/keyboard regression failed: %s\n' "$label" >&2
    printf '  file: %s\n' "$file" >&2
    printf '  missing literal: %s\n' "$needle" >&2
    exit 1
  fi
}

require_absent() {
  local file="$1"
  local needle="$2"
  local label="$3"
  if grep -Fq "$needle" "$file"; then
    printf 'Photo/tab/keyboard regression failed: %s\n' "$label" >&2
    printf '  file: %s\n' "$file" >&2
    printf '  forbidden literal: %s\n' "$needle" >&2
    exit 1
  fi
}

require_contains "$MAP" 'import Photos' 'Photos framework import is missing'
require_contains "$MAP" 'presentMapImageDestination(image: image, url: url)' 'map image destination menu is not used'
require_contains "$MAP" 'title: "保存到相册"' 'Save to Photos action is missing'
require_contains "$MAP" 'PHPhotoLibrary.requestAuthorization(for: .addOnly)' 'iOS 14+ add-only permission request is missing'
require_contains "$MAP" 'PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: fileURL)' 'photo-library asset creation is missing'
require_contains "$MAP" 'UIActivityViewController(activityItems: [image, url]' 'share sheet must receive both UIImage and PNG URL'
require_contains "$INFO" '<key>NSPhotoLibraryAddUsageDescription</key>' 'NSPhotoLibraryAddUsageDescription is missing'
require_contains "$INFO" '<key>NSPhotoLibraryUsageDescription</key>' 'NSPhotoLibraryUsageDescription is missing'

require_contains "$TABS" 'entities.tabBarItem = UITabBarItem(title: "实体"' 'entity bottom-tab title must be static'
require_contains "$TABS" 'chunks.tabBarItem = UITabBarItem(title: "区块"' 'chunk bottom-tab title must be static'
require_contains "$ENTITY" 'title = "\(kind.displayName)（\(shownObjects.count)）"' 'entity page navigation title must retain its count'
require_contains "$CHUNK" 'self.title = "区块（\(values.count)）"' 'chunk page navigation title must retain its count'
require_absent "$CHUNK" 'self.title = "区块列表（' 'obsolete chunk-list title must not return'

require_contains "$COMMAND" 'image: UIImage(systemName: "keyboard")' 'keyboard icon button is missing'
require_contains "$COMMAND" 'navigationItem.rightBarButtonItems = [clearButton, keyboardButton]' 'keyboard button must remain left of Clear'
require_contains "$COMMAND" '@objc private func toggleKeyboard()' 'keyboard toggle handler is missing'
require_contains "$COMMAND" 'inputField.resignFirstResponder()' 'keyboard dismiss path is missing'
require_contains "$COMMAND" 'inputField.becomeFirstResponder()' 'keyboard show path is missing'

echo 'Photo export, static bottom tab titles and keyboard toggle regression checks passed'
