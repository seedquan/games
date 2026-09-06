import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFileSync} from 'node:fs';
const html=readFileSync(new URL('../../abyss-protocol/index.html',import.meta.url),'utf8');
test('reduced and off effects avoid canvas shadow blur',()=>{
 const code=html.slice(html.indexOf('function glow('),html.indexOf('function noglow('));
 for(const level of ['reduced','off']) {
  const box={ctx:{},frameProfile:null,ffx:{level},renderQuality:{shadows:false}};vm.createContext(box);vm.runInContext(code,box);
  box.glow('#5ee6ff',20);assert.equal(box.ctx.shadowBlur,0);
 }
});
test('render resolution respects a pixel budget on ultrawide and retina screens',()=>{
 const start=html.indexOf('function chooseRenderDpr(');
 assert.notEqual(start,-1,'pixel budget must be implemented');
 const end=html.indexOf('\n}',start)+2;
 const box={Math};vm.createContext(box);vm.runInContext(html.slice(start,end),box);
 for(const [w,h,dpr] of [[3440,1440,1],[3840,2160,2],[1920,1080,2],[390,844,3]]) {
  const scale=box.chooseRenderDpr(w,h,dpr,1500000);
  assert.ok(w*h*scale*scale<=1500001);assert.ok(scale<=dpr);assert.ok(scale>0);
 }
 assert.equal(box.chooseRenderDpr(1280,720,1,1500000),1);
});
test('sustained slow frames reduce raster budget; stable frames and hidden tabs do not',()=>{
 const start=html.indexOf('function observeRasterBudget(');assert.notEqual(start,-1);
 const end=html.indexOf('\n}',start)+2;
 let resizes=0;const budget={pixels:1500000,elapsed:0,frames:0,slow:0};
 const box={Math,rasterBudget:budget,document:{hidden:false},resize:()=>resizes++};vm.createContext(box);vm.runInContext(html.slice(start,end),box);
 for(let i=0;i<200;i++) box.observeRasterBudget(16.67);
 assert.equal(budget.pixels,1500000);assert.equal(resizes,0);
 for(let i=0;i<120;i++) box.observeRasterBudget(33.3);
 assert.ok(budget.pixels<1500000);assert.equal(resizes,1);
 for(let i=0;i<1000;i++)box.observeRasterBudget(33.3);
 assert.equal(budget.pixels,960000);
 const old=resizes;box.document.hidden=true;
 for(let i=0;i<1000;i++)box.observeRasterBudget(40);
 assert.equal(resizes,old);
});
test('radial lights reuse bounded cached sprites across positions and radii',()=>{
 const start=html.indexOf('const radialLightCache =');assert.notEqual(start,-1);
 const end=html.indexOf('/* additive bloom helper',start);
 let builds=0,draws=0;
 const tileCtx={createRadialGradient:()=>{builds++;return {addColorStop(){}};},fillRect(){}};
 const box={Math,Map,document:{createElement:()=>({getContext:()=>tileCtx})},ctx:{globalAlpha:.5,drawImage(){draws++;}}};
 vm.createContext(box);vm.runInContext(html.slice(start,end),box);
 for(let i=0;i<200;i++)box.drawRadialLight(i,i,30+i,'#5ee6ff',.4);
 assert.equal(builds,1);assert.equal(draws,200);assert.equal(box.ctx.globalAlpha,.5);
 for(let i=0;i<100;i++)box.drawRadialLight(0,0,50,`rgb(${i},0,0)`,.5);
 assert.ok(vm.runInContext('radialLightCache.size',box)<=64);
 const before=draws;box.drawRadialLight(0,0,0,'#fff',1);box.drawRadialLight(0,0,20,'#fff',0);assert.equal(draws,before);
});
test('profiling resets samples when scene or canvas size changes',()=>{
 const start=html.indexOf('function recordFrameProfile(');
 const end=html.indexOf('\nlet aS =',start);
 const box={document:{hidden:false},frameProfile:{intervals:[],render:[],lastPublish:0},state:'hub',paused:false,canvas:{width:1000,height:800,dataset:{}},ffx:{level:'reduced'},uiCanvas:null,uiDpr:1,dpr:1,cw:1000,ch:800,enemies:[],bullets:[],pbolts:[],ebolts:[],spells:[],glaives:[],radialLightCache:new Map()};
 vm.createContext(box);vm.runInContext(html.slice(start,end),box);
 for(let i=0;i<150;i++)box.recordFrameProfile(i*17,17,.2);
 assert.equal(JSON.parse(box.canvas.dataset.frameProfile).state,'hub');
 box.state='play';box.recordFrameProfile(2600,17,.2);
 assert.equal(box.canvas.dataset.frameProfile,undefined);
 assert.equal(box.frameProfile.intervals.length,1);
 for(let i=1;i<150;i++)box.recordFrameProfile(2600+i*17,17,.2);
 assert.equal(JSON.parse(box.canvas.dataset.frameProfile).state,'play');
 box.canvas.width=900;box.recordFrameProfile(5200,17,.2);
 assert.equal(box.canvas.dataset.frameProfile,undefined);
 assert.equal(box.frameProfile.intervals.length,1);
 box.uiCanvas={width:1920,height:1080};box.recordFrameProfile(5217,17,.2);
 assert.equal(box.frameProfile.intervals.length,1);
});


