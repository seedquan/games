// Pure regression checks; this does not replace browser gameplay or FPS verification.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import test from 'node:test';
const html = readFileSync(new URL('../../abyss-protocol/index.html', import.meta.url), 'utf8');
const source = html.slice(html.indexOf('let androidTransitionSurface ='), html.indexOf('function drawTexturedFloor('));
function harness(ready=true) {
  const calls=[];
  const ctx=new Proxy({globalAlpha:1}, {get(o,k){return k in o ? o[k] : (...args)=>calls.push([k,...args]);}});
  const box={ctx,artAnimationPreview:false,southRigPreviewEnabled:false,rigArtEnabled:false,abyssArt:{player:{ready,image:{}}},timeNow:0,TAU:Math.PI*2,numPlayers:1,
    meleeArcNow:()=>Math.PI,weaponDefP:p=>p.weapon,drawHeldWeapon:(...args)=>calls.push(['weapon',...args]),
    drawAndroidFeedback:p=>calls.push(['feedback',p]),Math,Object,Number};
  for(const key of ['East','SouthEast','South','SouthWest','West','NorthWest','North','NorthEast'])box.abyssArt['rig'+key]={ready:true,image:{}};
  vm.createContext(box);vm.runInContext(source,box);
  return {box,calls};
}
const player=()=>({x:20,y:30,r:12,hp:100,maxHp:100,aimDraw:0,moveAmt:0,walkT:0,recoilT:0,hurtT:0,weapon:{id:'blade'}});
test('all eight directions and wraparound resolve to valid atlas cells',()=>{
 const {box}=harness();
 for(let i=-24;i<24;i++) assert.equal(box.textureFacing(i*Math.PI/4),((i%8)+8)%8);
 assert.equal(box.textureFacing(-.01,0),0);
});
test('facing dead band resists boundary jitter but permits an intentional turn',()=>{
 const {box}=harness(); const boundary=Math.PI/8;
 assert.equal(box.textureFacing(boundary+.03,0),0);
 assert.equal(box.textureFacing(boundary-.03,1),1);
 assert.equal(box.textureFacing(boundary+.09,0),1);
 assert.equal(box.textureFacing(Math.PI,0),4);
});
test('charged longbow and quick bow retain their authored draw behavior',()=>{
 const {box,calls}=harness(); const p=player();p.weapon={id:'lbow',isBow:true};p.drawing=true;p.drawT=.87;
 box.drawTexturedAndroid(p);assert.equal(calls.find(c=>c[0]==='weapon')[6],.87);
 p.drawing=false;assert.equal(box.texturedWeaponPose(p,p.weapon).draw,0);
 p.weapon={id:'qbow',isBow:true};p.recoilT=.09;assert.equal(box.texturedWeaponPose(p,p.weapon).draw,.6);
});
test('flying glaive is absent from hand and shared damage feedback still runs',()=>{
 const {box,calls}=harness(); const p=player();p.glaiveOut=true;
 assert.equal(box.drawTexturedAndroid(p),true);
 assert.equal(calls.filter(c=>c[0]==='weapon').length,0);
 assert.equal(calls.filter(c=>c[0]==='feedback').length,1);
});
test('unloaded art yields to fallback without drawing or duplicate feedback',()=>{
 const {box,calls}=harness(false);
 assert.equal(box.drawTexturedAndroid(player()),false);assert.equal(calls.length,0);
});
test('co-op identification and damage state draw a ground ring',()=>{
 const {box,calls}=harness();box.numPlayers=2;box.drawTexturedAndroid(player());
 assert.equal(calls.filter(c=>c[0]==='stroke').length,1);
});
test('textured final boss preserves phase transition and rage feedback',()=>{
 const {box,calls}=harness();box.abyssArt.core={ready:true,image:{}};
 box.drawBossPhaseAuras=e=>calls.push(['phase',e.bossRage,e.phaseInvT]);
 assert.equal(box.drawTexturedEnemy({type:'boss',kind:'abyss',x:0,y:0,r:50,phase:0,bossRage:true,phaseInvT:.3},false),true);
 assert.deepEqual(calls.find(c=>c[0]==='phase'),['phase',true,.3]);
});
test('unavailable guardian asset yields to vector shield renderer',()=>{
 const {box,calls}=harness();
 assert.equal(box.drawTexturedEnemy({type:'shield'},false),false);
 assert.equal(calls.length,0);
});
test('character passes put warnings below sorted bodies and labels above, without changing simulation order',()=>{
 const events=[];
 const near={id:'near',x:0,y:30,r:10}, far={id:'far',x:0,y:10,r:10}, culled={id:'culled',x:999,y:0,r:10};
 const middle={id:'player',x:0,y:20,r:10,hp:1}, dead={id:'dead',x:0,y:0,r:10,hp:0};
 const enemies=[near,far,culled];const players=[middle,dead];
 const box={enemies,players,pillars:[],texturedObstacleAsset:()=>null,numPlayers:2,inView:x=>x!==999,
 drawEnemy:(e,layer)=>events.push(`${layer}:${e.id}`),drawPlayerTrails:()=>events.push('trails'),
 drawOnePlayer:(p,showTag)=>{assert.equal(showTag,false);events.push(`body:${p.id}`);},
 drawPlayerTag:p=>events.push(`tag:${p.id}`)};
 vm.createContext(box);
 const start=html.indexOf('const characterDrawList =');
 vm.runInContext(html.slice(start,html.indexOf('function drawPlayerTrails()',start)),box);
 box.drawCharacterLayers();
 assert.deepEqual(events,['telegraph:near','telegraph:far','trails','body:far','body:player','body:near','status:near','status:far','tag:player']);
 assert.deepEqual(enemies,[near,far,culled]);assert.deepEqual(players,[middle,dead]);
 // A following frame must clear the reused work lists; removed actors cannot linger.
 events.length=0;enemies.length=0;players.length=0;box.drawCharacterLayers();assert.deepEqual(events,['trails']);
});
test('enemy warning, body and HP layers execute exclusively and balance canvas save/restore',()=>{
 const calls=[];let depth=0;
 const ctx=new Proxy({save:()=>depth++,restore:()=>depth--}, {get(o,k){return k in o ? o[k] : (...args)=>calls.push([k,...args]);}});
 const box={ctx,Math,TAU:Math.PI*2,timeNow:0,player:null,spriteDetail:()=>false,
 clamp:(v,a,b)=>Math.max(a,Math.min(b,v)),glow:()=>{},noglow:()=>{},
 drawTexturedEnemy:()=>{calls.push(['body']);return true;},enemyLabelTop:()=>-26};
 vm.createContext(box);
 const start=html.indexOf('function drawEnemy(');
 vm.runInContext(html.slice(start,html.indexOf('/* the held weapon',start)),box);
 const e={type:'bomber',state:'fuse',x:0,y:0,r:10,t:.5,col:'#f88',hp:3,maxHp:10,flash:0,frozenT:0};
 box.drawEnemy(e,'telegraph');assert.ok(calls.some(c=>c[0]==='arc'));assert.ok(!calls.some(c=>c[0]==='body'||c[0]==='fillRect'));assert.equal(depth,0);
 calls.length=0;box.drawEnemy(e,'body');assert.equal(calls.filter(c=>c[0]==='body').length,1);assert.ok(!calls.some(c=>c[0]==='arc'||c[0]==='fillRect'));assert.equal(depth,0);
 calls.length=0;box.drawEnemy(e,'status');assert.equal(calls.filter(c=>c[0]==='fillRect').length,2);assert.ok(!calls.some(c=>c[0]==='arc'||c[0]==='body'));assert.equal(depth,0);
});

test('run phase follows displacement, freezes at walls/during dash, and blends to idle',()=>{
 const {box}=harness();const p=player();
 box.advanceRunAnimation(p,28,0,.1);assert.ok(Math.abs(p.artRunPhase-.25)<1e-8);
 const phase=p.artRunPhase;box.advanceRunAnimation(p,0,0,.1);assert.equal(p.artRunPhase,phase);
 p.dashT=.1;box.advanceRunAnimation(p,60,0,.01);assert.equal(p.artRunPhase,phase);
 p.dashT=0;box.advanceRunAnimation(p,-14,0,.1);assert.ok(Math.abs(p.artRunPhase-.125)<1e-8);
 for(let i=0;i<20;i++)box.advanceRunAnimation(p,0,0,.016);
 assert.equal(p.artRunBlend,0);assert.equal(p.artRunPhase,0);
});
test('run previews retain unloaded and unconverted direction fallbacks',()=>{
 const {box,calls}=harness();box.artAnimationPreview=true;
 const p=player();p.artRunBlend=1;p.artRunPhase=.5;
 box.abyssArt.runEast={ready:false,image:{id:'run'}};
 box.drawTexturedAndroid(p);assert.equal(calls.filter(c=>c[0]==='drawImage').length,1);
 assert.equal(box.runAnimationAsset(p,0),null);
 box.abyssArt.runEast.ready=true;assert.ok(box.runAnimationAsset(p,0));
 assert.equal(box.runAnimationAsset(p,6),null);
 calls.length=0;box.drawTexturedAndroid(p);
 const draw=calls.find(c=>c[0]==='drawImage');assert.equal(draw[1].id,'run');assert.equal(draw[2],0);assert.equal(draw[3],160);
 assert.equal(calls.filter(c=>c[0]==='weapon').length,1);
 assert.equal(calls.filter(c=>c[0]==='feedback').length,1);
});
test('preview movement is confined to player one in the hub',()=>{
 const box={artAnimationPreview:true,state:'hub',artPreviewMove:{x:1,y:0},keys:{},joy:{id:-1},padForPlayer:()=>null,p1ArrowsActive:()=>true,p2UsesKeyboard:()=>false,Math};
 vm.createContext(box);const start=html.indexOf('function moveInputFor(');vm.runInContext(html.slice(start,html.indexOf('/* legacy alias',start)),box);
 const read=idx=>JSON.stringify(box.moveInputFor({idx}));
 assert.equal(read(0),' {"x":1,"y":0}'.trim());assert.equal(read(1),'{"x":0,"y":0}');
 box.state='play';assert.equal(read(0),'{"x":0,"y":0}');
 box.state='hub';box.artAnimationPreview=false;assert.equal(read(0),'{"x":0,"y":0}');
});

