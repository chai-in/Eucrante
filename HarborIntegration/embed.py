#!/usr/bin/env python3
"""Embed a truthful app-owned Harbor manifest before code signing."""
import argparse, hashlib, json, os, plistlib, subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent

def verify_sdk():
    lock = json.loads((ROOT / 'sdk-lock.json').read_text())
    sdk = ROOT / 'SDK'
    actual = {str(p.relative_to(sdk)) for p in sdk.rglob('*') if p.is_file() and not any(part in ('.build', '.swiftpm', '.git', '__pycache__') for part in p.relative_to(sdk).parts)}
    if actual != set(lock['files']): raise ValueError('Harbor SDK file set changed. Resync the reviewed SDK snapshot before building.')
    for name, digest in lock['files'].items():
        p = sdk / name
        if p.is_symlink() or hashlib.sha256(p.read_bytes()).hexdigest() != digest:
            raise ValueError('Harbor SDK snapshot changed: ' + name)

def embed(app):
    verify_sdk()
    config = json.loads((ROOT / 'app.json').read_text())
    app = Path(app).resolve()
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    allowed = [config['bundleIdentifier']] + config.get('previewBundleIdentifiers', [])
    if info.get('CFBundleIdentifier') not in allowed: raise ValueError('App identity does not match this Harbor integration.')
    manifest = json.loads((ROOT / 'manifest.json').read_text())
    manifest['bundleIdentifier'] = info['CFBundleIdentifier']
    manifest['minimumOS'] = info['LSMinimumSystemVersion']
    manifest['appVersion'] = info['CFBundleShortVersionString']
    manifest['appBuild'] = info['CFBundleVersion']
    repo = ROOT.parent
    revision = subprocess.run(['git', 'rev-parse', 'HEAD'], cwd=repo, capture_output=True, text=True)
    status = subprocess.run(['git', 'status', '--porcelain'], cwd=repo, capture_output=True, text=True)
    manifest['sourceRevision'] = revision.stdout.strip() if revision.returncode == 0 else None
    manifest['sourceDirty'] = bool(status.stdout.strip()) if status.returncode == 0 else None
    resource = app / 'Contents/Resources/HarborIntegration.json'
    resource.parent.mkdir(parents=True, exist_ok=True)
    resource.write_text(json.dumps(manifest, indent=2, sort_keys=True) + '\n')
    print('Embedded Harbor integration for ' + config['name'])

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', nargs='?')
    parser.add_argument('--verify-sdk', action='store_true')
    args = parser.parse_args()
    try:
        if args.verify_sdk: verify_sdk(); print('Harbor SDK snapshot verified.')
        elif args.app: embed(args.app)
        else: parser.error('Pass an app bundle or --verify-sdk.')
    except Exception as error: parser.exit(1, 'Harbor integration: ' + str(error) + '\n')
