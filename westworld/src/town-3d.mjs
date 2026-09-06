import * as THREE from 'three';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';
import { PLACES } from './world.mjs';
import { TOWN_WIDTH, TOWN_HEIGHT, ISLAND_RADIUS, townPoint, townRoadPoints, islandCoast } from './island-layout.mjs';
import { townResidentPoint, sampleTownMotion } from './town-scene.mjs';

export function createTownCamera(yaw = .48, tilt = .83) {
  if (!Number.isFinite(yaw) || !Number.isFinite(tilt)) throw new Error('Invalid island camera.');
  tilt = Math.max(.4, Math.min(1.25, tilt));
  const sx = Math.abs(Math.cos(yaw)), sz = Math.abs(Math.sin(yaw));
  const horizontal = sx * ISLAND_RADIUS.x + sz * ISLAND_RADIUS.z;
  const deep = sz * ISLAND_RADIUS.x + sx * ISLAND_RADIUS.z;
  const scale = Math.min(440 / (horizontal * 2.2), 278 / (deep * 2.2 * Math.sin(tilt) + 160 * Math.cos(tilt)));
  const camera = new THREE.OrthographicCamera(-240/scale,240/scale,160/scale,-160/scale,1,5000);
  camera.position.set(Math.sin(yaw)*1800*Math.cos(tilt),1800*Math.sin(tilt)+25,Math.cos(yaw)*1800*Math.cos(tilt));
  camera.lookAt(0,25,0); camera.updateMatrixWorld(); camera.updateProjectionMatrix();
  const vector = new THREE.Vector3();
  const project = ({x,y=0,z}) => {
    vector.set(x,y,z).project(camera);
    return {x:(vector.x+1)*240,y:(1-vector.y)*160,depth:-vector.z};
  };
  return {yaw,tilt,scale,camera,project,ground:p=>project({x:p.x,y:0,z:p.y}),actorHeight:64*Math.cos(tilt)*scale};
}
export function town3DBounds(place,camera) {
  const p=townPoint(place),width=place.id==='home'?150:84,height=place.id==='home'?110:place.id==='farm'?100:90,depth=place.id==='home'?118:74;
  const corners=[];
  for(const x of [-width/2,width/2]) for(const z of [-depth,8]) for(const y of [0,height]) corners.push(camera.project({x:p.x+x,y,z:p.y+z}));
  const left=Math.min(...corners.map(p=>p.x)),right=Math.max(...corners.map(p=>p.x)),top=Math.min(...corners.map(p=>p.y)),bottom=Math.max(...corners.map(p=>p.y));
  return {x:(left+right)/2,y:(top+bottom)/2,width:right-left,height:bottom-top};
}
function islandShape(scale) {
  const points=islandCoast(128,scale),shape=new THREE.Shape();
  points.forEach((p,i)=>i?shape.lineTo(p.x,-p.y):shape.moveTo(p.x,-p.y));
  shape.closePath(); return shape;
}
function islandExtrusion(scale,depth,bevel,top) {
  const geometry=new THREE.ExtrudeGeometry(islandShape(scale),{depth,steps:1,bevelEnabled:true,bevelSegments:4,bevelSize:bevel,bevelThickness:bevel,curveSegments:12});
  geometry.rotateX(-Math.PI/2); geometry.computeBoundingBox();
  geometry.translate(0,top-geometry.boundingBox.max.y,0); return geometry;
}
function islandRibbon(points,width,y=.65) {
  const vertices=[],indices=[];
  for(let i=0;i<points.length;i++) {
    const before=points[Math.max(0,i-1)],after=points[Math.min(points.length-1,i+1)],length=Math.hypot(after.x-before.x,after.y-before.y)||1;
    const dx=-(after.y-before.y)/length*width/2,dz=(after.x-before.x)/length*width/2,p=points[i];
    vertices.push(p.x+dx,y,p.y+dz,p.x-dx,y,p.y-dz);
    if(i<points.length-1) {const a=i*2;indices.push(a,a+2,a+1,a+1,a+2,a+3);}
  }
  const geometry=new THREE.BufferGeometry();
  geometry.setAttribute('position',new THREE.Float32BufferAttribute(vertices,3));geometry.setIndex(indices);geometry.computeVertexNormals();return geometry;
}
function islandDistanceToSegment(p,a,b) {
  const dx=b.x-a.x,dy=b.y-a.y,t=Math.max(0,Math.min(1,((p.x-a.x)*dx+(p.y-a.y)*dy)/(dx*dx+dy*dy||1)));
  return Math.hypot(p.x-a.x-dx*t,p.y-a.y-dy*t);
}
export function islandPalette(colors) {
  const c=key=>new THREE.Color(colors[key]),mix=(a,b,n)=>c(a).lerp(c(b),n);
  let paper=c('surface');if(paper.r+paper.g+paper.b<1)paper=c('text');
  return {
    sea:mix('link','bg',.45),seaShadow:c('ink'),foam:paper.clone().lerp(c('link'),.08),sand:mix('warning','bg',.48),grass:mix('success','bg',.22),
    hill:mix('success','bg',.19),leaf:mix('success','bg',.10),leafLight:mix('success','bg',.29),
    wood:mix('text-muted','warning',.30),path:mix('warning','bg',.44),pathEdge:mix('warning','bg',.32),
    wall:c('surface'),cream:mix('warning','surface',.17),rose:mix('accent','bg',.27),blue:mix('link','bg',.42),
    mint:mix('success','bg',.57),water:mix('link','bg',.38),skin:c('warning').lerp(paper,.77),
    ink:c('ink'),stone:mix('border-strong','bg',.58),cheek:c('accent').lerp(paper,.68),light:paper,fog:mix('border-strong','bg',.64),
  };
}

