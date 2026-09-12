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
PROJECT="$ROOT/project.yml"

require_contains() {
  local file="$1"
  local needle="$2"
  local label="$3"
  if ! grep -Fq -- "$needle" "$file"; then
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
  if grep -Fq -- "$needle" "$file"; then
    printf 'Photo/tab/keyboard regression failed: %s\n' "$label" >&2
    printf '  file: %s\n' "$file" >&2
    printf '  forbidden literal: %s\n' "$needle" >&2
    exit 1
  fi
}

require_contains "$MAP" 'try data.write(to: url, options: .atomic)' 'map export must write the PNG file before presenting share sheet'
require_contains "$MAP" 'UIActivityViewController(activityItems: [url], applicationActivities: nil)' 'map share sheet must receive exactly one PNG URL'
require_absent "$MAP" 'UIActivityViewController(activityItems: [image, url]' 'map share sheet must not receive duplicate UIImage and URL items'
require_absent "$MAP" 'presentMapImageDestination' 'obsolete map export destination menu must be removed'
require_absent "$MAP" 'title: "保存到相册"' 'obsolete direct Save to Photos menu action must be removed'
require_absent "$MAP" 'title: "分享／存储…"' 'obsolete share/storage menu action must be removed'
require_absent "$MAP" 'import Photos' 'PhotoKit import must be removed when export uses the system share sheet only'
require_absent "$MAP" 'PHPhotoLibrary' 'direct PhotoKit save path must be removed'
require_absent "$PROJECT" '- sdk: Photos.framework' 'unused Photos.framework dependency must be removed'
require_contains "$PROJECT" 'NSPhotoLibraryAddUsageDescription:' 'project.yml must retain add-only usage description for share-sheet Save Image'
require_contains "$PROJECT" 'NSPhotoLibraryUsageDescription:' 'project.yml must retain legacy photo usage description for iOS 13 compatibility'
require_contains "$INFO" '<key>NSPhotoLibraryAddUsageDescription</key>' 'generated Info.plist must retain add-only usage description'
require_contains "$INFO" '<key>NSPhotoLibraryUsageDescription</key>' 'generated Info.plist must retain legacy photo usage description'

require_contains "$TABS" 'entities.tabBarItem = UITabBarItem(title: "实体"' 'entity bottom-tab title must be static'
require_contains "$TABS" 'chunks.tabBarItem = UITabBarItem(title: "区块"' 'chunk bottom-tab title must be static'
require_contains "$ENTITY" 'navigationItem.title = "\(kind.displayName)（\(shownObjects.count)）"' 'entity page navigation title must retain its count without mutating the bottom tab title'
require_contains "$CHUNK" 'self.navigationItem.title = "区块（\(values.count)）"' 'chunk page navigation title must retain its count without mutating the bottom tab title'
require_absent "$CHUNK" 'self.title = "区块列表（' 'obsolete chunk-list title must not return'
require_absent "$ENTITY" '    title = "\(kind.displayName)（\(shownObjects.count)）"' 'entity count must not be written through UIViewController.title'
require_absent "$CHUNK" '                    self.title = "区块（\(values.count)）"' 'chunk count must not be written through UIViewController.title'

require_contains "$COMMAND" 'image: UIImage(systemName: "keyboard")' 'keyboard icon button is missing'
require_contains "$COMMAND" 'clearButton, keyboardButton, caretRightButton, caretLeftButton, historyDownButton, historyUpButton' 'direction buttons must remain to the left of keyboard while keyboard remains left of Clear'
require_contains "$COMMAND" 'image: UIImage(systemName: "arrow.up")' 'history up button is missing'
require_contains "$COMMAND" 'image: UIImage(systemName: "arrow.down")' 'history down button is missing'
require_contains "$COMMAND" 'image: UIImage(systemName: "arrow.left")' 'caret left button is missing'
require_contains "$COMMAND" 'image: UIImage(systemName: "arrow.right")' 'caret right button is missing'
require_contains "$COMMAND" '@objc private func recallPreviousCommand()' 'history up handler is missing'
require_contains "$COMMAND" '@objc private func recallNextCommand()' 'history down handler is missing'
require_contains "$COMMAND" '@objc private func moveCaretLeft()' 'caret-left handler is missing'
require_contains "$COMMAND" '@objc private func moveCaretRight()' 'caret-right handler is missing'
require_contains "$COMMAND" '@objc private func toggleKeyboard()' 'keyboard toggle handler is missing'
require_contains "$COMMAND" 'inputField.resignFirstResponder()' 'keyboard dismiss path is missing'
require_contains "$COMMAND" 'inputField.becomeFirstResponder()' 'keyboard show path is missing'

echo 'Single-PNG direct share, static bottom tab titles and keyboard toggle regression checks passed'
