import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { runInNewContext } from 'node:vm';
import * as engine from '../src/world.mjs';
import * as art from '../src/pixel-art.mjs';
import * as town from '../src/town-scene.mjs';
import * as town3d from '../src/town-3d.mjs';
import * as island from '../src/island-layout.mjs';

const source = (await readFile(new URL('../src/app.mjs', import.meta.url), 'utf8')).replace(/^import .*\n/gm, '');
const template = await readFile(new URL('../src/template.html', import.meta.url), 'utf8');
const stylesheet = await readFile(new URL('../src/style.css', import.meta.url), 'utf8');
const compiled = [...(await readFile(new URL('../index.html', import.meta.url), 'utf8')).matchAll(/<script>([\s\S]*?)<\/script>/g)].at(-1)[1];
const AUTO_KEY = 'westworld-lab-auto-v1', SAVE_KEY = 'westworld-lab-manual-v1', MODELS_KEY = 'westworld-lab-resident-models-v1';
const profiles = [
  { id: 'fast', label: '快速', provider: 'copilot', providerLabel: 'Copilot', adapter: 'copilot', model: 'test', effort: 'low', available: true },
  { id: 'deep', label: '深度', provider: 'copilot', providerLabel: 'Copilot', adapter: 'copilot', model: 'test', effort: 'high', available: true },
  { id: 'other-model', label: '另一个模型', provider: 'copilot', providerLabel: 'Copilot', adapter: 'copilot', model: 'other-model', effort: 'low', available: true },
  { id: 'api', label: 'API 模型', provider: 'custom-api', providerLabel: 'Custom API', adapter: 'openai-compatible', model: 'api-model', effort: 'medium', available: true },
  { id: 'missing-key', label: '未配置', provider: 'missing', providerLabel: 'Missing key', adapter: 'openai-compatible', model: 'api-model', effort: 'low', available: false },
];

class Element {
  constructor() {
    this.listeners = new Map();
    this.classList = {
      add() {}, remove() {}, toggle() {},
    };
    this.value = '1'; this.checked = false; this.disabled = false; this.hidden = false;
    this.open = false; this.children = []; this.files = [];
    this.scrollTop = 0; this.scrollHeight = 0; this.textContent = ''; this.innerHTML = '';
    this.style = {}; this.scrollLeft = 0; this.clientWidth = 480; this.clientHeight = 320;
  }
  addEventListener(type, listener) {
    if (!this.listeners.has(type)) this.listeners.set(type, []);
    this.listeners.get(type).push(listener);
  }
  async emit(type) {
    for (const listener of this.listeners.get(type) || []) await listener({ target: this });
  }
  setAttribute() {}
  getContext() { return {}; }
  querySelectorAll() { return []; }
  showModal() { this.open = true; }
  close() { this.open = false; return this.emit('close'); }
}

