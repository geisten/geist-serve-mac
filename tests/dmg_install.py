#!/usr/bin/env python3
"""Install the actual DMG into a disposable Applications directory.

This does not simulate quarantine or Apple approval. No user installation,
launch-at-login setting, model file or credential store is modified.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
version = os.environ.get('VERSION', '0.0.0-dev')
image = ROOT/'build'/f'Geist-{version}-arm64.dmg'
with tempfile.TemporaryDirectory(prefix='geist-install-') as temp:
    root = Path(temp)
    mount = root/'disk'; mount.mkdir()
    applications = root/'Applications'; applications.mkdir()
    home = root/'data'
    installed = applications/'Geist.app'
    env = os.environ | {'GEIST_HOME':str(home), 'GEIST_PORT':'0'}
    model = os.environ.get('GEIST_TEST_MODEL')
    if model: env['GEIST_MODEL'] = model
    cli = installed/'Contents/MacOS/geist-cli'
    def run(*args):
        return subprocess.check_output([str(cli), *args], env=env, text=True, timeout=60)
    subprocess.run(['hdiutil','attach','-readonly','-nobrowse','-mountpoint',str(mount),str(image)],
                   check=True, capture_output=True, timeout=60)
    try:
        shutil.copytree(mount/'Geist.app', installed, symlinks=True)
    finally:
        subprocess.run(['hdiutil','detach',str(mount)],check=True,capture_output=True,timeout=30)
    try:
        subprocess.run(['codesign','--verify','--deep','--strict',str(installed)],check=True)
        run('start')
        key = json.loads(run('connection'))['api_key']
        if model:
            for attempt in range(100):
                if json.loads(run('connection'))['ready']: break
                time.sleep(.1)
            assert json.loads(run('test'))['usage']['completion_tokens'] > 0
        marker = home/'models'/'keep-me'; marker.write_text('preserved')
        run('restart')
        assert json.loads(run('connection'))['api_key'] == key
        run('stop')
        # Manual replacement path using the verified candidate; not Sparkle.
        previous = applications/'previous.app'
        installed.rename(previous)
        shutil.copytree(previous, installed, symlinks=True)
        run('start')
        assert json.loads(run('connection'))['api_key'] == key
        run('stop')
        shutil.rmtree(installed)
        assert marker.read_text() == 'preserved'
        assert (home/'api-key').read_text() == key
        assert not (home/'connection.json').exists()
    finally:
        if cli.exists():
            subprocess.run([str(cli),'stop'],env=env,capture_output=True,timeout=30)
print('DMG: mounted/copied installation, relocated CLI, restart, manual replacement and removal passed')
print('DMG real inference: ' + ('passed' if model else 'SKIPPED; set GEIST_TEST_MODEL'))
