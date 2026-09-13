#!/usr/bin/env python3
"""Build a portable Windows package with isolated native or Wine verification."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import zipfile

from verify import COMMAND, PROJECT as ROOT
from prepare_windows_templates import SHA256 as TEMPLATE_ARCHIVE_SHA256


def digest(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def run(command, timeout=180, cwd=ROOT):
    result = subprocess.run(command, cwd=cwd, text=True, encoding="utf-8", errors="replace",
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout)
    if result.returncode or "ERROR:" in result.stdout:
        raise RuntimeError(result.stdout[-12000:])
    return result.stdout


def inspect_executable(path, version):
    data = path.read_bytes()
    if len(data) < 1024 or data[:2] != b"MZ":
        raise RuntimeError("Windows executable is not a PE file")
    header = struct.unpack_from("<I", data, 0x3C)[0]
    if data[header:header + 4] != b"PE\0\0" or struct.unpack_from("<H", data, header + 4)[0] != 0x8664:
        raise RuntimeError("Windows executable is not x86_64")
    optional = header + 24
    if struct.unpack_from("<H", data, optional)[0] != 0x20B:
        raise RuntimeError("Windows executable lacks a PE32+ header")
    resource_rva = struct.unpack_from("<I", data, optional + 112 + 16)[0]
    sections = optional + struct.unpack_from("<H", data, header + 20)[0]
    resource_offset = None
    for index in range(struct.unpack_from("<H", data, header + 6)[0]):
        virtual_size, address, size, offset = struct.unpack_from("<IIII", data, sections + index * 40 + 8)
        if address <= resource_rva < address + max(virtual_size, size):
            resource_offset = offset + resource_rva - address
    if resource_offset is None:
        raise RuntimeError("Windows icon/version resource section is missing")
    named, numbered = struct.unpack_from("<HH", data, resource_offset + 12)
    types = {struct.unpack_from("<I", data, resource_offset + 16 + i * 8)[0] for i in range(named + numbered)}
    if not {3, 14, 16}.issubset(types):
        raise RuntimeError("Windows icon or version resources are missing")
    for expected in ["深渊协议", version + ".0"]:
        if expected.encode("utf-16le") not in data:
            raise RuntimeError("Windows product identity/version is missing: " + expected)
    return {"architecture": "x86_64", "format": "PE32+", "icon_and_version_resources": True}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--skip-checks", action="store_true", help="Only after a current successful verify.py run")
    parser.add_argument("--wine", type=Path, help="Wine executable for explicitly labeled compatibility testing")
    parser.add_argument("--wine-prefix", type=Path, help="Reuse an initialized, explicitly marked Wine test prefix")
    parser.add_argument("--structural-only", action="store_true", help="Package without Windows execution; report remains unverified")
    parser.add_argument("--rendered", action="store_true", help="Also verify the release in a rendered window")
    args = parser.parse_args()
    if args.structural_only and (args.rendered or args.wine):
        parser.error("--structural-only cannot be combined with runtime verification")
    if args.wine_prefix and not args.wine:
        parser.error("--wine-prefix requires --wine")
    if os.name != "nt" and not (args.wine or args.structural_only):
        parser.error("Cross-export requires --wine, or explicit --structural-only")
    shell = shutil.which("pwsh") or shutil.which("powershell")
    if not args.structural_only and not shell:
        raise RuntimeError("PowerShell is required for the Windows release verifier")
    provenance_path = ROOT / "builds/templates/windows-provenance.json"
    if not provenance_path.is_file():
        raise RuntimeError("Run python3 prepare_windows_templates.py first")
    provenance = json.loads(provenance_path.read_text(encoding="utf-8"))
    if provenance["archive_sha256"] != TEMPLATE_ARCHIVE_SHA256:
        raise RuntimeError("Windows template provenance does not match the pinned release")
    for name, expected in provenance["files"].items():
        if digest(provenance_path.parent / name) != expected:
            raise RuntimeError("Windows template was modified: " + name)
    engine = run(COMMAND + ["--version"]).strip()
    if not engine.startswith(provenance["version"] + "."):
        raise RuntimeError("Godot engine and Windows export template versions do not match")
    version = re.search(r'config/version="([0-9.]+)"', (ROOT / "project.godot").read_text(encoding="utf-8"))[1]
    if not args.skip_checks:
        print(run([sys.executable, str(ROOT / "verify.py")], timeout=420), end="", flush=True)
    notices = run(COMMAND + ["--audio-driver", "Dummy", "--headless", "--script", "res://tools/export_notices.gd"])
    if "ABYSS NOTICES: complete" not in notices:
        raise RuntimeError("Engine and font attribution generation did not finish")
    output = ROOT / "builds" / f"深渊协议-{version}-Windows-x64.zip"
    runtime_reports = []
    with tempfile.TemporaryDirectory(prefix="abyss-windows-export-") as temporary:
        # Exercise Unicode and spaces on a path outside the source directory.
        package = Path(temporary) / f"深渊协议 {version}"
        package.mkdir()
        executable = package / "AbyssProtocol.exe"
        log = run(COMMAND + ["--audio-driver", "Dummy", "--headless", "--export-release", "Windows Desktop", str(executable)])
        (ROOT / "builds/qa").mkdir(exist_ok=True)
        (ROOT / "builds/qa/windows-export.log").write_text(log, encoding="utf-8")
        if re.search(r"Storing File: res://(?:tests|tools|builds|docs)/", log):
            raise RuntimeError("Development files leaked into the Windows content pack")
        pe = inspect_executable(executable, version)
        content = executable.with_suffix(".pck")
        if not content.is_file() or content.read_bytes()[:4] != b"GDPC":
            raise RuntimeError("Windows content pack is missing or invalid")
        shutil.copyfile(ROOT / "tools/verify_windows.ps1", package / "Verify-Windows.ps1")
        shutil.copyfile(ROOT / "builds/ThirdPartyNotices.txt", package / "ThirdPartyNotices.txt")
        (package / "游玩说明.txt").write_text((ROOT / "docs/windows-player.txt").read_text(encoding="utf-8"), encoding="utf-8-sig")
        (package / "ANGLE-compatibility.cmd").write_bytes(b'@echo off\r\nstart "" "%~dp0AbyssProtocol.exe" --rendering-driver opengl3_angle\r\n')
        if not args.structural_only:
            modes = [False, True] if args.rendered else [False]
            for rendered in modes:
                # This applies only to the verifier process, never the user's saved policy.
                command = [shell, "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(package / "Verify-Windows.ps1"),
                           "-OutputDirectory", str(ROOT / "builds/qa")]
                if args.wine:
                    command += ["-WinePath", str(args.wine.resolve())]
                if args.wine_prefix:
                    command += ["-WinePrefix", str(args.wine_prefix.resolve())]
                if rendered:
                    command += ["-Rendered"]
                result = run(command, timeout=360, cwd=temporary)
                print(result, end="", flush=True)
                match = re.search(r"ABYSS WINDOWS REPORT: (.+)", result)
                if not match:
                    raise RuntimeError("Windows verifier did not produce a report")
                report_path = Path(match[1].strip())
                report = json.loads(report_path.read_text(encoding="utf-8-sig"))
                if report["executable_sha256"] != digest(executable) or report["content_sha256"] != digest(content):
                    raise RuntimeError("Windows verification report does not match the packaged files")
                runtime_reports.append({"path": str(report_path), **report})
        entries = {f.name: digest(f) for f in sorted(package.iterdir()) if f.is_file()}
        (package / "checksums.json").write_text(json.dumps(entries, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        partial = output.with_suffix(".zip.part")
        with zipfile.ZipFile(partial, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
            for path in sorted(package.iterdir()):
                archive.write(path, package.name + "/" + path.name)
        with zipfile.ZipFile(partial) as archive:
            if archive.testzip() is not None:
                raise RuntimeError("Windows archive integrity check failed")
        partial.replace(output)
    report = {"version": version, "engine": engine, "platform": "Windows 10/11 x86_64",
              "archive": output.name, "sha256": digest(output), "bytes": output.stat().st_size,
              "signing": "unsigned", "verification_skipped": args.skip_checks,
              "pe": pe, "template_provenance": provenance, "files": entries,
              "runtime_verification": runtime_reports or "not run; structural package only"}
    output.with_suffix(".json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    output.with_suffix(".sha256").write_text(f"{report['sha256']}  {output.name}\n", encoding="utf-8")
    print(f"Built {output}\nSHA-256 {report['sha256']}", flush=True)


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, ValueError, struct.error, subprocess.TimeoutExpired, zipfile.BadZipFile) as error:
        print(f"Windows export failed: {error}", file=sys.stderr)
        sys.exit(1)
