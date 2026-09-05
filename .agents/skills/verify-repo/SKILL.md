---
name: verify-repo
description: Verify a change in the games repository by mapping the diff to focused checks — project tests, rebuilt index.html artifacts, Pages deployment allowlist, and AI-bridge security invariants. Use before declaring any change to this repository done.
---

# Verify a change in this repository

Run checks proportional to what actually changed. Never treat verification as
permission to stage, commit, push, deploy, or spend inference credits.

## 1. Inspect the diff

Run `git status --short` and `git diff` (plus `git diff --stat` for scale).
Identify which surfaces changed, and note any pre-existing worktree changes
unrelated to the current task — preserve them and exclude them from your
verification claims.

## 2. Map changed surfaces to checks

| Changed surface | Required checks |
|---|---|
| `terrarium/src/**`, `terrarium/build.mjs`, `terrarium/server.mjs` | `cd terrarium && npm test`. If `src/` or `build.mjs` changed: `npm run build`, then `git diff terrarium/index.html` must show the regenerated artifact is included in the change. |
| `westworld/src/**`, `westworld/build.mjs`, `westworld/server.mjs` | `cd westworld && npm test`. If `src/` or `build.mjs` changed: `npm run build`, then confirm the regenerated `westworld/index.html` is included. |
| `terrarium/server.mjs` or `westworld/server.mjs` | Additionally confirm the bridge invariants still hold: loopback-only bind, Host/Origin validation, per-process token, request budget/timeout enforcement, no automatic retry of failed requests. In westworld, `--available-tools=none` must remain exactly that string. |
| Any single-file game `*/index.html` | No automated tests exist. Open the file in a browser and exercise the changed mechanic. Confirm the file remains self-contained (no new CDN/external references — check with `grep -nE 'https?://' <file>` and justify every hit). |
| Root `index.html` (arcade hub) | Open it in a browser; confirm every game card links to an existing directory. |
| `.github/workflows/pages.yml` | Confirm the allowlist copies exactly the intended files; for terrarium/westworld only `index.html`, never `server.mjs`, `src/`, or `test/`. New game directories must also appear in the hub `index.html`. |
| `AGENTS.md`, `.agents/**`, `CLAUDE.md`, `.claude/**` | Validate skill frontmatter parses; resolve symlinks with `ls -l` and confirm targets exist; `git check-ignore` intended-tracked paths to confirm they are not ignored. |

Do not run both projects' suites for a change scoped to one project, and do not
build projects whose sources did not change.

## 3. Cross-cutting changes

If a change spans terrarium and westworld, or alters shared conventions
(deployment, bridge pattern, note system), run both test suites and re-read the
relevant README sections — they are behavior contracts.

## 4. Report

State exactly which checks ran, their results (including failures, verbatim),
and which checks were deliberately skipped and why. If a required check cannot
run (e.g. no browser available for a single-file game), say so explicitly
rather than implying coverage.