test('UI resolution stays independent of adaptive world resolution and bounds retina memory',()=>{
 const start=html.indexOf('function chooseUiDpr('),end=html.indexOf('function resize()',start);
 const uiCanvas={style:{}},operations=[];
 const uiContext={setTransform:(...v)=>operations.push(['transform',...v]),clearRect:(...v)=>operations.push(['clear',...v])};
 const box={Math,uiCanvas,uiContext,ctx:{id:'world'},uiDpr:1,cw:3440,ch:1440,dpr:.49,window:{devicePixelRatio:1}};
 vm.createContext(box);vm.runInContext(html.slice(start,end),box);box.resizeUiLayer();box.beginUiLayer();
 assert.equal(uiCanvas.width,3440);assert.equal(uiCanvas.height,1440);assert.equal(box.uiDpr,1);
 assert.equal(box.ctx,uiContext);assert.deepEqual(operations,[['transform',1,0,0,1,0,0],['clear',0,0,3440,1440]]);
 box.dpr=.44;box.resizeUiLayer();assert.equal(uiCanvas.width,3440);
 const d=box.chooseUiDpr(3840,2160,2);assert.ok(3840*2160*d*d<=8000001);
 assert.equal(box.chooseUiDpr(390,844,3),1.5);
 box.uiCanvas=null;box.uiContext=null;const before=operations.length;box.beginUiLayer();assert.equal(operations.length,before);
});

test('compact pause targets fit portrait and landscape viewports at touch size',()=>{
 const start=html.indexOf('function pauseLayout('),end=html.indexOf('function drawPause()',start);
 const box={Math};vm.createContext(box);vm.runInContext(html.slice(start,end),box);
 for(const [w,h] of [[320,568],[390,844],[844,390],[390,390]]) {
  const l=box.pauseLayout(w,h,1);assert.ok(l.bh>=44);
  for(let i=0;i<4;i++) {
   const x=l.bx+(i%l.cols)*(l.bw+l.gap),y=l.by+Math.floor(i/l.cols)*(l.bh+l.gap);
   assert.ok(x>=16&&x+l.bw<=w-15);assert.ok(y>0&&y+l.bh<h-40);
  }
 }
 assert.equal(box.pauseLayout(3440,1440,1.25).cols,1);
});

