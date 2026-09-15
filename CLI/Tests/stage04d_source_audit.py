#!/usr/bin/env python3
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[2]
fail=[]
def req(v,m):
    if not v: fail.append(m)
def txt(p): return (ROOT/p).read_text(encoding='utf-8')
for p in ['CLI/Windows/CliSharedCommandStore.cs','CLI/iOS/CliSharedCommandStore.swift']:
    req((ROOT/p).exists(), f'missing {p}')
win=txt('CLI/Windows/CliSharedCommandStore.cs') if (ROOT/'CLI/Windows/CliSharedCommandStore.cs').exists() else ''
ios=txt('CLI/iOS/CliSharedCommandStore.swift') if (ROOT/'CLI/iOS/CliSharedCommandStore.swift').exists() else ''
for marker in ['Commands','ReadMe.txt','Command.txt']:
    req(marker in win and marker in ios, f'shared command store missing {marker}')
req('WriteAllText' in win and 'CommandFilePath' in win, 'Windows fixed ReadMe / user Command path contract missing')
req('.atomic' in ios and 'commandFile' in ios, 'Swift fixed ReadMe / user Command path contract missing')
req('CliCommandFile.Read' in win and 'CliCommandFile.read' in ios, 'Command.txt must reuse strict UTF-8/physical-line parser')
req('PrepareDefault' in txt('CLI/Windows/Program.cs') and 'prepareDefault' in txt('CLI/iOS/CliEntry.swift'), 'startup Commands preparation not wired')
ws=txt('CLI/Windows/CliInteractiveShell.cs'); ss=txt('CLI/iOS/CliInteractiveShell.swift')
for marker in ['Command.txt','语法检查','是否执行']:
    req(marker in ws and marker in ss, f'interactive Command.txt flow missing {marker}')
req('CliCommandPlan.Parse' in ws and 'CliCommandPlan.parse' in ss, 'Command.txt whole-batch preflight missing')
req('batchExitStatus' in ws and 'batchExitStatus' in ss, 'runtime/preflight batch failures must affect final exit status')
req('MCBEEditor CLI 1.0.0' in txt('CLI/Windows/Program.cs') and 'MCBEEditor CLI 1.0.0' in txt('CLI/iOS/CliMain.swift'), 'CLI 1.0.0 version missing')
req('CLI/iOS/CliSharedCommandStore.swift' in txt('CLI/iOS/sources.txt'), 'Swift shared command store not wired')
if fail:
    for m in fail: print('FAIL:',m)
    sys.exit(1)
print('PASS: stage04d Commands directory / fixed ReadMe / Command.txt batch contract present')
