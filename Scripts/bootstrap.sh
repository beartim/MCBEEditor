#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR="$ROOT/Vendor/leveldb-mcpe"
LEVELDB_REPOSITORY="${LEVELDB_REPOSITORY:-https://github.com/Amulet-Team/leveldb-mcpe.git}"
LEVELDB_REF="${LEVELDB_REF:-master}"
PROJECT_SPEC="$ROOT/project.yml"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "错误：iOS 工程生成与编译必须在 macOS 上执行。" >&2
  exit 1
fi

command -v xcodebuild >/dev/null || { echo "错误：未安装 Xcode Command Line Tools。" >&2; exit 1; }
command -v git >/dev/null || { echo "错误：未安装 git。" >&2; exit 1; }
command -v xcodegen >/dev/null || {
  echo "错误：未安装 XcodeGen。请先执行：brew install xcodegen" >&2
  exit 1
}
[[ -f "$PROJECT_SPEC" ]] || { echo "错误：工程配置不存在：$PROJECT_SPEC" >&2; exit 1; }

XCODE_VERSION_OUTPUT="$(xcodebuild -version 2>&1)" || {
  echo "错误：无法读取 Xcode 版本。" >&2
  exit 1
}
XCODE_VERSION="$(awk '/^Xcode / { version = $2 } END { print version }' <<< "$XCODE_VERSION_OUTPUT")"
[[ -n "$XCODE_VERSION" ]] || {
  printf '错误：无法从 xcodebuild 输出中解析 Xcode 版本：\n%s\n' "$XCODE_VERSION_OUTPUT" >&2
  exit 1
}
XCODE_MAJOR="${XCODE_VERSION%%.*}"
if [[ "$XCODE_MAJOR" != "15" ]]; then
  printf '错误：此工程只构建 iOS 13，需要 Xcode 15.x（推荐 15.4）。当前为 Xcode %s。\n' \
    "${XCODE_VERSION}" >&2
  exit 1
fi

mkdir -p "$ROOT/Vendor"
if [[ ! -d "$VENDOR/.git" ]]; then
  rm -rf "$VENDOR"
  git clone --filter=blob:none "$LEVELDB_REPOSITORY" "$VENDOR"
fi

git -C "$VENDOR" fetch --depth 1 origin "$LEVELDB_REF"
git -C "$VENDOR" checkout --detach FETCH_HEAD
git -C "$VENDOR" rev-parse HEAD > "$ROOT/Vendor/leveldb-mcpe.lock"

# Remove source files retired by overlay-style upgrades.
rm -f "$ROOT/Sources/World/WorldBackupService.swift"

# XcodeGen --project expects an output directory, not the .xcodeproj path.
# Remove stale/partially generated output left by an interrupted previous run.
rm -rf "$ROOT/Blocktopograph.xcodeproj"
xcodegen generate --spec "$PROJECT_SPEC" --project "$ROOT"

PBXPROJ="$ROOT/Blocktopograph.xcodeproj/project.pbxproj"
[[ -f "$PBXPROJ" ]] || {
  echo "错误：XcodeGen 未生成有效工程：$ROOT/Blocktopograph.xcodeproj" >&2
  exit 1
}

# XcodeGen 2.44+ defaults to the Xcode 16 project format (objectVersion 77).
# This project deliberately builds with Xcode 15.4 so that it can target iOS 13.
# project.yml pins projectFormat=xcode15_3, which XcodeGen emits as objectVersion 63.
# Xcode 15.4 accepts project object versions up to and including 63.
MAX_XCODE15_OBJECT_VERSION=63
OBJECT_VERSION="$(awk '/^[[:space:]]*objectVersion = / { gsub(/;/, "", $3); print $3; exit }' "$PBXPROJ")"
if [[ ! "$OBJECT_VERSION" =~ ^[0-9]+$ ]]; then
  echo "错误：无法读取生成工程的 objectVersion。" >&2
  exit 1
fi
if (( OBJECT_VERSION > MAX_XCODE15_OBJECT_VERSION )); then
  printf '错误：生成工程的 objectVersion=%s，超过 Xcode 15.4 支持上限 %s。\n' \
    "${OBJECT_VERSION}" "${MAX_XCODE15_OBJECT_VERSION}" >&2
  echo "请确认 project.yml 包含 projectFormat: xcode15_3。" >&2
  exit 1
fi

echo "完成：$ROOT/Blocktopograph.xcodeproj"
printf 'Xcode 工程格式：objectVersion=%s（Xcode 15 compatible）\n' \
  "${OBJECT_VERSION}"
echo "工程配置：project.yml（iOS 13.0 only）"
printf 'Xcode：%s\n' "${XCODE_VERSION}"
echo "Mojang LevelDB 兼容分支：$(cat "$ROOT/Vendor/leveldb-mcpe.lock")"
