# East-facing articulated animation candidate

Status: implemented behind the existing animationPreview + rigPreview flags.

The East view now uses an eleven-part embedded transparent WebP, generated from
the existing android identity and South parts layout. Its two-bone leg solver
preserves 25/27-unit segment lengths through the entire gait. It shares the
96-world-unit displacement cycle and calibrated stance travel with South.
Far limbs draw behind the torso; the near arm draws in front. No mirroring of
the asymmetric armor is used. Weapon, recoil, damage and co-op passes remain
shared. Normal gameplay skips both rig images and retains the existing sprites.

39 focused checks pass, including all-phase leg lengths, opt-in/loading fallback,
eleven part draws and exactly one weapon/feedback pass. Offline pose sheets were
rendered using actual game functions. These checks do not establish natural gait,
identity consistency across turns, full directional completion or device FPS.

Source and review assets are under output/imagegen/abyss-protocol-runtime and
output/abyss-animation-review; only the compressed data is embedded for Pages.
Open: idle/rig proportions, remaining six directions, browser motion acceptance.
