import { createWorld, stepWorld, setAction, observation, intervene, setWeather, restoreWorld, clock, TYPES } from './world.mjs';
import { WorldView } from './view.mjs';

const $ = id => document.getElementById(id);
const paths = {
  world: '<path d="m12 2 9 5v10l-9 5-9-5V7Z"/><path d="m3 7 9 5 9-5M12 12v10M7.5 4.5l9 5v5"/>',
  brain: '<path d="M12 5c-3-5-8-1-6 3-5 0-5 7-1 8-1 5 6 7 7 3 1 4 8 2 7-3 4-1 4-8-1-8 2-4-3-8-6-3Z"/><path d="M12 5v14M6 8l2 2m10-2-2 2M5 16l3-2m11 2-3-2"/>',
  cursor: '<path d="m5 3 14 9-7 1-3 7Z"/>',
  food: '<circle cx="9" cy="15" r="5"/><circle cx="16" cy="15" r="4"/><path d="M12 11V5m0 3C6 8 5 3 5 3s7-1 7 5Zm0-1c1-4 5-4 7-4-1 4-3 5-7 4Z"/>',
  water: '<path d="M12 2S5 10 5 15a7 7 0 0 0 14 0c0-5-7-13-7-13Z"/><path d="M8 15a4 4 0 0 0 4 4"/>',
  tree: '<path d="m12 2-6 7h3l-5 6h5l-4 4h14l-4-4h5l-5-6h3Z"/><path d="M12 19v3"/>',
  stone: '<path d="m8 3 9 1 5 10-6 7-12-2L2 10Z"/><path d="m8 3 1 8 8-7M9 11l7 10M2 10l7 1 13 3"/>',
  home: '<path d="m3 10 9-8 9 8M5 9v12h14V9M10 21v-8h4v8"/>',
  fire: '<path d="M13 2c2 7-6 6-4 12 3 0 6-3 7-5 7 8 2 13-4 13-8 0-11-8-4-14-1 4 0 4 0 4 0-4 6-5 5-10Z"/>',
  artifact: '<path d="m12 2 8 10-8 10-8-10Z"/><path d="m12 2 3 10-3 10-3-10ZM4 12h16"/>',
  person: '<circle cx="12" cy="7" r="4"/><path d="M5 22v-4a7 7 0 0 1 14 0v4M8 18v4m8-4v4"/>',
  sun: '<circle cx="12" cy="12" r="4"/><path d="M12 2v2m0 16v2M2 12h2m16 0h2M5 5l1 1m12 12 1 1M5 19l1-1M18 6l1-1"/>',
  rain: '<path d="M6 14a4 4 0 0 1 0-8 6 6 0 0 1 11-1 4.5 4.5 0 1 1 2 9ZM7 17l-1 3m6-3-1 3m6-3-1 3"/>',
  dry: '<circle cx="12" cy="7" r="3"/><path d="M12 1v1M5 3l1 1m12-1-1 1M4 8h1m14 0h1M3 15h18M6 15l3 3-2 4m2-4 6-1 3 5m-3-5 2-2"/>',
  mouse: '<rect x="6" y="2" width="12" height="20" rx="6"/><path d="M12 2v7M6 9h12"/>',
  spark: '<path d="m12 3 2.5 6.5L21 12l-6.5 2.5L12 21l-2.5-6.5L3 12l6.5-2.5ZM20 2v4m-2-2h4"/>',
  save: '<path d="M3 3h15l3 3v15H3ZM7 3v6h10V3M7 21v-8h10v8"/>',
  restore: '<path d="M3 10a9 9 0 1 1 2 8M3 4v6h6M12 7v5l3 2"/>',
  refresh: '<path d="M20 7a9 9 0 0 0-16 3M4 17a9 9 0 0 0 16-3M20 2v5h-5M4 22v-5h5"/>',
  download: '<path d="M12 3v12m-5-5 5 5 5-5M4 15v6h16v-6"/>',
  focus: '<path d="M8 3H3v5m13-5h5v5M3 16v5h5m13-5v5h-5"/><circle cx="12" cy="12" r="3"/>',
  eye: '<path d="M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12Z"/><circle cx="12" cy="12" r="3"/>',
  pause: '<path d="M8 5v14M16 5v14"/>',
  play: '<path d="m8 4 12 8-12 8Z"/>',
};
function icon(name) {
  return `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${paths[name] || paths.spark}</svg>`;
}
document.querySelectorAll('[data-icon]').forEach(e => { e.innerHTML = icon(e.dataset.icon); });
const seedParam = Number(new URLSearchParams(location.search).get('seed') || 20260905);
let world = createWorld(Number.isFinite(seedParam) ? seedParam : 20260905);
let selected = world.agents[0].id;
let paused = false, speed = 1, mode = 'demo', tool = 'observe', accumulator = 0;
let view, uiAt = 0, lastTime = performance.now(), rosterKey = '', memoryKey = '', eventKey = '';
let modelConnection = null, pending = null, generation = 0, used = 0, budget = 0, toastTimer;
const STORAGE = 'terrarium.world.v1';
function toast(text, duration = 4500) {
  $('toast').textContent = text;
  $('toast').hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { $('toast').hidden = true; }, duration);
}
function element(tag, className, text) {
  const e = document.createElement(tag);
  if (className) e.className = className;
  if (text !== undefined) e.textContent = text;
  return e;
}
function selectTool(next) {
  tool = next;
  if (view) {
    view.tool = next;
    view.preview.visible = false;
  }
  document.querySelectorAll('[data-tool]').forEach(button => {
    button.classList.toggle('active', button.dataset.tool === tool);
    button.setAttribute('aria-pressed', String(button.dataset.tool === tool));
  });
  $('tool-help').replaceChildren(element('span', '', tool === 'observe'
    ? '点击居民查看；拖动旋转世界。'
    : `在陆地上点击投放${tool === 'resident' ? '居民' : TYPES[tool].name}，ESC 取消。`));
}
function selectResident(id) {
  selected = id;
  memoryKey = '';
  updateUI();
}
function setPanel(panel) {
  document.body.dataset.panel = panel;
  document.querySelectorAll('[data-panel]').forEach(b => b.classList.toggle('active', b.dataset.panel === panel));
}
try {
  view = new WorldView($('viewport'), {
    select: selectResident,
    inspect: id => {
      const e = world.entities.find(e => e.id === id);
      toast(`${TYPES[e.type].name}${['artifact', 'fire', 'shelter'].includes(e.type) ? '' : ` · 剩余 ${Math.floor(e.amount)}`} · 居民需要靠近才能交互`);
    },
    place: (x, z) => {
      try {
        intervene(world, tool, x, z);
        toast('已经放下了。接下来，让居民自己发现。');
        updateUI();
      } catch (error) { toast(error.message); }
    },
    error: error => { paused = true; toast(error.message, 30000); updateUI(); },
  });
  $('loading').hidden = true;
} catch (error) {
  paused = true;
  $('loading').textContent = `无法创建 3D 世界：${error.message}。请使用支持 WebGL 2 的浏览器并开启图形加速。`;
  console.error(error);
}

