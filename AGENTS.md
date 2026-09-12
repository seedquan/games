# AGENTS.md

Guidance for coding agents (Codex, Claude Code, etc.) working in this repository.
This file is canonical; `CLAUDE.md` is a symlink to it.

## What this repository is

NEON ARCADE — a collection of self-contained browser games deployed to GitHub
Pages. `index.html` at the root is the arcade hub linking to each game.

Three kinds of projects live here:

- **Single-file games** (`abyss-protocol/`, `comet-dash/`, `crimson-command/`,
  `neon-fury/`, `neon-stack/`, `nova-breaker/`, `orbit-drift/`, `singularity/`,
  `star-serpent/`, `starfall-squadron/`, `voxel-frontier/`): each is exactly one
  hand-edited `index.html` with inline CSS/JS. No build step, no dependencies.
- **Built simulations** (`terrarium/`, `westworld/`): Node projects with
  `src/`, `test/`, `build.mjs` (bundles source into a self-contained
  `index.html`), and `server.mjs` (an optional local AI bridge). Their
  `index.html` is a **committed build artifact**.
- **Native Godot projects** (`abyss-protocol-godot/`): independent Godot 4
  scenes, GDScript, and local assets. Open `project.godot` in Godot. These are
  source-only desktop projects, not Pages targets; any future Web export needs
  explicit packaging plus hub/deployment allowlist integration.

## Commands that exist

```sh
# terrarium (has npm dependencies: three, esbuild)
cd terrarium && npm ci
npm run build      # regenerate index.html from src/
npm test           # node --test test/*.test.mjs
npm start          # local server on http://127.0.0.1:4317/terrarium/

# westworld (has npm dependencies: three, esbuild)
cd westworld && npm ci
npm run build      # regenerate index.html from src/
npm test           # node --test test/*.test.mjs
npm start          # local server on http://127.0.0.1:4320/westworld/
```

Single-file games have no commands; open their `index.html` in a browser.
There is no repo-wide test runner, linter, or formatter.

For `abyss-protocol-godot/`, run `./godot.sh` to open the editor, or
`./godot.sh --play` to play. In that directory, run `python3 verify.py` for
import and all scene suites: smoke, weapons, campaign/persistence, Chinese
story/UI, player services, checkpoints, animation, presentation and aiming,
plus local two-controller co-op, five-region navigation, artwork collision,
blessing balance and legacy/checkpoint compatibility, with script-error detection and timeouts.
Player-facing text is Chinese.

## Invariants

**Self-containment.** Every deployed `index.html` must work as a static file:
no CDN references, no external assets, no API keys embedded or accepted by the
browser. GitHub Pages serves rule/demo modes only — never anything that spends
inference money.

**Committed build artifacts.** When changing `terrarium/src/` or
`westworld/src/`, run that project's `npm run build` and commit the regenerated
`index.html` in the same change. Never hand-edit a generated `index.html`.

**Deployment allowlist.** `.github/workflows/pages.yml` copies an explicit
allowlist of files. Adding a game requires adding it there and to the hub
`index.html`. For terrarium/westworld only the compiled `index.html` is ever
deployed — never `server.mjs`, `src/`, or `test/`.

**AI-bridge security (terrarium/westworld `server.mjs`).** The bridges bind to
loopback only, validate Host/Origin, require a per-process token, enforce hard
request budgets and timeouts, never auto-retry failed (charged) requests, and
run the `copilot` CLI outside the repository with tools disabled. Do not weaken
any of these. In westworld, the CLI tool filter must stay
`--available-tools=none`; an empty `--available-tools=` argument is normalized
by the CLI to "no filter", exposing all tool schemas and blowing the credit
ceiling (this happened before).

**Honest labeling.** Both simulation READMEs deliberately distinguish scripted
rule baselines from real model decisions and disclaim AGI/benchmark claims.
Preserve that framing in any UI or documentation text you touch.

## Change and verification expectations

- Read the project's README (`terrarium/README.md`, `westworld/README.md`)
  before modifying it; they document behavior contracts, not just usage.
- Run the affected project's `npm test` and `npm run build` before considering
  a change to terrarium or westworld done. Use the `verify-repo` skill in
  `.agents/skills/verify-repo/` to structure verification.
- For single-file games, open the game in a browser and play the affected
  mechanic; there are no automated tests.
- Do not stage, commit, push, or deploy unless the user asks. Testing is never
  permission to publish.
- The user has authorized Windows game builds to be deployed to
  `smb://Rog-xx/Games` (currently mounted at `/Volumes/Games`). Verify the mount
  destination, preserve other games/versions, and check destination file hashes.
  This authorization does not cover GitHub Pages or other public publishing.

## Agent Notes

Durable decisions live in `.agents/notes/` (see `.agents/notes/README.md` for
the proposed/implemented/rejected/archived states). Write a Note for
non-trivial architecture, security, cross-cutting behavior, workflow, or
testing decisions — e.g. anything touching the AI bridges' trust boundary or
the deployment allowlist. Skip Notes for mechanical edits and narrow gameplay
tweaks. Name Notes `YYYY-MM-DD-short-title.md`. Search existing Notes before
re-deciding something.

## Repository skills

- `.agents/skills/verify-repo/` — maps a diff to the focused checks above
  (tests, rebuild-artifact consistency, deployment allowlist, bridge
  invariants) and reports exactly what was and was not verified.
