from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
errors = []

def need(path, text=None, label=None):
    p = ROOT / path
    if not p.exists():
        errors.append(f"missing {path}")
        return ""
    data = p.read_text(encoding="utf-8", errors="replace")
    if text is not None and text not in data:
        errors.append(f"{label or path}: missing {text!r}")
    return data

paths = need("CLI/Windows/CliPortablePaths.cs")
need("CLI/Windows/CliSharedCommandStore.cs", "CliPortablePaths.CommandsDirectory")
need("CLI/Windows/CliRunOptions.cs", "CliPortablePaths.WorldCacheDirectory")
need("CLI/Windows/CliInteractiveShell.cs", "CliPortablePaths.WorldCacheDirectory")
launcher = need("CLI/Windows/PortableLauncher/launcher.cpp")
need("CLI/Windows/PortableLauncher/CMakeLists.txt", "MCBE_PAYLOAD_PATH")
need("CLI/Windows/PortableLauncher/payload.rc.in", "RCDATA")
release = need("CLI/Scripts/build-windows-release.ps1")
for token in [
    "--self-contained", "PublishSingleFile=true", "IncludeNativeLibrariesForSelfExtract=true",
    "mcbe-cli.exe", "PortableLauncher", "--version", "--help", "--check",
]:
    if token not in release:
        errors.append(f"build-windows-release.ps1 missing {token!r}")
for token in ["MCBEEDITOR_PORTABLE_ROOT", "MCBEEDITOR_CACHE_ROOT", "DOTNET_BUNDLE_EXTRACT_BASE_DIR"]:
    if token not in launcher:
        errors.append(f"portable launcher missing {token}")
if "SetCurrentDirectoryW" in launcher:
    errors.append("portable launcher must preserve the caller current directory")
if "relative-command-file" not in release:
    errors.append("release script is missing the relative-path/CWD final-EXE probe")
workflow = need(".github/workflows/cli-release.yml")
for token in ["windows-latest", "build-windows-release.ps1", "CLI/Windows/dist/mcbe-cli.exe", "upload-artifact"]:
    if token not in workflow:
        errors.append(f"cli-release workflow missing Windows release token {token!r}")
if "exactly one" not in release.lower() and "Count -ne 1" not in release:
    errors.append("release script does not enforce one-file dist")

if errors:
    print("stage05a source audit: FAIL")
    for e in errors:
        print(" -", e)
    sys.exit(1)
print("stage05a source audit: PASS")
