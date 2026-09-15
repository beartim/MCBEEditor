#!/usr/bin/env python3
from pathlib import Path
import json, sys
ROOT=Path(__file__).resolve().parents[2]
fail=[]
def req(v,m):
    if not v: fail.append(m)
def txt(p): return (ROOT/p).read_text(encoding='utf-8')
win=txt('CLI/Windows/Program.cs'); ios=txt('CLI/iOS/CliMain.swift'); parser=txt('Sources/Command/WorldCommand.swift')
req((('0.4.0-stage04e' in win and '0.4.0-stage04e' in ios) or ('0.5.0-stage05b' in win and '0.5.0-stage05b' in ios) or ('0.6.0-stage06' in win and '0.6.0-stage06' in ios)), 'stage04e version missing')
req('tokens.first?.lowercased()' in parser, 'Swift root command is not case-insensitive')
for marker in ['arguments.first?.lowercased()', 'parseDimension(_ text: String)', 'text.lowercased()']:
    req(marker in parser, f'Swift parser normalization marker missing: {marker}')
coord=parser[parser.find('private static func parseCoordinates'):parser.find('private static func parseBiomeID')]
req('Int32(values[offset])' in coord and 'Int32(values[offset + 2])' in coord, 'Swift block X/Z are not constrained to Int32')
entity=txt('Windows/MCBEEditor.Core/Chunk/EntityActionCommand.cs')
req('args[0].ToLowerInvariant() switch' in entity, 'Windows effect subcommand is still case-sensitive')
cases=json.loads(txt('CLI/Shared/parser-cases.json'))
req(not any('expected_by_backend' in c for c in cases), 'shared parser fixtures still contain backend-specific expectations')
by_id={c['id']:c for c in cases}
for cid in ['parity-case-root','parity-case-subcommand','parity-int32-max','parity-int32-overflow','parity-semantic-all']:
    req(cid in by_id, f'missing shared 04e fixture {cid}')
if 'parity-case-root' in by_id: req(by_id['parity-case-root']['valid'] is True, 'mixed-case root must be valid')
if 'parity-int32-overflow' in by_id: req(by_id['parity-int32-overflow']['valid'] is False, 'Int32 overflow must be invalid')
if 'parity-semantic-all' in by_id: req(by_id['parity-semantic-all']['valid'] is False, 'semantic ALL must remain case-sensitive')
if fail:
    for m in fail: print('FAIL:',m)
    sys.exit(1)
print('PASS: stage04e parser case/bounds parity contract present')
