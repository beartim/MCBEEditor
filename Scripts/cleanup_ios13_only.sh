#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

obsolete=(
  project-ios13-legacy.yml
  Scripts/bootstrap_ios13_legacy.sh
  Sources/World/WorldBackupService.swift
)

if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git rm -f --ignore-unmatch -- "${obsolete[@]}"
else
  rm -f -- "${obsolete[@]}"
fi

echo "Removed obsolete build files and the retired world-backup service."
echo "The active project is project.yml with iOS 13.0 deployment target."
