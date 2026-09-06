export const RADIUS = 23;
export const VISION = 8;
export const DAY_LENGTH = 150;
export const TYPES = Object.freeze({
  food: { name: '浆果丛', max: 18 },
  water: { name: '泉眼', max: 30 },
  tree: { name: '树木', max: 12 },
  stone: { name: '矿石', max: 12 },
  shelter: { name: '小屋', max: 1 },
  fire: { name: '篝火', max: 1 },
  artifact: { name: '未知物件', max: 1 },
});
export const ACTIONS = ['move', 'gather', 'eat', 'drink', 'rest', 'build', 'inspect', 'share', 'talk', 'wait'];
const NAMES = ['阿达', '米洛', '诺亚', '伊芙', '卢卡', '苏'];
const ROLES = ['好奇的探索者', '耐心的收集者', '热心的建造者', '乐于分享的邻居', '安静的观察者', '不安分的漫游者'];
const clamp = (n, min = 0, max = 100) => Math.max(min, Math.min(max, n));
export const distance = (a, b) => Math.hypot(a.x - b.x, a.z - b.z);
export const isLand = (x, z) => Number.isFinite(x) && Number.isFinite(z)
  && Math.hypot(x, z) < RADIUS
  && ((x + 7) / 4.8) ** 2 + ((z + 2) / 3.5) ** 2 > 1;
export const clock = t => {
  const hours = ((t / DAY_LENGTH * 24) + 7) % 24;
  return `DAY ${String(Math.floor(t / DAY_LENGTH) + 1).padStart(2, '0')} · ${String(Math.floor(hours)).padStart(2, '0')}:${String(Math.floor(hours % 1 * 60)).padStart(2, '0')}`;
};

function random(w) {
  w.rng = (Math.imul(w.rng, 1664525) + 1013904223) >>> 0;
  return w.rng / 4294967296;
}

function point(w, origin = { x: 0, z: 0 }, radius = RADIUS) {
  for (let i = 0; i < 150; i++) {
    const a = random(w) * Math.PI * 2;
    const r = Math.sqrt(random(w)) * radius;
    const p = { x: origin.x + Math.cos(a) * r, z: origin.z + Math.sin(a) * r };
    if (isLand(p.x, p.z)) return p;
  }
  return { x: 0, z: 0 };
}

function event(w, kind, text, agentId = null) {
  w.events.push({ id: w.nextEvent++, t: w.t, kind, text, agentId });
  if (w.events.length > 400) {
    w.events.shift();
    w.droppedEvents++;
  }
}

function remember(w, a, text, kind = 'experience') {
  a.memories.push({ t: w.t, text, kind });
  if (a.memories.length > 18) a.memories.shift();
}

function addEntity(w, type, x, z) {
  const entity = {
    id: `e${w.nextId++}`, type, x, z, amount: TYPES[type].max,
    effect: type === 'artifact' ? (random(w) > 0.5 ? 'nourish' : 'energize') : null,
  };
  w.entities.push(entity);
  return entity;
}

function addAgent(w, x, z) {
  const index = w.agents.length;
  const a = {
    id: `a${w.nextId++}`, name: NAMES[index] || `旅人 ${index + 1}`,
    role: ROLES[index % ROLES.length], color: index % 6, x, z,
    hunger: 68 + random(w) * 25, thirst: 64 + random(w) * 30,
    energy: 70 + random(w) * 25, health: 100,
    inventory: { food: 0, wood: 0, stone: 0 },
    memories: [], known: [], relationships: {}, action: null, path: [],
    nextDecision: w.t, lastSocial: -30, lastBuild: -60,
    goal: '观察周围', speech: '', speechUntil: 0, source: '规则', alive: true,
  };
  w.agents.push(a);
  remember(w, a, '来到这里。我还不了解这座岛。');
  return a;
}

