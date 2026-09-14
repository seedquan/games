# Native stress timing distinguishes simulation observation from rendering

Status: implemented

## Context

The 0.23.0 native QHD co-op/refit stress report failed its 25 ms P95 envelope
at 25.669 ms. The fixture awaits a physics frame and then a process frame for
each observation. On this 120 Hz Mac display, about two rendered frames can
occur per 60 Hz physics observation. Calling that interval a rendered frame
conceals the difference between simulation cadence, drawing and display waits.

Temporary instrumentation measured arena steering at about 0.033 ms and all
enemy physics callbacks at about 0.488 ms per observation. A two-second native
stack sample spent 644 of 1,474 main-thread samples in AppKit display-sync
waiting beneath OpenGL buffer swapping. This rules out the proposed navigation
cache as a justified response to this sample; it does not prove a universal
frame-time cause. No navigation, enemy, collision or rendering behavior changed.

## Decision

Keep the historical `frame_ms_*` observations and their P95 <=25 / P99 <=50 ms
gate. Additionally collect `RenderingServer.frame_post_draw` callback intervals,
apply the same envelope, and require the complete 900-observation window and
at least 899 rendered intervals. A render callback is engine completion, not a
timestamp of presentation by the OS compositor or physical display.

Record display refresh, VSync mode, frame limit, physics rate and physics/process
frame counts. `--trace-frames` retains ordered observer/render intervals and
viewport CPU rendering measurements, without putting long traces on stdout.
Only the stress fixture enables those measurements; no normal gameplay hooks
remain. Warmup and the 40 restart/cleanup cycles are outside timing capture.

All reports gain timestamp/PID suffixes and print their actual path, so repeat
runs do not replace release evidence. Reports, exploratory instrumentation and
stack samples remain local under ignored `builds/qa/`. The old failed report is
preserved unchanged.

## Alternatives and limits

Do not lower enemy pressure, remove visuals, loosen thresholds or cache paths
without measurements showing that those changes address the problem. VSync off
was a command-line diagnostic in an isolated save-free process, not a shipped
setting or a performance acceptance result for the default configuration.

The diagnostic default-VSync run reproduced the original gate failure at
25.117 ms P95 while render callbacks had 14.710 ms P95 and CPU rendering had
3.081 ms P95. The VSync-off comparison measured 20.720 / 7.520 / 2.380 ms
respectively. Native timings vary with scheduling and this limited comparison
does not prove a gameplay speedup. A future rendering/pacing change needs an
actual default-configuration comparison and visual/input verification.

## Verification

Both native runs completed 900 observations, thousands of rendering callbacks
and 40 restarts, with zero orphan baseline. Independent Python recomputation
checked every reported quantile against its retained ordered trace. The default
run keeps its one historical-envelope failure; the diagnostic VSync-off run
passed 88 checks. Runtime hashes and 275 unrelated worktree files are unchanged.
Full source regression and subsequent default/no-trace evidence are recorded in
`abyss-protocol-godot/docs/production-readiness.md`.
