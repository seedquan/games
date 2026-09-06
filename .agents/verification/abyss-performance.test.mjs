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
