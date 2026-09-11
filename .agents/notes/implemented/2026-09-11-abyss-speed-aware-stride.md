# Speed-aware walk and run stride

Status: implemented.

## Context and decision

The constant 96-world-unit stride gave each foot only about 13.4% support at the usual player scale, even with gentle analog input. Low-speed movement therefore looked like a slowed sprint with a long aerial phase.

Live rigs now target a 2.625-cycle/second cadence, shortening the cycle at lower resolved speeds. The shortest cycle caps each foot's support at 58%, allowing double support for walking. Full base speed (252 units/second) and faster retain the original maximum 96-unit cycle. Low-speed recovery raises the foot less. Every heading receives the same per-player cycle length. Gameplay movement and input magnitude remain unchanged.

Cycle length follows speed exponentially. Naively changing it displaced planted feet, so single-support retiming preserves the supporting foot's normalized phase times cycle length; double support defers the change until one foot lifts. The phase stays distance-driven, and existing dash, collision, stopping and fallback rules remain intact. No assets or additional draw passes were added. The opt-in animation panel now offers full speed, quarter speed and tenth speed for browser review.

## Verification and limits

104 focused checks pass. Coverage includes constant-speed phase agreement at 60/120/240 updates per second, slow contact across 64 heading/travel combinations, continuous foot velocity at contact/recovery boundaries, and rendered support-foot anchors while accelerating and decelerating at 60/120 updates per second. A separate geometry sweep found fixed-bone length error below 3e-14, and 120 Hz transition support drift below 3e-14 world units. Actual Canvas before/after clips cover all eight directions at quarter speed and stopping.

These checks cover stable travel directions and full movement blend. Existing start/stop blending and sharp reversals can still move foot placement; they are not world-space IK. Physical touch/gamepad acceptance, whole-run performance, off-hand choreography and broader production art acceptance remain open.
