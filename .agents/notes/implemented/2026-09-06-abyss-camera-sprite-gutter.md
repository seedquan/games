# Frame sprite silhouettes at arena boundaries

Status: implemented.

Browser North-rig testing exposed a real head-clipping defect: computeView
clamped the full viewport to the exact floor rectangle, while character art
extends well above its collision centre. Replace that floor-only framing with
fixed visual gutters inside the existing HUD-safe view band: 32 world units on
left/right/bottom, 64 above. The existing dark starfield is the station exterior.
No collision limits, spawn positions, input transforms or simulation timing change.

The axis clamp is continuous; a small arena is centered within the padded view.
Padding is fixed, independent of animation and entities, to avoid camera pumping.
Normal and preview sprites share this framing. Strong screen-shake excursions
and boss-specific oversized art are not covered by a claim of full visibility.

44 focused checks pass. Camera checks cover 390×844, 844×390, 1280×720,
2646×1108; zoom .65/1/1.55/2; player radii 12/13/18 at all four arena corners.
They check full 4.4r sprite bounds, HUD clearance, coordinate inversion and clamp
continuity. These geometry tests do not replace browser movement validation.
