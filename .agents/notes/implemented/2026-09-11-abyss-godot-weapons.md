# Native base weapon roster and collision verification

Status: implemented; this is one part of the ongoing Godot remake.

## Context

The first Godot slice only had one melee attack, while the browser original's
18 base forms define much of its combat variety. A weapon selection screen
without those mechanical differences would not advance the remake faithfully.

## Decision

Keep a data catalogue (`scripts/weapons.gd`) and a separate player-owned
`Weapon` node. The controller owns combo/charge and returning-glaive state;
the player still owns shared cooldowns, run damage and the independent plasma
ability. Introduce actual projectile, melee, chain, returning and delayed-field
families. The armory exposes all 18 base forms before a run, and preserves the
selected form across restarts within the same game process. Combat forbids swaps.

Each projectile tracks hit bodies and physics RIDs. Its swept step can process
multiple penetrated targets; walls terminate it. A returning glaive clears the
hit set once at the transition to return flight, allowing two hits per target
without continuous overlap damage. Fire pools and gravity fields belong to the
world and are removed on restart/room transition. All attacks check solid cover.

Native ice freeze is tracked separately from generic stagger, so thermal shock
only consumes an actual ice freeze. Shared plasma carries no innate weapon
element. Universal enchantment stacking is now implemented in the Chinese
campaign Note. Original weapon aspects and exclusive boons remain unported.

Menu transitions defer collision-process changes, but the deferred callback
reads the current state. This prevents a queued old pause/title transition from
disabling a just-restarted run. Tab's title-armory shortcut runs before GUI
focus navigation consumes the key.

## Verification

The real-scene weapon suite checks all 18 forms, damage, cover, charge/release,
flurry cadence, pulling, chain limits, outbound/return hit counts, sustained
fire, pellet/arrow spread, ice/thermal/fire behavior, selection and cleanup.
Final `python3 verify.py` passed import, 35 run checks and 123 weapon checks
(158 checks total), including the Tab input route. Native inspection covered armory
selection, selected-weapon description, starting with Longbow and distinct
primary/plasma inputs. Selected and primary buttons now use dark focus text
on their bright fill; this was also inspected in the running native window.

Godot may return exit 0 on import despite script errors. `python3 verify.py`
now requires error-free output and successful test summary markers, and bounds
each engine subprocess to 60 seconds. No tests write user saves. No exports,
publication, unrelated simulation tests or original-HTML changes are involved.
