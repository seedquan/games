# Default articulated player rendering

Status: implemented; broader production art acceptance remains open.

Supersedes the South/East preview activation decisions now archived in
2026-09-06-abyss-articulated-gait-preview.md and
2026-09-06-abyss-east-articulation.md.

All eight independently generated alpha part atlases now load in normal sessions.
The player switches to articulation only when the player image and every rig atlas
are ready. A failed or pending direction keeps the whole set on the original
sprite path, preventing mixed rendering while turning. The diagnostic rigs=0
query preserves that fallback for comparison. Animation preview panels remain
opt-in; rejected run-sheet candidates do not load in normal sessions.

The eight atlases total 380,668 encoded WebP bytes, and 12 MiB decoded RGBA at
768x512 each. They are already embedded; no external dependencies or requests.
Part transforms run directly on Canvas. Movement is post-collision displacement,
with short direction blending, independent facing, palm-attached attack poses
and per-direction ground calibration. Damage, collision and input rules are
unchanged. Profiling records rig readiness and resets on readiness changes.

66 focused checks pass, including activation without preview flags, all-or-none
readiness, per-direction fallback, movement/turn/ground/weapon contracts and
existing performance checks. Syntax and zero external URLs verified. Public
browser validation follows deployment and is recorded in the local review files.
This rollout is concrete progress toward the requested animated game; it is not
completion of all art work. Remaining work includes gait polish, off-hand weapon
choreography, remaining procedural enemy/VFX assets, full-run and device acceptance.
