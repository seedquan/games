# Terrarium

A small, observable Three.js world. Drop objects from above; residents act from
local observations rather than receiving commands from the observer.

## Run

```sh
cd terrarium
npm ci
npm start
```

Open `http://127.0.0.1:4317/terrarium/`. `PORT=4318 npm start` selects another port.
The committed `index.html` is also a completely self-contained static artifact:
no CDN, external assets, API key, or build step is required to play the rule demo.

## Two distinct modes

- **Rule demo** starts immediately without inference charges. Survival priorities,
  gathering, sharing, communication, exploration, and building are programmed
  policies. These are not evidence of learned cooperation or AGI.
- **Astra** is explicitly enabled in the model dialog on the local server. It
  uses the installed, authenticated `copilot` CLI with `--model gpt-6-astra`.
  The account must have access to that model. Login and availability are only
  confirmed by an actual request; the status endpoint only checks the bridge.
  Each resident receives an independent prompt containing its own observation
  and memories. Model tools and custom instructions are disabled, and the
  process runs outside the repository in a temporary directory.

Choose a request limit before enabling Astra (default 12, maximum 24).
The server permits at most 24 requests for its entire lifetime, one at a time,
with a 90-second request timeout and a 30-credit CLI ceiling per request
(the installed CLI's minimum accepted limit, not a fixed charge per request).
**Failed requests count too.** The world freezes while waiting for a decision.
Errors and budget exhaustion pause the simulation, without falling back to
scripted decisions. Closing the tab cancels an in-flight request where possible;
already incurred inference charges cannot be undone.

No model requests happen on startup. GitHub Pages only supports rule mode.
No API key is accepted by or embedded in the browser. The bridge binds to
loopback, validates Host/Origin, requires a per-process request token, and only
serves the compiled page and its two API routes.

## World rules

- Six initial residents; maximum twelve. Radius-eight local perception.
- Hunger, thirst, energy and health; food, water, wood and stone.
- Residents can move, gather, eat, drink, rest, build, inspect, share and talk.
- A shelter costs three wood and two stone. Rest works without a shelter but
  recovers less energy. All shelters are public.
- Sharing transfers food, not nutrition. Talking can convey a resource location.
- Mystery objects have a hidden nourishing or energizing effect, revealed by
  interacting. These two effects and available actions are predefined.
- Rain triples resource regeneration. Drought stops regeneration and increases
  water consumption. The decorative lake is not an interactable drinking source;
  residents drink from placed springs.
- Seeded rule simulation with fixed time steps; model responses are not
  deterministic. Same-seed resets preserve the starting conditions.

The observer can see everything. A model receives only that resident's nearby
objects, visible neighbors, remembered locations and last ten memories. Hidden
artifact effects and other residents' private state are excluded. Terrain and
the action vocabulary are given affordances, not learned physics.

## Controls and records

Choose an object, then click land to place it. Escape returns to observation.
Drag to orbit, scroll to zoom, right-drag to pan. Click a resident or its roster
button to inspect it. The resident-view button filters visible objects and
neighbors, but still shows the terrain.

Space pauses; 1x/3x/10x buttons adjust simulation speed, not model concurrency.
The world does not progress while the page is hidden or closed. Save/restore uses
this browser's local storage. Restore pauses and never reconnects a model.
Export downloads the state plus the most recent 400 events and 500 interventions;
this bounded log is **not** a complete replay. Existing demo memories persist
when switching to a model; reset first for a fresh comparison.

## Development

```sh
npm run build
npm test
```

`src/world.mjs` is the seeded simulation; `src/view.mjs` handles Three.js;
`src/app.mjs` handles observation controls and model scheduling. `server.mjs`
contains the optional model bridge. `build.mjs` bundles code, CSS, Three.js and
its license into `index.html`. Commit the rebuilt artifact when changing source.

This is an open-ended behavior sandbox, **not an AGI certification**. Assess
observed outcomes against the known scripted baseline rather than inferring
intelligence from narrative or animation.
