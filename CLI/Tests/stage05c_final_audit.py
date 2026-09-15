#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
issues: list[str] = []

def text(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")

def require(condition: bool, message: str) -> None:
    if not condition:
        issues.append(message)

report = ROOT / "WORK_FINAL_REPORT.md"
require(report.is_file(), "WORK_FINAL_REPORT.md is missing")

stages = text("CLI/Docs/STAGES.md")
readme = text("CLI/README.md")
checkpoint = text("WORK_CHECKPOINT.md")
win_build = text("CLI/Scripts/build-windows.ps1")
apple_build = text("CLI/Scripts/build-apple.sh")
workflow = text(".github/workflows/cli-release.yml")
gitignore = text(".gitignore")

require("| 05c | 一次全量最终审计和最终报告 | 已完成" in stages,
        "STAGES.md does not mark 05c complete")
require("stage05c" in readme.lower(),
        "CLI README no longer preserves the stage05c final-audit baseline")
require("stage05c" in checkpoint.lower() and "下一轮从 **05c" not in checkpoint,
        "WORK_CHECKPOINT.md still points at 05c as future work")
require("stage05c_final_audit.py" in win_build,
        "Windows cumulative build does not invoke the final 05c audit")
windows_audit_chain = r"""    & python (Join-Path $root 'CLI\Tests\stage05b_source_audit.py')
    if ($LASTEXITCODE -ne 0) { throw 'CLI stage 05b source audit failed.' }
    & python (Join-Path $root 'CLI\Tests\stage05c_final_audit.py')
    if ($LASTEXITCODE -ne 0) { throw 'CLI stage 05c final audit failed.' }
"""
require(windows_audit_chain in win_build,
        "Windows cumulative build can mask stage05b failure or mislabel the stage05c failure")
require("stage05c_final_audit.py" in apple_build,
        "Apple cumulative build does not invoke the final 05c audit")
require("build-windows-release.ps1 -Test" in readme and "build-apple.sh ios" in readme,
        "README no longer documents both final release entry points")
require("CLI/Windows/dist/mcbe-cli.exe" in workflow and "CLI/build/apple-ios/mcbe-cli" in workflow,
        "release workflow no longer uploads both final platform artifacts")
legacy_ios_workflow = text(".github/workflows/build-ios.yml")
for obsolete in ("project-ios13-legacy.yml", "bootstrap_ios13_legacy.sh", "MapMarker.swift", "MapMarkerListViewController.swift", "WorldBackupService.swift"):
    require(obsolete not in legacy_ios_workflow, f"obsolete ZIP-overlay cleanup remains in build-ios workflow: {obsolete}")
require("dpkg-deb" not in workflow and "rootful" not in workflow.lower() and "rootless" not in workflow.lower(),
        "iOS release workflow regressed to deb/rootful/rootless packaging")
for pattern in ("CLI/**/bin/", "CLI/**/obj/", "CLI/Windows/artifacts/", "CLI/Windows/dist/", "CLI/Windows/PortableLauncher/build/", "__pycache__/"):
    require(pattern in gitignore, f".gitignore does not exclude generated CLI artifact: {pattern}")

inventory = json.loads(text("CLI/Shared/command-inventory.json"))
require(inventory.get("checkpoint_tag") == "stage05c",
        "command inventory checkpoint_tag is not stage05c")
require(inventory.get("checkpoint") == 5,
        "command inventory checkpoint is no longer stage 5")
require(len(inventory.get("commands", [])) == 26,
        "command inventory no longer contains 26 root commands")
require(inventory.get("known_parser_differences") == [],
        "known parser differences reappeared after stage04e alignment")
for backend in ("windows", "ios"):
    state = inventory.get("current_backend_state", {}).get(backend, "")
    require("stage05" in state and "runtime_unverified" in state,
            f"{backend} final backend state does not preserve the platform-runtime-unverified boundary")

for folder in (ROOT / "CLI/iOS", ROOT / "CLI/Windows"):
    for path in folder.rglob("*"):
        if not path.is_file() or path.suffix.lower() not in {".swift", ".cs"}:
            continue
        source = path.read_text(encoding="utf-8")
        require("import UIKit" not in source and "import AppKit" not in source and "System.Windows" not in source,
                f"GUI dependency leaked into CLI production source: {path.relative_to(ROOT)}")

if issues:
    print("stage05c final audit: FAIL")
    for issue in issues:
        print(f"- {issue}")
    raise SystemExit(1)
print("stage05c final audit: PASS")