test('north run clip keeps the authored back direction and preserves reverse gait wrapping',()=>{
 const {box,calls}=harness();box.artAnimationPreview=true;
 box.abyssArt.runNorth={ready:true,image:{id:'north'}};
 const p=player();p.aimDraw=-Math.PI/2;p.artRunBlend=1;p.artRunPhase=.875;
 box.drawTexturedAndroid(p);const draw=calls.find(c=>c[0]==='drawImage');
 assert.equal(draw[1].id,'north');assert.equal(draw[2],480);assert.equal(draw[3],160);
 box.advanceRunAnimation(p,0,28,.1);assert.ok(Math.abs(p.artRunPhase-.625)<1e-8);
 assert.equal(box.runAnimationAsset(p,5),null);
});

test('stopping a preview at the portal cannot unintentionally start a run',()=>{
 const {box}=harness();box.artAnimationPreview=true;box.artPreviewExitArmed=true;
 box.artPreviewMove={x:0,y:-1};box.HUB={exitY:100,exitH:36};
 const p={y:110,r:12};assert.equal(box.previewAllowsDescent(p),false);
 box.artPreviewMove=null;assert.equal(box.previewAllowsDescent(p),false);
 p.y=200;assert.equal(box.previewAllowsDescent(p),true);
 p.y=110;assert.equal(box.previewAllowsDescent(p),true);
 box.artAnimationPreview=false;box.artPreviewExitArmed=false;assert.equal(box.previewAllowsDescent(p),true);
});

test('northeast clip uses its own unmirrored atlas and stays gated in ordinary sessions',()=>{
 const {box,calls}=harness();box.artAnimationPreview=true;
 box.abyssArt.runNorthEast={ready:true,image:{id:'northeast'}};
 const p=player();p.aimDraw=-Math.PI/4;p.artRunBlend=1;p.artRunPhase=.375;
 box.drawTexturedAndroid(p);const draw=calls.find(c=>c[0]==='drawImage');
 assert.equal(p.artFacing,7);assert.equal(draw[1].id,'northeast');assert.equal(draw[2],480);assert.equal(draw[3],0);
 box.artAnimationPreview=false;assert.equal(box.runAnimationAsset(p,7),null);
});


test('pose crossfade adds weighted alpha before a single world draw and reuses its surface',()=>{
 const {box,calls}=harness();let allocations=0,pixelAlpha=0;
 const compositing=[];
 const offscreen={globalAlpha:1,globalCompositeOperation:'source-over',
  clearRect:()=>{pixelAlpha=0;},
  drawImage:()=>{const a=offscreen.globalAlpha;
   pixelAlpha=offscreen.globalCompositeOperation==='lighter'?Math.min(1,pixelAlpha+a):a+pixelAlpha*(1-a);
   compositing.push(offscreen.globalCompositeOperation);
  }};
 const canvas={getContext:()=>offscreen};
 box.document={createElement:()=>{allocations++;return canvas;}};
 box.artAnimationPreview=true;box.abyssArt.runEast={ready:true,image:{}};
 const p=player();p.artRunPhase=.25;p.artRunBlend=.5;
 box.drawTexturedAndroid(p);
 assert.equal(pixelAlpha,1);assert.equal(canvas.width,160);assert.equal(canvas.height,160);
 assert.deepEqual(compositing,['source-over','lighter']);
 assert.equal(calls.filter(c=>c[0]==='drawImage').length,1);
 assert.equal(calls.find(c=>c[0]==='drawImage')[1],canvas);
 assert.equal(calls.filter(c=>c[0]==='weapon').length,1);
 assert.equal(calls.filter(c=>c[0]==='feedback').length,1);
 p.artRunBlend=.2;box.drawTexturedAndroid(p);assert.equal(allocations,1);assert.equal(pixelAlpha,1);
 assert.equal(offscreen.globalAlpha,1);assert.equal(offscreen.globalCompositeOperation,'source-over');
});


test('textured guardian preserves directional and status-dependent barrier rendering',()=>{
 const {box,calls}=harness();box.abyssArt.guardian={ready:true,image:{id:'guardian'}};
 box.spriteDetail=()=>false;box.clamp=(v,a,b)=>Math.max(a,Math.min(b,v));box.glow=()=>{};box.noglow=()=>{};
 const start=html.indexOf('function shieldActive(');
 vm.runInContext(html.slice(start,html.indexOf('/* does a frontal shield',start)),box);
 const e={type:'shield',x:20,y:30,r:17,hp:100,shieldHp:70,shieldMax:70,shieldA:1.2,frozenT:0,phase:0};
 box.drawTexturedEnemy(e,false);
 assert.equal(calls.filter(c=>c[0]==='drawImage').length,1);
 assert.equal(calls.filter(c=>c[0]==='arc').length,2);
 assert.equal(calls.find(c=>c[0]==='rotate')[1],1.2);
 for(const overrides of [{shieldHp:0},{frozenT:1},{shockT:1},{exposeT:1}]){
   calls.length=0;box.drawTexturedEnemy({...e,...overrides},false);
   assert.equal(calls.filter(c=>c[0]==='drawImage').length,1);
   assert.equal(calls.filter(c=>c[0]==='arc').length,1);
 }
 calls.length=0;box.drawTexturedEnemy({...e,shieldA:-2},false);
 assert.equal(calls.find(c=>c[0]==='rotate')[1],-2);
 assert.equal(calls.filter(c=>c[0]==='save').length,calls.filter(c=>c[0]==='restore').length);
});

test('articulated gait alternates support legs, clears the swing foot, and loops continuously',()=>{
 const {box}=harness();
 for(let i=0;i<100;i++) {
  const phase=i/100,L=box.southRigStep(phase,-1,1),R=box.southRigStep(phase,1,1);
  assert.ok(!(L.contact && R.contact));
  for(const step of [L,R]) {assert.ok(step.lift>=0);if(step.contact)assert.equal(step.lift,0);}
  const shifted=box.southRigStep(phase+.5,-1,1);
  assert.ok(Math.abs(shifted.travel-R.travel)<1e-10);
  assert.ok(Math.abs(shifted.lift-R.lift)<1e-10);
 }
 for(const boundary of [0,box.southRigStep(0,-1,1).duty,.5,1]) {
  const before=box.southRigStep(boundary-1e-7,-1,1),after=box.southRigStep(boundary+1e-7,-1,1);
  assert.ok(Math.abs(before.travel-after.travel)<1e-5);
  assert.ok(Math.abs(before.lift-after.lift)<1e-5);
 }
 assert.equal(box.southRigStep(.7,-1,0).lift,0);
 assert.equal(Math.abs(box.southRigStep(.2,1,0).travel),0);
});
test('south rig respects the art switch, waits for its image, and preserves one weapon and feedback pass',()=>{
 const {box,calls}=harness();const p=player();p.aimDraw=Math.PI/2;p.artRunPhase=.7;p.artRunBlend=1;
 box.abyssArt.rigSouth={ready:true,image:{id:'rig'}};
 box.drawTexturedAndroid(p);assert.equal(calls.filter(c=>c[0]==='drawImage'&&c[1].id==='rig').length,0);
 box.rigArtEnabled=true;calls.length=0;box.drawTexturedAndroid(p);
 assert.equal(calls.filter(c=>c[0]==='drawImage'&&c[1].id==='rig').length,11);
 assert.equal(calls.filter(c=>c[0]==='weapon').length,1);assert.equal(calls.filter(c=>c[0]==='feedback').length,1);
 assert.equal(calls.filter(c=>c[0]==='save').length,calls.filter(c=>c[0]==='restore').length);
 for(const c of calls.filter(c=>['scale','rotate','translate'].includes(c[0])))assert.ok(c.slice(1).every(Number.isFinite));
 box.abyssArt.rigSouth.ready=false;calls.length=0;box.drawTexturedAndroid(p);
 assert.equal(calls.filter(c=>c[0]==='drawImage').length,1);
 assert.equal(box.drawSouthRig(.3,1),false);
});

test('rig planted toe stays in one world position through stance at actual actor scales',()=>{
 const {box}=harness();box.abyssArt.rigSouth={ready:true,image:{}};
 for(const radius of [12,13,18]) {
  const scale=radius*4.4/160,duty=box.southRigStep(0,-1,1,scale).duty;
  const positions=[];
  box.drawSouthRigPart=(image,key,x,y,endX,endY)=>{
   if(key==='footL')positions.push({x:endX*scale,y:endY*scale});
  };
  for(let i=1;i<20;i++) {
   const phase=duty*i/20;
   box.drawSouthRig(phase,1,scale);
   positions.at(-1).y+=phase*96;
  }
  const spread=axis=>Math.max(...positions.map(p=>p[axis]))-Math.min(...positions.map(p=>p[axis]));
  assert.ok(spread('y')<1e-9,`planted toe drift at r=${radius}: ${spread('y')}`);
  assert.ok(spread('x')<1e-9);
 }
});
test('rig phase uses its calibrated stride while disabled fallback clips retain theirs',()=>{
 const {box}=harness();box.rigArtEnabled=true;box.abyssArt.rigSouth={ready:true,image:{}};
 const p=player();p.aimDraw=Math.PI/2;box.advanceRunAnimation(p,0,12,.01);
 assert.ok(Math.abs(p.artRunPhase-.125)<1e-9);
 box.rigArtEnabled=false;p.artRunPhase=0;p.aimDraw=0;box.advanceRunAnimation(p,14,0,.01);
 assert.ok(Math.abs(p.artRunPhase-.125)<1e-9);
});

test('chaser atlas draws one body from each of its eight direction cells',()=>{
 const {box,calls}=harness();box.abyssArt.chaser={ready:true,image:{}};
 for(let i=0;i<8;i++) {
  calls.length=0;
  const e={type:'chaser',x:0,y:0,r:14,state:'seek',_tgt:{x:Math.cos(i*Math.PI/4)*100,y:Math.sin(i*Math.PI/4)*100}};
  assert.equal(box.drawTexturedEnemy(e,false),true);
  const draws=calls.filter(c=>c[0]==='drawImage');assert.equal(draws.length,1);
  assert.deepEqual(draws[0].slice(2,6),[(i%4)*128,Math.floor(i/4)*128,128,128]);
 }
});
test('chaser facing follows co-op target but locks to committed lunge and frozen pose',()=>{
 const {box}=harness();box.player={x:-100,y:0};
 const e={x:0,y:0,state:'seek',_tgt:{x:100,y:0},dirX:0,dirY:1};
 assert.equal(box.enemyArtFacing(e),0);
 for(const state of ['wind','lunge']) {e.state=state;assert.equal(box.enemyArtFacing(e),2);}
 e.frozenT=1;e.dirY=-1;assert.equal(box.enemyArtFacing(e),2);
 e.frozenT=0;assert.equal(box.enemyArtFacing(e),6);
 e.state='seek';e._tgt=null;assert.equal(box.enemyArtFacing(e),4);
});
test('unloaded chaser atlas preserves procedural fallback',()=>{
 const {box,calls}=harness();assert.equal(box.drawTexturedEnemy({type:'chaser'},false),false);assert.equal(calls.length,0);
});

