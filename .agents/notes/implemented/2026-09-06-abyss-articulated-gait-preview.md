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

Foot-contact correction (browser verification follows deployment): the first
rig used the 112-world-unit clip cycle with only ±6 stage pixels of ankle travel.
For the actual radius 13 / sprite scale 0.3575, a planted foot slipped 51.71 world
units through half a cycle (56 root movement minus 4.29 local cancellation).
Alternating legs alone therefore did not establish a grounded gait.

The candidate now uses a 96-unit South rig cycle, ±18 stage-pixel travel and a
sprint contact duty derived from sprite scale: 2*18*scale/96. During full-blend
stance, foot velocity cancels root velocity; swing uses a continuous return
curve with clearance and an aerial phase between opposite contacts. Moving leg
projection is lowered to keep the larger stride within the body proportions.
Other directional clips retain their 112-unit cycle.

29 focused checks pass. The new check records the actual renderer's toe endpoint
through stance at radii 12, 13 and 18, applies root displacement, and finds less
than 1e-9 world-unit drift on both axes. This is a stable full-blend, no-recoil
geometry check; it does not prove natural movement, ground contact while blending,
combat quality or game FPS. Source-rendered contact poses and a motion study are
in output/abyss-animation-review/. The browser has been unlocked; public gameplay verification follows the preview
release. Full-direction expansion still requires visual acceptance.
