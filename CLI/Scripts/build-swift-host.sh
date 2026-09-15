#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
[[ $# -le 1 ]] || { echo 'Usage: build-swift-host.sh [output-directory]' >&2; exit 2; }
exec bash "$ROOT/CLI/Scripts/build-apple.sh" host "${1:-$ROOT/CLI/build/swift-host}"
