import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { loadProfiles, publicProfile, runChatProvider } from '../providers.mjs';
import { modelProfiles } from '../server.mjs';

const api = {
  id: 'api-low', label: 'API low', provider: 'test-api', providerLabel: 'Test API',
  adapter: 'openai-compatible', model: 'test-model', effort: 'low',
  endpoint: 'https://api.example.invalid/v1/chat/completions',
  apiKeyEnv: 'WESTWORLD_TEST_API_KEY', maxOutputTokens: 2048, tokenLimitField: 'max_completion_tokens',
};
const env = { WESTWORLD_TEST_API_KEY: 'test-only-credential' };
const completion = (message = { content: '{"action":"wait"}' }, finish_reason = 'stop') =>
  new Response(JSON.stringify({ choices: [{ message, finish_reason }] }), { headers: { 'Content-Type': 'application/json' } });

async function profileFile(t, data) {
  const directory = await mkdtemp(join(tmpdir(), 'westworld-profile-test-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const path = join(directory, 'profiles.json');
  await writeFile(path, JSON.stringify(data));
  return { ...env, WESTWORLD_PROFILES_FILE: path };
}

test('profile file extends defaults, preserves exact model IDs and publishes no endpoints or credentials', async t => {
  const settings = await profileFile(t, [api, { ...api, id: 'api-high', effort: 'high', maxOutputTokens: 4096 }]);
  const profiles = loadProfiles(modelProfiles({}), settings);
  assert.equal(profiles.length, 4);
  assert.equal(profiles[2].model, 'test-model');
  const visible = publicProfile(profiles[2], settings);
  assert.equal(visible.available, true);
  assert.equal(publicProfile(profiles[2], {}).available, false);
  assert.equal(visible.maxOutputTokens, 2048);
  assert.ok(!JSON.stringify(visible).includes('apiKeyEnv'));
  assert.ok(!JSON.stringify(visible).includes(api.endpoint));
  assert.ok(!JSON.stringify(visible).includes(env.WESTWORLD_TEST_API_KEY));
});

test('unsafe endpoints, duplicate IDs, arbitrary options and excessive caps fail before serving', async t => {
  for (const bad of [
    { ...api, endpoint: 'http://public.example.invalid/chat' },
    { ...api, endpoint: 'https://user:pass@example.invalid/chat' },
    { ...api, endpoint: 'https://example.invalid/chat?api_key=hidden' },
    { ...api, endpoint: 'https://example.invalid/chat#fragment' },
    { ...api, endpoint: 'file:///private/file' },
    { ...api, id: 'fast' }, { ...api, model: '' }, { ...api, apiKey: 'not-accepted' },
    { ...api, maxOutputTokens: 100000 }, { ...api, effort: 'unbounded' },
    { ...api, adapter: 'shell' }, { ...api, tokenLimitField: 'unknown' },
    { ...api, provider: 'copilot' }, { ...api, apiKeyEnv: 'lowercase-key' },
  ]) {
    const settings = await profileFile(t, [bad]);
    assert.throws(() => loadProfiles(modelProfiles({}), settings));
  }
  assert.throws(() => loadProfiles(modelProfiles({}), { WESTWORLD_PROFILES_FILE: '/nonexistent-westworld-profiles-test' }));
});

test('duplicate model/effort choices and conflicting provider endpoints are rejected', async t => {
  for (const list of [
    [api, api], [api, { ...api, id: 'another-id' }],
    [api, { ...api, id: 'another-id', endpoint: 'https://other.invalid/chat', effort: 'high' }],
  ]) {
    const settings = await profileFile(t, list);
    assert.throws(() => loadProfiles(modelProfiles({}), settings), /duplicate|unique|provider ID/);
  }
});

test('explicit loopback HTTP endpoints are supported for local compatible providers', async t => {
  const settings = await profileFile(t, [{ ...api, endpoint: 'http://127.0.0.1:9999/v1/chat/completions', effort: 'default', tokenLimitField: 'max_tokens' }]);
  assert.equal(loadProfiles(modelProfiles({}), settings).at(-1).effort, 'default');
});

test('compatible requests contain one private prompt, bounded output and no tools or redirects', async () => {
  let sent, timing;
  const result = await runChatProvider('ONE_RESIDENT_ONLY', {
    profile: api, env, onTiming: value => { timing = value; },
    fetchRequest: async (url, options) => { sent = { url, options }; return completion(); },
  });
  assert.equal(result, '{"action":"wait"}');
  assert.equal(sent.url, api.endpoint);
  assert.equal(sent.options.redirect, 'error');
  assert.equal(sent.options.headers.Authorization, `Bearer ${env.WESTWORLD_TEST_API_KEY}`);
  const body = JSON.parse(sent.options.body);
  assert.deepEqual(body, {
    model: api.model, messages: [{ role: 'user', content: 'ONE_RESIDENT_ONLY' }],
    stream: false, max_completion_tokens: 2048, reasoning_effort: 'low',
  });
  assert.ok(timing.responseHeadersMs >= 0);
  assert.ok(timing.firstByteMs >= timing.responseHeadersMs);
  assert.ok(!JSON.stringify(timing).includes('ONE_RESIDENT_ONLY'));
});

test('default effort omits provider-specific reasoning options and uses the configured token field', async () => {
  let body;
  await runChatProvider('prompt', {
    profile: { ...api, effort: 'default', tokenLimitField: 'max_tokens' }, env,
    fetchRequest: async (_, options) => { body = JSON.parse(options.body); return completion(); },
  });
  assert.equal(body.max_tokens, 2048);
  assert.equal(body.reasoning_effort, undefined);
  assert.equal(body.max_completion_tokens, undefined);
});

test('missing credentials never sends an API request', async () => {
  let calls = 0;
  await assert.rejects(runChatProvider('prompt', {
    profile: api, env: {}, fetchRequest: async () => { calls++; return completion(); },
  }), /凭据/);
  assert.equal(calls, 0);
});

test('HTTP failures, partial answers, tool calls and oversized responses never retry', async () => {
  for (const response of [
    () => new Response('private provider error', { status: 429 }),
    () => completion({ content: '{"action":"wait"}' }, 'length'),
    () => completion({ content: '{"action":"wait"}', tool_calls: [{ function: { name: 'shell' } }] }),
    () => completion({ content: null }), () => new Response('not JSON'),
    () => new Response('x'.repeat(64001)),
  ]) {
    let calls = 0, timing;
    await assert.rejects(runChatProvider('prompt', {
      profile: api, env, onTiming: value => { timing = value; },
      fetchRequest: async () => { calls++; return response(); },
    }), error => !error.message.includes('private provider error'));
    assert.equal(calls, 1);
    assert.ok(timing.providerTotalMs >= 0);
  }
});

test('API cancellation stops the one in-flight request without retrying', async () => {
  const controller = new AbortController();
  let calls = 0;
  const pending = runChatProvider('prompt', {
    profile: api, env, signal: controller.signal,
    fetchRequest: async (_, { signal }) => {
      calls++;
      return new Promise((_, reject) => signal.addEventListener('abort', () => reject(new DOMException('aborted', 'AbortError')), { once: true }));
    },
  });
  controller.abort();
  await assert.rejects(pending, /取消/);
  assert.equal(calls, 1);
});

test('API timeout aborts at the existing 90-second boundary and does not retry', async t => {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  let calls = 0, aborted = false;
  const pending = runChatProvider('prompt', {
    profile: api, env,
    fetchRequest: async (_, { signal }) => {
      calls++;
      return new Promise((_, reject) => signal.addEventListener('abort', () => {
        aborted = true; reject(new DOMException('aborted', 'AbortError'));
      }, { once: true }));
    },
  });
  t.mock.timers.tick(89999);
  assert.equal(aborted, false);
  t.mock.timers.tick(1);
  await assert.rejects(pending, /90 秒/);
  assert.equal(aborted, true);
  assert.equal(calls, 1);
});