for (const [key, name] of [['hunger', '饱腹'], ['thirst', '水分'], ['energy', '体力'], ['health', '健康']]) {
  const row = element('div', 'need');
  const head = element('div', 'need-head');
  head.append(element('span', '', name), element('span', '', '100'));
  const meter = element('div', `meter ${key}`);
  meter.setAttribute('role', 'meter');
  meter.setAttribute('aria-label', name);
  meter.setAttribute('aria-valuemin', '0');
  meter.setAttribute('aria-valuemax', '100');
  meter.append(element('span'));
  row.id = `need-${key}`;
  row.append(head, meter);
  $('needs').append(row);
}

function updateUI() {
  $('clock').textContent = clock(world.t);
  $('weather-label').textContent = { sun: '晴天', rain: '细雨', drought: '干旱' }[world.weather];
  const alive = world.agents.filter(a => a.alive).length;
  $('population').textContent = String(alive).padStart(2, '0');
  $('alive-label').textContent = `${alive} 位居民`;
  $('resource-count').textContent = String(Math.floor(world.entities.reduce((s, e) => s + (['food', 'water', 'tree', 'stone'].includes(e.type) ? e.amount : 0), 0)));
  $('share-count').textContent = String(world.stats.shares).padStart(2, '0');
  $('discovery-count').textContent = String(world.stats.discoveries).padStart(2, '0');
  $('pause').innerHTML = icon(paused ? 'play' : 'pause');
  $('pause').setAttribute('aria-label', paused ? '继续' : '暂停');
  $('time-status').textContent = pending ? '等待模型 · 时间冻结' : paused ? '世界已暂停' : mode === 'model' ? `Astra · ${used}/${budget} 次` : '世界正在继续';
  $('mode-label').textContent = mode === 'model' ? pending ? 'Astra · 决策中' : `Astra · ${used}/${budget}` : '规则模拟';
  $('weather-help').textContent = {
    sun: '资源缓慢再生，一切刚刚好。',
    rain: '雨水让泉眼、浆果和树木以 3 倍速度恢复。',
    drought: '资源停止再生，居民消耗水分更快。',
  }[world.weather];
  document.querySelectorAll('[data-weather]').forEach(b => {
    b.classList.toggle('active', b.dataset.weather === world.weather);
    b.setAttribute('aria-pressed', String(b.dataset.weather === world.weather));
  });
  const key = world.agents.map(a => `${a.id}:${a.alive}`).join();
  if (key !== rosterKey) {
    rosterKey = key;
    $('roster').replaceChildren(...world.agents.map(a => {
      const button = element('button', `roster-button${a.alive ? '' : ' dead'}`, a.name[0]);
      button.title = `${a.name} · ${a.role}`;
      button.setAttribute('aria-label', `查看${a.name}`);
      button.dataset.id = a.id;
      button.addEventListener('click', () => selectResident(a.id));
      return button;
    }));
  }
  $('roster').querySelectorAll('button').forEach(b => {
    b.classList.toggle('selected', b.dataset.id === selected);
    b.setAttribute('aria-pressed', String(b.dataset.id === selected));
  });
  const a = world.agents.find(a => a.id === selected) || world.agents[0];
  $('resident-name').textContent = a.name;
  $('resident-role').textContent = a.role;
  $('resident-source').textContent = a.source;
  $('resident-goal').textContent = pending?.agentId === a.id ? '等待 Astra 选择行动…' : a.goal;
  for (const name of ['hunger', 'thirst', 'energy', 'health']) {
    const row = $(`need-${name}`);
    row.firstChild.lastChild.textContent = `${Math.round(a[name])} / 100`;
    row.lastChild.firstChild.style.width = `${a[name]}%`;
    row.lastChild.setAttribute('aria-valuenow', String(Math.round(a[name])));
  }
  for (const item of ['food', 'wood', 'stone']) $(`inventory-${item}`).textContent = a.inventory[item];
  $('knowledge').textContent = `感知半径 8 · 已知地点 ${a.known.length} · 交往 ${Object.keys(a.relationships).length} 人`;
  const memories = a.memories.slice(-5).reverse();
  const mk = a.id + JSON.stringify(memories);
  if (memoryKey !== mk) {
    memoryKey = mk;
    $('memories').replaceChildren(...memories.map(m => {
      const row = element('div', 'memory');
      row.append(element('time', '', clock(m.t)), element('p', '', m.text));
      return row;
    }));
  }
  const ek = `${world.nextEvent}:${world.droppedEvents}`;
  if (eventKey !== ek) {
    eventKey = ek;
    $('event-count').textContent = `${world.nextEvent - 1} EVENTS`;
    $('events').replaceChildren(...world.events.slice(-30).reverse().map(e => {
      const row = element('div', `event ${e.kind}`);
      row.append(element('time', '', clock(e.t).split(' · ')[1]), element('i'), element('span', '', e.text));
      return row;
    }));
  }
}

