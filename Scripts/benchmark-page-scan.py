#!/usr/bin/env python3
"""Reproduce the pre-optimization two-worker full-extraction baseline, without cookies."""
import argparse
import concurrent.futures
import json
from pathlib import Path
import subprocess
import tempfile
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--input', type=Path, default=Path('Docs/Benchmarks/page-scan-urls.txt'))
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
yt = root / '.build/eucrante-tools/yt-dlp'
deno = root / '.build/eucrante-tools/deno'
urls = args.input.read_text().splitlines()
# Both paths do full extraction including all formats. This baseline emits only
# the metadata fields needed to compare availability; no signed URLs are emitted.
template = ('{"metadata":%(.{id,title,duration})j,'
            '"formats":%(formats.:.{format_id,ext,vcodec,acodec,width,height,fps,tbr,abr,filesize,filesize_approx})j}')

def inspect(url):
    with tempfile.TemporaryDirectory(prefix='eucrante-benchmark-') as folder:
        environment = {'HOME': folder, 'XDG_CACHE_HOME': folder,
                       'PATH': '/usr/bin:/bin:/usr/sbin:/sbin', 'LANG': 'en_US.UTF-8'}
        started = time.monotonic()
        result = subprocess.run([str(yt), '--ignore-config', '--no-playlist', '--no-warnings',
                                 '--skip-download', '--ignore-errors', '--print', template,
                                 '--js-runtimes', 'deno:' + str(deno), url],
                                env=environment, capture_output=True, text=True, timeout=180)
        documents = []
        for line in result.stdout.splitlines():
            try:
                documents.append(json.loads(line))
            except ValueError:
                pass
        return {'url': url, 'seconds': time.monotonic() - started,
                'verified': any(entry.get('formats') for entry in documents),
                'formatCounts': [len(entry.get('formats', [])) for entry in documents]}

started = time.monotonic()
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
    results = list(pool.map(inspect, urls))
report = {'seconds': time.monotonic() - started, 'items': len(urls), 'results': results}
args.output.write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps({'seconds': report['seconds'], 'items': len(urls),
                  'verified': sum(entry['verified'] for entry in results)}))
