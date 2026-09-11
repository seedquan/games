# Bow arrow release and flight projection

Status: implemented.

## Decision

Bow projectiles retain their ground-plane physics while carrying a fixed visual offset captured at release. The source point is the actual rig grip plus calibrated bow nock and arrowhead, including body recoil, gait bounce and facing-specific ground anchor. The longbow reconstructs the released draw fraction because input handling clears drawing before fireBow. Every volley member starts visually at this release point; subsequent owner motion/turning/weapon changes cannot drag it. Unavailable rig/bow assets retain the procedural fallback.

Flying shafts now match the nocked arrow's 20/24-unit length and .65-unit width. Their local origin is the arrowhead. This avoids the previous change in size driven by collision radius. Glow uses a smaller cached bloom; the projected arrow does not add a shadow filter, texture decode or offscreen surface. Three scalar visual fields reset when a pooled arrow is acquired.

Arrow trails, direct hit sparks/lights, pillar impacts and shield-contact sparks share the projected contact point. The shared hitEnemy function accepts optional cosmetic coordinates; damage, knockback, shield coverage, status effects and ground-area indicators still use simulation coordinates. Piercing/homing/ricochet preserve the captured offset. Split shards now originate at the hit, exclude the struck enemy and inherit its visual projection; the prior implementation unexpectedly relaunched them at the player. At the 72-arrow cap, splits stop creating shards instead of evicting their currently executing parent.

Bow recoil uses each bow's full duration (.12/.22/.2 seconds), avoiding the negative sine segment previously produced above .18 seconds. Other weapon recoil is clamped against a negative initial segment.

## Verification and limits

119 focused render/performance checks pass. New checks compare release points against actual Canvas-transformed longbow arrowheads across eight facings, three body sizes, three draw fractions and idle/moving poses. Tests exercise normal bow dispatch, multishot/homing volleys, pool reset, owner movement independence, ground-plane collisions, hit cosmetics, piercing/ricochet/splits and splitting at capacity. Inline JS syntax, diff whitespace and embedded asset equality checks pass; zero external URLs. Actual Canvas specimens were inspected at full draw and 16.7/33.3ms after release in all eight directions.

This is a fixed 2.5D projection per shot, not a general three-dimensional target-height model. The generic enemy death/status-area effects retain their existing anchors. Guns/casters still need a corresponding launch/flight alignment pass. Bow back-view occlusion, independent weapon views and finger closure remain incomplete. Automated checks and Canvas specimens do not establish browser or device frame rates; deployment/browser observations are recorded in the PR and output review log.
