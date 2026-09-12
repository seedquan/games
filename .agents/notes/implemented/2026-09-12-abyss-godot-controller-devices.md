# Controller bindings accept nonzero device IDs

Status: implemented

## Context

Godot's new joypad input events default to device 0. The game's explicit
gameplay and menu bindings retained that default, so an OS-assigned device 1
or 3 changed HUD input mode but could not move, attack, pause or confirm.
Earlier tests also used the default device 0 and missed this boundary.

## Decision

Set `device = -1` on joypad button and motion bindings in `controls.gd`.
This is the Godot InputMap wildcard for any controller. Keyboard/mouse
bindings remain separate. The game remains single-player; it does not assign
different controllers to different players.

Production tests dispatch motion and button events on devices 1 and 3 through
`Input.parse_input_event`, checking actual player displacement, right-stick
aim, all five combat actions, pause and focused resume. The full controller
menu flow now uses device 3. Existing keyboard and device-0 checks remain.
The opt-in packed release verifier uses device-3 motion, pause and confirmation
instead of bypassing the device mapping with `Input.action_press` for movement.

## Verification

Before the fix, production reported 231 checks with 18 failures: both nonzero
devices failed movement, aim, five combat actions, pause and confirmation.
After the fix, headless production passed 231 checks and native OpenGL
production passed 233 checks with no errors. Logs are in
`/tmp/abyss-devices-before.log`, `/tmp/abyss-devices-after.log` and
`/tmp/abyss-095-native-production.log`. Final package evidence is recorded in
the project's `docs/production-readiness.md`.

These are synthetic controller events dispatched into real game and menu
processing. They do not establish physical controller connection, mapping,
drift or human playability. Player saves are disabled in the scene tests;
release storage tests use explicitly marked disposable fixtures.