test('east rig respects the art switch and falls back while unavailable',()=>{
 const {box}=harness();box.abyssArt.rigEast={ready:true,image:{}};
 assert.equal(box.androidRigKey(0),null);box.rigArtEnabled=true;
 assert.equal(box.androidRigKey(0),'rigEast');assert.equal(box.androidRigKey(4),'rigWest');
 box.abyssArt.rigEast.ready=false;assert.equal(box.androidRigKey(0),null);
});
test('actual east leg renderer preserves bone lengths through running and stopping',()=>{
 const {box}=harness();box.abyssArt.rigEast={ready:true,image:{}};
 const bones=[];
 box.drawSouthRigPart=(image,key,x,y,ex,ey)=>{if(key.startsWith('shin')||key.startsWith('thigh'))bones.push({key,length:Math.hypot(ex-x,ey-y)});};
 for(const blend of [0,.25,.5,.75,1])for(let i=0;i<120;i++) {
  bones.length=0;box.drawEastRig(i/120,blend);
  assert.equal(bones.length,4);
  for(const b of bones)assert.ok(Math.abs(b.length-(b.key.startsWith('thigh')?25.25:27.25))<1e-8);
 }
});
test('east planted foot cancels world movement across supported actor scales',()=>{
 const {box}=harness();box.abyssArt.rigEast={ready:true,image:{}};
 for(const radius of [12,13,18]) {
  const scale=radius*4.4/160,points=[];
  box.drawSouthRigPart=(image,key,x,y,ex,ey)=>{if(key==='footL')points.push({x:ex*scale,y:ey*scale});};
  const duty=box.southRigStep(0,-1,1,scale).duty;
  for(let i=0;i<20;i++) {const phase=duty*i/20;box.drawEastRig(phase,1,scale);points.at(-1).x+=phase*96;}
  for(const axis of ['x','y'])assert.ok(Math.max(...points.map(p=>p[axis]))-Math.min(...points.map(p=>p[axis]))<1e-8);
 }
});
test('east rig renders eleven connected parts with one held weapon and feedback pass',()=>{
 const {box,calls}=harness();box.rigArtEnabled=true;box.abyssArt.rigEast={ready:true,image:{}};
 const p=player();p.artRunPhase=.3;p.artRunBlend=1;box.drawTexturedAndroid(p);
 assert.equal(calls.filter(c=>c[0]==='drawImage').length,11);
 assert.equal(calls.filter(c=>c[0]==='weapon').length,1);
 assert.equal(calls.filter(c=>c[0]==='feedback').length,1);
 box.advanceRunAnimation(p,24,0,.1);assert.ok(Math.abs(p.artRunPhase-.55)<1e-8);
});

test('north rig respects the art switch and renders eleven parts with shared weapon feedback',()=>{
 const {box,calls}=harness();box.abyssArt.rigNorth={ready:true,image:{}};
 assert.equal(box.androidRigKey(6),null);box.rigArtEnabled=true;
 assert.equal(box.androidRigKey(6),'rigNorth');
 const p=player();p.aimDraw=-Math.PI/2;p.artRunPhase=.2;p.artRunBlend=1;
 box.drawTexturedAndroid(p);
 assert.equal(calls.filter(c=>c[0]==='drawImage').length,11);
 assert.equal(calls.filter(c=>c[0]==='weapon').length,1);
 assert.equal(calls.filter(c=>c[0]==='feedback').length,1);
 box.abyssArt.rigNorth.ready=false;assert.equal(box.androidRigKey(6),null);
});
test('north stance cancels negative world Y travel at three actor scales',()=>{
 const {box}=harness();box.abyssArt.rigNorth={ready:true,image:{}};
 for(const radius of [12,13,18]) {
  const scale=radius*4.4/160,points=[];
  box.drawSouthRigPart=(image,key,x,y,ex,ey)=>{if(key==='footL')points.push({x:ex*scale,y:ey*scale});};
  const duty=box.southRigStep(0,-1,1,scale).duty;
  for(let i=0;i<20;i++){const phase=duty*i/20;box.drawNorthRig(phase,1,scale);points.at(-1).y-=phase*96;}
  for(const axis of ['x','y'])assert.ok(Math.max(...points.map(p=>p[axis]))-Math.min(...points.map(p=>p[axis]))<1e-8);
 }
});

test('west rig uses its own atlas without mirroring asymmetric artwork',()=>{
 const {box,calls}=harness();const image={west:true};box.abyssArt.rigWest={ready:true,image};
 assert.equal(box.androidRigKey(4),null);box.rigArtEnabled=true;assert.equal(box.androidRigKey(4),'rigWest');
 const p=player();p.aimDraw=Math.PI;p.artRunPhase=.3;p.artRunBlend=1;box.drawTexturedAndroid(p);
 const draws=calls.filter(c=>c[0]==='drawImage');assert.equal(draws.length,11);
 for(const d of draws)assert.equal(d[1],image);
 for(const c of calls.filter(c=>c[0]==='scale'))assert.ok(c[1]>0&&c[2]>0,'artwork must not be mirrored');
 assert.equal(calls.filter(c=>c[0]==='weapon').length,1);assert.equal(calls.filter(c=>c[0]==='feedback').length,1);
 box.abyssArt.rigWest.ready=false;assert.equal(box.androidRigKey(4),null);
});
test('west stance cancels negative world X travel and retains fixed leg lengths',()=>{
 const {box}=harness();box.abyssArt.rigWest={ready:true,image:{}};
 for(const radius of [12,13,18]) {
  const scale=radius*4.4/160,points=[];
  box.drawSouthRigPart=(image,key,x,y,ex,ey)=>{
   if(key==='footL')points.push({x:ex*scale,y:ey*scale});
   if(key.startsWith('thigh')||key.startsWith('shin'))assert.ok(Math.abs(Math.hypot(ex-x,ey-y)-(key.startsWith('thigh')?25.25:27.25))<1e-8);
  };
  const duty=box.southRigStep(0,-1,1,scale).duty;
  for(let i=0;i<20;i++){const phase=duty*i/20;box.drawWestRig(phase,1,scale);points.at(-1).x-=phase*96;}
  for(const axis of ['x','y'])assert.ok(Math.max(...points.map(p=>p[axis]))-Math.min(...points.map(p=>p[axis]))<1e-8);
 }
});

test('northeast rig draws independent parts and preserves weapon/feedback',()=>{
 const {box,calls}=harness();box.abyssArt.rigNorthEast={ready:true,image:{}};
 assert.equal(box.androidRigKey(7),null);box.rigArtEnabled=true;assert.equal(box.androidRigKey(7),'rigNorthEast');
 const p=player();p.aimDraw=-Math.PI/4;p.artRunPhase=.2;p.artRunBlend=1;box.drawTexturedAndroid(p);
 assert.equal(calls.filter(c=>c[0]==='drawImage').length,11);
 assert.equal(calls.filter(c=>c[0]==='weapon').length,1);assert.equal(calls.filter(c=>c[0]==='feedback').length,1);
 box.abyssArt.rigNorthEast.ready=false;assert.equal(box.androidRigKey(7),null);
});
test('northeast stance locks both world axes and actual leg draws retain bone lengths',()=>{
 const {box}=harness();box.abyssArt.rigNorthEast={ready:true,image:{}};
 for(const radius of [12,13,18]) {
  const scale=radius*4.4/160,points=[];
  box.drawSouthRigPart=(image,key,x,y,ex,ey)=>{
   if(key==='footL')points.push({x:ex*scale,y:ey*scale});
   if(key.startsWith('thigh')||key.startsWith('shin'))assert.ok(Math.abs(Math.hypot(ex-x,ey-y)-(key.startsWith('thigh')?25.25:27.25))<1e-8);
  };
  const duty=box.southRigStep(0,-1,1,scale).duty;
  for(let i=0;i<20;i++){const phase=duty*i/20;box.drawNorthEastRig(phase,1,scale);points.at(-1).x+=phase*96*Math.SQRT1_2;points.at(-1).y-=phase*96*Math.SQRT1_2;}
  for(const axis of ['x','y'])assert.ok(Math.max(...points.map(p=>p[axis]))-Math.min(...points.map(p=>p[axis]))<1e-8);
  for(const blend of [0,.25,.5,.75,1])for(let i=0;i<120;i++)box.drawNorthEastRig(i/120,blend,scale);
 }
});

test('northwest rig preserves its independent asymmetric art without negative image scales',()=>{
 const {box,calls}=harness();const image={northwest:true};box.abyssArt.rigNorthWest={ready:true,image};
 assert.equal(box.androidRigKey(5),null);box.rigArtEnabled=true;assert.equal(box.androidRigKey(5),'rigNorthWest');
 const p=player();p.aimDraw=-3*Math.PI/4;p.artRunPhase=.3;p.artRunBlend=1;box.drawTexturedAndroid(p);
 const draws=calls.filter(c=>c[0]==='drawImage');assert.equal(draws.length,11);for(const d of draws)assert.equal(d[1],image);
 for(const c of calls.filter(c=>c[0]==='scale'))assert.ok(c[1]>0&&c[2]>0);
 assert.equal(calls.filter(c=>c[0]==='weapon').length,1);assert.equal(calls.filter(c=>c[0]==='feedback').length,1);
 box.abyssArt.rigNorthWest.ready=false;assert.equal(box.androidRigKey(5),null);
});
test('northwest planted foot cancels both negative world axes with fixed leg lengths',()=>{
 const {box}=harness();box.abyssArt.rigNorthWest={ready:true,image:{}};
 for(const radius of [12,13,18]) {
  const scale=radius*4.4/160,points=[];
  box.drawSouthRigPart=(image,key,x,y,ex,ey)=>{
   if(key==='footL')points.push({x:ex*scale,y:ey*scale});
   if(key.startsWith('thigh')||key.startsWith('shin'))assert.ok(Math.abs(Math.hypot(ex-x,ey-y)-(key.startsWith('thigh')?25.25:27.25))<1e-8);
  };
  const duty=box.southRigStep(0,-1,1,scale).duty;
  for(let i=0;i<20;i++){const phase=duty*i/20;box.drawNorthWestRig(phase,1,scale);points.at(-1).x-=phase*96*Math.SQRT1_2;points.at(-1).y-=phase*96*Math.SQRT1_2;}
  for(const axis of ['x','y'])assert.ok(Math.max(...points.map(p=>p[axis]))-Math.min(...points.map(p=>p[axis]))<1e-8);
  for(const blend of [0,.25,.5,.75,1])for(let i=0;i<120;i++)box.drawNorthWestRig(i/120,blend,scale);
 }
});

