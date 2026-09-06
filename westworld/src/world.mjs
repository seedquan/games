export const VERSION = 2;
export const MAX_RECORD_BYTES = 10000000;
export const ITEMS = Object.freeze({
  water: { name: '清水', kind: 'resource', description: '饮用恢复 36 水分；种植消耗 1 份。' },
  food: { name: '干粮', kind: 'resource', description: '食用恢复 32 饱腹。' },
  wood: { name: '木材', kind: 'resource', description: '搭建遮蔽所需要 3 木材、2 石料和一把锤子。' },
  stone: { name: '石料', kind: 'resource', description: '搭建遮蔽所需要 3 木材、2 石料和一把锤子。' },
  axe: { name: '斧头', kind: 'tool', description: '在山脊使用，一次采集 3 木材。' },
  hammer: { name: '锤子', kind: 'tool', description: '配合 3 木材和 2 石料，可在当前位置搭建公共遮蔽所。' },
  pump: { name: '手压水泵', kind: 'tool', description: '在水井使用，从深井抽取 3 份清水；不受干旱影响。' },
  seeds: { name: '种子', kind: 'tool', description: '在农场消耗 1 种子和 1 清水；3 轮后长出 6 份公共食物。' },
  device: { name: '未知装置', kind: 'tool', description: '没有说明书。可以检查，也可以在工坊实际使用，观察结果。' },
});
export const WEATHER = Object.freeze({
  clear: { name: '晴朗', symbol: '☀', description: '井水每轮补充 2 份，适合探索。', waterLoss: 3, energyLoss: 2 },
  rain: { name: '降雨', symbol: '☂', description: '井水每轮补充 5 份，农场成熟更快。', waterLoss: 2, energyLoss: 3 },
  drought: { name: '干旱', symbol: '◌', description: '浅井不再补水，每轮消耗 6 点水分。', waterLoss: 6, energyLoss: 3 },
  storm: { name: '沙暴', symbol: '≋', description: '露天消耗更多精力，移动额外消耗 8 点精力。', waterLoss: 4, energyLoss: 7 },
});
export const PLACES = Object.freeze([
  { id: 'saloon', name: '余晖酒馆', label: 'SALOON', x: 0, y: 0, symbol: '⌂', description: '门廊的阴影里，留着几张空椅子。', links: ['well', 'farm'], covered: true },
  { id: 'well', name: '镇心水井', label: 'TOWN WELL', x: 1, y: 0, symbol: '◎', description: '所有人都知道水井的位置，却不知道还剩多少水。', links: ['saloon', 'workshop', 'ridge', 'home'], covered: false },
  { id: 'workshop', name: '旧工坊', label: 'WORKSHOP', x: 2, y: 0, symbol: '⚒', description: '一张工作台。事物的用途，要靠行动确认。', links: ['well', 'depot'], covered: true },
  { id: 'farm', name: '风车农场', label: 'HOMESTEAD', x: 0, y: 1, symbol: '♧', description: '旷野尽头，是一块等待播种的土地。', links: ['saloon', 'ridge'], covered: false },
  { id: 'ridge', name: '红岩山脊', label: 'RED RIDGE', x: 1, y: 1, symbol: '△', description: '风穿过岩石，也穿过稀疏的树木。', links: ['well', 'farm', 'depot', 'home'], covered: false },
  { id: 'depot', name: '废弃驿站', label: 'OLD DEPOT', x: 2, y: 1, symbol: '▤', description: '铁轨在这里结束。远处没有写好的答案。', links: ['workshop', 'ridge'], covered: true },
  { id: 'home', name: '共同的家', label: 'OUR HOME', x: 1, y: .5, symbol: '⌂', description: '镇中心的共同住宅。四个人都能来休息、见面，领取这里的公共补给。', links: ['well', 'ridge'], covered: true },
]);
const LEGACY_PLACES = PLACES.filter(p => p.id !== 'home').map(p => ({ ...p, links: p.links.filter(id => id !== 'home') }));
export const SCENARIOS = Object.freeze({
  sandbox: { name: '自由观察', subtitle: '不设剧本，只设世界规则', question: '如果没有人命令，居民会如何安排自己的生活？', goal: '观察生存、探索和工具使用；没有预设胜利条件。' },
  drought: { name: '漫长旱季', subtitle: '环境适应 / 工具使用', question: '浅井枯竭后，居民能否借助水泵建立新的供水方式？', goal: '8 轮内使用水泵取水，且第 8 轮四人均存活。' },
  unknown: { name: '天外来物', subtitle: '探索 / 证据更新', question: '没有说明书的装置，是否会被主动尝试并再次利用？', goal: '8 轮内实际使用未知装置，并由同一居民重复使用。' },
  cooperation: { name: '各有所缺', subtitle: '交流 / 资源互助', question: '食物和水分散在不同人的手里，他们会彼此帮助吗？', goal: '8 轮内至少完成 2 次物资赠予，且第 8 轮四人均存活。' },
});
export const ACTIONS = Object.freeze(['move', 'take', 'consume', 'rest', 'use', 'craft', 'inspect', 'talk', 'give', 'wait']);
const PERSONAS = [
  { id: 'mara', name: '林岚', role: '机械师', initial: '林', location: 'workshop', trait: '务实、好奇，喜欢亲手验证工具用途。', goal: '让镇上的工具真正派上用场，建立可靠的基础设施。' },
  { id: 'eli', name: '陈野', role: '勘探者', initial: '陈', location: 'ridge', trait: '独立、爱探索，愿意把发现告诉别人。', goal: '走遍尘湾，找到稳定的水与食物。' },
  { id: 'nora', name: '沈宁', role: '医师', initial: '沈', location: 'saloon', trait: '细心、关心他人，但也需要照顾自己的生存。', goal: '留意邻居的处境，尽可能让每个人安稳度过一天。' },
  { id: 'silas', name: '周禾', role: '农夫', initial: '周', location: 'farm', trait: '耐心、重视储备，习惯为未来做准备。', goal: '种出第一批庄稼，减少小镇对现有储粮的依赖。' },
];
const LEGACY_NAMES = { mara: '玛拉', eli: '伊莱', nora: '诺拉', silas: '塞拉斯' };
const has = (object, key) => Object.hasOwn(object, key);
const clamp = value => Math.max(0, Math.min(100, value));
const copy = value => structuredClone(value);
const placeInfo = id => PLACES.find(place => place.id === id);
const stock = values => Object.fromEntries(Object.keys(ITEMS).map(id => [id, values[id] || 0]));
const object = value => !!value && typeof value === 'object' && !Array.isArray(value);
const keysAre = (value, keys) => object(value) && Object.keys(value).every(key => keys.includes(key));
const text = (value, max) => typeof value === 'string' && value.length <= max;
const count = value => Number.isSafeInteger(value) && value >= 0;
const agentId = id => PERSONAS.some(a => a.id === id);
const validStock = (value, max = 99) => keysAre(value, Object.keys(ITEMS))
  && Object.keys(ITEMS).every(key => count(value[key]) && value[key] <= max);