document.querySelectorAll('[data-tool]').forEach(b => b.addEventListener('click', () => {
  selectTool(b.dataset.tool);
  if (matchMedia('(max-width: 820px)').matches) setPanel('world');
}));
document.querySelectorAll('[data-weather]').forEach(b => b.addEventListener('click', () => { setWeather(world, b.dataset.weather); updateUI(); }));
document.querySelectorAll('[data-speed]').forEach(b => b.addEventListener('click', () => {
  speed = Number(b.dataset.speed);
  document.querySelectorAll('[data-speed]').forEach(button => {
    button.classList.toggle('active', Number(button.dataset.speed) === speed);
    button.setAttribute('aria-pressed', String(Number(button.dataset.speed) === speed));
  });
}));
document.querySelectorAll('.mobile-nav button').forEach(b => b.addEventListener('click', () => setPanel(b.dataset.panel)));
$('pause').addEventListener('click', () => { paused = !paused; updateUI(); });
$('focus').addEventListener('click', () => view?.focus());
$('vision').addEventListener('click', () => {
  if (!view) return;
  view.vision = !view.vision;
  $('vision').setAttribute('aria-pressed', String(view.vision));
  toast(view.vision ? '只显示所选居民身边 8 单位内的物件与邻居；地形仍可见。' : '已回到上帝视角。');
});
$('names').addEventListener('click', () => {
  if (!view) return;
  view.showNames = !view.showNames;
  $('names').setAttribute('aria-pressed', String(view.showNames));
});
$('theme').addEventListener('click', () => {
  const theme = document.documentElement.dataset.theme === 'dark' ? 'light' : 'dark';
  document.documentElement.dataset.theme = theme;
  view?.reset();
});
window.addEventListener('keydown', e => {
  if (/INPUT|TEXTAREA|SELECT|BUTTON/.test(e.target.tagName) || document.querySelector('dialog[open]')) return;
  if (e.code === 'Space') { e.preventDefault(); paused = !paused; updateUI(); }
  if (e.code === 'Escape') selectTool('observe');
});
$('save').addEventListener('click', () => {
  try {
    localStorage.setItem(STORAGE, JSON.stringify(world));
    toast('世界已存到这个浏览器。不会在离线时继续模拟。');
  } catch (error) { toast(`存档失败：${error.message}`, 8000); }
});
function cancelRequest() {
  generation++;
  pending?.controller.abort();
  pending = null;
}
function switchToDemo() {
  cancelRequest();
  mode = 'demo';
  $('boundary-copy').textContent = '目前是预设规则驱动的演示。连接模型后，Astra 才会根据每位居民自己的观察选择行动。';
}
function replaceWorld(next) {
  switchToDemo();
  world = next;
  selected = world.agents[0].id;
  accumulator = 0;
  rosterKey = memoryKey = eventKey = '';
  paused = true;
  view?.reset();
  selectTool('observe');
  updateUI();
}
$('load').addEventListener('click', () => {
  try {
    const save = localStorage.getItem(STORAGE);
    if (!save) { toast('还没有存档。先点击「存档」保存一个世界。'); return; }
    replaceWorld(restoreWorld(save));
    toast('存档已恢复并暂停。模型不会自动重连。');
  } catch (error) { toast(`恢复失败：${error.message}`, 8000); }
});
$('export').addEventListener('click', () => {
  const blob = new Blob([JSON.stringify({ ...world, exportNote: 'Snapshot + last 400 events; not a complete replay. No model credentials.' }, null, 2)], { type: 'application/json' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = `terrarium-${world.seed}-${Math.floor(world.t)}.json`;
  a.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
  toast('已导出当前世界快照和最近 400 条事件，不包含模型凭据。');
});
$('reset').addEventListener('click', () => { paused = true; $('reset-dialog').showModal(); updateUI(); });
$('cancel-reset').addEventListener('click', () => $('reset-dialog').close());
$('confirm-reset').addEventListener('click', () => {
  replaceWorld(createWorld(world.seed));
  $('reset-dialog').close();
  toast('同一种子，同一个起点。点击播放开始新的实验。');
});

async function openModel() {
  paused = true;
  updateUI();
  $('model-dialog').showModal();
  $('connect-model').disabled = true;
  $('connection-state').classList.remove('ready');
  $('connection-state').textContent = '正在检查本地连接…';
  modelConnection = null;
  if (!['127.0.0.1', 'localhost', '[::1]'].includes(location.hostname)) {
    $('connection-state').textContent = '当前为静态演示。真实模型需要本地桥接：在 terrarium 目录运行 npm start，再打开终端给出的本地地址。API 密钥不会放在网页里。';
    return;
  }
  try {
    const response = await fetch('/api/status', { signal: AbortSignal.timeout(5000) });
    if (!response.ok) throw new Error(`本地桥接返回 HTTP ${response.status}`);
    const status = await response.json();
    if (status.service !== 'terrarium' || typeof status.token !== 'string') throw new Error('当前地址不是 Terrarium 模型服务');
    modelConnection = status;
    $('model-name').textContent = status.model;
    $('connection-state').textContent = `本地桥接已连接 · 本次服务剩余 ${status.remaining} 次额度上限。\n将使用已登录的 Copilot CLI；认证与模型可用性在第一次调用时确认。`;
    $('connection-state').classList.add('ready');
    $('connect-model').disabled = status.remaining <= 0;
  } catch (error) {
    $('connection-state').textContent = `尚未连接本地模型服务：${error.message}。\n在 terrarium 目录运行 npm start，打开终端显示的地址。静态页面仍可使用完整规则演示。`;
  }
}
$('model-button').addEventListener('click', openModel);
$('open-model').addEventListener('click', openModel);
$('use-demo').addEventListener('click', () => {
  switchToDemo();
  paused = false;
  $('model-dialog').close();
  updateUI();
});
$('connect-model').addEventListener('click', () => {
  const amount = Number($('budget').value);
  if (!Number.isInteger(amount) || amount < 1 || amount > 24) { $('budget').reportValidity(); toast('调用上限必须是 1 到 24 的整数。'); return; }
  if (!modelConnection) return;
  cancelRequest();
  budget = Math.min(amount, modelConnection.remaining);
  used = 0;
  mode = 'model';
  for (const a of world.agents) { a.action = null; a.path = []; a.nextDecision = world.t; a.goal = '等待模型决定'; }
  $('boundary-copy').textContent = '现在由 Astra 选择居民行动；移动、资源和生命需求仍由固定世界规则执行。这是模型 + 环境的实验，不是 AGI 证明。';
  paused = false;
  $('model-dialog').close();
  updateUI();
});
async function requestDecision(a) {
  if (used >= budget) {
    paused = true;
    toast(`本轮 ${budget} 次模型调用已用完，世界已暂停。不会回退到规则模拟。`, 12000);
    updateUI();
    return;
  }
  const controller = new AbortController();
  const request = { controller, agentId: a.id, generation };
  pending = request;
  used++;
  updateUI();
  const timeout = setTimeout(() => controller.abort(new Error('模型请求超时。')), 110000);
  try {
    const response = await fetch('/api/decide', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-Terrarium-Token': modelConnection.token },
      body: JSON.stringify({ observation: observation(world, a) }),
      signal: controller.signal,
    });
    const data = await response.json();
    if (!response.ok) throw new Error(data.error || `HTTP ${response.status}`);
    if (request.generation !== generation) return;
    setAction(world, a, data.decision, 'Astra');
  } catch (error) {
    if (request.generation !== generation) return;
    paused = true;
    toast(`模型已停下：${error.message} 没有切换到规则模拟。`, 30000);
    a.goal = '模型调用失败 · 等待处理';
  } finally {
    clearTimeout(timeout);
    if (pending === request) pending = null;
    updateUI();
  }
}

function animate(now) {
  requestAnimationFrame(animate);
  const delta = Math.min((now - lastTime) / 1000, 0.25);
  lastTime = now;
  if (!paused && !pending && !document.hidden && view) {
    const ready = mode === 'model' && world.agents.find(a => a.alive && !a.action && a.nextDecision <= world.t);
    if (ready && (used < budget || !world.agents.some(a => a.alive && a.action))) requestDecision(ready);
    else {
      accumulator += delta * speed;
      while (accumulator >= 0.25) {
        try { stepWorld(world, 0.25, mode); }
        catch (error) {
          paused = true;
          accumulator = 0;
          toast(`模拟已暂停：${error.message}`, 30000);
          console.error(error);
          break;
        }
        accumulator -= 0.25;
        if (mode === 'model' && used < budget && world.agents.some(a => a.alive && !a.action && a.nextDecision <= world.t)) break;
      }
      if (!world.agents.some(a => a.alive)) {
        paused = true;
        toast('岛上已没有活着的居民。你可以投放新居民，或开始新的实验。', 12000);
      }
    }
  }
  view?.render(world, selected);
  if (now - uiAt > 250) { uiAt = now; updateUI(); }
}
window.terrarium = Object.freeze({
  snapshot: () => structuredClone(world),
  observation: id => observation(world, world.agents.find(a => a.id === id) || world.agents[0]),
  screenPoint: p => view?.screenPoint(p),
});
window.addEventListener('pagehide', cancelRequest);
updateUI();
requestAnimationFrame(animate);