test('combat profiling store never reads or writes the real save namespace',()=>{
 const start=html.indexOf('const store ='),end=html.indexOf('/* ---------------- canvas / view',start);
 for(const preview of [true,false]) {
  let reads=0,writes=0;const saved={};
  const box={combatPreviewEnabled:preview,localStorage:{getItem:k=>{reads++;return saved[k];},setItem:(k,v)=>{writes++;saved[k]=v;}}};
  vm.createContext(box);vm.runInContext(html.slice(start,end)+'\nglobalThis.subject=store;',box);
  assert.equal(box.subject.get('meta'),undefined);box.subject.set('meta','test');assert.equal(box.subject.get('meta'),'test');
  assert.equal(reads,preview?0:2);assert.equal(writes,preview?0:1);
 }
});
test('combat scenario uses real spawners, resets waves and leaves ordinary mode inert',()=>{
 const start=html.indexOf("let combatPreviewScenario ="),end=html.indexOf('if(combatPreviewEnabled) {',start);
 const spawned=[];let hubs=0,runs=0,rooms=0;
 const box={combatPreviewEnabled:false,enterHub:()=>hubs++,startRun:()=>runs++,genRoom:()=>rooms++,placePlayers(){},snapCamera(){},CONFIG:{arenaW:2000,arenaH:1200},FINAL_DEPTH:24,players:[{}],player:{x:1000,y:760},ENEMY_DEFS:{chaser:{},shooter:{},tank:{},shield:{}},spawnEnemy:(...a)=>spawned.push(a),TAU:Math.PI*2,Math,Object,frameProfile:{sampleKey:'old'}};
 vm.createContext(box);vm.runInContext(html.slice(start,end),box);box.startCombatPreview('crowd');assert.equal(hubs,0);
 box.combatPreviewEnabled=true;box.startCombatPreview('invalid');assert.equal(hubs,0);
 box.startCombatPreview('crowd');assert.equal(spawned.length,48);assert.equal(runs,1);assert.equal(rooms,1);
 assert.equal(box.players[0].hp,100000);assert.equal(box.spawnQ.length,0);assert.equal(box.waves.length,0);assert.equal(box.state,'play');assert.equal(box.frameProfile.sampleKey,null);
 box.boss={hp:1000,maxHp:1000};box.startCombatPreview('core3');assert.equal(box.depth,24);assert.equal(box.boss.hp,300);
});

test('reduced effects omit secondary bloom while retaining a bounded world-light budget',()=>{
 const bloomStart=html.indexOf('get bloom()'),bloomEnd=html.indexOf('\n  get scanlines()',bloomStart);
 const capStart=html.indexOf('get lightCap()'),capEnd=html.indexOf('\n  trauma(',capStart);
 const box={FX_LIGHT_CAP:36};vm.createContext(box);
 vm.runInContext('globalThis.fx={level:"reduced",'+html.slice(bloomStart,bloomEnd)+html.slice(capStart,capEnd)+'};',box);
 assert.equal(box.fx.bloom,false);assert.equal(box.fx.lightCap,8);
 box.fx.level='full';assert.equal(box.fx.bloom,true);assert.equal(box.fx.lightCap,36);
 box.fx.level='off';assert.equal(box.fx.bloom,false);assert.equal(box.fx.lightCap,0);
 const calls=[];box.ffx=box.fx;box.ctx={save:()=>calls.push('save')};box.drawRadialLight=()=>calls.push('light');
 const start=html.indexOf('function bloomCircle('),end=html.indexOf('function drawMotes()',start);
 vm.runInContext(html.slice(start,end),box);box.fx.level='reduced';box.bloomCircle(1,2,30,'#fff',.5);assert.equal(calls.length,0);
});