export function createWorld(seed = 20260905) {
  const w = {
    version: 1, seed: seed >>> 0, rng: seed >>> 0, t: 0, nextId: 1, nextEvent: 1,
    weather: 'sun', entities: [], agents: [], events: [], droppedEvents: 0,
    interventions: [], stats: { discoveries: 0, shares: 0, built: 0, modelDecisions: 0 },
  };
  for (const [type, positions] of Object.entries({
    shelter: [[3, 2], [5, 4]],
    fire: [[0, 3]],
    water: [[-2, -2], [12, 8]],
    food: [[-1, 7], [7, -3], [-12, 7], [12, -9], [-4, -13]],
    stone: [[9, 5], [-8, 10], [-10, -10]],
    tree: [[-4, 8], [-6, 11], [-10, 13], [-14, 4], [-12, -7], [-8, -12], [2, -12], [6, -13], [13, -5], [15, 1], [11, 11], [5, 13]],
  })) {
    for (const [x, z] of positions) addEntity(w, type, x, z);
  }
  for (let i = 0; i < 6; i++) {
    const p = point(w, { x: 2, z: 3 }, 5);
    addAgent(w, p.x, p.z);
  }
  event(w, 'system', '小岛醒来了。六位居民开始各自的生活。');
  event(w, 'system', '当前为规则模拟；性格、互助和建造均有预设规则，不代表 AGI。');
  return w;
}

function perceive(w, a) {
  for (const e of w.entities) {
    if (distance(a, e) <= VISION && !a.known.includes(e.id)) {
      a.known.push(e.id);
      remember(w, a, `发现${TYPES[e.type].name}，位置 (${Math.round(e.x)}, ${Math.round(e.z)})。`, 'observation');
      if (e.type === 'artifact') event(w, 'discovery', `${a.name}发现了一个从未见过的物件。`, a.id);
    }
  }
}

export function observation(w, a) {
  // Never include world.entities, hidden artifact effects, other residents' memories, or global events.
  return {
    time: clock(w.t), weather: w.weather, visionRadius: VISION,
    self: {
      id: a.id, name: a.name, disposition: a.role, x: a.x, z: a.z,
      hunger: a.hunger, thirst: a.thirst, energy: a.energy, health: a.health,
      inventory: { ...a.inventory }, memories: a.memories.slice(-10),
    },
    nearby: w.entities.filter(e => distance(a, e) <= VISION).map(e => ({
      id: e.id, type: e.type, x: e.x, z: e.z, amount: Math.floor(e.amount),
    })),
    neighbors: w.agents.filter(b => b.id !== a.id && b.alive && distance(a, b) <= VISION).map(b => ({
      id: b.id, name: b.name, x: b.x, z: b.z, appearsHungry: b.hunger < 40,
      speech: b.speechUntil > w.t ? b.speech : '',
    })),
    knownPlaces: w.entities.filter(e => a.known.includes(e.id) && distance(a, e) > VISION).map(e => ({
      id: e.id, type: e.type, x: e.x, z: e.z,
    })),
    possibleDestinations: Array.from({ length: 8 }, (_, i) => ({
      x: Math.round(a.x + Math.cos(i * Math.PI / 4) * 6),
      z: Math.round(a.z + Math.sin(i * Math.PI / 4) * 6),
    })).filter(p => isLand(p.x, p.z)),
  };
}

export function intervene(w, type, x, z) {
  if (!isLand(x, z)) throw new Error('请投放在岛上的陆地，不要放在湖里或岛外。');
  if (type === 'resident') {
    if (w.agents.length >= 12) throw new Error('这个实验最多容纳 12 位居民。');
    addAgent(w, x, z);
  } else {
    if (!Object.hasOwn(TYPES, type)) throw new Error('未知的投放类型。');
    if (w.entities.length >= 160) throw new Error('物件已达 160 个上限，请开启新实验。');
    if (w.entities.some(e => distance(e, { x, z }) < 1.3)) throw new Error('这里已经有物件，请留一点空间。');
    addEntity(w, type, x, z);
  }
  w.interventions.push({ t: w.t, type, x, z });
  if (w.interventions.length > 500) w.interventions.shift();
  event(w, 'god', `你投放了${type === 'resident' ? '一位新居民' : TYPES[type].name}。居民尚需亲自发现。`);
}

export function setWeather(w, weather) {
  if (!['sun', 'rain', 'drought'].includes(weather)) throw new Error('未知天气。');
  if (w.weather === weather) return;
  w.weather = weather;
  w.interventions.push({ t: w.t, type: 'weather', weather });
  if (w.interventions.length > 500) w.interventions.shift();
  event(w, 'god', `你把天气改成了${{ sun: '晴天', rain: '细雨', drought: '干旱' }[weather]}。`);
  for (const a of w.agents.filter(a => a.alive)) remember(w, a, `天气变成了${weather === 'rain' ? '雨天' : weather === 'drought' ? '炎热干旱' : '晴天'}。`, 'observation');
}

