#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
issues: list[str] = []

def text(path: str) -> str:
    p = ROOT / path
    if not p.is_file():
        issues.append(f"missing {path}")
        return ""
    return p.read_text(encoding="utf-8", errors="replace")

def require(condition: bool, message: str) -> None:
    if not condition:
        issues.append(message)

win = text("CLI/Scripts/build-windows.ps1")
apple = text("CLI/Scripts/build-apple.sh")
workflow = text(".github/workflows/cli-release.yml")

# PowerShell treats an unquoted -D...=3.5 token as separate command arguments on the
# current Windows runner, producing CMake arguments "...=3" and ".5".
require('"-DCMAKE_POLICY_VERSION_MINIMUM=3.5"' in win,
        "Windows CMake policy version must be passed as one quoted PowerShell argument")
require(' -DCMAKE_POLICY_VERSION_MINIMUM=3.5 ' not in win,
        "Windows build still contains the runner-breaking unquoted CMake policy argument")

# macOS 15 still executes /bin/bash 3.2. With `set -u`, expanding an empty array is an
# unbound-variable failure. Host mode must not expand an empty PLATFORM_OPTIONS array.
require('PLATFORM_OPTIONS=()' not in apple and '${PLATFORM_OPTIONS[@]}' not in apple,
        "Apple host build still expands an empty array under bash 3.2 + nounset")
require('configure_native()' in apple and 'configure_native -DCMAKE_SYSTEM_NAME=iOS' in apple,
        "Apple build must pass optional platform CMake arguments without an empty array")
require('configure_native\n' in apple,
        "Apple host mode must call the native configure helper with no optional arguments")


ios_main = text("CLI/iOS/CliMain.swift")
win_main = text("CLI/Windows/Program.cs")
smoke = text("CLI/Tests/smoke.py")
release_script = text("CLI/Scripts/build-windows-release.ps1")
native_cmake = text("Windows/Native/CMakeLists.txt")

# CliInteractiveShell stores output/error callbacks in CliTerminal, so CliMain.run must
# accept those callbacks as escaping before forwarding them.
require("output: @escaping (String) -> Void" in ios_main,
        "iOS CliMain.run output callback must be @escaping")
require("error: @escaping (String) -> Void" in ios_main,
        "iOS CliMain.run error callback must be @escaping")

# Both CLI implementations and their release/smoke checks use one public version.
for label, content in [
    ("iOS runtime", ios_main),
    ("Windows runtime", win_main),
    ("smoke test", smoke),
    ("Windows release script", release_script),
]:
    require("MCBEEditor CLI 1.0.0" in content,
            f"{label} does not use MCBEEditor CLI 1.0.0")
    require("0.6.0-stage06" not in content,
            f"{label} still contains the pre-1.0 CLI version")

# Release CI should use Node 24 based action majors to avoid GitHub's Node 20
# deprecation annotations.
require("actions/checkout@v6" in workflow,
        "CLI release workflow must use actions/checkout@v6")
require("actions/setup-dotnet@v5" in workflow,
        "CLI release workflow must use actions/setup-dotnet@v5")
require("actions/setup-python@v6" in workflow,
        "CLI release workflow must use actions/setup-python@v6")
require("actions/upload-artifact@v6" in workflow,
        "CLI release workflow must use actions/upload-artifact@v6")

# Third-party LevelDB warning policy is target-local: do not leak warning suppression
# into MCBEEditor sources.
require("/wd4312" in native_cmake,
        "Windows LevelDB target must suppress the known upstream C4312 pointer-sentinel warning")
require("-Wno-deprecated-declarations" in native_cmake,
        "Apple/POSIX LevelDB target must suppress the known upstream deprecated barrier warning")

win_native_tests = text("CLI/Windows.Tests/Program.cs")
require("var root = StandaloneNbtFileCodec.Decode" not in win_native_tests,
        "Windows native integration test shadows its root parameter and will fail C# compilation")
require("var rootDocument = StandaloneNbtFileCodec.Decode" in win_native_tests,
        "Windows conversion integration test must use a non-conflicting NBT root variable")

require("stage06b_build_audit.py" in win,
        "Windows cumulative build does not run the stage06b build regression audit")
require("stage06b_build_audit.py" in apple,
        "Apple cumulative host test build does not run the stage06b build regression audit")

require('build-windows-release.ps1 -Test' in workflow,
        "release workflow no longer exercises the Windows cumulative build")
require('build-apple.sh host CLI/build/apple-host --test' in workflow and
        'build-apple.sh ios CLI/build/apple-ios' in workflow,
        "release workflow no longer exercises both Apple host tests and iOS cross-build")

if issues:
    print("stage06b build audit: FAIL")
    for issue in issues:
        print("-", issue)
    raise SystemExit(1)
print("stage06b build audit: PASS")
