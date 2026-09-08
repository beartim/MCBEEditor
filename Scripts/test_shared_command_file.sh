#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STORE="$ROOT/Sources/Support/SharedCommandFileStore.swift"
APP="$ROOT/Sources/App/AppDelegate.swift"
DETAIL="$ROOT/Sources/UI/WorldDetailTabBarController.swift"
COMMAND_UI="$ROOT/Sources/UI/WorldCommandViewController.swift"
PARSER="$ROOT/Sources/Command/WorldCommand.swift"
MAP="$ROOT/Sources/UI/WorldMapViewController.swift"
TEXTURES="$ROOT/Sources/Support/BlockTextureOverrideStore.swift"

require() { grep -qF "$1" "$2" || { echo "missing: $1 in $2" >&2; exit 1; }; }
forbid() { ! grep -qF "$1" "$2" || { echo "forbidden: $1 in $2" >&2; exit 1; }; }

# Startup creates Documents/Commands. Both shared-folder ReadMe files are
# fixed text embedded in source and are reset from those fixed strings when
# the app starts, never from runtime help interpolation.
require '.appendingPathComponent(directoryName, isDirectory: true)' "$STORE"
require 'private static let directoryName = "Commands"' "$STORE"
require 'private static let commandFilename = "Command.txt"' "$STORE"
require 'private static let readMeFilename = "ReadMe.txt"' "$STORE"
require 'private static let readMeText = """' "$STORE"
require 'SharedCommandFileStore.prepareSharedDirectory()' "$APP"
forbid 'readMeRevision' "$STORE"
forbid 'readMeRevisionDefaultsKey' "$STORE"
forbid 'UserDefaults.standard' "$STORE"
require 'try Data(readMeText.utf8).write(to: readMeURL, options: .atomic)' "$STORE"
forbid '\(WorldCommandParser.helpText())' "$STORE"
require '当前支持的全部命令（与本版本 help 输出一致）' "$STORE"
require 'MCBEEditor 不会自动创建、修改或删除 Command.txt。' "$STORE"
require '并会在 MCBEEditor 每次启动时重置为默认内容。' "$STORE"
require 'private static let readMeText = """' "$TEXTURES"

# Read Command.txt as UTF-8, skip only blank rows and preserve original line
# numbers. Presence itself is separately exposed so an empty Command.txt still
# opens the command tab on workspace entry.
require 'static var commandFileExists: Bool' "$STORE"
require 'Commands/Command.txt 必须使用 UTF-8 文本格式' "$STORE"
require 'text.components(separatedBy: .newlines).enumerated().compactMap' "$STORE"
require 'SharedCommandFileLine(lineNumber: offset + 1, text: trimmed)' "$STORE"
require 'if SharedCommandFileStore.commandFileExists {' "$DETAIL"
require 'selectedIndex = commandTabIndex' "$DETAIL"

# Each world workspace asks once. Confirming performs a complete parser pass
# before any executor entry point is called; any syntax error refuses the
# entire batch.
require 'private var didCheckSharedCommandFile = false' "$DETAIL"
require 'title: "检测到 Command.txt"' "$DETAIL"
require 'WorldCommandParser.parse(line.text)' "$DETAIL"
require 'if !syntaxErrors.isEmpty {' "$DETAIL"
require '未执行任何命令' "$DETAIL"
require 'showBusy("正在检查 Command.txt 语法…")' "$DETAIL"
require 'commandController.executeValidatedSharedCommands(parsed)' "$DETAIL"
require 'self.mapController?.prepareForSharedCommandBatch()' "$DETAIL"
require 'func prepareForSharedCommandBatch()' "$MAP"
forbid 'showBusy("正在执行 Command.txt 命令…")' "$DETAIL"

# While the validated batch runs, the command tab stays selected; other tabs,
# close buttons and interactive modal dismissal are locked until completion.
require 'private var sharedCommandBatchRunning = false' "$DETAIL"
require 'self.setSharedCommandBatchNavigationLocked(true)' "$DETAIL"
require 'self.setSharedCommandBatchNavigationLocked(false)' "$DETAIL"
require 'item.isEnabled = !locked || index == commandTabIndex' "$DETAIL"
require 'navigation.viewControllers.first?.navigationItem.leftBarButtonItem?.isEnabled = !locked' "$DETAIL"
require 'isModalInPresentation = locked' "$DETAIL"
require 'guard !sharedCommandBatchRunning else { return }' "$DETAIL"
require 'return index == commandTabIndex' "$DETAIL"

# Validated commands run sequentially through the existing executor. The raw
# command is appended immediately, then each result is synchronously appended
# on main before the next command starts. Runtime failures do not stop later
# commands, and world invalidation happens once after the batch.
require 'for item in commands {' "$COMMAND_UI"
require 'DispatchQueue.main.sync {' "$COMMAND_UI"
require 'self.appendOutput("[第 \(item.lineNumber) 行] > \(item.rawText)")' "$COMMAND_UI"
require 'let result = try self.executor.execute(item.command)' "$COMMAND_UI"
require 'self.appendOutput(result.message, color: .systemGreen)' "$COMMAND_UI"
require 'self.appendOutput("错误：\(message)", color: .systemRed)' "$COMMAND_UI"
require '其余命令已继续执行' "$COMMAND_UI"
require 'self.session.notifyAfterDatabaseMutation()' "$COMMAND_UI"

# Textures ReadMe remains the exact fixed user-supplied wording.
require '此目录用于覆盖地图中方块的默认显示颜色。' "$TEXTURES"
require 'minecraft:bedrock.png）不受支持。' "$TEXTURES"
forbid '此目录用于覆盖地图与 X/Z 剖面中方块的默认显示颜色。' "$TEXTURES"

# Verify Commands/ReadMe contains a static copy of every current help entry in
# commandNames order, without calling helpText() at runtime.
python3 - "$PARSER" "$STORE" <<'PYEOF'
import re, sys
from pathlib import Path
parser = Path(sys.argv[1]).read_text()
store = Path(sys.argv[2]).read_text()
command_block = re.search(r'static let commandNames = \[(.*?)\]\n\n    static let usage:', parser, re.S).group(1)
names = re.findall(r'"([a-z]+)"', command_block)
usage_block = re.search(r'static let usage: \[String: String\] = \[(.*?)\n    \]\n\n    static func parse', parser, re.S).group(1)
pattern = re.compile(r'\s*"([^"\\]+)"\s*:\s*"((?:\\.|[^"\\])*)"\s*,?')
usage = {k: v.replace('\\n', '\n').replace('\\"', '"').replace('\\\\', '\\') for k, v in pattern.findall(usage_block)}
expected = '\n\n'.join(usage[name] for name in names)
readme = re.search(r'private static let readMeText = """\n(.*?)\n"""', store, re.S).group(1)
marker = '当前支持的全部命令（与本版本 help 输出一致）：\n\n'
actual = readme.split(marker, 1)[1].split('\n\n注意：本 ReadMe.txt', 1)[0]
if actual != expected:
    raise SystemExit('error: fixed Commands/ReadMe help copy is not synchronized with current command help')
PYEOF

swiftc -parse "$STORE" "$APP" "$DETAIL" "$COMMAND_UI" "$PARSER" "$TEXTURES" "$MAP"
printf 'shared Commands folder / Command.txt preflight / batch terminal checks passed\n'
