#!/usr/bin/env python3
"""Exercise real CLI sessions and file lifecycle with a valid test database.

Commands under test edit level.dat, but dimension preflight opens LevelDB.
Database/terrain behavior stays in Windows.Tests and iOS.Tests.
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import queue
import signal
import struct
import subprocess
import tempfile
import threading
import time
import zipfile
from smoke_support import configure_utf8_output, create_test_database, snapshot


def level_dat(x=0, y=64, z=0):
    # Hand-encoded little-endian NBT; independent of the production writer.
    payload = b"\x0a\x00\x00"
    for name, value in ((b"SpawnX", x), (b"SpawnY", y), (b"SpawnZ", z)):
        payload += b"\x03" + struct.pack("<H", len(name)) + name + struct.pack("<i", value)
    payload += b"\x00"
    return struct.pack("<II", 8, len(payload)) + payload


class Session:
    def __init__(self, executable, env):
        self.process = subprocess.Popen(executable + ["--interactive"], stdin=subprocess.PIPE,
                                        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                        text=True, encoding="utf-8", env=env, bufsize=1)
        self.lines, self.errors, self.pending = [], [], queue.Queue()
        self.threads = []
        for stream, target in ((self.process.stdout, self.lines), (self.process.stderr, self.errors)):
            def read(stream=stream, target=target):
                for line in stream:
                    target.append(line)
                    if target is self.lines:
                        self.pending.put(line)
            thread = threading.Thread(target=read, daemon=True)
            thread.start()
            self.threads.append(thread)

    def send(self, *lines):
        self.process.stdin.write("\n".join(lines) + "\n")
        self.process.stdin.flush()

    def open(self, source, in_place=False):
        self.send(f':open "{source}"' + (" --in-place" if in_place else ""))
        line = self.wait_for("已打开工作副本：")
        return Path(line.split("已打开工作副本：", 1)[1].strip())

    def wait_for(self, text):
        while True:
            line = self.pending.get(timeout=30)
            if text in line:
                return line

    def finish(self, *lines):
        self.send(*lines)
        self.process.stdin.close()
        self.process.wait(timeout=30)
        for thread in self.threads:
            thread.join(timeout=5)
        return self.process.returncode, "".join(self.lines), "".join(self.errors)

    def close(self):
        if self.process.poll() is None:
            self.process.kill()
        self.process.wait(timeout=5)
        for thread in self.threads:
            thread.join(timeout=5)
        for stream in (self.process.stdin, self.process.stdout, self.process.stderr):
            stream.close()


def main():
    configure_utf8_output()
    parser = argparse.ArgumentParser()
    parser.add_argument("--fixture-tool", required=True, type=Path)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    executable = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not executable:
        parser.error("supply an executable after --")
    fixture_tool = args.fixture_tool.resolve(strict=True)
    failures, count = [], 0
    with tempfile.TemporaryDirectory(prefix="mcbe-cli-session-") as temporary:
        root = Path(temporary)
        source = root / "源世界 with spaces"
        create_test_database(source, fixture_tool)
        original = level_dat()
        (source / "level.dat").write_bytes(original)
        (source / "untouched.bin").write_bytes(b"\x00\x80\xff")
        source_before = snapshot(source)
        env = dict(os.environ, MCBEEDITOR_PORTABLE_ROOT=str(root / "portable"),
                   MCBEEDITOR_CACHE_ROOT=str(root / "cache"))

        def check(name, action):
            nonlocal count
            count += 1
            try:
                action()
                assert snapshot(source) == source_before, "changed source world bytes"
                print("PASS", name)
            except (AssertionError, OSError, queue.Empty, subprocess.TimeoutExpired) as error:
                failures.append(f"{name}: {error}")
                print("FAIL", failures[-1])

        def recovered_input(line):
            session = Session(executable, env)
            try:
                code, out, err = session.finish(line, ":history", ":quit")
                assert code == 0 and ":history" in out and err, (code, out, err)
            finally:
                session.close()

        check("unclosed-quote-recovers", lambda: recovered_input(':open "unfinished'))
        check("missing-world-recovers", lambda: recovered_input(f':open "{root / "missing"}"'))

        def failed_switch(corrupt):
            session = Session(executable, env)
            destination = root / f"after-failed-switch-{corrupt}.mcworld"
            invalid = root / ("corrupt" if corrupt else "missing")
            if corrupt:
                (invalid / "db").mkdir(parents=True)
                (invalid / "level.dat").write_bytes(b"invalid")
            try:
                working = session.open(source)
                code, out, err = session.finish(f':open "{invalid}"', "setworldspawn 9 70 4",
                                                f':save "{destination}"', ":quit")
                assert code == 0 and destination.is_file() and err, (code, out, err)
                with zipfile.ZipFile(destination) as archive:
                    assert archive.read("level.dat") == level_dat(9, 70, 4)
                assert not working.exists(), "successful saved session was not cleaned up"
            finally:
                session.close()
        check("failed-open-keeps-current-world", lambda: failed_switch(False))
        check("corrupt-world-keeps-current-world", lambda: failed_switch(True))

        def reject_current_copy_as_source():
            session = Session(executable, env)
            destination = root / "after-rejected-source.mcworld"
            try:
                working = session.open(source)
                code, out, err = session.finish(f':open "{working}" --in-place', "setworldspawn 2 73 8",
                                                f':save "{destination}"', ":quit")
                assert code == 0 and out.count("已打开工作副本") == 1 and err, (code, out, err)
                with zipfile.ZipFile(destination) as archive:
                    assert archive.read("level.dat") == level_dat(2, 73, 8)
                assert not working.exists()
            finally:
                session.close()
        check("active-work-copy-cannot-become-new-source", reject_current_copy_as_source)

        def reject_save(location):
            session = Session(executable, env)
            destination = root / f"recovered-{location}.mcworld"
            try:
                working = session.open(source)
                forbidden = {"cache": working.parent / "lost.mcworld",
                             "working": working / "lost.mcworld",
                             "source": source / "lost.mcworld",
                             "directory": root / "directory.mcworld"}[location]
                if location == "directory":
                    forbidden.mkdir(exist_ok=True)
                code, out, err = session.finish("setworldspawn 5 80 7", f':save "{forbidden}"',
                                                ":quit", f':save "{destination}"', ":quit")
                assert code == 0 and "未保存修改" in err and destination.exists(), (code, out, err)
                assert f"导出完成：{forbidden}" not in out
                with zipfile.ZipFile(destination) as archive:
                    assert archive.read("level.dat") == level_dat(5, 80, 7)
                assert not working.exists()
            finally:
                session.close()
                (source / "lost.mcworld").unlink(missing_ok=True)
        for location in ("cache", "working", "source", "directory"):
            check(f"reject-save-{location}-keeps-dirty", lambda location=location: reject_save(location))

        def repeated_save():
            target = root / "in-place"
            create_test_database(target, fixture_tool)
            (target / "level.dat").write_bytes(original)
            session = Session(executable, env)
            try:
                working = session.open(target, in_place=True)
                code, out, err = session.finish("setworldspawn 1 71 2", ":save", "setworldspawn 3 72 4", ":save", ":quit")
                assert code == 0 and out.count("原位更新完成") == 2, (code, out, err)
                assert (target / "level.dat").read_bytes() == level_dat(3, 72, 4)
                assert not working.exists()
            finally:
                session.close()
        check("repeated-in-place-save", repeated_save)

        def save_copy_then_in_place():
            target = root / "in-place-after-copy"
            create_test_database(target, fixture_tool)
            (target / "level.dat").write_bytes(original)
            backup = root / "saved-copy.mcworld"
            session = Session(executable, env)
            try:
                session.open(target, in_place=True)
                code, out, err = session.finish("setworldspawn 9 70 4", f':save "{backup}"', ":save", ":quit")
                assert code == 0 and "原位更新完成" in out, (code, out, err)
                assert (target / "level.dat").read_bytes() == level_dat(9, 70, 4), "save-as hid a pending in-place save"
                with zipfile.ZipFile(backup) as archive:
                    assert archive.read("level.dat") == level_dat(9, 70, 4)
            finally:
                session.close()
        check("save-copy-does-not-hide-pending-in-place", save_copy_then_in_place)

        if os.name == "posix":
            def interrupted_save():
                target = root / "cancelled"
                create_test_database(target, fixture_tool)
                (target / "level.dat").write_bytes(original)
                session = Session(executable, env)
                try:
                    session.open(target, in_place=True)
                    session.send("setworldspawn 9 70 4")
                    session.wait_for("setworldspawn 完成")
                    session.process.send_signal(signal.SIGINT)
                    # The async managed signal callback must run before we release
                    # its blocked stdin read. The process is already at the prompt.
                    time.sleep(0.2)
                    if session.process.poll() is None:
                        code, out, err = session.finish(":save")
                    else:
                        code, out, err = session.process.returncode, "".join(session.lines), "".join(session.errors)
                    assert code == 130 and "原位更新完成" not in out, (code, out, err)
                    assert (target / "level.dat").read_bytes() == original, "processed :save after cancellation"
                finally:
                    session.close()
            check("cancelled-input-cannot-save", interrupted_save)
        else:
            print("SKIP SIGINT process case: POSIX signal delivery required")

        def preflight():
            result = subprocess.run(executable + ["--world", str(source), "--cache-dir", str(root / "batch-cache"),
                                    "--command", "setworldspawn 99 88 77", "--command", "unknown-command", "--in-place"],
                                    capture_output=True, env=env, timeout=30)
            assert result.returncode == 2, result.stderr
            assert not (root / "batch-cache").exists()
        check("whole-batch-preflight-before-write", preflight)

        def mixed_help():
            for name in ("HeLp", "StRuCtUrE", "CONVERT"):
                result = subprocess.run(executable + ["--help", name], capture_output=True, env=env, timeout=30)
                assert result.returncode == 0, result.stderr
                if name == "StRuCtUrE":
                    assert b"--file" in result.stdout
        check("mixed-case-help", mixed_help)

    if failures:
        raise SystemExit(f"FAIL: {len(failures)}/{count} session cases")
    print(f"PASS: {count} session cases; valid native database fixture; level.dat/file lifecycle")


if __name__ == "__main__":
    main()
