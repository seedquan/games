import test from 'node:test';
import assert from 'node:assert/strict';
import { createWorld, advance, intervene, PLACES } from '../src/world.mjs';
import { projectTown, createTownMotion, townResidentPoint, townMotionFrames, sampleTownMotion } from '../src/town-scene.mjs';
import { createTownCamera, town3DBounds, buildMiniIsland, createTown3DView } from '../src/town-3d.mjs';
import { islandCoast, ISLAND_RADIUS, townRoadPoints } from '../src/island-layout.mjs';

test('the large organic island has substantially more ground than the former 480 by 320 board', () => {
  const coast=islandCoast();
  const width=Math.max(...coast.map(p=>p.x))-Math.min(...coast.map(p=>p.x));
  const depth=Math.max(...coast.map(p=>p.y))-Math.min(...coast.map(p=>p.y));
  const area=Math.abs(coast.reduce((n,p,i)=>{const q=coast[(i+1)%coast.length];return n+p.x*q.y-q.x*p.y;},0))/2;
  assert.ok(width>1400&&depth>1000&&area>480*320*7);
  const radii=coast.map(p=>Math.hypot(p.x/ISLAND_RADIUS.x,p.y/ISLAND_RADIUS.z));
  assert.ok(Math.max(...radii)-Math.min(...radii)>.15);
  for(const p of PLACES)for(const target of p.links) {
    const to=PLACES.find(q=>q.id===target),points=townRoadPoints(p,to),reverse=townRoadPoints(to,p);
    assert.ok(points.length>24);
    points.forEach((point,i)=>assert.ok(Math.hypot(point.x-reverse.at(-i-1).x,point.y-reverse.at(-i-1).y)<1e-8));
  }
});

test('orthographic camera fits the coastline, projects height and rotates the shared coordinate space', () => {
  for(const yaw of [0,.48,Math.PI/2,Math.PI,Math.PI*1.5])for(const tilt of [.4,.83,1.25]) {
    const camera=createTownCamera(yaw,tilt);
    for(const ground of islandCoast()) {
      const p=camera.ground(ground);
      assert.ok(p.x>0&&p.x<480&&p.y>0&&p.y<320,JSON.stringify({yaw,tilt,p}));
    }
    const foot=camera.project({x:0,y:0,z:0}),head=camera.project({x:0,y:64,z:0});
    assert.ok(head.y<foot.y&&head.depth>foot.depth);
    assert.ok(Math.abs(foot.y-head.y-camera.actorHeight)<1e-9);
  }
  assert.notDeepEqual(createTownCamera(0).ground({x:340,y:-170}),createTownCamera(1).ground({x:340,y:-170}));
  assert.throws(()=>createTownCamera(NaN));
});

test('all seven buildings have bounded hit regions, smooth solid geometry and a shared central home', () => {
  const scene=projectTown(createWorld(),'mara',false),model=buildMiniIsland(scene),camera=createTownCamera();
  assert.equal(model.sites.size,7);assert.equal(model.actors.size,4);assert.equal(model.roads.length,9);
  assert.ok(model.root.userData.treeCount>45);
  assert.deepEqual(model.sites.get('home').position.toArray(),[0,0,40]);
  const geometryTypes=new Set();
  model.root.traverse(mesh=>{
    if(!mesh.geometry)return;
    geometryTypes.add(mesh.geometry.type);
    assert.ok([...mesh.geometry.attributes.position.array].every(Number.isFinite));
  });
  for(const type of ['SphereGeometry','CapsuleGeometry','ExtrudeGeometry','TorusGeometry'])assert.ok(geometryTypes.has(type),type);
  for(const p of PLACES) {
    const bounds=town3DBounds(p,camera);
    assert.ok(bounds.width>10&&bounds.height>10);
    assert.ok(bounds.x-bounds.width/2>=0&&bounds.x+bounds.width/2<=480);
  }
});

function geometrySummary(model) {
  const summary=[];
  model.root.traverse(object=>summary.push({
    type:object.type,data:object.userData,position:object.position.toArray(),scale:object.scale.toArray(),
    geometry:object.geometry?.type,vertices:object.geometry?.attributes.position.count,instances:object.count,
  }));
  return summary;
}
test('island geometry never exposes remote crops, supplies or private resident state', () => {
  const w=createWorld(),before=geometrySummary(buildMiniIsland(projectTown(w,'mara',true)));
  w.places.farm.crop=3;intervene(w,{type:'drop',location:'home',item:'food',amount:3});w.agents[1].goal='OTHER_PRIVATE_GOAL';
  assert.deepEqual(geometrySummary(buildMiniIsland(projectTown(w,'mara',true))),before);
  assert.doesNotMatch(JSON.stringify(geometrySummary(buildMiniIsland(projectTown(w,'mara',false)))),/OTHER_PRIVATE_GOAL/);
  assert.equal(buildMiniIsland(projectTown(w,'mara',true)).actors.size,1);
});

