# Textured cover in the character depth pass

Status: implemented; browser release validation is recorded in the associated PR.

## Context

The initial embedded-texture renderer sorted characters while drawing every pillar before them. Taller painted cover would therefore appear behind characters regardless of their ground positions. This extends the character-layer decision in `2026-09-06-abyss-embedded-textures.md`.

## Decision

Six permanent cover kinds share one embedded 768×512 WebP atlas (98,968 encoded bytes, 1.5 MiB decoded). The image decodes once, keeps its authored camera angle, and needs one cropped draw per visible body. The generated alpha is preserved; atlas cropping separates neighboring cells.

The ground pass draws contact shadows. Decoded permanent bodies join the existing reusable character list, ordered by `y + r * 0.6`. A reusable Set identifies cover without altering simulation arrays. Warning passes remain before bodies and overhead status remains afterward. The culling margin includes raised artwork.

When a living or downed player overlaps a foreground cover rectangle, that prop approaches 42% opacity with exponential time-based interpolation. Its shadow and physical collision remain in place. Enemies do not trigger transparency. Undefined-kind, unavailable-image and temporary TTL ward objects retain their original rendering path, including ward expiration cues.

Collision radii, obstacle generation, damage and save formats are unchanged. Large decorative terrain patches remain non-colliding procedural scenery; this atlas is not used to make those patches look like solid walls.

## Alternatives and consequences

Keeping all pillars in the ground pass would prevent correct foreground occlusion. Sorting the simulation arrays could affect gameplay iteration; only the render list is sorted. Per-object DOM or shader filters would add unnecessary work, so fading uses canvas alpha and the shared decoded atlas.

The rectangle overlap is a conservative visibility aid rather than pixel-perfect occlusion. It can fade a prop slightly before opaque pixels overlap. Cover and character art still use a simplified 2D projection over circular gameplay collision; this is not a new 3D physics model.

## Verification

90 render/performance checks pass, including six atlas cells, loaded/unloaded and TTL fallbacks, unchanged collision coordinates, player-only fade and frame-step equivalence, stable depth ordering/culling, and single ground-shadow rendering. JavaScript syntax and diff checks pass. Existing embedded assets are unchanged; no external URLs or deployment allowlist changes were introduced. Actual NAPI Canvas specimens cover the six props and a player behind the crystal prop. These checks do not establish whole-run or mobile performance acceptance.
