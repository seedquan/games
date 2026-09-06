# 尘湾 / Westworld Lab

A Chinese world observed through a rotatable miniature island and a text event
history. Four original residents have
separate goals, inventories, local observations and memories. The observer can
change weather, drop resources/tools, and send a private, explicitly unverified
whisper. There is no prewritten story ending.

The residents are 林岚 (mechanic), 陈野 (prospector), 沈宁 (doctor) and 周禾
(farmer), with rounded portraits and full-body toy-like walking characters. The island
is one continuous game-like scene, not a grid of location cards: terrain,
buildings, roads and residents share a single coordinate space. It shows the seven
places, their actual road links and residents' current positions. Its buildings
are illustrative, not additional resources or world rules. Selecting a place
still targets resource drops. Resident view hides remote people and live
stocks, while retaining the known map topology. All artwork is local and
theme-aware, with no external images, fonts, models or runtime asset requests.

The default **3D Mini** view is a spacious organic island with an ocean, a soft
beach edge, groves, a pond, a stream, a footbridge and a pier. Rounded cottages,
beveled roofs and big-headed residents use smooth geometry and soft shadows,
not pixel or voxel artwork. The physical island footprint is more than seven
times the former 480-by-320 presentation board; the seven places retain their
simulation IDs and original road graph, now drawn as winding paths.
The additional scenery does not create new resources, destinations or rules.
Mouse dragging rotates the
camera and adjusts elevation; the arrow buttons also rotate it. Hold Shift
while dragging to pan a zoomed map. Touch users can use the rotation buttons
and native scrolling. **Full view** resets zoom and camera orientation.
The view selector offers a smooth **flat island** overview as an explicit option.

Three.js is pinned locally and bundled with esbuild into the committed HTML;
there are no CDN scripts or cross-project imports. An orthographic WebGL2
camera is shared by geometry, hit targets, movement and overhead captions.
Static geometry is cached, repeated trees are instanced, render resolution is
bounded, and frames are drawn on changes and during bounded movement rather
than in a permanent idle loop. Unsupported or lost WebGL is reported visibly
and switches to the smooth SVG overview. This adds no new physics or AI calls.

The larger house in the center is **共同的家 / OUR HOME**, a real shared place
connected to the well and ridge. All four residents can visit, meet and rest
under its roof; it has no owner or automatic sharing of private memories or
inventories. It starts without supplies. Observer drops there become public
stock that residents must visit and take, just like at other locations.
The rule baseline prefers returning home when tired, adjacent and able to
afford the move; it does not teleport residents or override model decisions.

Click a building to select a drop location, or click a resident to inspect them.
The detail strip shows stocks only when the selected location is visible.
Zoom controls provide a closer view; drag empty ground with a mouse, use native
touch scrolling, or focus the map viewport and use arrow keys. The full-scene
view can be restored with the panorama button.

Walking is a short visual interpolation of an **already committed adjacent
move** in either view. It never creates an action, waits before the next decision, mutates
world time or makes a model call. Stationary residents do not wander for
decoration. Pausing, hiding the page, restoring a world, changing viewpoint or
enabling reduced motion snaps sprites to their committed positions. Residents
entering local visibility appear at their current location without a trail
from their hidden origin; departing residents disappear immediately. Terrain
is cached between relevant visual changes and only a moving sprite animates.

Residents have overhead action captions and speech bubbles. Captions summarize
the most recent committed action, not a predicted plan; walking and pending
model decisions have explicit temporary labels. A failed action is marked as
failed rather than shown as a successful gift or conversation. Speech comes
only from a successful `talk` action, never private goals, action intentions or
observer whispers. It stays available until the resident's next action.
Click a resident or their bubble to read the complete latest utterance below
the scene; narrow screens show a one-line preview. Captions spread out when
residents gather at home and adapt to zoom and resize without advancing time.
Local view omits another resident's earlier actions or speech unless the
selected resident was present; a newly visible resident's origin is not exposed.

## Run

```sh
cd westworld
npm ci
npm run build
npm start
```

Open `http://127.0.0.1:4320/westworld/`. Use `PORT=4321 npm start` to select a
different port. Building requires the locked local dependencies; viewing the
generated page or running the optional bridge does not. The generated `index.html`
is self-contained: it can also be opened directly or served on GitHub Pages.
Static hosting only supports the rule baseline.

