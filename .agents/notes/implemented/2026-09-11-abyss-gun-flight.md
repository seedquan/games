# Firearm muzzle and ballistic projection

Status: implemented.

## Decision

Rifle rounds, scatter pellets/slugs, and rail discharges now originate visually at their calibrated painted muzzles. A shared rigHeldPoint maps a local weapon coordinate through the actual two-hand grip, recoil, gait bounce and facing-specific ground anchor; bows reuse it with their nocked arrowhead. It runs at firing only. Each ballistic round freezes two offset scalars and a projected-art flag, reset on pool acquisition. Owner movement, weapon changes, wall bounces, piercing and target ricochets do not move the flight plane.

Muzzle sparks/lights, tracer particles, direct hit/shield/pillar contact cosmetics use the same projection. Rail beam endpoints and direct contact sparks are translated together, while hitscan selection, damage, knockback, barrel interaction and siege-area ground markers retain simulation coordinates. Rail beam layers are now stable straight segments with bounded lifetime fade, instead of reusing lightning's random vertices on every frame. Other lightning retains its existing rendering.

Projected rounds are narrow 7/5-unit tracer shapes with the leading edge at the muzzle endpoint. They use the cached bloom and avoid the previous shadow filter. Gun recoil is normalized to actual rifle/scatter/rail/rapid-rail durations. Existing inline raster assets and offline self-containment are unchanged.

## Verification and limits

127 focused checks pass. New tests compare actual Canvas-transformed muzzles with computed origins across eight headings, three body sizes and moving/recoil poses; normal dispatch covers rifle/burst, scatter/slug and rail/rapid rail. Tests exercise owner movement, pool reuse, wall/pillar collision, piercing, ricochet, rail target/damage equivalence, unchanged siege ground zones, fixed beam endpoints and bounded tracer geometry. Previous bow release tests pass after sharing the projection helper. One test initially failed due to cross-VM object prototypes; serializing the equivalent plain nova records corrected the comparison.

Actual runtime Canvas specimens of all three guns at +16.7ms were inspected across eight directions. Inline syntax, whitespace and embedded-asset equality checks pass; zero external URLs. No unrelated projects were modified or tested for this change. Browser release/FPS observations are recorded separately in the PR and output review log.

This remains fixed per-shot 2.5D projection, not general target-height interpolation or occlusion. The physics aim and smoothed visual aim may differ during rapid turns; directional weapon views, enemy gait, caster/melee assets and full-run/mobile/gamepad acceptance remain separate unfinished work.
