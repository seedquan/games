#!/usr/bin/env python3
"""Download checksum-pinned official Godot templates into ignored build storage."""
import hashlib
import json
from pathlib import Path
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parent
VERSION = "4.7.2"
ARCHIVE = f"Godot_v{VERSION}-stable_export_templates.tpz"
URL = f"https://github.com/godotengine/godot-builds/releases/download/{VERSION}-stable/{ARCHIVE}"
SHA256 = "f298490b8d44d934be425a5a65a51bf15f422428b229a06a6e11d9ffea248011"


def digest(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def main():
    directory = ROOT / "builds/templates"
    directory.mkdir(parents=True, exist_ok=True)
    (directory.parent / ".gdignore").touch()
    archive = directory / ARCHIVE
    if not archive.is_file():
        partial = archive.with_suffix(".tpz.part")
        print(f"Downloading official Godot {VERSION} templates (1.28 GB)", flush=True)
        with urllib.request.urlopen(URL, timeout=60) as response, partial.open("wb") as output:
            while chunk := response.read(1024 * 1024):
                output.write(chunk)
        if digest(partial) != SHA256:
            raise RuntimeError("Official template archive checksum mismatch; nothing extracted")
        partial.replace(archive)
    if digest(archive) != SHA256:
        raise RuntimeError("Cached template archive checksum mismatch; nothing extracted")
    files = {}
    with zipfile.ZipFile(archive) as package:
        version = package.read("templates/version.txt").decode().strip()
        if version != VERSION + ".stable":
            raise RuntimeError(f"Unexpected template version {version}")
        for name in ["windows_release_x86_64.exe", "windows_debug_x86_64.exe"]:
            target = directory / name
            target.write_bytes(package.read("templates/" + name))
            files[name] = digest(target)
    report = {"version": version, "url": URL, "archive_sha256": SHA256, "files": files}
    (directory / "windows-provenance.json").write_text(json.dumps(report, indent=2) + "\n")
    print("PASS official Windows x86_64 template checksums")


if __name__ == "__main__":
    main()