## Real AI versus scripted baseline

The default mode is **free, hand-written rules**, visibly labeled throughout.
It is not a model, learned cooperation, or evidence of AGI.

For independent model decisions, start the local server, open the model dialog,
review the billing consent, and explicitly enable AI. The bridge invokes the
installed, authenticated `copilot` CLI with `gpt-6-astra`, or the model selected
by `WESTWORLD_MODEL`. Bridge status does not verify login or model availability;
only an actual request does. No requests happen on startup or connection.

### Decision speed and diagnostics

The model dialog offers two server-defined profiles. **Fast** is the default:
`WESTWORLD_MODEL` (default `gpt-6-astra`) with `WESTWORLD_EFFORT` (default `low`).
**Deep** uses `WESTWORLD_DEEP_MODEL` (default the same model) with
`WESTWORLD_DEEP_EFFORT` (default `high`). Switching a profile clears billing
consent and makes no inference request. The browser sends only the profile ID,
never an arbitrary model or CLI flag. Profile labels describe intent, not a
guaranteed speed, quality or price.

Each resident can independently select **Provider / Model / reasoning effort**.
The batch selector is only a convenience for applying one profile to everyone.
Edits remain drafts until billing consent is confirmed; cancelling the dialog
keeps the previously authorized choices. Only non-secret profile IDs are saved
in a separate browser preference key. Reloading still requires reconnection and
fresh consent, and removed/unavailable profiles block activation rather than
silently substituting a model. Audit entries record the configured provider,
model and effort; these are observer metadata, not shared resident knowledge or
cryptographic proof of which model a provider actually ran.

For example, to configure a different fast model while keeping Astra for deeper
decisions, save progress and manually stop the old server before starting:

```sh
WESTWORLD_MODEL=claude-haiku-4.5 WESTWORLD_EFFORT=low \
WESTWORLD_DEEP_MODEL=gpt-6-astra WESTWORLD_DEEP_EFFORT=high npm start
```

Model access and accepted reasoning levels depend on the installed CLI and
account. Unsupported combinations fail visibly, consume an attempted call, and
pause without trying another profile or raising the budget. Supported local
effort values are `none`, `minimal`, `low`, `medium`, `high`, `xhigh` and `max`;
this syntactic allowlist is not a guarantee that each model accepts every value.

While waiting, the page shows the resident, turn position and elapsed seconds.
The previous request retains browser elapsed time, success/failure/cancellation,
server total, process-spawn, first-stdout and process-exit timings. Missing
timestamps are shown as unavailable, not zero. Only the progress text updates
once per second: it does not poll the server, rerender the town or add calls.
These recent UI timings are not saved into world history.

Every charged attempt also writes a single `westworld.decision` JSON line to
the local server's console, including profile, resident ID, round, outcome and
timings, but no prompt, response text, memories, whispers or connection token.
Capture that console output yourself if you need a persistent timing log.
The server timestamps are offsets from the call start, **not additive stages**.
Process spawn only means the OS started the child; it does not measure CLI
readiness. With streaming disabled, first stdout is not time-to-first-model-token:
it includes initialization, network, queueing and reasoning, and may arrive
only with the complete answer. These numbers cannot isolate pure inference time.

Each Copilot action still starts one isolated CLI process and residents remain
sequential. No persistent SDK, concurrent inference or shared resident context
has been introduced. Consider process reuse only after actual timings justify
it, preserving the same knowledge boundaries, tool restrictions and budgets.
Low effort is a speed/quality tradeoff, not a measured speedup claim.

### Additional providers and models

Two adapters are supported: the installed **Copilot CLI**, and
**OpenAI-compatible Chat Completions HTTP APIs**. The latter does not launch a
CLI process. Native Anthropic Messages APIs are not supported by this adapter;
a gateway must actually support the configured Chat Completions format.

To load additional allowlisted choices, review `profiles.example.json`, adjust
the model IDs to those available to your account, and start from this directory:

```sh
WESTWORLD_PROFILES_FILE=./profiles.example.json npm start
```

The example includes extra Copilot model choices and OpenAI API profiles.
Names such as `gpt-5.6-sol` are explicit model IDs, not an availability promise;
replace them if your provider exposes GPT-5.6 under a different ID. No startup,
profile discovery or UI selection sends a model request.

