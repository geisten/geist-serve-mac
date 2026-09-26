#!/usr/bin/env python3
"""Explicit nested signing and fail-closed notarization. Never publishes releases."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess


def run(*args, **kwargs):
    return subprocess.run(args, check=True, text=True, **kwargs)


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def targets(app):
    fw = app / 'Contents/Frameworks/Sparkle.framework'
    version = fw / 'Versions/B'
    return [app / 'Contents/MacOS/geist-cli', app / 'Contents/MacOS/geist-app', app / 'Contents/MacOS/geistd',
            version / 'Autoupdate', version / 'Updater.app',
            version / 'XPCServices/Downloader.xpc', version / 'XPCServices/Installer.xpc',
            fw, app]


def sign(app, identity, keychain=None):
    paths = targets(app)
    if not all(p.exists() for p in paths):
        raise ValueError('Incomplete app/Sparkle payload; refusing partial signing')
    if identity != '-':
        if not re.fullmatch(r'[A-Fa-f0-9]{40}', identity):
            raise ValueError('Use the exact Developer ID Application identity SHA-1 fingerprint')
        identities = run('security', 'find-identity', '-v', '-p', 'codesigning',
                         *([keychain] if keychain else []), capture_output=True).stdout
        if not any(identity.lower() in line.lower() and 'Developer ID Application:' in line
                   for line in identities.splitlines()):
            raise ValueError('Developer ID Application identity with private key not available')
    for path in paths:
        if path == app:
            # Hash all final signed payloads before sealing the outer bundle.
            content = app / 'Contents'
            manifest = ''.join(digest(content / name)
                               + '  ' + name + '\n' for name in ('MacOS/geist-cli', 'MacOS/geist-app', 'MacOS/geistd'))
            (content / 'Resources/RUNTIME-SHA256SUMS').write_text(manifest)
        # Ad-hoc code has no Team ID, so hardened library validation cannot
        # authenticate its bundled Sparkle. Distribution always uses both.
        run('codesign', '--force', '--sign', identity,
            '--preserve-metadata=entitlements', *([] if identity == '-' else ['--options','runtime','--timestamp']),
            *(['--keychain', keychain] if keychain else []), str(path))
    verify(app, distribution=identity != '-')


def verify(app, distribution=True):
    run('codesign', '--verify', '--deep', '--strict', str(app))
    for path in targets(app):
        details = run('codesign', '-dv', '--verbose=4', str(path), capture_output=True).stderr
        if distribution and not all(s in details for s in
                                     ('Authority=Developer ID Application:', 'Timestamp=', 'runtime')):
            raise ValueError(f'Distribution signature incomplete: {path.name}')
    content = app / 'Contents'
    run('shasum', '-a', '256', '-c', 'Resources/RUNTIME-SHA256SUMS', cwd=content)


def accepted(payload):
    return isinstance(payload, dict) and payload.get('status') == 'Accepted' and bool(payload.get('id'))


def notarize(artifact, profile, log_dir, keychain=None):
    log_dir.mkdir(parents=True, exist_ok=False)
    auth = ['--keychain-profile', profile] + (['--keychain', keychain] if keychain else [])
    submitted = subprocess.run(['xcrun', 'notarytool', 'submit', str(artifact), *auth, '--wait',
                    '--timeout', '30m', '--output-format', 'json'], capture_output=True, text=True)
    (log_dir / 'submission.json').write_text(submitted.stdout)
    (log_dir / 'submission-stderr.txt').write_text(submitted.stderr)
    try:
        payload = json.loads(submitted.stdout)
    except json.JSONDecodeError as exc:
        raise ValueError('Apple returned no valid submission JSON; inspect saved diagnostics') from exc
    if payload.get('id'):
        run('xcrun', 'notarytool', 'log', payload['id'], *auth, str(log_dir / 'apple-log.json'))
    if submitted.returncode or not accepted(payload):
        raise ValueError('Apple did not return Accepted; inspect saved submission and Apple log')


def main():
    p = argparse.ArgumentParser(description=__doc__)
    commands = p.add_subparsers(dest='command', required=True)
    s = commands.add_parser('sign')
    s.add_argument('--app', type=Path, required=True)
    s.add_argument('--identity', required=True)
    s.add_argument('--keychain')
    v = commands.add_parser('verify')
    v.add_argument('--app', type=Path, required=True)
    n = commands.add_parser('notarize')
    n.add_argument('--artifact', type=Path, required=True)
    n.add_argument('--profile', required=True)
    n.add_argument('--keychain')
    n.add_argument('--log-dir', type=Path, required=True)
    a = p.parse_args()
    if a.command == 'sign':
        sign(a.app.resolve(), a.identity, a.keychain)
    elif a.command == 'verify':
        verify(a.app.resolve())
    else:
        notarize(a.artifact.resolve(), a.profile, a.log_dir, a.keychain)


if __name__ == '__main__':
    main()
