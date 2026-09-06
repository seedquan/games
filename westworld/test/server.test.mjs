import test from 'node:test';
import assert from 'node:assert/strict';
import { once, EventEmitter } from 'node:events';
import { PassThrough } from 'node:stream';
import { access } from 'node:fs/promises';
import { request as httpRequest, createServer } from 'node:http';
import { createBridge, validateObservation, residentPrompt, runResident, modelProfiles } from '../server.mjs';
import { VERSION, createWorld, observation } from '../src/world.mjs';
import { publicProfile } from '../providers.mjs';

async function bridge(t, options = {}) {
  const server = createBridge({ logTiming: () => {}, ...options });
  server.listen(0, '127.0.0.1'); await once(server, 'listening');
  t.after(() => new Promise(resolve => { server.cancelActive(); server.closeAllConnections(); server.close(resolve); }));
  const base = `http://127.0.0.1:${server.address().port}`;
  const status = await (await fetch(`${base}/api/status`)).json();
  const w = createWorld(), data = observation(w, w.agents[0]);
  const post = (body = { observation: data }, headers = {}) => fetch(`${base}/api/decide`, {
    method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Westworld-Token': status.token, ...headers },
    body: JSON.stringify(body),
  });
  return { base, status, data, post };
}

test('observation validation rejects global or nested private-state additions', () => {
  const w = createWorld(), o = observation(w, w.agents[0]);
  assert.deepEqual(validateObservation(o), o);
  for (const bad of [
    { ...o, agents: w.agents }, { ...o, deviceEffect: w.deviceEffect },
    { ...o, self: { ...o.self, secrets: 'x' } },
    { ...o, neighbors: [{ id: 'eli', name: 'Eli', role: 'x', condition: 'ok', inventory: {} }] },
    { ...o, here: { ...o.here, hidden: 'x' } }, { ...o, map: [] },
  ]) assert.throws(() => validateObservation(bad), /局部/);
  assert.match(residentPrompt(o), /untrusted simulation data/);
  assert.ok(!residentPrompt(o).includes('deviceEffect'));
});

test('bridge advertises its map version and accepts a home resident through the bounded adapter', async t => {
  let seen;
  const { status, post } = await bridge(t, { decide: async o => { seen = o; return { action: 'rest' }; } });
  assert.equal(status.worldVersion, VERSION);
  const w = createWorld();
  w.agents[0].location = 'home'; w.agents[0].visited.push('home');
  const o = observation(w, w.agents[0]);
  const response = await post({ observation: o });
  assert.equal(response.status, 200);
  assert.equal((await response.json()).decision.action, 'rest');
  assert.deepEqual(seen, o);
  assert.match(residentPrompt(o), /home is shared shelter.*not shared memory or inventory/);
});

test('CLI runner isolates tools and cwd, validates JSON and cleans its temporary directory', async () => {
  let invoked;
  const spawnProcess = (command, args, options) => {
    invoked = { command, args, options };
    const child = new EventEmitter();
    child.stdout = new PassThrough(); child.stderr = new PassThrough();
    child.kill = () => true;
    process.nextTick(() => { child.stdout.write('{"action":"wait","intent":"观察"}'); child.emit('close', 0); });
    return child;
  };
  const w = createWorld(), result = await runResident(observation(w, w.agents[0]), { spawnProcess });
  assert.equal(result.action, 'wait');
  assert.equal(invoked.command, 'copilot');
  for (const flag of ['--available-tools=none', '--no-custom-instructions', '--disable-builtin-mcps', '--no-remote-export', '--no-bash-env']) assert.ok(invoked.args.includes(flag));
  assert.ok(!invoked.args.includes('--available-tools='), 'An empty CLI allowlist is normalized away and exposes every tool.');
  assert.equal(invoked.args[invoked.args.indexOf('--max-ai-credits') + 1], '30');
  assert.equal(invoked.args[invoked.args.indexOf('--effort') + 1], modelProfiles()[0].effort);
  assert.equal(invoked.options.shell, false);
  assert.match(invoked.options.cwd, /westworld-resident-/);
  await assert.rejects(access(invoked.options.cwd));
});