export function buildMiniIsland(scene) {
  const root=new THREE.Group(),materials=new Map(),sites=new Map(),actors=new Map(),geometryCache=new Map();
  const material=key=>{
    if(!materials.has(key)) materials.set(key,key==='sea'?new THREE.MeshBasicMaterial({toneMapped:false}):key==='seaShadow'?new THREE.ShadowMaterial({opacity:.14}):new THREE.MeshStandardMaterial({roughness:.92,metalness:0}));
    return materials.get(key);
  };
  const geometry=(key,create)=>{if(!geometryCache.has(key)) geometryCache.set(key,create());return geometryCache.get(key);};
  const sphere=geometry('sphere',()=>new THREE.SphereGeometry(1,20,14));
  const cylinder=geometry('cylinder',()=>new THREE.CylinderGeometry(1,1,1,20));
  const add=(parent,geo,key,x=0,y=0,z=0,sx=1,sy=1,sz=1)=>{
    const mesh=new THREE.Mesh(geo,material(key));mesh.position.set(x,y,z);mesh.scale.set(sx,sy,sz);mesh.castShadow=true;mesh.receiveShadow=true;parent.add(mesh);return mesh;
  };
  const ball=(parent,key,x,y,z,sx,sy=sx,sz=sx)=>add(parent,sphere,key,x,y,z,sx,sy,sz);
  const box=(parent,key,x,y,z,w,h,d,r=2)=>{
    const id=`box:${w}:${h}:${d}:${r}`;
    return add(parent,geometry(id,()=>new RoundedBoxGeometry(w,h,d,3,r)),key,x,y,z);
  };
  const tube=(parent,key,points,r=.8)=>{
    const curve=new THREE.CatmullRomCurve3(points.map(p=>new THREE.Vector3(...p)));
    return add(parent,new THREE.TubeGeometry(curve,Math.max(12,points.length*8),r,6,false),key);
  };
  const ocean=add(root,new THREE.PlaneGeometry(12000,12000),'sea',0,-38,0);
  ocean.rotation.x=-Math.PI/2;ocean.castShadow=false;
  const seaShadow=add(root,new THREE.PlaneGeometry(12000,12000),'seaShadow',0,-37.9,0);
  seaShadow.rotation.x=-Math.PI/2;seaShadow.castShadow=false;
  add(root,islandExtrusion(1.075,12,12,-31),'foam').castShadow=false;
  add(root,islandExtrusion(1.04,17,17,-10),'sand').castShadow=false;
  add(root,islandExtrusion(.98,28,18,0),'grass');
  root.userData.islandFootprint=islandCoast();
  const roads=PLACES.flatMap((p,i)=>p.links.filter(id=>PLACES.findIndex(q=>q.id===id)>i).map(id=>({id:`${p.id}-${id}`,points:townRoadPoints(p,PLACES.find(q=>q.id===id))})));
  for(const road of roads) {
    const edge=add(root,islandRibbon(road.points,21,.4),'pathEdge');edge.castShadow=false;
    const path=add(root,islandRibbon(road.points,16,.7),'path');path.castShadow=false;path.userData.road=road.id;
  }
  const coastal=islandCoast(96,.83);
  add(root,islandRibbon([...coastal,coastal[0]],7,.3),'path').castShadow=false;
  ball(root,'hill',-480,-20,-220,140,55,105);
  ball(root,'hill',385,-22,-315,150,63,110);
  const pond=ball(root,'water',-95,1,-335,70,1.5,46);pond.castShadow=false;
  const river=[{x:-95,y:-350},{x:-40,y:-390},{x:-80,y:-440},{x:-10,y:-505}];
  add(root,islandRibbon(river,19,.3),'sand').castShadow=false;
  add(root,islandRibbon(river,12,.8),'water').castShadow=false;
  for(let i=0;i<10;i++) box(root,'wood',-53+i*3.8,4,-399,3.4,3,27,1);
  tube(root,'cream',[[-56,14,-414],[-36,17,-414],[-15,14,-414]],1.4);
  tube(root,'cream',[[-56,14,-384],[-36,17,-384],[-15,14,-384]],1.4);
  for(const [x,z] of [[-550,380],[590,-390],[680,270]]) for(let i=0;i<3;i++) {
    const cloud=ball(root,'foam',x+i*25,125+Math.sin(i)*10,z,35,18,22);cloud.castShadow=false;
  }
  const matrix=new THREE.Matrix4(),quaternion=new THREE.Quaternion(),position=new THREE.Vector3(),scale=new THREE.Vector3();
  const instances=(geo,key,items)=>{
    const mesh=new THREE.InstancedMesh(geo,material(key),items.length);
    items.forEach((v,i)=>{position.set(v.x,v.y,v.z);scale.set(v.sx,v.sy,v.sz);matrix.compose(position,quaternion,scale);mesh.setMatrixAt(i,matrix);});
    mesh.castShadow=true;mesh.receiveShadow=true;root.add(mesh);return mesh;
  };
  const trunks=[],crowns=[],tops=[],flowers=[];
  const groves=[[-500,-200],[-475,270],[430,-310],[550,290],[-175,-430]];
  for(const [g,[cx,cz]] of groves.entries()) for(let i=0;i<18;i++) {
    const angle=i*2.399+g,r=22+Math.sqrt(i/18)*105,x=cx+Math.cos(angle)*r,z=cz+Math.sin(angle)*r,p={x,y:z};
    if(roads.some(road=>road.points.some((q,j)=>j&&islandDistanceToSegment(p,road.points[j-1],q)<30))) continue;
    const size=17+i%4*2;
    trunks.push({x,y:12,z,sx:2.5,sy:24,sz:2.5});
    crowns.push({x,y:29,z,sx:size,sy:size*1.25,sz:size*.85});
    tops.push({x:x-4,y:39,z:z+2,sx:size*.69,sy:size*.83,sz:size*.62});
  }
  instances(cylinder,'wood',trunks);instances(sphere,'leaf',crowns);instances(sphere,'leafLight',tops);
  for(let i=0;i<130;i++) {
    const x=Math.sin(i*4.73)*570,z=Math.cos(i*2.13)*380,p={x,y:z};
    if(PLACES.some(q=>Math.hypot(x-townPoint(q).x,z-townPoint(q).y)<85)||roads.some(road=>road.points.some((q,j)=>j&&islandDistanceToSegment(p,road.points[j-1],q)<20))) continue;
    flowers.push({x,y:2,z,sx:2.6,sy:1.6,sz:2.6});
  }
  instances(sphere,'cheek',flowers);root.userData.treeCount=trunks.length;
  const roof=(parent,x,y,z,w,h,d,key='rose')=>{
    const shape=new THREE.Shape();
    shape.moveTo(-w/2,0);shape.quadraticCurveTo(-w/2-3,3,-w/2+2,6);
    shape.lineTo(-5,h-2);shape.quadraticCurveTo(0,h+2,5,h-2);shape.lineTo(w/2-2,6);shape.quadraticCurveTo(w/2+3,3,w/2,0);shape.closePath();
    const geo=new THREE.ExtrudeGeometry(shape,{depth:d,steps:1,bevelEnabled:true,bevelSegments:3,bevelSize:2,bevelThickness:2,curveSegments:8});
    geo.translate(0,0,-d/2);return add(parent,geo,key,x,y,z);
  };
  for(const p of scene.places) {
    const group=new THREE.Group();group.position.set(p.point.x,0,p.point.y);group.userData.place=p.id;root.add(group);sites.set(p.id,group);
    const key=normal=>p.visible?normal:'fog';
    if(p.id==='ridge') {
      ball(group,key('hill'),0,-16,-44,70,42,60);
      for(const [x,y,z,s] of [[-25,9,-38,17],[9,22,-48,20],[29,5,-23,14]]) ball(group,key('stone'),x,y,z,s,s*.72,s*.9);
      box(group,key('wood'),-5,17,-42,34,4,12);box(group,key('wood'),-5,25,-48,34,13,3);
    } else if(p.id==='well') {
      add(group,geometry('well-ring',()=>new THREE.TorusGeometry(20,5,12,32)),key('stone'),0,10,-24).rotation.x=Math.PI/2;
      const water=add(group,new THREE.CircleGeometry(18,32),key('water'),0,8,-24);water.rotation.x=-Math.PI/2;water.castShadow=false;
      for(const x of [-25,25]) add(group,cylinder,key('wood'),x,24,-24,2.5,48,2.5);
      roof(group,0,45,-24,63,19,42);
      add(group,cylinder,key('wood'),0,28,-24,1,26,1);
    } else {
      const home=p.id==='home',w=home?126:72,d=home?84:52,h=home?60:38,z=-d/2-18;
      box(group,key('stone'),0,3,z,w+8,6,d+8,4);
      box(group,key(p.id==='farm'?'cream':'wall'),0,h/2+6,z,w,h,d,5);
      roof(group,0,h+6,z,w+12,home?29:23,d+12,p.id==='depot'?'blue':'rose');
      box(group,key('wood'),0,20,-17,16,31,3,6);
      ball(group,key('cream'),5,19,-14.7,1.1);
      for(const x of [-w*.30,w*.30]) {
        box(group,key('wood'),x,27,-16.5,18,20,3,5);
        box(group,key('blue'),x,27,-14.5,13,15,1,4);
        box(group,key('cream'),x,27,-13.6,1,15,1,.4);box(group,key('cream'),x,27,-13.5,13,1,1,.4);
        box(group,key('wood'),x,14,-12,20,5,7,2);
        for(const dx of [-6,0,6]) ball(group,key('cheek'),x+dx,18,-12,3,2,2);
      }
      box(group,key('wood'),w/2+1,27,z,2,18,17,3);
      box(group,key('blue'),w/2+2,27,z,1,13,12,2);
      add(group,cylinder,key('wood'),w*.28,h+19,z-10,5,29,5);
      if(home) {
        box(group,key('path'),0,1.5,15,148,3,70,9);
        for(const x of [-84,84]) {box(group,key('wood'),x,9,25,29,4,12);box(group,key('wood'),x,17,20,29,14,3);}
        const heart=new THREE.Shape();heart.moveTo(0,0);heart.bezierCurveTo(-12,8,-8,17,0,12);heart.bezierCurveTo(8,17,12,8,0,0);
        add(group,new THREE.ShapeGeometry(heart,12),key('cream'),0,h+9,-8);
      }
      if(p.id==='farm') {
        add(group,cylinder,key('cream'),-64,31,-31,6,62,6);
        const hub=ball(group,key('wood'),-64,63,-23,3);
        for(const angle of [0,Math.PI/2]) {const blade=box(group,key('wall'),-64,63,-22,5,39,2,2);blade.rotation.z=angle;}
        hub.userData.decorative=true;
        for(let row=0;row<5;row++) {
          box(group,key('wood'),-82,1,18+row*13,62,2,7,3);
          if(p.visible&&p.crop>0) for(let col=0;col<6;col++) ball(group,'mint',-108+col*10,5,18+row*13,3,6,3);
        }
      }
      if(p.id==='depot') {
        for(let i=0;i<22;i++) {
          box(group,key('wood'),45+i*8,1,35,7.2,4,47,1);
          if(i%5===0) for(const dz of [-20,20]) add(group,cylinder,key('wood'),45+i*8,-19,35+dz,2.5,40,2.5);
        }
      }
    }
    if(p.visible&&p.shelter&&!PLACES.find(q=>q.id===p.id).covered) {
      for(const x of [55,82]) add(group,cylinder,'wood',x,12,5,2,24,2);
      roof(group,69,24,5,38,7,28,'mint');
    }
  }
  const createActor=resident=>{
    const group=new THREE.Group(),shirt={mara:'rose',eli:'blue',nora:'wall',silas:'mint'}[resident.id];
    const limbs=[];
    const capsule=geometry('body',()=>new THREE.CapsuleGeometry(7,12,8,16));
    add(group,capsule,shirt,0,21,0);
    for(const side of [-1,1]) {
      const leg=new THREE.Group();leg.position.set(side*4,12,0);group.add(leg);
      add(leg,geometry('leg',()=>new THREE.CapsuleGeometry(2.8,8,6,12)),'wood',0,-6,0);
      box(leg,'ink',0,-11,2,6,4,9,2);limbs.push(leg);
      add(group,geometry('arm',()=>new THREE.CapsuleGeometry(3,8,6,12)),shirt,side*10,20,0);
      ball(group,'skin',side*10,13,0,3.3);
    }
    ball(group,'skin',0,43,0,12,12,11.5);
    const cap=geometry('hair',()=>new THREE.SphereGeometry(12.4,24,16,0,Math.PI*2,0,Math.PI/2));
    add(group,cap,'ink',0,44,0);
    ball(group,'ink',0,43,-8,10,10,4);
    for(const side of [-1,1]) {
      ball(group,'ink',side*4,43,10.8,1.5,2.2,.8);
      ball(group,'wall',side*4-.4,43.8,11.5,.45);
      ball(group,'cheek',side*7,38.5,9.5,2.2,1.2,.5);
    }
    tube(group,'ink',[[-2,37,11.4],[0,36.3,11.8],[2,37,11.4]],.45);
    if(resident.id==='mara') ball(group,'ink',6,56,-2,5);
    if(resident.id==='nora') for(const side of [-1,1]) ball(group,'ink',side*10,40,-2,3,9,6);
    if(resident.id==='silas') {add(group,cylinder,'cream',0,57,0,17,2,16);add(group,cylinder,'cream',0,61,0,10,7,10);}
    group.userData.resident=resident.id;root.add(group);return {group,limbs};
  };
  for(const resident of scene.residents) actors.set(resident.id,createActor(resident));
  return {root,materials,sites,actors,roads};
}

