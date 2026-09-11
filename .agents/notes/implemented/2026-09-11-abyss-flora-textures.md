# Root-anchored flora textures

Status: implemented.

## Decision

Five sector plants and one rigid crystal sprout now use a transparent 768×512 WebP atlas (129,354 encoded bytes, 1.5 MiB decoded). Authored root pivots anchor a small horizontal shear: at most .035 with full effects and .015 with reduced effects. Crystals and effects-off plants do not sway. Each visible clump costs one image crop, with no filter, glow pass or per-frame texture allocation. The genuine generated alpha survives resizing and compression.

The existing procedural renderer remains the unloaded fallback. Touch devices with effects off continue omitting flora. Culling accounts for the full painted height. No terrain generation, collision, save, combat or input rules change. The isolated ground preview includes a regional plant and crystal for visual checks.

## Tradeoffs and verification

A small shear provides restrained movement without extra animation frames or individual leaf bones. One plant is reused per sector and crystals share one cell; this is not a complete vegetation library. Three focused checks cover all six crops, stable roots, bounded sway, feature immutability, fallback, culling and touch/off dispatch. Actual Canvas specimens were inspected at enlarged and gameplay sizes. Short desktop browser samples cannot establish mobile or whole-run acceptance.
