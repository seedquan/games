# Opt-in combat performance scenarios

`?combatPreview=1` exposes visible controls for a 48-enemy mixed room and the
three Abyss Core phases. These exercise the real enemy spawners, combat update,
damage, collision, projectile and drawing paths. The player receives 100,000 HP
to survive the observation; damage is not disabled. Normal controls remain usable.
The boss phase controls lower HP to the normal transition thresholds, retaining
the entrance and transition effects. Scenarios and AI are randomized, so these
are exploratory stress samples rather than deterministic benchmark scores.

The flag is evaluated before store construction. All reads and writes in this
mode go exclusively to an in-memory store, including statistics, achievements,
settings and progression. Reload starts fresh. Ordinary sessions retain the
existing localStorage namespace and behavior. No network, external assets or
production save migration is introduced. Stop clears combat through enterHub.

The page automatically enables existing frame telemetry in this mode. The panel
reports current enemy/projectile counts and rolling FPS/P95; old sample windows
are reset when a scenario starts. Large player HP, stationary observation, scene
randomness and culling must be disclosed with results. They do not prove full-run,
real-device, or visual-art acceptance.

31 focused checks pass, including store isolation, ordinary-store behavior,
scenario gating, 48 actual spawner invocations, wave reset, boss HP thresholds
and telemetry reset. Public browser verification follows deployment.
