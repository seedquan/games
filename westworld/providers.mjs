import { readFileSync } from 'node:fs';

const EFFORTS = ['default', 'none', 'minimal', 'low', 'medium', 'high', 'xhigh', 'max'];
const identifier = value => typeof value === 'string' && /^[a-zA-Z0-9][a-zA-Z0-9._-]{0,79}$/.test(value);
const text = (value, max) => typeof value === 'string' && value.trim().length > 0 && value.length <= max;
const environmentName = value => typeof value === 'string' && /^[A-Z_][A-Z0-9_]*$/.test(value);
const elapsed = start => Math.round((performance.now() - start) * 100) / 100;

export function loadProfiles(defaults, env = process.env) {
  const base = defaults.map(p => ({ ...p, provider: 'copilot', providerLabel: 'Copilot', adapter: 'copilot' }));
  if (!env.WESTWORLD_PROFILES_FILE) return base;
  const content = readFileSync(env.WESTWORLD_PROFILES_FILE, 'utf8');
  if (Buffer.byteLength(content) > 64000) throw new Error('WESTWORLD_PROFILES_FILE exceeds 64 KB.');
  let extra;
  try { extra = JSON.parse(content); }
  catch { throw new Error('WESTWORLD_PROFILES_FILE must contain a JSON array of profiles.'); }
  if (!Array.isArray(extra) || extra.length > 24) throw new Error('Configure at most 24 additional profiles.');
  const ids = new Set(base.map(p => p.id)), combinations = new Set(base.map(p => `${p.provider}/${p.model}/${p.effort}`));
  for (const p of extra) {
    const keys = ['id', 'label', 'provider', 'providerLabel', 'adapter', 'model', 'effort', 'endpoint', 'apiKeyEnv', 'maxOutputTokens', 'tokenLimitField'];
    if (!p || Array.isArray(p) || typeof p !== 'object' || Object.keys(p).some(k => !keys.includes(k))
      || !identifier(p.id) || ids.has(p.id) || !identifier(p.provider) || !text(p.providerLabel, 80)
      || !text(p.label, 80) || !text(p.model, 100) || !EFFORTS.includes(p.effort)
      || !['copilot', 'openai-compatible'].includes(p.adapter)) throw new Error('Invalid or duplicate provider profile in WESTWORLD_PROFILES_FILE.');
    if (p.adapter === 'copilot') {
      if (p.provider !== 'copilot' || ['endpoint', 'apiKeyEnv', 'maxOutputTokens', 'tokenLimitField'].some(k => p[k] !== undefined)) {
        throw new Error('Copilot profiles cannot contain API endpoints or credentials.');
      }
    } else {
      if (p.provider === 'copilot' || !text(p.endpoint, 1000) || !environmentName(p.apiKeyEnv)
        || !Number.isInteger(p.maxOutputTokens) || p.maxOutputTokens < 256 || p.maxOutputTokens > 4096
        || !['max_tokens', 'max_completion_tokens'].includes(p.tokenLimitField)) throw new Error('API profiles require endpoint, apiKeyEnv, a 256..4096 output cap and tokenLimitField.');
      let url;
      try { url = new URL(p.endpoint); }
      catch { throw new Error('Provider endpoint must be an absolute URL.'); }
      const local = ['localhost', '127.0.0.1', '[::1]'].includes(url.hostname);
      if ((url.protocol !== 'https:' && !(local && url.protocol === 'http:')) || url.username || url.password || url.search || url.hash) {
        throw new Error('Provider endpoints require HTTPS (or loopback HTTP), with no credentials, query or fragment.');
      }
    }
    const peers = [...base, ...extra.filter(q => q !== p && q?.provider === p.provider)];
    if (peers.some(q => q.provider === p.provider && (q.providerLabel !== p.providerLabel || q.adapter !== p.adapter
      || q.endpoint !== p.endpoint || q.apiKeyEnv !== p.apiKeyEnv))) throw new Error('Each provider ID must use one label, adapter, endpoint and credential source.');
    const combination = `${p.provider}/${p.model}/${p.effort}`;
    if (combinations.has(combination)) throw new Error('Provider/model/effort combinations must be unique.');
    ids.add(p.id); combinations.add(combination);
  }
  return [...base, ...extra];
}

export function publicProfile(profile, env = process.env) {
  const { id, label, provider, providerLabel, model, effort, adapter } = profile;
  return { id, label, provider, providerLabel, model, effort, adapter,
    available: adapter === 'copilot' || Boolean(env[profile.apiKeyEnv]?.trim()),
    maxOutputTokens: profile.maxOutputTokens ?? null };
}

export async function runChatProvider(prompt, { profile, signal, onTiming = () => {}, env = process.env, fetchRequest = fetch } = {}) {
  const key = env[profile.apiKeyEnv];
  if (!key?.trim()) throw new Error(`Provider ${profile.provider} 尚未在服务端配置凭据。`);
  const startedAt = performance.now(), controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 90000);
  const combined = signal ? AbortSignal.any([signal, controller.signal]) : controller.signal;
  let headersMs = null, firstByteMs = null;
  try {
    const response = await fetchRequest(profile.endpoint, {
      method: 'POST', signal: combined, redirect: 'error',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${key}` },
      body: JSON.stringify({
        model: profile.model, messages: [{ role: 'user', content: prompt }], stream: false,
        [profile.tokenLimitField]: profile.maxOutputTokens,
        ...(profile.effort === 'default' ? {} : { reasoning_effort: profile.effort }),
      }),
    });
    headersMs = elapsed(startedAt);
    if (!response.ok) {
      await response.body?.cancel();
      throw new Error(`Provider ${profile.provider} 返回 HTTP ${response.status}；已暂停，不自动重试。`);
    }
    if (!response.body) throw new Error('Provider 没有返回响应正文。');
    let bytes = 0, body = '';
    const decoder = new TextDecoder();
    for await (const chunk of response.body) {
      if (firstByteMs === null) firstByteMs = elapsed(startedAt);
      bytes += chunk.byteLength;
      if (bytes > 64000) { controller.abort(); throw new Error('Provider 响应超过 64 KB，已中止。'); }
      body += decoder.decode(chunk, { stream: true });
    }
    body += decoder.decode();
    let data;
    try { data = JSON.parse(body); }
    catch { throw new Error('Provider 没有返回有效的 JSON 响应。'); }
    const choice = data?.choices?.[0];
    if (choice?.finish_reason !== 'stop' || choice.message?.tool_calls?.length || choice.message?.function_call
      || typeof choice.message?.content !== 'string' || !choice.message.content.trim()) {
      throw new Error('Provider 未完整返回文本行动，或试图调用工具。已暂停，不重试或追加推理。');
    }
    return choice.message.content;
  } catch (error) {
    if (signal?.aborted) throw new Error('请求已取消；本次调用仍计入上限。');
    if (controller.signal.aborted && error.name === 'AbortError') throw new Error('Provider 调用超过 90 秒或被中止。');
    if (error instanceof TypeError) throw new Error(`Provider ${profile.provider} 连接失败；检查服务端地址与网络，不自动重试。`);
    throw error;
  } finally {
    clearTimeout(timeout);
    onTiming({ responseHeadersMs: headersMs, firstByteMs, providerTotalMs: elapsed(startedAt) });
  }
}
