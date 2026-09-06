import { ITEMS, PLACES } from './world.mjs';
import { TOWN_WIDTH, TOWN_HEIGHT, townPoint, townBackdrop, townRoadPoints } from './pixel-art.mjs';
import { islandPlanPoint } from './island-layout.mjs';

const townGround = townBackdrop(PLACES);
const townOffsets = { mara: [-23, 7], eli: [23, 7], nora: [-23, 37], silas: [23, 37] };
const courtyardOffsets = {
  home: { mara: [-55, 28], eli: [55, 28], nora: [-95, 75], silas: [95, 75] },
  well: { nora: [-50, 22], silas: [50, 22] },
};
const townPlace = id => {
  const place = PLACES.find(p => p.id === id);
  if (!place) throw new Error(`Unknown town place: ${id}`);
  return place;
};
export function townResidentPoint(resident) {
  const p = townPoint(townPlace(resident.location)), offset = courtyardOffsets[resident.location]?.[resident.id] || townOffsets[resident.id];
  if (!offset) throw new Error(`Unknown town resident: ${resident.id}`);
  return { x: p.x + offset[0], y: p.y + offset[1] };
}
export function residentPublicActivity(world, resident, viewerId = null) {
  const event = world.events.findLast(e => e.agent === resident.id && ['rule', 'model'].includes(e.source));
  if (!event || event.location !== resident.location) return null;
  const audit = world.audit.find(e => e.eventId === event.id);
  if (viewerId && viewerId !== resident.id
    && !audit?.observation.neighbors.some(n => n.id === viewerId)) return null;
  const decision = audit?.decision, item = ITEMS[decision?.item]?.name || '物资';
  const succeeded = event.ok === true;
  const labels = {
    move: `抵达${townPlace(resident.location).name}`, take: `领取${item}`,
    consume: decision?.item === 'water' ? '喝水' : decision?.item === 'food' ? '吃东西' : '补充饮食',
    rest: '休息', use: `使用${item}`, craft: '搭建遮蔽所', inspect: `查看${item}`,
    talk: '交谈', give: `赠送${item}`, wait: '等待',
  };
  return {
    label: succeeded ? labels[event.action] : '行动未成功', detail: event.text, source: event.source,
    speech: succeeded && event.action === 'talk' ? decision?.message || event.text : null,
  };
}
export function townBubbleLayout(residents, pixelWidth, project = islandPlanPoint) {
  if (!Number.isFinite(pixelWidth) || pixelWidth < 32) throw new Error('Invalid town caption width.');
  const compact = pixelWidth < 800, scale = pixelWidth / TOWN_WIDTH, groups = new Map(), layout = new Map();
  for (const a of residents) {
    const key = compact ? 'visible' : a.location;
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push({ id: a.id, x: project(townResidentPoint(a)).x * scale });
  }
  for (const group of groups.values()) {
    group.sort((a, b) => a.x - b.x || a.id.localeCompare(b.id));
    const width = Math.min(132, (pixelWidth - 12 - (group.length - 1) * 6) / group.length);
    const total = group.length * width + (group.length - 1) * 6;
    const center = group.reduce((n, a) => n + a.x, 0) / group.length;
    const left = Math.max(6, Math.min(pixelWidth - total - 6, center - total / 2));
    group.forEach((a, i) => layout.set(a.id, { width, compact, shift: left + i * (width + 6) + width / 2 - a.x }));
  }
  return layout;
}
export function projectTown(world, selectedId, localView) {
  const self = world.agents.find(a => a.id === selectedId);
  if (!self) throw new Error('Unknown town observer.');
  return {
    view: localView ? selectedId : 'observer', weather: world.weather,
    places: PLACES.map(p => {
      const visible = !localView || p.id === self.location, state = world.places[p.id];
      return { id: p.id, name: p.name, point: townPoint(p), visible,
        ...(visible ? { items: { ...state.items }, crop: state.crop, shelter: state.shelter } : {}) };
    }),
    residents: world.agents.filter(a => !localView || a.location === self.location)
      .map(a => ({ id: a.id, name: a.name, location: a.location, alive: a.health > 0,
        activity: residentPublicActivity(world, a, localView ? selectedId : null) })),
  };
}
export function townScenery(scene) {
  const crop = scene.places.find(p => p.id === 'farm');
  const farm = islandPlanPoint(crop.point);
  const seedlings = crop?.visible && crop.crop > 0
    ? `<g fill="var(--cp-success)" opacity=".65">${Array.from({ length: 12 }, (_, i) => `<ellipse cx="${farm.x - 23 + i%3*4}" cy="${farm.y+Math.floor(i/3)*4}" rx="1.4" ry="2"/>`).join('')}</g>` : '';
  const shelters = scene.places.filter(p => p.visible && p.shelter && !townPlace(p.id).covered).map(p => {
    const q=islandPlanPoint(p.point);
    return `<g transform="translate(${q.x+15} ${q.y-7})"><path fill="var(--cp-accent)" d="M0 2Q6-3 12 2V4H0Z"/><path stroke="var(--cp-text-muted)" stroke-width="1" d="M1 4V11M11 4V11"/></g>`;
  }).join('');
  const weather = ['rain', 'storm'].includes(scene.weather)
    ? `<g fill="var(--cp-${scene.weather === 'rain' ? 'link' : 'warning'})" opacity=".35">${Array.from({ length: 55 }, (_, i) =>
      `<path d="M${i * 83 % 480} ${i * 57 % 320}h1v5h-1z"/>`).join('')}</g>` : '';
  const fog = scene.places.filter(p => !p.visible).map(p => {
    const q=islandPlanPoint(p.point);
    return `<ellipse data-fog="${p.id}" cx="${q.x}" cy="${q.y-9}" rx="27" ry="25" fill="var(--cp-bg-elevated)" opacity=".7"/>`;
  }).join('');
  return `<svg class="town-scene" viewBox="0 0 ${TOWN_WIDTH} ${TOWN_HEIGHT}" shape-rendering="geometricPrecision" aria-hidden="true" focusable="false">${townGround}${seedlings}${shelters}${weather}${fog}</svg>`;
}

