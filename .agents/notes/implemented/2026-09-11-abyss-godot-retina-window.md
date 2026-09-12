# Godot default window dimensions on Retina

Status: implemented

## Context

System UI inspection showed the original 1280x800 window at only 640x400 desktop
points. The local Mac reports scale 2.0, DPI 220 and screen size 2992x1934:
Godot's native window API uses physical pixels. Merely checking that the window
fit the usable screen had missed the resulting small text and controls.

## Decision

Express the intended 1280x800 desktop window and its edge margins in points,
multiply by the current screen's scale, then fit and center within that screen's
physical usable rectangle. Keep the 1440x900 reference canvas, aspect ratio and
fullscreen preference. The current Mac gets approximately 2550x1594 pixels,
1275x797 points, instead of a half-size window.

## Verification

Native production now also rejects a default narrower than 960 desktop points
when the current screen has sufficient room, in addition to its screen-boundary
check. All 64 native production assertions pass and the default title screenshot
was inspected. This is a display-coordinate regression; headless checks cannot
prove it and do not pretend to.

The performance fixture accepts `-- --desktop-size` to render at the actual
default size and records measured pixel dimensions and scale. On the M4 Pro,
900 samples at 2550x1594 yielded p50 16.727 ms, p95 23.143 ms and p99 25.478 ms;
40 restart cycles returned to baseline with zero orphan growth. All 44 assertions
passed, with no runtime or renderer errors. The smaller 1440x900 evidence is
preserved separately; it is not used as proof of Retina-size performance.