export function createTown3DView(canvas,context,platform) {
  const renderer=(platform.createRenderer||((options)=>new THREE.WebGLRenderer(options)))({canvas,context,antialias:true,alpha:false,powerPreference:'low-power'});
  renderer.outputColorSpace=THREE.SRGBColorSpace;renderer.toneMapping=THREE.ACESFilmicToneMapping;renderer.toneMappingExposure=1;
  renderer.shadowMap.enabled=true;renderer.shadowMap.type=THREE.PCFSoftShadowMap;
  const stage=new THREE.Scene(),hemisphere=new THREE.HemisphereLight(),sun=new THREE.DirectionalLight();
  hemisphere.intensity=1.65;sun.intensity=2.2;sun.position.set(-650,1000,550);sun.castShadow=true;
  sun.shadow.mapSize.set(1024,1024);sun.shadow.camera.left=-1100;sun.shadow.camera.right=1100;sun.shadow.camera.top=900;sun.shadow.camera.bottom=-900;
  sun.shadow.camera.near=100;sun.shadow.camera.far=2600;sun.shadow.bias=-.0002;sun.shadow.normalBias=.5;
  stage.add(hemisphere,sun);
  let camera=createTownCamera(),scene,model,motions=new Map(),key='',paletteKey='',enabled=false,frame=null,frames=0,sizeKey='';
  const requestDraw=()=>{if(enabled&&scene&&frame===null) frame=platform.requestFrame(draw);};
  const disposeModel=()=>{
    if(!model)return;
    const geometries=new Set(),materials=new Set();
    model.root.traverse(object=>{
      if(object.geometry)geometries.add(object.geometry);
      if(object.material)materials.add(object.material);
      if(object.isInstancedMesh)object.dispose();
    });
    geometries.forEach(g=>g.dispose());materials.forEach(m=>m.dispose());stage.remove(model.root);
  };
  function draw(now) {
    frame=null;if(!enabled||!scene)return;
    const width=canvas.clientWidth,height=canvas.clientHeight;if(!width||!height)return;
    const ratio=Math.min(platform.pixelRatio(),2,2400/Math.max(width,height)),nextSize=`${width}:${height}:${ratio}`;
    if(nextSize!==sizeKey) {renderer.setPixelRatio(ratio);renderer.setSize(width,height,false);sizeKey=nextSize;}
    const colors=platform.palette(),nextPalette=JSON.stringify([colors,scene.weather]);
    if(nextPalette!==paletteKey) {
      paletteKey=nextPalette;const values=islandPalette(colors);
      model.materials.forEach((material,key)=>material.color.copy(values[key]));
      stage.background=values.sea.clone();hemisphere.color.copy(values.light);hemisphere.groundColor.copy(values.grass);sun.color.copy(values.light);
      sun.intensity=scene.weather==='storm'?.65:scene.weather==='rain'?1.2:2.2;
      if(['storm','rain'].includes(scene.weather))stage.background.lerp(values.fog,scene.weather==='storm'?.35:.13);
    }
    let moving=false;
    for(const a of scene.residents) {
      const actor=model.actors.get(a.id),motion=motions.get(a.id),active=!!motion&&now<motion.startedAt+motion.duration;
      const point=active?sampleTownMotion(motion,now).point:townResidentPoint(a);
      actor.group.position.set(point.x,0,point.y);actor.group.visible=true;
      if(active) {
        const next=sampleTownMotion(motion,Math.min(now+16,motion.startedAt+motion.duration)).point;
        if(Math.hypot(next.x-point.x,next.y-point.y)>.01)actor.group.rotation.y=Math.atan2(next.x-point.x,next.y-point.y);
      }
      actor.limbs.forEach((leg,i)=>{leg.rotation.x=active?Math.sin(now/95+i*Math.PI)*.5:0;});
      moving ||=active;
    }
    renderer.render(stage,camera.camera);canvas.setAttribute('data-renderer','mini-island');canvas.setAttribute('data-frames',String(++frames));
    canvas.setAttribute('data-draw-calls',String(renderer.info.render.calls));
    if(moving)requestDraw();
  }
  canvas.addEventListener('webglcontextlost',event=>{
    event.preventDefault();enabled=false;if(frame!==null)platform.cancelFrame(frame);frame=null;
    platform.onError('立体绘图暂时不可用，已切换为平面海岛。刷新后可以重新启用 3D。');
  });
  return {
    get camera(){return camera;},
    setCamera(yaw,tilt){camera=createTownCamera(yaw,tilt);requestDraw();},
    reset(){camera=createTownCamera();requestDraw();},
    enable(value){enabled=value;if(!enabled&&frame!==null){platform.cancelFrame(frame);frame=null;}requestDraw();},
    update(next,nextMotions) {
      scene=next;motions=nextMotions;
      const nextKey=JSON.stringify([next.places.map(p=>[p.id,p.visible,p.crop,p.shelter]),next.residents.map(a=>[a.id,a.alive])]);
      if(nextKey!==key) {disposeModel();model=buildMiniIsland(next);stage.add(model.root);key=nextKey;paletteKey='';}
      requestDraw();
    },
  };
}
