#!/usr/bin/env python3
"""Prepare a notarytool profile only on an explicitly configured ephemeral GitHub runner."""
import os,subprocess,tempfile
from pathlib import Path
if os.environ.get('GITHUB_ACTIONS')!='true': raise SystemExit('This helper is for ephemeral GitHub Actions runners only.')
required=['APPLE_NOTARY_KEY_ID','APPLE_NOTARY_ISSUER_ID','APPLE_NOTARY_PRIVATE_KEY']
if any(not os.environ.get(k) for k in required): raise SystemExit('The Apple notarization secrets are not configured.')
with tempfile.TemporaryDirectory(prefix='harbor-notary-',dir=os.environ['RUNNER_TEMP']) as tmp:
    p=Path(tmp)/'AuthKey.p8';p.write_text(os.environ['APPLE_NOTARY_PRIVATE_KEY']);p.chmod(0o600)
    subprocess.run(['xcrun','notarytool','store-credentials','HarborCI','--key',str(p),'--key-id',os.environ['APPLE_NOTARY_KEY_ID'],'--issuer',os.environ['APPLE_NOTARY_ISSUER_ID']],check=True)