function route(start, end) {
  const sx = Math.round(start.x), sz = Math.round(start.z);
  const ex = Math.round(end.x), ez = Math.round(end.z);
  const key = (x, z) => `${x},${z}`;
  const startKey = key(sx, sz), endKey = key(ex, ez);
  const queue = [{ x: sx, z: sz }];
  const seen = new Map([[startKey, null]]);
  for (let i = 0; i < queue.length; i++) {
    const p = queue[i];
    if (distance(p, end) < 1.25 || key(p.x, p.z) === endKey) {
      const path = [];
      let cursor = key(p.x, p.z);
      while (cursor !== startKey) {
        const [x, z] = cursor.split(',').map(Number);
        path.unshift({ x, z });
        cursor = seen.get(cursor);
      }
      if (isLand(end.x, end.z)) path.push({ x: end.x, z: end.z });
      return path;
    }
    for (const [dx, dz] of [[1, 0], [0, 1], [-1, 0], [0, -1]]) {
      const x = p.x + dx, z = p.z + dz, k = key(x, z);
      if (!seen.has(k) && isLand(x, z)) {
        seen.set(k, key(p.x, p.z));
        queue.push({ x, z });
      }
    }
  }
  throw new Error('无法找到通往目标的陆地路径。');
}

export function setAction(w, a, decision, source = '规则') {
  if (!a?.alive) throw new Error('这位居民已经无法行动。');
  if (!decision || !ACTIONS.includes(decision.action)) throw new Error('模型返回了不支持的行动。');
  const act = { type: decision.action, target: null, duration: 0, speech: '', x: a.x, z: a.z };
  const needsTarget = ['gather', 'drink', 'inspect', 'share', 'talk'].includes(act.type);
  const suppliedTarget = decision.target != null && decision.target !== '';
  let target;
  if (needsTarget || suppliedTarget) {
    target = w.entities.find(e => e.id === decision.target) || w.agents.find(b => b.id === decision.target && b.alive && b.id !== a.id);
    if (!target || (distance(a, target) > VISION && !a.known.includes(target.id))) throw new Error('行动目标不在居民的视野或记忆中。');
    if (act.type === 'gather' && !['food', 'tree', 'stone'].includes(target.type)) throw new Error('这里没有可采集的物资。');
    if (act.type === 'drink' && target.type !== 'water') throw new Error('这里不是水源。');
    if (act.type === 'inspect' && target.type !== 'artifact') throw new Error('这个物件不支持实验。');
    if (['share', 'talk'].includes(act.type) && !w.agents.includes(target)) throw new Error('交互对象必须是附近的居民。');
    if (act.type === 'rest' && !['shelter', 'fire'].includes(target.type)) throw new Error('只能在小屋、篝火旁或原地休息。');
    if (['eat', 'build', 'wait'].includes(act.type)) throw new Error('这项行动不需要目标。');
    act.target = target.id;
    act.x = target.x;
    act.z = target.z;
  }
  if (act.type === 'move' && !suppliedTarget) {
    if (!isLand(decision.x, decision.z) || distance(a, decision) > VISION + 0.1) throw new Error('一次只能移动到视野半径内的陆地。');
    act.x = decision.x;
    act.z = decision.z;
  }
  if (act.type === 'eat' && a.inventory.food < 1) throw new Error('背包里没有食物。');
  if (act.type === 'share' && a.inventory.food < 1) throw new Error('没有食物可以分享。');
  if (act.type === 'build' && (a.inventory.wood < 3 || a.inventory.stone < 2)) throw new Error('建造需要 3 木材和 2 石料。');
  if (act.type === 'build' && (w.entities.length >= 160 || w.entities.some(e => distance(e, a) < 1.6))) throw new Error('这里没有足够的建造空间。');
  const path = distance(a, act) > 1.3 ? route(a, act) : [];
  act.speech = typeof decision.say === 'string' ? decision.say.slice(0, 100) : '';
  a.action = act;
  a.path = path;
  a.goal = typeof decision.intent === 'string' && decision.intent.trim()
    ? decision.intent.slice(0, 90)
    : { move: '探索周围', gather: '收集物资', eat: '吃点东西', drink: '寻找水源', rest: '休息一会', build: '建造小屋', inspect: '尝试未知物件', share: '分享食物', talk: '与邻居交谈', wait: '观察变化' }[act.type];
  a.source = source;
  a.nextDecision = w.t + 7;
  if (source === 'Astra') {
    w.stats.modelDecisions++;
    event(w, 'model', `${a.name} · ${a.goal}`, a.id);
  }
}

