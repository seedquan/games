# A smooth miniature island with a locally bundled renderer

- **Status:** implemented
- **Date:** 2026-09-05
- **Category:** rendering architecture

## Context and decision

The requested presentation is now a spacious, cute miniature island, explicitly
not pixel or voxel art. The former software renderer's deliberately low-resolution
depth buffer is unsuitable for smooth rounded geometry and soft lighting.
This supersedes `../archived/2026-09-05-westworld-voxel-view.md`.

Westworld now owns pinned Three.js and esbuild dependencies, matching the
versions already used by terrarium without importing that project's packages
or modifying its files. The build embeds the entire browser bundle, styles and
Three.js MIT license into one HTML artifact. There are no runtime CDN, model,
texture, font or other asset requests. The source-build command now requires
`npm ci`; the compiled page and optional bridge do not require installed
rendering dependencies.

## Coordinate and rendering contracts

- `island-layout.mjs` owns physical ground coordinates, the organic coastline
  and winding samples for the same nine logical roads. The land footprint is
  over seven times the previous 480-by-320 board. Screen coordinates remain
  480 by 320 and are obtained only through an explicit projection.
- The shared home remains central and has a larger cottage and forecourt.
  Decorative groves, beach, pond, stream, bridge and pier add no resources,
  interactive location IDs or new simulation semantics.
- Three's orthographic camera is shared by geometry, DOM hit targets, resident
  motion and captions. The smooth SVG overview uses its own explicit
  top-down projection, not physical coordinates mistaken for screen pixels.
- Acquire WebGL2 before constructing the renderer; never acquire Canvas 2D
  first on that canvas. Unsupported or lost WebGL is visibly reported and
  switches to the smooth, non-pixel SVG fallback.
- Rendering consumes only the existing privacy-filtered scene projection.
  Roads sample actual committed movement. No decorative wandering, inferred
  speech, extra decisions, world-clock changes or model calls are introduced.
- Cache static geometry, instance repeated trees, bound drawing-buffer
  resolution, and request frames only for changes or finite committed motion.
  Dispose replaced geometry, materials and instance buffers. Theme colors
  derive from the existing Clawpilot tokens.
- Preserve `overflow: clip` on the transformed inner map. Place labels and
  residents remain actual accessible DOM buttons. Public speech remains
  available through the existing detail strip.

## Alternatives and consequences

Extending the software voxel rasterizer would retain its pixelated appearance
or require a substantially larger custom graphics implementation. External
models, CDNs and a cross-project package dependency would violate static
self-containment or ownership. The chosen bundle is larger, and 3D now needs
WebGL2; unsupported devices retain an explicit local SVG alternative.

The engine, save schema, seven-place graph, bridge trust boundary, provider
configuration and inference budgets are unchanged. Regenerating the artifact
does not require restarting the live bridge.

## Verification

The Westworld suite and regenerated artifact pass. Coverage includes organic
land area, reversible sampled routes, camera fitting, rounded geometry,
private-scene filtering, exact projected motion, idle rendering, geometry and
instance disposal, controls and the unsupported-WebGL startup path.

Isolated Chrome exercised real WebGL, mouse orbit, Shift-pan, zoom/reset,
smooth fallback, light/dark themes, local visibility, shared-home gathering,
public conversation, cancellation and per-resident profile controls. Captions
were checked at desktop, 390px and 320px. An offline `file:` load rendered 3D;
forced context loss visibly switched to SVG. The preview used mock decisions
only and made no external asset requests. The live bridge was not restarted
or given a new request budget.
