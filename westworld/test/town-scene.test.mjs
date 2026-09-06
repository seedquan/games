import test from 'node:test';
import assert from 'node:assert/strict';
import { createWorld, PLACES, advance, intervene } from '../src/world.mjs';
import { townPoint, townRoadPoints, TOWN_WIDTH, TOWN_HEIGHT } from '../src/pixel-art.mjs';
import { islandPlanPoint } from '../src/island-layout.mjs';
import { projectTown, townScenery, townResidentPoint, residentPublicActivity, townBubbleLayout, createTownMotion, sampleTownMotion, townMotionFrames } from '../src/town-scene.mjs';

test('town projection exposes only scene state and never hidden observations or private residents', () => {
  const w = createWorld();
  const observer = projectTown(w, 'mara', false), local = projectTown(w, 'mara', true);
  assert.equal(observer.residents.length, 4);
  assert.equal(local.residents.length, 1);
  assert.equal(local.residents[0].id, 'mara');
  assert.equal(local.places.filter(p => p.visible).length, 1);
  assert.ok(local.places.filter(p => !p.visible).every(p => !Object.hasOwn(p, 'items') && !Object.hasOwn(p, 'crop')));
  for (const secret of ['goal', 'memories', 'inventory', 'known', 'deviceEffect']) assert.ok(!JSON.stringify(observer).includes(secret));
  intervene(w, { type: 'drop', location: 'farm', item: 'water', amount: 1 });
  assert.deepEqual(projectTown(w, 'mara', true), local);
  assert.throws(() => projectTown(w, 'unknown', true));
});

test('the continuous scenery has seven buildings, nine real links and hides live crop state under fog', () => {
  const w = createWorld();
  w.places.farm.crop = 2;
  const all = townScenery(projectTown(w, 'mara', false));
  const local = townScenery(projectTown(w, 'mara', true));
  w.places.farm.crop = 0;
  assert.equal(townScenery(projectTown(w, 'mara', true)), local);
  assert.notEqual(townScenery(projectTown(w, 'mara', false)), all);
  assert.equal([...all.matchAll(/<svg/g)].length, 1);
  assert.equal([...all.matchAll(/data-art=/g)].length, 7);
  assert.equal([...all.matchAll(/data-road=/g)].length, 9);
  assert.equal([...local.matchAll(/data-fog=/g)].length, 6);
  for (const p of PLACES) {
    const point = islandPlanPoint(townPoint(p));
    assert.ok(point.x > 32 && point.x < TOWN_WIDTH - 32 && point.y < TOWN_HEIGHT - 40);
  }
});

test('the central home has its own visible courtyard and movement uses the drawn roads around its roof', () => {
  const w = createWorld(), home = PLACES.find(p => p.id === 'home'), well = PLACES.find(p => p.id === 'well');
  assert.deepEqual(townPoint(home), { x: 0, y: 40 });
  const route = townRoadPoints(well, home);
  townRoadPoints(home, well).forEach((p,i) => assert.ok(Math.hypot(p.x-route.at(-i-1).x,p.y-route.at(-i-1).y)<1e-8));
  assert.ok(route.slice(1, -1).some(p => p.x < -80));
  w.agents[0].location = 'well';
  const tracker = createTownMotion();
  tracker.update(projectTown(w, 'mara', false), w);
  advance(w, { action: 'move', target: 'home' });
  const motion = tracker.update(projectTown(w, 'mara', false), w, { now: 10 }).get('mara');
  assert.deepEqual(motion.points.slice(1, -1), route);
  const local = projectTown(w, 'mara', true), scenery = townScenery(local);
  assert.equal(local.places.find(p => p.id === 'home').visible, true);
  assert.doesNotMatch(scenery, /data-fog="home"/);
  assert.match(scenery, /ellipse data-fog="well"/);
  assert.match(scenery, /ellipse data-fog="ridge"/);
  w.agents.forEach(a => { a.location = 'home'; });
  const residents = projectTown(w, 'mara', true).residents;
  assert.equal(residents.length, 4);
  assert.equal(new Set(residents.map(a => JSON.stringify(townResidentPoint(a)))).size, 4);
});

test('motion follows an executed adjacent move through the actual road anchors', () => {
  const w = createWorld(), tracker = createTownMotion();
  tracker.update(projectTown(w, 'mara', false), w, { now: 0 });
  advance(w, { action: 'move', target: 'well' });
  const motion = tracker.update(projectTown(w, 'mara', false), w, { now: 100 }).get('mara');
  assert.ok(motion);
  assert.deepEqual(motion.points.slice(1, -1), townRoadPoints(PLACES.find(p => p.id === 'workshop'),PLACES.find(p => p.id === 'well')));
  assert.deepEqual(motion.points.at(-1), townResidentPoint(w.agents[0]));
  const middle = sampleTownMotion(motion, 340).point;
  assert.ok(middle.x < motion.points[0].x && middle.x > motion.points.at(-1).x);
  const frames = townMotionFrames(motion, 340);
  assert.equal(frames[0].offset, 0);
  assert.equal(frames.at(-1).offset, 1);
  assert.ok(frames.every((f, i) => !i || f.offset >= frames[i - 1].offset));
  assert.equal(tracker.update(projectTown(w, 'mara', false), w, { now: 580 }).size, 0);
});