function choose(w, a) {
  const known = w.entities.filter(e => a.known.includes(e.id));
  const nearest = (type, usable = false) => known.filter(e => e.type === type && (!usable || e.amount >= 1))
    .sort((x, y) => distance(a, x) - distance(a, y))[0];
  const water = nearest('water', true), food = nearest('food', true);
  if (a.thirst < 65 && water) return { action: 'drink', target: water.id };
  if (a.hunger < 70 && a.inventory.food) return { action: 'eat' };
  if (a.hunger < 60 && food) return { action: 'gather', target: food.id };
  if (a.energy < 42) {
    const shelter = nearest('shelter') || nearest('fire');
    return { action: 'rest', target: shelter?.id };
  }
  const neighbor = w.agents.find(b => b.alive && b.id !== a.id && distance(a, b) < 5 && b.hunger < 45);
  if (neighbor && a.inventory.food > 1) return { action: 'share', target: neighbor.id };
  const artifact = known.find(e => e.type === 'artifact' && !a.memories.some(m => m.kind === e.id));
  if (artifact) return { action: 'inspect', target: artifact.id };
  if (a.inventory.wood >= 3 && a.inventory.stone >= 2 && w.t - a.lastBuild > 60 && w.entities.length < 160
    && !w.entities.some(e => distance(a, e) < 2.4)) return { action: 'build' };
  if (a.inventory.food < 3 && food) return { action: 'gather', target: food.id };
  const tree = nearest('tree', true), stone = nearest('stone', true);
  if (a.color % 3 !== 0 && a.inventory.wood < 3 && tree) return { action: 'gather', target: tree.id };
  if (a.color % 3 !== 0 && a.inventory.stone < 2 && stone) return { action: 'gather', target: stone.id };
  const friend = w.agents.find(b => b.alive && b.id !== a.id && distance(a, b) < 4);
  if (friend && w.t - a.lastSocial > 28 && random(w) < 0.35) return { action: 'talk', target: friend.id, say: '我在附近发现了一些资源，告诉你它们的位置。' };
  const p = point(w, a, 6.5);
  return { action: 'move', ...p };
}