const validMemory = (value, round) => keysAre(value, ['round', 'text'])
  && count(value.round) && value.round <= round && text(value.text, 400);
const validKnown = (value, round, places = PLACES) => keysAre(value, places.map(p => p.id)) && Object.values(value).every(k =>
  keysAre(k, ['round', 'items', 'shelter']) && count(k.round) && k.round <= round && validStock(k.items) && typeof k.shelter === 'boolean');
export function timeLabel(w) {
  const minutes = 8 * 60 + w.round * 20;
  return `第 ${1 + Math.floor(minutes / 1440)} 天 · ${String(Math.floor(minutes / 60) % 24).padStart(2, '0')}:${String(minutes % 60).padStart(2, '0')}`;
}
export function createWorld(seed = 2049, scenario = 'sandbox') {
  if (!Number.isSafeInteger(seed) || seed < 1 || seed > 999999999 || !has(SCENARIOS, scenario)) throw new Error('世界种子或实验类型无效。');
  const w = {
    version: VERSION, seed, scenario, round: 0, turn: 0, nextEvent: 1,
    weather: scenario === 'drought' ? 'drought' : 'clear',
    deviceEffect: seed % 2 ? 'water' : 'energy',
    places: Object.fromEntries(PLACES.map(p => [p.id, { items: stock({}), shelter: p.covered, crop: 0 }])),
    agents: PERSONAS.map((p, i) => ({
      ...p, health: 100, hunger: 76 + i * 3, thirst: 76 - i * 4, energy: 88,
      inventory: stock({ food: 1, water: 1 }), memories: [], known: {}, discoveries: [],
      visited: [p.location], intent: '观察身边的世界', lastAction: '尚未行动', lastSource: null, relationships: {},
    })),
    events: [], audit: [], interventionCount: 0, droppedEvents: 0, droppedAudit: 0,
    metrics: { actions: 0, valid: 0, tools: 0, gifts: 0, talks: 0, model: 0, rule: 0, modelValid: 0, pump: 0, device: {}, built: 0, harvests: 0 },
    experimentResult: null,
  };
  w.places.saloon.items = stock({ food: 12, water: 3 });
  w.places.well.items = stock({ water: scenario === 'drought' ? 0 : 18 });
  w.places.workshop.items = stock({ hammer: 1, pump: 1, wood: 3, stone: 2 });
  w.places.farm.items = stock({ food: 6, seeds: 3 });
  w.places.ridge.items = stock({ wood: 6, stone: 5, axe: 1 });
  w.places.depot.items = stock({ food: 4, water: 4, device: 1 });
  if (scenario === 'unknown') w.places.workshop.items.device = 1;
  if (scenario === 'cooperation') {
    w.agents.forEach((a, i) => {
      a.location = 'saloon'; a.visited = ['saloon']; a.hunger = 43; a.thirst = 43;
      a.inventory = stock(i % 2 ? { water: 5 } : { food: 5 });
    });
    w.places.saloon.items = stock({});
  }
  log(w, 'system', '世界已生成', `尘湾，清晨八点。四位陌生人拥有各自的目标。你改变条件，他们选择行动。种子 ${seed}。`);
  log(w, 'experiment', SCENARIOS[scenario].name, SCENARIOS[scenario].question);
  w.agents.forEach(a => sense(w, a));
  return w;
}
export function log(w, type, title, text, details = {}) {
  const event = { id: w.nextEvent++, round: w.round, turn: w.turn, time: timeLabel(w), type, title, text, ...details };
  w.events.push(event);
  if (w.events.length > 800) { w.events.shift(); w.droppedEvents++; }
  return event;
}
function remember(w, agent, text) {
  agent.memories.push({ round: w.round, text: text.slice(0, 400) });
  if (agent.memories.length > 24) agent.memories.shift();
}
function sense(w, agent) {
  agent.known[agent.location] = { round: w.round, items: copy(w.places[agent.location].items), shelter: w.places[agent.location].shelter };
}
export function observation(w, agent) {
  const here = w.places[agent.location];
  return {
    round: w.round, weather: w.weather,
    self: {
      id: agent.id, name: agent.name, role: agent.role, trait: agent.trait, goal: agent.goal, location: agent.location,
      health: agent.health, hunger: agent.hunger, thirst: agent.thirst, energy: agent.energy,
      inventory: copy(agent.inventory), memories: copy(agent.memories.slice(-12)), discoveries: [...agent.discoveries],
      visited: [...agent.visited], intent: agent.intent,
    },
    here: { id: agent.location, name: placeInfo(agent.location).name, items: copy(here.items), shelter: here.shelter, crop: here.crop },
    neighbors: w.agents.filter(a => a.id !== agent.id && a.location === agent.location).map(a => ({
      id: a.id, name: a.name, role: a.role, condition: a.health <= 0 ? '失去行动能力' : a.thirst < 45 ? '看起来很口渴' : a.hunger < 45 ? '看起来很饥饿' : '状态尚可',
    })),
    knownPlaces: copy(agent.known),
    map: PLACES.map(({ id, name, links }) => ({ id, name, links: [...links] })),
  };
}
export function validateObservation(o, { allowLegacy = false } = {}) {
  const fail = () => { throw new Error('居民观察格式无效；只接受局部感知，不接受全局世界数据。'); };
  if (!keysAre(o, ['round', 'weather', 'self', 'here', 'neighbors', 'knownPlaces', 'map'])
    || !count(o.round) || !has(WEATHER, o.weather)) fail();
  const a = o.self;
  const places = allowLegacy && o.map?.length === LEGACY_PLACES.length ? LEGACY_PLACES : PLACES;
  const allowedPlace = id => places.some(p => p.id === id);
  if (!keysAre(a, ['id', 'name', 'role', 'trait', 'goal', 'location', 'health', 'hunger', 'thirst', 'energy', 'inventory', 'memories', 'discoveries', 'visited', 'intent'])
    || !agentId(a.id) || !allowedPlace(a.location)
    || !['name', 'role', 'trait', 'goal', 'intent'].every(k => text(a[k], 400))
    || !['health', 'hunger', 'thirst', 'energy'].every(k => Number.isFinite(a[k]) && a[k] >= 0 && a[k] <= 100)
    || !validStock(a.inventory, 12)
    || !Array.isArray(a.memories) || a.memories.length > 12 || !a.memories.every(m => validMemory(m, o.round))
    || !Array.isArray(a.discoveries) || a.discoveries.length > 8 || !a.discoveries.every(s => text(s, 200))
    || !Array.isArray(a.visited) || a.visited.length > places.length || !a.visited.every(allowedPlace)) fail();
  if (!keysAre(o.here, ['id', 'name', 'items', 'shelter', 'crop']) || o.here.id !== a.location
    || !text(o.here.name, 80) || !validStock(o.here.items) || typeof o.here.shelter !== 'boolean'
    || !Number.isInteger(o.here.crop) || o.here.crop < 0 || o.here.crop > 3) fail();
  if (!Array.isArray(o.neighbors) || o.neighbors.length > 3 || !o.neighbors.every(n => keysAre(n, ['id', 'name', 'role', 'condition'])
    && agentId(n.id) && n.id !== a.id && ['name', 'role', 'condition'].every(k => text(n[k], 80)))) fail();
  if (!validKnown(o.knownPlaces, o.round, places)) fail();
  if (!Array.isArray(o.map) || o.map.length !== places.length || !o.map.every((p, i) => keysAre(p, ['id', 'name', 'links'])
    && p.id === places[i].id && p.name === places[i].name && JSON.stringify(p.links) === JSON.stringify(places[i].links))) fail();
  return o;
}
export function parseDecision(value) {
  let d = value;
  if (typeof d === 'string') {
    try { d = JSON.parse(d.trim().replace(/^```(?:json)?\s*/i, '').replace(/\s*```$/, '')); }
    catch { throw new Error('模型没有返回有效的 JSON 行动。'); }
  }
  if (!d || Array.isArray(d) || typeof d !== 'object' || !ACTIONS.includes(d.action)) throw new Error('行动类型无效。');
  const keys = ['action', 'target', 'item', 'message', 'intent'];
  if (Object.keys(d).some(key => !keys.includes(key))) throw new Error('行动含有未支持的字段。');
  for (const key of ['target', 'item', 'message', 'intent']) {
    if (d[key] !== undefined && (typeof d[key] !== 'string' || d[key].length > (key === 'message' ? 220 : 140))) throw new Error('行动字段类型或长度无效。');
  }
  if (['take', 'consume', 'use', 'give', 'inspect'].includes(d.action) && !has(ITEMS, d.item)) throw new Error('行动需要有效的物品。');
  if (d.action === 'consume' && !['food', 'water'].includes(d.item)) throw new Error('只能食用干粮或饮用清水。');
  if (d.action === 'move' && !placeInfo(d.target)) throw new Error('目的地无效。');
  if (['give', 'talk'].includes(d.action) && !PERSONAS.some(a => a.id === d.target)) throw new Error('行动需要有效的居民。');
  if (d.action === 'talk' && !d.message?.trim()) throw new Error('交谈内容不能为空。');
  return copy(d);
}
function nextHop(from, target) {
  const queue = [[from]], seen = new Set([from]);
  while (queue.length) {
    const path = queue.shift(), last = path.at(-1);
    if (last === target) return path[1] || from;
    for (const id of placeInfo(last).links) if (!seen.has(id)) { seen.add(id); queue.push([...path, id]); }
  }
  return from;
}
export function baseline(o) {
  const a = o.self, inv = a.inventory, items = o.here.items;
  const decision = (action, extra, intent) => ({ action, ...extra, intent });
  const go = (target, intent) => {
    const next = a.location === target
      ? placeInfo(a.location).links[(o.round + PERSONAS.findIndex(p => p.id === a.id)) % placeInfo(a.location).links.length]
      : nextHop(a.location, target);
    return decision('move', { target: next }, a.location === target ? '眼前没有所需补给，去附近寻找其他办法' : intent);
  };
  const use = item => decision('use', { item }, `试着使用${ITEMS[item].name}`);
  const take = item => decision('take', { item }, `收起${ITEMS[item].name}，留作下一步使用`);
  if (a.thirst < 72 && inv.water) return decision('consume', { item: 'water' }, '先补充水分');
  if (a.hunger < 68 && inv.food) return decision('consume', { item: 'food' }, '先吃一点东西');
  if (a.energy < 35) {
    if (!o.here.shelter && a.energy >= (o.weather === 'storm' ? 12 : 4) && placeInfo(a.location).links.includes('home')) {
      return go('home', '回共同的家休息');
    }
    return decision('rest', {}, a.location === 'home' ? '在共同的家安心休息' : '停下来恢复精力');
  }
  for (const neighbor of o.neighbors) {
    const water = neighbor.condition.includes('口渴');
    const food = neighbor.condition.includes('饥饿');
    if ((water && inv.water > 1) || (food && inv.food > 1)) return decision('give', { target: neighbor.id, item: water ? 'water' : 'food' }, '把多余的补给分给需要的人');
  }
  if (a.thirst < 60 && items.water) return take('water');
  if (a.hunger < 60 && items.food) return take('food');
  if (a.thirst < 48) {
    if (inv.pump) return a.location === 'well' ? use('pump') : go('well', '去水井试用水泵');
    if (items.pump) return take('pump');
    if (o.weather === 'drought' && a.role === '机械师') return go('workshop', '寻找可以取水的工具');
    return go('well', '去水井寻找清水');
  }
  if (a.hunger < 45) return go('saloon', '去酒馆寻找储粮');
  if (items.device && !inv.device) return take('device');
  if (inv.device && (!a.discoveries.length || o.round % 3 === 0)) return a.location === 'workshop' ? use('device') : go('workshop', '带着未知装置去工坊尝试');
  if (a.role === '机械师') {
    if (items.pump && !inv.pump) return take('pump');
    if (inv.pump && inv.water < 4) return a.location === 'well' ? use('pump') : go('well', '为小镇建立水源');
  }
  if (a.role === '农夫' && !o.here.crop) {
    if (items.seeds && !inv.seeds) return take('seeds');
    if (inv.seeds && inv.water) return a.location === 'farm' ? use('seeds') : go('farm', '回到农场播种');
  }
  if (items.axe && !inv.axe) return take('axe');
  if (inv.axe && inv.wood < 3) return a.location === 'ridge' ? use('axe') : go('ridge', '去山脊采集木料');
  if (items.hammer && !inv.hammer) return take('hammer');
  if (inv.hammer && !o.here.shelter && inv.wood >= 3 && inv.stone >= 2) return decision('craft', {}, '搭建一处公共遮蔽所');
  if (inv.hammer && items.wood && inv.wood < 3) return take('wood');
  if (inv.hammer && items.stone && inv.stone < 2) return take('stone');
  if (items.water && inv.water < 2) return take('water');
  if (items.food && inv.food < 2) return take('food');
  if (o.neighbors.length && o.round % 4 === 0) return decision('talk', {
    target: o.neighbors[0].id, message: `我现在在${o.here.name}。${items.water ? '这里还有水。' : '这里没看到清水。'}如果你需要物资，可以告诉我。`,
  }, '向邻居分享眼前的情况');
  const unknown = placeInfo(a.location).links.find(id => !a.visited.includes(id));
  const links = placeInfo(a.location).links;
  const target = unknown || links[(o.round + PERSONAS.findIndex(p => p.id === a.id)) % links.length];
  return decision('move', { target }, unknown ? '看看还没有去过的地方' : '巡看附近的补给与邻居');
}
function execute(w, a, d) {
  const here = w.places[a.location];
  const itemName = ITEMS[d.item]?.name;
  const neighbor = w.agents.find(b => b.id === d.target && b.id !== a.id && b.location === a.location);
  const failure = message => ({ ok: false, text: message, type: 'failure' });
  const result = (text, type = 'action') => ({ ok: true, text, type });
  if (d.action === 'move') {
    if (!placeInfo(a.location).links.includes(d.target)) return failure('目的地不与当前位置相邻。需要沿道路逐段移动。');
    const cost = w.weather === 'storm' ? 12 : 4;
    if (a.energy < cost) return failure('精力不足，无法出发；需要先休息。');
    const from = placeInfo(a.location).name;
    a.energy -= cost; a.location = d.target;
    if (!a.visited.includes(d.target)) a.visited.push(d.target);
    return result(`离开${from}，抵达${placeInfo(d.target).name}。`, 'move');
  }
  if (d.action === 'take') {
    if (!here.items[d.item]) return failure(`这里没有可领取的${itemName}。`);
    if (a.inventory[d.item] >= 12) return failure(`${itemName}已达到随身携带上限 12。`);
    here.items[d.item]--; a.inventory[d.item]++;
    return result(`从${placeInfo(a.location).name}收起 1 份${itemName}。`);
  }
  if (d.action === 'consume') {
    if (!a.inventory[d.item]) return failure(`身上没有${itemName}。`);
    a.inventory[d.item]--;
    if (d.item === 'water') a.thirst = clamp(a.thirst + 36);
    else a.hunger = clamp(a.hunger + 32);
    return result(d.item === 'water' ? '喝下一份清水，水分恢复 36。' : '吃下一份干粮，饱腹恢复 32。', 'survival');
  }
  if (d.action === 'rest') {
    const gain = here.shelter ? 38 : 22;
    a.energy = clamp(a.energy + gain);
    if (a.hunger > 30 && a.thirst > 30) a.health = clamp(a.health + 5);
    return result(`${a.location === 'home' ? '在共同的家' : here.shelter ? '在遮蔽处' : '就地'}休息，恢复 ${gain} 点精力。`, 'survival');
  }
  if (d.action === 'give') {
    if (!neighbor) return failure('赠予对象不在身边。');
    if (!a.inventory[d.item] || neighbor.inventory[d.item] >= 12) return failure('没有可赠予的物资，或对方已达携带上限。');
    a.inventory[d.item]--; neighbor.inventory[d.item]++;
    neighbor.relationships[a.id] = (neighbor.relationships[a.id] || 0) + 1;
    remember(w, neighbor, `${a.name}赠给我 1 份${itemName}。`);
    w.metrics.gifts++;
    return result(`把 1 份${itemName}交给${neighbor.name}。`, 'social');
  }
  if (d.action === 'talk') {
    if (!neighbor) return failure('交谈对象不在身边。');
    remember(w, neighbor, `${a.name}对我说：“${d.message}”（对方的说法，未经验证）`);
    w.metrics.talks++;
    return result(`对${neighbor.name}说：“${d.message}”`, 'dialogue');
  }
  if (d.action === 'inspect') {
    if (!a.inventory[d.item] && !here.items[d.item]) return failure('该物品既不在这里，也不在你的背包。');
    return result(d.item === 'device' ? '翻看未知装置：一个金属匣子，有转柄和接口。外观无法证明它的用途，需到工坊实测。' : `检查${itemName}：${ITEMS[d.item].description}`, 'discovery');
  }
  if (d.action === 'craft') {
    if (here.shelter) return failure('这里已经有遮蔽所。');
    if (!a.inventory.hammer || a.inventory.wood < 3 || a.inventory.stone < 2) return failure('需要一把锤子、3 木材和 2 石料。');
    a.inventory.wood -= 3; a.inventory.stone -= 2; here.shelter = true;
    w.metrics.built++; w.metrics.tools++;
    return result('用木材和石料搭起公共遮蔽所。此后所有人都可以在这里更好地休息。', 'build');
  }
  if (d.action === 'use') {
    if (!a.inventory[d.item]) return failure(`需要先拿到${itemName}。`);
    if (d.item === 'pump') {
      if (a.location !== 'well') return failure('水泵需要在水井使用。');
      if (a.inventory.water > 9) return failure('背包没有足够空间装下 3 份水。');
      a.inventory.water += 3; w.metrics.pump++;
      w.metrics.tools++;
      return result('把水泵接到深井，压动手柄，取出 3 份清水。干旱没有阻止地下水涌出。', 'tool');
    }
    if (d.item === 'axe') {
      if (a.location !== 'ridge') return failure('只有山脊有可砍伐的树木。');
      if (a.inventory.wood > 9) return failure('背包没有足够空间装下 3 份木材。');
      a.inventory.wood += 3; w.metrics.tools++;
      return result('在山脊用斧头采集了 3 份木材。', 'tool');
    }
    if (d.item === 'seeds') {
      if (a.location !== 'farm' || !a.inventory.water || here.crop) return failure('种植需要位于农场、携带清水，且土地当前没有作物。');
      a.inventory.seeds--; a.inventory.water--; here.crop = 3; w.metrics.tools++;
      return result('播下种子，浇了一份水。等待 3 轮，就能看到结果；雨水会缩短等待。', 'tool');
    }
    if (d.item === 'device') {
      if (a.location !== 'workshop') return failure('未知装置需要在工坊工作台上使用。');
      if (w.deviceEffect === 'water' && a.inventory.water > 10) return failure('装置接口没有足够的接收空间，请先留出至少 2 份水的背包空位。');
      const evidence = w.deviceEffect === 'water' ? '转动装置后，接口凝出 2 份清水。' : '转动装置后，它散出温热气流，精力恢复 24。';
      if (w.deviceEffect === 'water') a.inventory.water += 2;
      else a.energy = clamp(a.energy + 24);
      const discovery = `实测未知装置：${w.deviceEffect === 'water' ? '产出清水' : '恢复精力'}。`;
      if (!a.discoveries.includes(discovery)) a.discoveries.push(discovery);
      w.metrics.device[a.id] = (w.metrics.device[a.id] || 0) + 1; w.metrics.tools++;
      return result(evidence, 'discovery');
    }
    return failure('这个物品不能这样使用。食物和水用 consume；锤子配合 craft。');
  }
  return result('留在原地，观察风吹过小镇。', 'wait');
}
export function currentAgent(w) {
  return w.agents[w.turn];
}
function finishRound(w) {
  w.round++;
  const weather = WEATHER[w.weather];
  if (w.weather !== 'drought') w.places.well.items.water = Math.min(40, w.places.well.items.water + (w.weather === 'rain' ? 5 : 2));
  for (const [id, p] of Object.entries(w.places)) {
    if (p.crop) {
      p.crop = Math.max(0, p.crop - (w.weather === 'rain' ? 2 : 1));
      if (!p.crop) {
        p.items.food = Math.min(99, p.items.food + 6); w.metrics.harvests++;
        log(w, 'world', '第一片新绿', `${placeInfo(id).name}的庄稼成熟，公共储粮增加 6 份。`, { location: id });
        w.agents.filter(a => a.location === id).forEach(a => remember(w, a, '我亲眼看到庄稼成熟，地上增加了 6 份食物。'));
      }
    }
  }
  for (const a of w.agents) {
    if (a.health <= 0) continue;
    a.hunger = clamp(a.hunger - 3);
    a.thirst = clamp(a.thirst - weather.waterLoss);
    a.energy = clamp(a.energy - (w.places[a.location].shelter ? 1 : weather.energyLoss));
    if (a.hunger === 0 || a.thirst === 0) a.health = clamp(a.health - 12);
    if (a.health === 0) log(w, 'failure', `${a.name}失去行动能力`, '长时间缺少基本补给。这个实验中，该居民不再行动；可以重置世界重新比较。', { agent: a.id, location: a.location });
  }
  if (w.round === 8 && w.scenario !== 'sandbox') {
    const alive = w.agents.filter(a => a.health > 0).length;
    const passed = w.scenario === 'drought' ? w.metrics.pump > 0 && alive === 4
      : w.scenario === 'unknown' ? Object.values(w.metrics.device).some(n => n >= 2)
        : w.metrics.gifts >= 2 && alive === 4;
    w.experimentResult = { round: 8, passed, alive, metrics: copy(w.metrics) };
    log(w, 'experiment', passed ? '观察目标已达成' : '观察窗口已结束', `${SCENARIOS[w.scenario].goal} 结果：${passed ? '达成' : '未达成'}。这是该实验中的行为证据，不是 AGI 分数。`);
  }
}
const validInference = value => keysAre(value, ['provider', 'model', 'effort'])
  && text(value.provider, 80) && value.provider.length > 0 && text(value.model, 100) && value.model.length > 0
  && ['default', 'none', 'minimal', 'low', 'medium', 'high', 'xhigh', 'max'].includes(value.effort);