const townDistance = (a, b) => Math.hypot(b.x - a.x, b.y - a.y);
const townPathLength = points => points.slice(1).reduce((sum, p, i) => sum + townDistance(points[i], p), 0);
export function sampleTownMotion(motion, now) {
  const elapsed = Math.max(0, Math.min(1, (now - motion.startedAt) / motion.duration));
  let remaining = townPathLength(motion.points) * elapsed;
  for (let i = 1; i < motion.points.length; i++) {
    const from = motion.points[i - 1], to = motion.points[i], length = townDistance(from, to);
    if (length > 0 && remaining < length) {
      const progress = remaining / length;
      return { point: { x: from.x + (to.x - from.x) * progress, y: from.y + (to.y - from.y) * progress }, next: i };
    }
    remaining -= length;
  }
  return { point: motion.points.at(-1), next: motion.points.length };
}
export function townMotionFrames(motion, now, project = islandPlanPoint) {
  const current = sampleTownMotion(motion, now);
  const points = [current.point, ...motion.points.slice(current.next)], length = townPathLength(points);
  let distance = 0;
  return points.map((p, i) => {
    if (i) distance += townDistance(points[i - 1], p);
    const screen = project(p);
    return { transform: `translate(${screen.x / TOWN_WIDTH * 100}%, ${screen.y / TOWN_HEIGHT * 100}%)`, offset: length ? distance / length : 1 };
  });
}
export function createTownMotion() {
  let previous = new Map(), motions = new Map(), token, view;
  return {
    update(scene, worldToken, { now = 0, animate = true, duration = 480 } = {}) {
      const continuous = token === worldToken && view === scene.view && animate;
      const next = new Map();
      for (const actor of scene.residents) {
        const old = previous.get(actor.id), active = motions.get(actor.id), target = townResidentPoint(actor);
        if (!continuous || !old || !actor.alive) continue;
        if (old.location === actor.location) {
          if (active && now < active.startedAt + active.duration) next.set(actor.id, active);
        } else if (townPlace(old.location).links.includes(actor.location)) {
          const current = active ? sampleTownMotion(active, now) : { point: townResidentPoint(old), next: 0 };
          const remainder = active ? active.points.slice(current.next) : [];
          const points = [current.point, ...remainder, ...townRoadPoints(townPlace(old.location), townPlace(actor.location)), target];
          next.set(actor.id, { startedAt: now, duration, points });
        }
      }
      previous = new Map(scene.residents.map(a => [a.id, { ...a }]));
      motions = next; token = worldToken; view = scene.view;
      return motions;
    },
  };
}
