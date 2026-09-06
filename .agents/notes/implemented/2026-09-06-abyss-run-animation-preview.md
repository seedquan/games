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

North / Northeast follow-up: add two independently authored transparent atlases
(39,924 and 34,326 bytes) with pelvis registration, without mirroring asymmetric
shoulder armor. These remain preview candidates; ordinary sessions skip all four
run decodes. The panel now wraps its controls and includes North and Northeast.
Preview movement disarms the hub exit until the actor stops and walks clear of
it, preventing Stop at the portal from unintentionally starting combat.

21 focused checks pass, covering north/northeast selection, reverse phase, normal
mode isolation and portal re-arming. Inline script syntax and whitespace checks
pass; all 12 assets are data URLs and the HTML contains no external URLs. The new
public preview still needs live browser validation after Pages deploys. West
iterations were rejected for direction reversal or repeated leg poses; full
eight-direction gait and production art acceptance remain open.

Transition opacity / guardian body follow-up: two source-over draws at 50% each
leave overlapping opaque body pixels at 75% opacity. Crossfades now combine the
weighted poses using additive premultiplied alpha on one reusable 160×160 canvas,
then draw the result once with the actor's existing hurt alpha. The surface is
allocated only on the first preview transition; ordinary play never needs it.

The guardian image is now a transparent body without a painted barrier. The live
shield body uses it in ordinary play, while both textured and vector fallback
paths share the existing directional barrier renderer. Shield health, hit flash,
freeze, shock and exposure still control visibility through shieldActive. No
combat logic changed. An optional `animationPreview=1&guardianPreview=1` gallery
shows intact, depleted and frozen specimens through the actual renderer, without
adding them to the combat entity list or touching saves.

23 focused checks pass, including constant overlapping transition opacity,
surface reuse, guardian shield direction, depleted/frozen/shocked/exposed states
and balanced canvas scopes. Inline syntax, whitespace and offline checks pass.
Live browser validation follows Pages deployment. Southeast generation attempts
still repeat a forward leg or lose alpha; none was integrated. Full directional
gait and production acceptance remain open.
