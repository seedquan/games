# Chinese campaign, local progression, and rescue narrative

Status: implemented.

## Context and scope

The user requested an independent Abyss Protocol remake under `games`, using
Godot, then explicitly added a fully Chinese interface and a coherent story.
The native remake now has a complete single-player rescue campaign. The old
browser game remains independent. Optional legacy co-op, touch/gamepad support,
weapon aspects and advanced animation are documented differences, not claimed
as implemented in this version. No release export or publication was requested.

## Decisions

- `rooms.gd` assembles twelve chambers from six layouts and mirrored variants,
  with reproducible seeded spawn order, combat/elite/supply/repair choices, and
  guardians at chambers 6 and 12. Two clearance grids let ordinary and larger
  enemies navigate around solid cover.
- `progression.gd` separates run upgrades/runes from permanent upgrades.
  Scrap resets on a new run. Technical cores are banked on room clear and can
  upgrade the next android. Room awards, purchases and ending rewards are guarded
  against duplicate activation. All six rune types apply through the shared
  weapon-hit path, while the shared plasma ability remains unenchanted.
- `profile.gd` stores only this game's bounded progress fields in
  `user://profile.cfg`. Writes are staged and the previous profile is backed up.
  Recovery never copies a broken primary over a known valid backup. Unknown
  future schemas are read-only. Test saves use unique, isolated paths.
- All player-facing names, descriptions, menus, status labels, prompts and
  narrative are Chinese. Keyboard key names retain their real labels. Noto Sans
  CJK SC is bundled locally under SIL OFL 1.1; no runtime font downloads or
  proprietary system-font redistribution is needed.
- `story.gd` owns six milestone scenes: activation, false-alarm evidence,
  authorization recovered from the warden, independent calibration readings,
  the core repair handshake, and evacuation. Dialogue freezes combat and does
  not advance twice on repeated input. Both route branches preserve all clues.
  Only the final victory resolves the rescue; ordinary defeat returns the
  android's records to the dock for another attempt.

## Narrative contract

312 passengers remain in hibernation. A broken temperature sensor triggers an
overprotective containment protocol; power diverted from cooling creates the
real danger. The android must restore power, gain authorization and return valid
data. It suppresses the defense module instead of indiscriminately cutting life
support. The AI corrects its assessment and assists evacuation. This causal
sequence is documented in `abyss-protocol-godot/docs/剧情设定.md`.

## Verification and boundaries

`python3 verify.py` imports the Godot project and runs real-scene smoke,
weapons, campaign/persistence and story/localization suites. They cover room
navigation and live obstacle avoidance, currency/purchase guards, profile
round-trip/recovery/version handling, both full narrative routes, font glyph
coverage, untranslated UI tokens and menu size. Runtime/import errors fail the
wrapper even when Godot returns exit code 0. The desktop opening, Chinese text,
story continuation, primary/plasma input and pause menu were also exercised.

Local resource references all resolve inside the project. The original HTML,
hub and Pages workflow have no diff. Existing westworld changes were preserved;
its unrelated test/build suites were not run. Exports, other operating systems,
legacy feature parity and performance certification are not claimed.
