# Agent Notes

Durable decision records shared by all coding agents working on this
repository. Notes are named `YYYY-MM-DD-short-title.md` and record: status,
context, decision, alternatives considered, consequences, and how the decision
was verified.

## States

- `proposed/` — unfinished designs under discussion; **not** current authority.
- `implemented/` — decisions reflected in the current code. This is the only
  directory that describes how the repository works today.
- `rejected/` — approaches that were explored and intentionally not adopted,
  kept so they are not re-litigated.
- `archived/` — superseded history; frozen and non-authoritative.

## When to write a Note

Write one for non-trivial architecture, security, cross-cutting behavior,
workflow, or testing decisions — especially anything touching the terrarium or
westworld AI-bridge trust boundary, request budgets, or the GitHub Pages
deployment allowlist. Skip Notes for mechanical edits and narrow gameplay
tweaks.

When a decision in `implemented/` is replaced, move the old Note to
`archived/` and reference it from the new one.