function cliExit(stdout, stderr, code) {
  return () => {
    const child = new EventEmitter();
    child.stdout = new PassThrough(); child.stderr = new PassThrough();
    child.kill = () => true;
    process.nextTick(() => {
      child.stdout.write(stdout); child.stderr.write(stderr); child.emit('close', code);
    });
    return child;
  };
}

test('CLI empty-response failure is identifiable but must not trigger another charge automatically', async () => {
  const w = createWorld(), o = observation(w, w.agents[1]);
  for (const spawnProcess of [
    cliExit('Error: No response was returned. Send your message again to retry.', '', 1),
    cliExit('', 'No response was returned. Send your message again to retry.', 1),
    cliExit(' \n', '', 0),
  ]) {
    await assert.rejects(runResident(o, { spawnProcess }), error => {
      assert.equal(error.code, 'MODEL_EMPTY_RESPONSE');
      assert.equal(error.retryable, false);
      assert.match(error.message, /没有返回/);
      assert.doesNotMatch(error.message, /登录|权限|额度/);
      return true;
    });
  }
});

test('session budget exhaustion takes priority over its misleading empty-response symptom', async () => {
  const w = createWorld(), o = observation(w, w.agents[0]);
  const spawnProcess = cliExit(
    'Error: No response was returned. Send your message again to retry.',
    'Session limit reached (74.59/30 AI credits used). Tool execution was skipped because the session limits were reached.',
    1,
  );
  await assert.rejects(runResident(o, { spawnProcess }), error => {
    assert.equal(error.code, 'MODEL_BUDGET_EXHAUSTED');
    assert.equal(error.retryable, false);
    assert.match(error.message, /会话.*上限/);
    return true;
  });
});

test('authentication and malformed model output are not automatically retryable', async () => {
  const w = createWorld(), o = observation(w, w.agents[0]);
  for (const spawnProcess of [
    cliExit('', 'Authentication failed. Run copilot login.', 1),
    cliExit('I will invent an action', '', 0),
  ]) {
    await assert.rejects(runResident(o, { spawnProcess }), error => error.retryable !== true);
  }
});

test('bridge does not mark an ambiguous empty response safe to retry', async t => {
  const w = createWorld(), o = observation(w, w.agents[1]);
  const { post } = await bridge(t, {
    decide: () => runResident(o, { spawnProcess: cliExit('No response was returned. Send your message again to retry.', '', 1) }),
  });
  const response = await post(), data = await response.json();
  assert.equal(response.status, 502);
  assert.equal(data.code, 'MODEL_EMPTY_RESPONSE');
  assert.equal(data.retryable, false);
  assert.equal(data.remaining, 23);
  assert.equal(data.decision, undefined);
});

test('server exposes only standalone HTML and bridge routes, no source or credentials', async t => {
  let calls = 0;
  const { base, status } = await bridge(t, { decide: async () => { calls++; return { action: 'wait' }; } });
  assert.equal(status.service, 'westworld'); assert.equal(status.remaining, 24);
  const page = await fetch(`${base}/westworld/`);
  assert.equal(page.status, 200);
  assert.match(await page.text(), /WESTWORLD LAB/);
  for (const path of ['/server.mjs', '/providers.mjs', '/profiles.example.json', '/src/app.mjs', '/package.json', '/.git/config', '/api/missing']) assert.equal((await fetch(base + path)).status, 404);
  assert.equal(calls, 0);
});

test('cross-origin, wrong-host and missing-token requests cannot invoke a model', async t => {
  let calls = 0;
  const { base, post } = await bridge(t, { decide: async () => { calls++; return { action: 'wait' }; } });
  for (const headers of [{ Origin: 'https://other.invalid' }, { 'X-Westworld-Token': '' }, { 'Sec-Fetch-Site': 'cross-site' }]) assert.equal((await post(undefined, headers)).status, 403);
  const code = await new Promise((resolve, reject) => {
    const req = httpRequest(`${base}/api/status`, { headers: { Host: 'other.invalid' } }, res => { res.resume(); resolve(res.statusCode); });
    req.on('error', reject); req.end();
  });
  assert.equal(code, 403); assert.equal(calls, 0);
});

