# Static floor raster cache

Paint the floor's base color, embedded texture, panel grids/decals and center
light once into a reusable canvas. Camera motion crops that image; it no longer
replays all static paths and the large radial gradient every frame. Walls remain
live so their glow and boundary clipping retain their original behavior. Terrain,
actors, attack warnings, damage effects and dynamic light are not cached here.

The surface uses native world resolution, capped at four million pixels (16 MB
RGBA, excluding browser/GPU overhead). Only one surface is retained. Its key
includes arena dimensions, biome, effects level, touch detail and texture-ready
state. Camera movement, zoom and adaptive world DPR do not trigger reallocations.
`floorCache=0` selects the direct renderer for comparison or rollback.

33 focused checks pass: reuse, content invalidation, late texture readiness,
pixel-budget bound and context restoration after a failed cache paint. The
actual rendering functions were compared with the bundled Canvas implementation:
at native scale, mean channel error was below 0.00005/255 across three biomes;
at 1.55x zoom, mean error was 0.56/255 with maximum 13/255. The latter includes
expected interpolation differences from scaling cached vectors. Both rendered
images were inspected; no geometry shift or missing floor elements were seen.
These are offline rendering results, not browser performance measurements.

Source/reproduction and comparisons are in output/abyss-animation-review/:
verify-floor-cache.cjs, floor-pixel-comparison.json, floor-direct.png and
floor-cached.png. Inline syntax and whitespace pass. Public browser validation
and dense-combat measurement follow deployment. Full directional animation and
production art acceptance remain open.
