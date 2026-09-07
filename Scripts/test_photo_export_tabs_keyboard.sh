#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MAP="$ROOT/Sources/UI/WorldMapViewController.swift"
INFO="$ROOT/Resources/Info.plist"
TABS="$ROOT/Sources/UI/WorldDetailTabBarController.swift"
ENTITY="$ROOT/Sources/UI/EntityBrowserViewController.swift"
CHUNK="$ROOT/Sources/UI/ChunkListViewController.swift"
COMMAND="$ROOT/Sources/UI/WorldCommandViewController.swift"

grep -q '^import Photos$' "$MAP"
grep -q 'presentMapImageDestination(image: image, url: url)' "$MAP"
grep -q 'title: "保存到相册"' "$MAP"
grep -q 'PHPhotoLibrary.requestAuthorization(for: .addOnly)' "$MAP"
grep -q 'PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: fileURL)' "$MAP"
grep -q 'UIActivityViewController(activityItems: \[image, url\]' "$MAP"
grep -q '<key>NSPhotoLibraryAddUsageDescription</key>' "$INFO"
grep -q '<key>NSPhotoLibraryUsageDescription</key>' "$INFO"

grep -q 'entities.tabBarItem = UITabBarItem(title: "实体"' "$TABS"
grep -q 'chunks.tabBarItem = UITabBarItem(title: "区块"' "$TABS"
grep -q 'title = "\\(kind.displayName)（\\(shownObjects.count)）"' "$ENTITY"
grep -q 'self.title = "区块（\\(values.count)）"' "$CHUNK"
! grep -q 'self.title = "区块列表（' "$CHUNK"

grep -q 'image: UIImage(systemName: "keyboard")' "$COMMAND"
grep -q 'navigationItem.rightBarButtonItems = \[clearButton, keyboardButton\]' "$COMMAND"
grep -q '@objc private func toggleKeyboard()' "$COMMAND"
grep -q 'inputField.resignFirstResponder()' "$COMMAND"
grep -q 'inputField.becomeFirstResponder()' "$COMMAND"

echo 'Photo export, static bottom tab titles and keyboard toggle regression checks passed'
