# Abyss canvas raster budget

Status: implemented; measured improvement requires deployed comparison.

## Evidence

At a fixed 3440×1440 viewport, a 240-frame hub sample measured 16.1 FPS,
83.3 ms p95 intervals and 0.41 ms mean JS render submission time. A shadow-only
bypass at the same size measured 16.6 FPS and 67 ms p95. At 1280×720 without
shadows the same hub reached 60 FPS. Canvas area is therefore the leading
bottleneck; shadow blur alone did not explain the large-screen regression.

## Decision

Cap canvas backing resolution to 1.5 million pixels, retaining CSS dimensions
and world/input coordinate mapping. This trades some high-resolution sharpness
for bounded raster cost. Reduced/off effects now disable shadowBlur. Default
new settings to reduced effects (no scanlines, gentler shake); retain explicit
saved full-effect preferences.

Opt-in `?profile=1` exposes a rolling frame sample in the canvas data attribute.
No network telemetry or persistent data is collected. `shadows=off` only acts
with profiling enabled. Render submission time is not total GPU frame cost.

## Verification

12 focused render/performance tests passed, including failing-before checks
for pixel-budget enforcement and reduced/off shadow behavior. Inline syntax
and diff whitespace checks passed. Measurements are browser/scene-specific;
they do not establish performance across all devices or boss fights.

## Deployed follow-up

At the same 3440×1440 viewport, the 1.5 MP cap and reduced defaults measured
53.7 FPS, 33.4 ms p95, and 0.30 ms mean render submission time (240 hub frames).
This is substantially better but still has slow frames. Add a bounded downshift:
a three-second window with >8% frames above 22 ms reduces the pixel budget by
20%, stopping at 0.96 MP. Hidden-tab samples are discarded; there is no automatic
up/down oscillation during a run. This changes only rendering resolution.
The additional controller regression passes (13 tests total).
