#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
issues = []

def text(path: str) -> str:
    p = ROOT / path
    if not p.exists():
        issues.append(f"missing {path}")
        return ""
    return p.read_text(encoding="utf-8", errors="replace")

def require(condition: bool, message: str) -> None:
    if not condition:
        issues.append(message)

win = text("CLI/Windows/Program.cs") + text("CLI/Windows/CliFormatConverter.cs")
ios = text("CLI/iOS/CliMain.swift") + text("CLI/iOS/CliFormatConverter.swift")
readme = text("CLI/README.md")
sources = text("CLI/iOS/sources.txt")
win_tests = text("CLI/Windows.Tests/Program.cs")
ios_tests = text("CLI/iOS.Tests/NativeIntegration.swift")
win_build = text("CLI/Scripts/build-windows.ps1")
apple_build = text("CLI/Scripts/build-apple.sh")
smoke = text("CLI/Tests/smoke.py")
final_report = text("WORK_FINAL_REPORT.md")

for token in ["--convert", "--to", "big-endian", "little-endian", "little-varint", "json", "mcstructure"]:
    require(token in win, f"Windows converter missing {token}")
    require(token in ios, f"Swift converter missing {token}")
    require(token in readme, f"README missing converter token {token}")
require("StandaloneNbtFileCodec.Decode" in win and "StandaloneNbtFileCodec.Encode" in win and "EncodeAsMcStructure" in win,
        "Windows converter does not reuse standalone NBT codecs")
require("StandaloneNBTFileCodec.decode" in ios and "StandaloneNBTFileCodec.encode" in ios and "encodeAsMCStructure" in ios,
        "Swift converter does not reuse standalone NBT codecs")
require("CLI/iOS/CliFormatConverter.swift" in sources, "Swift converter missing from sources.txt")
for test_source, backend in [(win_tests, "Windows"), (ios_tests, "Swift")]:
    require("--convert" in test_source and "little-varint" in test_source and "mcstructure" in test_source,
            f"{backend} native integration lacks format conversion coverage")
require("stage06_conversion_audit.py" in win_build, "Windows cumulative test build does not run stage06 audit")
require("stage06_conversion_audit.py" in apple_build, "Apple cumulative test build does not run stage06 audit")
require("MCBEEditor CLI 0.6.0-stage06" in win and "MCBEEditor CLI 0.6.0-stage06" in ios, "runtime version is not stage06 on both backends")
require("MCBEEditor CLI 0.6.0-stage06" in smoke and "--help", "smoke test does not expect stage06 runtime")
require("--convert" in smoke and "little-varint" in smoke and "--overwrite" in smoke, "process smoke test lacks converter chain")
require("没有引入 NBT 编辑器功能" in final_report or "没有加入 NBT 编辑器功能" in final_report, "final report does not preserve no-editor scope")

if issues:
    print("stage06 conversion audit: FAIL")
    for issue in issues:
        print("-", issue)
    raise SystemExit(1)
print("stage06 conversion audit: PASS")