test('requests are bounded and validation failures never invoke a model', async t => {
  let calls = 0;
  const { data, post } = await bridge(t, { decide: async () => { calls++; return { action: 'wait' }; } });
  assert.equal((await post({ observation: {} })).status, 400);
  assert.equal((await post({ observation: { ...data, extra: 'x'.repeat(25000) } })).status, 413);
  assert.equal((await post(undefined, { 'Content-Type': 'text/plain' })).status, 415);
  assert.equal(calls, 0);
});

test('successful and failed calls both consume server-wide allowance, no fake fallback', async t => {
  let calls = 0;
  const { base, post } = await bridge(t, { maxRequests: 2, decide: async () => {
    if (calls++ === 0) throw new Error('model unavailable');
    return { action: 'wait' };
  } });
  const failed = await post(); assert.equal(failed.status, 502);
  const failure = await failed.json();
  assert.equal(failure.error, 'model unavailable'); assert.equal(failure.remaining, 1);
  assert.ok(failure.timing.totalMs >= 0);
  assert.equal(failure.timing.firstOutputMs, null);
  assert.equal((await post()).status, 200);
  assert.equal((await post()).status, 429);
  assert.equal((await (await fetch(`${base}/api/status`)).json()).remaining, 0);
  assert.equal(calls, 2);
});

test('inference is serialized even across tabs', async t => {
  let release, began;
  const started = new Promise(resolve => { began = resolve; });
  const done = new Promise(resolve => { release = resolve; });
  const { post } = await bridge(t, { decide: async () => { began(); await done; return { action: 'wait' }; } });
  const one = post();
  await started;
  assert.equal((await post()).status, 409);
  release();
  assert.equal((await one).status, 200);
});

test('invalid model output is visible failure, not a fabricated action', async t => {
  const { post } = await bridge(t, { decide: async () => ({ action: 'teleport' }) });
  const response = await post(), data = await response.json();
  assert.equal(response.status, 502); assert.equal(data.decision, undefined);
  assert.match(data.error, /行动/);
});

test('browser disconnect aborts inference', async t => {
  let began, aborted;
  const started = new Promise(resolve => { began = resolve; });
  const cancelled = new Promise(resolve => { aborted = resolve; });
  const { base, status, data } = await bridge(t, { decide: async (_, { signal }) => {
    began();
    await new Promise(resolve => signal.addEventListener('abort', () => { aborted(); resolve(); }, { once: true }));
    throw new Error('cancelled');
  } });
  const controller = new AbortController();
  const pending = fetch(`${base}/api/decide`, {
    method: 'POST', signal: controller.signal,
    headers: { 'Content-Type': 'application/json', 'X-Westworld-Token': status.token },
    body: JSON.stringify({ observation: data }),
  }).catch(error => error);
  await started; controller.abort(); await pending; await cancelled;
});

test('model profiles default to explicit low/high effort and accept only local configuration', () => {
  assert.deepEqual(modelProfiles({}), [
    { id: 'fast', label: '快速', model: 'gpt-6-astra', effort: 'low' },
    { id: 'deep', label: '深度', model: 'gpt-6-astra', effort: 'high' },
  ]);
  const profiles = modelProfiles({
    WESTWORLD_MODEL: 'fast-model', WESTWORLD_EFFORT: 'minimal',
    WESTWORLD_DEEP_MODEL: 'deep-model', WESTWORLD_DEEP_EFFORT: 'medium',
  });
  assert.equal(profiles[0].model, 'fast-model'); assert.equal(profiles[0].effort, 'minimal');
  assert.equal(profiles[1].model, 'deep-model'); assert.equal(profiles[1].effort, 'medium');
  for (const env of [{ WESTWORLD_EFFORT: 'typo' }, { WESTWORLD_DEEP_EFFORT: 'typo' }, { WESTWORLD_MODEL: ' ' }]) {
    assert.throws(() => modelProfiles(env), /WESTWORLD/);
  }
});

