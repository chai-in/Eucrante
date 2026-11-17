#!/usr/bin/env python3
"""Build and prepare Harbor release assets. Publication is a separate, explicit draft operation."""
import argparse, base64, hashlib, http.client, json, os, plistlib, re, shutil, subprocess, sys, tempfile, urllib.error, urllib.parse, urllib.request
from pathlib import Path
from embed import verify_sdk

INTEGRATION = Path(__file__).resolve().parent
ROOT = INTEGRATION.parent
CONFIG = json.loads((INTEGRATION / 'app.json').read_text())
MAX_ARCHIVE = 4 * 1024**3

def run(args, *, cwd=ROOT, capture=False, env=None):
    return subprocess.run([str(a) for a in args], cwd=cwd, env=env, check=True, text=True,
                          stdout=subprocess.PIPE if capture else None).stdout

def digest(path):
    h=hashlib.sha256()
    with Path(path).open('rb') as f:
        for b in iter(lambda:f.read(1024*1024),b''): h.update(b)
    return h.hexdigest()

def git(*args): return run(['git', *args], capture=True).strip()

def repo_name(value=None):
    remote=git('remote','get-url','origin')
    match=re.fullmatch(r'(?:https://github\.com/|git@github\.com:)([\w.-]+/[\w.-]+?)(?:\.git)?',remote)
    if not match: raise ValueError('Configure a real GitHub origin before preparing a release.')
    actual=match.group(1)
    requested=value or os.environ.get('GITHUB_REPOSITORY') or actual
    if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+',requested) or requested.lower()!=actual.lower():
        raise ValueError('The release repository must match this checkout\'s GitHub origin.')
    return actual


def check_tag(tag, repository=None):
    if not re.fullmatch(r'v[0-9]+(?:\.[0-9]+){0,3}',tag): raise ValueError('Release tag must be v followed by a numeric app version.')
    if git('status','--porcelain'): raise ValueError('Release preparation requires a clean committed working tree, including the Harbor integration.')
    commit=git('rev-parse','HEAD')
    if git('rev-parse',tag+'^{commit}') != commit: raise ValueError('The release tag must point to the checked-out commit.')
    repository=repo_name(repository)
    env=os.environ.copy()
    token=env.get('GH_TOKEN') or env.get('GITHUB_TOKEN')
    if token:
        n=int(env.get('GIT_CONFIG_COUNT','0'))
        env['GIT_CONFIG_COUNT']=str(n+1)
        env['GIT_CONFIG_KEY_'+str(n)]='http.https://github.com/.extraheader'
        env['GIT_CONFIG_VALUE_'+str(n)]='AUTHORIZATION: basic '+base64.b64encode(('x-access-token:'+token).encode()).decode()
    remote=run(['git','ls-remote','--tags','origin','refs/tags/'+tag,'refs/tags/'+tag+'^{}'],capture=True,env=env).strip()
    refs=dict(line.split()[::-1] for line in remote.splitlines() if line.strip())
    if refs.get('refs/tags/'+tag+'^{}',refs.get('refs/tags/'+tag)) != commit:
        raise ValueError('The pushed tag does not resolve to this commit.')
    return repository,commit

def tool():
    verify_sdk()
    sdk=INTEGRATION/'SDK'
    run(['swift','build','--package-path',sdk,'--arch','arm64','-c','release','--product','harbor-release'])
    directory=run(['swift','build','--package-path',sdk,'--arch','arm64','-c','release','--show-bin-path'],capture=True).strip()
    return Path(directory)/'harbor-release'

def build(channel):
    verify_sdk()
    env=os.environ.copy()
    identity=env.get('HARBOR_CODESIGN_IDENTITY','-')
    if channel=='verified' and identity=='-': raise ValueError('Verified releases require HARBOR_CODESIGN_IDENTITY and an existing notarization profile.')
    env[CONFIG['signingEnvironment']]=identity
    run(CONFIG['buildCommand'],env=env)
    app=ROOT/CONFIG['appPath']
    if not app.is_dir(): raise ValueError('Build did not produce '+str(app))
    if channel=='verified':
        profile=env.get('HARBOR_NOTARY_PROFILE')
        if not profile: raise ValueError('Set HARBOR_NOTARY_PROFILE to an existing notarytool Keychain profile.')
        with tempfile.TemporaryDirectory(prefix='harbor-notary-') as tmp:
            archive=Path(tmp)/'app.zip'
            run(['/usr/bin/ditto','-c','-k','--keepParent',app,archive])
            run(['xcrun','notarytool','submit',archive,'--keychain-profile',profile,'--wait'])
        run(['xcrun','stapler','staple',app]);run(['xcrun','stapler','validate',app])
    return app

