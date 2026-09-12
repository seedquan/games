#!/usr/bin/env python3
"""Generate a Windows acceptance handoff from an explicit local export report.

Example: python3 tools/prepare_windows_acceptance.py --report builds/深渊协议-0.11.0-Windows-x64.json
The sibling ZIP is verified before any output is created. Existing handoffs are
never overwritten; --output may select a fresh directory for another revision.
"""
import argparse
import hashlib
import json
from pathlib import Path, PureWindowsPath
import re
import stat
import sys
import tempfile
import zipfile


ROOT = Path(__file__).resolve().parents[1]
TOKENS = {
    "AbyssProtocol.exe": "__ABYSS_EXE_SHA256__",
    "AbyssProtocol.pck": "__ABYSS_PCK_SHA256__",
    "Verify-Windows.ps1": "__ABYSS_VERIFIER_SHA256__",
}
VERSION_TOKEN = "__ABYSS_VERSION__"


def digest(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def sha256(value, field):
    if not isinstance(value, str) or not re.fullmatch(r"[0-9a-fA-F]{64}", value):
        raise ValueError(f"Missing or invalid SHA-256: {field}")
    return value.lower()


def basename(value):
    return (isinstance(value, str) and bool(value) and value not in (".", "..")
            and not re.search(r'[\\/:<>"|?*\x00-\x1f]', value))


def verify_build(report_path, archive_path=None):
    report = json.loads(report_path.read_text(encoding="utf-8-sig"))
    if not isinstance(report, dict):
        raise ValueError("Build report must be a JSON object")
    version = report.get("version")
    if not isinstance(version, str) or not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
        raise ValueError("Missing or invalid build version")
    archive_name = f"深渊协议-{version}-Windows-x64.zip"
    if report.get("archive") != archive_name or report.get("platform") != "Windows 10/11 x86_64":
        raise ValueError("Build report archive/platform does not identify this Windows version")
    expected_zip = sha256(report.get("sha256"), "archive")
    size = report.get("bytes")
    if type(size) is not int or size <= 0:
        raise ValueError("Missing or invalid archive byte count")
    files = report.get("files")
    if not isinstance(files, dict) or not all(name in files for name in TOKENS):
        raise ValueError("Build report must include all three critical release file hashes")
    if not all(basename(name) for name in files) or "checksums.json" in files:
        raise ValueError("Build report contains invalid package filenames")
    files = {name: sha256(value, name) for name, value in files.items()}
    archive_path = Path(archive_path) if archive_path is not None else report_path.parent / archive_name
    if archive_path.name != archive_name:
        raise ValueError("Archive filename does not match the build report")
    if archive_path.stat().st_size != size or digest(archive_path) != expected_zip:
        raise ValueError("Archive SHA-256 or byte count does not match the build report")
    package = f"深渊协议 {version}/"
    with zipfile.ZipFile(archive_path) as archive:
        entries = archive.infolist()
        expected_names = {package + name for name in files} | {package + "checksums.json"}
        if len(entries) != len(expected_names) or {item.filename for item in entries} != expected_names:
            raise ValueError("ZIP file list does not exactly match the versioned build report")
        if any(item.is_dir() or stat.S_ISLNK(item.external_attr >> 16) for item in entries):
            raise ValueError("ZIP must contain regular package files, never directory or symlink entries")
        embedded = json.loads(archive.read(package + "checksums.json").decode("utf-8-sig"))
        if embedded != files:
            raise ValueError("Embedded package checksums do not match the build report")
        for name, expected in files.items():
            with archive.open(package + name) as source:
                actual = hashlib.file_digest(source, "sha256").hexdigest()
            if actual != expected:
                raise ValueError("ZIP member SHA-256 does not match the build report: " + name)
    return version, expected_zip, files


def windows_text(value):
    return value.replace("\r\n", "\n").replace("\r", "\n").replace("\n", "\r\n").encode("utf-8-sig")


def generate(report_path, archive_path=None, output=None, destination_root=""):
    if destination_root and (not PureWindowsPath(destination_root).is_absolute()
                             or re.search(r"[\x00-\x1f]", destination_root)):
        raise ValueError("Report destination must be an absolute Windows directory")
    report_path = Path(report_path)
    version, archive_hash, files = verify_build(report_path, archive_path)
    template = (ROOT / "tools/run_windows_acceptance.ps1").read_text(encoding="utf-8-sig")
    replacements = {VERSION_TOKEN: version,
                    "__ABYSS_REPORT_ROOT__": destination_root.replace("'", "''"),
                    **{token: files[name] for name, token in TOKENS.items()}}
    for token, value in replacements.items():
        if template.count(token) != 1:
            raise ValueError("Acceptance template must contain exactly one " + token)
        template = template.replace(token, value)
    template = template.replace(
        "# Source template only. Generate a version-bound handoff with prepare_windows_acceptance.py.",
        "# Generated from the SHA-256-verified Windows export. Do not edit version or hashes.",
    )
    instructions = (ROOT / "docs/windows-acceptance.txt").read_text(encoding="utf-8-sig")
    if VERSION_TOKEN not in instructions:
        raise ValueError("Acceptance instructions are missing their version placeholder")
    instructions = instructions.replace(VERSION_TOKEN, version)
    instructions = instructions.replace("__ABYSS_REPORT_LOCATION__", destination_root or "验收入口所在目录")
    if "__ABYSS_" in template or "__ABYSS_" in instructions:
        raise ValueError("An acceptance template placeholder was not resolved")
    outputs = {
        "Run-Windows-Acceptance.ps1": windows_text(template),
        "一键Windows验收.cmd": (ROOT / "tools/run_windows_acceptance.cmd").read_bytes(),
        "仅回传验收报告.cmd": (ROOT / "tools/recover_windows_acceptance.cmd").read_bytes(),
        "Windows验收说明.txt": windows_text(instructions),
    }
    manifest = {
        "schema": 1, "version": version, "tool_revision": 5,
        "report_destination": destination_root or "script directory",
        "archive_sha256": archive_hash,
        "release_files": {name: files[name] for name in TOKENS},
        "files": {name: hashlib.sha256(data).hexdigest() for name, data in outputs.items()},
        "scope": "Prepared acceptance tools only; preparation does not execute or certify Windows gameplay.",
    }
    outputs["acceptance-manifest.json"] = (json.dumps(manifest, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    destination = Path(output) if output is not None else ROOT / "builds" / ("acceptance-" + version)
    if destination.exists() or destination.is_symlink():
        raise FileExistsError("Existing acceptance directory is preserved; select a fresh --output: " + str(destination))
    destination.parent.mkdir(parents=True, exist_ok=True)
    # Validate and render first, then publish the complete new directory together.
    with tempfile.TemporaryDirectory(prefix=".abyss-acceptance-", dir=destination.parent) as temporary:
        staged = Path(temporary) / "handoff"
        staged.mkdir()
        for name, data in outputs.items():
            (staged / name).write_bytes(data)
        staged.rename(destination)
    return destination


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, required=True, help="Explicit JSON build report from export_windows.py")
    parser.add_argument("--archive", type=Path, help="Matching ZIP; defaults to the report's sibling archive")
    parser.add_argument("--output", type=Path, help="Fresh handoff directory; defaults to builds/acceptance-<version>")
    parser.add_argument("--destination-root", default="", help="Existing Windows directory receiving report ZIPs directly; defaults to the script directory")
    args = parser.parse_args()
    print("Prepared verified acceptance handoff: " + str(generate(args.report, args.archive, args.output, args.destination_root)))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError, zipfile.BadZipFile) as error:
        print("Acceptance preparation failed: " + str(error), file=sys.stderr)
        sys.exit(1)
