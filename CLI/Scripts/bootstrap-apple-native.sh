#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEPS="$ROOT/CLI/build/deps"
command -v git >/dev/null 2>&1 || { echo 'git is required to fetch pinned native dependencies.' >&2; exit 127; }
mkdir -p "$DEPS"
fetch_tag() {
  local repository="$1" tag="$2" directory="$3"
  if [[ ! -e "$directory" ]]; then
    git clone --depth 1 --branch "$tag" "$repository" "$directory"
  fi
  [[ -d "$directory/.git" ]] || { echo "Expected a pinned git checkout: $directory" >&2; exit 1; }
  local head_revision tag_revision
  head_revision="$(git -C "$directory" rev-parse HEAD)"
  tag_revision="$(git -C "$directory" rev-parse "refs/tags/$tag^{commit}")"
  [[ "$head_revision" == "$tag_revision" ]] || { echo "Dependency checkout differs from $tag: $directory" >&2; exit 1; }
  printf '%s %s\n' "$tag" "$head_revision"
}
fetch_tag https://github.com/Amulet-Team/leveldb-mcpe.git 0.8.0a8 "$DEPS/leveldb-mcpe"
fetch_tag https://github.com/madler/zlib.git v1.3.1 "$DEPS/zlib"
