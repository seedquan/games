"""Exercise acceptance filesystem failures without running a game or touching saves."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest
import zipfile


SCRIPT = Path(__file__).with_name("run_windows_acceptance.ps1")


class AcceptanceIOTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="abyss-acceptance-io-")
        self.root = Path(self.temp.name)
        self.denied = self.root / "denied"
        self.denied.mkdir()
        (self.root / 'share').mkdir()
        # Real filesystem denial, rather than a mocked PowerShell exception.
        self.denied.chmod(0o500)

    def tearDown(self):
        self.denied.chmod(0o700)
        self.temp.cleanup()

    def run_ps(self, body):
        harness = self.root / "check.ps1"
        harness.write_text(r'''
$ErrorActionPreference = 'Stop'
$source = Get-Content -LiteralPath $env:ABYSS_IO_SOURCE -Raw
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
foreach ($function in $ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst]}, $false)) {
    . ([scriptblock]::Create($function.Extent.Text))
}
$AcceptanceVersion = '0.11.1'
$root = $env:ABYSS_IO_ROOT
$denied = Join-Path $root 'denied'
''' + body, encoding="utf-8")
        result = subprocess.run(
            ["pwsh", "-NoLogo", "-NoProfile", "-File", str(harness)],
            env={**os.environ, "ABYSS_IO_SOURCE": str(SCRIPT), "ABYSS_IO_ROOT": str(self.root)},
            capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result.stdout

    @unittest.skipIf(os.name == "nt", "This regression uses POSIX directory permissions")
    def test_unwritable_temp_uses_writable_fallback(self):
        self.run_ps(r'''
$fallback = Join-Path $root 'user local QA'
if (Get-Command New-AcceptanceWorkspace -ErrorAction SilentlyContinue) {
    $chosen = New-AcceptanceWorkspace -Candidates @($denied, $fallback)
} else {
    # Original handoff only selected TEMP; the verifier's first write failed here.
    $chosen = $denied
    New-Item -ItemType Directory -Path (Join-Path $chosen 'abyss-windows-0123456789abcdef0123456789abcdef/storage with spaces') -Force | Out-Null
}
if (-not $chosen.StartsWith($fallback) -or -not (Test-Path -LiteralPath $chosen -PathType Container)) {
    throw 'A writable fallback workspace was not selected.'
}
''')

    def evidence(self):
        run = self.root / "abyss-windows-0123456789abcdef0123456789abcdef"
        run.mkdir()
        (run / "report.json").write_text(json.dumps({"fixture": "Synthetic I/O test, NOT a game acceptance report"}))
        for stage in ("campaign", "write", "read"):
            for suffix in ("log", "engine.log"):
                (run / f"{stage}.{suffix}").write_text("synthetic I/O fixture")
        storage = run / "storage with spaces"
        storage.mkdir()
        for shot in ("title-write", "title-read", "shop-write", "shop-read", "victory-read", "coop-write", "coop-read"):
            (storage / f"{shot}.png").write_bytes(b"synthetic I/O fixture")
        (storage / "profile.cfg").write_text("must stay local")
        (storage / "settings.cfg").write_text("must also stay local")
        return run

    def snapshot_files(self, directory):
        return {path: path.read_bytes() for path in directory.rglob("*") if path.is_file()}

    def assert_original_files_unchanged(self, originals):
        for path, content in originals.items():
            self.assertTrue(path.is_file(), f"Original fixture file was removed: {path}")
            self.assertEqual(path.read_bytes(), content, f"Original fixture file was changed: {path}")

    def assert_local_archive(self, publication, run):
        self.assertIn("local_archive", publication, "Publication must expose the local diagnostics ZIP")
        archive_path = Path(publication["local_archive"])
        self.assertTrue(archive_path.is_file(), "A transferable local ZIP must survive publication failure")
        expected = {"report.json", "handoff.json"}
        expected.update(f"{stage}.{suffix}" for stage in ("campaign", "write", "read") for suffix in ("log", "engine.log"))
        expected.update(f"storage with spaces/{shot}.png" for shot in (
            "title-write", "title-read", "shop-write", "shop-read", "victory-read", "coop-write", "coop-read",
        ))
        with zipfile.ZipFile(archive_path) as archive:
            members = [item.filename for item in archive.infolist() if not item.is_dir()]
            self.assertEqual(set(members), expected, "Transfer ZIP must contain only the complete diagnostics whitelist")
            self.assertEqual(len(members), len(expected), "Transfer ZIP must not duplicate evidence")
            for relative in expected - {"handoff.json"}:
                self.assertEqual(archive.read(relative), (run / relative).read_bytes())
            self.assertEqual(archive.read("handoff.json"), (Path(publication["local_directory"]) / "handoff.json").read_bytes())
            receipt = json.loads(archive.read("handoff.json").decode("utf-8-sig"))
            self.assertEqual(receipt["report_sha256"], hashlib.sha256(archive.read("report.json")).hexdigest())

    @unittest.skipIf(os.name == "nt", "This regression uses POSIX directory permissions")
    def test_denied_share_preserves_local_evidence_without_failing_test_result(self):
        run = self.evidence()
        originals = self.snapshot_files(run)
        output = self.run_ps(r'''
$runDirectory = Join-Path $root 'abyss-windows-0123456789abcdef0123456789abcdef'
$result = Publish-AcceptanceEvidence -RunDirectory $runDirectory -DestinationRoot $denied
if ($result.published -or -not $result.error -or -not (Test-Path -LiteralPath $result.local_directory)) {
    throw 'Denied upload must return retained local evidence and a separate upload error.'
}
if (-not $result.local_archive -or -not (Test-Path -LiteralPath $result.local_archive -PathType Leaf)) {
    throw 'Denied upload must also retain a transferable diagnostics ZIP.'
}
$result | ConvertTo-Json -Compress
''')
        publication = json.loads(output)
        self.assert_local_archive(publication, run)
        self.assert_original_files_unchanged(originals)

    def test_success_copies_only_diagnostics_and_binds_report_hash(self):
        run = self.evidence()
        originals = self.snapshot_files(run)
        output = self.run_ps(r'''
$runDirectory = Join-Path $root 'abyss-windows-0123456789abcdef0123456789abcdef'
$result = Publish-AcceptanceEvidence -RunDirectory $runDirectory -DestinationRoot (Join-Path $root 'share')
if (-not $result.published) { throw $result.error }
if (-not (Test-Path -LiteralPath $result.destination -PathType Leaf)) { throw 'Report must be a file directly in the target directory.' }
if ((Get-FileHash -LiteralPath $result.destination).Hash -ne (Get-FileHash -LiteralPath $result.local_archive).Hash) { throw 'Archive copy differs.' }
$result | ConvertTo-Json -Compress
''')
        publication = json.loads(output)
        self.assert_local_archive(publication, run)
        target = Path(publication["destination"])
        self.assertEqual(target.parent, self.root / "share")
        self.assertEqual(list(target.parent.iterdir()), [target])
        self.assertEqual(target.read_bytes(), Path(publication["local_archive"]).read_bytes())
        self.assert_original_files_unchanged(originals)

    def test_unavailable_zip_dependency_preserves_local_diagnostics_without_creating_target_directories(self):
        run = self.evidence()
        originals = self.snapshot_files(run)
        output = self.run_ps(r'''
# Simulate only an unavailable compression assembly. Directory, copy and hash
# operations below still run against the real filesystem.
function Add-Type { throw 'Synthetic compression dependency unavailable' }
$runDirectory = Join-Path $root 'abyss-windows-0123456789abcdef0123456789abcdef'
$result = Publish-AcceptanceEvidence -RunDirectory $runDirectory -DestinationRoot (Join-Path $root 'share')
if ($result.published -or -not $result.error) { throw 'ZIP failure must not claim publication.' }
if ($result.local_archive -or -not $result.archive_error.Contains('Synthetic compression dependency unavailable')) {
    throw 'ZIP dependency failure must be reported separately from publication.'
}
$result | ConvertTo-Json -Compress
''')
        publication = json.loads(output)
        local = Path(publication["local_directory"])
        self.assertFalse(Path(publication["destination"]).exists())
        self.assertEqual(list((self.root / "share").iterdir()), [])
        self.assertTrue((local / "handoff.json").is_file())
        for path, content in originals.items():
            relative = path.relative_to(run)
            if path.name in ("profile.cfg", "settings.cfg"):
                self.assertFalse((local / relative).exists())
            else:
                self.assertEqual((local / relative).read_bytes(), content)
        self.assert_original_files_unchanged(originals)

    @unittest.skipIf(os.name == "nt", "This regression uses POSIX directory permissions")
    def test_no_writable_workspace_reports_full_path(self):
        self.run_ps(r'''
$caught = $false
try { New-AcceptanceWorkspace -Candidates @($denied) | Out-Null }
catch {
    $caught = $true
    if (-not $_.Exception.Message.Contains($denied)) { throw 'Missing failed directory in diagnostic.' }
}
if (-not $caught) { throw 'Unwritable workspace incorrectly accepted.' }
''')

    def test_missing_evidence_does_not_publish_a_receipt(self):
        run = self.evidence()
        (run / "storage with spaces/coop-read.png").unlink()
        self.run_ps(r'''
$runDirectory = Join-Path $root 'abyss-windows-0123456789abcdef0123456789abcdef'
$caught = $false
try { Publish-AcceptanceEvidence -RunDirectory $runDirectory -DestinationRoot (Join-Path $root 'share') | Out-Null }
catch { $caught = $true }
if (-not $caught) { throw 'Incomplete local evidence was accepted.' }
if (Get-ChildItem -LiteralPath $root -Recurse -Filter 'handoff.json') { throw 'Receipt created for incomplete evidence.' }
''')

    def assert_retry_preserves_remote_run(self, completed):
        run = self.evidence()
        originals = self.snapshot_files(run)
        remote = self.root / "share" / f"Windows验收报告-0.11.1-{run.name}.zip"
        if completed:
            with zipfile.ZipFile(remote, "w") as archive:
                archive.writestr("handoff.json", "existing evidence must not change")
        else:
            remote.write_bytes(b"interrupted ZIP upload")
        remote_original = remote.read_bytes()
        output = self.run_ps(r'''
$runDirectory = Join-Path $root 'abyss-windows-0123456789abcdef0123456789abcdef'
$result = Publish-AcceptanceEvidence -RunDirectory $runDirectory -DestinationRoot (Join-Path $root 'share')
if (-not $result.published) { throw ('Existing remote run should allow a separate retry: ' + $result.error) }
$result | ConvertTo-Json -Compress
''')
        publication = json.loads(output)
        destination = Path(publication["destination"])
        self.assertEqual(destination.parent, remote.parent)
        self.assertRegex(destination.name, "^" + re.escape(remote.stem) + r"-retry-[0-9a-f]{32}\.zip$")
        self.assertEqual(remote.read_bytes(), remote_original, "Retry must preserve previous complete or partial archives")
        self.assertEqual(destination.read_bytes(), Path(publication["local_archive"]).read_bytes())
        self.assert_local_archive(publication, run)
        self.assert_original_files_unchanged(originals)

    def test_existing_completed_remote_run_is_preserved_and_retry_succeeds(self):
        self.assert_retry_preserves_remote_run(completed=True)

    def test_partial_remote_run_is_preserved_and_retry_succeeds(self):
        self.assert_retry_preserves_remote_run(completed=False)


if __name__ == "__main__":
    unittest.main()