function finish(w, a) {
  const act = a.action;
  const target = w.entities.find(e => e.id === act.target) || w.agents.find(b => b.id === act.target && b.alive);
  const near = target && distance(a, target) < 2;
  let note = '';
  if (act.type === 'gather' && near && target.amount >= 1) {
    const item = { food: 'food', tree: 'wood', stone: 'stone' }[target.type];
    if (a.inventory[item] < 12) {
      target.amount -= 1;
      a.inventory[item]++;
      note = `采集了一份${{ food: '浆果', tree: '木材', stone: '石料' }[target.type]}。`;
    } else note = '背包中这种物资已经装满了。';
  } else if (act.type === 'eat' && a.inventory.food > 0) {
    a.inventory.food--;
    a.hunger = clamp(a.hunger + 32);
    note = '吃掉一份浆果，恢复了饱腹感。';
  } else if (act.type === 'drink' && near && target.amount >= 1) {
    target.amount -= 1;
    a.thirst = clamp(a.thirst + 46);
    note = '喝到了水。';
  } else if (act.type === 'rest') {
    a.energy = clamp(a.energy + (near ? 55 : 28));
    note = near ? '在遮蔽处休息，体力恢复了。' : '在露天休息了一会。';
  } else if (act.type === 'build') {
    if (w.entities.length < 160 && !w.entities.some(e => distance(a, e) < 1.6)) {
      a.inventory.wood -= 3;
      a.inventory.stone -= 2;
      addEntity(w, 'shelter', a.x, a.z);
      a.lastBuild = w.t;
      w.stats.built++;
      note = '用 3 木材和 2 石料建造了一间所有人都能使用的小屋。';
      event(w, 'build', `${a.name}建起了一间公共小屋。`, a.id);
    } else note = '建造失败：这里已经没有空地了。';
  } else if (act.type === 'inspect' && near) {
    if (target.effect === 'nourish') a.hunger = clamp(a.hunger + 25);
    else a.energy = clamp(a.energy + 35);
    note = target.effect === 'nourish' ? '触碰未知物件后，饥饿感减弱了。' : '触碰未知物件后，体力恢复了。';
    if (!a.memories.some(m => m.kind === target.id)) w.stats.discoveries++;
    event(w, 'discovery', `${a.name}：${note}`, a.id);
    remember(w, a, note, target.id);
  } else if (act.type === 'share' && near && a.inventory.food > 0 && target.inventory.food < 12) {
    a.inventory.food--;
    target.inventory.food++;
    a.relationships[target.id] = (a.relationships[target.id] || 0) + 1;
    target.relationships[a.id] = (target.relationships[a.id] || 0) + 1;
    w.stats.shares++;
    note = `给了${target.name}一份食物。`;
    remember(w, target, `${a.name}给了我一份食物。`, 'social');
    event(w, 'social', `${a.name}把食物分享给了${target.name}。`, a.id);
  } else if (act.type === 'talk' && near) {
    const fact = a.known.find(id => !target.known.includes(id));
    if (fact) {
      target.known.push(fact);
      const e = w.entities.find(e => e.id === fact);
      remember(w, target, `${a.name}告诉我：${TYPES[e.type].name}在 (${Math.round(e.x)}, ${Math.round(e.z)})。`, 'social');
    }
    a.lastSocial = w.t;
    a.relationships[target.id] = (a.relationships[target.id] || 0) + 1;
    a.speech = act.speech || '你好，邻居。';
    a.speechUntil = w.t + 7;
    note = `对${target.name}说：“${a.speech}”`;
    remember(w, target, `${a.name}对我说：“${a.speech}”`, 'social');
    event(w, 'social', `${a.name} → ${target.name}：${a.speech}`, a.id);
  } else if (['gather', 'drink', 'inspect', 'share', 'talk'].includes(act.type)) {
    note = '行动没有成功：目标已移动、资源不足或对方背包已满。';
  }
  if (note && act.type !== 'inspect') remember(w, a, note);
  a.action = null;
  a.path = [];
}

export function stepWorld(w, dt = 0.25, mode = 'demo') {
  if (!Number.isFinite(dt) || dt <= 0 || dt > 0.5) throw new Error('模拟步长必须在 0 到 0.5 秒之间。');
  if (!['demo', 'model'].includes(mode)) throw new Error('未知的决策模式。');
  w.t += dt;
  for (const e of w.entities) {
    const rate = e.type === 'food' ? 0.022 : e.type === 'water' ? 0.045 : e.type === 'tree' ? 0.006 : 0;
    const multiplier = w.weather === 'rain' ? 3 : w.weather === 'drought' ? 0 : 1;
    e.amount = Math.min(TYPES[e.type].max, e.amount + rate * multiplier * dt);
  }
  for (const a of w.agents.filter(a => a.alive)) {
    a.hunger = clamp(a.hunger - dt * 0.19);
    a.thirst = clamp(a.thirst - dt * (w.weather === 'drought' ? 0.56 : 0.25));
    a.energy = clamp(a.energy - dt * (a.path.length ? 0.28 : 0.10));
    a.health = clamp(a.health + dt * (a.hunger < 1 || a.thirst < 1 ? -0.75 : a.hunger > 40 && a.thirst > 40 ? 0.14 : 0));
    if (a.health <= 0) {
      a.alive = false;
      a.action = null;
      a.path = [];
      a.goal = '生命结束';
      event(w, 'loss', `${a.name}因长期缺乏基本资源而离开了这个世界。`, a.id);
      continue;
    }
    perceive(w, a);
    if (!a.action && mode === 'demo' && w.t >= a.nextDecision) setAction(w, a, choose(w, a));
    if (!a.action) continue;
    if (a.path.length) {
      const p = a.path[0], d = distance(a, p), amount = dt * 1.8;
      if (d <= amount) {
        a.x = p.x;
        a.z = p.z;
        a.path.shift();
      } else {
        a.x += (p.x - a.x) / d * amount;
        a.z += (p.z - a.z) / d * amount;
      }
    } else {
      a.action.duration += dt;
      const duration = a.action.type === 'rest' ? 6 : a.action.type === 'build' ? 5 : 2;
      if (a.action.duration >= duration) finish(w, a);
    }
  }
}

