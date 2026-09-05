#!/usr/bin/env python3
"""Prepare the pinned upstream onedir helper using macOS tools, or verify its build cache."""

import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import zipfile


def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()


def inventory(root):
    files, links = {}, {}
    for path in sorted(root.rglob("*")):
        name = path.relative_to(root).as_posix()
        if name == "manifest.json":
            continue
        if path.is_symlink():
            path.resolve(strict=True).relative_to(root.resolve())
            links[name] = os.readlink(path)
        elif path.is_file():
            files[name] = [digest(path), stat.S_IMODE(path.stat().st_mode)]
    return {"files": files, "links": links}


def manifest(root, artifact):
    return {"artifact": artifact, "recipe": digest(Path(__file__)), **inventory(root)}


def prepare(archive, root, artifact):
    if digest(archive) != artifact:
        raise ValueError("Downloader archive checksum mismatch")
    root.mkdir()  # Caller supplies a new private build directory.
    with zipfile.ZipFile(archive) as source:
        for entry in source.infolist():
            name = Path(entry.filename)
            mode = entry.external_attr >> 16
            if name.is_absolute() or ".." in name.parts or stat.S_ISLNK(mode):
                raise ValueError("Unexpected downloader archive path")
            source.extract(entry, root)
            if not entry.is_dir():
                (root / name).chmod(0o755 if mode & 0o111 else 0o644)
    (root / "yt-dlp_macos").rename(root / "yt-dlp")

    # The app requires arm64. lipo preserves the upstream PyInstaller bytecode archive;
    # only unused Intel machine code is removed. All code is signed during app assembly.
    for path in sorted(root.rglob("*")):
        if not path.is_file():
            continue
        with path.open("rb") as source:
            magic = source.read(4)
        if magic in (b"\xca\xfe\xba\xbe", b"\xca\xfe\xba\xbf"):
            temporary = path.with_name(path.name + ".arm64")
            subprocess.run(["lipo", str(path), "-thin", "arm64", "-output", str(temporary)], check=True)
            temporary.chmod(path.stat().st_mode)
            temporary.replace(path)

    # Upstream ZIP flattens Python.framework's normal aliases into four copies of Python.
    # Restore the standard framework layout only after checking the copies are identical.
    internal = root / "_internal"
    framework = internal / "Python.framework"
    version = framework / "Versions/3.14"
    python_digest = digest(version / "Python")
    for path in (internal / "Python", framework / "Python", framework / "Versions/Current/Python"):
        if digest(path) != python_digest:
            raise ValueError("Python framework aliases differ")
    for directory in (framework / "Resources", framework / "Versions/Current/Resources"):
        if inventory(directory) != inventory(version / "Resources"):
            raise ValueError("Python framework resources differ")
    for path, target in (
        (framework / "Versions/Current", "3.14"),
        (framework / "Resources", "Versions/Current/Resources"),
        (framework / "Python", "Versions/Current/Python"),
        (internal / "Python", "Python.framework/Python"),
    ):
        if path.is_dir():
            shutil.rmtree(path)
        else:
            path.unlink()
        path.symlink_to(target)

    (root / "manifest.json").write_text(json.dumps(manifest(root, artifact), sort_keys=True))


def main():
    mode, *args = sys.argv[1:]
    if mode == "prepare":
        archive, root, artifact = args
        prepare(Path(archive), Path(root), artifact)
    elif mode == "verify":
        root, artifact = args
        root = Path(root)
        if json.loads((root / "manifest.json").read_text()) != manifest(root, artifact):
            raise ValueError("Prepared downloader cache changed")
    elif mode == "fingerprint":
        root, = args
        payload = json.dumps(inventory(Path(root)), sort_keys=True, separators=(",", ":"))
        print(hashlib.sha256(payload.encode()).hexdigest())
    else:
        raise ValueError("Expected prepare, verify, or fingerprint")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, KeyError, subprocess.CalledProcessError) as error:
        print(f"Downloader preparation failed: {error}", file=sys.stderr)
        sys.exit(1)
