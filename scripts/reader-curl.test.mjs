import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const studio = process.env.DEVECO_STUDIO_HOME || path.join(process.env.ProgramFiles || 'C:\\Program Files', 'Huawei', 'DevEco Studio');
const ts = require(path.join(process.env.DEVECO_SDK_HOME || path.join(studio,'sdk'),
  'default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = process.env.BIKA_PROJECT_ROOT || fileURLToPath(new URL('../', import.meta.url));
const read = file => fs.readFileSync(path.join(root, 'entry/src/main/ets', file), 'utf8');
function evaluate(source, globals={}) {
  const context = vm.createContext({exports:{},console:{warn(){}},...globals});
  vm.runInContext(ts.transpileModule(source,{
    compilerOptions:{target:ts.ScriptTarget.ES2021,module:ts.ModuleKind.CommonJS}
  }).outputText,context);
  return context.exports;
}
const geometry=evaluate(read('models/ReaderCurlGeometry.ets'));
const paperModel=evaluate(read('models/ReaderSpineMesh.ets'));
const source=read('components/ReaderCurlPager.ets');
const ast=ts.createSourceFile('ReaderCurlPager.ets',source,ts.ScriptTarget.Latest,true,ts.ScriptKind.ETS);
const owner=ast.statements.find(node=>node.name?.getText(ast)==='ReaderCurlPager');
const methods=owner.members.filter(node=>node.body && node.name?.getText(ast)!=='build').map(node=>node.getText(ast)).join('\n');

function reader(options={}) {
  const frames=[],timers=[],commits=[],released=[],samples=[],shown=[];
  let time=0,starts=0,ends=0,captures=0;
  const {Subject}=evaluate('export class Subject {\n'+methods+'\n}',{
    ...geometry, ...paperModel,
    Date:class extends Date {static now(){return time;}},
    setTimeout:(callback,delay)=>{timers.push([callback,delay]);return timers.length;}
  });
  const page=new Subject();
  const snapshot=()=>{
    const id=++captures;
    if(options.failSecond && id%2===0)throw new Error('snapshot not ready');
    const sample={id,getImageInfoSync:()=>({size:{width:1600,height:1000}}),
      release:()=>{released.push(id);return Promise.resolve();}};
    samples.push(sample);return sample;
  };
  Object.assign(page,{
    index:2,count:6,rtl:false,revision:0,blocked:false,animationsOn:options.animationsOn??true,
    drawing:false,instanceId:'test',alive:true,pageWidth:1000,pageHeight:700,busy:false,settling:false,
    session:0,sourceIndex:-1,targetIndex:-1,committingIndex:-1,sessionRevision:0,initialOffset:0,progress:0,frame:null,
    isPaired:options.isPaired||(()=>true),
    getPageBounds:(_index,w,h)=>[{left:0,top:0,right:w/2-1,bottom:h},{left:w/2+1,top:0,right:w,bottom:h}],
    onTurnStart:()=>{starts++;},onTurnEnd:()=>{ends++;},
    onIndexChange:index=>{commits.push(index);page.index=index;page.onExternalChange('index');},
    nodeController:{show:frame=>shown.push(frame.progress),clear(){},resize(){},dispose(){}},
    controller:{attach(){},detach(){}},
    getUIContext:()=>({vp2px:value=>value*2,getComponentSnapshot:()=>({getSync:snapshot}),
      postFrameCallback:callback=>frames.push(callback)})
  });
  const flush=()=>{
    let limit=200;
    while(frames.length&&limit--){time+=16;for(const frame of frames.splice(0))frame.onFrame(0);}
    assert(limit>0,'animation must finish');
  };
  const retire=()=>{for(const [callback]of timers.splice(0))callback();};
  return{page,frames,timers,commits,released,samples,shown,flush,retire,
    get starts(){return starts;},get ends(){return ends;}};
}

test('RTL maps rightward drags to the next group, with no wrap at either chapter boundary',()=>{
  assert.equal(geometry.readerCurlTarget(2,6,50,true),3);
  assert.equal(geometry.readerCurlTarget(2,6,-50,true),1);
  assert.equal(geometry.readerCurlTarget(0,6,50,false),-1);
  assert.equal(geometry.readerCurlTarget(5,6,-50,false),-1);
  assert.equal(geometry.readerCurlTarget(2,6,NaN,false),-1);
  assert.equal(geometry.normalizeReaderTurnEffect('unknown'),'slide');
});
test('short drags cancel, directional flicks commit and a reverse flick cancels a long drag',()=>{
  assert.equal(geometry.shouldCommitReaderCurl(.2,-5,-100),false);
  assert.equal(geometry.shouldCommitReaderCurl(.03,-5,-800),true);
  assert.equal(geometry.shouldCommitReaderCurl(.5,-5,800),false);
  assert.equal(geometry.readerCurlProgress(100,1000,-10),0);
});
test('an incomplete curl returns to the original spread without writing progress',()=>{
  const h=reader();assert.equal(h.page.begin(-10,600),true);h.page.update(-100);h.page.settle(false);h.flush();
  assert.deepEqual(h.commits,[]);assert.equal(h.page.index,2);assert.equal(h.page.busy,false);
  assert.equal(h.starts,1);assert.equal(h.ends,1);h.retire();assert.deepEqual(h.released,[1,2]);
});
for(const rtl of[false,true])test(`a completed ${rtl?'RTL':'LTR'} curl commits exactly once after animation`,()=>{
  const h=reader();h.page.rtl=rtl;h.page.begin(rtl?10:-10,600);h.page.update(rtl?500:-500);h.page.settle(true);
  assert.deepEqual(h.commits,[]);h.flush();assert.deepEqual(h.commits,[3]);
  assert.equal(h.page.busy,false);assert.equal(h.starts,h.ends);h.page.cancelTurn();h.retire();
  assert.deepEqual(h.released,[1,2]);assert.equal(h.shown.at(-1),1);
});
test('a stale animation cannot commit after a slider relocation or a new scene revision',()=>{
  const h=reader();h.page.begin(-10,600);h.page.update(-500);h.page.settle(true);
  h.page.revision++;h.page.onExternalChange('revision');h.page.index=5;h.flush();h.retire();
  assert.deepEqual(h.commits,[]);assert.equal(h.page.index,5);assert.equal(h.ends,1);assert.deepEqual(h.released,[1,2]);
});
test('rotation, modal sheets and leaving the reader cancel active gestures',()=>{
  for(const action of[
    page=>page.resize({width:600,height:900}),
    page=>{page.blocked=true;page.onExternalChange('blocked');},
    page=>page.aboutToDisappear()
  ]){
    const h=reader();h.page.begin(-10,600);h.page.update(-500);h.page.settle(true);action(h.page);h.flush();h.retire();
    assert.deepEqual(h.commits,[]);assert.equal(h.page.busy,false);assert.equal(h.ends,1);assert.deepEqual(h.released,[1,2]);
  }
});
test('partial snapshot failures release the first bitmap and still permit navigation',()=>{
  const h=reader({failSecond:true});assert.equal(h.page.turn(1),true);h.flush();
  assert.deepEqual(h.commits,[3]);assert.deepEqual(h.released,[1]);assert.equal(h.page.drawing,false);
});
test('disabled animations retain functional gesture and volume navigation without allocating snapshots',()=>{
  const h=reader({animationsOn:false});assert.equal(h.page.turn(1),true);h.flush();
  assert.deepEqual(h.commits,[3]);assert.equal(h.samples.length,0);
  h.page.begin(10,100);h.page.update(100);h.page.settle(false);h.flush();assert.deepEqual(h.commits,[3]);
});
test('wide images or unpaired covers use full-page curl and paired spreads use the spine',()=>{
  const h=reader({isPaired:index=>index!==3});h.page.begin(-10,600);assert.equal(h.page.frame.paired,false);h.page.cancelTurn();
  h.page.isPaired=()=>true;h.page.begin(-10,600);assert.equal(h.page.frame.paired,true);h.page.cancelTurn();h.retire();
  assert.deepEqual(h.released,[1,2,3,4]);
});
test('a new gesture is rejected while settling or when no adjacent spread exists',()=>{
  const h=reader();h.page.begin(-10,600);h.page.settle(true);assert.equal(h.page.begin(10,600),false);h.flush();
  h.page.index=5;assert.equal(h.page.begin(-10,600),false);assert.equal(h.starts,1);
});


test('a cancelled drag cannot restart on its remaining move events after rotation or scene change',()=>{
  const h=reader();const event={offsetX:-50,velocityX:-900,fingerList:[{localY:600}]};
  h.page.onPanStart(event);h.page.revision++;h.page.onExternalChange('revision');
  h.page.onPanUpdate({...event,offsetX:-600});h.page.onPanEnd({...event,offsetX:-600});h.flush();
  assert.deepEqual(h.commits,[]);assert.equal(h.starts,1);assert.equal(h.ends,1);
  h.page.onPanStart(event);h.page.onPanEnd({...event,offsetX:-600});h.flush();
  assert.deepEqual(h.commits,[3]);
});

function pose(p=.4,fromRight=true,paired=true,vertical=250){
  const frontRect=paired?{left:fromRight?600:120,top:80,right:fromRight?1080:600,bottom:820}
    :{left:360,top:80,right:840,bottom:820};
  const backRect=paired?{left:fromRight?120:600,top:80,right:fromRight?600:1080,bottom:820}:frontRect;
  return{width:1200,height:900,frontRect,backRect,paired,fromRight,
    touchX:480*(1-2*p),touchY:Math.sin(Math.PI*p)*vertical,cornerY:0};
}
test('paper geometry respects actual image bounds and both completed reading directions',()=>{
  for(const fromRight of[true,false])for(const paired of[true,false])for(const p of[0,.1,.25,.5,.75,.9,1]){
    const frame=pose(p,fromRight,paired),mesh=paperModel.buildReaderPaperMesh(frame);
    for(const side of[mesh.front,mesh.back]){
      assert.equal(side.vertices.length,(mesh.columns+1)*(mesh.rows+1)*2);
      assert.equal(side.colors.length,(mesh.columns+1)*(mesh.rows+1));
      assert(side.vertices.every(Number.isFinite));
      assert(side.colors.every(c=>(c>>>24)===255&&((c>>>16)&255)>=233));
    }
    if(p===0){
      const xs=mesh.front.vertices.filter((_,i)=>i%2===0),ys=mesh.front.vertices.filter((_,i)=>i%2===1);
      assert(Math.abs(Math.min(...xs)-frame.frontRect.left)<.001);
      assert(Math.abs(Math.max(...xs)-frame.frontRect.right)<.001);
      assert(Math.abs(Math.min(...ys)-frame.frontRect.top)<.001);
      assert(Math.abs(Math.max(...ys)-frame.frontRect.bottom)<.001);
    }
    if(p===1&&paired){
      const xs=mesh.back.vertices.filter((_,i)=>i%2===0),ys=mesh.back.vertices.filter((_,i)=>i%2===1);
      assert(Math.abs(Math.min(...xs)-frame.backRect.left)<.001);
      assert(Math.abs(Math.max(...xs)-frame.backRect.right)<.001);
      assert(Math.abs(Math.min(...ys)-frame.backRect.top)<.001);
      assert(Math.abs(Math.max(...ys)-frame.backRect.bottom)<.001);
    }
  }
});
test('moving a corner vertically changes the fold geometry at the same horizontal position',()=>{
  const horizontal=paperModel.buildReaderPaperMesh(pose(.3,true,true,0));
  const diagonal=paperModel.buildReaderPaperMesh(pose(.3,true,true,450));
  assert.notDeepEqual([...horizontal.front.vertices],[...diagonal.front.vertices]);
  const col=60,stride=(diagonal.columns+1)*2;
  assert(Math.abs(diagonal.front.vertices[col*2]-diagonal.front.vertices[diagonal.rows*stride+col*2])>1);
});
test('contain image geometry excludes the reader margins and aligns paired images to their inner edges',()=>{
  const single=paperModel.readerPaperImageRect(1920,1260,0,0,1,0,.67);
  assert(single.left>500&&single.right<1420);assert.equal(single.top,0);assert.equal(single.bottom,1260);
  const left=paperModel.readerPaperImageRect(1920,1260,0,0,2,0,.67);
  const right=paperModel.readerPaperImageRect(1920,1260,0,0,2,1,.67);
  assert.equal(left.right,959);assert.equal(right.left,961);
  assert.equal(paperModel.buildReaderPaperMesh({...pose(),touchX:NaN}),null);
});
class Brush{setAntiAlias(){}setColor(value){assert.equal(value,0xFFFFFFFF);}}
class RenderNode{}
class NodeController{}
const renderer=evaluate(read('components/ReaderCurlRenderer.ets')+'\nexport { ReaderCurlRenderNode };',{
  require:name=>name.includes('ReaderSpineMesh')?paperModel:name.includes('ArkGraphics2D')?{drawing:{Brush}}:{RenderNode,NodeController}
});
test('paper draws original-color textures as two shared meshes without a gray back overlay',()=>{
  for(const paired of[true,false])for(const right of[true,false]){
    const node=new renderer.ReaderCurlRenderNode(),calls=[];let saves=0;
    node.content={...pose(.4,right,paired),current:'A',next:'B',progress:.4,completed:false};
    const canvas={attachBrush(){},detachBrush(){},save(){saves++;},restore(){saves--;},clipRect(){},drawImageRect(){},
      drawPixelMapMesh:(...args)=>calls.push(args)};
    node.draw({canvas});assert.equal(calls.length,2);assert.deepEqual(calls.map(v=>v[0]),paired?['A','B']:['A','A']);
    assert.equal(saves,0);
  }
});
test('corner gestures retain live vertical movement and a fully open layout keeps original image margins',()=>{
  const h=reader();h.page.getPageBounds=()=>[{left:300,top:20,right:700,bottom:680}];
  h.page.isPaired=()=>false;h.page.onPanStart({offsetX:-20,offsetY:0,fingerList:[{localY:25}]});
  h.page.onPanUpdate({offsetX:-120,offsetY:160,fingerList:[{localY:185}]});
  assert.equal(h.page.frame.frontRect.left,600);assert.equal(h.page.frame.touchY,320);
  assert.equal(h.page.frame.touchX,560);assert.equal(h.page.frame.completed,false);
  h.page.onPanCancel();h.flush();assert.deepEqual(h.commits,[]);
});
const transitionSource=read('components/ReaderLayoutTransition.ets');
const transitionAst=ts.createSourceFile('ReaderLayoutTransition.ets',transitionSource,ts.ScriptTarget.Latest,true,ts.ScriptKind.ETS);
const transitionOwner=transitionAst.statements.find(n=>n.name?.getText(transitionAst)==='ReaderLayoutTransition');
const transitionMethods=transitionOwner.members.filter(n=>n.body&&n.name?.getText(transitionAst)!=='build').map(n=>n.getText(transitionAst)).join('\n');
function transition(){
  const frames=[],finishes=[],timers=[],released=[];let sequence=0;
  const {Subject}=evaluate('export class Subject {\n'+transitionMethods+'\n}',{
    Curve:{EaseInOut:0},setTimeout:callback=>timers.push(callback)
  });
  const page=new Subject();Object.assign(page,{alive:true,revision:0,animationsOn:true,snapshot:null,snapshotOpacity:0,snapshotScale:1,
    contentId:'layout',controller:{detach(){},attach(){}},
    getUIContext:()=>({getComponentSnapshot:()=>({getSync:()=>{const id=++sequence;return{id,release:()=>{released.push(id);return Promise.resolve();}};}}),
      postFrameCallback:callback=>frames.push(callback),animateTo:(options,change)=>{change();finishes.push(options.onFinish);}})});
  const flush=()=>{while(frames.length)for(const f of frames.splice(0))f.onFrame(0);};
  return{page,frames,finishes,released,flush,release:()=>{for(const f of timers.splice(0))f();}};
}
test('layout changes keep a snapshot through regrouping, animate it away and release it',()=>{
  const h=transition();h.page.capture();assert.equal(h.page.snapshotOpacity,1);
  h.flush();assert.equal(h.page.snapshotOpacity,0);assert.equal(h.page.snapshotScale,1.015);
  h.finishes[0]();assert.equal(h.page.snapshot,null);h.release();assert.deepEqual(h.released,[1]);
});
test('rapid layout changes and leaving the page invalidate old animation completions',()=>{
  const h=transition();h.page.capture();h.flush();h.page.capture();h.flush();
  h.finishes[0]();assert.equal(h.page.snapshot.id,2);
  h.page.aboutToDisappear();h.finishes[1]();h.release();assert.equal(h.page.snapshot,null);
  assert.deepEqual(h.released,[1,2]);
});
