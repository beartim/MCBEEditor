#!/usr/bin/env python3
"""Check that failure diagnostics survive redirected Windows-style encoding."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from smoke_support import configure_utf8_output, create_test_database


class SmokeOutputTests(unittest.TestCase):
    def test_fixture_failure_includes_process_diagnostic(self):
        with tempfile.TemporaryDirectory(prefix="mcbe-fixture-diagnostic-") as temporary:
            world = Path(temporary) / "world"
            try:
                # This real executable cannot create a fixture: Python will
                # report the missing ASCII-relative db script on stderr.
                create_test_database(world, sys.executable)
            except Exception as error:
                self.assertIn("can't open file", str(error))
                self.assertIsInstance(error, RuntimeError)
            else:
                self.fail("invalid fixture executable unexpectedly succeeded")
            self.assertFalse((world / "db").exists())

    def test_chinese_failure_diagnostics_use_utf8(self):
        program = ("from smoke_support import configure_utf8_output; import sys; "
                   "configure_utf8_output(); "
                   "print('FAIL: 未保存修改'); print('保存失败：源世界', file=sys.stderr)")
        for encoding in ("cp1252:strict", "utf-8:strict"):
            with self.subTest(encoding=encoding):
                env = dict(os.environ, PYTHONIOENCODING=encoding)
                result = subprocess.run([sys.executable, "-c", program],
                                        cwd=Path(__file__).resolve().parent, env=env,
                                        capture_output=True, timeout=10)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.decode("utf-8").splitlines(), ["FAIL: 未保存修改"])
                self.assertEqual(result.stderr.decode("utf-8").splitlines(), ["保存失败：源世界"])


if __name__ == "__main__":
    configure_utf8_output()
    unittest.main()
