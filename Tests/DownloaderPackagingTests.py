import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile


SCRIPT = Path(__file__).resolve().parents[1] / "Scripts/prepare-downloader.py"
spec = importlib.util.spec_from_file_location("prepare_downloader", SCRIPT)
packaging = importlib.util.module_from_spec(spec)
spec.loader.exec_module(packaging)


class DownloaderPackagingTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="eucrante-packaging-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    def test_cache_rejects_changed_bytes_permissions_and_unexpected_files(self):
        payload = self.root / "payload"
        payload.mkdir()
        executable = payload / "yt-dlp"
        executable.write_bytes(b"fixture")
        executable.chmod(0o755)
        (payload / "manifest.json").write_text(json.dumps(packaging.manifest(payload, "pin")))
        command = [sys.executable, str(SCRIPT), "verify", str(payload), "pin"]
        subprocess.run(command, check=True)
        for mutation in ("bytes", "permissions", "extra"):
            executable.write_bytes(b"fixture")
            executable.chmod(0o755)
            if mutation == "bytes":
                executable.write_bytes(b"changed")
            elif mutation == "permissions":
                executable.chmod(0o644)
            else:
                (payload / "unexpected").write_bytes(b"extra")
            result = subprocess.run(command, capture_output=True)
            self.assertNotEqual(result.returncode, 0, mutation)

    def test_payload_fingerprint_survives_relocation_and_rejects_external_links(self):
        payload = self.root / "payload"
        payload.mkdir()
        (payload / "Python").write_bytes(b"native runtime")
        (payload / "alias").symlink_to("Python")
        copy = self.root / "relocated"
        shutil.copytree(payload, copy, symlinks=True)
        self.assertEqual(packaging.inventory(payload), packaging.inventory(copy))
        (payload / "alias").unlink()
        (payload / "alias").symlink_to(copy / "Python")
        with self.assertRaises(ValueError):
            packaging.inventory(payload)

    def test_bad_archive_hash_and_traversal_never_install_payload(self):
        archive = self.root / "upstream.zip"
        with zipfile.ZipFile(archive, "w") as output:
            output.writestr("../escape", "untrusted")
        destination = self.root / "prepared"
        with self.assertRaises(ValueError):
            packaging.prepare(archive, destination, "wrong hash")
        self.assertFalse(destination.exists())
        with self.assertRaises(ValueError):
            packaging.prepare(archive, destination, packaging.digest(archive))
        self.assertFalse((self.root / "escape").exists())


if __name__ == "__main__":
    unittest.main()
