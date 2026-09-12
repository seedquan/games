"""Exercise acceptance filesystem failures without running a game or touching saves."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).with_name("run_windows_acceptance.ps1")


class AcceptanceIOTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="abyss-acceptance-io-")
        self.root = Path(self.temp.name)
        self.denied = self.root / "denied"
        self.denied.mkdir()
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
$root = $env:ABYSS_IO_ROOT
$denied = Join-Path $root 'denied'
''' + body, encoding="utf-8")
        result = subprocess.run(
            ["pwsh", "-NoLogo", "-NoProfile", "-File", str(harness)],
            env={**os.environ, "ABYSS_IO_SOURCE": str(SCRIPT), "ABYSS_IO_ROOT": str(self.root)},
            capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

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
        return run

    @unittest.skipIf(os.name == "nt", "This regression uses POSIX directory permissions")
    def test_denied_share_preserves_local_evidence_without_failing_test_result(self):
        run = self.evidence()
        self.run_ps(r'''
$runDirectory = Join-Path $root 'abyss-windows-0123456789abcdef0123456789abcdef'
$runName = Split-Path -Leaf $runDirectory
if (Get-Command Publish-AcceptanceEvidence -ErrorAction SilentlyContinue) {
    $result = Publish-AcceptanceEvidence -RunDirectory $runDirectory -DestinationRoot $denied
    if ($result.published -or -not $result.error -or -not (Test-Path -LiteralPath $result.local_directory)) {
        throw 'Denied upload must return retained local evidence and a separate upload error.'
    }
} else {
    # Execute the original inline publication block; failure used to escape to the
    # outer "acceptance incomplete" catch even after all game checks had passed.
    $start = $source.IndexOf('    $destination = Join-Path')
    $end = $source.IndexOf('    exit 0', $start)
    $legacy = $source.Substring($start, $end - $start)
    $legacy = $legacy.Replace("(Join-Path $PSScriptRoot '验收记录')", '$denied')
    $legacy = $legacy -replace '\(Join-Path \$PSScriptRoot ''验收记录''\)', '$denied'
    & ([scriptblock]::Create($legacy))
}
''')
        self.assertTrue((run / "report.json").is_file())

    def test_success_copies_only_diagnostics_and_binds_report_hash(self):
        run = self.evidence()
        self.run_ps(r'''
$runDirectory = Join-Path $root 'abyss-windows-0123456789abcdef0123456789abcdef'
$result = Publish-AcceptanceEvidence -RunDirectory $runDirectory -DestinationRoot (Join-Path $root 'share')
if (-not $result.published) { throw $result.error }
$receipt = Get-Content -LiteralPath (Join-Path $result.destination 'handoff.json') -Raw | ConvertFrom-Json
$hash = (Get-FileHash -LiteralPath (Join-Path $result.destination 'report.json')).Hash.ToLowerInvariant()
if ($receipt.report_sha256 -ne $hash) { throw 'Receipt is not bound to copied report.' }
if (Test-Path -LiteralPath (Join-Path $result.destination 'storage with spaces/profile.cfg')) { throw 'Player fixture copied.' }
''')
        self.assertTrue((run / "storage with spaces/profile.cfg").is_file())

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

    def test_existing_remote_run_is_preserved(self):
        run = self.evidence()
        remote = self.root / "share" / run.name
        remote.mkdir(parents=True)
        receipt = remote / "handoff.json"
        receipt.write_text("existing evidence must not change")
        self.run_ps(r'''
$runDirectory = Join-Path $root 'abyss-windows-0123456789abcdef0123456789abcdef'
$result = Publish-AcceptanceEvidence -RunDirectory $runDirectory -DestinationRoot (Join-Path $root 'share')
if ($result.published -or -not (Test-Path -LiteralPath $result.local_directory)) { throw 'Existing remote run was not handled safely.' }
''')
        self.assertEqual(receipt.read_text(), "existing evidence must not change")


if __name__ == "__main__":
    unittest.main()
