#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NBT="$ROOT/Windows/MCBEEditor.Desktop/NbtEditorWindow.cs"
MAIN="$ROOT/Windows/MCBEEditor.Desktop/MainWindow.xaml.cs"
STORE="$ROOT/Windows/MCBEEditor.Desktop/BlockTextureOverrideStore.cs"
CSPROJ="$ROOT/Windows/MCBEEditor.Desktop/MCBEEditor.Desktop.csproj"
RC="$ROOT/Windows/PortableLauncher/payload.rc.in"
ICON="$ROOT/Windows/Resources/MCBEEditor.ico"

grep -q '"存在同名标签"' "$NBT"
grep -q 'CompoundConflictChoice.Overwrite' "$NBT"
grep -q 'CompoundConflictChoice.Keep' "$NBT"
grep -q 'CompoundConflictChoice.Cancel' "$NBT"
grep -q 'UniqueGeneratedName("导入的标签"' "$NBT"
! grep -q 'foreach (var document in documents) AddImportedChild' "$NBT"

grep -Fq '..\Resources\MCBEEditor.ico' "$CSPROJ"
grep -q '^1 ICON "@MCBE_ICON_PATH_RC@"' "$RC"
test -s "$ICON"

# Reload failure handling belongs to the store, not duplicated at map render/export call sites.
! grep -Fq 'try { BlockTextureOverrideStore.Reload(); } catch { }' "$MAIN"
grep -q 'catch (IOException)' "$STORE"
grep -q 'catch (UnauthorizedAccessException)' "$STORE"
grep -q 'lock (Gate) _colors = loaded;' "$STORE"

echo 'Windows NBT parity, portable icon and cleanup regression checks passed'
