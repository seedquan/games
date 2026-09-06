# A continuous 2D pixel town, not location cards

- **Status:** implemented
- **Date:** 2026-09-05
- **Category:** presentation architecture

## Context and design direction

The creator explicitly requested a town that looks like a 2D pixel game,
clarifying that the whole town should share that treatment. The earlier six
cards with pixel illustrations did not meet that request. This is an observer's
game world: the user watches independent residents and intervenes in conditions,
rather than controlling a resident's footsteps.

## Decision

Promote the town into a full-width stage above the existing controls/history
workspace. Render terrain, six buildings and seven real road links in one
480-by-320 logical space. Inline SVG and full-body sprites use the existing
theme variables; no image service, font download, framework or runtime asset
request is introduced. Zoom/pan belongs to a containing viewport.

Keep rendering separate from engine state. Project only the visible place
stocks, crop/shelter state and coarse resident identities/locations into the
scene. Reuse cached terrain markup; animate only actual adjacent moves after
the engine commits them. Visual motion never advances time or schedules model
requests. Pausing, restored world identity, viewpoint changes, hidden pages and
reduced-motion preferences cancel interpolation and show the committed state.
Actors newly entering visibility do not reveal their previous hidden location.

Use real buttons over the scene for places and residents so clicking, focus and
keyboard selection remain available. Physical resources are explained in one
selected-site strip, rather than six repeated panels. Decorative terrain does
not add new resources or physics.

## Non-obvious clipping invariant

The inner map must use `overflow: clip`, not `overflow: hidden`. Actor anchors
are full-scene transform layers. Hidden overflow still creates a scroll
container, so focus/scrollIntoView can scroll the inner map independently of
the intended outer camera, especially after viewport resizing. This produced a
thin strip of scenery followed by blank space on phones. `clip` prevents that
unintended inner scrolling; the outer viewport alone handles pan/zoom.

## Verification

The existing Node suite covers projection privacy, exact road topology,
full-body sprites, stable motion paths, pause/restore/reduced-motion behavior,
unknown-origin visibility, zoom without engine mutations and the clipping
invariant. The standalone HTML is rebuilt with all four browser modules.
Isolated headless Chrome uses only a mock bridge and rule actions to inspect
desktop/mobile scenes, actual movement and cancellation, provider controls,
camera behavior and reduced motion. No paid inference is used.

## Boundaries

The world engine, provider adapters, budgets and AI trust boundary are
unchanged. Existing saves and per-resident provider choices remain compatible.
The existing local service can serve the rebuilt page without restarting or
resetting its request budget. Nothing is committed or deployed.