test('southeast rig respects the art switch and renders one articulated body plus shared weapon',()=>{
 const {box,calls}=harness();box.abyssArt.rigSouthEast={ready:true,image:{}};
 assert.equal(box.androidRigKey(1),null);box.rigArtEnabled=true;assert.equal(box.androidRigKey(1),'rigSouthEast');
 const p=player();p.aimDraw=Math.PI/4;p.artRunPhase=.2;p.artRunBlend=1;box.drawTexturedAndroid(p);
 assert.equal(calls.filter(c=>c[0]==='drawImage').length,11);
 assert.equal(calls.filter(c=>c[0]==='weapon').length,1);assert.equal(calls.filter(c=>c[0]==='feedback').length,1);
 box.abyssArt.rigSouthEast.ready=false;assert.equal(box.androidRigKey(1),null);
});
test('southeast stance cancels both positive world axes and preserves leg lengths',()=>{
 const {box}=harness();box.abyssArt.rigSouthEast={ready:true,image:{}};
 for(const radius of [12,13,18]) {
  const scale=radius*4.4/160,points=[];
  box.drawSouthRigPart=(image,key,x,y,ex,ey)=>{
   if(key==='footL')points.push({x:ex*scale,y:ey*scale});
   if(key.startsWith('thigh')||key.startsWith('shin'))assert.ok(Math.abs(Math.hypot(ex-x,ey-y)-(key.startsWith('thigh')?25.25:27.25))<1e-8);
  };
  const duty=box.southRigStep(0,-1,1,scale).duty;
  for(let i=0;i<20;i++){const phase=duty*i/20;box.drawSouthEastRig(phase,1,scale);points.at(-1).x+=phase*96*Math.SQRT1_2;points.at(-1).y+=phase*96*Math.SQRT1_2;}
  for(const axis of ['x','y'])assert.ok(Math.max(...points.map(p=>p[axis]))-Math.min(...points.map(p=>p[axis]))<1e-8);
  for(const blend of [0,.25,.5,.75,1])for(let i=0;i<120;i++)box.drawSouthEastRig(i/120,blend,scale);
 }
});

test('southwest rig respects the art switch and renders one articulated body plus shared weapon',()=>{
 const {box,calls}=harness();box.abyssArt.rigSouthWest={ready:true,image:{}};
 assert.equal(box.androidRigKey(3),null);box.rigArtEnabled=true;assert.equal(box.androidRigKey(3),'rigSouthWest');
 const p=player();p.aimDraw=3*Math.PI/4;p.artRunPhase=.2;p.artRunBlend=1;box.drawTexturedAndroid(p);
 assert.equal(calls.filter(c=>c[0]==='drawImage').length,11);
 assert.equal(calls.filter(c=>c[0]==='weapon').length,1);assert.equal(calls.filter(c=>c[0]==='feedback').length,1);
 box.abyssArt.rigSouthWest.ready=false;assert.equal(box.androidRigKey(3),null);
});
test('southwest stance cancels negative X and positive Y and preserves leg lengths',()=>{
 const {box}=harness();box.abyssArt.rigSouthWest={ready:true,image:{}};
 for(const radius of [12,13,18]) {
  const scale=radius*4.4/160,points=[];
  box.drawSouthRigPart=(image,key,x,y,ex,ey)=>{
   if(key==='footL')points.push({x:ex*scale,y:ey*scale});
   if(key.startsWith('thigh')||key.startsWith('shin'))assert.ok(Math.abs(Math.hypot(ex-x,ey-y)-(key.startsWith('thigh')?25.25:27.25))<1e-8);
  };
  const duty=box.southRigStep(0,-1,1,scale).duty;
  for(let i=0;i<20;i++){const phase=duty*i/20;box.drawSouthWestRig(phase,1,scale);points.at(-1).x-=phase*96*Math.SQRT1_2;points.at(-1).y+=phase*96*Math.SQRT1_2;}
  for(const axis of ['x','y'])assert.ok(Math.max(...points.map(p=>p[axis]))-Math.min(...points.map(p=>p[axis]))<1e-8);
  for(const blend of [0,.25,.5,.75,1])for(let i=0;i<120;i++)box.drawSouthWestRig(i/120,blend,scale);
 }
});

test('all eight weapon grips follow the rendered palm through pose, scale and recoil',()=>{
 const keys=['East','SouthEast','South','SouthWest','West','NorthWest','North','NorthEast'];
 const mul=(a,b)=>[a[0]*b[0]+a[2]*b[1],a[1]*b[0]+a[3]*b[1],a[0]*b[2]+a[2]*b[3],a[1]*b[2]+a[3]*b[3],a[0]*b[4]+a[2]*b[5]+a[4],a[1]*b[4]+a[3]*b[5]+a[5]];
 const point=(m,x,y)=>[m[0]*x+m[2]*y+m[4],m[1]*x+m[3]*y+m[5]];
 for(let dir=0;dir<8;dir++)for(const phase of [0,.27,.71])for(const blend of [0,1])for(const radius of [12,18]) {
  const {box,calls}=harness();box.rigArtEnabled=true;box.abyssArt['rig'+keys[dir]]={ready:true,image:{}};
  const parts=vm.runInContext(keys[dir].toUpperCase()+'_RIG_PARTS.foreR',box);
  const p=player();Object.assign(p,{aimDraw:dir*Math.PI/4+.07,r:radius,artRunPhase:phase,artRunBlend:blend,recoilT:.09});
  if(phase===0){p.slashT=.15;p.slashDur=.25;p.slashAng=p.aimDraw;p.slashSide=-1;}
  p.weapon=phase===.27?{id:'lbow',isBow:true}:phase===.71?{id:'qbow',isBow:true}:{id:'blade'};
  box.drawTexturedAndroid(p);
  let m=[1,0,0,1,0,0],stack=[],palm,grip;
  for(const [op,...v] of calls){
   if(op==='save')stack.push([...m]);else if(op==='restore')m=stack.pop();
   else if(op==='translate')m=mul(m,[1,0,0,1,v[0],v[1]]);
   else if(op==='rotate')m=mul(m,[Math.cos(v[0]),Math.sin(v[0]),-Math.sin(v[0]),Math.cos(v[0]),0,0]);
   else if(op==='scale')m=mul(m,[v[0],0,0,v[1],0,0]);
   else if(op==='drawImage'&&v[1]===parts[0]/2&&v[2]===parts[1]/2)palm=point(m,parts[8]-parts[4],parts[9]-parts[5]);
   else if(op==='weapon')grip=point(m,v[1]+(p.weapon.isBow?(p.weapon.id==='lbow'?10:9):0),v[2]);
  }
  assert.ok(palm&&grip,keys[dir]+' must render a palm and a weapon');
  assert.ok(Math.hypot(palm[0]-grip[0],palm[1]-grip[1])<1e-8,keys[dir]+' grip detached from rendered palm');
 }
});

test('rig feet plant along actual travel for every facing and movement direction',()=>{
 const names=['East','SouthEast','South','SouthWest','West','NorthWest','North','NorthEast'];
 for(const name of names)for(let dir=0;dir<16;dir++)for(const radius of [12,18])for(const amount of [0,.5,1]) {
  const {box}=harness();box.abyssArt['rig'+name]={ready:true,image:{}};
  const motion={x:amount*Math.cos(dir*Math.PI/8),y:amount*Math.sin(dir*Math.PI/8)},scale=radius*4.4/160,points=[];
  box.drawSouthRigPart=(image,key,x,y,ex,ey)=>{
   if(key==='footL')points.push({x:ex*scale,y:ey*scale});
   if(!['South','North'].includes(name)&&(key.startsWith('thigh')||key.startsWith('shin')))
    assert.ok(Math.abs(Math.hypot(ex-x,ey-y)-(key.startsWith('thigh')?25.25:27.25))<1e-8,`${name}/${dir} ${key} overextended`);
  };
  const duty=box.southRigStep(0,-1,1,scale).duty;
  for(let i=0;i<20;i++){
   const phase=duty*i/20;box['draw'+name+'Rig'](phase,1,scale,motion);
   points.at(-1).x+=phase*96*motion.x;points.at(-1).y+=phase*96*motion.y;
  }
  for(const axis of ['x','y'])assert.ok(Math.max(...points.map(p=>p[axis]))-Math.min(...points.map(p=>p[axis]))<1e-8,`${name}/${dir} ${axis} slides`);
  for(const blend of [0,.5,1])for(let i=0;i<60;i++)box['draw'+name+'Rig'](i/60,blend,scale,motion);
 }
});
test('rig phase advances forward while displacement supplies backward or strafe motion',()=>{
 const {box}=harness();box.rigArtEnabled=true;box.abyssArt.rigEast={ready:true,image:{}};
 const p=player();box.advanceRunAnimation(p,-24,0,.1);
 assert.ok(Math.abs(p.artRunPhase-.25)<1e-8);assert.equal(p.artMotion.x,-1);assert.equal(p.artMotion.y,0);
 box.advanceRunAnimation(p,0,-24,.1);assert.ok(Math.abs(p.artRunPhase-.5)<1e-8);assert.ok(Math.abs(p.artMotion.x+Math.exp(-2.4))<1e-8);assert.ok(Math.abs(p.artMotion.y+1-Math.exp(-2.4))<1e-8);
 box.advanceRunAnimation(p,0,0,.1);assert.equal(p.artRunPhase,.5);
 p.dashT=1;box.advanceRunAnimation(p,24,0,.01);assert.equal(p.artRunPhase,.5);assert.ok(Math.abs(p.artMotion.y+1-Math.exp(-2.4))<1e-8);
});

