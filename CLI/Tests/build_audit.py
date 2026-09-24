#!/usr/bin/env python3
"""Check build contracts that are easy to break during source-only maintenance.

This does not replace compiling, linking, running the native tests or testing the
published executable. Behavioral contracts live in smoke/session/native tests.
"""
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


def require_tokens(path, tokens):
    text = read(path)
    for token in tokens:
        assert token in text, f"{path}: missing {token}"
    return text


def main():
    for relative in ("CLI/Windows/MCBEEditor.Cli.csproj", "CLI/Windows.Tests/MCBEEditor.Cli.Tests.csproj"):
        path = ROOT / relative
        xml = ET.parse(path).getroot()
        for name, value in (("OutputType", "Exe"), ("TargetFramework", "net10.0"), ("PlatformTarget", "x64")):
            assert xml.findtext(f"PropertyGroup/{name}") == value, (relative, name)
        for reference in xml.findall(".//ProjectReference"):
            assert (path.parent / reference.attrib["Include"]).resolve().is_file()
        require_tokens(relative, ["MCBEEditor.LevelDB.Native.dll"])

    apple = require_tokens("CLI/Scripts/build-apple.sh", [
        "-D MCBE_CLI", "-import-objc-header", "TARGET=arm64-apple-ios13.0", "MINIMUM=13.0",
        "configure_native -DCMAKE_SYSTEM_NAME=iOS", "configure_native\n", "--target mcbe_cli_apple_bridge",
        "NativeIntegration.swift", "test_end_missing_subchunks.sh", "lipo -archs", "vtool -show-build",
        "codesign --force --sign -", "codesign --verify", "source_audit.py", "build_audit.py",
        "smoke.py", "session_smoke.py", "environment_smoke.py", "apple_build_lifecycle.py",
    ])
    # The default macOS bash is 3.2: nounset must not expand an empty optional array.
    assert "PLATFORM_OPTIONS=()" not in apple and "${PLATFORM_OPTIONS[@]}" not in apple
    require_tokens("CLI/Scripts/bootstrap-apple-native.sh", ["0.8.0a8", "v1.3.1"])
    require_tokens("CLI/Native/Apple/CMakeLists.txt", [
        "BTLevelDBBridge.mm", "BTCompressionBridge.mm", "-fobjc-arc", "mcbe_leveldb_core", "zlibstatic",
    ])
    # Preserve the iOS 13.0 compatibility fix (the modern FileHandle API requires 13.4).
    for relative in read("CLI/iOS/sources.txt").splitlines():
        assert "read(upToCount:" not in read(relative), f"iOS 13.4 API in {relative}"

    windows = require_tokens("CLI/Scripts/build-windows.ps1", [
        '"-DCMAKE_POLICY_VERSION_MINIMUM=3.5"', "bootstrap-native.ps1", "MCBEEditor.LevelDB.Native",
        "--cli-regression", "mcbe_cli_create_test_db", "MCBEEditor.Cli.Tests.csproj",
        "source_audit.py", "build_audit.py", "smoke.py", "session_smoke.py", "environment_smoke.py",
    ])
    assert " -DCMAKE_POLICY_VERSION_MINIMUM=3.5 " not in windows
    release = require_tokens("CLI/Scripts/build-windows-release.ps1", [
        "--self-contained", "PublishSingleFile=true", "IncludeNativeLibrariesForSelfExtract=true",
        "PortableLauncher", "relative-command-file", "--version", "--help", "--check", "Count -ne 1",
    ])
    assert "-Encoding utf8NoBOM" not in release, "release probe must support Windows PowerShell 5.1"
    raw_release = (ROOT / "CLI/Scripts/build-windows-release.ps1").read_bytes()
    assert raw_release.startswith(b"\xef\xbb\xbf") or raw_release.isascii(), "PowerShell 5.1 needs a BOM for non-ASCII source"
    require_tokens("CLI/Scripts/build-windows-release.ps1", ["portable_release_smoke.py", "$fixtureTool"])
    launcher = require_tokens("CLI/Windows/PortableLauncher/launcher.cpp", [
        "MCBEEDITOR_PORTABLE_ROOT", "MCBEEDITOR_CACHE_ROOT", "DOTNET_BUNDLE_EXTRACT_BASE_DIR",
    ])
    assert "SetCurrentDirectoryW" not in launcher, "launcher must preserve relative command paths"
    require_tokens("CLI/Windows/PortableLauncher/CMakeLists.txt", ["MCBE_PAYLOAD_PATH"])
    require_tokens("CLI/Windows/PortableLauncher/payload.rc.in", ["RCDATA"])
    for path in ("Windows/Native/src/mcbe_leveldb.cpp", "Sources/Bridge/BTLevelDBBridge.mm"):
        require_tokens(path, ["options.create_if_missing = false;"])
    require_tokens("CLI/Tests/Native/CreateTestDatabase.cpp", ["options.create_if_missing = true;"])
    require_tokens("Windows/Native/CMakeLists.txt", ["MCBE_BUILD_CLI_TEST_TOOLS", "CreateTestDatabase.cpp"])

    require_tokens(".github/workflows/cli-release.yml", [
        "windows-latest", "macos-15", "build-windows-release.ps1 -Test", "CLI/Windows/dist/mcbe-cli.exe",
        "build-apple.sh host CLI/build/apple-host --test", "build-apple.sh ios CLI/build/apple-ios",
        "path: CLI/build/apple-ios/mcbe-cli",
    ])
    version = ET.parse(ROOT / "CLI/Windows/MCBEEditor.Cli.csproj").findtext("PropertyGroup/Version")
    for path in ("CLI/Windows/Program.cs", "CLI/iOS/CliMain.swift", "CLI/Tests/smoke.py"):
        require_tokens(path, [f"MCBEEditor CLI {version}"])
    assert f"MCBEEditor CLI {version}" in release
    print("PASS: Windows/Apple build inputs, native test wiring, portable release and iOS 13.0 source contracts")


if __name__ == "__main__":
    main()
