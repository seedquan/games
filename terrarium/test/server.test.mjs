import test from 'node:test';
import assert from 'node:assert/strict';
import { once } from 'node:events';
import { request as httpRequest } from 'node:http';
import { fileURLToPath } from 'node:url';
import { createBridge, parseDecision, validateObservation, runCopilot } from '../server.mjs';
import { createWorld, observation } from '../src/world.mjs';

test('resident CLI invocation uses accepted credit and tool-isolation flags', async () => {
  const path = process.env.PATH;
  process.env.PATH = `${fileURLToPath(new URL('./fixtures/', import.meta.url))}:${path}`;
  try {
    const w = createWorld();
    assert.deepEqual(await runCopilot(observation(w, w.agents[0])), { action: 'wait', intent: '观察周围' });
  } finally {
    process.env.PATH = path;
  }
});

async function bridge(t, options) {
  const server = createBridge(options);
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(() => new Promise(resolve => { server.closeAllConnections(); server.close(resolve); }));
  const base = `http://127.0.0.1:${server.address().port}`;
  const status = await (await fetch(`${base}/api/status`)).json();
  const w = createWorld();
  const data = observation(w, w.agents[0]);
  const post = (body = { observation: data }, headers = {}) => fetch(`${base}/api/decide`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'X-Terrarium-Token': status.token, ...headers },
    body: JSON.stringify(body),
  });
  return { server, base, status, data, post };
}

test('strict model JSON parser accepts one valid action and rejects malformed output', () => {
  assert.equal(parseDecision('```json\n{"action":"wait","intent":"观察"}\n```').action, 'wait');
  assert.throws(() => parseDecision('Here is my plan: {"action":"wait"}'), /JSON/);
  assert.throws(() => parseDecision('{"action":"delete_world"}'), /格式/);
  assert.throws(() => parseDecision('{"action":"move"}'), /坐标/);
  assert.throws(() => parseDecision('{"action":"move","x":999,"z":0}'), /格式/);
  assert.deepEqual(parseDecision('{"action":"wait","secret":"ignored"}'), { action: 'wait' });
});

test('observation rejects global world data', () => {
  const w = createWorld(), data = observation(w, w.agents[0]);
  assert.equal(validateObservation(data), data);
  assert.throws(() => validateObservation({ ...data, entities: w.entities }), /全局/);
  assert.throws(() => validateObservation({}), /无效/);
});

test('bridge serves only the compiled artifact, never server source or local files', async t => {
  const { base, status } = await bridge(t, { decide: async () => ({ action: 'wait' }) });
  assert.equal(status.service, 'terrarium');
  assert.equal(status.model, 'gpt-6-astra');
  const html = await fetch(`${base}/terrarium/`);
  assert.equal(html.status, 200);
  assert.ok((await html.text()).includes('TERRARIUM'));
  for (const path of ['/server.mjs', '/src/world.mjs', '/package.json', '/api/nope']) {
    assert.equal((await fetch(base + path)).status, 404);
  }
});

test('model requests require a same-origin token and matching Host', async t => {
  let calls = 0;
  const { base, post } = await bridge(t, { decide: async () => { calls++; return { action: 'wait' }; } });
  assert.equal((await post(undefined, { 'X-Terrarium-Token': 'wrong' })).status, 403);
  assert.equal((await post(undefined, { Origin: 'https://attacker.invalid' })).status, 403);
  const invalidHostStatus = await new Promise((resolve, reject) => {
    const req = httpRequest(`${base}/api/status`, { headers: { Host: 'attacker.invalid' } }, res => {
      res.resume();
      resolve(res.statusCode);
    });
    req.on('error', reject);
    req.end();
  });
  assert.equal(invalidHostStatus, 403);
  assert.equal((await post(undefined, { 'Sec-Fetch-Site': 'cross-site' })).status, 403);
  assert.equal(calls, 0);
});

test('valid requests return decisions and enforce the service-wide budget', async t => {
  let calls = 0;
  const { base, post } = await bridge(t, { maxRequests: 2, decide: async () => { calls++; return { action: 'wait' }; } });
  for (let i = 0; i < 2; i++) {
    const res = await post();
    assert.equal(res.status, 200);
    assert.equal((await res.json()).decision.action, 'wait');
  }
  assert.equal((await post()).status, 429);
  assert.equal((await (await fetch(`${base}/api/status`)).json()).remaining, 0);
  assert.equal(calls, 2);
});

test('model failures consume budget and never return a fallback decision', async t => {
  const { base, post } = await bridge(t, { decide: async () => { throw new Error('simulated inference failure'); } });
  const res = await post();
  assert.equal(res.status, 502);
  const data = await res.json();
  assert.equal(data.error, 'simulated inference failure');
  assert.equal(data.decision, undefined);
  assert.equal((await (await fetch(`${base}/api/status`)).json()).remaining, 23);
});

test('the bridge runs only one inference at a time', async t => {
  let release, started;
  const entered = new Promise(resolve => { started = resolve; });
  const gate = new Promise(resolve => { release = resolve; });
  const { post } = await bridge(t, { decide: async () => { started(); await gate; return { action: 'wait' }; } });
  const first = post();
  await entered;
  assert.equal((await post()).status, 409);
  release();
  assert.equal((await first).status, 200);
});

test('invalid and excessive request bodies do not call the model', async t => {
  let calls = 0;
  const { post, data } = await bridge(t, { decide: async () => { calls++; return { action: 'wait' }; } });
  assert.equal((await post({ observation: {} })).status, 400);
  assert.equal((await post({ observation: { ...data, extra: 'x'.repeat(25000) } })).status, 413);
  assert.equal((await post(undefined, { 'Content-Type': 'text/plain' })).status, 415);
  assert.equal(calls, 0);
});

test('disconnect cancels an in-flight model request', async t => {
  let started, cancelled;
  const entered = new Promise(resolve => { started = resolve; });
  const aborted = new Promise(resolve => { cancelled = resolve; });
  const { base, data, status } = await bridge(t, {
    decide: async (_, { signal }) => {
      started();
      await new Promise(resolve => signal.addEventListener('abort', () => { cancelled(); resolve(); }, { once: true }));
      throw new Error('cancelled');
    },
  });
  const controller = new AbortController();
  const request = fetch(`${base}/api/decide`, {
    method: 'POST', signal: controller.signal,
    headers: { 'Content-Type': 'application/json', 'X-Terrarium-Token': status.token },
    body: JSON.stringify({ observation: data }),
  }).catch(error => error);
  await entered;
  controller.abort();
  await request;
  await aborted;
});