test('direction reversal narrows the stride continuously and converges independent of update rate',()=>{
 const setup=()=>{const {box}=harness();box.rigArtEnabled=true;box.abyssArt.rigEast={ready:true,image:{}};const p=player();box.advanceRunAnimation(p,2,0,1/120);return {box,p};};
 const {box,p}=setup();box.advanceRunAnimation(p,-2,0,1/120);
 assert.ok(p.artMotion.x>.6&&p.artMotion.x<1,'first reverse update must not snap to opposite foot targets');
 assert.equal(p.artMotion.y,0);
 const values=[];
 for(const hz of [30,60,120,240]){
  const {box,p}=setup();for(let i=0;i<hz/2;i++)box.advanceRunAnimation(p,-240/hz,0,1/hz);
  values.push(p.artMotion.x);assert.ok(Math.abs(p.artMotion.x+1)<.006);
 }
 assert.ok(Math.max(...values)-Math.min(...values)<1e-10);
});
test('fully stopped characters restart in the new direction without stale stride or NaNs',()=>{
 const {box}=harness();box.rigArtEnabled=true;box.abyssArt.rigEast={ready:true,image:{}};const p=player();
 box.advanceRunAnimation(p,20,0,.1);box.advanceRunAnimation(p,0,0,.5);
 assert.equal(p.artMotion,null);assert.equal(p.artRunBlend,0);
 box.advanceRunAnimation(p,0,-20,.1);assert.equal(p.artMotion.x,0);assert.equal(p.artMotion.y,-1);
 box.advanceRunAnimation(p,0,0,0);assert.ok(Number.isFinite(p.artRunPhase));assert.equal(p.artMotion.y,-1);
});

test('all rigs render after movement settles and clears the motion vector',()=>{
 const keys=['East','SouthEast','South','SouthWest','West','NorthWest','North','NorthEast'];
 for(let dir=0;dir<8;dir++){
  const {box,calls}=harness();box.rigArtEnabled=true;box.abyssArt['rig'+keys[dir]]={ready:true,image:{}};
  const p=player();p.aimDraw=dir*Math.PI/4;
  box.advanceRunAnimation(p,20,0,.1);box.advanceRunAnimation(p,0,0,.5);
  assert.equal(p.artMotion,null);assert.doesNotThrow(()=>box.drawTexturedAndroid(p));
  assert.equal(calls.filter(c=>c[0]==='drawImage').length,11);
  assert.equal(calls.filter(c=>c[0]==='weapon').length,1);
 }
});

test('articulated ground shadow remains on the actor plane through movement and scaling',()=>{
 const names=['East','SouthEast','South','SouthWest','West','NorthWest','North','NorthEast'];
 for(let dir=0;dir<8;dir++)for(const radius of [12,18])for(const blend of [0,.5,1]){
  const {box,calls}=harness();box.rigArtEnabled=true;box.abyssArt['rig'+names[dir]]={ready:true,image:{}};
  const p=player();Object.assign(p,{aimDraw:dir*Math.PI/4,r:radius,artRunBlend:blend,artMotion:{x:0,y:-1}});
  box.drawTexturedAndroid(p);const shadow=calls.find(c=>c[0]==='ellipse');
  assert.equal(shadow[1],p.x);assert.equal(shadow[2],p.y);
  assert.equal(shadow[3],p.r*.85);assert.equal(shadow[4],p.r*.32);
  assert.ok(Number.isFinite(box.rigGroundLevel('rig'+names[dir],blend,p.artMotion)));
 }
 const {box,calls}=harness();const p=player();box.drawTexturedAndroid(p);
 assert.equal(calls.find(c=>c[0]==='ellipse')[2],p.y+p.r*.6,'original sprite shadow remains unchanged');
});

test('melee pose follows committed sweep timing, thrust direction and recovery',()=>{
 const {box}=harness(),p=player(),pose={recoil:0,draw:0};Object.assign(p,{slashDur:.25,slashT:.15,slashAng:1,slashSide:-1});
 const a=box.rigAttackPose(p,{id:'blade'},pose);assert.ok(a.amount>.99);assert.ok(Math.abs(a.angle-(1-Math.PI*(.4*2.4-.5)))<1e-8);
 assert.equal(box.rigAttackPose(p,{id:'lance'},pose).angle,1);
 p.slashT=.25;assert.equal(box.rigAttackPose(p,{id:'blade'},pose),null);
 p.slashT=0;assert.equal(box.rigAttackPose(p,{id:'blade'},pose),null);
 p.glaiveOut=true;assert.equal(box.rigAttackPose(p,{id:'glaive'},{recoil:1,draw:0}),null);
});
test('combat arm solve stays connected and finite across all aim angles',()=>{
 const {box}=harness();
 for(const direction of [-1,1])for(let i=0;i<360;i++){
  const p=box.rigArmAction(95,44,100,65,106,84,{amount:1,angle:i*Math.PI/180},direction);
  assert.ok(Math.abs(Math.hypot(p.ex-95,p.ey-44)-22)<1e-8);
  assert.ok(Math.abs(Math.hypot(p.wx-p.ex,p.wy-p.ey)-22)<1e-8);
 }
 const rest=box.rigArmAction(95,44,100,65,106,84,{amount:0,angle:Math.PI},1);
 assert.equal(rest.ex,100);assert.equal(rest.ey,65);assert.equal(rest.wx,106);assert.equal(rest.wy,84);
});

test('full-circle melee recovery does not flip at the aim angle wrap boundary',()=>{
 const {box}=harness();box.meleeArcNow=()=>Math.PI*2;
 const p=player();Object.assign(p,{slashT:.04,slashDur:.25,slashAng:0,slashSide:1});
 const angles=[];for(const aim of [-.00001,.00001]){p.aimDraw=aim;angles.push(box.rigAttackPose(p,{id:'maul'},{recoil:0,draw:0}).angle);}
 assert.ok(Math.abs(angles[1]-angles[0])<.0001);
});

test('attack arc uses the drawing actor rather than the previous co-op actor context',()=>{
 const start=html.indexOf('function meleeArcNow('),end=html.indexOf('\nfunction ',start+20);
 const box={TAU:Math.PI*2,CONFIG:{meleeArc:2},Math,weaponDefP:p=>p?.weapon||{id:'maul'},boonPow:()=>99};vm.createContext(box);vm.runInContext(html.slice(start,end),box);
 assert.ok(Math.abs(box.meleeArcNow({weapon:{id:'blade',arcMul:.8},boonPow:{arc:2}})-2*1.7*.8)<1e-8);
 assert.equal(box.meleeArcNow({weapon:{id:'maul',arcMul:1}}),Math.PI*2);
 assert.equal(box.meleeArcNow(),Math.PI*2);
});

test('normal gameplay enables the entire eight-direction rig set atomically',()=>{
 const declaration=html.match(/const rigArtEnabled = ([^;]+);/)[1];
 assert.equal(vm.runInNewContext(declaration,{profileQuery:new URLSearchParams()}),true);
 assert.equal(vm.runInNewContext(declaration,{profileQuery:new URLSearchParams('rigs=0')}),false);
 const {box,calls}=harness();box.rigArtEnabled=true;
 assert.equal(box.artAnimationPreview,false);assert.equal(box.southRigPreviewEnabled,false);
 const keys=['East','SouthEast','South','SouthWest','West','NorthWest','North','NorthEast'];
 for(const missing of keys){
  box.abyssArt['rig'+missing].ready=false;
  for(let i=0;i<8;i++)assert.equal(box.androidRigKey(i),null);
  box.abyssArt['rig'+missing].ready=true;
 }
 for(let i=0;i<8;i++){
  assert.equal(box.androidRigKey(i),'rig'+keys[i]);calls.length=0;
  const p=player();p.aimDraw=i*Math.PI/4;box.drawTexturedAndroid(p);
  assert.equal(calls.filter(c=>c[0]==='drawImage').length,11);
 }
});

test('normal player movement advances rendered gait after collision resolution in all eight directions',()=>{
 const movement=html.slice(html.indexOf('  const artPrevX = p.x, artPrevY = p.y;'),html.indexOf('  for (const tr of p.trail) tr.t -= dt;'));
 assert.ok(movement.includes('collidePillars(p)')&&movement.includes('separatePlayers(p)'));
 const {box,calls}=harness();box.rigArtEnabled=true;box.artAnimationPreview=false;
 box.collidePillars=()=>{};box.collideArena=()=>{};box.separatePlayers=()=>{};
 vm.runInContext('function movePlayerForCheck(p,dt){'+movement+'}',box);
 for(let direction=0;direction<8;direction++)for(const idx of [0,1]){
  const angle=direction*Math.PI/4,p={...player(),idx,aimDraw:angle,vx:Math.cos(angle)*252,vy:Math.sin(angle)*252};
  box.drawTexturedAndroid(p);const idle=calls.filter(c=>c[0]==='rotate').map(c=>c[1]);calls.length=0;
  box.movePlayerForCheck(p,.016);
  assert.ok(p.artRunPhase>0,`normal direction ${direction}, player ${idx+1} did not advance`);
  assert.ok(p.artRunBlend>0);assert.ok(Math.abs(p.artMotion.x-Math.cos(angle))<1e-10);
  box.drawTexturedAndroid(p);assert.equal(calls.filter(c=>c[0]==='drawImage').length,11);
  assert.notDeepEqual(calls.filter(c=>c[0]==='rotate').map(c=>c[1]),idle);calls.length=0;
  const phase=p.artRunPhase,previous={x:p.x,y:p.y};
  box.collideArena=p=>Object.assign(p,previous);box.movePlayerForCheck(p,.016);
  assert.equal(p.artRunPhase,phase,'blocked movement must not advance feet');
  box.collideArena=()=>{};p.dashT=.1;box.movePlayerForCheck(p,.016);assert.equal(p.artRunPhase,phase,'dash must not drive a running stride');
  p.dashT=0;p.vx=p.vy=0;for(let i=0;i<30;i++)box.movePlayerForCheck(p,.016);
  assert.equal(p.artRunBlend,0);assert.equal(p.artRunPhase,0);
 }
});

