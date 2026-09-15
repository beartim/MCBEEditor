#!/usr/bin/env python3
from pathlib import Path
import sys
ROOT = Path(__file__).resolve().parents[2]
failures=[]
def require(cond,msg):
    if not cond: failures.append(msg)
def text(rel): return (ROOT/rel).read_text(encoding='utf-8')

for rel in ['CLI/Windows/CliTerminal.cs','CLI/iOS/CliTerminal.swift']:
    require((ROOT/rel).is_file(), f'missing {rel}')
win_shell=text('CLI/Windows/CliInteractiveShell.cs')
ios_shell=text('CLI/iOS/CliInteractiveShell.swift')
for marker in [':history', ':clear']:
    require(marker in win_shell and marker in ios_shell, f'missing interactive meta command {marker}')
for marker in ['UpArrow','DownArrow','LeftArrow','RightArrow']:
    require(marker in text('CLI/Windows/CliTerminal.cs') if (ROOT/'CLI/Windows/CliTerminal.cs').exists() else False,
            f'Windows terminal editor missing {marker}')
for marker in ['historyUp','historyDown','cursorLeft','cursorRight']:
    require(marker in text('CLI/iOS/CliTerminal.swift') if (ROOT/'CLI/iOS/CliTerminal.swift').exists() else False,
            f'Swift terminal editor missing {marker}')
win_term=text('CLI/Windows/CliTerminal.cs') if (ROOT/'CLI/Windows/CliTerminal.cs').exists() else ''
ios_term=text('CLI/iOS/CliTerminal.swift') if (ROOT/'CLI/iOS/CliTerminal.swift').exists() else ''
require('IsOutputRedirected' in win_term and 'IsInputRedirected' in win_term, 'Windows TTY/redirection detection missing')
require('isatty' in ios_term, 'Swift TTY/redirection detection missing')
require('_interactiveKeys = terminalFeatures && !Console.IsInputRedirected && !Console.IsOutputRedirected' in win_term, 'Windows raw line editor must be disabled when stdout is redirected')
require('rawInput = terminalFeatures && isatty(STDIN_FILENO) == 1 && isatty(STDOUT_FILENO) == 1' in ios_term, 'Swift raw line editor must be disabled when stdout is redirected')
require('UseAnsi' in win_term and 'useANSI' in ios_term, 'ANSI gating missing')
require('IsErrorRedirected' in win_term and '_useAnsiError' in win_term, 'Windows stderr ANSI must have its own redirection gate')
require('STDERR_FILENO' in ios_term and 'useANSIError' in ios_term, 'Swift stderr ANSI must have its own redirection gate')
require('CliOutputKind' in win_term and 'WorldCommandOutputStyle' in ios_term, 'styled command output mapping missing')
require((any(f'0.4.0-stage04{x}' in text('CLI/Windows/Program.cs') and f'0.4.0-stage04{x}' in text('CLI/iOS/CliMain.swift') for x in 'cde') or (('0.5.0-stage05b' in text('CLI/Windows/Program.cs') and '0.5.0-stage05b' in text('CLI/iOS/CliMain.swift')) or ('0.6.0-stage06' in text('CLI/Windows/Program.cs') and '0.6.0-stage06' in text('CLI/iOS/CliMain.swift')))), 'stage04c-or-later version missing')
require('CLI/iOS/CliTerminal.swift' in text('CLI/iOS/sources.txt'), 'Swift terminal source not wired')

if failures:
    for f in failures: print('FAIL:', f)
    sys.exit(1)
print('PASS: stage04c interactive history/editor/clear/color source contract present on both backends')