The file extends the built-in `fast` and `deep` profiles with at most 24 entries.
Each entry has `id`, `label`, `provider`, `providerLabel`, `adapter`, `model` and
`effort`. A provider/model/effort combination must be unique. For API entries,
also configure a full Chat Completions `endpoint`, an `apiKeyEnv` naming a
server-side environment variable, `maxOutputTokens` (256..4096), and
`tokenLimitField` (`max_completion_tokens` or `max_tokens`, as supported by the
provider). `effort: "default"` omits the reasoning parameter; other choices send
`reasoning_effort` exactly, without automatic fallback.

Set the credential in the server environment, never the JSON file, browser,
whisper or repository. Missing API credentials are shown as unavailable and
rejected before consuming request budget. Endpoints must use HTTPS, except
explicit loopback HTTP for local providers. URL credentials/query strings,
redirects and arbitrary request options are rejected. Keep a real profile file
outside the repository if endpoint/model information is private. The page only
receives display metadata and availability, never endpoints, environment-variable
names or API keys.

API requests send the same single resident prompt without tools, shared
conversation state or retries. They share the service's serialization, token
authentication, 24-call limit, input validation and cancellation behavior.
They have a 90-second timeout, a 64 KB response limit and the configured output
token cap. Truncated responses, tool calls and invalid JSON stop the experiment.
API usage is billed by that provider, **not** covered by the CLI's 30-credit
soft ceiling; a token cap is not a fixed price. HTTP failures consume an
attempted call. No automatic retry, provider switch or follow-up reasoning call
occurs.

API timing records response-header, first-body-byte and total elapsed times.
Those include network/provider processing and are not pure reasoning latency.
These adapters and the toy world's narrow probes do not establish ARC-AGI
scores, generalized world-model learning or any other external benchmark claim.

Each live resident receives its own prompt. Residents know the map topology,
their state, stocks at their current location, visible neighbors' coarse
condition, their own timestamped old observations, and their last 12 memories.
They do not receive other residents' inventories/goals/memories, the global
event log, or the device's hidden effect. The observer can inspect exact
observation/decision/result records. Short intent text is **not internal
chain-of-thought**.

Each Copilot request runs outside the repository in a temporary directory with no
available model tools, builtin MCPs or custom instruction files. The local
bridge follows the repository's Terrarium pattern without depending on or
modifying that application. It binds only to loopback, rejects cross-origin
requests and unexpected Host headers, requires a per-process token, bounds
bodies and responses, serves only the compiled page, and serializes inference.
It is a CLI integration, not an operating-system sandbox; the user's installed
CLI and its authentication configuration remain part of the trust boundary.
Never put sensitive information in whispers.

The CLI tool filter uses the explicit nonmatching allowlist
`--available-tools=none`. Do not replace this with `--available-tools=`: the
installed CLI normalizes an empty argument to an absent filter, exposing all
tools and adding their schemas to every model request. This previously added
tens of thousands of tokens and triggered the per-session credit ceiling.

The per-connection limit defaults to 12 calls; the service-wide limit is 24.
**Failures consume budget.** Every CLI process has a 90-second timeout and
a 30-AI-credit soft ceiling (the local CLI's minimum accepted ceiling, not a
per-request price or a guaranteed hard charge cap). There is one request per
active resident per round. Eight rounds usually require 32 requests: to run a
longer experiment, save progress, manually restart the service, reload, reconnect,
and **uncheck the fresh-world option**. Raising playback speed never adds model
concurrency. Pausing/closing/hiding the page cancels pending requests where
possible; charges already incurred cannot be undone. Errors pause without
automatic retries or silently switching to rules. In particular, CLI "No response
was returned" can mask session-limit exhaustion; it is not proof of a transient
network failure and must not trigger another charged request automatically.
Explicit session-limit diagnostics take precedence over this generic symptom.
Already applied actions are retained and are not repeated on manual continuation.

## Physics and interpretation

- Seven connected places and nine road links; movement is one adjacent edge
  per action. The original six places and all their links remain.
- Food/water/energy/health are bounded from 0 to 100, higher is better.
- Four decisions form a round, then 20 minutes pass and needs decay.
- Water restores 36 hydration; food restores 32 hunger; items must be taken first.
- Each inventory item is capped at 12; transfers conserve items.
- Rain replenishes the well faster and advances crops faster. Drought stops
  shallow-water regeneration and doubles hydration consumption relative to sun.
