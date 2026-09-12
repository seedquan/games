# Godot presentation and native acceptance

Status: implemented

## Context

The Mac remake had functional campaign, input and save services, but the visual
hierarchy was noisy, many effects originated at floor proxies instead of the
painted weapon, and no rendered stress or ordinary-rules playthrough existed.

## Decision

Use a restrained industrial station direction: original vector orbital key art,
locally bundled Noto Serif CJK display type, warm neutral UI, quiet deck structure,
and semantic combat accents. Keep physical collision coordinates on the floor;
projectile `visual_offset` connects the initial drawn position to the painted
muzzle without changing swept collision behavior. Equipment shares actor y-sort
and fades when it occludes the player. Boss framing follows both combatants.

Authored WAV cues are generated offline by `tools/make_audio.py`, preloaded and
played through the existing twelve-voice pool. No runtime synthesis allocation
was added to weapon attack paths. No external asset service is required.

## Verification

`tests/presentation.gd` checks all eight orientations, visible versus physical
projectile origins, occlusion, camera limits and boss status. `tests/performance.gd`
requires native rendering, records wall-clock percentiles and forty restart
cycles. `tests/playthrough.gd` drives normal player actions with no damage/health
overrides; it is explicitly a bot, not a human playtest. All tests disable player
save access. `tests/playtest.gd` offers an interactive isolated session.

## Consequences

The headless wrapper now has eight suites; rendered performance is a separate
acceptance command. Do not equate headless frame speed with GPU performance or
bot success with player usability. Art, fonts and audio reside inside the Godot
project and are exported with the Mac application. The legacy browser game,
Pages allowlist and unrelated work remain outside this change.