test('stationary residents and redraws never start fake walking or advance the engine', () => {
  const w = createWorld(), before = structuredClone(w), tracker = createTownMotion();
  assert.equal(tracker.update(projectTown(w, 'mara', false), w, { now: 0 }).size, 0);
  assert.equal(tracker.update(projectTown(w, 'mara', false), w, { now: 100 }).size, 0);
  assert.deepEqual(w, before);
});

test('pause, reduced-motion preference, viewpoint changes and restored worlds snap to committed positions', () => {
  for (const mode of ['pause', 'viewpoint', 'restore']) {
    const w = createWorld(), tracker = createTownMotion();
    tracker.update(projectTown(w, 'mara', false), w, { now: 0 });
    advance(w, { action: 'move', target: 'well' });
    assert.equal(tracker.update(projectTown(w, 'mara', false), w, { now: 10 }).size, 1);
    const next = mode === 'restore' ? structuredClone(w) : w;
    const motions = tracker.update(projectTown(next, 'mara', mode === 'viewpoint'), next, { now: 50, animate: mode !== 'pause' });
    assert.equal(motions.size, 0);
    assert.equal(next.agents[0].location, 'well');
  }
});

test('newly visible residents do not animate from a hidden origin and departing residents disappear immediately', () => {
  const w = createWorld(), tracker = createTownMotion();
  tracker.update(projectTown(w, 'mara', true), w, { now: 0 });
  w.agents[1].location = 'workshop';
  assert.equal(tracker.update(projectTown(w, 'mara', true), w, { now: 10 }).size, 0);
  w.agents[1].location = 'well';
  const scene = projectTown(w, 'mara', true);
  assert.equal(scene.residents.length, 1);
  assert.equal(tracker.update(scene, w, { now: 20 }).size, 0);
});

test('overhead activity comes from actual public outcomes, never private intentions or whispers', () => {
  const w = createWorld(2049, 'cooperation'), a = w.agents[0];
  advance(w, { action: 'talk', target: 'eli', message: '大家回来喝水吧。', intent: 'PRIVATE_INTENT' });
  intervene(w, { type: 'whisper', agent: 'mara', message: 'PRIVATE_WHISPER' });
  const activity = residentPublicActivity(w, a);
  assert.equal(activity.label, '交谈');
  assert.equal(activity.speech, '大家回来喝水吧。');
  assert.equal(activity.source, 'rule');
  assert.doesNotMatch(JSON.stringify(projectTown(w, 'mara', false)), /PRIVATE_INTENT|PRIVATE_WHISPER/);
  assert.deepEqual(residentPublicActivity(w, a, 'eli'), activity);
  w.agents[1].location = 'well';
  advance(w, { action: 'talk', target: 'mara', message: '这句没有说到对方身边。' });
  assert.equal(residentPublicActivity(w, w.agents[1]).speech, null);
  assert.equal(residentPublicActivity(w, w.agents[1]).label, '行动未成功');
});

test('local captions do not reveal earlier unobserved speech, actions or a hidden arrival origin', () => {
  const w = createWorld();
  w.agents[1].location = 'workshop';
  advance(w, { action: 'talk', target: 'eli', message: 'EARLIER_CONVERSATION' });
  w.agents[2].location = 'workshop';
  assert.equal(residentPublicActivity(w, w.agents[0], 'nora'), null);
  assert.doesNotMatch(JSON.stringify(projectTown(w, 'nora', true)), /EARLIER_CONVERSATION/);
  w.agents[2].location = 'saloon';
  advance(w, { action: 'move', target: 'well' });
  w.agents[2].location = 'well';
  assert.equal(residentPublicActivity(w, w.agents[1], 'nora'), null);
  assert.doesNotMatch(JSON.stringify(projectTown(w, 'nora', true)), /离开旧工坊/);
});

test('shared-home captions spread into bounded nonoverlapping columns without mutating the world', () => {
  const w = createWorld();
  w.agents.forEach(a => { a.location = 'home'; });
  const before = structuredClone(w), residents = projectTown(w, 'mara', false).residents;
  for (const pixelWidth of [286, 358, 480, 1080, 2160]) {
    const layout = townBubbleLayout(residents, pixelWidth);
    const boxes = residents.map(a => {
      const { shift, width } = layout.get(a.id), center = islandPlanPoint(townResidentPoint(a)).x / TOWN_WIDTH * pixelWidth + shift;
      return { left: center - width / 2, right: center + width / 2 };
    }).sort((a, b) => a.left - b.left);
    assert.ok(boxes.every(b => b.left >= 5.99 && b.right <= pixelWidth - 5.99));
    assert.ok(boxes.every((b, i) => !i || b.left - boxes[i - 1].right >= 5.99));
  }
  assert.deepEqual(w, before);
  assert.throws(() => townBubbleLayout(residents, NaN), /caption width/);
});
