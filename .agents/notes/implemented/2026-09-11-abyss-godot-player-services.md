# Godot player settings, input and resumable rescue

Status: implemented player services; production delivery remains in progress.

## Context

The user asked to bring the remake to production quality and selected Mac as the
delivery platform. The initial native project had no preferences or continuation;
it synthesized each sound during combat, and restart discarded the current run.

## Decisions

- `settings.gd` stores validated preferences separately from progress, with staged
  writes, backup recovery and future-version protection. `controls.gd` owns
  keyboard remapping and explicit controller gameplay/menu mappings. Do not rely
  on Godot's built-in UI actions containing controller events: this engine only
  supplied keyboard defaults. HUD shortcuts use the current binding/device.
- Gate held combat buttons at menu exit, then rearm after release. Fresh input
  after a new run remains valid. Device switching ignores brief mouse-motion noise
  after controller events, while intentional mouse clicks/keys switch immediately.
  Application focus loss and controller disconnection pause combat.
- `sound.gd` precaches authored cues and uses 12 reusable players plus one local
  ambient loop. Both gain and mute apply to real audio output. No runtime download
  or third-party recording is used.
- Profile schema 2 saves permanent progress and the safe-point checkpoint in one
  ConfigFile transaction. Schema 1 migrates; future schemas stay read-only. A
  separate checkpoint file was rejected because it could diverge from core rewards.
- `run_save.gd` stores bounded player stats, canonical item identifiers, route
  recipes and RNG state. Room geometry is reconstructed from the recipe. It does
  not deserialize arbitrary Nodes/resources. Invalid checkpoints preserve the file.
- Auto-save at chamber entry and safe decisions. Combat continuation starts paused
  at the chamber entrance; partial combat is intentionally replayed. Do not call
  `next_room` during restore: it would heal rest rooms and append history again.
  Clear the checkpoint on death/victory. Restart requires an in-game confirmation;
  returning to the dock preserves the last safe point.

## Verification

Original physics, weapons, campaign and Chinese story suites pass. Added production
checks dispatch physical keyboard/controller events, test setting corruption and
backup recovery, exercise pause/confirm/focus behavior, and bound the sound pool.
Native Compatibility rendering on Apple M4 Pro has exercised the new menus and
screenshots at desktop sizes. Physical controller hardware is not yet verified.

The checkpoint suite automatically writes each transition to an isolated path,
destroys and recreates the game from disk at every safe point on both routes,
reaches both endings and verifies no duplicate rewards, purchases or healing.
It also covers legacy migration, future/invalid records and missing-primary backup
recovery. ConfigFile's textual float precision is compared approximately; RNG
state and integral currency comparisons remain exact.

Source and reports: `abyss-protocol-godot/docs/production-readiness.md`.
No commits, upload, Pages changes or publication are authorized by this work.
