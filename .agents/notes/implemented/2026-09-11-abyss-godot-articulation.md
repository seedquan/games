# Native eight-direction articulation and textured held weapons

Status: implemented; broader production acceptance remains open.

## Decision

Reuse the original game's eight separately authored alpha part atlases, copying
them into `abyss-protocol-godot/assets/rig/`. Transfer their calibrated source
crops and pivots to `rig_data.gd`; implement native GDScript projected joints in
`android_rig.gd`. There is no runtime dependency on the HTML renderer or `output/`.

The renderer uses eleven textured parts per body. Walking phase advances from
actual displacement after `move_and_slide`, settles when blocked, and does not
advance during a dash. Facing and locomotion direction remain independent.
Projected foot contact timing adapts to speed, while direction-specific ground
calibration keeps the stance near the collision body's feet. This is projected
2D articulation, not a fully three-dimensional anatomical skeleton.

The weapon attaches to the painted primary palm. Firearms and bows solve both
arms against calibrated receiver/string targets, including shortened projected
forearms when the bow is drawn near the shoulder. Recoil moves hands and weapon
together; the weapon drawing must not apply a second recoil offset. Existing
gun/bow atlases and grip metadata are local project resources.

## Verification

The animation suite tests the actual movement caller, wall-stopped gait and dash
phase, all facing/movement combinations for finite nondegenerate transforms, and
primary/support palm attachment across weapons, charge and recoil. The native
Mac pose sheet was rendered and inspected across all eight headings for standing,
walking, rifle and drawn bow. Existing seven suites passed before the final
textured-weapon update; that update also passed native animation checks. The next
full verification/export must include it.

Screenshots and delivery gates are tracked in `docs/production-readiness.md`.
Enemy animation, projectile presentation, environment depth and complete gameplay
acceptance are still unfinished. Nothing was staged, committed or published.
