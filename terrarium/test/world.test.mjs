import test from 'node:test';
import assert from 'node:assert/strict';
import {
  createWorld, stepWorld, observation, intervene, setWeather, setAction,
  restoreWorld, isLand, distance, VISION,
} from '../src/world.mjs';

function advance(w, seconds, mode = 'demo') {
  for (let i = 0; i < seconds * 4; i++) stepWorld(w, 0.25, mode);
}

test('identical seeds and interventions produce identical rule simulations', () => {
  const a = createWorld(120), b = createWorld(120);
  intervene(a, 'artifact', 17, 7);
  intervene(b, 'artifact', 17, 7);
  advance(a, 320);
  advance(b, 320);
  assert.deepEqual(a, b);
  assert.notDeepEqual(createWorld(121), createWorld(120));
});

test('a sustained simulation remains restorable, finite and on land across weather conditions', () => {
  for (const seed of [1, 42, 20260905, 4294967295]) {
    const w = createWorld(seed);
    intervene(w, 'artifact', 17, 7);
    for (const weather of ['sun', 'rain', 'drought', 'sun']) {
      setWeather(w, weather);
      advance(w, 240);
      assert.deepEqual(restoreWorld(JSON.stringify(w)), w);
      for (const a of w.agents) {
        assert.ok(isLand(a.x, a.z), `${a.name} left land at ${a.x},${a.z}`);
        assert.ok(a.memories.length <= 18);
        for (const count of Object.values(a.inventory)) assert.ok(count >= 0 && count <= 12);
      }
    }
  }
});

test('model observations include only locally visible data and remembered locations', () => {
  const w = createWorld();
  const a = w.agents[0];
  a.x = 0; a.z = 0;
  const other = w.agents[1];
  other.x = 20; other.z = 0;
  other.memories.push({ t: 0, text: 'PRIVATE_SECRET', kind: 'private' });
  intervene(w, 'artifact', 18, 0);
  const artifact = w.entities.at(-1);
  const first = observation(w, a);
  assert.ok(!JSON.stringify(first).includes(artifact.id));
  assert.ok(!JSON.stringify(first).includes('PRIVATE_SECRET'));
  assert.ok(first.nearby.every(e => distance(e, a) <= VISION));
  a.x = 17; a.z = 0;
  advance(w, 0.25, 'model');
  const second = observation(w, a);
  assert.ok(second.nearby.some(e => e.id === artifact.id));
  assert.ok(!JSON.stringify(second).includes('"effect"'));
  assert.ok(!JSON.stringify(second).includes('"nourish"'));
  assert.ok(!JSON.stringify(second).includes('"energize"'));
  a.x = 0; a.z = 0;
  const remembered = observation(w, a).knownPlaces.find(e => e.id === artifact.id);
  assert.deepEqual(Object.keys(remembered).sort(), ['id', 'type', 'x', 'z']);
});

test('model mode never invokes the scripted decision policy', () => {
  const w = createWorld();
  const positions = w.agents.map(a => [a.x, a.z]);
  advance(w, 60, 'model');
  assert.deepEqual(w.agents.map(a => [a.x, a.z]), positions);
  assert.ok(w.agents.every(a => a.action === null));
  assert.equal(w.stats.modelDecisions, 0);
});

test('model actions are validated against perception, available inventory, and target types', () => {
  const w = createWorld();
  const a = w.agents[0];
  a.x = 0; a.z = 0;
  assert.throws(() => setAction(w, a, { action: 'teleport' }, 'Astra'), /不支持/);
  assert.throws(() => setAction(w, a, { action: 'move', x: 20, z: 0 }, 'Astra'), /视野/);
  assert.throws(() => setAction(w, a, { action: 'move', x: -7, z: -2 }, 'Astra'), /陆地/);
  assert.throws(() => setAction(w, a, { action: 'eat' }, 'Astra'), /没有食物/);
  assert.throws(() => setAction(w, a, { action: 'build' }, 'Astra'), /需要/);
  const tree = w.entities.find(e => e.type === 'tree');
  assert.throws(() => setAction(w, a, { action: 'drink', target: tree.id }, 'Astra'), /视野|水源/);
  const shelter = w.entities.find(e => e.type === 'shelter');
  assert.throws(() => setAction(w, a, { action: 'share', target: shelter.id }, 'Astra'), /居民/);
  assert.equal(w.stats.modelDecisions, 0);
});

test('gather then eat conserves resource counts and restores hunger', () => {
  const w = createWorld();
  const a = w.agents[0], food = w.entities.find(e => e.type === 'food');
  Object.assign(a, { x: food.x, z: food.z, hunger: 30 });
  setWeather(w, 'drought');
  const count = food.amount;
  setAction(w, a, { action: 'gather', target: food.id }, 'Astra');
  advance(w, 3, 'model');
  assert.equal(a.inventory.food, 1);
  assert.equal(food.amount, count - 1);
  const hunger = a.hunger;
  setAction(w, a, { action: 'eat' }, 'Astra');
  advance(w, 3, 'model');
  assert.equal(a.inventory.food, 0);
  assert.ok(a.hunger > hunger + 30);
});

