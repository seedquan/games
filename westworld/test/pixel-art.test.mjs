import test from 'node:test';
import assert from 'node:assert/strict';
import { residentPortrait, residentFigure, placeArtwork, townBackdrop } from '../src/pixel-art.mjs';
import { createWorld, PLACES } from '../src/world.mjs';

test('each resident has a distinct rounded portrait in all display sizes', () => {
  const portraits = createWorld().agents.map(a => residentPortrait(a.id));
  assert.equal(new Set(portraits.map(p => p.replace(/data-portrait="[^"]+"/, ''))).size, 4);
  for (const a of createWorld().agents) for (const size of ['card', 'map', 'inspector']) {
    const svg = residentPortrait(a.id, size);
    assert.match(svg, /viewBox="0 0 16 16".*shape-rendering="geometricPrecision"/);
    assert.match(svg, /aria-hidden="true"/);
    assert.doesNotMatch(svg, /<text|<image|https?:\/\/|#[0-9a-f]{3,8}\b/i);
    for (const [, x, y] of svg.matchAll(/M(\d+) (\d+)h1v1h-1z/g)) {
      assert.ok(Number(x) < 16 && Number(y) < 16);
    }
  }
  assert.throws(() => residentPortrait('unknown'));
  assert.throws(() => residentPortrait('mara', 'unknown'));
});

test('town art is local and theme-aware, with roads derived from the real map', () => {
  for (const p of PLACES) {
    assert.match(placeArtwork(p.id), /shape-rendering="geometricPrecision"/);
    assert.match(placeArtwork(p.id), /var\(--cp-/);
    assert.doesNotMatch(placeArtwork(p.id), /<image|https?:\/\/|#[0-9a-f]{3,8}\b/i);
  }
  const roads = [...townBackdrop(PLACES).matchAll(/data-road="([^"]+)"/g)].map(([, road]) => road);
  const expected = PLACES.flatMap((p, i) => p.links.filter(id => PLACES.findIndex(q => q.id === id) > i).map(id => `${p.id}-${id}`));
  assert.deepEqual(roads, expected);
  assert.equal(new Set(roads).size, 9);
  assert.throws(() => placeArtwork('unknown'));
  const scenery = townBackdrop(PLACES);
  assert.equal([...scenery.matchAll(/data-art=/g)].length, 7);
  assert.doesNotMatch(scenery, /<svg|<image|https?:\/\/|#[0-9a-f]{3,8}\b/i);
});

test('residents have full-body two-frame walking sprites rather than portrait tiles', () => {
  for (const a of createWorld().agents) {
    const sprite = residentFigure(a.id);
    assert.match(sprite, /viewBox="0 0 16 24"/);
    assert.match(sprite, /step-a/); assert.match(sprite, /step-b/);
    assert.doesNotMatch(sprite, /<image|https?:\/\/|#[0-9a-f]{3,8}\b/i);
  }
  assert.throws(() => residentFigure('unknown'));
});
