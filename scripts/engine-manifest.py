#!/usr/bin/env python3
"""Verify the engine identity in the signed macOS bundle."""
import json
from pathlib import Path
import re
import subprocess
import sys
binary, manifest = map(Path, sys.argv[1:3])
result = subprocess.run([str(binary.resolve()), '--build-info'], check=True, capture_output=True, timeout=10)
assert len(result.stdout) <= 8192, 'Oversized engine metadata'
identity = json.loads(result.stdout)
lib = identity['geistlib']
assert re.fullmatch(r'[A-Za-z0-9.+_-]{1,63}', lib['version'])
assert re.fullmatch(r'[0-9a-f]{40}|[0-9a-f]{64}', lib['revision'])
assert lib['source_state'] == 'clean', 'Release engine must have clean source'
assert re.fullmatch(r'[0-9a-f]{64}', identity['archive_sha256'])
if '--verify' in sys.argv:
    assert json.loads(manifest.read_text()) == identity, 'Packaged engine identity mismatch'
else:
    manifest.write_text(json.dumps(identity, indent=2) + '\n')