test('textured bomber keeps live fuse countdown and unloaded fallback',()=>{
 const {box,calls}=harness();
 const e={type:'bomber',state:'fuse',x:20,y:30,r:12,t:.4,phase:0};
 assert.equal(box.drawTexturedEnemy(e,false),false);assert.equal(calls.length,0);
 box.abyssArt.bomber={ready:true,image:{}};
 assert.equal(box.drawTexturedEnemy(e,false),true);
 assert.equal(calls.filter(c=>c[0]==='drawImage').length,1);
 const arc=calls.find(c=>c[0]==='arc');assert.ok(Math.abs(arc[5]-(-Math.PI/2+Math.PI*2*.6))<1e-8);
 calls.length=0;e.state='chase';box.drawTexturedEnemy(e,false);
 assert.equal(calls.filter(c=>c[0]==='arc').length,0);
});

test('medic beam survives textured bodies and only runs in the ground pass',()=>{
 const calls=[];
 const ctx=new Proxy({}, {get(o,k){return k in o ? o[k] : (...args)=>calls.push([k,...args]);}});
 const box={ctx,Math,TAU:Math.PI*2,timeNow:0,player:null,spriteDetail:()=>false,
 clamp:(v,a,b)=>Math.max(a,Math.min(b,v)),glow:()=>{},noglow:()=>{},
 drawTexturedEnemy:()=>true,enemyLabelTop:()=>-26};
 vm.createContext(box);const start=html.indexOf('function drawEnemy(');
 vm.runInContext(html.slice(start,html.indexOf('/* the held weapon',start)),box);
 const e={type:'medic',state:'chase',x:0,y:0,r:11,col:'#6fc',hp:24,maxHp:24,healTgt:{x:100,y:80,hp:10}};
 box.drawEnemy(e,'telegraph');assert.ok(calls.some(c=>c[0]==='lineTo'&&c[1]===100&&c[2]===80));
 calls.length=0;box.drawEnemy(e,'body');assert.ok(!calls.some(c=>c[0]==='lineTo'));
 calls.length=0;e.healTgt.hp=0;box.drawEnemy(e,'telegraph');assert.ok(!calls.some(c=>c[0]==='lineTo'));
});

test('stationary textured pylon does not bob and mortar charge stays live',()=>{
 const {box,calls}=harness();box.abyssArt.totem={ready:true,image:{}};box.abyssArt.lobber={ready:true,image:{}};
 const e={type:'totem',x:0,y:0,r:15,phase:1};
 box.drawTexturedEnemy(e,false);const y=calls.find(c=>c[0]==='drawImage')[3];
 calls.length=0;box.timeNow=2;box.drawTexturedEnemy(e,false);
 assert.equal(calls.find(c=>c[0]==='drawImage')[3],y);
 calls.length=0;e.type='lobber';e.state='lob';e.t=.1;box.drawTexturedEnemy(e,false);
 assert.equal(calls.filter(c=>c[0]==='stroke').length,1);
 calls.length=0;e.state='chase';box.drawTexturedEnemy(e,false);assert.equal(calls.filter(c=>c[0]==='stroke').length,0);
});

test('all twelve ordinary enemy types resolve to embedded textures',()=>{
 const {box}=harness();
 for(const type of ['chaser','shooter','tank','swarmer','bomber','shield','medic','phantom','blinker','bulwark','lobber','totem']) {
  const key=box.enemyTextureKey({type});assert.ok(key,type);
  assert.ok(html.includes('"'+key+'":"data:image/webp;base64,'),type);
 }
});
test('swarm heading follows travel, holds when stopped and locks while frozen',()=>{
 const {box,calls}=harness();box.abyssArt.swarmer={ready:true,image:{}};
 const e={type:'swarmer',x:0,y:0,r:8,vx:0,vy:100};box.drawTexturedEnemy(e,false);
 assert.equal(e.artHeading,Math.PI/2);assert.ok(calls.some(c=>c[0]==='rotate'&&c[1]===Math.PI/2));
 e.vy=0;box.drawTexturedEnemy(e,false);assert.equal(e.artHeading,Math.PI/2);
 e.vx=-100;e.frozenT=1;box.drawTexturedEnemy(e,false);assert.equal(e.artHeading,Math.PI/2);
 e.frozenT=0;box.drawTexturedEnemy(e,false);assert.equal(e.artHeading,Math.PI);
});
test('textured bulwark shield uses live angle, health and frozen state',()=>{
 const {box,calls}=harness();box.abyssArt.bulwark={ready:true,image:{}};
 box.clamp=(v,a,b)=>Math.max(a,Math.min(b,v));box.glow=()=>{};box.noglow=()=>{};
 box.shieldActive=e=>e.shieldHp>0&&!e.frozenT;
 const e={type:'bulwark',x:0,y:0,r:18,shieldA:1.2,shieldHp:50,shieldMax:50};
 box.drawTexturedEnemy(e,false);assert.ok(calls.some(c=>c[0]==='rotate'&&c[1]===1.2));assert.equal(box.ctx.lineWidth,6);
 e.frozenT=1;box.drawTexturedEnemy(e,false);assert.equal(box.ctx.lineWidth,3);
 e.frozenT=0;e.shieldHp=0;box.drawTexturedEnemy(e,false);assert.equal(box.ctx.lineWidth,3);
});

test('textured reactor bosses retain phase feedback exactly once',()=>{
 const {box,calls}=harness();box.drawBossPhaseAuras=e=>calls.push(['phase',e.kind]);
 for(const kind of ['warden','summoner','overseer']) {
  box.abyssArt[kind]={ready:true,image:{}};calls.length=0;
  assert.equal(box.drawTexturedEnemy({type:'boss',kind,x:0,y:0,r:40,rot:0,state:'move',t:0},false),true);
  assert.equal(calls.filter(c=>c[0]==='phase').length,1);assert.equal(calls.filter(c=>c[0]==='drawImage').length,1);
 }
});
test('overseer tracking pupil narrows during sweep and summoner shards expand while casting',()=>{
 const {box,calls}=harness();
 const e={x:0,y:0,r:36,rot:0,state:'move',t:0,_tgt:{x:100,y:0}};
 box.drawTexturedBossMechanics(e,'overseer',120,0);const idle=calls.find(c=>c[0]==='ellipse');assert.ok(idle[1]>0);
 calls.length=0;e.state='sweep';e.t=.02;e._tgt.x=-100;
 box.drawTexturedBossMechanics(e,'overseer',120,0);const cast=calls.find(c=>c[0]==='ellipse');assert.ok(cast[1]<0);assert.ok(cast[3]<idle[3]);
 calls.length=0;e.state='move';box.drawTexturedBossMechanics(e,'summoner',120,0);
 const orbit=calls.filter(c=>c[0]==='translate')[1][1];
 calls.length=0;e.state='summon';e.t=.02;box.drawTexturedBossMechanics(e,'summoner',120,0);
 assert.ok(calls.filter(c=>c[0]==='translate')[1][1]>orbit);
});

test('splitter texture deforms along its committed axis and preserves generation nuclei',()=>{
 const {box,calls}=harness(),asset={image:{}};
 const e={x:0,y:0,r:52,rot:0,dirX:0,dirY:1,state:'wind',t:0,gen:0};
 box.drawTexturedSplitBody(e,asset,160,0);
 assert.equal(calls.find(c=>c[0]==='rotate')[1],Math.PI/2);
 const scale=calls.find(c=>c[0]==='scale');assert.equal(scale[1],1.25);assert.ok(Math.abs(scale[2]-.82)<1e-12);
 assert.equal(calls.filter(c=>c[0]==='ellipse').length,3);
 calls.length=0;e.gen=1;e.frozenT=1;e.state='move';e.rot=1;
 box.drawTexturedSplitBody(e,asset,115.2,0);
 assert.deepEqual(calls.find(c=>c[0]==='scale'),['scale',1,1]);assert.equal(calls.filter(c=>c[0]==='ellipse').length,2);
 assert.equal(calls.find(c=>c[0]==='drawImage')[4],115.2);
});
test('hexweaver keeps two expanding cast glyphs around its textured body',()=>{
 const {box,calls}=harness();const e={x:0,y:0,r:38,rot:0,state:'move'};
 box.drawTexturedBossMechanics(e,'hexweaver',124,0);const idle=calls.find(c=>c[0]==='moveTo')[2];assert.equal(calls.filter(c=>c[0]==='stroke').length,2);
 calls.length=0;e.state='runes';e.t=0;box.drawTexturedBossMechanics(e,'hexweaver',124,0);
 assert.ok(Math.abs(calls.find(c=>c[0]==='moveTo')[2])>Math.abs(idle));
});

test('juggernaut armor textures follow live plate count without changing combat state',()=>{
 const {box,calls}=harness(),asset={image:{}};
 const e={x:0,y:0,r:48,plates:4,state:'move',t:0,hp:100,maxHp:100};
 for(const plates of [4,3,2,1,0]) {
  e.plates=plates;calls.length=0;const before=JSON.stringify(e);
  box.drawTexturedJuggernaut(e,asset,156,0);
  const draws=calls.filter(c=>c[0]==='drawImage');
  assert.equal(draws.length,1+plates);
  for(const c of draws){assert.ok(c[2]>=0&&c[2]+c[4]<=768);assert.ok(c[3]>=0&&c[3]+c[5]<=512);}
  assert.equal(JSON.stringify(e),before);
 }
 calls.length=0;e.plates=4;e.state='slam';e.t=0;
 box.drawTexturedJuggernaut(e,asset,156,0);
 assert.ok(calls.find(c=>c[0]==='scale')[2]<1);
 assert.ok(calls.some(c=>c[0]==='ellipse'));
});
test('juggernaut retains unloaded fallback, phase feedback and a grounded chassis',()=>{
 const {box,calls}=harness();box.drawBossPhaseAuras=()=>calls.push(['phase']);
 const e={type:'boss',kind:'juggernaut',x:20,y:30,r:48,plates:4,state:'move',t:0};
 assert.equal(box.drawTexturedEnemy(e,false),false);assert.equal(calls.length,0);
 box.abyssArt.juggernaut={ready:true,image:{}};
 assert.equal(box.drawTexturedEnemy(e,false),true);
 assert.equal(calls.filter(c=>c[0]==='phase').length,1);
 const position=calls.find(c=>c[0]==='translate');calls.length=0;box.timeNow=1.5;
 box.drawTexturedEnemy(e,false);assert.deepEqual(calls.find(c=>c[0]==='translate'),position);
 assert.ok(html.includes('"juggernaut":"data:image/webp;base64,'));
});