test('CLI timing uses first stdout and process lifecycle timestamps, never stderr as model output', async () => {
  let time = 0, timing, args;
  const w = createWorld(), o = observation(w, w.agents[0]);
  const profile = modelProfiles({ WESTWORLD_DEEP_MODEL: 'deep-model' })[1];
  const spawnProcess = (_, argv) => {
    args = argv;
    const child = new EventEmitter();
    child.stdout = new PassThrough(); child.stderr = new PassThrough(); child.kill = () => true;
    process.nextTick(() => {
      time = 20; child.emit('spawn');
      time = 30; child.stderr.write('private diagnostic');
      time = 80; child.stdout.write('{"action":');
      time = 90; child.stdout.write('"wait"}');
      time = 100; child.emit('close', 0);
    });
    return child;
  };
  await runResident(o, { spawnProcess, profile, now: () => time, onTiming: value => { timing = value; } });
  assert.deepEqual(timing, { processSpawnMs: 20, firstOutputMs: 80, processExitMs: 100, cliTotalMs: 100, promptCharacters: residentPrompt(o).length });
  assert.equal(args[args.indexOf('--model') + 1], 'deep-model');
  assert.equal(args[args.indexOf('--effort') + 1], 'high');
  assert.ok(args.includes('--available-tools=none'));
});

test('failed CLI calls report timing with no fabricated first-output timestamp', async () => {
  let timing;
  const w = createWorld();
  await assert.rejects(runResident(observation(w, w.agents[0]), {
    spawnProcess: cliExit('', 'Authentication failed', 1), onTiming: value => { timing = value; },
  }), /login/);
  assert.equal(timing.firstOutputMs, null);
  assert.ok(timing.processExitMs >= 0);
  assert.ok(timing.cliTotalMs >= timing.processExitMs);
});

test('profile selection is allowlisted before charging and passed explicitly to the decision runner', async t => {
  const choices = [];
  const { post, data, status } = await bridge(t, { decide: async (_, { profile }) => {
    choices.push(profile); return { action: 'wait' };
  } });
  assert.equal(status.defaultProfile, 'fast');
  for (const body of [
    { observation: data, profile: 'unknown' }, { observation: data, profile: null },
    { observation: data, profile: { model: 'other' } }, { observation: data, model: 'other' },
    { observation: data, effort: 'max' },
  ]) assert.equal((await post(body)).status, 400);
  assert.equal(choices.length, 0);
  assert.equal((await post({ observation: data, profile: 'deep' })).status, 200);
  assert.deepEqual(publicProfile(choices[0]), status.profiles.find(p => p.id === 'deep'));
  assert.equal((await post()).status, 200);
  assert.deepEqual(publicProfile(choices[1]), status.profiles.find(p => p.id === 'fast'));
});

test('bridge returns and logs timing for success and failure without prompts, output or tokens', async t => {
  const records = [];
  let calls = 0;
  const { post, data, status } = await bridge(t, {
    logTiming: record => records.push(record),
    decide: async (_, { onTiming }) => {
      onTiming({ processSpawnMs: 0, firstOutputMs: null, processExitMs: 0, cliTotalMs: 0, promptCharacters: 123 });
      if (calls++ === 1) throw new Error('failure');
      return { action: 'wait', intent: 'PRIVATE_OUTPUT' };
    },
  });
  data.self.memories = [{ round: 0, text: 'PRIVATE_MEMORY' }];
  for (const expected of [200, 502]) {
    const response = await post(), result = await response.json();
    assert.equal(response.status, expected);
    assert.ok(result.timing.totalMs >= 0);
    assert.equal(result.timing.firstOutputMs, null);
    assert.equal(result.timing.promptCharacters, 123);
    assert.deepEqual(records.at(-1).timing, result.timing);
  }
  assert.deepEqual(records.map(r => r.outcome), ['success', 'failure']);
  assert.deepEqual(records.map(r => r.request), [1, 2]);
  assert.equal(records[0].resident, 'mara');
  const serialized = JSON.stringify(records);
  for (const secret of ['PRIVATE_MEMORY', 'PRIVATE_OUTPUT', status.token]) assert.ok(!serialized.includes(secret));
});

