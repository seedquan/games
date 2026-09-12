# Windows desktop packaging and verification

Status: implemented

## Context

The user extended the production-quality Godot goal to Windows while retaining
the existing Mac version. This work adds Windows 10/11 x86_64 packaging; it does
not change the browser game, Pages deployment or other projects.

## Decision

Use official Godot 4.7.2 release templates with a pinned full-archive SHA-256 in
`prepare_windows_templates.py`. The Windows exporter validates template
provenance, engine version, PE32+ architecture, icon/version resources, content
pack and archive integrity. Runtime assets remain local. Developer scripts,
tools, docs, tests and build storage are excluded from the packed game.

Package a portable EXE/PCK pair, Chinese player instructions, complete engine
and library/font attributions, an ANGLE compatibility launcher and an optional
PowerShell verifier. No Godot/Python/Wine installation is required for players.
Mac and Windows versions are 0.9.6; Mac archives include attributions beside the
signed app, preserving its signature.

`Verify-Windows.ps1` uses a marked temporary storage fixture and three separate
processes: campaign, write, read/resume. It rejects nonzero exits, engine errors
and missing summaries; reports bind results to the EXE and PCK checksums. Rendered
storage tests save screenshots only in the validated fixture. Native Windows and
Wine are explicitly different report types. A reused Wine prefix must carry an
`.abyss-wine-fixture` marker; never use the normal/default prefix.

## Verification

The nine source suites pass. Actual Windows binaries passed campaign and
two-process storage checks in Wine 11.0 on an Apple M4 Pro, both headless
(30/11/19 checks) and rendered OpenGL (30/13/22 checks). Inspected screenshots
show Chinese fonts/title art and restored shop state. Unicode and spaces in
package/storage paths are covered. PE identity, ZIP CRC and file hashes pass.

The ANGLE path fails EGL display initialization in this Wine environment. Its
failure is recorded separately; it is not a successful renderer test and does
not establish behavior on native Windows. Windows hardware/DPI/audio/physical
controller and human-play acceptance remain open.

Mac 0.9.6 independently passes headless release (30/11/19) and native release
(30/13/22), signature and ZIP checks. Exact artifacts, hashes and log paths are
in `abyss-protocol-godot/docs/production-readiness.md`.

## Consequences

Cross-export can produce a useful Windows candidate locally. Wine gives real
Windows-binary execution evidence without claiming Windows hardware coverage.
An explicit `--structural-only` escape hatch creates an unexecuted package with
that limitation preserved in its report. Publishing/signing remains outside
the authorized local build task.