- A carried pump at the well produces 3 water; an axe at the ridge produces 3
  wood. Their underlying sources do not deplete in this version.
- A hammer plus 3 wood and 2 stone builds a public shelter.
- Seeds plus 1 water at the farm yield 6 public food after 3 round boundaries;
  rain advances 2 growth units per round.
- The unknown device has one of two seeded, predefined effects, revealed only
  by actual use at the workshop. Even-numbered seeds restore energy;
  odd-numbered seeds produce water.
- A gift transfers an item, not immediate nutrition. Talk is recorded as
  unverified speech for the recipient. Whispers do not modify physics.
- Residents with zero health permanently stop acting until reset. There is
  no death/revival narrative. Exhausted living residents can rest.
- The eight-round scenarios check specific behavior: pumping/survival,
  repeated device use, or two gifts/survival. These are deliberately narrow
  behavioral probes, not standardized benchmarks or an AGI score.
- The same seed reproduces starting conditions; it does not make model output
  deterministic. Sequential decisions mean later residents can observe effects
  left by earlier residents. Each decision includes its original observation.

## Persistence and audit

Progress autosaves after actions/interventions. A separate manual save slot is
not overwritten by autosave. Loading pauses and disconnects AI. Switching from
rules to AI optionally resets the same seed (on by default for a new rule-only
world). When reconnecting a world that already contains model actions, this
option defaults to off so recovery preserves progress. Continuing without reset
preserves any rule-generated memories, and exports identify mixed provenance.

Existing default names migrate to the new Chinese names when restoring an old
save. Internal resident IDs, progress, relationships and inventories stay the
same. Custom names are preserved. Historical events, memories and original
decision observations are not rewritten, so older records can still contain
the former names.

World version 2 adds the shared home. Valid version-1 six-place saves gain an
empty, covered home without changing progress, locations, visited places,
inventories, memories or past audits. The archival envelope remains
`westworld-lab-v1`; the world payload carries its own version. Historical
six-place observations remain verbatim alongside new seven-place observations.
Missing locations in a version-2 save remain an error, not a silent repair.
The additional routes and home-seeking baseline can change future trajectories;
old and new engine runs are not identical experiments.

Bridge status advertises the world version. A page with the new home refuses
to enable an older bridge before any model request; save and manually restart
the local service to load the new map, then reconnect with fresh consent.
The house itself works immediately in static/rule mode.

JSON export contains the world, intervention records, action sources, latest
800 events and latest 200 full observation/decision/result records, plus dropped
record counters. It is **not a full replay** beyond those retention windows.
There is no simulation while the tab is hidden or closed. Export is archival;
**Import** also restores an exported JSON file (up to 10 MB), including a
partially completed round, residents' memories and the retained audit history.
The file is read locally, validated and previewed before explicit confirmation
replaces the world and autosave; the separate manual save is never overwritten.
Cancelling, malformed files and stale file reads leave the current world intact.
Recovery pauses time and disconnects AI without any model calls. Reconnect with
the fresh-world option unchecked to continue an existing model experiment.

Browser saves and imported files use the same validation, including inventory
limits, local observation shapes, event ordering and audit counters. Validation
is structural, not a re-execution or proof of authenticity: JSON is editable and
the recorded action sources are not cryptographically attested.

## Development

```sh
npm run build
npm test
```

`src/world.mjs` is the deterministic world engine and isolated rule baseline.
`src/app.mjs` is the browser UI and non-overlapping round scheduler.
`src/pixel-art.mjs` contains the self-contained pixel scenes and resident art.
`src/town-scene.mjs` projects visible scene state and plans presentation-only
movement along the real map's roads. `src/town-3d.mjs` supplies the software
3D camera, geometry and on-demand renderer.
`server.mjs` contains the optional bounded AI bridge; `providers.mjs` loads the
server-only profile allowlist and implements bounded compatible API calls.
`build.mjs` joins the five browser
dependency-free modules into a single inline script with the HTML/CSS template.
Rebuild and include `index.html` when changing sources. Deployment explicitly
copies only the compiled artifact, never server code or test fixtures.
