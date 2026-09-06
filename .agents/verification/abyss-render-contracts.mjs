// Pure regression checks; this does not replace browser gameplay or FPS verification.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import test from 'node:test';
const html = readFileSync(new URL('../../abyss-protocol/index.html', import.meta.url), 'utf8');
const source = html.slice(html.indexOf('function textureFacing('), html.indexOf('function drawTexturedFloor('));
function harness(ready=true) {
  const calls=[];
  const ctx=new Proxy({globalAlpha:1}, {get(o,k){return k in o ? o[k] : (...args)=>calls.push([k,...args]);}});
  const box={ctx,artAnimationPreview:false,abyssArt:{player:{ready,image:{}}},timeNow:0,TAU:Math.PI*2,numPlayers:1,
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
test('unconverted shield retains vector blocking direction semantics',()=>{
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
