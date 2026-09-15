#!/usr/bin/env bash
# Compatibility entry retained from stage 01; now builds the complete world CLI.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
[[ $# -le 1 ]] || { echo 'Usage: build-ios-parser.sh [output-directory]' >&2; exit 2; }
exec bash "$ROOT/CLI/Scripts/build-apple.sh" ios "${1:-$ROOT/CLI/build/ios-parser}"
