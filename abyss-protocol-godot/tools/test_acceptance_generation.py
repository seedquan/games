"""Verify acceptance generation against isolated synthetic export archives."""
import codecs
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import warnings
import zipfile

import prepare_windows_acceptance as prepare


class AcceptanceGenerationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="abyss-acceptance-generation-")
        self.root = Path(self.temp.name)
        self.version = "0.11.0"
        self.package = "深渊协议 " + self.version + "/"
        self.archive = self.root / f"深渊协议-{self.version}-Windows-x64.zip"
        self.report_path = self.archive.with_suffix(".json")
        self.output = self.root / "handoff"
        self.contents = {
            "AbyssProtocol.exe": b"Synthetic executable fixture, NOT a game",
            "AbyssProtocol.pck": b"Synthetic content fixture, NOT a game",
            "Verify-Windows.ps1": b"# Synthetic verifier fixture; never executed\n",
            "ThirdPartyNotices.txt": b"Synthetic attribution fixture\n",
        }
        self.files = {name: hashlib.sha256(data).hexdigest() for name, data in self.contents.items()}
        self.report = {
            "version": self.version, "platform": "Windows 10/11 x86_64",
            "archive": self.archive.name, "files": self.files,
        }
        self.write_zip()

    def tearDown(self):
        self.temp.cleanup()

    def save_report(self):
        self.report_path.write_text(json.dumps(self.report), encoding="utf-8")

    def write_zip(self, contents=None, embedded=None, extra=None):
        with zipfile.ZipFile(self.archive, "w", zipfile.ZIP_DEFLATED) as archive:
            for name, data in (self.contents if contents is None else contents).items():
                archive.writestr(self.package + name, data)
            archive.writestr(self.package + "checksums.json", json.dumps(self.files if embedded is None else embedded))
            if extra:
                with warnings.catch_warnings():
                    warnings.simplefilter("ignore", UserWarning)
                    archive.writestr(*extra)
        self.report["bytes"] = self.archive.stat().st_size
        self.report["sha256"] = prepare.digest(self.archive)
        self.save_report()

    def assert_rejected(self):
        with self.assertRaises((ValueError, OSError, zipfile.BadZipFile)):
            prepare.generate(self.report_path, output=self.output)
        self.assertFalse(self.output.exists(), "Rejected inputs must not leave a runnable handoff")

    def test_generates_bound_scripts_and_instructions_with_windows_encoding(self):
        result = prepare.generate(self.report_path, output=self.output)
        self.assertEqual(result, self.output)
        script = (self.output / "Run-Windows-Acceptance.ps1").read_bytes()
        instructions = (self.output / "Windows验收说明.txt").read_bytes()
        for content in (script, instructions):
            self.assertTrue(content.startswith(codecs.BOM_UTF8))
            self.assertNotIn(b"\n", content.replace(b"\r\n", b""))
            self.assertNotIn(b"__ABYSS_", content)
        text = script.decode("utf-8-sig")
        self.assertIn("$AcceptanceVersion = '0.11.0'", text)
        for name in prepare.TOKENS:
            self.assertIn(self.files[name], text)
        self.assertIn("深渊协议 0.11.0", instructions.decode("utf-8-sig"))
        self.assertEqual((self.output / "一键Windows验收.cmd").read_bytes(),
                         (prepare.ROOT / "tools/run_windows_acceptance.cmd").read_bytes())
        recovery = (self.output / "仅回传验收报告.cmd").read_text(encoding="ascii")
        self.assertIn('-ReportOnly', recovery)
        manifest = json.loads((self.output / "acceptance-manifest.json").read_text())
        self.assertEqual(manifest["version"], self.version)
        self.assertEqual(manifest["tool_revision"], 5)
        self.assertEqual(manifest["archive_sha256"], self.report["sha256"])
        self.assertEqual(manifest["release_files"], {name: self.files[name] for name in prepare.TOKENS})
        for name, expected in manifest["files"].items():
            self.assertEqual(prepare.digest(self.output / name), expected)

    def test_destination_is_bound_and_powershell_quotes_are_literal(self):
        target = r"\\test-server\Games\owner's reports"
        prepare.generate(self.report_path, output=self.output, destination_root=target)
        script = (self.output / "Run-Windows-Acceptance.ps1").read_text(encoding="utf-8-sig")
        self.assertIn("[string]$DestinationRoot = '" + target.replace("'", "''") + "'", script)
        manifest = json.loads((self.output / "acceptance-manifest.json").read_text())
        self.assertEqual(manifest["report_destination"], target)
        self.assertIn(target, (self.output / "Windows验收说明.txt").read_text(encoding="utf-8-sig"))
        for invalid in ("relative", "C:relative", "C:\\Games\nInjected"):
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                prepare.generate(self.report_path, output=self.root / "invalid", destination_root=invalid)

    def test_default_output_is_a_separate_versioned_build_directory(self):
        fixture_project = self.root / "project"
        for relative in ("tools/run_windows_acceptance.ps1", "tools/run_windows_acceptance.cmd", "tools/recover_windows_acceptance.cmd", "docs/windows-acceptance.txt"):
            target = fixture_project / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(prepare.ROOT / relative, target)
        with patch.object(prepare, "ROOT", fixture_project):
            output = prepare.generate(self.report_path)
        self.assertEqual(output, fixture_project / "builds/acceptance-0.11.0")
        self.assertTrue((output / "Run-Windows-Acceptance.ps1").is_file())

    def test_changed_zip_digest_or_size_is_rejected(self):
        with self.archive.open("ab") as archive:
            archive.write(b"unexpected changed bytes")
        self.assert_rejected()

    def test_each_critical_member_hash_is_checked_even_when_zip_hash_matches(self):
        for name in prepare.TOKENS:
            with self.subTest(name=name):
                changed = dict(self.contents)
                changed[name] += b" modified"
                self.write_zip(changed)
                self.assert_rejected()

    def test_missing_report_fields_or_critical_hashes_are_rejected(self):
        original = dict(self.report)
        for field in ("version", "archive", "platform", "bytes", "sha256", "files"):
            with self.subTest(field=field):
                self.report = dict(original)
                self.report.pop(field)
                self.save_report()
                self.assert_rejected()
        for name in prepare.TOKENS:
            with self.subTest(critical_file=name):
                self.report = {**original, "files": dict(self.files)}
                self.report["files"].pop(name)
                self.save_report()
                self.assert_rejected()

    def test_missing_archive_or_member_is_rejected(self):
        incomplete = dict(self.contents)
        incomplete.pop("Verify-Windows.ps1")
        self.write_zip(incomplete)
        self.assert_rejected()
        self.archive.unlink()
        self.assert_rejected()

    def test_duplicate_or_unreported_zip_entries_are_rejected(self):
        for member in (self.package + "AbyssProtocol.exe", "../unexpected.ps1"):
            with self.subTest(member=member):
                self.write_zip(extra=(member, b"unexpected ZIP entry"))
                self.assert_rejected()

    def test_embedded_checksum_manifest_must_match_report(self):
        self.write_zip(embedded={})
        self.assert_rejected()

    def test_version_and_hash_values_cannot_inject_script_or_paths(self):
        original = dict(self.report)
        for field, value in (("version", "0.11.0'; Write-Host injected; '"),
                             ("version", "../0.11.0"), ("sha256", "missing"),
                             ("bytes", True), ("archive", "../archive.zip")):
            with self.subTest(field=field):
                self.report = {**original, field: value}
                self.save_report()
                self.assert_rejected()

    def test_existing_handoff_is_never_overwritten(self):
        self.output.mkdir()
        existing = self.output / "Run-Windows-Acceptance.ps1"
        existing.write_text("prior delivered handoff must remain intact")
        with self.assertRaises(FileExistsError):
            prepare.generate(self.report_path, output=self.output)
        self.assertEqual(existing.read_text(), "prior delivered handoff must remain intact")
        self.assertEqual(list(self.output.iterdir()), [existing])

    @unittest.skipUnless(shutil.which("pwsh"), "PowerShell is needed to parse generated delivery scripts")
    def test_generated_powershell_parses_and_source_template_refuses_execution(self):
        prepare.generate(self.report_path, output=self.output)
        harness = self.root / "parse.ps1"
        harness.write_text("""
$tokens = $null; $errors = $null
[void][Management.Automation.Language.Parser]::ParseFile($env:ABYSS_GENERATED_ACCEPTANCE, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
""")
        result = subprocess.run(["pwsh", "-NoLogo", "-NoProfile", "-File", str(harness)],
                                env={**os.environ, "ABYSS_GENERATED_ACCEPTANCE": str(self.output / "Run-Windows-Acceptance.ps1")},
                                capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        source = subprocess.run(["pwsh", "-NoLogo", "-NoProfile", "-File", str(prepare.ROOT / "tools/run_windows_acceptance.ps1")],
                                capture_output=True, text=True, timeout=30)
        self.assertNotEqual(source.returncode, 0)
        self.assertIn("unrendered acceptance template", source.stdout + source.stderr)
        if os.name != "nt":
            # The real generated entry point must stop before package access on a
            # non-Windows host, including report-only mode. No game is available.
            entry = subprocess.run(["pwsh", "-NoLogo", "-NoProfile", "-File",
                                    str(self.output / "Run-Windows-Acceptance.ps1"), "-ReportOnly"],
                                   capture_output=True, text=True, timeout=30)
            self.assertEqual(entry.returncode, 1, entry.stdout + entry.stderr)
            self.assertIn("must be run on the Windows test computer", entry.stdout)
            self.assertFalse((self.output / "验收记录").exists())


if __name__ == "__main__":
    unittest.main()
