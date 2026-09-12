"""Recover already completed native reports without launching a game."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).with_name("run_windows_acceptance.ps1")
EXE_HASH = "a" * 64
PACK_HASH = "b" * 64


class AcceptanceRecoveryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="abyss-report-recovery-")
        self.root = Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def run_ps(self, body):
        harness = self.root / "check.ps1"
        harness.write_text(r'''
$ErrorActionPreference = 'Stop'
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($env:ABYSS_RECOVERY_SOURCE, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
foreach ($function in $ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst]}, $false)) {
    . ([scriptblock]::Create($function.Extent.Text))
}
$AcceptanceVersion = '0.11.0'
$root = $env:ABYSS_RECOVERY_ROOT
$expected = @{ 'AbyssProtocol.exe' = ('a' * 64); 'AbyssProtocol.pck' = ('b' * 64) }
''' + body, encoding="utf-8")
        result = subprocess.run(
            ["pwsh", "-NoLogo", "-NoProfile", "-File", str(harness)],
            env={**os.environ, "ABYSS_RECOVERY_SOURCE": str(SCRIPT), "ABYSS_RECOVERY_ROOT": str(self.root)},
            capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def evidence(self, number=1, **report_changes):
        workspace = self.root / f"abyss-acceptance-{number:032x}"
        workspace.mkdir()
        (workspace / ".abyss-acceptance-workspace").write_text("Disposable acceptance workspace")
        run = workspace / f"abyss-windows-{number:032x}"
        run.mkdir()
        report = {
            "runtime": "Windows native", "rendered": True,
            "executable_sha256": EXE_HASH, "content_sha256": PACK_HASH,
            "checks": [{"stage": stage, "exit_code": 0, "summary": f"{prefix}: 10 checks, 0 failures"}
                       for stage, prefix in (("campaign", "ABYSS RELEASE"), ("write", "ABYSS STORAGE WRITE"),
                                             ("read", "ABYSS STORAGE READ"))],
            "fixture": "Synthetic recovery test; NOT Windows hardware evidence",
        }
        report.update(report_changes)
        (run / "report.json").write_text(json.dumps(report), encoding="utf-8")
        os.utime(run / "report.json", (1000 + number, 1000 + number))
        for stage in ("campaign", "write", "read"):
            for suffix in ("log", "engine.log"):
                (run / f"{stage}.{suffix}").write_text("Synthetic fixture")
        storage = run / "storage with spaces"
        storage.mkdir()
        for shot in ("title-write", "title-read", "shop-write", "shop-read", "victory-read", "coop-write", "coop-read"):
            (storage / f"{shot}.png").write_bytes(b"Synthetic fixture")
        (storage / "profile.cfg").write_text("must stay local")
        return run

    def test_recovers_latest_matching_report_without_running_verifier(self):
        self.evidence(1)
        latest = self.evidence(2)
        self.evidence(3, content_sha256="c" * 64)
        self.evidence(4, runtime="Wine compatibility; not Windows hardware")
        # Recovery runs through its real public function; a game cannot be invoked.
        self.run_ps(r'''
function Start-Process { throw 'Report recovery must never launch a game.' }
[void][IO.Directory]::CreateDirectory((Join-Path $root 'share'))
$result = Restore-AcceptanceEvidence -Candidates @($root) -Expected $expected -DestinationRoot (Join-Path $root 'share')
if (-not $result.published) { throw $result.error }
if ((Split-Path -Leaf $result.run_directory) -ne 'abyss-windows-00000000000000000000000000000002') { throw 'Wrong report selected.' }
if (-not (Test-Path -LiteralPath $result.local_archive -PathType Leaf)) { throw 'Recovery did not create a portable report.' }
''')
        self.assertEqual((latest / "storage with spaces/profile.cfg").read_text(), "must stay local")

    def test_explicit_report_must_match_release_and_all_stages(self):
        run = self.evidence()
        self.run_ps(r'''
$run = Join-Path $root 'abyss-acceptance-00000000000000000000000000000001/abyss-windows-00000000000000000000000000000001'
$expected['AbyssProtocol.pck'] = ('c' * 64)
$caught = $false
try { Restore-AcceptanceEvidence -RunDirectory $run -Expected $expected -DestinationRoot (Join-Path $root 'share') | Out-Null }
catch { $caught = $true; if (-not $_.Exception.Message.Contains('does not verify')) { throw } }
if (-not $caught -or (Test-Path -LiteralPath (Join-Path $root 'share'))) { throw 'Wrong release was published.' }
''')
        report = json.loads((run / "report.json").read_text())
        report["checks"][2]["exit_code"] = 1
        (run / "report.json").write_text(json.dumps(report))
        self.run_ps(r'''
$run = Join-Path $root 'abyss-acceptance-00000000000000000000000000000001/abyss-windows-00000000000000000000000000000001'
$caught = $false
try { Restore-AcceptanceEvidence -RunDirectory $run -Expected $expected -DestinationRoot (Join-Path $root 'share') | Out-Null }
catch { $caught = $true; if (-not $_.Exception.Message.Contains('Incomplete verification stage')) { throw } }
if (-not $caught -or (Test-Path -LiteralPath (Join-Path $root 'share'))) { throw 'Failed stage was published.' }
''')

    @unittest.skipIf(os.name == "nt", "Creating Windows symlinks may require elevated privileges")
    def test_discovery_ignores_unmarked_and_linked_workspaces(self):
        run = self.evidence()
        (run.parent / ".abyss-acceptance-workspace").unlink()
        linked = self.root / "abyss-acceptance-00000000000000000000000000000002"
        outside = self.root / "outside-discovery"
        outside.mkdir()
        (outside / ".abyss-acceptance-workspace").write_text("Disposable acceptance workspace")
        # A linked marked workspace must also be ignored, independently of the
        # unmarked real workspace above.
        (outside / run.name).symlink_to(run, target_is_directory=True)
        linked.symlink_to(outside, target_is_directory=True)
        self.run_ps(r'''
$caught = $false
try { Restore-AcceptanceEvidence -Candidates @($root) -Expected $expected -DestinationRoot (Join-Path $root 'share') | Out-Null }
catch {
    $caught = $true
    if (-not $_.Exception.Message.Contains('未找到')) { throw }
}
if (-not $caught -or (Test-Path -LiteralPath (Join-Path $root 'share'))) { throw 'Unmarked fixture was accepted.' }
''')


if __name__ == "__main__":
    unittest.main()
