# Committed melee traces and weapon follow-through

Status: implemented.

## Context

All seven melee forms shared one rotating arc in player-local space. Turning or moving after the immediate damage evaluation moved that arc to an area that had not been hit. Lance, maul, and whip also used the same wrist swing. A headless Godot runtime probe confirmed a 180-degree aim reversal rotated their follow-through by 180 degrees. The suspected ranged muzzle lag was dismissed: fire already synchronizes the rig before constructing projectile origins.

## Decision

Capture aim on each successful attack and retain it for the 180 ms melee follow-through. Input aim, movement, skills and collision remain live. The next attack captures its own aim immediately. Rig pose, palm and held weapon have one transform owner; the obsolete temporary placement in weapon tick is removed.

Create a short independent melee trace in World/Effects at the resolved attack's position and facing. The quiet footprint samples the original reach/arc and clips to solid cover once. Material strokes carry a fixed hand offset, analogous to projectile presentation, while collision remains in the floor plane. The trace has no damage logic and never follows the owner. Lance thrust, hammer chips, retracting chain and alternating twin-blade strokes express existing behavior; the third twin strike highlights the actual double hit. No new damage, cooldown, hit-stop, input lock or save fields.

World pause freezes traces and the explicit state guard covers deferred pause changes. Existing room/restart cleanup owns disposal; finite lifetimes bound active effects. Flash set to zero removes highlights and freezes the flourish shape while retaining the finite, fading contact indicator. Core body movement remains functional animation.

## Verification

The dedicated real-scene suite covers original damage/cadence, eight headings, finite bones/palm attachment, resolved cover, paired attacks, true physics input reversal, pause, resume and room cleanup. Native captures reuse the same live fire caller and renderer. The performance suite has an opt-in --melee mode that cycles the seven forms for both actors amid the existing dense guardian scenario. The native test leaves a short real-time interval after freeing the game so the Dummy audio mixer can release its last playback; this is test teardown only.

Release-specific results and limitations are recorded in docs/production-readiness.md. Visual inspection uses external JPEGs no larger than 1024 pixels and 256 KiB; no source map is opened for inspection.

The additional normal-rule lance comparison exposed a test reproducibility gap: the room generator was seeded but enemy attack offsets used a randomized global RNG. The playthrough driver now fixes the global initial seed too, without changing player/enemy rules. Initial randomized samples and subsequent comparisons are retained separately; a single bot death or victory does not establish human difficulty or a regression by itself.

The driver also waited for a render frame after every physics frame, coupling accelerated bot reaction time to rendering throughput. It now updates input each simulated physics step and records input updates/clock. This changes the measurement driver, not game balance. Even with a fixed initial seed, cosmetic shake consumes the global RNG on render frames, so separate processes are not deterministic replays. Treat paired samples as diagnostics, not a controlled claim of difficulty improvement. Version 0.17 completed the first guardian with the corrected driver; an isolated 0.16 control failed in chamber two. Earlier render-clock runs produced the opposite result. All samples remain available in the release QA directory.
