# Painted gun sprites and calibrated grips

Status: implemented.

## Decision

Replace the procedural held bodies of the auto-rifle, scattergun and railgun with one embedded 256×288 alpha WebP atlas. Three separately generated originals share gunmetal bevels and restrained cyan/amber lights. The first scattergun had baked checkerboard pixels and was rejected; a built-in image edit produced genuine alpha before integration. Packing only crops and resizes the accepted source images. Runtime payload is 19,630 bytes (26,176 base64 characters); decoded RGBA budget is 294,912 bytes. Source images, prompts and packing metadata remain in the workspace's output/imagegen/abyss-protocol-runtime/weapons directory.

Each gun has calibrated painted grip, support and muzzle points plus an authored barrel angle. Rendering and the two-hand solver use the same rigid transform. Center both grips around the chest so the longer painted handguard remains reachable; do not lengthen bones. The barrel correction keeps the railgun's painted bore aligned with aim. Gun length is constant during recoil, and the transient muzzle flash starts at the painted muzzle. Existing actor recoil, aspect cue and unloaded/failed-asset vector fallbacks remain available. No simulation, damage or projectile logic changes.

One additional texture crop replaces each held gun's procedural body, for twelve total actor crops. No per-frame decoding, filters or additional offscreen surfaces. Existing embedded assets are unchanged, with no external references.

## Evidence and limits

108 focused checks pass, including actual Canvas-transform reconstruction of both painted palms against the rendered gun image across eight headings, three sizes, three guns and idle/intermediate/full recoil. Gun crops are bounded, firing preserves dimensions, and unloaded assets keep the procedural fallback. A separate 64-angle sweep across gun/bow poses found zero unreachable targets and maximum palm error below 4e-14 rig pixels. Eight-direction real Canvas specimens were inspected; inline JavaScript syntax and whitespace checks pass.

These are elevated painted profiles rotated with aim, not eight independent weapon views. Finger closure, back-view occlusion and camera foreshortening still need refinement. Bows, melee weapons and casting weapons remain procedural. Browser gameplay/FPS and physical-device/whole-run validation are distinct from the focused checks and are not established by them.