test('unconfigured API credentials stay server-only and do not consume a request', async t => {
  let calls = 0;
  const defaults = modelProfiles().map(p => ({ ...p, provider: 'copilot', providerLabel: 'Copilot', adapter: 'copilot' }));
  const api = {
    id: 'missing', label: 'Missing key', provider: 'test-api', providerLabel: 'Test API',
    adapter: 'openai-compatible', model: 'api-model', effort: 'low',
    endpoint: 'https://private.example.invalid/chat', apiKeyEnv: 'WESTWORLD_MISSING_TEST_KEY',
    maxOutputTokens: 2048, tokenLimitField: 'max_completion_tokens',
  };
  const { status, data, post } = await bridge(t, { profiles: [...defaults, api], decide: async () => { calls++; return { action: 'wait' }; } });
  const profile = status.profiles.find(p => p.id === 'missing');
  assert.equal(profile.available, false);
  assert.equal(profile.endpoint, undefined);
  assert.equal(profile.apiKeyEnv, undefined);
  const response = await post({ observation: data, profile: 'missing' });
  assert.equal(response.status, 400);
  assert.equal(calls, 0);
  assert.equal((await (await post()).json()).remaining, 23);
});

test('configured API adapter makes one bounded private request and shares failure budgets end to end', async t => {
  const keyName = 'WESTWORLD_LOOPBACK_TEST_KEY', original = process.env[keyName];
  process.env[keyName] = 'synthetic-loopback-test-key';
  t.after(() => { if (original === undefined) delete process.env[keyName]; else process.env[keyName] = original; });
  const received = [], records = [];
  const provider = createServer(async (req, res) => {
    let raw = '';
    for await (const chunk of req) raw += chunk;
    received.push({ authorization: req.headers.authorization, body: JSON.parse(raw) });
    res.setHeader('Content-Type', 'application/json');
    if (received.length === 2) { res.writeHead(429); res.end('PRIVATE_PROVIDER_ERROR'); return; }
    res.end(JSON.stringify({ choices: [{ finish_reason: 'stop', message: { content: '{"action":"wait"}' } }] }));
  });
  provider.listen(0, '127.0.0.1'); await once(provider, 'listening');
  t.after(() => new Promise(resolve => { provider.closeAllConnections(); provider.close(resolve); }));
  const defaults = modelProfiles().map(p => ({ ...p, provider: 'copilot', providerLabel: 'Copilot', adapter: 'copilot' }));
  const api = { id: 'loopback-api', label: 'Loopback', provider: 'loopback', providerLabel: 'Loopback test',
    adapter: 'openai-compatible', model: 'test-model', effort: 'low', apiKeyEnv: keyName,
    endpoint: `http://127.0.0.1:${provider.address().port}/v1/chat/completions`,
    maxOutputTokens: 512, tokenLimitField: 'max_completion_tokens' };
  const { status, post, data } = await bridge(t, { profiles: [...defaults, api], maxRequests: 2, logTiming: value => records.push(value) });
  assert.equal(status.profiles.at(-1).available, true);
  const good = await post({ observation: data, profile: api.id }), result = await good.json();
  assert.equal(good.status, 200);
  assert.deepEqual(result.decision, { action: 'wait' });
  assert.deepEqual(result.inference, { provider: 'loopback', model: 'test-model', effort: 'low' });
  assert.ok(result.timing.responseHeadersMs >= 0);
  assert.ok(result.timing.firstByteMs >= 0);
  assert.equal(result.timing.processSpawnMs, null);
  assert.equal(received[0].body.messages.length, 1);
  assert.equal(received[0].body.messages[0].content, residentPrompt(data));
  assert.equal(received[0].body.max_completion_tokens, 512);
  assert.equal(received[0].body.tools, undefined);
  assert.equal(received[0].authorization, 'Bearer synthetic-loopback-test-key');
  const failed = await post({ observation: data, profile: api.id }), failure = await failed.json();
  assert.equal(failed.status, 502); assert.equal(failure.remaining, 0);
  assert.match(failure.error, /HTTP 429/);
  assert.doesNotMatch(failure.error, /PRIVATE_PROVIDER_ERROR/);
  assert.equal((await post({ observation: data, profile: api.id })).status, 429);
  assert.equal(received.length, 2);
  assert.deepEqual(records.map(r => r.outcome), ['success', 'failure']);
  assert.doesNotMatch(JSON.stringify(records), /synthetic-loopback-test-key|PRIVATE_PROVIDER_ERROR|messages|endpoint/);
});
