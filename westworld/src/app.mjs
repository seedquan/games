import { VERSION, ITEMS, WEATHER, PLACES, SCENARIOS, MAX_RECORD_BYTES, createWorld, timeLabel, observation, baseline, advance, currentAgent, intervene, exportRecord, restoreRecord, log, parseDecision } from './world.mjs';
import { residentPortrait, residentFigure, TOWN_WIDTH, TOWN_HEIGHT } from './pixel-art.mjs';
import { projectTown, townScenery, townResidentPoint, townBubbleLayout, createTownMotion, townMotionFrames } from './town-scene.mjs';
import { createTown3DView, town3DBounds } from './town-3d.mjs';
import { islandPlanPoint } from './island-layout.mjs';

const $ = id => document.getElementById(id);
const esc = value => String(value).replace(/[&<>"']/g, ch => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[ch]);
const placeName = id => PLACES.find(p => p.id === id)?.name || id;
const sourceName = source => source === 'model' ? 'AI' : source === 'rule' ? 'RULE' : 'WORLD';
const SAVE_KEY = 'westworld-lab-manual-v1', AUTO_KEY = 'westworld-lab-auto-v1';
const MODELS_KEY = 'westworld-lab-resident-models-v1';
let world = createWorld(), selectedAgent = 'mara', selectedPlace = 'workshop', selectedItem = 'pump';
let filter = 'all', inspectorTab = 'state', residentView = false, pendingScenario = 'sandbox';
let mode = 'rule', running = false, busy = false, stopRequested = false, timer, requestController, thinking = null;
let bridgeStatus = null, allowance = 12, calls = 0, connectionId = 0;
let residentProfiles = Object.fromEntries(world.agents.map(a => [a.id, 'fast']));
let draftProfiles = { ...residentProfiles }, requestStartedAt = 0, lastModelCall = null;
let saveFailureShown = false, lastFeedKey = '', runFinishedNotice = '';
let pendingImport = null, importGeneration = 0;
const townMotion = createTownMotion(), motionPreference = window.matchMedia('(prefers-reduced-motion: reduce)');
let sceneAnimations = [], sceneSceneryKey = '', sceneZoom = 1, townDrag = null;
const townCanvas = $('town-canvas'), townContext = townCanvas.getContext('webgl2', { antialias: true, alpha: false });
const town3d = townContext ? createTown3DView(townCanvas, townContext, {
  requestFrame: callback => window.requestAnimationFrame(callback),
  cancelFrame: id => window.cancelAnimationFrame(id),
  pixelRatio: () => window.devicePixelRatio || 1,
  onError: message => { sceneView = '2d'; $('scene-view').value = '2d'; $('scene-view').disabled = true; notify(message, true); renderMap(); },
  palette: () => {
    const style = window.getComputedStyle(document.documentElement);
    const colors = Object.fromEntries(['bg', 'bg-elevated', 'border-strong', 'text', 'text-muted', 'warning', 'success', 'accent', 'accent-fg', 'link', 'surface']
      .map(key => [key, style.getPropertyValue(`--cp-${key}`).trim()]));
    colors.sand = colors.bg;
    colors.ink = document.documentElement.getAttribute('data-theme') === 'dark' ? colors['accent-fg'] : colors.text;
    return colors;
  },
}) : null;
let sceneView = town3d ? '3d' : '2d';
$('scene-view').value = sceneView;
$('scene-view').disabled = !town3d;

function notify(text, error = false) {
  $('notice').textContent = text;
  $('notice').classList.toggle('error', error);
  $('notice').hidden = false;
}
function persist(manual = false) {
  try {
    localStorage.setItem(manual ? SAVE_KEY : AUTO_KEY, JSON.stringify(exportRecord(world)));
    if (manual) notify('已保存独立手动存档。后续自动进度不会覆盖它。');
    saveFailureShown = false;
    return true;
  } catch (error) {
    if (!saveFailureShown || manual) notify(`无法保存到浏览器：${error.message}。请使用“导出”保留实验。`, true);
    saveFailureShown = true;
    return false;
  }
}
function acceptRestoredWorld(restored) {
  world = restored;
  mode = 'rule'; calls = 0; bridgeStatus = null; connectionId++; lastFeedKey = '';
  lastModelCall = null;
  selectedPlace = world.agents.find(a => a.id === selectedAgent).location;
  log(world, 'system', '进度已恢复，时间已暂停', '真实 AI 不会自动重连。若之前使用模型，请重新启用并取消“重新开始”；否则接下来的规则行动会形成混合来源记录。');
}
function load(key) {
  const raw = localStorage.getItem(key);
  if (!raw) return false;
  acceptRestoredWorld(restoreRecord(raw));
  return true;
}
async function previewImport() {
  const generation = ++importGeneration, file = $('import-file').files[0];
  pendingImport = null; $('import-confirm').disabled = true;
  $('import-preview').classList.remove('error');
  $('import-preview').textContent = file ? '正在读取实验存档…' : '选择之前导出的 JSON 文件，查看将恢复的进度。';
  if (!file) return;
  try {
    if (file.size > MAX_RECORD_BYTES) throw new Error('存档超过 10 MB 限制。');
    const restored = restoreRecord(await file.text());
    if (generation !== importGeneration || !$('import-dialog').open) return;
    pendingImport = restored;
    const m = restored.metrics;
    $('import-preview').textContent = [
      `${SCENARIOS[restored.scenario].name} · 种子 ${restored.seed}`,
      `${timeLabel(restored)} · 已完成 ${restored.round} 轮，本轮 ${restored.turn}/4 已行动`,
      `来源记录：规则 ${m.rule} 次 / AI ${m.model} 次 · 干预 ${restored.interventionCount} 次`,
      `保留 ${restored.events.length} 条事件、${restored.audit.length} 次决策审计`,
      restored.droppedEvents || restored.droppedAudit ? `更早的 ${restored.droppedEvents} 条事件、${restored.droppedAudit} 次审计已不在文件中。` : '',
    ].filter(Boolean).join('\n');
    $('import-confirm').disabled = false;
  } catch (error) {
    if (generation !== importGeneration || !$('import-dialog').open) return;
    $('import-preview').textContent = `无法导入：${error.message} 当前世界保持不变。`;
    $('import-preview').classList.add('error');
  }
}
function itemSummary(items, max = 3) {
  const entries = Object.entries(items).filter(([, n]) => n > 0);
  return entries.slice(0, max).map(([id, n]) => `${ITEMS[id].name} ${n}`).join(' · ') + (entries.length > max ? ' …' : '') || '没有可见物资';
}
const profileById = id => bridgeStatus?.profiles.find(p => p.id === id);
const activeProfile = (agent = currentAgent(world)) => profileById(residentProfiles[agent.id]);
const draftReady = () => world.agents.every(a => profileById(draftProfiles[a.id])?.available);
const duration = ms => Number.isFinite(ms) && ms >= 0 ? `${(ms / 1000).toFixed(1)} 秒` : '未提供';
function renderModelProgress() {
  $('model-performance').hidden = mode !== 'model';
  const profile = activeProfile();
  $('model-progress').textContent = thinking
    ? `第 ${world.turn + 1}/4 位居民 · ${world.agents.find(a => a.id === thinking).name}正在决策 · 已等待 ${Math.floor((performance.now() - requestStartedAt) / 1000)} 秒`
    : profile ? `居民按顺序独立决策 · ${world.agents.map(a => {
      const p = activeProfile(a);
      return `${a.name}：${p?.providerLabel || '未配置'} / ${p?.model || '未配置'} / ${p?.effort || '未配置'}`;
    }).join('；')}` : '';
  const t = lastModelCall?.timing;
  $('model-timing').textContent = lastModelCall
    ? `上次 ${lastModelCall.provider} / ${lastModelCall.model}：请求 ${duration(lastModelCall.elapsedMs)}（${{ success: '成功', failure: '失败', cancelled: '已取消' }[lastModelCall.outcome]}） · 服务端 ${duration(t?.totalMs)}${lastModelCall.adapter === 'copilot'
      ? ` · 子进程启动 ${duration(t?.processSpawnMs)} · 首输出 ${duration(t?.firstOutputMs)} · 进程退出 ${duration(t?.processExitMs)}`
      : ` · 响应头 ${duration(t?.responseHeadersMs)} · 正文首字节 ${duration(t?.firstByteMs)}`}`
    : '尚无调用记录；连接和切换配置不会发起模型请求。';
}
function renderControls() {
  $('weather-controls').innerHTML = Object.entries(WEATHER).map(([id, weather]) => `<button class="weather-button ${world.weather === id ? 'active' : ''}" data-weather="${id}" aria-pressed="${world.weather === id}" ${busy ? 'disabled' : ''}><span class="weather-symbol" aria-hidden="true">${weather.symbol}</span>${weather.name}</button>`).join('');
  $('weather-description').textContent = WEATHER[world.weather].description;
  $('weather-code').textContent = world.weather.toUpperCase();
  $('item-controls').innerHTML = Object.entries(ITEMS).map(([id, item]) => `<button class="item-button ${selectedItem === id ? 'active' : ''}" data-item="${id}" aria-pressed="${selectedItem === id}">${item.name}</button>`).join('');
  $('item-description').textContent = ITEMS[selectedItem].description;
  $('drop-location').value = selectedPlace;
  $('scenario-controls').innerHTML = Object.entries(SCENARIOS).map(([id, s]) => `<button class="scenario-button ${world.scenario === id ? 'active' : ''}" data-scenario="${id}" aria-pressed="${world.scenario === id}" ${busy ? 'disabled' : ''}><strong>${s.name}</strong><span>${s.subtitle.split(' / ')[0]}</span></button>`).join('');
  for (const id of ['drop', 'whisper-send', 'save', 'restore', 'import-open', 'reset', 'model-open', 'step']) $(id).disabled = busy;
  $('play').innerHTML = running || busy ? '<span aria-hidden="true">Ⅱ</span> 暂停世界' : '<span aria-hidden="true">▶</span> 运行世界';
  $('play').setAttribute('aria-pressed', String(running || busy));
  $('run-state').textContent = thinking ? `${world.agents.find(a => a.id === thinking).name}正在决策…` : busy ? '居民正在行动…' : running ? '世界运行中' : '时间已暂停';
  $('mode-label').textContent = mode === 'model' ? `真实 AI · ${Math.min(allowance - calls, bridgeStatus?.remaining ?? 0)} 次余量` : '规则演示';
  $('model-open').classList.toggle('connected', mode === 'model');
  $('speed').disabled = mode === 'model';
  $('speed').title = '仅调整规则演示速度；真实 AI 仍需依次等待模型返回。';
  $('clock').textContent = timeLabel(world);
  $('round-label').textContent = `WORLD TIME / ROUND ${String(world.round).padStart(3, '0')}`;
  $('weather-summary').textContent = `${WEATHER[world.weather].symbol} ${WEATHER[world.weather].name} · ${world.turn ? `本轮 ${world.turn}/4 已行动` : '新一轮，新的可能'}`;
  $('seed-label').textContent = `SEED ${world.seed}`;
  $('source-note').textContent = mode === 'model' ? '真实模型独立决策 · 简短意图不是内部思维' : '规则演示 · 行为来自预设策略，不是真实 AI';
  renderModelProgress();
}
function renderMap() {
  const self = world.agents.find(a => a.id === selectedAgent);
  const scene = projectTown(world, selectedAgent, residentView), now = performance.now();
  const is3d = sceneView === '3d', project = is3d ? town3d.camera.ground : islandPlanPoint;
  $('world-map').classList.toggle('view-3d', is3d);
  $('scene-rotate-left').disabled = !is3d; $('scene-rotate-right').disabled = !is3d;
  $('world-map').setAttribute('data-view', sceneView);
  $('world-map').setAttribute('data-camera-yaw', String(town3d?.camera.yaw ?? 0));
  $('town-viewport').setAttribute('aria-label', is3d ? '立体小镇，鼠标拖动旋转，Shift 加拖动平移；也可使用旋转按钮' : '二维小镇，放大后可拖动或使用方向键滚动');
  const sceneryKey = JSON.stringify([scene.weather, scene.places.map(p => [p.id, p.visible, p.crop, p.shelter])]);
  if (sceneryKey !== sceneSceneryKey) {
    $('town-landscape').innerHTML = townScenery(scene);
    sceneSceneryKey = sceneryKey;
  }
  $('town-places').innerHTML = scene.places.map(p => {
    const bounds = is3d ? town3DBounds(PLACES.find(q => q.id === p.id), town3d.camera) : null;
    const plan=islandPlanPoint(p.point);
    const point = bounds || { x: plan.x, y: plan.y - 10 };
    return `<button class="place ${p.id === 'home' ? 'shared-home' : ''} ${selectedPlace === p.id ? 'selected' : ''} ${p.visible ? '' : 'fogged'}"
    data-place="${p.id}" style="left:${point.x / TOWN_WIDTH * 100}%;top:${point.y / TOWN_HEIGHT * 100}%;${bounds ? `width:${bounds.width / TOWN_WIDTH * 100}%;height:${bounds.height / TOWN_HEIGHT * 100}%` : 'width:8%;height:10%'}"
    aria-pressed="${selectedPlace === p.id}" aria-label="${p.name}，${p.visible ? esc(itemSummary(p.items, 9)) : '当前不可见'}"><span class="place-name">${p.name}</span></button>`;
  }).join('');
  const motions = townMotion.update(scene, world, {
    now, animate: !stopRequested && !document.hidden && !motionPreference.matches,
    duration: mode === 'rule' ? 1100 / Number($('speed').value) : 1100,
  });
  town3d?.enable(is3d);
  if (is3d) town3d.update(scene, motions);
  for (const animation of sceneAnimations) animation.cancel();
  sceneAnimations = [];
  const mapWidth = $('world-map').clientWidth || TOWN_WIDTH;
  const bubbles = townBubbleLayout(scene.residents, mapWidth, project);
  $('town-residents').innerHTML = scene.residents.map(a => {
    const p = project(townResidentPoint(a)), bubble = bubbles.get(a.id);
    const settled = a.alive ? a.activity?.label || '暂无动作记录' : '失去行动能力';
    const status = a.id === thinking ? '选择行动中…' : motions.has(a.id) ? '赶路中…' : settled;
    const speech = a.id === thinking ? null : a.activity?.speech;
    const showBubble = !!a.activity || a.id === thinking || motions.has(a.id) || !a.alive;
    const title = `${a.name} · ${placeName(a.location)} · ${a.activity?.detail || settled}${speech ? `\n最近发言：${speech}` : ''}`;
    const tailWidth = Math.abs(bubble.shift) + 2, start = bubble.shift < 0 ? 1 : tailWidth - 1, end = tailWidth - start;
    return `<div class="resident-anchor ${motions.has(a.id) ? 'moving' : ''}" data-motion="${a.id}" style="transform:translate(${p.x / TOWN_WIDTH * 100}%,${p.y / TOWN_HEIGHT * 100}%)">
      <button class="scene-resident ${a.id === selectedAgent ? 'selected' : ''} ${a.alive ? '' : 'inactive'}" data-scene-agent="${a.id}" aria-pressed="${a.id === selectedAgent}" ${is3d ? `style="height:${town3d.camera.actorHeight / TOWN_WIDTH * mapWidth}px;aspect-ratio:auto"` : ''}
        aria-label="${esc(title)}" title="${esc(title)}">${residentFigure(a.id)}
        ${showBubble ? `<svg class="bubble-connector" aria-hidden="true" viewBox="0 0 ${tailWidth} 8" style="left:calc(50% + ${Math.min(bubble.shift, 0) - 1}px);width:${tailWidth}px"><path d="M${start} 0V4H${end}V8"/></svg>
        <span class="resident-bubble ${speech ? 'has-speech' : ''} ${bubble.compact ? 'compact' : ''} ${a.id === thinking ? 'thinking' : ''}" aria-hidden="true" style="--bubble-shift:${bubble.shift}px;--bubble-width:${bubble.width}px">
          <span class="bubble-status" data-settled="${esc(settled)}">${esc(status)}</span>${speech ? `<span class="bubble-speech">“${esc(speech)}”</span>` : ''}
        </span>` : ''}<span class="scene-resident-name">${esc(a.name)}${a.alive ? '' : ' · 失能'}</span></button></div>`;
  }).join('');
  for (const anchor of $('town-residents').querySelectorAll('[data-motion]')) {
    const motion = motions.get(anchor.dataset.motion);
    if (!motion) continue;
    const animation = anchor.animate(townMotionFrames(motion, now, project), {
      duration: Math.max(1, motion.startedAt + motion.duration - now), easing: 'linear',
    });
    animation.onfinish = () => {
      anchor.classList.remove('moving');
      const label = anchor.querySelector('.bubble-status');
      label.textContent = label.dataset.settled;
    };
    sceneAnimations.push(animation);
  }
  const site = scene.places.find(p => p.id === selectedPlace);
  $('scene-site').textContent = `${site.name}${site.id === 'home' ? ' · 四位居民共同居住，可休息、见面与领取公共补给' : ''} · ${site.visible ? `${itemSummary(site.items, 9)}${site.crop ? ` · 作物 ${site.crop} 轮后成熟` : ''}` : '当前不可见，需亲自到访才能获知物资'}`;
  $('scene-status').textContent = `${WEATHER[world.weather].name} · ROUND ${String(world.round).padStart(3, '0')} · ${mode === 'model' ? '真实 AI' : '规则演示'}`;
  const speaker = scene.residents.find(a => a.id === selectedAgent), speech = speaker?.activity?.speech;
  const dialogue = speech ? `${speaker.name} · ${speaker.activity.source === 'model' ? 'AI' : '规则'}最近发言：${speech}` : '';
  $('scene-dialogue').hidden = !speech;
  if ($('scene-dialogue').textContent !== dialogue) $('scene-dialogue').textContent = dialogue;
  $('perspective').textContent = residentView ? `◉ ${self.name}的视野` : '◎ 上帝视角';
  $('perspective').setAttribute('aria-pressed', String(residentView));
  $('map-caption').textContent = residentView ? '雾中不显示远处居民；不会展示你未听见的往事与低语。'
    : is3d ? '拖动旋转，Shift + 拖动平移。点建筑投放，点居民读对话；箭头按钮也可旋转。'
      : '头顶显示最近行动与发言；点居民读完整对话，点建筑选择投放地点。放大后可拖动。';
  $('population').textContent = `${world.agents.filter(a => a.health > 0).length} / 4 活跃`;
}
function zoomTown(next) {
  const viewport = $('town-viewport'), zoom = Math.max(1, Math.min(4, next)), ratio = zoom / sceneZoom;
  sceneZoom = zoom;
  $('world-map').style.width = `${sceneZoom * 100}%`;
  $('world-map').style.height = `${sceneZoom * 100}%`;
  viewport.scrollLeft = (viewport.scrollLeft + viewport.clientWidth / 2) * ratio - viewport.clientWidth / 2;
  viewport.scrollTop = (viewport.scrollTop + viewport.clientHeight / 2) * ratio - viewport.clientHeight / 2;
  $('scene-zoom-label').textContent = `${sceneZoom}×`;
  $('scene-zoom-out').disabled = sceneZoom === 1;
  $('scene-zoom-in').disabled = sceneZoom === 4;
  renderMap();
}
function renderFeed() {
  const feedKey = `${world.nextEvent}:${filter}`;
  if (lastFeedKey === feedKey) return;
  lastFeedKey = feedKey;
  const feed = $('feed'), before = feed.scrollTop, oldHeight = feed.scrollHeight;
  const events = world.events.filter(event => filter === 'all' || (filter === 'residents' && event.source) || (filter === 'dialogue' && ['social', 'dialogue'].includes(event.type)) || (filter === 'god' && event.type === 'god')).slice(-80).reverse();
  const icons = { god: '✧', system: '◎', experiment: '↗', world: '♧', dialogue: '“', social: '⇄', discovery: '◇', tool: '⚒', build: '⌂', failure: '!', move: '↗', survival: '◌', wait: '·' };
  feed.innerHTML = events.length ? events.map(event => {
    const person = world.agents.find(a => a.id === event.agent);
    const audit = world.audit.find(a => a.eventId === event.id);
    return `<article class="event ${esc(event.type)}"><div class="event-icon" aria-hidden="true">${icons[event.type] || person?.initial || '·'}</div><div>
      <div class="event-meta"><strong>${esc(event.title)}</strong><span class="source-chip ${event.source === 'model' ? 'model' : ''}">${event.type === 'god' ? 'OBSERVER' : sourceName(event.source)}</span><time>${esc(event.time?.split(' · ')[1] || '')} / R${event.round}</time></div>
      <p class="event-text">${esc(event.text)}</p>${event.intent ? `<details><summary>行动意图 / 查看证据</summary><p>简短意图：${esc(event.intent)}</p>${audit ? `<p>输入为该居民当时的局部感知，结果由引擎执行。</p><pre>${esc(JSON.stringify(audit, null, 2))}</pre>` : '<p>此条详细审计已超出保留窗口。</p>'}</details>` : ''}
      </div></article>`;
  }).join('') : '<p class="empty">这里还没有记录。<br>让世界运行，或亲手改变一点什么。</p>';
  feed.scrollTop = $('follow').checked ? 0 : Math.max(0, before + feed.scrollHeight - oldHeight);
  $('event-count').textContent = `${world.events.length} 条记录${world.droppedEvents ? ' · 滚动保留' : ''}`;
}
function renderResidents() {
  const whisperTarget = $('whisper-agent').value;
  $('whisper-agent').innerHTML = world.agents.map(a => `<option value="${a.id}">${esc(a.name)} · ${esc(a.role)}</option>`).join('');
  $('whisper-agent').value = world.agents.some(a => a.id === whisperTarget) ? whisperTarget : selectedAgent;
  $('resident-list').innerHTML = world.agents.map(a => `<button class="resident-card ${a.id === selectedAgent ? 'selected' : ''}" data-agent="${a.id}" aria-pressed="${a.id === selectedAgent}">
    ${residentPortrait(a.id)}<span><span class="resident-name-line"><strong>${esc(a.name)}</strong><span>${esc(a.role)}</span>${a.health > 0 ? '<i class="status-dot"></i>' : ''}</span>
    <span class="resident-location">${esc(placeName(a.location))} · ${a.health > 0 ? `${a.visited.length}/${PLACES.length} 已探索` : '失去行动能力'}</span>
    ${mode === 'model' && activeProfile(a) ? `<span class="resident-model">${esc(activeProfile(a).providerLabel)} · ${esc(activeProfile(a).model)} / ${esc(activeProfile(a).effort)}</span>` : ''}
    <span class="resident-intent ${thinking === a.id ? 'thinking' : ''}">${thinking === a.id ? '正在独立选择行动…' : esc(a.intent)}</span></span></button>`).join('');
  const a = world.agents.find(a => a.id === selectedAgent);
  $('inspector-heading').innerHTML = `<div class="inspector-title">${residentPortrait(a.id, 'inspector')}<div><h2>${esc(a.name)}</h2><p>${esc(a.role)} / RESIDENT ${a.id.toUpperCase()}</p></div></div>`;
  const source = a.lastSource === 'model' ? 'AI 简短行动说明' : a.lastSource === 'rule' ? '规则策略标签，不是 AI 思维' : '初始目标';
  if (inspectorTab === 'state') {
    $('inspector-body').innerHTML = `<div class="needs">${[['health', '健康'], ['thirst', '水分'], ['hunger', '饱腹'], ['energy', '精力']].map(([key, name]) => `<div><div class="need-label"><span>${name}</span><strong>${Math.round(a[key])}<span class="muted">/100</span></strong></div><progress class="${a[key] < 30 ? 'low' : ''}" value="${a[key]}" max="100" aria-label="${name}"></progress></div>`).join('')}</div>
    <p class="intent-label">${source}</p><div class="intent-box">${esc(a.intent)}</div>
    <div class="inspector-section"><h3>长期目标</h3><p>${esc(a.goal)}</p></div><div class="inspector-section"><h3>性格设定</h3><p>${esc(a.trait)}</p></div>
    <div class="inspector-section"><h3>随身物品 · 每种上限 12</h3><div class="inventory">${Object.entries(a.inventory).filter(([, n]) => n).map(([id, n]) => `<span>${ITEMS[id].name} ×${n}</span>`).join('') || '<span>空空如也</span>'}</div></div>
    <div class="inspector-section"><h3>最近的实际结果</h3><p>${esc(a.lastAction)}</p></div>
    ${Object.keys(a.relationships).length ? `<div class="inspector-section"><h3>收到的帮助</h3><p>${Object.entries(a.relationships).map(([id, n]) => `${esc(world.agents.find(a => a.id === id).name)} · ${n} 次`).join(' / ')}</p></div>` : ''}`;
  } else if (inspectorTab === 'memory') {
    $('inspector-body').innerHTML = `<p class="memory-note">只属于${esc(a.name)}的经历。保留最近 24 条，模型读取最近 12 条；转述不等于事实。</p>${a.discoveries.length ? `<div class="intent-box">${a.discoveries.map(esc).join('<br>')}</div><br>` : ''}${a.memories.length ? [...a.memories].reverse().map(m => `<div class="memory"><span class="mono">ROUND ${String(m.round).padStart(3, '0')}</span><p>${esc(m.text)}</p></div>`).join('') : '<p class="empty">还没有自己的故事。<br>第一次行动之后，记忆开始累积。</p>'}`;
  } else {
    const o = observation(world, a);
    $('inspector-body').innerHTML = `<p class="memory-note">这是下一次决策可获得的输入。远处的存量只是旧观察，不会实时更新。</p>
    <div class="perception-place"><h3>此刻 · ${esc(o.here.name)}</h3><p>${esc(itemSummary(o.here.items, 9))}</p><p>${o.here.shelter ? '有公共遮蔽处' : '露天地点'} / ${WEATHER[o.weather].name}</p></div>
    <div class="inspector-section"><h3>身边的人</h3><p>${o.neighbors.map(n => `${esc(n.name)}（${esc(n.condition)}）`).join('<br>') || '没有人在附近。'}</p></div>
    <div class="inspector-section"><h3>去过的地方</h3><p>${Object.entries(o.knownPlaces).map(([id, k]) => `${placeName(id)} · R${k.round} 的旧观察`).join('<br>')}</p></div>
    <details class="inspector-section"><summary class="small">查看完整局部输入 JSON</summary><pre>${esc(JSON.stringify(o, null, 2))}</pre></details>`;
  }
}
function renderMetrics() {
  const m = world.metrics;
  const modelValid = m.model ? `${Math.round(m.modelValid / m.model * 100)}%` : '—';
  const exploration = world.agents.reduce((n, a) => n + a.visited.length, 0);
  $('metrics').innerHTML = [[m.tools, '成功使用工具'], [m.gifts, '实际物资互助'], [`${exploration}/${PLACES.length * world.agents.length}`, '个人地点覆盖'], [modelValid, '模型行动合法率']].map(([value, name]) => `<div class="metric"><strong>${value}</strong><span>${name}</span></div>`).join('');
  const s = SCENARIOS[world.scenario];
  $('experiment-question').innerHTML = `<strong>${s.question}</strong><p>${s.goal}</p><p>来源：规则 ${m.rule} 次 / 模型 ${m.model} 次 · 干预 ${world.interventionCount} 次。合法率仅统计已解析并执行的模型行动。</p>${world.experimentResult ? `<span class="result-label">第 8 轮结论：${world.experimentResult.passed ? '观察目标达成' : '观察目标未达成'} · ${world.experimentResult.alive}/4 存活</span>` : world.scenario !== 'sandbox' ? `<span class="result-label">观察窗口 ${Math.min(8, world.round)} / 8 轮</span>` : ''}`;
}
function render() { renderControls(); renderMap(); renderFeed(); renderResidents(); renderMetrics(); }
function pause(message) {
  running = false; stopRequested = true; clearTimeout(timer);
  requestController?.abort();
  if (message) notify(message);
  renderControls(); renderMap();
}
async function modelDecision(agent) {
  if (!bridgeStatus || calls >= allowance || bridgeStatus.remaining <= 0) throw new Error('模型调用上限已用完，世界已暂停。可存档并重启桥接服务，或明确切换回规则演示。');
  const profile = activeProfile(agent);
  if (!profile?.available) throw new Error(`${agent.name}的 Provider 配置不可用；请重新连接并检查服务端配置。`);
  requestController = new AbortController();
  const controller = requestController, timeout = setTimeout(() => controller.abort(), 100000);
  calls++;
  bridgeStatus.remaining--;
  thinking = agent.id;
  requestStartedAt = performance.now();
  const progressTimer = setInterval(renderModelProgress, 1000);
  let timing = null, outcome = 'failure';
  renderControls(); renderResidents(); renderMap();
  try {
    const response = await fetch('/api/decide', {
      method: 'POST', signal: controller.signal,
      headers: { 'Content-Type': 'application/json', 'X-Westworld-Token': bridgeStatus.token },
      body: JSON.stringify({ observation: observation(world, agent), profile: profile.id }),
    });
    const data = await response.json();
    timing = data.timing ?? null;
    if (Number.isInteger(data.remaining)) bridgeStatus.remaining = data.remaining;
    if (!response.ok) throw new Error(data.error || `模型桥接返回 HTTP ${response.status}`);
    const decision = parseDecision(data.decision);
    outcome = 'success';
    return decision;
  } finally {
    clearTimeout(timeout);
    clearInterval(progressTimer);
    lastModelCall = { timing, provider: profile.providerLabel, model: profile.model, adapter: profile.adapter,
      elapsedMs: performance.now() - requestStartedAt, outcome: controller.signal.aborted ? 'cancelled' : outcome };
    if (requestController === controller) requestController = null;
    thinking = null;
    renderModelProgress();
  }
}
async function runRound() {
  if (busy) return;
  if (world.agents.every(a => a.health <= 0)) { pause('所有居民已失去行动能力。请重置世界，开始新的实验。'); return; }
  busy = true; stopRequested = false; runFinishedNotice = ''; renderControls();
  const startingRound = world.round;
  try {
    while (world.round === startingRound && !stopRequested) {
      const agent = currentAgent(world);
      const decision = agent.health <= 0 ? { action: 'wait' } : mode === 'model' ? await modelDecision(agent) : baseline(observation(world, agent));
      if (stopRequested) break;
      const profile = mode === 'model' && agent.health > 0 ? activeProfile(agent) : null;
      advance(world, decision, mode, profile ? { provider: profile.provider, model: profile.model, effort: profile.effort } : null);
      persist(); render();
      if (mode === 'rule') await new Promise(resolve => setTimeout(resolve, 180 / Number($('speed').value)));
    }
    if (world.round === 8 && world.turn === 0 && world.scenario !== 'sandbox') {
      running = false;
      runFinishedNotice = '第 8 轮观察窗口已结束，已自动暂停。结论和证据可在实验面板与导出记录中查看。';
    }
    if (mode === 'model' && (calls >= allowance || bridgeStatus.remaining <= 0)) {
      running = false;
      runFinishedNotice = '已达到模型调用上限，世界已暂停；没有自动切回规则模式。';
    }
  } catch (error) {
    running = false;
    if (error.name === 'AbortError') {
      notify(stopRequested ? '已暂停并取消等待中的模型请求。已发生的调用仍可能计费。' : '模型请求等待超时，世界已暂停。', !stopRequested);
    } else {
      notify(error.message, true);
      log(world, 'failure', '决策中断，未自动降级', error.message);
    }
    persist();
  } finally {
    busy = false; thinking = null; render();
    if (runFinishedNotice) notify(runFinishedNotice);
    if (running) timer = setTimeout(runRound, mode === 'model' ? 500 : 1600 / Number($('speed').value));
  }
}
function togglePlay() {
  if (running || busy) { pause(); return; }
  running = true; $('notice').hidden = true; runRound();
}
function doIntervention(data) {
  if (busy) { notify('居民正在行动，请先暂停再干预。'); return; }
  try { intervene(world, data); persist(); render(); }
  catch (error) { notify(error.message, true); }
}
function requestReset(scenario) {
  pause();
  pendingScenario = scenario;
  $('seed-input').value = world.seed;
  $('reset-title').textContent = `开始「${SCENARIOS[scenario].name}」`;
  $('reset-dialog').showModal();
}
async function detectBridge() {
  const id = ++connectionId;
  bridgeStatus = null; $('model-enable').disabled = true;
  $('model-profile').disabled = true;
  $('resident-model-config').innerHTML = '';
  if (!['127.0.0.1', 'localhost'].includes(location.hostname) || location.protocol !== 'http:') {
    $('bridge-status').textContent = '静态页面：规则模式可用；真实 AI 请在本机服务中打开。';
    return;
  }
  $('bridge-status').textContent = '正在检测本地桥接…';
  try {
    const response = await fetch('/api/status', { signal: AbortSignal.timeout(5000) });
    if (!response.ok) throw new Error(`桥接 HTTP ${response.status}`);
    const data = await response.json();
    if (data.service !== 'westworld' || typeof data.token !== 'string') throw new Error('这个端口不是尘湾模型桥接。');
    if (!Array.isArray(data.profiles) || !data.profiles.length
      || !data.profiles.every(p => p && typeof p.id === 'string' && typeof p.available === 'boolean'
        && ['label', 'provider', 'providerLabel', 'adapter', 'model', 'effort'].every(k => typeof p[k] === 'string'))
      || !data.profiles.some(p => p.id === data.defaultProfile)) throw new Error('桥接版本不兼容，请保存进度并手动重启 westworld 服务。');
    if (data.worldVersion !== VERSION) throw new Error('桥接地图版本不兼容：共同的家已加入地图，请保存进度并手动重启 westworld 服务。');
    if (id !== connectionId) return;
    bridgeStatus = data;
    $('model-profile').innerHTML = '<option value="" disabled>逐居民自定义</option>' + data.profiles.map(p => `<option value="${esc(p.id)}">${esc(p.providerLabel)} · ${esc(p.label)} · ${esc(p.model)} / ${esc(p.effort)}${p.available ? '' : '（未配置凭据）'}</option>`).join('');
    $('model-profile').disabled = false;
    renderResidentModelConfig();
    renderBridgeProfile();
    updateConsent();
  } catch (error) {
    if (id === connectionId) $('bridge-status').textContent = `桥接不可用：${error.message}。请按下方命令启动。`;
  }
}
function renderBridgeProfile() {
  $('bridge-status').textContent = bridgeStatus
    ? `本机桥接就绪 · 剩余 ${bridgeStatus.remaining} 次 · ${draftReady() ? '居民配置完整' : '请为每位居民选择可用配置'}（尚未验证登录、模型权限与推理强度支持）`
    : '请选择本地服务提供的模型配置。';
}
function renderResidentModelConfig() {
  const profiles = bridgeStatus?.profiles || [];
  const selected = new Set(Object.values(draftProfiles));
  $('model-profile').value = selected.size === 1 ? [...selected][0] : '';
  const options = (values, chosen) => values.map(([value, label]) => `<option value="${esc(value)}" ${value === chosen ? 'selected' : ''}>${esc(label)}</option>`).join('');
  $('resident-model-config').innerHTML = world.agents.map(a => {
    const current = profileById(draftProfiles[a.id]);
    const providers = [...new Map(profiles.map(p => [p.provider, p.providerLabel])).entries()];
    const models = [...new Set(profiles.filter(p => p.provider === current?.provider).map(p => p.model))].map(id => [id, id]);
    const efforts = profiles.filter(p => p.provider === current?.provider && p.model === current?.model).map(p => [p.effort, `${p.effort}${p.available ? '' : '（未配置凭据）'}`]);
    return `<div class="resident-model-config"><strong>${residentPortrait(a.id, 'map')}${esc(a.name)}</strong>
      <label>Provider<select data-resident="${a.id}" data-setting="provider" aria-label="${esc(a.name)} Provider"><option value="" disabled ${current ? '' : 'selected'}>请选择</option>${options(providers, current?.provider)}</select></label>
      <label>Model<select data-resident="${a.id}" data-setting="model" aria-label="${esc(a.name)} Model">${options(models, current?.model)}</select></label>
      <label>推理强度<select data-resident="${a.id}" data-setting="effort" aria-label="${esc(a.name)} 推理强度">${options(efforts, current?.effort)}</select></label></div>`;
  }).join('');
}
function updateConsent() {
  $('model-enable').disabled = !draftReady() || bridgeStatus.remaining <= 0 || !$('model-consent').checked;
}
function bind() {
  $('drop-location').innerHTML = PLACES.map(p => `<option value="${p.id}">${p.name}</option>`).join('');
  $('weather-controls').addEventListener('click', event => {
    const id = event.target.closest('[data-weather]')?.dataset.weather;
    if (id && world.weather !== id) doIntervention({ type: 'weather', weather: id });
  });
  $('item-controls').addEventListener('click', event => {
    const id = event.target.closest('[data-item]')?.dataset.item;
    if (id) { selectedItem = id; renderControls(); }
  });
  $('world-map').addEventListener('click', event => {
    const resident = event.target.closest('[data-scene-agent]')?.dataset.sceneAgent;
    if (resident) {
      selectedAgent = resident; selectedPlace = world.agents.find(a => a.id === resident).location;
      $('whisper-agent').value = resident; renderResidents(); renderMap(); $('drop-location').value = selectedPlace; return;
    }
    const id = event.target.closest('[data-place]')?.dataset.place;
    if (id) { selectedPlace = id; renderMap(); $('drop-location').value = id; }
  });
  $('scene-zoom-in').addEventListener('click', () => zoomTown(Math.min(4, sceneZoom + .5)));
  $('scene-zoom-out').addEventListener('click', () => zoomTown(Math.max(1, sceneZoom - .5)));
  $('scene-fit').addEventListener('click', () => { town3d?.reset(); zoomTown(1); });
  $('scene-view').addEventListener('change', () => {
    const next = $('scene-view').value;
    if (!['2d', '3d'].includes(next) || next === '3d' && !town3d) { notify('这个浏览器无法使用所选视图。', true); return; }
    sceneView = next; townDrag = null; renderMap();
  });
  for (const [id, direction] of [['scene-rotate-left', -1], ['scene-rotate-right', 1]]) $(id).addEventListener('click', () => {
    town3d.setCamera(town3d.camera.yaw + direction * Math.PI / 8, town3d.camera.tilt); renderMap();
  });
  $('town-viewport').addEventListener('pointerdown', event => {
    if (event.button !== 0 || event.pointerType === 'touch' || event.target.closest('button')) return;
    const orbit = sceneView === '3d' && !event.shiftKey;
    if (!orbit && sceneZoom === 1) return;
    townDrag = { id: event.pointerId, x: event.clientX, y: event.clientY, left: $('town-viewport').scrollLeft, top: $('town-viewport').scrollTop,
      orbit, yaw: town3d?.camera.yaw, tilt: town3d?.camera.tilt };
    $('town-viewport').setPointerCapture(event.pointerId); event.preventDefault();
  });
  $('town-viewport').addEventListener('pointermove', event => {
    if (!townDrag || townDrag.id !== event.pointerId) return;
    if (townDrag.orbit) {
      town3d.setCamera(townDrag.yaw + (event.clientX - townDrag.x) * .008, townDrag.tilt + (event.clientY - townDrag.y) * .004);
      renderMap(); return;
    }
    $('town-viewport').scrollLeft = townDrag.left + townDrag.x - event.clientX;
    $('town-viewport').scrollTop = townDrag.top + townDrag.y - event.clientY;
  });
  for (const type of ['pointerup', 'pointercancel', 'lostpointercapture']) $('town-viewport').addEventListener(type, () => { townDrag = null; });
  motionPreference.addEventListener('change', renderMap);
  window.addEventListener('resize', renderMap);
  $('drop-location').addEventListener('change', () => { selectedPlace = $('drop-location').value; renderMap(); });
  $('drop').addEventListener('click', () => doIntervention({ type: 'drop', location: selectedPlace, item: selectedItem, amount: Number($('drop-amount').value) }));
  $('whisper-send').addEventListener('click', () => {
    const message = $('whisper').value.trim();
    if (!message) { notify('先写下一句低语。', true); $('whisper').focus(); return; }
    doIntervention({ type: 'whisper', agent: $('whisper-agent').value, message });
    $('whisper').value = '';
  });
  $('resident-list').addEventListener('click', event => {
    const id = event.target.closest('[data-agent]')?.dataset.agent;
    if (id) { selectedAgent = id; $('whisper-agent').value = id; renderResidents(); renderMap(); }
  });
  $('inspector-tabs').addEventListener('click', event => {
    const button = event.target.closest('[data-tab]');
    if (!button) return;
    inspectorTab = button.dataset.tab;
    for (const child of $('inspector-tabs').children) { child.classList.toggle('active', child === button); child.setAttribute('aria-pressed', String(child === button)); }
    renderResidents();
  });
  $('feed-tabs').addEventListener('click', event => {
    const button = event.target.closest('[data-filter]');
    if (!button) return;
    filter = button.dataset.filter;
    for (const child of $('feed-tabs').children) { child.classList.toggle('active', child === button); child.setAttribute('aria-pressed', String(child === button)); }
    renderFeed();
  });
  $('perspective').addEventListener('click', () => { residentView = !residentView; renderMap(); });
  $('play').addEventListener('click', togglePlay);
  $('step').addEventListener('click', () => { running = false; clearTimeout(timer); runRound(); });
  $('save').addEventListener('click', () => persist(true));
  $('restore').addEventListener('click', () => {
    pause();
    try {
      if (!load(SAVE_KEY)) { notify('尚无手动存档。点击“存档”创建一个实验检查点。'); return; }
      render();
      if (persist()) notify('手动存档已恢复，时间暂停。AI 需重新启用；继续旧模型实验时，请取消“重新开始”。');
    } catch (error) { notify(`存档读取失败：${error.message}。当前世界保持不变。`, true); }
  });
  $('import-open').addEventListener('click', () => {
    if (busy) { notify('居民正在行动，请先暂停再导入。', true); return; }
    pause();
    pendingImport = null; importGeneration++; $('import-file').value = '';
    $('import-confirm').disabled = true;
    $('import-preview').classList.remove('error');
    $('import-preview').textContent = '选择之前导出的 JSON 文件，查看将恢复的进度。';
    $('import-dialog').showModal();
  });
  $('import-file').addEventListener('change', previewImport);
  $('import-cancel').addEventListener('click', () => $('import-dialog').close());
  $('import-dialog').addEventListener('close', () => {
    pendingImport = null; importGeneration++; $('import-confirm').disabled = true;
  });
  $('import-confirm').addEventListener('click', () => {
    if (!pendingImport || busy) { notify('请先选择有效存档，并等待当前行动结束。', true); return; }
    pause();
    acceptRestoredWorld(pendingImport);
    $('import-dialog').close();
    render();
    if (persist()) notify('实验已导入，时间暂停，手动存档未覆盖。轮次与记忆已保留；继续 AI 实验需重新连接，并取消“重新开始”。');
  });
  $('export').addEventListener('click', () => {
    const blob = new Blob([JSON.stringify(exportRecord(world), null, 2)], { type: 'application/json' });
    const url = URL.createObjectURL(blob), anchor = document.createElement('a');
    anchor.href = url; anchor.download = `dusthaven-${world.scenario}-s${world.seed}-r${world.round}.json`;
    anchor.click(); setTimeout(() => URL.revokeObjectURL(url), 1000);
    notify('已导出世界、来源与观察—行动—结果记录。详细审计保留最近 200 次，事件保留最近 800 条。');
  });
  $('reset').addEventListener('click', () => requestReset(world.scenario));
  $('scenario-controls').addEventListener('click', event => {
    const id = event.target.closest('[data-scenario]')?.dataset.scenario;
    if (id) requestReset(id);
  });
  $('reset-cancel').addEventListener('click', () => $('reset-dialog').close());
  $('reset-confirm').addEventListener('click', () => {
    try {
      world = createWorld(Number($('seed-input').value), pendingScenario);
      mode = 'rule'; calls = 0; bridgeStatus = null; lastFeedKey = '';
      lastModelCall = null;
      $('reset-dialog').close(); $('notice').hidden = true; persist(); render();
    } catch (error) { $('seed-input').setCustomValidity(error.message); $('seed-input').reportValidity(); }
  });
  $('seed-input').addEventListener('input', () => $('seed-input').setCustomValidity(''));
  $('theme').addEventListener('click', () => {
    document.documentElement.setAttribute('data-theme', document.documentElement.getAttribute('data-theme') === 'dark' ? 'light' : 'dark');
    renderMap();
  });
  $('help').addEventListener('click', () => { pause(); $('help-dialog').showModal(); });
  $('model-open').addEventListener('click', () => {
    pause(); $('model-consent').checked = false;
    draftProfiles = { ...residentProfiles };
    $('fresh-model').checked = world.metrics.model === 0;
    $('model-dialog').showModal(); detectBridge();
  });
  $('model-consent').addEventListener('change', updateConsent);
  $('model-profile').addEventListener('change', () => {
    const id = $('model-profile').value;
    if (!profileById(id)) { notify('请选择本地服务提供的配置。', true); return; }
    draftProfiles = Object.fromEntries(world.agents.map(a => [a.id, id]));
    $('model-consent').checked = false;
    renderResidentModelConfig(); renderBridgeProfile(); updateConsent();
  });
  $('resident-model-config').addEventListener('change', event => {
    const select = event.target.closest('select[data-resident]');
    if (!select) return;
    const { resident, setting } = select.dataset;
    const current = profileById(draftProfiles[resident]);
    if (!bridgeStatus || !world.agents.some(a => a.id === resident) || !['provider', 'model', 'effort'].includes(setting)) {
      notify('居民配置无效，请重新打开连接面板。', true); return;
    }
    const candidates = bridgeStatus.profiles.filter(p => setting === 'provider' ? p.provider === select.value
      : setting === 'model' ? p.provider === current?.provider && p.model === select.value
        : p.provider === current?.provider && p.model === current?.model && p.effort === select.value);
    const next = candidates.find(p => p.effort === current?.effort) || candidates[0];
    if (!next) { notify('这组 Provider / Model / 推理强度不在服务端允许列表中。', true); return; }
    draftProfiles[resident] = next.id;
    $('model-consent').checked = false;
    renderResidentModelConfig(); renderBridgeProfile(); updateConsent();
  });
  $('demo-mode').addEventListener('click', () => {
    mode = 'rule'; bridgeStatus = null;
    log(world, 'system', '已明确选择规则演示', '接下来的行动由手写策略驱动；此前模型记忆如有则保留，记录将标明混合来源。');
    $('model-dialog').close(); notify('免费规则演示已启用。点击运行世界继续。'); persist(); render();
  });
  $('model-enable').addEventListener('click', () => {
    if (!draftReady() || !$('model-consent').checked) return;
    residentProfiles = { ...draftProfiles };
    if ($('fresh-model').checked) { world = createWorld(world.seed, world.scenario); lastFeedKey = ''; }
    mode = 'model'; calls = 0; allowance = Math.min(Number($('budget').value), bridgeStatus.remaining);
    lastModelCall = null;
    log(world, 'system', '真实 AI 已启用，等待运行', `${world.agents.map(a => {
      const p = activeProfile(a); return `${a.name}：${p.providerLabel} / ${p.model} / ${p.effort}`;
    }).join('；')}。本次连接最多 ${allowance} 次请求。每位居民独立感知、独立决策，不提供系统工具。`);
    $('model-dialog').close(); notify('真实 AI 已启用。点击“推进一轮”或“运行世界”开始调用；每位居民依次决策。'); persist(); render();
    try { localStorage.setItem(MODELS_KEY, JSON.stringify(residentProfiles)); }
    catch (error) { notify(`居民模型选择无法保存：${error.message}。当前连接仍可使用，刷新后需重新选择。`, true); }
  });
  document.addEventListener('keydown', event => {
    if (event.code === 'Space' && !event.repeat && !['INPUT', 'TEXTAREA', 'SELECT', 'BUTTON', 'SUMMARY'].includes(event.target.tagName) && !document.querySelector('dialog[open]')) {
      event.preventDefault(); togglePlay();
    }
  });
  document.addEventListener('visibilitychange', () => { if (document.hidden && (running || busy)) pause('页面进入后台，世界已暂停，避免无人观察时继续消耗额度。'); });
  window.addEventListener('pagehide', () => { pause(); persist(); });
}
try {
  if (load(AUTO_KEY)) notify('已恢复最近进度，世界暂停中。规则模式不会自动调用 AI；继续模型实验请重新连接。');
} catch (error) { notify(`自动进度无法读取，已打开新世界：${error.message}。旧存档尚未覆盖。`, true); }
try {
  const saved = localStorage.getItem(MODELS_KEY);
  if (saved) {
    const choices = JSON.parse(saved);
    if (!choices || Array.isArray(choices) || Object.keys(choices).length !== world.agents.length
      || !world.agents.every(a => typeof choices[a.id] === 'string' && choices[a.id].length <= 80)) throw new Error('配置格式无效');
    residentProfiles = choices;
  }
} catch (error) { notify(`居民模型选择无法读取：${error.message}。请在连接面板重新选择，不会自动调用模型。`, true); }
bind();
render();
if (!town3d) notify('当前浏览器不支持 WebGL 立体绘图，已切换为平面海岛；其他功能不受影响。', true);