test('all boss archetypes resolve to embedded textures',()=>{
 const {box}=harness();
 for(const kind of ['abyss','warden','summoner','overseer','splitter','hexweaver','juggernaut','artillery']) {
  const key=box.enemyTextureKey({type:'boss',kind});assert.ok(key,kind);
  assert.ok(html.includes('"'+key+'":"data:image/webp;base64,'),kind);
 }
});
test('artillery barrel axis matches committed aim for every direction and holds during recoil',()=>{
 const {box}=harness();
 for(let i=0;i<64;i++) {
  const a=i*Math.PI/32,e={x:0,y:0,state:'aim',t:.2,dirX:Math.cos(a),dirY:Math.sin(a),_tgt:{x:-100,y:1}};
  const pose=box.artilleryCannonPose(e,124),p=pose.points;
  const authored=Math.atan2(p[3]-p[1],p[2]-p[0]);
  assert.ok(Math.abs(Math.cos(authored+pose.angle)-Math.cos(a))<1e-10);
  assert.ok(Math.abs(Math.sin(authored+pose.angle)-Math.sin(a))<1e-10);
  assert.ok(Math.abs(Math.atan2(Math.sin(a-pose.facing*Math.PI/4),Math.cos(a-pose.facing*Math.PI/4)))<=Math.PI/8+1e-10);
  e.state='move';e.artRecoilT=.18;e.artShotA=a;
  assert.ok(Math.abs(Math.cos(box.artilleryCannonPose(e,124).a)-Math.cos(a))<1e-10);
  e.artRecoilT=0;assert.equal(box.artilleryCannonPose(e,124).a,Math.atan2(1,-100));
 }
});
test('artillery fallback and painted bearing remain stable with independent cannon recoil',()=>{
 const {box,calls}=harness();box.drawBossPhaseAuras=()=>calls.push(['phase']);
 const e={type:'boss',kind:'artillery',x:10,y:20,r:38,state:'move',dirX:1,dirY:0};
 assert.equal(box.drawTexturedEnemy(e,false),false);assert.equal(calls.length,0);
 box.abyssArt.artillery={ready:true,image:{}};box.drawTexturedEnemy(e,false);
 const body=calls.find(c=>c[0]==='drawImage'),bearing=calls.filter(c=>c[0]==='translate').at(-1);
 assert.equal(calls.filter(c=>c[0]==='drawImage').length,2);assert.equal(calls.filter(c=>c[0]==='phase').length,1);
 calls.length=0;e.artRecoilT=.18;e.artShotA=0;box.timeNow=3;box.drawTexturedEnemy(e,false);
 assert.deepEqual(calls.find(c=>c[0]==='drawImage'),body);
 assert.ok(calls.filter(c=>c[0]==='translate').at(-1)[1]<bearing[1]);
});
test('artillery recoil starts only on a real shot and decays in simulation time',()=>{
 const bolts=[],e={x:0,y:0,r:38,state:'aim',t:.1,cd:0,rot:0,vx:0,vy:0,dirX:1,dirY:0,sub:0,tier:0,_tgt:{x:0,y:100}};
 const box={Math,player:null,bossPhaseTick:()=>1,fireEbolt:(...a)=>bolts.push(a),audio:{bolt(){}},shake(){},enemyContact(){},rand:a=>a,angTo:(x,y,a,b)=>Math.atan2(b-y,a-x)};
 vm.createContext(box);const start=html.indexOf('function updateBossArtillery(');
 vm.runInContext(html.slice(start,html.indexOf('/* --- MITOSIS PRIME:',start)),box);
 box.updateBossArtillery(e,.05,100);assert.equal(e.artRecoilT,0);assert.equal(bolts.length,0);
 box.updateBossArtillery(e,.06,100);assert.equal(bolts.length,1);assert.equal(e.artRecoilT,.18);assert.equal(e.artShotA,0);
 e.state='aim';e.t=.2;box.updateBossArtillery(e,.04,100);assert.ok(Math.abs(e.artRecoilT-.14)<1e-10);assert.equal(bolts.length,1);
});

test('foot trajectory matches velocity through toe-off, recovery and touchdown',()=>{
 const {box}=harness(),h=1e-7;
 for(const radius of [12,13,18]) {
  const scale=radius*4.4/160,duty=box.southRigStep(0,-1,1,scale).duty;
  const step=u=>box.southRigStep(u,-1,1,scale);
  for(const boundary of [0,duty,duty*1.08,1-duty*.08,1]) {
   const before=step(boundary-h),at=step(boundary),after=step(boundary+h);
   for(const axis of ['travel','lift']) {
    const incoming=(at[axis]-before[axis])/h,outgoing=(after[axis]-at[axis])/h;
    assert.ok(Math.abs(incoming-outgoing)<.005,`${radius}, ${boundary}, ${axis}: ${incoming} -> ${outgoing}`);
   }
  }
  for(let i=0;i<1000;i++) {
   const p=step(i/1000);assert.ok(Math.abs(p.travel)<=1.081);assert.ok(p.lift>=0&&p.lift<=1);
  }
 }
});

test('cover atlas preserves unloaded, unknown and temporary ward fallbacks',()=>{
 const {box,calls}=harness();box.players=[];
 for(const kind of ['cargo','machinery','reactor','conduit','crystal','shard']) {
  const p={kind,x:0,y:0,r:40};assert.equal(box.drawTexturedObstacle(p),false);
 }
 assert.equal(calls.length,0);box.abyssArt.coverProps={ready:true,image:{}};
 for(const kind of ['cargo','machinery','reactor','conduit','crystal','shard']) {
  const p={kind,x:10,y:20,r:40};calls.length=0;
  assert.equal(box.drawTexturedObstacle(p),true);const draw=calls.find(c=>c[0]==='drawImage');
  assert.ok(draw[2]>=0&&draw[2]+draw[4]<=768);assert.ok(draw[3]>=0&&draw[3]+draw[5]<=512);
  assert.deepEqual([p.x,p.y,p.r,p.kind],[10,20,40,kind]);
 }
 for(const p of [{kind:'cargo',ttl:1},{kind:'cargo',ttl:0},{kind:'unknown'},{}])assert.equal(box.drawTexturedObstacle(p),false);
});
test('cover fades only for a living or downed player behind it, with time-based recovery',()=>{
 const {box}=harness();box.abyssArt.coverProps={ready:true,image:{}};
 box.characterGroundY=e=>e.y+e.r*.6;box.players=[];
 const p={kind:'crystal',x:0,y:0,r:40};box.drawTexturedObstacle(p);assert.equal(p.artCoverAlpha,1);
 const actor={x:0,y:-60,r:13,hp:100};box.players=[actor];box.timeNow=.1;box.drawTexturedObstacle(p);
 assert.ok(p.artCoverAlpha>.42&&p.artCoverAlpha<.6);const low=p.artCoverAlpha;
 actor.y=80;box.timeNow=.2;box.drawTexturedObstacle(p);assert.ok(p.artCoverAlpha>low&&p.artCoverAlpha<1);
 const alpha=(hp,downed)=>{box.players=[{x:0,y:-60,r:13,hp,downed}];const prop={kind:'crystal',x:0,y:0,r:40};box.drawTexturedObstacle(prop);return prop.artCoverAlpha;};
 assert.equal(alpha(0,false),1);assert.equal(alpha(0,true),.42);assert.equal(alpha(100,false),.42);
 const atRate=dt=>{box.timeNow=0;box.players=[];const prop={kind:'crystal',x:0,y:0,r:40};box.drawTexturedObstacle(prop);box.players=[{x:0,y:-60,r:13,hp:100}];for(let t=dt;t<.16+1e-8;t+=dt){box.timeNow=t;box.drawTexturedObstacle(prop);}return prop.artCoverAlpha;};
 assert.ok(Math.abs(atRate(.016)-atRate(.032))<1e-10);
});
test('cover bodies share actor depth ordering while warnings and status retain their passes',()=>{
 const events=[],behind={id:'behind',x:0,y:10,r:10,hp:100},near={id:'near',x:0,y:40,r:10};
 const wall={id:'wall',kind:'cargo',x:0,y:25,r:10},ward={id:'ward',kind:'cargo',ttl:1,x:0,y:0,r:10},culled={id:'culled',kind:'cargo',x:999,y:0,r:10};
 const pillars=[wall,ward,culled],enemies=[near],players=[behind];
 const box={pillars,enemies,players,numPlayers:1,inView:x=>x!==999,texturedObstacleAsset:p=>p.ttl===undefined,
 drawTexturedObstacle:p=>events.push('cover:'+p.id),drawEnemy:(e,layer)=>events.push(layer+':'+e.id),drawOnePlayer:p=>events.push('body:'+p.id),drawPlayerTrails:()=>events.push('trails')};
 vm.createContext(box);vm.runInContext(html.slice(html.indexOf('const characterDrawList ='),html.indexOf('function drawPlayerTrails()')),box);
 box.drawCharacterLayers();assert.deepEqual(events,['telegraph:near','trails','body:behind','cover:wall','body:near','status:near']);
 assert.deepEqual(pillars,[wall,ward,culled]);assert.deepEqual(enemies,[near]);assert.deepEqual(players,[behind]);
 events.length=0;pillars.length=0;box.drawCharacterLayers();assert.ok(!events.some(x=>x.startsWith('cover:')));
});
test('ground pass paints one cover shadow and defers only decoded bodies',()=>{
 const {box,calls}=harness();box.pillars=[{kind:'cargo',x:10,y:20,r:40}];box.spriteDetail=()=>false;box.inView=()=>true;
 box.obstacleShadow=()=>calls.push(['shadow']);box.drawObstacleBody=()=>calls.push(['fallback']);
 vm.runInContext(html.slice(html.indexOf('function drawPillars()'),html.indexOf('function drawDoors()')),box);
 box.drawPillars();assert.deepEqual(calls.filter(c=>['shadow','fallback'].includes(c[0])),[['shadow'],['fallback']]);
 calls.length=0;box.abyssArt.coverProps={ready:true,image:{}};box.drawPillars();
 assert.equal(calls.filter(c=>c[0]==='shadow').length,1);assert.equal(calls.filter(c=>['drawImage','fallback'].includes(c[0])).length,0);
});

