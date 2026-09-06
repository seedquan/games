# A real shared home in the center of town

- **Status:** implemented
- **Date:** 2026-09-05
- **Category:** world topology and persistence

## Decision

Add `home` as the seventh location rather than drawing an unreachable house.
The larger pixel house is centered in the existing continuous scene, with a
small courtyard and seating. It connects to `well` and `ridge`; the original
six locations and all seven old links remain, for nine links total.

The house is public shelter with initially empty stocks. Every resident may
move there, rest, meet others or take observer-dropped supplies. It does not
merge memories, goals or carried inventories. The rule baseline goes home
when tired and directly adjacent, but only if the move is affordable. No new
actions, automatic teleportation, free food or extra model requests are added.

One shared geometry helper supplies central road detours to both the SVG and
movement interpolation so residents do not walk through the house. Courtyard
standing positions and the central column's fog regions are adjusted without
exposing distant people or live resources.

## Compatibility

World payload version 2 requires all seven locations. Valid version-1 saves
are first structurally validated against the old six-place schema, then gain
one empty sheltered home. No old visits, observations, event text or audit
records are rewritten, and no actions are synthesized. The archive envelope
stays `westworld-lab-v1`; it already contains the independent payload version.
Historical audit validation explicitly permits the exact legacy topology.
Live bridge validation does not.

The bridge advertises `worldVersion`. A new page blocks consent for an older
bridge before spending a request. Existing running bridges need a deliberate
restart to load the new engine; merely rebuilding the frontend is insufficient.
The bridge's loopback, origin/token, tool-denial, timeout and budget boundaries
remain unchanged. Restarting must not silently replenish a used request budget.

Saved experiment results are retained, but future version-2 rule trajectories
can differ because of the added location, routes and home-seeking behavior.
Do not interpret old and new engine runs as identical experiments.

## Coverage

World cases exercise reciprocal connectivity, all residents sharing shelter,
resource conservation, local privacy, affordable homeward moves and exact
legacy-history retention. Scene cases cover road/motion agreement and local
home visibility. Browser cases exercise selection, public drops, all four
residents in the courtyard, mobile layout and version-gated AI consent.
