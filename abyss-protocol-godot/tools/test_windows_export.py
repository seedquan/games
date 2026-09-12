"""Exercise Windows packaging I/O with synthetic files, without invoking Godot."""
from contextlib import redirect_stdout
import hashlib
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import export_windows as export
import prepare_windows_acceptance as prepare


class WindowsExportTests(unittest.TestCase):
    def test_unicode_package_and_acceptance_survive_a_non_utf8_system_locale(self):
        with tempfile.TemporaryDirectory(prefix="abyss-windows-export-test-") as temporary:
            root = Path(temporary)
            for directory in ("builds/templates", "tools", "docs"):
                (root / directory).mkdir(parents=True)
            (root / "project.godot").write_text('config/name="深渊协议"\nconfig/version="0.11.0"\n', encoding="utf-8")
            player_text = "深渊协议：三十舱救援。\n"
            (root / "docs/windows-player.txt").write_text(player_text, encoding="utf-8")
            (root / "tools/verify_windows.ps1").write_text("# Synthetic fixture, never executed\n", encoding="utf-8")
            template = root / "builds/templates/windows_release_x86_64.exe"
            template.write_bytes(b"Synthetic template fixture, not a Windows executable")
            provenance = {"version": "4.7.2.stable", "archive_sha256": export.TEMPLATE_ARCHIVE_SHA256,
                          "files": {template.name: export.digest(template)}}
            (template.parent / "windows-provenance.json").write_text(json.dumps(provenance), encoding="utf-8")
            verifier_commands = []

            def fake_run(command, **kwargs):
                if command[-1] == "--version":
                    return "4.7.2.stable.fixture\n"
                if "res://tools/export_notices.gd" in command:
                    (root / "builds/ThirdPartyNotices.txt").write_bytes("合成许可样本\n".encode("utf-8"))
                    return "ABYSS NOTICES: complete\n"
                if "--export-release" in command:
                    executable = Path(command[-1])
                    executable.write_bytes(b"Synthetic executable fixture, not a game")
                    executable.with_suffix(".pck").write_bytes(b"GDPC synthetic content fixture")
                    return "Synthetic export: 深渊协议\n"
                if command[0] == "synthetic-powershell":
                    verifier_commands.append(command)
                    package = Path(command[command.index("-File") + 1]).parent
                    report_path = root / "builds/qa" / f"report-{len(verifier_commands)}.json"
                    report = {"platform": "Synthetic test fixture; no Windows execution",
                              "executable_sha256": export.digest(package / "AbyssProtocol.exe"),
                              "content_sha256": export.digest(package / "AbyssProtocol.pck")}
                    report_path.write_text(json.dumps(report), encoding="utf-8-sig")
                    return "ABYSS WINDOWS REPORT: " + str(report_path) + "\n"
                self.fail("Unexpected process request: " + repr(command))

            original_open = Path.open

            def ansi_open(path, mode="r", buffering=-1, encoding=None, errors=None, newline=None):
                # Python 3.11 on Windows may use an ANSI encoding for text files.
                if "b" not in mode and encoding in (None, "locale"):
                    encoding = "cp1252"
                return original_open(path, mode, buffering, encoding, errors, newline)

            with patch.object(export, "ROOT", root), patch.object(export, "run", side_effect=fake_run), \
                    patch.object(export, "inspect_executable", return_value={"fixture": True}), \
                    patch.object(export.shutil, "which", return_value="synthetic-powershell"), \
                    patch.object(sys, "argv", ["export_windows.py", "--skip-checks", "--wine", str(root / "fake-wine"), "--rendered"]), \
                    patch.object(Path, "open", ansi_open), redirect_stdout(io.StringIO()):
                export.main()

            self.assertEqual(len(verifier_commands), 2)
            for command in verifier_commands:
                self.assertEqual(command[command.index("-ExecutionPolicy") + 1], "Bypass")
                self.assertLess(command.index("-ExecutionPolicy"), command.index("-File"))
            self.assertNotIn("-Rendered", verifier_commands[0])
            self.assertIn("-Rendered", verifier_commands[1])
            archive_path = root / "builds/深渊协议-0.11.0-Windows-x64.zip"
            report_path = archive_path.with_suffix(".json")
            report = json.loads(report_path.read_text(encoding="utf-8"))
            self.assertEqual(report["version"], "0.11.0")
            with zipfile.ZipFile(archive_path) as archive:
                prefix = "深渊协议 0.11.0/"
                self.assertEqual(archive.read(prefix + "游玩说明.txt").decode("utf-8-sig"), player_text)
                self.assertEqual(json.loads(archive.read(prefix + "checksums.json").decode("utf-8")), report["files"])
                for name, expected in report["files"].items():
                    self.assertEqual(hashlib.sha256(archive.read(prefix + name)).hexdigest(), expected)
            self.assertIn(archive_path.name, archive_path.with_suffix(".sha256").read_text(encoding="utf-8"))
            self.assertIn("深渊协议", (root / "builds/qa/windows-export.log").read_text(encoding="utf-8"))
            output = prepare.generate(report_path, output=root / "handoff")
            manifest = json.loads((output / "acceptance-manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(manifest["version"], "0.11.0")
            self.assertEqual(manifest["archive_sha256"], export.digest(archive_path))


if __name__ == "__main__":
    unittest.main()