test('swarmer gait follows resolved distance, stops at walls and locks during stun',()=>{
 const {box}=harness();const make=()=>({type:'swarmer',r:8,artStride:.2,artHeading:0});
 const e=make();box.advanceSwarmerGait(e,2,0,.02);assert.ok(e.artStride>.2);
 const stride=e.artStride;box.advanceSwarmerGait(e,0,0,.02);assert.equal(e.artStride,stride);
 box.advanceSwarmerGait(e,0,2,.02,true);assert.equal(e.artStride,stride);assert.equal(e.artHeading,0);
 box.advanceSwarmerGait(e,1000,0,.02);assert.equal(e.artStride,stride);
 const a=make(),b=make();for(let i=0;i<10;i++)box.advanceSwarmerGait(a,1,0,.01);for(let i=0;i<5;i++)box.advanceSwarmerGait(b,2,0,.02);
 assert.ok(Math.abs(a.artStride-b.artStride)<1e-12);
 for(let i=0;i<8;i++){const e={type:'swarmer',r:8};box.advanceSwarmerGait(e,Math.cos(i*Math.PI/4),Math.sin(i*Math.PI/4),.016);assert.ok(Math.abs(e.artHeading-i*Math.PI/4)<1e-12||Math.abs(e.artHeading-i*Math.PI/4+Math.PI*2)<1e-12);}
});
test('swarmer feet plant during straight travel and have continuous contact velocity',()=>{
 const {box}=harness(),r=8,h=1e-6,cycleDistance=r*1.8/.62;
 for(const phase of [.1,.3,.55]){
  const a=box.swarmerFoot(phase,1,1,r),b=box.swarmerFoot(phase+h,1,1,r);
  assert.ok(Math.abs((b.x-a.x)/h+cycleDistance)<1e-6);assert.equal(a.lift,0);
 }
 for(const phase of [0,.62]){
  const left=box.swarmerFoot(phase-h,1,1,r),mid=box.swarmerFoot(phase,1,1,r),right=box.swarmerFoot(phase+h,1,1,r);
  assert.ok(Math.abs((mid.x-left.x)/h-(right.x-mid.x)/h)<.001);
  assert.ok(Math.abs((mid.y-left.y)/h-(right.y-mid.y)/h)<.001);
 }
 for(let i=0;i<100;i++)for(const front of [-1,1])for(const side of [-1,1]){
  const foot=box.swarmerFoot(i/100,front,side,r),hx=front*r*.2,hy=side*r*.28,k=box.swarmerKnee(hx,hy,foot.x,foot.y,side,r);
  assert.ok(Math.abs(Math.hypot(k.x-hx,k.y-hy)-r*.85)<1e-10);
  assert.ok(Math.abs(Math.hypot(k.x-foot.x,k.y-foot.y)-r*.85)<1e-10);
 }
});
test('swarmer articulated renderer uses nine bounded crops and does not advance simulation',()=>{
 const {box,calls}=harness();const e={type:'swarmer',x:0,y:0,r:8,artStride:.3,artHeading:1};
 assert.equal(box.drawArticulatedSwarmer(e),false);assert.equal(calls.length,0);
 box.abyssArt.swarmerRig={ready:true,image:{}};const before=JSON.stringify(e);
 assert.equal(box.drawArticulatedSwarmer(e),true);assert.equal(JSON.stringify(e),before);
 const draws=calls.filter(c=>c[0]==='drawImage');assert.equal(draws.length,9);
 for(const d of draws){assert.ok(d[2]>=0&&d[2]+d[4]<=768);assert.ok(d[3]>=0&&d[3]+d[5]<=512);}
});

test('ground decals cover all biome palettes and preserve unsupported fallbacks',()=>{
 const {box,calls}=harness();box.arenaBiomeIdx=0;const pal={liquid:{rim:'#448899'}};
 const f={kind:'lake',x:10,y:20,r:80,shallow:false};assert.equal(box.drawTexturedTerrain(f,pal),false);
 box.abyssArt.groundDecals={ready:true,image:{}};
 for(let biome=0;biome<5;biome++){
  box.arenaBiomeIdx=biome;assert.equal(box.terrainTextureCell(f,biome),[0,1,2,3,1][biome]);
  for(const kind of ['lake','rock']){
   calls.length=0;const prop={...f,kind,rot:.3};const before=JSON.stringify(prop);assert.equal(box.drawTexturedTerrain(prop,pal),true);assert.equal(JSON.stringify(prop),before);
   const draws=calls.filter(c=>c[0]==='drawImage');assert.equal(draws.length,1);const d=draws[0];assert.ok(d[2]>=0&&d[2]+d[4]<=768&&d[3]>=0&&d[3]+d[5]<=512);
  }
 }
 assert.equal(box.drawTexturedTerrain({...f,kind:'plant'},pal),false);assert.equal(box.terrainTextureCell({kind:'rock',crystal:true},0),5);
});
test('only shallow water shows its exact circular slow boundary',()=>{
 const {box,calls}=harness();const pal={liquid:{rim:'#448899'}},f={kind:'lake',x:10,y:20,r:80,shallow:true};
 box.drawShallowPoolCue(f,pal);const arc=calls.find(c=>c[0]==='arc');assert.deepEqual(arc.slice(1,4),[10,20,80*.82]);
 calls.length=0;box.drawShallowPoolCue({...f,shallow:false},pal);box.drawShallowPoolCue({...f,kind:'rock'},pal);assert.equal(calls.length,0);
 box.terrain=[f];box.dist=(x,y,a,b)=>Math.hypot(x-a,y-b);
 vm.runInContext(html.slice(html.indexOf('function terrainSlowFactor('),html.indexOf('/* REGION-WEIGHTED enemy pick:')),box);
 assert.equal(box.terrainSlowFactor(10,20,false),.82);assert.equal(box.terrainSlowFactor(10+80*.82+.01,20,false),1);assert.equal(box.terrainSlowFactor(10,20,true),1);
});
test('both desktop and touch-off terrain paths use decals with unloaded fallback',()=>{
 const {box}=harness();box.terrain=[{kind:'lake',x:0,y:0,r:80},{kind:'rock',x:200,y:0,r:80},{kind:'plant',x:300,y:0,r:10}];
 const events=[];box.ffx={level:'reduced'};box.touchUI=false;box.inView=()=>true;box.terrainPalette=()=>({liquid:{core:'#123'},rock:{base:'#123'}});box.drawTexturedTerrain=f=>{events.push('decal:'+f.kind);return true;};
 vm.runInContext(html.slice(html.indexOf('function drawTerrainUnder()'),html.indexOf('function drawLake(')),box);
 box.drawLake=()=>events.push('fallbackLake');box.drawRock=()=>events.push('fallbackRock');
 box.drawTerrainUnder();assert.deepEqual(events,['decal:lake','decal:rock']);events.length=0;
 box.touchUI=true;box.ffx.level='off';box.drawTerrainUnder();assert.deepEqual(events,['decal:lake','decal:rock']);events.length=0;
 box.touchUI=false;box.drawTexturedTerrain=()=>false;box.drawTerrainUnder();assert.deepEqual(events,['fallbackLake','fallbackRock']);
});

test('flora atlas covers all sectors with bounded crops and stable roots',()=>{
 const {box,calls}=harness();box.arenaBiomeIdx=0;box.ffx={level:'full'};
 const f={kind:'plant',x:10,y:20,h:40,ph:1};
 assert.equal(box.drawTexturedFlora(f),false);assert.equal(calls.length,0);
 box.abyssArt.flora={ready:true,image:{}};
 const roots=[[134,224],[134,224],[150,225],[132,216],[132,220],[140,214]];
 for(let i=0;i<6;i++){
  calls.length=0;box.arenaBiomeIdx=i%5;const p={...f,crystal:i===5};const before=JSON.stringify(p);
  assert.equal(box.floraTextureCell(p,i%5),i);assert.equal(box.drawTexturedFlora(p),true);assert.equal(JSON.stringify(p),before);
  const draws=calls.filter(c=>c[0]==='drawImage');assert.equal(draws.length,1);const d=draws[0];
  assert.ok(d[2]>=0&&d[2]+d[4]<=768&&d[3]>=0&&d[3]+d[5]<=512);
  const rootX=d[6]+roots[i][0]*d[8]/256,rootY=d[7]+roots[i][1]*d[9]/256;
  const shear=calls.find(c=>c[0]==='transform')[3];
  assert.ok(Math.abs(rootX+shear*rootY)<1e-10&&Math.abs(rootY)<1e-10);
 }
 assert.equal(box.drawTexturedFlora({...f,kind:'rock'}),false);
});
test('flora sway stays bounded while crystals and off effects remain stationary',()=>{
 const {box}=harness();
 for(let i=0;i<100;i++){
  const f={ph:i*.2};const t=i*.17;
  assert.ok(Math.abs(box.floraSway(f,t,'full'))<=.035);
  assert.ok(Math.abs(box.floraSway(f,t,'reduced'))<=.015);
  assert.equal(box.floraSway(f,t,'off'),0);
  assert.equal(box.floraSway({...f,crystal:true},t,'full'),0);
 }
});
test('flora dispatch preserves touch-off omission, view culling and unloaded fallback',()=>{
 const {box,calls}=harness();box.arenaBiomeIdx=0;box.ffx={level:'reduced'};box.touchUI=false;
 const plant={kind:'plant',x:10,y:20,h:40,r:24,blades:5,ph:0};
 box.terrain=[plant,{...plant,x:999},{...plant,kind:'rock'}];box.inView=x=>x!==999;
 box.terrainPalette=()=>({flora:{stem:'#234',glow:'#456'}});
 vm.runInContext(html.slice(html.indexOf('function drawTerrainOver()'),html.indexOf('function drawPillars()')),box);
 box.abyssArt.flora={ready:true,image:{}};box.drawTerrainOver();assert.equal(calls.filter(c=>c[0]==='drawImage').length,1);
 calls.length=0;box.touchUI=true;box.ffx.level='off';box.drawTerrainOver();assert.equal(calls.length,0);
 box.touchUI=false;box.abyssArt.flora.ready=false;box.drawTerrainOver();
 assert.equal(calls.filter(c=>c[0]==='drawImage').length,0);assert.equal(calls.filter(c=>c[0]==='quadraticCurveTo').length,5);
});
