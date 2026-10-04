"""Shared process-test setup; never creates or repairs production databases."""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


def configure_utf8_output():
    # Windows redirected Python stdout can default to cp1252. A failed check
    # must report the CLI's Chinese diagnostics without raising a second error.
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8", errors="backslashreplace")


def create_test_database(world, fixture_tool):
    world = Path(world)
    world.mkdir(parents=True, exist_ok=True)
    destination = world / "db"
    if destination.exists():
        raise FileExistsError(f"Test database already exists: {destination}")
    # The native fixture tool uses narrow argv on Windows. Pass an ASCII
    # relative name, then move the closed database into the Unicode world.
    with tempfile.TemporaryDirectory(prefix="mcbe-smoke-db-") as temporary:
        root = Path(temporary)
        try:
            subprocess.run([str(fixture_tool), "db"], cwd=root, check=True,
                           capture_output=True, text=True, encoding="utf-8", timeout=30)
        except subprocess.CalledProcessError as error:
            diagnostic = (error.stderr or error.stdout or "").strip()
            raise RuntimeError(f"Native database fixture failed (exit {error.returncode}): {diagnostic}") from error
        shutil.move(str(root / "db"), destination)


def snapshot(root):
    root = Path(root)
    return {p.relative_to(root).as_posix(): p.read_bytes() for p in root.rglob("*") if p.is_file()}
