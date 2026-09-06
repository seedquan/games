export const TOWN_WIDTH = 480, TOWN_HEIGHT = 320;
export const ISLAND_RADIUS = Object.freeze({ x: 720, z: 520 });
const ISLAND_SITES = {
  saloon: { x: -310, y: -200 }, well: { x: 35, y: -180 },
  workshop: { x: 340, y: -170 }, farm: { x: -340, y: 230 },
  ridge: { x: 75, y: 290 }, depot: { x: 480, y: 220 }, home: { x: 0, y: 40 },
};
export function townPoint(place) {
  const point = ISLAND_SITES[place.id];
  if (!point) throw new Error(`Unknown island place: ${place.id}`);
  return { ...point };
}
export function islandPlanPoint(point) {
  return { x: 240 + point.x * .285, y: 160 + point.y * .265 };
}
export function islandCoast(count = 128, scale = 1) {
  return Array.from({ length: count }, (_, i) => {
    const angle = i / count * Math.PI * 2;
    const radius = 1 + .08 * Math.sin(3 * angle + .5) + .045 * Math.cos(5 * angle - .4);
    return { x: Math.cos(angle) * ISLAND_RADIUS.x * radius * scale, y: Math.sin(angle) * ISLAND_RADIUS.z * radius * scale };
  });
}
const ISLAND_ROUTES = {
  'saloon-well': [[-200,-150],[-110,-170]],
  'saloon-farm': [[-465,-130],[-455,155]],
  'well-workshop': [[145,-235],[245,-215]],
  'well-ridge': [[-150,-90],[-165,240]],
  'well-home': [[-60,-115],[-115,70]],
  'workshop-depot': [[510,-80],[540,140]],
  'farm-ridge': [[-220,345],[-65,345]],
  'ridge-depot': [[255,360],[390,325]],
  'ridge-home': [[190,265],[165,85]],
};
export function townRoadPoints(from, to) {
  if (!from.links.includes(to.id)) throw new Error('Island road must join adjacent places.');
  const key = `${from.id}-${to.id}`, reverseKey = `${to.id}-${from.id}`;
  const direct = ISLAND_ROUTES[key], reverse = ISLAND_ROUTES[reverseKey];
  if (!direct && !reverse) throw new Error(`Missing island road: ${key}`);
  const controls = direct || [...reverse].reverse();
  const points = [townPoint(from), ...controls.map(([x,y]) => ({x,y})), townPoint(to)], result = [];
  for (let i = 0; i < points.length - 1; i++) {
    const a = points[Math.max(0,i-1)], b = points[i], c = points[i+1], d = points[Math.min(points.length-1,i+2)];
    for (let step = 0; step < 12; step++) {
      const t = step / 12, t2 = t*t, t3 = t2*t;
      const interpolate = key => .5 * (2*b[key] + (-a[key]+c[key])*t + (2*a[key]-5*b[key]+4*c[key]-d[key])*t2 + (-a[key]+3*b[key]-3*c[key]+d[key])*t3);
      result.push({x:interpolate('x'),y:interpolate('y')});
    }
  }
  result.push(points.at(-1));
  return result;
}
