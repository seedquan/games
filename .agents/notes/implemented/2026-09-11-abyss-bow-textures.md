# Painted bows with calibrated draw geometry

Status: implemented.

## Decision

The quick bow, longbow and storm bow now use three separately generated alpha sprites, packed into one embedded 384×256 WebP atlas (21,034 compressed bytes; 393,216 decoded RGBA bytes). Each body has a painted grip and two calibrated string anchors. The atlas is loaded once, with the existing procedural fallback while unavailable. Previous embedded assets are unchanged. Originals, exact prompts and calibration metadata are retained in output/imagegen/abyss-protocol-runtime/bows.

During draw, the body widens by up to 18% and shortens by up to 4% around its fixed grip to suggest limb flex. The string endpoints follow this transform, and its nocking point moves seven world units farther behind the string midpoint. Both painted hands follow the grip/nock, centered near the chest to stay within arm reach. The nocked arrow translates with the draw and keeps constant shaft length. Thin string/shaft strokes preserve the bow material's readability. Each held bow uses one texture crop; no extra surfaces or filters.

An opt-in animation-preview button holds the normal longbow fire input in the hub, allowing its actual charge/release logic to be tested without writing hidden state. It only applies to player one with the longbow, and clears on weapon change, stopping, losing focus, real keyboard input or leaving the hub. The normal game does not enable it; saved equipment choices remain unchanged.

## Verification and limits

111 focused checks pass. New actual Canvas-transform checks compare both rendered palms against the painted grip and the drawn string nock across eight headings, three body sizes and charge/recoil states. String endpoints match the flexed image, arrows retain constant length, and unloaded bows fall back. The input preview is gated to the opt-in hub/player/weapon. Separate 64-angle gun/bow sweep: zero unreachable targets; maximum palm error below 5e-14 rig pixels. Eight-direction real Canvas specimens inspected, inline syntax and diff whitespace checks pass; no external references.

This is a two-dimensional flex approximation using rotated painted profiles. Independent weapon views, foreshortening, finger closure and back-view occlusion remain incomplete. Nocked arrows/string remain procedural. These checks do not establish browser FPS, physical-device performance or complete-run acceptance; release/browser findings belong in the PR and output review log.
