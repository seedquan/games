# Two-hand gun and bow poses

Status: implemented.

## Context and decision

The live rig attached the weapon to one palm, while the other arm kept its running swing. Guns had no supporting hand and bowstrings moved without a drawing hand.

All three guns and three bows now use coordinated palm targets in every facing. Guns place the support palm four world units forward along the receiver. Bows place it on the actual string nocking point, including the seven-unit draw displacement and the bow's grip offset. The primary palm still drives the existing weapon draw. Movement bob and recoil share the same transforms, so the hands and weapon stay together. Eight authored support-palm pivots were calibrated from the existing alpha atlases; no pixels or assets changed.

The solver includes the painted hand beyond the wrist rather than treating the wrist joint as the grip. Close bow draws foreshorten the arm toward the camera; a stable folded elbow avoids the zero-distance target singularity. Projected bones can shorten, with no extra draw pass or hidden second weapon. Other weapon classes retain their existing poses. An opt-in preview button cycles temporary gun/bow choices on the hub player without changing the saved armory selection.

## Verification and limits

106 focused checks pass. The new renderer-level check transforms both painted palm points through the complete Canvas stack and compares them to receiver/string points for eight headings, three player sizes, six weapons and idle/intermediate/full draw or recoil states. Each pose keeps eleven texture crops and one weapon pass. Another check exercises the folded elbow across the shoulder singularity. A separate 64-angle sweep found no unreachable targets and maximum palm error below 4e-14 rig pixels. Actual Canvas rifle and full-draw longbow specimens were inspected across eight directions.

These are projected poses, not a complete anatomical 3D rig. Guns and bows still use procedural weapon artwork; weapon textures, finger closure, back-view occlusion refinements, polearm choreography and physical-device/whole-run acceptance remain separate work.
