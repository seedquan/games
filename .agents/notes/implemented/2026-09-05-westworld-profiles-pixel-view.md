# Westworld decision profiles, diagnostics and pixel presentation

- **Status:** implemented
- **Date:** 2026-09-05
- **Category:** cross-cutting behavior

## Context

Text-only resident actions can still wait on four serial CLI/model calls per
round. No paid latency benchmark was authorized. The same change requested
Chinese resident names, human portraits and a pixel-art town.

## Decision

Keep the default model and independent, sequential decisions. Add explicit
low/high reasoning profiles, configured only in the local server environment.
The browser sends an allowlisted profile ID, not arbitrary models or CLI
arguments. Pending profile selection is separate from the active authorized
profile; closing the dialog cannot silently switch the model or effort.

The subsequent per-resident provider requirement extends these profiles via a
server-only JSON allowlist. Residents choose provider/model/effort combinations
that map to exact profile IDs, never browser-supplied endpoints or credentials.
Copilot keeps the existing isolated CLI restrictions. An explicit
OpenAI-compatible Chat Completions adapter may instead call a locally configured
endpoint using a server environment key. It forbids redirects, non-HTTPS remote
URLs, query credentials and model tools; bounds response bytes, output tokens and
time; shares the same serialized service request budget; and never retries.
It does not claim the CLI credit ceiling applies to API billing.

Profile IDs are saved separately as browser preferences without reconnecting on
reload. Audit entries may include validated provider/model/effort metadata;
resident observations do not include it. Missing keys or removed choices block
activation and do not silently select another provider.

Record success, failure and cancellation timing without logging simulation
content or tokens. Show waiting time locally, without polling or rerendering the
map every second. OS process-spawn, first stdout and exit are offsets, not
additive stages or measurements of pure model inference. Streaming remains off.
All prior bridge restrictions, budgets and failure/no-retry behavior remain.

Bundle a dependency-free pixel-art module into the static page. Draw roads from
the engine's topology and people from actual locations; resident view must
continue hiding remote people and stocks. Art uses the existing theme variables.

Preserve resident IDs for old saves. Migrate only recognized original default
names/initials on restore; preserve custom names and original historical text,
memories and audit observations.

## Alternatives

Do not introduce a persistent SDK or context reuse before timing evidence
justifies its complexity. Do not parallelize or batch residents: that changes
sequential observations and risks sharing private state. Do not replace audit
text globally when renaming, since it records the original model inputs.

## Verification

The Westworld Node suite covers profile authorization, progress-timer cleanup,
failure timing, CLI flags, budget counting, request serialization, old-save
migration, pixel assets, real road topology and observation privacy. The
standalone artifact is regenerated from the three source modules. Headless
Chrome uses an isolated profile and a mock-only bridge, never paid inference.
It exercises light/dark and narrow layouts, map selection/drop targets,
resident fog, cancellation and sequential mock decisions. No external image or
font requests are required.

The completed suite has 75 passing cases, including a real loopback HTTP
provider fixture and a simulated 90-second API timeout. Chrome passed at
1440, 390 and 320 CSS-pixel widths with no horizontal overflow or runtime
exceptions. All model responses in these checks were local fakes.

## Limits

No actual model speedup or account/model availability has been measured.
Process reuse remains deferred. The existing dirty hub/deployment changes and
the separate Terrarium project are outside this change; nothing is published.
