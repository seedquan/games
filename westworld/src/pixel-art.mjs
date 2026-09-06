import { TOWN_WIDTH, TOWN_HEIGHT, townPoint, townRoadPoints, islandCoast, islandPlanPoint } from './island-layout.mjs';
export { TOWN_WIDTH, TOWN_HEIGHT, townPoint, townRoadPoints } from './island-layout.mjs';

const MINI_COLORS = { mara: 'accent', eli: 'link', nora: 'surface', silas: 'success' };
function miniHead(id) {
  if (!Object.hasOwn(MINI_COLORS, id)) throw new Error('Unknown resident illustration.');
  const hair = id === 'silas'
    ? '<ellipse cx="8" cy="4.4" rx="6.7" ry="1.5" fill="var(--cp-text-muted)"/><path d="M4 4V2.5Q8 .4 12 2.5V4" fill="var(--cp-text-muted)"/>'
    : `<path d="M3.2 8V5.5C3.2 .1 12.8 .1 12.8 5.5V8L11.4 5.5Q8 7 4.6 5.2Z" fill="var(--cp-text)"/>${id === 'mara' ? '<circle cx="10.8" cy="2" r="1.9" fill="var(--cp-text)"/>' : ''}`;
  return `<ellipse cx="8" cy="7.2" rx="4.9" ry="5.1" fill="var(--cp-bg-elevated)"/>
    <ellipse cx="8" cy="7.2" rx="4.9" ry="5.1" fill="var(--cp-warning)" opacity=".3"/>
    ${id === 'nora' ? '<path d="M3 5Q1 10 3.5 12L5 10M13 5Q15 10 12.5 12L11 10" stroke="var(--cp-text)" stroke-width="2" fill="none"/>' : ''}
    ${hair}<g fill="var(--cp-text)"><ellipse cx="6.2" cy="7.6" rx=".5" ry=".75"/><ellipse cx="9.8" cy="7.6" rx=".5" ry=".75"/></g>
    <path d="M6.8 9.4Q8 10.3 9.2 9.4" stroke="var(--cp-text)" stroke-width=".45" fill="none" stroke-linecap="round"/>
    <g fill="var(--cp-accent)" opacity=".22"><ellipse cx="4.7" cy="8.8" rx="1" ry=".6"/><ellipse cx="11.3" cy="8.8" rx="1" ry=".6"/></g>`;
}
export function residentPortrait(id, size = 'card') {
  const classes = { card: 'avatar', map: 'avatar map-avatar', inspector: 'avatar inspector-avatar' };
  if (!Object.hasOwn(classes, size)) throw new Error('Unknown portrait size.');
  return `<svg class="${classes[size]}" data-portrait="${id}" viewBox="0 0 16 16" shape-rendering="geometricPrecision" aria-hidden="true" focusable="false">
    <rect width="16" height="16" rx="8" fill="var(--cp-bg-elevated)"/><path d="M2 16Q2 11 8 11Q14 11 14 16" fill="var(--cp-${MINI_COLORS[id] || 'accent'})"/>${miniHead(id)}</svg>`;
}
export function residentFigure(id) {
  const head = miniHead(id);
  return `<svg class="resident-figure" data-portrait="${id}" viewBox="0 0 16 24" shape-rendering="geometricPrecision" aria-hidden="true" focusable="false">
    <g class="step-frame step-a" stroke="var(--cp-text-muted)" stroke-width="3" stroke-linecap="round"><path d="M6 18v4M10 18v4"/></g>
    <g class="step-frame step-b" stroke="var(--cp-text-muted)" stroke-width="3" stroke-linecap="round"><path d="M6 18l-1 3M10 18l1 5"/></g>
    <rect x="3.5" y="11.2" width="9" height="8.8" rx="4" fill="var(--cp-${MINI_COLORS[id]})"/>
    <path d="M3.5 13.5L2.5 17M12.5 13.5L13.5 17" stroke="var(--cp-${MINI_COLORS[id]})" stroke-width="3.5" stroke-linecap="round"/>${head}</svg>`;
}
export function placeArtwork(id, scenery = false) {
  const allowed = ['saloon','well','workshop','farm','ridge','depot','home'];
  if (!allowed.includes(id)) throw new Error(`Unknown island place: ${id}`);
  const building = id === 'well'
    ? '<ellipse cx="32" cy="34" rx="17" ry="9" fill="var(--cp-border-strong)"/><ellipse cx="32" cy="32" rx="13" ry="6" fill="var(--cp-link)"/><path d="M18 30V15M46 30V15" stroke="var(--cp-text-muted)" stroke-width="4" stroke-linecap="round"/><path d="M12 17Q32-3 52 17Z" fill="var(--cp-accent)"/>'
    : id === 'ridge'
      ? '<ellipse cx="33" cy="33" rx="26" ry="11" fill="var(--cp-success)" opacity=".22"/><path d="M10 34Q9 21 20 19Q18 4 33 6Q47 5 48 20Q61 23 55 37Z" fill="var(--cp-border-strong)"/><path d="M22 17Q25 9 35 11" fill="none" stroke="var(--cp-bg)" stroke-width="3" stroke-linecap="round"/>'
      : `<rect x="12" y="17" width="40" height="25" rx="5" fill="var(--cp-bg-elevated)"/><path d="M8 20Q6 18 10 15L29 3Q32 1 35 3L54 15Q58 19 54 21Z" fill="var(--cp-accent)"/>
         <rect x="27" y="25" width="10" height="18" rx="5" fill="var(--cp-warning)" opacity=".7"/><rect x="17" y="25" width="7" height="9" rx="3" fill="var(--cp-link)" opacity=".65"/><rect x="40" y="25" width="7" height="9" rx="3" fill="var(--cp-link)" opacity=".65"/>
         <path d="M12 42H53" stroke="var(--cp-border-strong)" stroke-width="3" stroke-linecap="round"/>
         ${id === 'farm' ? '<path d="M5 38V8M0 16H11M5 10V23" stroke="var(--cp-text-muted)" stroke-width="2" stroke-linecap="round"/>' : ''}`;
  return scenery ? `<g data-art="${id}">${building}</g>` : `<svg class="place-art" data-art="${id}" viewBox="0 0 64 48" shape-rendering="geometricPrecision" aria-hidden="true">${building}</svg>`;
}
export function townBackdrop(places) {
  const coastPath = scale => islandCoast(96,scale).map((p,i)=>{const q=islandPlanPoint(p);return `${i?'L':'M'}${q.x} ${q.y}`;}).join('')+'Z';
  const roads = places.flatMap((p,i)=>p.links.filter(id=>places.findIndex(q=>q.id===id)>i).map(id=>{
    const points=townRoadPoints(p,places.find(q=>q.id===id)).map(islandPlanPoint);
    return `<path data-road="${p.id}-${id}" d="${points.map((a,j)=>`${j?'L':'M'}${a.x} ${a.y}`).join('')}"/>`;
  })).join('');
  const groves = [[-520,-220],[-480,250],[440,-330],[550,240],[-70,-380]];
  const trees = groves.flatMap(([x,y],g)=>Array.from({length:6},(_,i)=>{
    const p=islandPlanPoint({x:x+Math.sin(i*2.4+g)*65,y:y+Math.cos(i*2.4)*45});
    return `<g transform="translate(${p.x} ${p.y})"><path d="M0 0V-9" stroke="var(--cp-text-muted)" stroke-width="2.5" stroke-linecap="round"/><ellipse cx="0" cy="-11" rx="6" ry="8" fill="var(--cp-success)" opacity=".6"/><ellipse cx="-2" cy="-14" rx="3" ry="4" fill="var(--cp-bg)" opacity=".3"/></g>`;
  })).join('');
  const buildings=places.map(p=>{const q=islandPlanPoint(townPoint(p));return `<g transform="translate(${q.x-16} ${q.y-23}) scale(.5)">${placeArtwork(p.id,true)}</g>`;}).join('');
  return `<g class="island-terrain"><rect width="480" height="320" fill="var(--cp-bg)"/><rect width="480" height="320" fill="var(--cp-link)" opacity=".18"/>
    <path d="${coastPath(1.075)}" fill="var(--cp-surface)" opacity=".6"/><path d="${coastPath(1.03)}" fill="var(--cp-bg)"/><path d="${coastPath(1.03)}" fill="var(--cp-warning)" opacity=".32"/>
    <path d="${coastPath(.96)}" fill="var(--cp-bg)"/><path d="${coastPath(.96)}" fill="var(--cp-success)" opacity=".24"/>
    <g fill="none" stroke="var(--cp-warning)" stroke-width="4" stroke-linecap="round" stroke-linejoin="round" opacity=".55">${roads}</g>
    <ellipse cx="214" cy="77" rx="16" ry="10" fill="var(--cp-link)" opacity=".45"/>${trees}${buildings}</g>`;
}
