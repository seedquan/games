#!/usr/bin/env python3
"""Reproducible local macOS release; no upload, credentials or notarization."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parent


def run(command, timeout=180, cwd=ROOT):
    result = subprocess.run(command, cwd=cwd, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=timeout, check=False)
    if result.returncode or "ERROR:" in result.stdout:
        raise RuntimeError(result.stdout[-12000:])
    return result.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--skip-checks", action="store_true", help="Use only after a current successful verify.py run")
    parser.add_argument("--rendered", action="store_true", help="Verify the packaged game in silent native windows")
    args = parser.parse_args()
    runtime_options = ["--audio-driver", "Dummy"] + ([] if args.rendered else ["--headless"])
    template = ROOT / "builds/templates/macos.zip"
    if not template.is_file():
        raise RuntimeError("Extract templates/macos.zip and templates/version.txt from the official matching Godot export_templates.tpz into builds/templates/ first.")
    version = run([str(ROOT / "godot.sh"), "--version"]).strip()
    template_version = (template.parent / "version.txt").read_text().strip()
    if not version.startswith(template_version):
        raise RuntimeError(f"Engine {version} does not match template {template_version}")
    (ROOT / "builds/.gdignore").touch()
    if not args.skip_checks:
        print(run([sys.executable, str(ROOT / "verify.py")], timeout=420), end="")
    notices = run([str(ROOT / "godot.sh"), "--audio-driver", "Dummy", "--headless", "--script", "res://tools/export_notices.gd"])
    if "ABYSS NOTICES: complete" not in notices:
        raise RuntimeError("Engine and font attribution generation did not finish")
    version_match = re.search(r'application/short_version="([0-9.]+)"', (ROOT / "export_presets.cfg").read_text())
    app_version = version_match.group(1)
    output = ROOT / "builds" / f"深渊协议-{app_version}-macOS.zip"
    run([str(ROOT / "godot.sh"), "--audio-driver", "Dummy", "--headless", "--export-release", "macOS", str(output)])
    # Keep attributions beside the signed app without modifying its sealed bundle.
    with zipfile.ZipFile(output, "a", zipfile.ZIP_DEFLATED) as archive:
        archive.write(ROOT / "builds/ThirdPartyNotices.txt", "ThirdPartyNotices.txt")
    print("PASS Godot macOS export")
    # Validate archive contents before presenting the artifact as a release.
    with zipfile.ZipFile(output) as archive:
        names = archive.namelist()
        if not any(name.endswith(".pck") for name in names) or not any("Contents/MacOS/" in name for name in names):
            raise RuntimeError("Export is missing its executable or content pack")
        if any("/tests/" in name or "export_credentials" in name for name in names):
            raise RuntimeError("Development-only content leaked into the archive")
        if archive.testzip() is not None:
            raise RuntimeError("Export archive failed its CRC integrity check")
    with tempfile.TemporaryDirectory(prefix="abyss-release-") as temp:
        run(["ditto", "-x", "-k", str(output), temp])
        applications = list(Path(temp).glob("*.app"))
        if len(applications) != 1:
            raise RuntimeError("Expected exactly one application bundle")
        app = applications[0]
        run(["codesign", "--verify", "--deep", "--strict", str(app)])
        executables = list((app / "Contents/MacOS").iterdir())
        if len(executables) != 1:
            raise RuntimeError("Expected exactly one native executable")
        # Run outside the project so missing packed resources cannot fall back to source.
        log = run([str(executables[0])] + runtime_options + ["--", "--verify-release"], cwd=temp, timeout=60)
        summary = re.search(r"ABYSS RELEASE: \d+ checks, 0 failures", log)
        if not summary:
            raise RuntimeError("Release runtime did not complete verification\n" + log)
        print(summary.group(0))
        print("PASS standalone macOS campaign and bundle signature")
        fixture = Path(temp) / "save-fixture"
        fixture.mkdir()
        (fixture / ".abyss-release-fixture").write_text("Disposable release verification data\n")
        for stage in ("write", "read"):
            log = run([str(executables[0])] + runtime_options + ["--", "--verify-release",
                       f"--verify-storage={fixture}", f"--verify-stage={stage}"], cwd=temp, timeout=60)
            summary = re.search(rf"ABYSS STORAGE {stage.upper()}: \d+ checks, 0 failures", log)
            if not summary:
                raise RuntimeError("Release storage roundtrip did not complete\n" + log)
            print(summary.group(0))
        print("PASS fresh installation and checkpoint resume in a second process")
    digest = hashlib.sha256(output.read_bytes()).hexdigest()
    output.with_suffix(".sha256").write_text(f"{digest}  {output.name}\n")
    report = {"version": app_version, "engine": version, "platform": "macOS universal",
              "archive": output.name, "bytes": output.stat().st_size, "sha256": digest,
              "signing": "ad-hoc; not notarized", "verification_skipped": args.skip_checks}
    report["standalone_campaign"] = "passed"
    report["rendered"] = args.rendered
    report["audio_driver"] = "Dummy"
    report["storage_roundtrip"] = "passed; isolated fresh installation and second-process resume"
    output.with_suffix(".json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(f"Built {output}\nSHA-256 {digest}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, RuntimeError, subprocess.TimeoutExpired, zipfile.BadZipFile) as exc:
        print(f"Export failed: {exc}", file=sys.stderr)
        sys.exit(1)
