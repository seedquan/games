# Godot aiming ownership and isolated release persistence

Status: implemented

## Context

The previous mouse inactivity timeout could transfer aiming to assistance during
a stationary held attack or a long charged shot. Release checks also disabled
persistence, so they could not demonstrate that an exported application restored
settings and a purchased shop checkpoint after process termination.

## Decisions

- Track mouse, stick, assist and movement-heading aiming explicitly. Held mouse
  buttons and their release retain pointer ownership; disabling assistance keeps
  mouse direction. Preserve facing when the pointer is too close to the player.
  Show the current mode in the HUD and a combat cursor for mouse input.
- Clear the custom cursor in HUD teardown before the rendering server exits.
  Input otherwise retains its texture, producing a native OpenGL resource leak.
- Keep `--verify-release` save-free by default. Persistence verification requires
  an absolute fixture directory containing `.abyss-release-fixture`, with an
  explicit write/read stage. Reject malformed flags before player files load;
  never fall back to ordinary save locations. The export script creates the
  disposable directory and runs two independent release processes outside source.
- First write a real loadout, preferences, binding, earned progress and purchased
  shop checkpoint. Then cold-load them, compare the transaction state, reject a
  duplicate purchase, finish the campaign and check the durable ending.
- High-contrast text is an optional saved setting, applied to existing and future
  labels. Retain each label's base color so disabling the option restores its
  intended appearance rather than repeatedly multiplying colors.

## Alternatives and consequences

Disabling assistance globally would remove a useful keyboard/controller aid.
In-process save reconstruction remains useful, but cannot replace independent
release processes. Reusing normal player data for QA was rejected because tests
must never affect actual progress. These fixture flags are local test entry
points; normal startup behavior is unchanged.

## Verification

The new aiming suite dispatched real mouse events and reproduced four failures
before the fix; all six checks then passed headless and with native rendering.
Native production checks passed 63 assertions, including live contrast toggling.
Cursor teardown removed the observed texture/RID leak and exit error. Release
storage checks passed 11 write and 19 read assertions in separate processes.
The final 0.9.2 package passed all nine source suites and the same release checks
in both headless and native rendered processes, with no exit errors. Its checksum
and validation are recorded in `abyss-protocol-godot/docs/production-readiness.md`.

The focused headless wrapper now has nine suites. Hardware controller acceptance,
Intel validation and new-player playtesting remain separate from these checks.