export function restoreWorld(raw) {
  const w = typeof raw === 'string' ? JSON.parse(raw) : structuredClone(raw);
  const finite = n => typeof n === 'number' && Number.isFinite(n);
  const nonnegative = n => finite(n) && n >= 0;
  const text = (s, max) => typeof s === 'string' && s.length <= max;
  const list = (v, max) => Array.isArray(v) && v.length <= max;
  if (!w || w.version !== 1 || !nonnegative(w.t) || !Number.isInteger(w.seed) || !Number.isInteger(w.rng)
    || !Number.isInteger(w.nextId) || !Number.isInteger(w.nextEvent)
    || !nonnegative(w.droppedEvents) || !['sun', 'rain', 'drought'].includes(w.weather)
    || !list(w.entities, 160) || !list(w.agents, 12) || !w.agents.length
    || !list(w.events, 400) || !list(w.interventions, 500)
    || !w.stats || !['discoveries', 'shares', 'built', 'modelDecisions'].every(k => nonnegative(w.stats[k]))) throw new Error('存档格式不受支持或数据已损坏。');
  const ids = new Set();
  for (const e of w.entities) {
    if (!text(e.id, 20) || !/^e\d+$/.test(e.id) || ids.has(e.id) || !Object.hasOwn(TYPES, e.type)
      || !isLand(e.x, e.z) || !nonnegative(e.amount) || e.amount > TYPES[e.type].max
      || !(e.effect === null || ['nourish', 'energize'].includes(e.effect))) throw new Error('存档物件数据无效。');
    ids.add(e.id);
  }
  for (const a of w.agents) {
    if (!text(a.id, 20) || !/^a\d+$/.test(a.id) || ids.has(a.id) || !text(a.name, 40) || !text(a.role, 80)
      || !Number.isInteger(a.color) || a.color < 0 || a.color > 5 || !isLand(a.x, a.z)
      || !['hunger', 'thirst', 'energy', 'health'].every(k => nonnegative(a[k]) && a[k] <= 100)
      || !a.inventory || !['food', 'wood', 'stone'].every(k => Number.isInteger(a.inventory[k]) && a.inventory[k] >= 0 && a.inventory[k] <= 12)
      || !list(a.memories, 18) || !a.memories.every(m => nonnegative(m.t) && text(m.text, 400) && text(m.kind, 40))
      || !list(a.known, 160) || !a.known.every(id => ids.has(id) && id.startsWith('e'))
      || !a.relationships || !Object.entries(a.relationships).every(([id, value]) => /^a\d+$/.test(id) && nonnegative(value))
      || !finite(a.nextDecision) || !finite(a.lastSocial) || !finite(a.lastBuild) || !text(a.goal, 100)
      || !text(a.speech, 100) || !nonnegative(a.speechUntil) || !['规则', 'Astra'].includes(a.source)
      || typeof a.alive !== 'boolean' || !list(a.path, 2400) || !a.path.every(p => isLand(p.x, p.z))
      || (a.action !== null && (!ACTIONS.includes(a.action.type) || !nonnegative(a.action.duration)
        || !isLand(a.action.x, a.action.z) || !(a.action.target === null || text(a.action.target, 20))
        || !text(a.action.speech, 100)))) throw new Error('存档居民数据无效。');
    ids.add(a.id);
  }
  if (w.nextId <= Math.max(...[...ids].map(id => Number(id.slice(1))))
    || !w.events.every(e => Number.isInteger(e.id) && nonnegative(e.t) && text(e.kind, 40) && text(e.text, 400))
    || !w.interventions.every(e => nonnegative(e.t) && text(e.type, 40))) throw new Error('存档日志数据无效。');
  return w;
}
