# Advance articulated gait in normal gameplay

Status: implemented.

## Failure and correction

The default rig activation described in 2026-09-06-abyss-live-articulated-player.md enabled all eight atlases in normal sessions, but updatePlayer still called advanceRunAnimation only under animationPreview. Normal play therefore drew an articulated idle pose while the player moved. Existing checks invoked the animation helper directly or checked renderer activation, so they missed the actual caller's gate.

The post-collision movement block now advances gait when rigArtEnabled or animationPreview is enabled. It applies to both players, uses resolved displacement, and retains the helper's dash lock and stopped-motion settling. The disabled-rig path without a preview remains unchanged. No artwork, stride tuning, gameplay speed, input, collision, damage, save format or network behavior changes.

## Verification and remaining work

A new regression executes the actual movement block with animationPreview false, checks all eight headings for both players, and then renders each updated pose. It failed before the fix with “normal direction 0, player 1 did not advance”. After the fix it checks changed limb transforms, post-collision wall blocking, dash exclusion and idle settling. All 100 focused checks pass. This uses controlled collision collaborators and is not a full game-loop or device test; public normal-game keyboard verification follows deployment.

The independent low-speed gait issue remains: the constant long stride gives slow movement an extended aerial phase. That requires separate timing and contact work. This correction makes the existing eight-direction gait run in the shipped game; it does not prove complete production animation quality.
