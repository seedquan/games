# Abyss run animation preview

Status: implemented behind `?animationPreview=1`; art acceptance remains open.

The character has eight authored idle directions, but no articulated gait. Add
South and East eight-frame run candidates to the actual renderer for evaluation.
Normal sessions do not decode these two preview images or advance their state.
Both WebP atlases are embedded (86,766 bytes combined), so offline operation holds.

Source frames use explicit source regions (East feet cross equal-grid boundaries)
and manually registered pelvis anchors. One scale per direction preserves relative
frame size; no per-frame bounding-box stretch. The preparation manifest and PNG
candidates are in `output/abyss-animation-review/` and the earlier imagegen output.
These are candidate frames, not approved production art.

Phase follows post-collision movement distance, wraps for reverse motion and holds
during dashes. A short exponential blend returns to idle after movement stops.
Unloaded clips and the other six directions use the existing idle atlas; weapon,
hurt, parry and co-op feedback remain in their existing renderer paths.

17 focused tests pass, including blocked movement, reverse phase, dash hold,
idle blending and unavailable-clip fallback. Inline syntax and whitespace checks
pass. Browser animation and frame-rate validation are still required. This does
not complete full directional animation, all-enemy textures, or art acceptance.

Preview follow-up: add visible East/South/Stop controls for sustained in-game
movement using browser tools that only expose short key presses. These controls
only affect player one in the hub, release on keyboard input/window blur, and
clear on leaving the hub. A visible frame/blend readout supports live checks.
18 focused tests pass; the added scope regression checks normal mode, combat,
and player two are unaffected. The controls are absent from ordinary sessions.
