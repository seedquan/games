# Bounded map image inspection

Status: implemented

## Context

Map PNGs are roughly 2.6–3.0 MiB each. Four viewed map originals amount to
about 15.3 MiB if sent as Base64, before other request content. A local proxy
with a 16 MiB body limit can reject both inference and compaction requests.
This is an estimated image payload, not a captured failing HTTP request.

## Decision

The Godot project's agent instructions require disposable JPEG previews with
a 1024-pixel longest edge and a 256 KiB file budget before image inspection.
Fine calibration uses bounded crops with explicit coordinate transforms.
Original game artwork and import metadata remain unchanged.

## Alternatives and consequences

Starting a fresh task alone does not prevent repeated loading of originals.
Raising a proxy limit alone leaves repeated image growth unchecked. Replacing
runtime artwork with lossy previews would unnecessarily change game quality.
Preview generation adds a small inspection step; existing oversized task
history is not repaired by these instructions.

## Verification

Generated ten disposable map previews with macOS sips and checked every file
against the 256 KiB budget. Source hashes were checked around initial preview
generation. Reviewed the Markdown additions and ignore eligibility. No game
code, map assets, imports, player data, or proxy configuration was changed.
Gameplay suites were not run for this agent-documentation-only change.