def prepare(args):
    repository,commit=check_tag(args.tag,args.repository)
    if json.loads((INTEGRATION/'sdk-lock.json').read_text()).get('sourceDirty') is not False: raise ValueError('Resync the SDK from a committed Harbor source before releasing.')
    cli=tool()
    app=Path(args.app_bundle).resolve() if args.app_bundle else build(args.channel)
    info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
    if info['CFBundleIdentifier']!=CONFIG['bundleIdentifier']: raise ValueError('Preview/debug bundle IDs cannot replace production apps.')
    version=info['CFBundleShortVersionString']; build_number=info['CFBundleVersion']
    if args.tag!='v'+version: raise ValueError('Tag and app version differ.')
    manifest=json.loads((app/'Contents/Resources/HarborIntegration.json').read_text())
    if manifest.get('sourceRevision')!=commit or manifest.get('sourceDirty') is not False:
        raise ValueError('Rebuild the app from this clean tag; its embedded source provenance does not match.')
    if manifest.get('appVersion')!=version or manifest.get('appBuild')!=build_number: raise ValueError('Embedded integration version differs from Info.plist.')
    run([cli,'check-integration',CONFIG['appID'],app])
    output=Path(args.output or INTEGRATION/'output'/args.tag).resolve()
    output.mkdir(parents=True,exist_ok=True)
    if any(output.iterdir()): raise ValueError('Release output must be empty; existing artifacts are never overwritten.')
    filename=f"{CONFIG['appID']}-{version}-{build_number}-arm64"+('-unnotarized' if args.channel=='preview' else '')+'.zip'
    base=f'https://github.com/{repository}/releases/download/{urllib.parse.quote(args.tag,safe="")}/'
    run([cli,'package',CONFIG['appID'],app,output,base+urllib.parse.quote(filename),args.channel])
    record=output/(filename+'.release.json')
    record.rename(output/'release.json')
    if CONFIG.get('correspondingSource'):
        source=ROOT/CONFIG['correspondingSource'].format(version=version)
        if not source.is_file(): raise ValueError('The corresponding-source archive is required for this app.')
        shutil.copy2(source,output/source.name)
    assets=[{'name':p.name,'bytes':p.stat().st_size,'sha256':digest(p)} for p in sorted(output.iterdir()) if p.is_file()]
    provenance={'schema':1,'repository':repository,'tag':args.tag,'commit':commit,'appID':CONFIG['appID'],
                'channel':args.channel,'architecture':'arm64','sdkSnapshot':json.loads((INTEGRATION/'sdk-lock.json').read_text())['snapshotDigest'],'assets':assets}
    (output/'provenance.json').write_text(json.dumps(provenance,indent=2,sort_keys=True)+'\n')
    (output/'SHA256SUMS').write_text(''.join(digest(p)+'  '+p.name+'\n' for p in sorted(output.iterdir()) if p.is_file()))
    print('Prepared release assets in '+str(output)+'. No release was created or published.')

def request(method,url,data=None,content_type='application/json'):
    token=os.environ.get('GH_TOKEN') or os.environ.get('GITHUB_TOKEN')
    if not token: raise ValueError('Set GH_TOKEN or GITHUB_TOKEN for the explicit draft operation.')
    headers={'Authorization':'Bearer '+token,'Accept':'application/vnd.github+json','X-GitHub-Api-Version':'2022-11-28','Content-Type':content_type}
    req=urllib.request.Request(url,data=data,headers=headers,method=method)
    # API requests never follow a redirect with the authorization header.
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self,*args,**kwargs): return None
    with urllib.request.build_opener(NoRedirect()).open(req,timeout=120) as r:
        return json.loads(r.read())


def upload_asset(repository,rid,file):
    size=file.stat().st_size
    if size>MAX_ARCHIVE: raise ValueError('Asset exceeds the supported size.')
    token=os.environ.get('GH_TOKEN') or os.environ.get('GITHUB_TOKEN')
    if not token: raise ValueError('GitHub token is missing.')
    connection=http.client.HTTPSConnection('uploads.github.com',timeout=120)
    try:
        path=f'/repos/{repository}/releases/{rid}/assets?name='+urllib.parse.quote(file.name)
        connection.putrequest('POST',path)
        connection.putheader('Authorization','Bearer '+token)
        connection.putheader('Accept','application/vnd.github+json')
        connection.putheader('Content-Type','application/octet-stream')
        connection.putheader('Content-Length',str(size));connection.endheaders()
        with file.open('rb') as stream:
            for block in iter(lambda:stream.read(1024*1024),b''): connection.send(block)
        response=connection.getresponse();body=response.read(1048576)
        if response.status!=201: raise ValueError('GitHub asset upload failed with status '+str(response.status))
        result=json.loads(body)
        if result.get('size')!=size or result.get('name')!=file.name: raise ValueError('Uploaded asset readback differs.')
    finally: connection.close()