test('floor cache reuses one bounded surface and invalidates only when its painted content changes',()=>{
 const start=html.indexOf('let arenaFloorCache ='),end=html.indexOf('function drawArenaFloorSource(',start);
 let allocations=0,paints=0,walls=0,draws=0;
 const world={drawImage(){draws++;}},target={setTransform(){}},surface={getContext:()=>target};
 const box={ctx:world,CONFIG:{arenaW:2500,arenaH:1408},state:'hub',depth:0,biomeIdxForDepth:d=>d,ffx:{level:'reduced'},touchUI:false,abyssArt:{station:{ready:false},abyss:{ready:true}},profileQuery:{get:()=>null},document:{createElement:()=>{allocations++;return surface;}},Math,clamp:(x,a,b)=>Math.max(a,Math.min(b,x)),aOX:0,aOY:0,aS:1,cw:1280,ch:720,drawArenaFloorSource:full=>{assert.equal(full,true);paints++;},drawArenaWalls:()=>walls++};
 vm.createContext(box);vm.runInContext(html.slice(start,end),box);
 box.drawArenaFloor();box.aOX=-150;box.aS=1.55;box.drawArenaFloor();
 assert.equal(allocations,1);assert.equal(paints,1);assert.equal(draws,2);assert.equal(walls,2);assert.equal(box.ctx,world);
 box.abyssArt.station.ready=true;box.drawArenaFloor();assert.equal(paints,2);
 box.ffx.level='off';box.drawArenaFloor();assert.equal(paints,3);
 box.state='play';box.depth=1;box.drawArenaFloor();assert.equal(paints,4);
 box.CONFIG.arenaW=8000;box.CONFIG.arenaH=4000;box.drawArenaFloor();assert.ok(surface.width*surface.height<=4000000);assert.equal(allocations,1);
 box.drawArenaFloorSource=()=>{throw Error('paint failed');};box.depth=4;
 assert.throws(()=>box.drawArenaFloor(),/paint failed/);assert.equal(box.ctx,world);
});

test('camera keeps full player sprite inside HUD-safe bounds at every arena corner',()=>{
 const start=html.indexOf('function frameArenaAxis('),end=html.indexOf('// Reads numPlayers',start);
 for(const [cw,ch] of [[390,844],[844,390],[1280,720],[2646,1108]])for(const zoom of [.65,1,1.55,2]) {
  const u=Math.max(.72,Math.min(1.25,Math.min(cw,ch)/640));
  const vb={x:16,y:46*u,w:cw-32,h:ch-124*u};vb.cx=vb.x+vb.w/2;vb.cy=vb.y+vb.h/2;
  const A={arenaW:2200,arenaH:1800},cam={zoom};
  const box={CONFIG:A,cam,viewBand:()=>vb,clamp:(v,a,b)=>Math.max(a,Math.min(b,v))};
  vm.createContext(box);vm.runInContext(start>=0?html.slice(start,end):'',box);
  for(const radius of [12,13,18])for(const x of [12+radius,A.arenaW-12-radius])for(const y of [12+radius,A.arenaH-12-radius]) {
   cam.cx=x;cam.cy=y;box.computeView();
   const size=radius*4.4;
   assert.ok((x-size/2)*zoom+box.aOX>=vb.x-.001,'left sprite clipped');
   assert.ok((x+size/2)*zoom+box.aOX<=vb.x+vb.w+.001,'right sprite clipped');
   assert.ok((y-size*.8)*zoom+box.aOY>=vb.y-.001,'head clipped');
   assert.ok((y+size*.2)*zoom+box.aOY<=vb.y+vb.h+.001,'feet clipped');
   const screenX=x*zoom+box.aOX,screenY=y*zoom+box.aOY;
   assert.ok(Math.abs((screenX-box.aOX)/box.aS-x)<1e-8);
   assert.ok(Math.abs((screenY-box.aOY)/box.aS-y)<1e-8);
  }
 }
});
test('camera clamps continuously at an edge and centers an arena smaller than its view',()=>{
 const start=html.indexOf('function frameArenaAxis('),end=html.indexOf('function computeView()',start);
 const box={clamp:(v,a,b)=>Math.max(a,Math.min(b,v))};vm.createContext(box);vm.runInContext(html.slice(start,end),box);
 assert.equal(box.frameArenaAxis(999,100,0,1000,30,30),450);
 const samples=[];for(let offset=-100;offset<=200;offset++)samples.push(box.frameArenaAxis(offset,2000,16,1000,32,32));
 for(let i=1;i<samples.length;i++)assert.ok(Math.abs(samples[i]-samples[i-1])<=1);
});
