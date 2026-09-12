# Independent Godot remake of Abyss Protocol

Status: implemented initial foundation; extended by the weapon and Chinese campaign Notes.

## Context

The user requested a new project under `games` to remake Abyss Protocol in
Godot. Existing Abyss Notes describe the browser game's renderer and do not
establish a native engine architecture. The original HTML remains independent.

## Decision

Create `abyss-protocol-godot/` as a standard Godot 4 / GDScript 2D project with
Compatibility rendering. Use editable scenes for the main world, player,
hostiles and projectiles; keep gameplay, UI and arena scripts separate. The
initial loop is four combat stages with upgrades followed by one boss stage.

Copy five existing local art assets into the project. No runtime references to
the ignored/untracked `output/` art workspace are permitted. Keep native Godot
UID/import metadata; ignore the `.godot` cache, builds and export credentials.

The project is source-only and local. Do not add a dead link to the browser
arcade hub or deploy Godot sources through Pages. A future browser release
requires a Web export packaging decision and explicit hub/allowlist changes.

The alternative of porting all existing HTML mechanics at once was not chosen:
this first playable establishes the native loop before weapon variety, co-op,
animation, persistence and richer rooms are introduced. It is not feature parity.

## Consequences

The project now uses Godot 4.7 format; the installed 4.7.2 engine is the
verified runtime. SceneTree smoke checks exercise real scene instances and
physics without extra test dependencies. Projectile motion uses a ray sweep
in addition to overlap events so cover intercepts the full traveled segment.
World process disabling is deferred because death may occur inside an Area2D
collision callback; menu state changes immediately.

## Verification

Godot 4.7.2 headless import and main-scene startup passed. The smoke suite
passed 35 checks covering movement, walls, directional attacks, skill gating,
damage, projectile hits/cover, pause, all upgrade paths, boss progression,
victory/death and restart cleanup, including lethal damage inside a projectile
callback. Native title, combat, skill input, death, restart and pause screens
were exercised on macOS with no runtime errors after the fixes. No exports or
other platforms were tested. Existing
terrarium/westworld changes and their build/test suites are outside this task.
