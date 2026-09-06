# Abyss embedded textures and character layers

Status: implemented initial texture integration; full animation/art acceptance pending.

## Decision

Keep the deployed game as one hand-edited HTML with embedded WebP data URLs.
Images decode once and floor patterns are reused. Failed or pending images
retain the procedural fallback without render-loop retries. No external assets,
save-schema changes or deployment configuration changes are needed.

Player art has eight discrete facing views with angular hysteresis. Shooter,
tank, phantom and the abyss boss have textured bodies. Other enemy archetypes,
including directional shield bearers, retain their original procedural bodies.
Held weapons preserve longbow charge, recoil and flying-glaive visibility.
Damage feedback and boss phase auras are shared between rendering styles.

Reusable render-only lists sort characters by ground position without mutating
simulation arrays. Enemy warnings precede bodies; overhead status and player
labels follow bodies. Texture baselines and labels account for taller artwork.
This does not yet solve environment occlusion or full character animation.

## Verification

Run `node --test .agents/verification/abyss-render-contracts.mjs` for focused
render contracts. Ten checks cover directions, jitter resistance, weapon poses,
fallback, damage feedback, co-op identification, boss cues, shield fallback,
layer order, culling and balanced canvas state. These are pure unit checks,
not browser gameplay or frame-rate evidence. Inline JavaScript syntax and
no-external-URL checks passed before publication.

## Remaining art scope

The player has directional idle sprites with body bob, not an articulated run
cycle. Additional enemy directions, consistent animation, VFX, environment
occlusion and measured desktop/mobile/gamepad performance remain to be verified.
The initial texture integration must not be described as production-complete.
