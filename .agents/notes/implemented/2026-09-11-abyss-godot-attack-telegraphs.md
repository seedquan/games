# Godot attack warnings match damage geometry

Status: implemented

## Context

Native acceptance found that the stalker's warning used radius 85 and half-angle
1 radian, while its actual attack reached radius 105 and an angle of acos(0.1).
This left damaging locations outside the visible warning. Bosses also reused one
pulsing ring for aimed spread, targeted ground attacks and radial projectiles.

## Decision

Use shared melee reach and half-angle values for the closed warning sector and
the existing hit predicate. Keep damage, timing and reach unchanged; enlarge the
warning to show the actual threat. Bright edges and a faint fill communicate the
sector without depending exclusively on hue.

Derive the upcoming boss pattern before advancing its sequence. Use the same
direction list for drawn arrows and fired projectiles, including 12/16-ray final
boss phases. Distinguish the warden's targeted ground attack with three rings;
the actual placed hazards retain their independent 0.95-second escape warning.
The boss HUD names the attack during windup, and the operation guide explains
the distinction between attack preparation and actual ground damage zones.

## Alternatives and consequences

Shrinking damage to the old warning would silently change balance. Keeping only
a generic boss ring would continue hiding usable information. These changes
preserve enemy attack cadence, projectile counts, damage and campaign behavior.
The native project still has nine focused source suites; the extra assertions
belong to presentation because they connect visible warnings to actual combat.

## Verification

The presentation suite samples inside/outside reach and side angles in eight
orientations, compares the CanvasItem polygon to actual player damage, and checks
each warned ray against a released projectile. It checks the full delay on ground
hazards and the HUD's current attack label. All 523 assertions passed headless
and in a native Mac window, with no renderer or exit errors. Native melee, spread,
ground and radial warning screenshots were visually inspected.

System mouse/keyboard operation separately verified scrolling to the bottom of
the guide, Escape navigation and menu exit in an isolated playtest. This is agent
UI testing, not a human new-player study. Current package verification is recorded
in `abyss-protocol-godot/docs/production-readiness.md`.
