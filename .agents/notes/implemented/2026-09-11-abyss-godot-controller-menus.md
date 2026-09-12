# Controller menu navigation and keyboard-capture cancellation

Status: implemented

## Context

Existing input checks covered controller resume, combat actions and disconnection,
but did not traverse the complete menu flow. Keyboard capture returned early from
the global input handler, so controller B and Start could not cancel it despite
their usual menu behavior. Rebuilding settings also focused Back rather than the
operation waiting for a key.

## Decision

While a keyboard binding is being captured, B or Start cancels capture, preserves
bindings and remains in settings. Other controller confirmation/navigation events
are consumed until capture ends, so they cannot activate another menu. Mouse
navigation and keyboard capture retain their existing behavior. Focus the pending
operation and describe controller cancellation in its Chinese prompt.

## Verification design

The production suite computes a route through Godot's directional focus graph,
then dispatches each D-pad step and verifies the resulting focus. It never calls
grab_focus or button signals to reach or activate menu targets. It visits all
armory entries, selects the last weapon, changes an audio slider, cancels keyboard
capture with B/Start, reads the scrolling guide, buys a permanent upgrade, shops,
chooses recovery rooms, advances all six story beats, and restarts from victory.

This fixture gives itself purchase currency and resolves combat directly. It is
a menu/input integration test, not a balance test or human/physical-controller
playthrough. All player persistence is disabled. Hardware and first-player
acceptance remain separate gates in docs/production-readiness.md.

Before the fix, 203 checks completed with exactly two failures: B/Start failed to
cancel capture. After the fix and added focus/guard/purchase assertions, all 211
headless checks pass; native rendering passes 213 checks and its capture-state
screenshot was inspected. The final 0.9.4 package passes all nine source suites,
28 release checks and separate-process storage write/read checks (11/19), both
headless and rendered. Records and checksum are in the project readiness document.