def draft(args):
    output=Path(args.output).resolve()
    p=json.loads((output/'provenance.json').read_text())
    repository,commit=check_tag(p['tag'],args.repository or p['repository'])
    if repository!=p['repository'] or commit!=p['commit'] or p['appID']!=CONFIG['appID']: raise ValueError('Release provenance no longer matches this checkout.')
    expected={a['name'] for a in p['assets']} | {'provenance.json','SHA256SUMS'}
    if {f.name for f in output.iterdir()}!=expected: raise ValueError('Unexpected files in the release output; refusing to upload them.')
    for asset in p['assets']:
        if Path(asset['name']).name!=asset['name']: raise ValueError('Unsafe asset filename.')
        file=output/asset['name']
        if not file.is_file() or file.is_symlink() or file.stat().st_size!=asset['bytes'] or digest(file)!=asset['sha256']:
            raise ValueError('Release asset changed after preparation: '+asset['name'])
    record=json.loads((output/'release.json').read_text())
    expected_channel=p['channel']
    if record['channel']!=expected_channel or record['appID']!=CONFIG['appID']: raise ValueError('Release record disagrees with provenance.')
    api=f'https://api.github.com/repos/{repository}'
    try:
        request('GET',api+'/releases/tags/'+urllib.parse.quote(p['tag'],safe=''))
        raise ValueError('A release already exists for this tag. Existing releases are never overwritten.')
    except urllib.error.HTTPError as error:
        if error.code!=404: raise
    notes=Path(args.notes).read_text() if args.notes else f"{CONFIG['name']} {p['tag']} for Apple silicon.\n"
    if expected_channel=='preview': notes='Unnotarized preview. Open normally first; if blocked, use System Settings → Privacy & Security → Open Anyway. Harbor preserves quarantine.\n\n'+notes
    notes+='\n\nThe Harbor release record is not publisher authentication on its own; the publisher must include it in an authenticated Harbor catalog.'
    release=request('POST',api+'/releases',json.dumps({'tag_name':p['tag'],'target_commitish':commit,'name':CONFIG['name']+' '+p['tag'],'body':notes,'draft':True,'prerelease':expected_channel=='preview'}).encode())
    rid=release['id']
    print('Created draft '+release['html_url']+'; uploading checked assets.')
    try:
        for file in sorted(output.iterdir()):
            if not file.is_file() or file.is_symlink(): raise ValueError('Unexpected release output entry.')
            upload_asset(repository,rid,file)
        readback=request('GET',api+'/releases/'+str(rid))
        if readback.get('draft') is not True: raise ValueError('GitHub did not preserve draft status.')
        actual={a['name']:a['size'] for a in readback['assets']}
        if actual!={p.name:p.stat().st_size for p in output.iterdir() if p.is_file()}: raise ValueError('Draft asset readback did not match the prepared output.')
        print('Draft and all asset sizes verified. Review on GitHub; nothing was published.')
    except Exception:
        print('Draft retained for recovery at '+release['html_url']+'. No release was published.',file=sys.stderr)
        raise

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    subs=parser.add_subparsers(dest='command',required=True)
    check=subs.add_parser('check');check.add_argument('--tag',required=True);check.add_argument('--repository')
    prepare_parser=subs.add_parser('prepare');prepare_parser.add_argument('--tag',required=True);prepare_parser.add_argument('--repository')
    prepare_parser.add_argument('--channel',choices=['preview','verified'],default='preview');prepare_parser.add_argument('--app-bundle');prepare_parser.add_argument('--output')
    draft_parser=subs.add_parser('draft');draft_parser.add_argument('--output',required=True);draft_parser.add_argument('--repository');draft_parser.add_argument('--notes')
    args=parser.parse_args()
    try:
        if args.command=='check': verify_sdk(); repo,commit=check_tag(args.tag,args.repository); print('Release source verified: '+repo+' '+commit)
        elif args.command=='prepare': prepare(args)
        else: draft(args)
    except Exception as error: parser.exit(1,'Harbor release: '+str(error)+'\n')
