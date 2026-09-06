# Articulated South gait candidate

Status: implemented behind `animationPreview=1&rigPreview=1`; art acceptance open.

Whole-sheet image generation repeatedly reused the same leading leg. A generated
RGBA parts sheet now supports a deterministic South-facing rig: core, upper and
lower arms, thighs, shins and feet. The original is preserved in
`output/imagegen/abyss-protocol-runtime/south-rig-parts-v2-alpha.png`. Runtime
preparation only downsamples to 768x512 and encodes WebP (43,764 bytes), preserving
alpha. Source joint/crop coordinates remain explicit in SOUTH_RIG_PARTS.
Upper-arm source drawings include forearms; rectangular crops retain the upper
segments. No local matting, recoloring, mirroring or pixel repair was performed.

The rig uses the same actual-displacement phase and stop blend as the earlier
clips. Legs have opposite stance/swing phases, zero lift during stance and a
continuous swing clearance curve. Joint transforms draw eleven embedded source
rectangles directly; no per-frame images, canvases, filters or network calls.
Normal sessions skip the rig decode. Non-South directions retain existing paths;
weapons, hurt opacity, ground rings and feedback still execute once.

The opt-in hub gallery compares the moving phase with the two opposite contact
poses, through the same renderer used for the actor. It is hidden on small
viewports and outside the unpaused hub. The preview is not an art-quality claim:
full directional articulation, foot-slip tuning, torso identity and broad
combat/device validation remain open.

27 focused checks pass, including opposite support legs, continuous cycle wrap,
zero stance clearance, idle amplitude, image fallback, opt-in gating and balanced
canvas scopes. Inline syntax, whitespace and self-contained asset checks pass.
Canvas-rendered stills were inspected for assembly; live browser validation follows
public deployment because local browser access was previously rejected.