test('sharing transfers a resource and records the interaction for both residents', () => {
  const w = createWorld();
  const [a, b] = w.agents;
  Object.assign(a, { x: 0, z: 0 });
  Object.assign(b, { x: 0.8, z: 0 });
  a.inventory.food = 2;
  setAction(w, a, { action: 'share', target: b.id }, 'Astra');
  advance(w, 3, 'model');
  assert.equal(a.inventory.food, 1);
  assert.equal(b.inventory.food, 1);
  assert.equal(w.stats.shares, 1);
  assert.ok(b.memories.some(m => m.kind === 'social'));
});

test('talk conveys a remembered location without leaking private memories', () => {
  const w = createWorld();
  const [a, b] = w.agents;
  Object.assign(a, { x: 0, z: 0 });
  Object.assign(b, { x: 0.8, z: 0 });
  const distant = w.entities.find(e => distance(a, e) > 15);
  a.known.push(distant.id);
  setAction(w, a, { action: 'talk', target: b.id, say: '这里有资源。' }, 'Astra');
  advance(w, 3, 'model');
  assert.ok(b.known.includes(distant.id));
  assert.equal(a.speech, '这里有资源。');
});

test('construction consumes materials, creates shelter, and cannot overlap an object', () => {
  const w = createWorld();
  const a = w.agents[0];
  Object.assign(a, { x: 18, z: 1 });
  Object.assign(a.inventory, { wood: 3, stone: 2 });
  const count = w.entities.length;
  setAction(w, a, { action: 'build' }, 'Astra');
  advance(w, 6, 'model');
  assert.equal(w.entities.length, count + 1);
  assert.equal(w.entities.at(-1).type, 'shelter');
  assert.equal(a.inventory.wood, 0);
  assert.equal(a.inventory.stone, 0);
  Object.assign(a.inventory, { wood: 3, stone: 2 });
  assert.throws(() => setAction(w, a, { action: 'build' }, 'Astra'), /空间/);
});

test('mystery object effects emerge only after an inspect action', () => {
  const w = createWorld();
  intervene(w, 'artifact', 18, 1);
  const artifact = w.entities.at(-1), a = w.agents[0];
  Object.assign(a, { x: 18, z: 0, hunger: 40, energy: 40 });
  assert.equal(w.stats.discoveries, 0);
  setAction(w, a, { action: 'inspect', target: artifact.id }, 'Astra');
  advance(w, 3, 'model');
  assert.equal(w.stats.discoveries, 1);
  assert.ok(a.memories.some(m => m.kind === artifact.id));
  assert.ok(a.hunger > 60 || a.energy > 70);
});

test('routing avoids the lake on a journey to a remembered resource', () => {
  const w = createWorld();
  const a = w.agents[0], target = w.entities.find(e => e.type === 'tree' && e.x === -14);
  Object.assign(a, { x: -1, z: -3 });
  a.known.push(target.id);
  setAction(w, a, { action: 'gather', target: target.id }, 'Astra');
  for (let i = 0; i < 160; i++) {
    stepWorld(w, 0.25, 'model');
    assert.ok(isLand(a.x, a.z));
  }
  assert.equal(a.inventory.wood, 1);
});

test('weather controls resource regeneration and rejects unknown weather', () => {
  const sun = createWorld(), rain = createWorld(), drought = createWorld();
  for (const w of [sun, rain, drought]) w.entities.find(e => e.type === 'water').amount = 10;
  setWeather(rain, 'rain');
  setWeather(drought, 'drought');
  for (const w of [sun, rain, drought]) advance(w, 10, 'model');
  const water = w => w.entities.find(e => e.type === 'water').amount;
  assert.ok(water(rain) > water(sun));
  assert.equal(water(drought), 10);
  assert.ok(drought.agents[0].thirst < sun.agents[0].thirst);
  assert.throws(() => setWeather(sun, 'lava'), /未知/);
});

test('placement limits and corrupt saves fail explicitly', () => {
  const w = createWorld();
  assert.throws(() => intervene(w, 'tree', -7, -2), /湖/);
  assert.throws(() => intervene(w, 'tree', 100, 0), /岛外/);
  assert.throws(() => intervene(w, 'unknown', 18, 1), /未知/);
  for (let i = 0; i < 6; i++) intervene(w, 'resident', 18, i / 10);
  assert.throws(() => intervene(w, 'resident', 18, 0), /12/);
  const bad = structuredClone(w);
  bad.agents[0].hunger = Infinity;
  assert.throws(() => restoreWorld(bad), /无效/);
  assert.throws(() => restoreWorld('{"version":9}'), /损坏/);
  assert.throws(() => stepWorld(w, 5), /步长/);
  assert.throws(() => stepWorld(w, 0.25, 'fake'), /模式/);
});

test('bounded event and memory logs disclose truncation', () => {
  const w = createWorld();
  for (let i = 0; i < 510; i++) setWeather(w, i % 2 ? 'rain' : 'drought');
  assert.equal(w.events.length, 400);
  assert.equal(w.interventions.length, 500);
  assert.ok(w.droppedEvents > 0);
  assert.ok(w.agents.every(a => a.memories.length === 18));
  assert.deepEqual(restoreWorld(JSON.stringify(w)), w);
});
