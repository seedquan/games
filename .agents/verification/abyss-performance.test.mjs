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
