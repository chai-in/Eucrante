#!/usr/bin/env python3
"""Exercise the packaged helper against generated local media, without provider sessions."""

from collections import Counter
from functools import partial
import http.server
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading


def main():
    app, fixtures, check = map(lambda path: Path(path).resolve(), sys.argv[1:])
    tools = app / "Contents/Resources/Tools"
    with tempfile.TemporaryDirectory(prefix="eucrante-http-check-") as directory:
        root = Path(directory)
        for name in ("video.mp4", "audio.m4a"):
            shutil.copy2(fixtures / name, root / name)
        requests = Counter()
        lock = threading.Lock()

        class Handler(http.server.SimpleHTTPRequestHandler):
            def do_GET(self):
                with lock:
                    requests[self.path] += 1
                super().do_GET()

            def log_message(self, *args):
                pass

        server = http.server.ThreadingHTTPServer(
            ("127.0.0.1", 0), partial(Handler, directory=str(root)))
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            base = f"http://127.0.0.1:{server.server_port}"
            info = {
                "id": "fixture", "title": "Local fixture", "extractor": "generic",
                "extractor_key": "Generic", "webpage_url": "https://example.test/fixture",
                "duration": 8,
                "formats": [
                    {"format_id": "video", "url": base + "/video.mp4", "ext": "mp4",
                     "vcodec": "avc1", "acodec": "none", "height": 1080, "width": 1920,
                     "filesize": (root / "video.mp4").stat().st_size},
                    {"format_id": "audio", "url": base + "/audio.m4a", "ext": "m4a",
                     "vcodec": "none", "acodec": "mp4a.40.2", "abr": 128,
                     "filesize": (root / "audio.m4a").stat().st_size},
                ],
            }
            (root / "info.json").write_text(json.dumps(info))
            wrapper = root / "fixture-helper"
            wrapper.write_text(
                f"#!{sys.executable}\nimport os, sys\n"
                f"with open({str(root / 'launches')!r}, 'a') as log: log.write('launch\\n')\n"
                f"tool = {str(tools / 'downloader/yt-dlp')!r}\n"
                f"os.execv(tool, [tool, '--load-info-json', {str(root / 'info.json')!r}] + sys.argv[1:-1])\n")
            wrapper.chmod(0o700)
            subprocess.run(
                [str(check), str(wrapper), str(tools / "deno"), str(tools / "ffmpeg"), str(root)],
                check=True, timeout=60)
            assert (root / "launches").read_text().splitlines() == ["launch", "launch"]
            assert requests == {"/video.mp4": 1, "/audio.m4a": 1}, requests
            assert not list(root.rglob("_MEI*")), "Unexpected runtime extraction"
            print("Exactly two launches, one GET per track, and no extracted runtime.")
        finally:
            server.shutdown()
            server.server_close()
            thread.join()


if __name__ == "__main__":
    main()
