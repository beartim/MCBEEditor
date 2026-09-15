from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
errors = []

def read(path):
    p = ROOT / path
    if not p.exists():
        errors.append(f"missing {path}")
        return ""
    return p.read_text(encoding="utf-8", errors="replace")

stages = read("CLI/Docs/STAGES.md")
readme = read("CLI/README.md")
build = read("CLI/Scripts/build-apple.sh")
workflow = read(".github/workflows/cli-release.yml")

for token in ["05b", "裸二进制", "arm64", "iOS 13"]:
    if token not in stages:
        errors.append(f"STAGES missing {token!r}")
if "iOS arm64 deb 发布与 Actions" in stages or "rootful 和 rootless 目录布局" in stages:
    errors.append("STAGES still requires deb packaging for 05b")
for token in ["iOS arm64 裸二进制", "build-apple.sh ios"]:
    if token not in readme:
        errors.append(f"README missing {token!r}")
for token in ["lipo -archs", "vtool -show-build", "arm64-apple-ios13.0"]:
    if token not in build:
        errors.append(f"build-apple.sh missing {token!r}")
for token in ["macos-15", "build-apple.sh ios", "CLI/build/apple-ios/mcbe-cli", "upload-artifact"]:
    if token not in workflow:
        errors.append(f"cli-release workflow missing iOS token {token!r}")
if "dpkg-deb" in workflow or ".deb" in workflow:
    errors.append("cli-release workflow unexpectedly packages a deb")

if errors:
    print("stage05b source audit: FAIL")
    for e in errors:
        print(" -", e)
    sys.exit(1)
print("stage05b source audit: PASS")