test('motion keyframes terminate at the exact projected 3D resident foot position', () => {
  const w=createWorld(),tracker=createTownMotion(),camera=createTownCamera();
  tracker.update(projectTown(w,'mara',false),w);advance(w,{action:'move',target:'well'});
  const motion=tracker.update(projectTown(w,'mara',false),w,{now:10}).get('mara');
  const frame=townMotionFrames(motion,10,camera.ground).at(-1),p=camera.ground(townResidentPoint(w.agents[0]));
  assert.equal(frame.transform,`translate(${p.x/480*100}%, ${p.y/320*100}%)`);assert.equal(frame.offset,1);
});

test('renderer caches geometry, moves only committed actors, stops idle frames, disposes replaced resources and handles context loss', () => {
  const callbacks=new Map(),events=new Map(),attributes=new Map(),canvas={
    clientWidth:480,clientHeight:320,addEventListener:(key,fn)=>events.set(key,fn),setAttribute:(key,value)=>attributes.set(key,value),
  };
  let id=0,paints=0,stage,lastError='',sizes=0;
  const renderer={shadowMap:{},info:{render:{calls:1}},setPixelRatio(){},setSize(){sizes++;},render(next){paints++;stage=next;}};
  const colors=Object.fromEntries(['bg','ink','border-strong','text-muted','text','success','warning','accent','surface','link'].map(key=>[key,'#888888']));
  const view=createTown3DView(canvas,{},{
    createRenderer:()=>renderer,requestFrame:fn=>{callbacks.set(++id,fn);return id;},cancelFrame:id=>callbacks.delete(id),
    pixelRatio:()=>1,palette:()=>colors,onError:message=>{lastError=message;},
  });
  const flush=now=>{const pending=[...callbacks.values()];callbacks.clear();pending.forEach(fn=>fn(now));};
  const w=createWorld(),tracker=createTownMotion(),before=structuredClone(w);
  view.enable(true);view.update(projectTown(w,'mara',false),new Map());assert.equal(callbacks.size,1);
  flush(0);assert.ok(paints>0);assert.equal(callbacks.size,0);assert.deepEqual(w,before);
  const root=stage.children.find(child=>child.userData.islandFootprint);
  let actor;root.traverse(child=>{if(child.userData.resident==='mara')actor=child;});
  assert.deepEqual([actor.position.x,actor.position.z],Object.values(townResidentPoint(w.agents[0])));
  view.update(projectTown(w,'mara',false),new Map());flush(2);
  assert.ok(stage.children.includes(root));assert.equal(sizes,1);
  tracker.update(projectTown(w,'mara',false),w);advance(w,{action:'move',target:'well'});
  const motions=tracker.update(projectTown(w,'mara',false),w,{now:10});
  view.update(projectTown(w,'mara',false),motions);flush(20);assert.equal(callbacks.size,1);
  const point=sampleTownMotion(motions.get('mara'),20).point;
  assert.deepEqual([actor.position.x,actor.position.z],[point.x,point.y]);
  flush(500);assert.equal(callbacks.size,0);
  assert.deepEqual([actor.position.x,actor.position.z],Object.values(townResidentPoint(w.agents[0])));
  const disposed=new Map(),resources=new Set();
  root.traverse(mesh=>{if(mesh.geometry)resources.add(mesh.geometry);if(mesh.material)resources.add(mesh.material);if(mesh.isInstancedMesh)resources.add(mesh);});
  resources.forEach(resource=>resource.addEventListener('dispose',()=>disposed.set(resource,(disposed.get(resource)||0)+1)));
  view.update(projectTown(w,'mara',true),new Map());flush(501);
  assert.equal(disposed.size,resources.size);assert.ok([...disposed.values()].every(n=>n===1));
  view.setCamera(1,.7);assert.equal(callbacks.size,1);view.enable(false);assert.equal(callbacks.size,0);
  view.enable(true);events.get('webglcontextlost')({preventDefault(){}});assert.equal(callbacks.size,0);
  assert.match(lastError,/平面海岛/);assert.equal(w.metrics.actions,1);
  assert.equal(attributes.get('data-renderer'),'mini-island');
});
