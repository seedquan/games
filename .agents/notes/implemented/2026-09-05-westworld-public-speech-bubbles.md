# Overhead public-action and speech captions

- **Status:** implemented
- **Date:** 2026-09-05
- **Category:** observer presentation and privacy

Display recent actions and spoken dialogue over residents, derived from the
engine's public action events and matching audit decisions. Do not treat
intentions, goals, memories or observer whispers as speech. Failed actions
cannot create successful speech bubbles. No caption generation uses inference.

The observer sees public outcomes; local view additionally requires the
selected resident to have been present in the recorded local observation.
Do not expose a newly visible resident's old conversation or departure origin.
The projected data contains only the display label, public outcome, source and
successful utterance, never the audit observation itself.

Ordinary labels describe the last committed action. Only actual walking or a
pending model request uses an in-progress label; completing movement restores
the committed label without scheduling another simulation action.

Spread gathered residents' bubbles into bounded columns, with connector lines
to their sprites. Narrow scenes use one-line dialogue previews, while selecting
a speaker reveals the full text below the map. All untrusted text is escaped
or assigned with textContent. Preserve the inner map's overflow:clip invariant.
Zoom/resize may redraw captions but must not mutate world state, create model
requests or persist extra actions. This presentation state is not saved.
