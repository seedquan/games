# Adopt a shared repository agent system

- **Status:** implemented
- **Date:** 2026-09-05
- **Category:** process

## Context

The repository had no agent guidance: no AGENTS.md, no CLAUDE.md, no shared
skills. Multiple coding agents (Codex, Claude Code) work here, and the
repository has non-obvious invariants — committed build artifacts, a Pages
deployment allowlist, and AI-bridge security constraints — that agents kept
having to rediscover from READMEs.

## Decision

Establish `AGENTS.md` as the single canonical instruction file, with:

- `.agents/notes/{proposed,implemented,rejected,archived}/` for durable
  decision records;
- `.agents/skills/verify-repo/` as the shared verification skill;
- `CLAUDE.md` as a symlink to `AGENTS.md` and
  `.claude/skills/verify-repo` as a symlink to the shared skill, so Claude
  Code discovers the same content without duplication.

## Alternatives

- Separate AGENTS.md and CLAUDE.md files: rejected — they drift.
- A `CLAUDE.md` containing `@AGENTS.md`: viable fallback if the symlink causes
  portability problems (e.g. on filesystems without symlink support).

## Consequences

Agent-facing policy is versioned and reviewable. Non-trivial decisions —
especially anything touching the terrarium/westworld bridge trust boundary or
`pages.yml` — should get a Note here.

## Verification

Symlinks resolved with `ls -l`; skill frontmatter validated; `git check-ignore`
confirmed the new paths are trackable; pre-existing worktree changes
(`pages.yml`, hub `index.html`, untracked `terrarium/`, `westworld/`) left
unstaged and unmodified.