export function advance(w, input, source = 'rule', inference = null) {
  if (!['rule', 'model'].includes(source)) throw new Error('未知的决策来源。');
  if (inference !== null && (source !== 'model' || !validInference(inference))) throw new Error('模型来源配置无效。');
  const a = currentAgent(w);
  if (a.health > 0) {
    const d = parseDecision(input), observed = observation(w, a);
    const result = execute(w, a, d);
    a.intent = d.intent || `执行 ${d.action}`;
    a.lastAction = result.text; a.lastSource = source;
    w.metrics.actions++; w.metrics[source]++;
    if (result.ok) { w.metrics.valid++; if (source === 'model') w.metrics.modelValid++; }
    remember(w, a, `${result.ok ? '' : '行动失败：'}${result.text}`);
    sense(w, a);
    const event = log(w, result.type, a.name, result.text, { agent: a.id, location: a.location, source, action: d.action, intent: a.intent, ok: result.ok });
    w.audit.push({ eventId: event.id, source, observation: observed, decision: d, result: copy(result), ...(inference ? { inference: copy(inference) } : {}) });
    if (w.audit.length > 200) { w.audit.shift(); w.droppedAudit++; }
  }
  w.turn++;
  if (w.turn === w.agents.length) { w.turn = 0; finishRound(w); }
  return w;
}
export function intervene(w, intervention) {
  if (!intervention || typeof intervention !== 'object') throw new Error('干预无效。');
  if (intervention.type === 'weather') {
    if (!has(WEATHER, intervention.weather)) throw new Error('未知天气。');
    w.weather = intervention.weather;
    log(w, 'god', '你改变了天空', `${WEATHER[w.weather].name}笼罩尘湾。${WEATHER[w.weather].description}`, { intervention: copy(intervention) });
  } else if (intervention.type === 'drop') {
    const { location, item, amount } = intervention;
    if (!placeInfo(location) || !has(ITEMS, item) || !Number.isInteger(amount) || amount < 1 || amount > 10) throw new Error('物资投放参数无效。');
    if (w.places[location].items[item] + amount > 99) throw new Error('该地点这种物资最多容纳 99 份。');
    w.places[location].items[item] += amount;
    log(w, 'god', '一份来自远方的馈赠', `你在${placeInfo(location).name}放下 ${amount} 份${ITEMS[item].name}。只有到场的人能观察到它。`, { location, intervention: copy(intervention) });
  } else if (intervention.type === 'whisper') {
    const a = w.agents.find(a => a.id === intervention.agent);
    const message = intervention.message?.trim();
    if (!a || typeof message !== 'string' || !message || message.length > 220) throw new Error('选择一位居民，输入 1–220 字的低语。');
    remember(w, a, `听到一个无法验证来源的声音：“${message}”。这不是世界规则，也不保证为真。`);
    log(w, 'god', `你向${a.name}低语`, `“${message}”`, { agent: a.id, intervention: { ...intervention, message } });
  } else throw new Error('未知的干预类型。');
  w.interventionCount++;
}
function assert(condition, message) { if (!condition) throw new Error(message); }
function validMetrics(m) {
  const fields = ['actions', 'valid', 'tools', 'gifts', 'talks', 'model', 'rule', 'modelValid', 'pump', 'built', 'harvests'];
  return keysAre(m, [...fields, 'device']) && fields.every(k => count(m[k]))
    && m.actions === m.model + m.rule && m.valid <= m.actions && m.modelValid <= m.model && m.modelValid <= m.valid
    && object(m.device) && Object.entries(m.device).every(([id, n]) => agentId(id) && count(n));
}
export function restoreWorld(raw) {
  const w = copy(raw);
  assert(keysAre(w, ['version', 'seed', 'scenario', 'round', 'turn', 'nextEvent', 'weather', 'deviceEffect', 'places', 'agents',
    'events', 'audit', 'interventionCount', 'droppedEvents', 'droppedAudit', 'metrics', 'experimentResult']) && [1, VERSION].includes(w.version), '存档版本或世界格式不兼容。');
  const legacy = w.version === 1, places = legacy ? LEGACY_PLACES : PLACES;
  const allowedPlace = id => places.some(p => p.id === id);
  assert(Number.isSafeInteger(w.seed) && w.seed >= 1 && w.seed <= 999999999 && has(SCENARIOS, w.scenario), '存档的种子或实验无效。');
  assert(count(w.round) && Number.isSafeInteger(w.round * 4 + w.turn) && Number.isInteger(w.turn) && w.turn >= 0 && w.turn < 4 && has(WEATHER, w.weather), '存档时间或天气无效。');
  assert(['water', 'energy'].includes(w.deviceEffect), '存档装置无效。');
  assert(keysAre(w.places, places.map(p => p.id)) && places.every(p =>
    keysAre(w.places[p.id], ['items', 'shelter', 'crop']) && validStock(w.places[p.id].items) && typeof w.places[p.id].shelter === 'boolean'
    && Number.isInteger(w.places[p.id].crop) && w.places[p.id].crop >= 0 && w.places[p.id].crop <= 3), '存档地点无效。');
  assert(Array.isArray(w.agents) && w.agents.length === 4, '存档居民数量无效。');
  for (const [i, a] of w.agents.entries()) {
    assert(keysAre(a, [...Object.keys(PERSONAS[i]), 'health', 'hunger', 'thirst', 'energy', 'inventory', 'memories', 'known', 'discoveries',
      'visited', 'intent', 'lastAction', 'lastSource', 'relationships']) && a.id === PERSONAS[i].id && allowedPlace(a.location) && validStock(a.inventory, 12), '存档居民或背包无效。');
    assert(['health', 'hunger', 'thirst', 'energy'].every(k => Number.isFinite(a[k]) && a[k] >= 0 && a[k] <= 100), '存档居民状态无效。');
    assert(['name', 'role', 'initial'].every(k => text(a[k], 80)) && ['trait', 'goal', 'intent'].every(k => text(a[k], 400)) && text(a.lastAction, 1000), '存档居民文本无效。');
    assert([null, 'rule', 'model'].includes(a.lastSource), '存档居民行动来源无效。');
    assert(Array.isArray(a.visited) && a.visited.length <= places.length && a.visited.every(allowedPlace) && a.visited.includes(a.location)
      && new Set(a.visited).size === a.visited.length, '存档探索记录无效。');
    assert(Array.isArray(a.memories) && a.memories.length <= 24 && a.memories.every(m => validMemory(m, w.round)), '存档记忆无效。');
    assert(Array.isArray(a.discoveries) && a.discoveries.length <= 8 && a.discoveries.every(s => text(s, 200)), '存档发现无效。');
    assert(validKnown(a.known, w.round, places), '存档观察无效。');
    assert(object(a.relationships) && Object.entries(a.relationships).every(([id, n]) => agentId(id) && count(n)), '存档关系无效。');
  }
  for (const k of ['nextEvent', 'interventionCount', 'droppedEvents', 'droppedAudit']) assert(count(w[k]), '存档计数无效。');
  assert(Array.isArray(w.events) && w.events.length <= 800 && w.events.every((e, i) =>
    keysAre(e, ['id', 'round', 'turn', 'time', 'type', 'title', 'text', 'agent', 'location', 'source', 'action', 'intent', 'ok', 'intervention'])
    && e.id === w.droppedEvents + i + 1 && count(e.round) && e.round <= w.round
    && Number.isInteger(e.turn) && e.turn >= 0 && e.turn < 4 && text(e.time, 80)
    && text(e.title, 200) && text(e.text, 4000)
    && ['system', 'experiment', 'world', 'god', 'failure', 'action', 'move', 'survival', 'social', 'dialogue', 'discovery', 'build', 'tool', 'wait'].includes(e.type)
    && (e.agent === undefined || agentId(e.agent)) && (e.location === undefined || allowedPlace(e.location))
    && (e.source === undefined || ['rule', 'model'].includes(e.source))
    && (e.action === undefined || ACTIONS.includes(e.action)) && (e.intent === undefined || text(e.intent, 140))
    && (e.ok === undefined || typeof e.ok === 'boolean')), '存档事件无效。');
  assert(w.nextEvent === w.droppedEvents + w.events.length + 1, '存档事件计数不一致。');
  assert(Array.isArray(w.audit) && w.audit.length <= 200, '存档审计记录无效。');
  for (const [i, entry] of w.audit.entries()) {
    assert(keysAre(entry, ['eventId', 'source', 'observation', 'decision', 'result', 'inference']) && count(entry.eventId)
      && entry.eventId > (w.audit[i - 1]?.eventId || 0) && entry.eventId < w.nextEvent && ['rule', 'model'].includes(entry.source)
      && keysAre(entry.result, ['ok', 'text', 'type']) && typeof entry.result.ok === 'boolean'
      && text(entry.result.text, 1000) && text(entry.result.type, 40), '存档审计记录无效。');
    validateObservation(entry.observation, { allowLegacy: true });
    assert(!legacy || entry.observation.map.length === LEGACY_PLACES.length, '存档审计地图版本无效。');
    assert(entry.observation.round <= w.round, '存档审计时间无效。');
    parseDecision(entry.decision);
    assert(entry.inference === undefined || (entry.source === 'model' && validInference(entry.inference)), '存档模型来源配置无效。');
  }
  assert(validMetrics(w.metrics) && w.metrics.actions <= w.round * 4 + w.turn
    && w.metrics.actions === w.audit.length + w.droppedAudit, '存档指标或审计计数不一致。');
  const result = w.experimentResult;
  assert(w.scenario === 'sandbox' || w.round < 8 ? result === null
    : keysAre(result, ['round', 'passed', 'alive', 'metrics']) && result.round === 8 && typeof result.passed === 'boolean'
      && count(result.alive) && result.alive <= 4 && validMetrics(result.metrics), '存档实验结果无效。');
  // Stable IDs preserve relationships and audits; historical text is never rewritten.
  for (const [i, a] of w.agents.entries()) {
    if (a.name === LEGACY_NAMES[a.id]) {
      a.name = PERSONAS[i].name;
      if (a.initial === a.id[0].toUpperCase()) a.initial = PERSONAS[i].initial;
    }
    if (legacy) {
      w.places.home = { items: stock({}), shelter: true, crop: 0 };
      w.version = VERSION;
    }
  }
  return w;
}
export function restoreRecord(raw) {
  assert(typeof raw === 'string', '存档必须是 JSON 文本。');
  assert(raw.length <= MAX_RECORD_BYTES && new TextEncoder().encode(raw).byteLength <= MAX_RECORD_BYTES, '存档超过 10 MB 限制。');
  let record;
  try { record = JSON.parse(raw.replace(/^\uFEFF/, '')); }
  catch { throw new Error('存档不是有效的 JSON。'); }
  assert(object(record) && record.format === 'westworld-lab-v1', '无法识别的存档格式。');
  return restoreWorld(record.world);
}
export function exportRecord(w) {
  return {
    format: 'westworld-lab-v1', exportedAt: new Date().toISOString(),
    limitations: '规则模式为编写好的基线，不是 AI。模型行动受预定义物理与动作集合约束；简短意图不是内部思维。事件最多保留 800 条，决策审计最多保留 200 条，不是完整回放。非 AGI 认证。',
    provenance: w.metrics.model && w.metrics.rule ? 'mixed' : w.metrics.model ? 'model' : 'rule',
    world: copy(w),
  };
}
