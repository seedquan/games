# Godot remake

This directory is a native Godot 4 project, not a single-file browser game.
Read README.md before changing it. Edit `.tscn` scenes and GDScript directly;
there is no HTML build artifact to regenerate.

## Inspecting map artwork without oversized model requests

- Before viewing artwork, check file bytes and dimensions. Do not send the
  original `assets/map/**/*.png` files directly to image-viewing tools or
  print their Base64 data. Several originals can exceed a proxy's request
  limit even in a new conversation; image payloads accumulate in history.
- Generate disposable JPEG previews outside the project, at most 1024 pixels
  on the longest side and 256 KiB per image. On macOS, use
  `sips -s format jpeg -s formatOptions 60 -Z 1024 SOURCE --out PREVIEW.jpg`,
  then verify the output size. View only the previews needed for the decision.
- For precise collision calibration, inspect bounded crops and record the
  crop origin and resize scale; translate coordinates back to the original
  dimensions. Keep the source PNGs and Godot import metadata unchanged.
- Keep previews out of game resources and commits. Summarize findings in text
  instead of repeatedly loading the same images or dumping full map arrays.

## Game implementation rules

- Keep engine-generated `.uid` and asset `.import` metadata with source files.
- Never commit `.godot/`, local export credentials, or `builds/`.
- All runtime resources must live in this project; no dependencies on `output/`.
- Use `./godot.sh --headless --editor --quit` for import and script validation.
- Run `./godot.sh --headless --script res://tests/smoke.gd` after gameplay changes.
- Also run `./godot.sh --headless --script res://tests/weapons.gd` after combat changes.
- Run campaign and Chinese story/UI suites for progression or narrative changes.
- Prefer `python3 verify.py` for all scene suites plus import; it also fails on
  script errors (Godot can otherwise return 0 despite errors) and missing summaries.
- For visual/input changes, also launch and exercise the native game.
- Develop and verify on macOS first, then build and validate Windows. Development
  and test launches must use `--audio-driver Dummy` to stay silent without
  changing system volume or the player's saved preferences.
- `tests/production.gd` covers preferences/input; `tests/checkpoints.gd` recreates
  both complete campaigns from disk at every safe point. Keep their files isolated.
- Save meta progress and safe-point run data in the same profile transaction; do
  not reintroduce a separate checkpoint file that can diverge from core rewards.
- Consult `docs/production-readiness.md` for unfinished delivery gates.
- All player-facing text is Chinese; keyboard labels may retain their key names.
  Keep narrative milestones reachable on both routes. Bundle fonts locally.
- Persistence tests must use an isolated test save path; never mutate the normal profile.
- Do not change the old browser game as part of this remake by default.
- This source-only native project is not a Pages deployment target. A future
  Web export needs an explicit packaging decision and hub/allowlist integration.

- Player animation uses local calibrated part atlases (`android_rig.gd`,
  `rig_data.gd`); movement phase must use post-collision displacement. Keep
  weapon artwork and hand anchors in the same transform; run animation checks
  and native pose inspection after changes.

- `tests/presentation.gd` covers raised projectile origins, cover occlusion and
  boss framing, plus visible attack geometry versus actual damage/projectiles;
  `tests/performance.gd` needs native rendering. Keep normal-rule
  input bot evidence distinct from human usability acceptance.
- Enemy warnings and damage must share melee geometry and projectile directions.
  Ground warning glyphs are preparation cues; placed hazards must retain their
  own full warning delay before damage. Keep the guide and boss attack label current.

- `tests/aiming.gd` protects held mouse aim and charged-shot release. Native
  cursor resources must be cleared before scene exit so Input cannot retain
  textures after the rendering server shuts down.
- Release persistence verification uses two processes and an explicitly marked
  temporary fixture. Never fall back to normal player paths when fixture flags
  are malformed. `--verify-release` alone remains save-free.
- Keyboard capture must allow controller B/Start cancellation without leaving
  settings or changing bindings. Consume other controller menu actions during
  capture. Production menu tests use real D-pad/confirm events; their direct
  combat setup is not player-experience evidence.
- Gameplay and UI joypad bindings must accept every OS-assigned device ID
  (`device = -1`), not just device 0. Production checks dispatch devices 1/3;
  the packed release check also exercises nonzero-device movement and resume.
- Windows packages target x86_64 and use the checksum-pinned official templates
  from `prepare_windows_templates.py`. `export_windows.py` verifies PE identity,
  package contents and isolated release execution via `tools/verify_windows.ps1`.
  Native Windows results and Wine compatibility results must remain distinct.
  Never run Wine tests in a normal/default prefix; reused test prefixes require
  the `.abyss-wine-fixture` marker. Rendered storage checks save screenshots only
  within the already validated disposable release fixture.
- Desktop archives include complete engine/library/font attributions generated
  by `tools/export_notices.gd`. Keep tools, docs and verification scripts out of
  the game content pack; the Windows verifier is copied beside the executable.

- Local co-op uses two explicitly paired device IDs and prefixed gameplay
  actions. Global wildcard bindings remain for single-player and shared menus.
  Do not serialize device IDs. Preserve both actors in one version-2 checkpoint;
  version-1 single-player checkpoints remain supported. All hostile geometry,
  cover occlusion and camera framing must include both actors.
- Run `tests/coop.gd` after co-op changes; its native mode verifies 2560x1440
  render output and OS fullscreen. Use `tests/performance.gd -- --coop` for
  native two-player frame timing, and distinguish input bots from human playtests.
