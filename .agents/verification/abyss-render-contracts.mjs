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
  const box={ctx,artAnimationPreview:false,southRigPreviewEnabled:false,abyssArt:{player:{ready,image:{}}},timeNow:0,TAU:Math.PI*2,numPlayers:1,
    weaponDefP:p=>p.weapon,drawHeldWeapon:(...args)=>calls.push(['weapon',...args]),
    drawAndroidFeedback:p=>calls.push(['feedback',p]),Math,Object,Number};
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
 const box={enemies,players,numPlayers:2,inView:x=>x!==999,
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
test('south rig is opt-in, waits for its image, and preserves one weapon and feedback pass',()=>{
 const {box,calls}=harness();const p=player();p.aimDraw=Math.PI/2;p.artRunPhase=.7;p.artRunBlend=1;
 box.abyssArt.rigSouth={ready:true,image:{id:'rig'}};
 box.drawTexturedAndroid(p);assert.equal(calls.filter(c=>c[0]==='drawImage'&&c[1].id==='rig').length,0);
 box.southRigPreviewEnabled=true;calls.length=0;box.drawTexturedAndroid(p);
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
test('south rig phase uses its calibrated stride while other direction clips retain theirs',()=>{
 const {box}=harness();box.southRigPreviewEnabled=true;box.abyssArt.rigSouth={ready:true,image:{}};
 const p=player();p.aimDraw=Math.PI/2;box.advanceRunAnimation(p,0,12,.01);
 assert.ok(Math.abs(p.artRunPhase-.125)<1e-9);
 p.artRunPhase=0;p.aimDraw=0;box.advanceRunAnimation(p,14,0,.01);
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

test('east rig remains opt-in and falls back while unavailable',()=>{
 const {box}=harness();box.abyssArt.rigEast={ready:true,image:{}};
 assert.equal(box.previewRigKey(0),null);box.southRigPreviewEnabled=true;
 assert.equal(box.previewRigKey(0),'rigEast');assert.equal(box.previewRigKey(4),null);
 box.abyssArt.rigEast.ready=false;assert.equal(box.previewRigKey(0),null);
});
test('east rig knees preserve both bone lengths across the full gait',()=>{
 const {box}=harness();
 for(let i=0;i<120;i++)for(const side of [-1,1]) {
  const phase=i/120,step=box.southRigStep(phase,side,1);
  const hx=80+side*3,hy=82+side*2-Math.abs(Math.sin(phase*Math.PI*2))*1.6;
  const ax=80+side*3+step.travel*18,ay=126+side*2-step.lift*19;
  const k=box.eastRigKnee(hx,hy,ax,ay);
  assert.ok(Math.abs(Math.hypot(k.x-hx,k.y-hy)-25)<1e-8);
  assert.ok(Math.abs(Math.hypot(k.x-ax,k.y-ay)-27)<1e-8);
 }
});
test('east rig renders eleven connected parts with one held weapon and feedback pass',()=>{
 const {box,calls}=harness();box.southRigPreviewEnabled=true;box.abyssArt.rigEast={ready:true,image:{}};
 const p=player();p.artRunPhase=.3;p.artRunBlend=1;box.drawTexturedAndroid(p);
 assert.equal(calls.filter(c=>c[0]==='drawImage').length,11);
 assert.equal(calls.filter(c=>c[0]==='weapon').length,1);
 assert.equal(calls.filter(c=>c[0]==='feedback').length,1);
 box.advanceRunAnimation(p,24,0,.1);assert.ok(Math.abs(p.artRunPhase-.55)<1e-8);
});
