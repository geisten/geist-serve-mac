#!/usr/bin/env python3
"""Verify the shipped C23 runtime and the native child's shutdown contract."""
import os
from pathlib import Path
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
BIN = ROOT / "build/Geist.app/Contents/MacOS"
with tempfile.TemporaryDirectory(prefix="geist-mac-") as home:
    subprocess.run([str(BIN / "geist-app"), "--home", home, "--check"], check=True)
    env = dict(os.environ, GEIST_HOME=home, GEIST_NO_OPEN="1", GEIST_TEST_QUIT="1")
    with tempfile.TemporaryFile() as log:
        process = subprocess.Popen([str(BIN / "Geist")], env=env, stdout=log, stderr=log)
        try:
            deadline = time.monotonic() + 15
            child = None
            while time.monotonic() < deadline:
                result = subprocess.run(["pgrep", "-P", str(process.pid), "-x", "geist-app"], capture_output=True, text=True)
                if result.returncode == 0:
                    child = int(result.stdout.strip()); break
                if process.poll() is not None:
                    break
                time.sleep(.1)
            assert child, "native shell did not launch the C23 application"
            # The explicit hook asks this app instance to quit through AppKit;
            # it never sends an event to another installed Geist instance.
            process.wait(timeout=20)
            try:
                os.kill(child, 0)
                raise AssertionError("owned C23 child outlived the native app")
            except ProcessLookupError:
                pass
            print("native app: launches C23 runtime and stops its owned child")
        finally:
            if process.poll() is None:
                process.terminate(); process.wait(timeout=20)
