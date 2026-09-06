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

## Cached radial lighting

Repeated radial gradients now use reusable 128×128 canvas sprites keyed by
color, capped at 64 entries (4 MiB of pixel storage). Radius and opacity remain
per-draw values; additive blending is preserved. This removes repeated gradient
construction without reducing game simulation or input frequency.

Profiling resets its rolling sample on scene, pause, effect-level, or backing-size
changes, and reports viewport size and entity counts to prevent mixed samples.
15 focused tests passed, including cache reuse, eviction bounds, alpha
restoration and profiling sample resets. No additional FPS improvement is claimed before browser sampling.

## Dense combat follow-up

The isolated 48-enemy scenario exposed a remaining raster bottleneck at
3440x1440: 39 remaining enemies / 23–26 projectiles sampled 37.9–38.5 FPS,
P95 33.8–33.9 ms, even after world resolution settled at 1514x634. Disabling the
separate UI layer still produced ~38 FPS at the same viewport. In the same live
room later, off effects reached 60 FPS (29 enemies / 6 projectiles), while
returning to reduced dropped to 49 FPS (28 enemies / 6 projectiles). These are
randomized exploratory samples, not a controlled deterministic benchmark.

Reduced still enabled every secondary additive bloom halo and up to 22 world
lights. Restrict those secondary halos to full and lower reduced world lights to
8; actual projectile/actor shapes, warnings, hits and collision logic are intact.
Full retains its existing appearance and off retains no world lights. This is a
bounded rendering-quality adjustment, not a simulation load reduction.

32 focused checks pass, including preset-specific bloom/light behavior and no
secondary light draw in reduced. Syntax and whitespace pass. Public combat
re-measurement and visual comparison follow deployment; do not claim 60 FPS
until those measurements exist.
