#!/usr/bin/env python3
"""The native menu and CLI reuse one service; closing the menu preserves it."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

ROOT=Path(__file__).resolve().parents[1]
BIN=ROOT/'build/Geist.app/Contents/MacOS'
with tempfile.TemporaryDirectory(prefix='geist-mac-') as home:
    subprocess.run([str(BIN/'geist-app'),'--home',home,'--check'],check=True)
    env=os.environ|{'GEIST_HOME':home,'GEIST_PORT':'0','GEIST_NO_OPEN':'1','GEIST_TEST_QUIT':'1'}
    def cli(*args):
        p=subprocess.run([str(BIN/'geist-cli'),*args],env=env,capture_output=True,text=True,timeout=30)
        assert p.returncode==0,p.stderr
        return p.stdout
    try:
        owners=[]
        for _ in range(2):
            with tempfile.TemporaryFile() as log:
                process=subprocess.Popen([str(BIN/'Geist')],env=env,stdout=log,stderr=log)
                try:
                    process.wait(timeout=35)
                    assert process.returncode==0
                finally:
                    if process.poll() is None: process.terminate();process.wait(timeout=10)
            descriptor=json.loads((Path(home)/'connection.json').read_text())
            owners.append(descriptor['pid'])
            assert json.loads(cli('status'))['runtime']=='geistd'
        assert owners[0]==owners[1],owners
        cli('stop')
        assert not (Path(home)/'connection.json').exists()
        print('native menu: starts and reattaches to one service; menu quit preserves it; explicit stop cleans up')
    finally:
        subprocess.run([str(BIN/'geist-cli'),'stop'],env=env,capture_output=True,timeout=30)
