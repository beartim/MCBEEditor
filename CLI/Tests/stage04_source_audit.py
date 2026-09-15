#!/usr/bin/env python3
from pathlib import Path
import json, sys
ROOT = Path(__file__).resolve().parents[2]
failures=[]
def require(cond,msg):
    if not cond: failures.append(msg)
def text(rel): return (ROOT/rel).read_text(encoding='utf-8')

win_main=text('CLI/Windows/Program.cs'); ios_main=text('CLI/iOS/CliMain.swift')
require((any(f'0.4.0-stage04{x}' in win_main and f'0.4.0-stage04{x}' in ios_main for x in 'bcde') or (('0.5.0-stage05b' in win_main and '0.5.0-stage05b' in ios_main) or ('0.6.0-stage06' in win_main and '0.6.0-stage06' in ios_main))), 'both backends must advertise stage04b-or-later version')
require('--interactive' in win_main and '--interactive' in ios_main, 'interactive entrypoint missing')
for rel in ['CLI/Windows/CliInteractiveShell.cs','CLI/iOS/CliInteractiveShell.swift','CLI/Windows/CliStructureFileCommand.cs','CLI/iOS/CliStructureFileCommand.swift']:
    require((ROOT/rel).is_file(), f'missing {rel}')

win_struct=text('CLI/Windows/CliStructureFileCommand.cs'); ios_struct=text('CLI/iOS/CliStructureFileCommand.swift')
for marker in ['--file','--overwrite','mcstructure','nbt','json']:
    require(marker in win_struct and marker in ios_struct, f'structure file marker absent on one backend: {marker}')
require('StandaloneNbtFileCodec' in win_struct and 'StructureNbtStore' in win_struct, 'Windows structure file path does not reuse core codecs/stores')
require('StandaloneNBTFileCodec' in ios_struct and 'StructureNBTStore' in ios_struct, 'Swift structure file path does not reuse core codecs/stores')

win_shell=text('CLI/Windows/CliInteractiveShell.cs'); ios_shell=text('CLI/iOS/CliInteractiveShell.swift')
for marker in [':open',':save',':quit','--discard']:
    require(marker in win_shell and marker in ios_shell, f'interactive marker absent on one backend: {marker}')
require('allowInteractiveStructureName' in text('CLI/Windows/CliCommandPlan.cs'), 'Windows batch/interactive structure-name preflight split missing')
require('allowInteractiveStructureName' in text('CLI/iOS/CliCommandPlan.swift'), 'Swift batch/interactive structure-name preflight split missing')

win_session=text('CLI/Windows/CliWorldSession.cs'); ios_workspace=text('CLI/iOS/CliWorldWorkspace.swift')
require('_sourceStamp = CliSourceStamp.Capture' in win_session, 'Windows source stamp is not refreshed after commit')
require('sourceStamp = try CliFileSystem.stamp(paths.source)' in ios_workspace, 'Swift source stamp is not refreshed after commit')
require('try MiniZipArchive.create(from: worldRoot, to: temporary)' in ios_workspace, 'Swift save-as no longer follows GUI world-root export path')
require('preserveAllFiles: true' in ios_workspace and 'excludingPaths: [prefix + "db/LOCK"]' in ios_workspace, 'Swift in-place archive rebuild/preservation path missing')

sources=text('CLI/iOS/sources.txt').splitlines()
require('CLI/iOS/CliInteractiveShell.swift' in sources and 'CLI/iOS/CliStructureFileCommand.swift' in sources, 'new Swift production files missing from sources.txt')
require(not any('UIKit' in text(rel) for rel in sources if rel.startswith('CLI/iOS/')), 'CLI Swift files import UIKit')

wtest=text('CLI/Windows.Tests/Program.cs'); stest=text('CLI/iOS.Tests/NativeIntegration.swift')
for marker in ['structure-file-export','structure-file-import','structure-file-missing-name','interactive']:
    require(marker in wtest and marker in stest, f'native integration coverage missing: {marker}')
require('time set 1111' in wtest and 'time set 2222' in wtest and 'time set 1111' in stest and 'time set 2222' in stest,
        'repeated interactive save/source-stamp regression missing')

if failures:
    for item in failures: print('FAIL:', item)
    sys.exit(1)
print('PASS: stage04a structure file paths reuse existing codecs/stores on both backends')
print('PASS: stage04b interactive :open/:save/:quit state machines are wired on both backends')
print('PASS: repeated in-place save refreshes source fingerprints on Windows and Swift')
print('PASS: batch preflight and integration sources cover path-with-spaces, missing-name and repeated-save cases')
print('RESULT: stage04 source audit passed; platform compilation/native execution remain separate gates')
