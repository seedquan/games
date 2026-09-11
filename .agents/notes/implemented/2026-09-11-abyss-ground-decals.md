# Walkable terrain decals

Status: implemented.

## Context and decision

The reduced-effects renderer drew decorative liquid and rock patches as large solid polygons that looked like unfinished obstacles beside the painted characters and cover. These features have no blocking collision; shallow liquid alone slows grounded players by 18%, while dashes ignore it.

A six-cell 768×512 WebP atlas replaces the lake and rock drawing when decoded, with four coolant/oil palettes and two flat metal/mineral debris patches. Encoded size is 179,856 bytes; decoded footprint is 1.5 MiB. The built-in generator supplied genuine alpha, preserved through downsampling and compression. Stable feature rotations vary the overhead decals. Each feature is one cropped image draw, below cover and actors, with no canvas filters or dynamic glow. Baked details also render on touch with effects off; unavailable assets retain the previous shapes.

Shallow pools carry a thin dashed circle at exactly r × 0.82, matching terrainSlowFactor. Deep decorative pools and debris have no circle. The cue is available across quality levels and in fallback paths. This makes the circular gameplay boundary explicit despite irregular spill edges. No generation, collision, pathfinding, damage or save rules changed. Culling includes the rotated sprite extent.

## Alternatives and limitations

Raised boulders would falsely suggest collision, so the art uses floor-level flakes and debris. Existing solid-cover assets are not reused here. Per-feature raster caches would add memory without reducing the one-draw decal cost. Void and final abyss share the violet liquid cell, and rock variants are reused across sectors; further art variation is still possible. Flora remains procedural and is separate work.

## Verification

96 focused checks pass. New coverage checks all biome cells, crop bounds, unchanged feature state, exact shallow slow boundary/dash exemption, non-shallow cue exclusion, and desktop versus touch/off dispatch and fallbacks. Actual Canvas specimens show all five palettes on the embedded floors. An opt-in ground preview cycles through five regions for browser verification. Short desktop samples do not establish mobile or whole-run acceptance.