function browser({ saved, preferences, storageFailure = false, bundle = false, decide, bridgeStatus, canvasSupport = true } = {}) {
  const elements = new Map([...template.matchAll(/\bid="([^"]+)"/g)].map(([, id]) => [id, new Element()]));
  const storage = new Map(saved ? [[AUTO_KEY, saved]] : []);
  if (preferences) storage.set(MODELS_KEY, preferences);
  if (!canvasSupport || bundle) elements.get('town-canvas').getContext = () => null;
  let fetches = 0, writes = 0, time = 0, nextInterval = 0;
  const intervals = new Map(), requests = [];
  const document = new Element();
  const motionPreference = new Element();
  motionPreference.matches = false;
  const window = new Element();
  window.matchMedia = () => motionPreference;
  window.requestAnimationFrame = () => 1;
  window.cancelAnimationFrame = () => {};
  document.getElementById = id => {
    assert.ok(elements.has(id), `Missing DOM element ${id}`);
    return elements.get(id);
  };
  document.querySelector = () => [...elements.values()].find(element => element.open);
  document.documentElement = new Element();
  const context = {
    ...engine, ...art, ...town, ...town3d, ...island, document, window, console, structuredClone, TextEncoder, AbortController, AbortSignal,
    createTown3DView: () => ({
      camera: town3d.createTownCamera(), enable() {}, update() {},
      setCamera(yaw, tilt) { this.camera = town3d.createTownCamera(yaw, tilt); },
      reset() { this.camera = town3d.createTownCamera(); },
    }),
    performance: { now: () => time },
    location: { hostname: '127.0.0.1', protocol: 'http:' },
    localStorage: {
      getItem: key => storage.get(key) ?? null,
      setItem: (key, value) => {
        writes++;
        if (storageFailure) throw new Error('storage full');
        storage.set(key, value);
      },
    },
    fetch: async (url, options) => {
      fetches++;
      if (url === '/api/decide') {
        const request = JSON.parse(options.body);
        requests.push(request);
        if (decide) return decide(request, options);
        return { ok: true, json: async () => ({ decision: { action: 'wait' }, remaining: 24 - requests.length }) };
      }
      return { ok: true, json: async () => bridgeStatus ?? ({
        service: 'westworld', worldVersion: engine.VERSION, token: 'test', remaining: 24, model: 'test', defaultProfile: 'fast',
        profiles,
      }) };
    },
    setTimeout: () => 1, clearTimeout() {},
    setInterval: callback => { intervals.set(++nextInterval, callback); return nextInterval; },
    clearInterval: id => intervals.delete(id),
  };
  runInNewContext(bundle ? compiled : `${source}\nglobalThis.appState = () => ({ world, mode, running, busy, bridgeStatus, calls, connectionId, lastModelCall });`, context);
  return {
    element: id => elements.get(id), storage, context, requests, intervals, motionPreference,
    tick(ms) { time += ms; for (const callback of intervals.values()) callback(); },
    snapshot: () => JSON.stringify(context.appState().world),
    fetches: () => fetches, writes: () => writes,
    async choose(raw, name = 'experiment.json') {
      elements.get('import-file').files = [{ name, size: Buffer.byteLength(raw), text: async () => raw }];
      await elements.get('import-file').emit('change');
    },
  };
}

const flush = () => new Promise(resolve => setImmediate(resolve));
async function enableModel(b, profile = 'fast') {
  await b.element('model-open').emit('click');
  await flush();
  b.element('model-profile').value = profile;
  await b.element('model-profile').emit('change');
  b.element('model-consent').checked = true;
  b.element('budget').value = '12';
  await b.element('model-consent').emit('change');
  await b.element('model-enable').emit('click');
}

function archive() {
  const w = engine.createWorld(42, 'unknown');
  engine.intervene(w, { type: 'whisper', agent: 'mara', message: 'Keep this memory.' });
  engine.advance(w, { action: 'take', item: 'device' }, 'model');
  engine.advance(w, { action: 'rest' }, 'rule');
  return JSON.stringify(engine.exportRecord(w));
}

test('import previews locally then restores partial progress paused, disconnected and autosaved', async () => {
  const b = browser(), manual = 'separate checkpoint';
  b.storage.set(SAVE_KEY, manual);
  await b.element('model-open').emit('click');
  await new Promise(resolve => setImmediate(resolve));
  b.element('model-consent').checked = true;
  await b.element('model-enable').emit('click');
  assert.equal(b.context.appState().mode, 'model');
  const callsBefore = b.fetches(), original = b.snapshot();
  await b.element('import-open').emit('click');
  await b.choose(archive());
  assert.equal(b.snapshot(), original);
  assert.match(b.element('import-preview').textContent, /2\/4/);
  assert.equal(b.element('import-confirm').disabled, false);
  await b.element('import-confirm').emit('click');
  const state = b.context.appState();
  assert.equal(state.mode, 'rule');
  assert.equal(state.running, false);
  assert.equal(state.busy, false);
  assert.equal(state.bridgeStatus, null);
  assert.equal(state.calls, 0);
  assert.equal(state.world.turn, 2);
  assert.equal(state.world.metrics.actions, 2);
  assert.equal(engine.currentAgent(state.world).id, 'nora');
  const expected = JSON.parse(archive()).world;
  assert.deepEqual(state.world.agents, expected.agents);
  assert.deepEqual(state.world.audit, expected.audit);
  assert.equal(b.storage.get(SAVE_KEY), manual);
  assert.deepEqual(JSON.parse(b.storage.get(AUTO_KEY)).world, state.world);
  assert.equal(b.fetches(), callsBefore);
  assert.equal(b.element('import-dialog').open, false);
  assert.equal(b.element('import-confirm').disabled, true);
});

test('cancelling or rejecting an import leaves current world and both save slots untouched', async () => {
  const b = browser(), original = b.snapshot();
  b.storage.set(AUTO_KEY, 'existing auto'); b.storage.set(SAVE_KEY, 'existing manual');
  await b.element('import-open').emit('click');
  await b.choose(archive());
  await b.element('import-cancel').emit('click');
  assert.equal(b.snapshot(), original);
  assert.equal(b.writes(), 0);
  assert.equal(b.fetches(), 0);
  await b.element('import-open').emit('click');
  await b.choose('{"format":"westworld-lab-v1","world":null}');
  assert.equal(b.element('import-confirm').disabled, true);
  assert.match(b.element('import-preview').textContent, /无法导入/);
  assert.equal(b.snapshot(), original);
  assert.equal(b.storage.get(AUTO_KEY), 'existing auto');
  assert.equal(b.storage.get(SAVE_KEY), 'existing manual');
});

test('oversized files are rejected before reading and do not replace the active preview', async () => {
  const b = browser();
  await b.element('import-open').emit('click');
  await b.choose(archive());
  let reads = 0;
  b.element('import-file').files = [{ size: engine.MAX_RECORD_BYTES + 1, text: async () => { reads++; return archive(); } }];
  await b.element('import-file').emit('change');
  assert.equal(reads, 0);
  assert.equal(b.element('import-confirm').disabled, true);
  assert.match(b.element('import-preview').textContent, /10 MB/);
});

test('a stale file read cannot override a newer selection or a closed import dialog', async () => {
  for (const close of [false, true]) {
    const b = browser();
    await b.element('import-open').emit('click');
    let finish;
    b.element('import-file').files = [{ size: 100, text: () => new Promise(resolve => { finish = resolve; }) }];
    const pending = b.element('import-file').emit('change');
    if (close) await b.element('import-cancel').emit('click');
    else await b.choose(JSON.stringify(engine.exportRecord(engine.createWorld(99))));
    const preview = b.element('import-preview').textContent;
    finish(archive());
    await pending;
    assert.equal(b.element('import-preview').textContent, preview);
    assert.equal(b.element('import-confirm').disabled, close);
    assert.equal(b.writes(), 0);
    assert.equal(b.fetches(), 0);
  }
});

test('storage failures remain visible after an otherwise successful import', async () => {
  const b = browser({ storageFailure: true });
  await b.element('import-open').emit('click');
  await b.choose(archive());
  await b.element('import-confirm').emit('click');
  assert.equal(b.context.appState().world.turn, 2);
  assert.match(b.element('notice').textContent, /storage full/);
  assert.equal(b.storage.has(AUTO_KEY), false);
});

test('browser reload uses the same validator and never reconnects or rewrites progress on startup', () => {
  const b = browser({ saved: archive() });
  assert.equal(b.context.appState().world.turn, 2);
  assert.equal(b.context.appState().mode, 'rule');
  assert.equal(b.fetches(), 0);
  assert.equal(b.writes(), 0);
  const broken = browser({ saved: '{"format":"westworld-lab-v1","world":null}' });
  assert.match(broken.element('notice').textContent, /无法读取/);
  assert.equal(broken.context.appState().world.turn, 0);
  assert.equal(broken.writes(), 0);
});

test('standalone artifact boots and restores through its bundled import controls', async () => {
  const b = browser({ bundle: true });
  assert.match(b.element('resident-list').innerHTML, /data-agent="mara"/);
  await b.element('import-open').emit('click');
  await b.choose(archive());
  assert.equal(b.element('import-confirm').disabled, false);
  await b.element('import-confirm').emit('click');
  assert.equal(engine.restoreRecord(b.storage.get(AUTO_KEY)).turn, 2);
  assert.equal(b.element('mode-label').textContent, '规则演示');
  assert.match(b.element('run-state').textContent, /暂停/);
  assert.equal(b.fetches(), 0);
});

test('model profiles require renewed consent, never charge on selection and keep requests sequential', async () => {
  const b = browser();
  await enableModel(b, 'deep');
  assert.equal(b.fetches(), 1);
  assert.equal(b.requests.length, 0);
  assert.equal(b.element('speed').disabled, true);
  assert.match(b.element('model-progress').textContent, /Copilot.*test.*high/);
  await b.element('step').emit('click'); await flush();
  assert.equal(b.context.appState().world.round, 1);
  assert.deepEqual(b.requests.map(r => r.observation.self.id), ['mara', 'eli', 'nora', 'silas']);
  assert.ok(b.requests.every(r => r.profile === 'deep'));
  assert.equal(b.intervals.size, 0);
  await b.element('model-open').emit('click'); await flush();
  b.element('model-consent').checked = true;
  await b.element('model-consent').emit('change');
  assert.equal(b.element('model-enable').disabled, false);
  b.element('model-profile').value = 'fast';
  await b.element('model-profile').emit('change');
  assert.equal(b.element('model-consent').checked, false);
  assert.equal(b.element('model-enable').disabled, true);
  assert.equal(b.requests.length, 4);
  await b.element('model-dialog').close();
  await b.element('step').emit('click'); await flush();
  assert.equal(b.requests.length, 8);
  assert.ok(b.requests.every(r => r.profile === 'deep'), 'A cancelled dialog must not change the authorized profile.');
});

test('waiting UI updates once per tick without calls or world mutation and retains failure timing', async () => {
  let finish;
  const b = browser({ decide: () => new Promise(resolve => { finish = resolve; }) });
  await enableModel(b);
  await b.element('step').emit('click'); await flush();
  const original = b.snapshot(), fetches = b.fetches();
  assert.match(b.element('model-progress').textContent, /第 1\/4.*林岚.*0 秒/);
  b.tick(8000);
  assert.match(b.element('model-progress').textContent, /8 秒/);
  assert.equal(b.snapshot(), original); assert.equal(b.fetches(), fetches);
  finish({ ok: false, json: async () => ({
    error: 'model unavailable', remaining: 23,
    timing: { totalMs: 7500, processSpawnMs: 50, firstOutputMs: null, processExitMs: 7400 },
  }) });
  await flush();
  assert.match(b.element('model-timing').textContent, /8.0 秒（失败）/);
  assert.match(b.element('model-timing').textContent, /服务端 7.5 秒.*首输出 未提供/);
  assert.match(b.element('notice').textContent, /model unavailable/);
  assert.equal(b.requests.length, 1);
  assert.equal(b.intervals.size, 0);
  assert.equal(b.context.appState().world.turn, 0);
  assert.equal(b.context.appState().running, false);
});

test('pausing an in-flight model call aborts it and cleans the progress timer without another request', async () => {
  const b = browser({ decide: (_, { signal }) => new Promise((_, reject) => {
    signal.addEventListener('abort', () => reject(Object.assign(new Error('aborted'), { name: 'AbortError' })), { once: true });
  }) });
  await enableModel(b);
  await b.element('step').emit('click'); await flush();
  b.tick(3000);
  await b.element('play').emit('click'); await flush();
  assert.equal(b.intervals.size, 0);
  assert.equal(b.requests.length, 1);
  assert.equal(b.context.appState().world.turn, 0);
  assert.match(b.element('model-timing').textContent, /3.0 秒（已取消）/);
  b.tick(5000);
  assert.equal(b.requests.length, 1);
});

test('outdated bridge is visibly rejected before consent or model calls', async () => {
  const b = browser({ bridgeStatus: { service: 'westworld', token: 'test', remaining: 24, model: 'old' } });
  await b.element('model-open').emit('click'); await flush();
  assert.match(b.element('bridge-status').textContent, /版本不兼容.*重启/);
  assert.equal(b.element('model-enable').disabled, true);
  assert.equal(b.element('model-profile').disabled, true);
  assert.equal(b.requests.length, 0);
});

test('a provider-capable bridge with the old map cannot spend a request on the new home', async () => {
  const b = browser({ bridgeStatus: { service: 'westworld', worldVersion: 1, token: 'test', remaining: 24, defaultProfile: 'fast', profiles } });
  await b.element('model-open').emit('click'); await flush();
  assert.match(b.element('bridge-status').textContent, /地图版本不兼容.*共同的家.*重启/);
  assert.equal(b.element('model-enable').disabled, true);
  assert.equal(b.requests.length, 0);
});

test('restoring legacy names updates cards and whisper targets without resetting progress', () => {
  const saved = JSON.parse(archive());
  saved.world.agents.forEach((a, i) => { a.name = ['玛拉', '伊莱', '诺拉', '塞拉斯'][i]; a.initial = a.id[0].toUpperCase(); });
  const b = browser({ saved: JSON.stringify(saved) });
  assert.equal(b.context.appState().world.turn, 2);
  for (const name of ['林岚', '陈野', '沈宁', '周禾']) {
    assert.ok(b.element('resident-list').innerHTML.includes(name));
    assert.ok(b.element('whisper-agent').innerHTML.includes(name));
  }
  assert.equal(b.fetches(), 0);
});

test('pixel portraits appear on cards, inspector and map without external assets', () => {
  const b = browser();
  for (const a of b.context.appState().world.agents) {
    assert.ok(b.element('resident-list').innerHTML.includes(`data-portrait="${a.id}"`));
    assert.ok(b.element('town-residents').innerHTML.includes(`data-portrait="${a.id}"`));
  }
  assert.match(b.element('inspector-heading').innerHTML, /inspector-avatar.*data-portrait="mara"/);
  const map = b.element('town-landscape').innerHTML + b.element('town-residents').innerHTML;
  assert.equal([...map.matchAll(/data-art=/g)].length, 7);
  assert.equal([...map.matchAll(/data-road=/g)].length, 9);
  assert.doesNotMatch(map + b.element('resident-list').innerHTML, /https?:\/\/|<image|<img/);
  assert.equal(b.fetches(), 0);
});

test('pixel map retains clickable places and hides remote people and live stocks in resident view', async () => {
  const b = browser();
  const world = b.context.appState().world;
  await b.element('perspective').emit('click');
  const map = b.element('town-landscape').innerHTML + b.element('town-residents').innerHTML + b.element('town-places').innerHTML;
  assert.match(map, /data-portrait="mara"/);
  for (const id of ['eli', 'nora', 'silas']) assert.ok(!map.includes(`data-portrait="${id}"`));
  for (const p of engine.PLACES) {
    assert.ok(map.includes(`data-place="${p.id}"`));
    assert.ok(map.includes(`data-art="${p.id}"`));
  }
  assert.equal([...map.matchAll(/data-fog=/g)].length, 6);
  assert.equal([...b.element('town-places').innerHTML.matchAll(/当前不可见/g)].length, 6);
  assert.equal(world.turn, 0);
  assert.equal(b.fetches(), 0);
  const target = { dataset: { place: 'farm' } };
  b.element('world-map').closest = () => target;
  await b.element('world-map').emit('click');
  assert.equal(b.element('drop-location').value, 'farm');
  assert.match(b.element('scene-site').textContent, /当前不可见/);
});

test('the shared home is a selectable public drop site and exploration uses seven locations', async () => {
  const b = browser();
  b.element('world-map').closest = selector => selector === '[data-place]' ? { dataset: { place: 'home' } } : null;
  await b.element('world-map').emit('click');
  assert.equal(b.element('drop-location').value, 'home');
  assert.match(b.element('scene-site').textContent, /共同的家.*四位居民.*休息/);
  b.element('drop-amount').value = '1';
  await b.element('drop').emit('click');
  assert.equal(b.context.appState().world.places.home.items.pump, 1);
  assert.match(b.element('resident-list').innerHTML, /1\/7 已探索/);
  assert.match(b.element('metrics').innerHTML, /4\/28/);
  assert.equal(b.requests.length, 0);
});

test('resident speech is escaped overhead and expands below the scene when its speaker is selected', async () => {
  const w = engine.createWorld(2049, 'cooperation');
  const message = '<img src=x onerror="unsafe()"> 大家回家吃饭吧。';
  engine.advance(w, { action: 'talk', target: 'eli', message, intent: 'PRIVATE_INTENT' });
  engine.intervene(w, { type: 'whisper', agent: 'mara', message: 'PRIVATE_WHISPER' });
  const b = browser({ saved: JSON.stringify(engine.exportRecord(w)) });
  assert.match(b.element('town-residents').innerHTML, /bubble-status[^>]*>交谈/);
  assert.match(b.element('town-residents').innerHTML, /&lt;img src=x onerror=&quot;unsafe\(\)&quot;&gt;/);
  assert.doesNotMatch(b.element('town-residents').innerHTML, /<img|PRIVATE_INTENT|PRIVATE_WHISPER/);
  assert.equal(b.element('scene-dialogue').hidden, false);
  assert.equal(b.element('scene-dialogue').textContent, `林岚 · 规则最近发言：${message}`);
  b.element('world-map').closest = selector => selector === '[data-scene-agent]' ? { dataset: { sceneAgent: 'eli' } } : null;
  await b.element('world-map').emit('click');
  assert.equal(b.element('scene-dialogue').hidden, true);
  assert.equal(b.element('scene-dialogue').textContent, '');
  const before = b.snapshot();
  await b.context.window.emit('resize');
  assert.equal(b.snapshot(), before);
  assert.equal(b.requests.length, 0);
});

test('a pending model decision shows a generic overhead status without inventing dialogue', async () => {
  const b = browser({ decide: (_, { signal }) => new Promise((resolve, reject) => {
    signal.addEventListener('abort', () => reject(new DOMException('Cancelled', 'AbortError')), { once: true });
  }) });
  await enableModel(b);
  await b.element('step').emit('click'); await flush();
  assert.match(b.element('town-residents').innerHTML, /选择行动中…/);
  assert.doesNotMatch(b.element('town-residents').innerHTML, /class="bubble-speech"/);
  assert.equal(b.requests.length, 1);
  await b.element('play').emit('click'); await flush();
  assert.doesNotMatch(b.element('town-residents').innerHTML, /选择行动中…/);
  assert.equal(b.context.appState().world.metrics.actions, 0);
});

test('the town is one full-width scene, with zoom and actor selection that do not advance time', async () => {
  const b = browser(), before = b.snapshot();
  assert.ok(template.indexOf('game-stage') < template.indexOf('class="workspace"'));
  assert.match(stylesheet, /\.world-map\s*\{[^}]*overflow:\s*clip;/);
  assert.equal([...b.element('town-landscape').innerHTML.matchAll(/<svg/g)].length, 1);
  assert.doesNotMatch(b.element('town-places').innerHTML, /place-stock|place-people|<svg/);
  await b.element('scene-zoom-in').emit('click');
  assert.equal(b.element('world-map').style.width, '150%');
  assert.equal(b.element('scene-zoom-label').textContent, '1.5×');
  await b.element('scene-fit').emit('click');
  assert.equal(b.element('world-map').style.width, '100%');
  b.element('world-map').closest = selector => selector === '[data-scene-agent]' ? { dataset: { sceneAgent: 'eli' } } : null;
  await b.element('world-map').emit('click');
  assert.match(b.element('inspector-heading').innerHTML, /陈野/);
  assert.equal(b.element('drop-location').value, 'ridge');
  assert.equal(b.snapshot(), before);
  assert.equal(b.fetches(), 0);
  assert.equal(b.writes(), 0);
});

test('3D camera controls and a 2D switch preserve world progress and never invoke models', async () => {
  const b = browser(), before = b.snapshot();
  assert.equal(b.element('scene-view').value, '3d');
  await b.element('scene-rotate-left').emit('click');
  await b.element('scene-rotate-right').emit('click');
  b.element('scene-view').value = '2d';
  await b.element('scene-view').emit('change');
  assert.equal(b.element('scene-rotate-left').disabled, true);
  b.element('scene-view').value = '3d';
  await b.element('scene-view').emit('change');
  await b.element('scene-fit').emit('click');
  assert.equal(b.element('scene-rotate-left').disabled, false);
  assert.equal(b.snapshot(), before);
  assert.equal(b.fetches(), 0);
  assert.equal(b.writes(), 0);
});

test('unsupported WebGL is explicitly reported while the smooth island fallback stays usable', () => {
  const b = browser({ canvasSupport: false });
  assert.equal(b.element('scene-view').value, '2d');
  assert.equal(b.element('scene-view').disabled, true);
  assert.match(b.element('notice').textContent, /不支持 WebGL 立体绘图.*平面海岛/);
  assert.equal([...b.element('town-places').innerHTML.matchAll(/data-place=/g)].length, 7);
  assert.equal(b.fetches(), 0);
  assert.doesNotMatch(stylesheet, /image-rendering:\s*pixelated/);
  assert.doesNotMatch(b.element('town-landscape').innerHTML, /crispEdges/);
});

async function chooseResident(b, resident, setting, value) {
  b.element('resident-model-config').closest = () => ({ dataset: { resident, setting }, value });
  await b.element('resident-model-config').emit('change');
}

test('each resident can use a different allowlisted provider, model and effort without sharing observations', async () => {
  const b = browser();
  await b.element('model-open').emit('click'); await flush();
  await chooseResident(b, 'eli', 'model', 'other-model');
  await chooseResident(b, 'nora', 'provider', 'custom-api');
  await chooseResident(b, 'silas', 'effort', 'high');
  assert.equal(b.element('model-consent').checked, false);
  assert.equal(b.requests.length, 0);
  b.element('model-consent').checked = true; b.element('budget').value = '12';
  await b.element('model-consent').emit('change');
  await b.element('model-enable').emit('click');
  await b.element('step').emit('click'); await flush();
  assert.deepEqual(b.requests.map(r => r.profile), ['fast', 'other-model', 'api', 'deep']);
  assert.deepEqual(b.requests.map(r => r.observation.self.id), ['mara', 'eli', 'nora', 'silas']);
  assert.ok(b.requests.every(r => !Object.hasOwn(r, 'model') && !Object.hasOwn(r, 'provider')));
  const world = b.context.appState().world;
  assert.deepEqual(world.audit.map(a => a.inference.provider), ['copilot', 'copilot', 'custom-api', 'copilot']);
  assert.deepEqual(world.audit.map(a => a.inference.model), ['test', 'other-model', 'api-model', 'test']);
  assert.deepEqual(engine.restoreRecord(b.storage.get(AUTO_KEY)).audit, world.audit);
  assert.match(b.element('resident-list').innerHTML, /Custom API/);
  const choices = JSON.parse(b.storage.get(MODELS_KEY));
  assert.deepEqual(choices, { mara: 'fast', eli: 'other-model', nora: 'api', silas: 'deep' });
  const reload = browser({ preferences: JSON.stringify(choices) });
  await reload.element('model-open').emit('click'); await flush();
  assert.equal(reload.element('model-profile').value, '');
  assert.match(reload.element('resident-model-config').innerHTML, /value="api-model" selected/);
  assert.equal(reload.requests.length, 0);
});

test('unavailable credentials and unknown saved profiles block consent instead of silently substituting a model', async () => {
  const b = browser();
  await b.element('model-open').emit('click'); await flush();
  await chooseResident(b, 'mara', 'provider', 'missing');
  b.element('model-consent').checked = true;
  await b.element('model-consent').emit('change');
  assert.equal(b.element('model-enable').disabled, true);
  assert.match(b.element('bridge-status').textContent, /可用配置/);
  assert.equal(b.requests.length, 0);
  const reload = browser({ preferences: JSON.stringify({ mara: 'removed', eli: 'fast', nora: 'fast', silas: 'fast' }) });
  await reload.element('model-open').emit('click'); await flush();
  reload.element('model-consent').checked = true;
  await reload.element('model-consent').emit('change');
  assert.equal(reload.element('model-enable').disabled, true);
  assert.equal(reload.requests.length, 0);
});

test('cancelling individual provider edits keeps the previously authorized resident configuration', async () => {
  const b = browser();
  await enableModel(b);
  await b.element('model-open').emit('click'); await flush();
  await chooseResident(b, 'mara', 'provider', 'custom-api');
  await b.element('model-dialog').close();
  await b.element('step').emit('click'); await flush();
  assert.ok(b.requests.every(r => r.profile === 'fast'));
});
