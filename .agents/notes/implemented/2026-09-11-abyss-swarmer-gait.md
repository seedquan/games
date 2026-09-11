# Articulated swarmer locomotion

Status: implemented.

## Context and decision

The low-profile four-legged swarmer previously rotated a single still sprite as it moved. A matching overhead body and two leg segments now share a 768×512 embedded WebP atlas (37,104 encoded bytes, 1.5 MiB decoded). The built-in image generator produced the parts; a second pass supplied genuine alpha after the first output painted a checkerboard. Alpha is preserved through resizing and WebP encoding.

Four two-bone legs alternate diagonal pairs. Each bone retains length 0.85 times the collision radius. The stride is 1.8 radii (about 5.7 cycles/second at the base 132.5 world units/second with radius 8), avoiding an initial overly short stride that would produce roughly 13 cycles/second. The stance occupies 62% of a cycle; Hermite recovery joins the linear stance with continuous position and velocity. Gait advances only by resolved displacement after AI, collision and separation. Spawn, freeze, shock and stagger lock animation; zero displacement and teleport-sized changes do not advance it. Heading follows actual movement with exponential smoothing. The renderer does not advance gait and renders nine cropped parts. Existing whole-sprite and procedural paths remain decode fallbacks.

## Alternatives and limits

A time-only gait would keep stepping into walls. Stretching the entire old sprite would not articulate its legs. World-space foot targets would better eliminate sliding during sharp turns, but would require additional state and reach recovery; this implementation locks straight-travel stance velocity while turning remains approximate. Stopped actors hold their current pose, including a raised foot. No AI, collision, damage or save rules changed. Other grounded enemies still need articulated locomotion.

## Verification

93 focused render/performance checks pass. New checks cover displacement and frame-step equivalence, zero-motion and status locks, eight headings, stance velocity, contact continuity, fixed bone lengths throughout the cycle, bounded atlas crops and render-only state invariance. Actual NAPI Canvas specimens exercise all eight directions, with a 60 FPS animation artifact. Isolated browser combat preview adds a 48-swarmer scene for release verification. Short desktop samples cannot establish whole-run or physical mobile performance.
