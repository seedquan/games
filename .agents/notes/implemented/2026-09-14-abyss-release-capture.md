# Release screenshots render explicitly when native windows stop drawing

Status: implemented

## Evidence

The 0.27.0, 0.28.0 and 0.29.0 macOS release runs intermittently reached the
55-second storage verification deadline. The same ZIPs passed independent
write/read runs. Those original failures remain; their logs do not identify
which awaited operation stalled, so this finding does not retrospectively
prove the cause of every historical timeout.

A minimal Godot 4.7.2 / macOS OpenGL probe reproduced a concrete cause:
minimizing the native window stopped automatic draw callbacks and retained
the old red framebuffer after the scene changed to green. An explicit
`RenderingServer.force_draw(false)` completed a draw and produced green pixels
without restoring or focusing the window. A subsequent blue update also
rendered correctly. The probe changes only its own disposable window.

`tests/release_capture.gd` invokes the actual release verifier's `snapshot()`
method with a disposable output directory. On the old implementation, both
minimized captures wait until the 2.5-second test watchdog restores the window:
11 checks, 2 failures. The explicit-render implementation passes all 11 checks,
including changed framebuffer pixels. The watchdog allows the old coroutine
to unwind; it does not relax the production verifier's 55-second deadline.

## Decision

After the existing physics/process frame wait, explicitly draw the current
scene without a buffer swap, then read the completed framebuffer. Do not await
an automatic OS-scheduled draw for these opt-in storage screenshots. Keep the
headless early return, existing screenshot checks, normal game rendering,
save-path validation, fixture isolation and process deadlines unchanged.

This is release verification infrastructure, not a frame-time optimization or
a new gameplay behavior. Delivery validation includes native regression,
complete minimized storage runs, full source suites and Mac/Windows packed
release evidence. The new capture test requires native rendering and runs separately
from the 37 headless-compatible source suites.
