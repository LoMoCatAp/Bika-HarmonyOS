import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const studio = process.env.DEVECO_STUDIO_HOME || path.join(process.env.ProgramFiles || 'C:\\Program Files', 'Huawei', 'DevEco Studio');
const ts = require(path.join(process.env.DEVECO_SDK_HOME || path.join(studio, 'sdk'),
  'default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = process.env.BIKA_PROJECT_ROOT || fileURLToPath(new URL('../', import.meta.url));
const read = file => fs.readFileSync(path.join(root, 'entry/src/main/ets', file), 'utf8');
const plain = value => JSON.parse(JSON.stringify(value));
function evaluate(source, globals = {}) {
  const context = vm.createContext({ exports: {}, ...globals,
    console: { info() {}, warn() {}, error() {}, debug() {} } });
  vm.runInContext(ts.transpileModule(source, {
    compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS }
  }).outputText, context);
  return context.exports;
}
const model = evaluate(read('models/ReaderPageSpread.ets'));
const curlModel = evaluate(read('models/ReaderCurlGeometry.ets'));
const { WindowHelper } = evaluate(read('common/WindowHelper.ets'));
const groups = (count, double = true, first = false, wide = []) => model.buildReaderPageSpreads(count, double, first, new Set(wide));
for (const [width,height,expected] of [[1100,740,true],[780,1100,false],[560,350,false],[719,400,false],[720,600,true],
  [1000,900,false],[0,0,false],[NaN,500,false],[900,Infinity,false]]) {
  test(`automatic layout follows the available window: ${width} x ${height}`, () => {
    assert.equal(model.useReaderDoublePage(1,'auto',width,height),expected);
  });
}
test('explicit layouts override window choice while all strip modes stay single-column', () => {
  assert.equal(model.useReaderDoublePage(0,'single',1200,700),false);
  assert.equal(model.useReaderDoublePage(1,'double',500,900),true);
  for (const mode of [3,4,-1,NaN]) assert.equal(model.useReaderDoublePage(mode,'double',1200,700),false);
  for (const value of ['', 'invalid', 'AUTO']) assert.equal(model.normalizeReaderPageLayout(value),'auto');
});
test('cover offset, odd tail and wide images form complete non-overlapping groups', () => {
  assert.deepEqual(plain(groups(5).map(s=>[s.first,s.last])), [[0,1],[2,3],[4,4]]);
  assert.deepEqual(plain(groups(5,true,true).map(s=>[s.first,s.last])), [[0,0],[1,2],[3,4]]);
  assert.deepEqual(plain(groups(6,true,false,[1,4]).map(s=>[s.first,s.last])), [[0,0],[1,1],[2,3],[4,4],[5,5]]);
  for (let count = 0; count < 80; count++) for (const first of [true,false]) {
    const wide = Array.from({ length: count }, (_,i)=>i).filter(i=>i%7===2||i%11===1);
    const spreads = groups(count,true,first,wide);
    const actual = spreads.flatMap(s=>s.first===s.last?[s.first]:[s.first,s.last]);
    assert.deepEqual(plain(actual),Array.from({length:count},(_,i)=>i));
    assert.equal(new Set(spreads.map(s=>s.key)).size,spreads.length);
    assert(spreads.every(s=>s.first===s.last||(!wide.includes(s.first)&&!wide.includes(s.last))));
  }
  for (const value of [-1, NaN, Infinity, 2.5]) assert.equal(groups(value).length,0);
});
test('wide classification tolerates slight landscape ratios and invalid dimensions', () => {
  assert.equal(model.isReaderWideImage(1100,1000),false); assert.equal(model.isReaderWideImage(1101,1000),true);
  for (const size of [[0,100],[100,0],[-10,100],[Infinity,100],[100,NaN]]) assert.equal(model.isReaderWideImage(...size),false);
});
test('RTL changes physical order without changing source indices, lookup or original page count', () => {
  const spreads = groups(12);
  assert.deepEqual(plain(model.readerSpreadPages(spreads[3],false)),[6,7]);
  assert.deepEqual(plain(model.readerSpreadPages(spreads[3],true)),[7,6]);
  assert.equal(model.readerSpreadIndex(spreads,7),3); assert.equal(model.readerPageRange(spreads,7,12),'7–8 / 12');
  assert.equal(model.adjacentReaderSpreadPage(spreads,7,1),8);
  assert.equal(model.adjacentReaderSpreadPage(spreads,7,-1),4);
  assert.equal(model.adjacentReaderSpreadPage(spreads,0,-1),-1);
  assert.equal(model.readerPageRange(groups(12,true,false,[7]),7,12),'8 / 12');
  assert.equal(model.readerPageRange([],NaN,12),'1 / 12'); assert.equal(model.readerPageRange([],0,NaN),'0 / 0');
});
test('strip widths validate old or damaged values and round to the slider step',()=>{
  for(const value of ['', 'NaN', '0', '400', '1201'])assert.equal(model.normalizeReaderStripWidth(value),780);
  assert.equal(model.normalizeReaderStripWidth('780'),780);assert.equal(model.normalizeReaderStripWidth('790'),800);
});

const names = ['rebuildPageSpreads','resetPageSpreads','queuePagerRelocation','cancelPagerAnimation',
  'onPagerAnimationStart','onPagerAnimationEnd','onPagerChange','onReaderImageSize','currentReaderPageRange',
  'currentReaderPage','clampProgressPage','jumpToReaderPage','turnByVolume','changePageLayout','changeFirstImageSingle',
  'updateReaderWindowSize','updateReaderWindowHeight','restoreLastPage','switchReadingMode','aboutToAppear','changeReaderStripWidth',
  'usesReaderCurl','changeTurnEffect','changeReaderStatus','onReaderPagerClick','onReaderImageDecoded','isReaderSpreadDecoded',
  'showReaderPageBoundary','onReaderNativePagerTouch','isImmersiveReading','syncReaderSystemBars',
  'onPageShow','onPageHide','stopObservingReaderInsets','toggleControls','cancelReaderControlsTransition',
  'clearReaderControlsReveal','finishReaderControlsReveal','finishReaderControlsWhenInsetsReady','animateReaderControls'];
const source = read('pages/ReaderPage.ets');
const ast = ts.createSourceFile('ReaderPage.ets',source,ts.ScriptTarget.Latest,true,ts.ScriptKind.ETS);
const owner = ast.statements.find(node=>node.name?.getText(ast)==='ReaderPage');
const methods = names.map(name=>{
  const member=owner.members.find(node=>node.name?.getText(ast)===name); assert(member,name); return member.getText(ast);
}).join('\n');
function reader() {
  const frames=[],calls=[],writes=[],messages=[],tips=[],systemBars=[],controlAnimations=[],settings=new Map(),timers=new Map();
  const images=Array.from({length:12},(_,i)=>({url:'image-'+i,failed:false}));
  let timerId=0, provider, params={comicId:'bookA',comicTitle:'Title',currentOrder:1,epsCount:1};
  const cache={isReady:()=>true,getSetting:(key,fallback)=>settings.get(key)??fallback,
    saveSetting:(key,value)=>settings.set(key,value),getPageProgress:()=>7};
  provider=()=>Promise.resolve(cache);
  const {Subject}=evaluate('export class Subject {\n'+methods+'\n}',{
    ...model, ...curlModel, CacheManager:{getInstance:()=>provider()},router:{getParams:()=>params},
    showImmersiveToast:value=>messages.push(value.message),ScrollAlign:{START:0},
    TouchType:{Down:0,Up:1,Move:2,Cancel:3},Curve:{EaseOut:0},READER_CONTROLS_FADE_MS:180,READER_CONTROLS_REVEAL_TIMEOUT_MS:200,
    WindowHelper:{setReaderSystemBars:(_window,visible,animated)=>systemBars.push([visible,animated])},
    setTimeout:(callback,delay)=>{const id=++timerId;timers.set(id,{callback,delay});return id;},
    clearTimeout:id=>timers.delete(id)
  });
  const page=new Subject();
  Object.assign(page,{readingMode:1,turnEffect:'slide',turnEffectChangeId:0,curlRevision:0,curlController:{cancel(){},turn(){return true;}},pageLayout:'auto',firstImageSingle:false,committedFirstImageSingle:false,
    doublePageActive:false,pageSpreads:[],widePageIndices:new Set(),readerImageRatios:new Map(),readerDecodedImages:new Map(),readerLayoutTransition:{capture(){},clear(){}},totalImages:12,swiperIndex:7,currentVisibleIndex:7,
    pagerDisplayIndex:0,pagerRelocating:false,pagerLayoutRevision:0,pagerAnimating:false,pagerRebuildPending:false,pagerAnimationTimer:-1,
    readerWindowActive:true,readerWindowWidth:1100,readerWindowHeight:740,readerTopInset:0,readerBottomInset:0,readerLeftInset:0,readerRightInset:0,
    generation:1,progressNavigationId:0,pageLayoutChangeId:0,firstImageChangeId:0,readingModeChangeId:0,
    stripReaderWidth:780,stripWidthChangeId:0,stripRelocating:false,
    isLoading:false,showSheet:false,downloadMenuVisible:false,progressMode:false,progressDragging:false,progressTouching:false,lastVolumeTurnAt:0,
    comicId:'bookA',currentOrder:1,showControls:true,readerPageVisible:true,readerSystemBarsVisible:true,
    readerControlsFadingOut:false,readerControlsTransitionId:0,readerControlsRevealPending:false,
    readerControlsRevealTimer:-1,readerShownTopInset:0,readerShownBottomInset:0,
    readerWindow:{off(){}},readerShowStatus:false,errorText:'',animationsOn:true,
    imageDataSource:{getData:index=>images[index]},
    swiperController:{changeIndex:(index,animation)=>{calls.push([index,animation]);page.onPagerChange(index);}},
    getUIContext:()=>({
      px2vp:value=>value/2,postFrameCallback:callback=>frames.push(callback),
      animateTo:(options,update)=>{controlAnimations.push(options);update();}
    }),
    persistPageIndex:()=>writes.push(page.swiperIndex),publishCurrentReading(){},
    nativeReaderSwipe:null,onReaderContentTouch(){},onReaderContentClick:()=>calls.push(['center']),showPageTip:index=>tips.push(index),resetProgressControl:()=>{page.progressMode=false;},
    listScroller:{scrollToIndex:index=>calls.push(['list',index])},
    observeReaderInsets:()=>{page.readerWindowActive=true;},registerVolumeKeys(){},unregisterVolumeKeys(){},updateChapterButtons(){},loadImagesWithCache:async()=>{},loadLocalImages(){}
  });
  const flush=()=>{let limit=20;while(frames.length&&limit--){for(const callback of frames.splice(0))callback.onFrame(0);}assert(limit>0,'frame loop');};
  return {page,frames,calls,writes,messages,tips,systemBars,controlAnimations,settings,cache,images,timers,flush,
    setProvider:value=>provider=value,setParams:value=>params=value};
}
test('rotation and resizing relocate by the original image rather than the spread number',()=>{
  const h=reader();h.page.rebuildPageSpreads();h.flush();
  assert.equal(h.page.swiperIndex,7);assert.deepEqual(h.calls.at(-1),[3,false]);assert.equal(h.writes.length,0);
  h.page.updateReaderWindowSize(780,1100,false);h.page.onPagerChange(0);h.flush();
  assert.equal(h.page.swiperIndex,7);assert.equal(h.page.currentVisibleIndex,7);assert.deepEqual(h.calls.at(-1),[7,false]);
  assert.equal(h.page.currentReaderPageRange(),'8 / 12');assert.equal(h.writes.length,0);
  h.page.updateReaderWindowSize(1100,740,false);h.flush();assert.deepEqual(h.calls.at(-1),[3,false]);
});
test('continuous window dragging within the same layout does not keep resetting the native pager',()=>{
  const h=reader();h.page.rebuildPageSpreads();h.flush();const count=h.calls.length;
  for(let width=1200;width>=900;width-=10)h.page.updateReaderWindowSize(width,700,false);
  h.flush();assert.equal(h.calls.length,count);h.page.updateReaderWindowSize(560,350,false);h.flush();
  assert.equal(h.page.doublePageActive,false);assert.equal(h.calls.length,count+1);
});
test('late wide-image measurements preserve the current page while re-pairing surrounding images',()=>{
  const h=reader();h.page.rebuildPageSpreads();h.flush();
  h.page.onReaderImageSize(1,'image-1',2000,1000);h.page.onPagerChange(0);h.flush();
  assert.equal(h.page.swiperIndex,7);assert.equal(h.writes.length,0);
  assert.equal(h.page.pageSpreads[model.readerSpreadIndex(h.page.pageSpreads,1)].first,1);
  assert.equal(h.page.pageSpreads[model.readerSpreadIndex(h.page.pageSpreads,1)].last,1);
  h.page.onReaderImageSize(7,'image-7',1600,900);h.flush();
  assert.equal(h.page.swiperIndex,7);assert.equal(h.page.currentReaderPageRange(),'8 / 12');
});
test('dimensions from stale images or disposed readers cannot change the active chapter',()=>{
  const h=reader();h.page.rebuildPageSpreads();h.flush();const count=h.calls.length;
  h.page.onReaderImageSize(1,'old-chapter-url',2000,1000);h.page.onReaderImageSize(99,'missing',2000,1000);
  h.page.readerWindowActive=false;h.page.onReaderImageSize(1,'image-1',2000,1000);
  assert.equal(h.page.widePageIndices.size,0);assert.equal(h.calls.length,count);
});
test('wide-image regrouping waits for the swipe animation to finish',()=>{
  const h=reader();h.page.rebuildPageSpreads();h.flush();const count=h.calls.length;
  h.page.onPagerAnimationStart();h.page.onReaderImageSize(7,'image-7',2000,1000);
  assert.equal(h.page.pagerRebuildPending,true);assert.equal(h.frames.length,0);
  h.page.onPagerChange(4);assert.equal(h.page.swiperIndex,8);
  h.page.onPagerAnimationEnd();h.flush();assert.equal(h.page.swiperIndex,8);assert.equal(h.calls.length,count+1);assert.equal(h.timers.size,0);
});
test('cancelled native animations have a finite fallback and chapter reset clears their timer',()=>{
  const h=reader();h.page.rebuildPageSpreads();h.flush();h.page.onPagerAnimationStart();
  h.page.onReaderImageSize(7,'image-7',2000,1000);
  const fallback=[...h.timers.values()][0];assert.equal(fallback.delay,600);fallback.callback();h.flush();
  assert.equal(h.page.pagerAnimating,false);assert.equal(h.page.pagerRebuildPending,false);
  h.page.onPagerAnimationStart();h.page.resetPageSpreads();assert.equal(h.timers.size,0);
});
test('stale relocation frames cannot overwrite a newly loaded chapter',()=>{
  const h=reader();h.page.rebuildPageSpreads();h.page.generation++;h.page.resetPageSpreads();
  h.page.swiperIndex=0;h.page.currentVisibleIndex=0;h.page.rebuildPageSpreads();h.flush();
  assert.deepEqual(h.calls,[[0,false]]);assert.equal(h.page.swiperIndex,0);assert.equal(h.page.pagerRelocating,false);
});
test('a briefly unready native controller is retried once without storing a false page',()=>{
  const h=reader();const original=h.page.swiperController.changeIndex;let attempts=0;
  h.page.swiperController.changeIndex=(...args)=>{if(++attempts===1)throw new Error('not ready');original(...args);};
  h.page.rebuildPageSpreads();h.flush();assert.equal(attempts,2);assert.equal(h.page.pagerRelocating,false);assert.equal(h.writes.length,0);
});
test('slider jumps retain the precise selected original page inside a double spread',()=>{
  const h=reader();h.page.rebuildPageSpreads();h.flush();
  assert.equal(h.page.jumpToReaderPage(8),true);h.flush();assert.equal(h.page.swiperIndex,7);
  assert.equal(h.page.currentReaderPage(),8);assert.equal(h.page.currentReaderPageRange(),'7–8 / 12');
  assert.equal(h.writes.at(-1),7);h.page.updateReaderWindowSize(600,900,false);h.flush();assert.equal(h.page.currentReaderPageRange(),'8 / 12');
});
test('volume keys advance one spread and normal single-column scrolling still advances one image',()=>{
  const h=reader();h.page.rebuildPageSpreads();h.flush();h.page.turnByVolume(1);h.flush();
  assert.equal(h.page.swiperIndex,8);assert.deepEqual(h.calls.at(-1),[4,false]);
  h.page.lastVolumeTurnAt=0;h.page.turnByVolume(-1);h.flush();assert.equal(h.page.swiperIndex,6);
  h.page.readingMode=4;h.page.currentVisibleIndex=7;h.page.lastVolumeTurnAt=0;h.page.turnByVolume(1);
  assert.equal(h.page.currentVisibleIndex,8);assert.deepEqual(h.calls.at(-1),['list',8]);
});
test('restoring a saved page or switching from strips keeps the same original image',async()=>{
  const h=reader();h.page.restoreLastPage(h.cache);h.flush();assert.equal(h.page.swiperIndex,7);assert.deepEqual(h.calls.at(-1),[3,false]);
  h.page.readingMode=4;h.page.currentVisibleIndex=9;await h.page.switchReadingMode(1);h.flush();
  assert.equal(h.page.swiperIndex,9);assert.equal(h.settings.get('reader_mode'),'1');
});
test('actual user swipes save the destination image while relocation callbacks do not',()=>{
  const h=reader();h.page.rebuildPageSpreads();h.page.onPagerChange(0);assert.equal(h.writes.length,0);h.flush();
  h.page.onPagerChange(4);assert.equal(h.page.swiperIndex,8);assert.deepEqual(h.writes,[8]);
});
test('reader startup loads global layout and per-comic pairing without changing the stored reading mode',async()=>{
  const h=reader();h.settings.set('reader_mode','4');h.settings.set('reader_page_layout','double');
  h.settings.set('reader_first_single_bookA','true');h.settings.set('reader_strip_width','1000');await h.page.aboutToAppear();
  assert.equal(h.page.readingMode,4);assert.equal(h.page.pageLayout,'double');assert.equal(h.page.firstImageSingle,true);
  assert.equal(h.page.stripReaderWidth,1000);
  h.setParams({comicId:'bookB',currentOrder:1,epsCount:1});await h.page.aboutToAppear();assert.equal(h.page.firstImageSingle,false);
  assert.equal(h.settings.get('reader_first_single_bookA'),'true');
});
test('rapid layout selections only commit the most recent value',async()=>{
  const h=reader(),pending=[];h.setProvider(()=>new Promise(resolve=>pending.push(resolve)));
  const first=h.page.changePageLayout('double'),second=h.page.changePageLayout('single');
  pending[0](h.cache);await first;assert.equal(h.settings.size,0);
  pending[1](h.cache);await second;h.flush();assert.equal(h.settings.get('reader_page_layout'),'single');assert.equal(h.page.swiperIndex,7);
});
test('pairing is saved per comic and rapid toggles cannot commit an obsolete value',async()=>{
  const h=reader(),pending=[];h.page.comicId='book/a';h.setProvider(()=>new Promise(resolve=>pending.push(resolve)));
  const first=h.page.changeFirstImageSingle(true),second=h.page.changeFirstImageSingle(false);
  pending[1](h.cache);await second;pending[0](h.cache);await first;h.flush();
  assert.equal(h.settings.get('reader_first_single_book%2Fa'),'false');assert.equal(h.page.firstImageSingle,false);
  assert.equal(h.page.swiperIndex,7);
});
test('failed layout writes keep the previous setting and failed pairing rolls back to the last committed value',async()=>{
  const h=reader();h.cache.saveSetting=()=>{throw new Error('disk unavailable');};
  await h.page.changePageLayout('double');assert.equal(h.page.pageLayout,'auto');assert.equal(h.messages.length,1);
  await h.page.changeFirstImageSingle(true);h.flush();assert.equal(h.page.firstImageSingle,false);assert.equal(h.settings.size,0);
});
test('leaving the reader cancels pending setting writes',async()=>{
  const h=reader();let complete;h.setProvider(()=>new Promise(resolve=>complete=resolve));
  const request=h.page.changePageLayout('double');h.page.readerWindowActive=false;complete(h.cache);await request;
  assert.equal(h.settings.size,0);assert.equal(h.page.pageLayout,'auto');
});
test('strip width changes preserve the current original image and suppress reflow progress writes',async()=>{
  const h=reader();h.page.readingMode=4;await h.page.changeReaderStripWidth(1000);
  assert.equal(h.page.stripRelocating,true);assert.equal(h.page.stripReaderWidth,1000);
  h.flush();assert.equal(h.page.currentVisibleIndex,7);assert.equal(h.page.stripRelocating,false);
  assert.deepEqual(h.calls.at(-1),['list',7]);assert.equal(h.writes.length,0);assert.equal(h.settings.get('reader_strip_width'),'1000');
});
test('a new chapter invalidates a queued strip-width relocation',async()=>{
  const h=reader();h.page.readingMode=4;await h.page.changeReaderStripWidth(1000);
  h.page.generation++;h.page.resetPageSpreads();h.page.currentVisibleIndex=0;h.flush();
  assert.equal(h.page.currentVisibleIndex,0);assert.equal(h.page.stripRelocating,false);assert.equal(h.calls.length,0);
});
test('rapid strip-width selections commit only the most recent setting',async()=>{
  const h=reader(),pending=[];h.page.readingMode=4;h.setProvider(()=>new Promise(resolve=>pending.push(resolve)));
  const first=h.page.changeReaderStripWidth(600),second=h.page.changeReaderStripWidth(1000);
  pending[1](h.cache);await second;pending[0](h.cache);await first;h.flush();
  assert.equal(h.page.stripReaderWidth,1000);assert.equal(h.settings.get('reader_strip_width'),'1000');assert.equal(h.calls.length,1);
});
test('failed strip-width saves leave the previous display width intact',async()=>{
  const h=reader();h.cache.saveSetting=()=>{throw new Error('disk unavailable');};
  await h.page.changeReaderStripWidth(1000);assert.equal(h.page.stripReaderWidth,780);assert.equal(h.frames.length,0);
  assert.equal(h.messages.length,1);assert.equal(h.settings.size,0);
});

test('curl preference is independent of reading mode and does not relocate through the absent native swiper',async()=>{
  const h=reader();h.page.rebuildPageSpreads();h.flush();h.calls.length=0;
  await h.page.changeTurnEffect('curl');h.flush();assert.equal(h.page.turnEffect,'curl');
  assert.equal(h.settings.get('reader_turn_effect'),'curl');assert.equal(h.settings.has('reader_mode'),false);
  assert.equal(h.calls.length,0);assert.equal(h.page.swiperIndex,7);assert.equal(h.page.pagerRelocating,false);
  h.page.readingMode=2;assert.equal(h.page.usesReaderCurl(),false);
});
test('curl startup restores the preference and long gestures keep wide-image regrouping deferred',async()=>{
  const h=reader();h.settings.set('reader_turn_effect','curl');await h.page.aboutToAppear();
  assert.equal(h.page.turnEffect,'curl');h.page.readingMode=1;h.page.rebuildPageSpreads();h.flush();
  h.page.onPagerAnimationStart(true);assert.equal(h.timers.size,0);
  h.page.onReaderImageSize(7,'image-7',1800,900);assert.equal(h.page.pagerRebuildPending,true);
  h.page.onPagerAnimationEnd();h.flush();assert.equal(h.page.pageSpreads.find(s=>s.first===7).last,7);
});
test('rapid or failed effect saves preserve the last successfully chosen effect',async()=>{
  const h=reader(),pending=[];h.setProvider(()=>new Promise(resolve=>pending.push(resolve)));
  const first=h.page.changeTurnEffect('curl'),second=h.page.changeTurnEffect('slide');
  pending[1](h.cache);await second;pending[0](h.cache);await first;h.flush();
  assert.equal(h.settings.get('reader_turn_effect'),'slide');assert.equal(h.page.turnEffect,'slide');
  h.setProvider(()=>Promise.resolve(h.cache));h.cache.saveSetting=()=>{throw new Error('disk unavailable');};
  await h.page.changeTurnEffect('curl');assert.equal(h.page.turnEffect,'slide');assert.equal(h.messages.length,1);
});

test('single and double regrouping captures a layout transition while preserving the original image',async()=>{
  const h=reader();h.page.rebuildPageSpreads();h.flush();let captures=0;
  h.page.animationsOn=true;h.page.readerLayoutTransition.capture=()=>captures++;
  await h.page.changePageLayout('single');h.flush();assert.equal(captures,1);assert.equal(h.page.swiperIndex,7);
  h.page.updateReaderWindowSize(700,1000,false);h.flush();assert.equal(captures,1);
  await h.page.changePageLayout('double');h.flush();assert.equal(captures,2);assert.equal(h.page.swiperIndex,7);
});
test('portrait measurements provide actual image bounds without forcing regrouping or accepting stale images',()=>{
  const h=reader();h.page.rebuildPageSpreads();h.flush();const previous=h.page.pageSpreads.map(s=>s.key);
  h.page.onReaderImageSize(7,'image-7',600,900);assert.equal(h.page.readerImageRatios.get(7),2/3);
  assert.deepEqual(h.page.pageSpreads.map(s=>s.key),previous);
  h.page.onReaderImageSize(6,'stale-image',800,900);assert.equal(h.page.readerImageRatios.has(6),false);
});

test('switching to strip reading keeps settings open and restores the original page after layout', async () => {
  const h = reader();
  h.page.showSheet = true;
  h.page.swiperIndex = 7;
  await h.page.switchReadingMode(3);
  assert.equal(h.page.showSheet, true);
  assert.equal(h.page.stripRelocating, true);
  h.flush();
  assert.equal(h.page.currentVisibleIndex, 7);
  assert.deepEqual(h.calls.at(-1), ['list', 7]);
  assert.equal(h.page.stripRelocating, false);
  assert.equal(h.page.lastStripReadingMode, 3);
});

test('reading status visibility is restored from saved settings, and rapid toggles save the latest choice', async () => {
  const h = reader();
  h.page.readerStatusChangeId = 0;
  await h.page.aboutToAppear();
  assert.equal(h.page.readerShowStatus, false);
  await h.page.changeReaderStatus(true);
  assert.equal(h.settings.get('reader_show_status'), 'true');
  await h.page.aboutToAppear();
  assert.equal(h.page.readerShowStatus, true);
  const pending = [];
  h.setProvider(() => new Promise(resolve => pending.push(resolve)));
  const earlier = h.page.changeReaderStatus(true);
  const latest = h.page.changeReaderStatus(false);
  pending[1](h.cache);
  await latest;
  pending[0](h.cache);
  await earlier;
  assert.equal(h.settings.get('reader_show_status'), 'false');
  assert.equal(h.page.readerShowStatus, false);
});

test('fullscreen follows the reader controls and foreground lifecycle independently of the clock setting', () => {
  const h = reader();
  const page = h.page;
  page.syncReaderSystemBars();
  assert.deepEqual(h.systemBars, []);
  page.showControls = false;
  page.syncReaderSystemBars();
  assert.equal(page.readerShowStatus, false);
  assert.equal(page.isImmersiveReading(), true);
  page.onPageHide();
  page.onPageShow();
  page.showControls = true;
  page.syncReaderSystemBars();
  page.showControls = false;
  page.syncReaderSystemBars();
  page.stopObservingReaderInsets();
  assert.deepEqual(h.systemBars, [[false, true], [true, false], [false, true], [true, true], [false, true], [true, false]]);
});

test('system bars start hiding after the reader toolbars finish fading', () => {
  const h = reader();
  h.page.toggleControls();
  h.page.syncReaderSystemBars();
  assert.equal(h.page.showControls, false);
  assert.equal(h.page.readerControlsFadingOut, true);
  assert.deepEqual(h.systemBars, []);
  h.controlAnimations[0].onFinish();
  assert.equal(h.page.readerControlsFadingOut, false);
  assert.deepEqual(h.systemBars, [[false, true]]);
});

test('a cancelled reader fade cannot hide native bars after reopening controls or leaving', () => {
  for (const cancel of [page => page.toggleControls(), page => page.onPageHide()]) {
    const h = reader();
    h.page.toggleControls();
    cancel(h.page);
    h.controlAnimations[0].onFinish();
    assert.equal(h.page.readerControlsFadingOut, false);
    assert.deepEqual(h.systemBars, []);
  }
});

function reopenReaderWithHiddenSystemBars() {
  const h = reader();
  h.page.readerTopInset = 28;
  h.page.readerBottomInset = 14;
  h.page.toggleControls();
  h.controlAnimations[0].onFinish();
  h.page.readerTopInset = 0;
  h.page.readerBottomInset = 0;
  h.page.toggleControls();
  return h;
}

test('reader controls wait until both safe insets are restored before fading in', () => {
  const h = reopenReaderWithHiddenSystemBars();
  assert.deepEqual(h.systemBars, [[false, true], [true, false]]);
  assert.equal(h.page.showControls, false);
  h.page.readerTopInset = 28;
  h.page.finishReaderControlsWhenInsetsReady();
  assert.equal(h.page.showControls, false);
  h.page.readerBottomInset = 14;
  h.page.finishReaderControlsWhenInsetsReady();
  assert.equal(h.page.showControls, true);
  assert.equal(h.controlAnimations.length, 2);
  assert.equal(h.timers.has(h.page.readerControlsRevealTimer), false);
});

test('reader fade-in has a timeout and stale timeouts cannot reopen controls', () => {
  const h = reopenReaderWithHiddenSystemBars();
  const pending = h.timers.get(h.page.readerControlsRevealTimer);
  assert.equal(pending.delay, 200);
  pending.callback();
  assert.equal(h.page.showControls, true);

  for (const cancel of [page => page.toggleControls(), page => page.onPageHide()]) {
    const cancelled = reopenReaderWithHiddenSystemBars();
    const timer = cancelled.timers.get(cancelled.page.readerControlsRevealTimer);
    cancel(cancelled.page);
    timer.callback();
    assert.equal(cancelled.page.showControls, false);
    assert.equal(cancelled.controlAnimations.length, 1);
  }
});

test('restoring system bars does not change the automatic page layout breakpoint', () => {
  const h = reader();
  h.page.readerWindowWidth = 840;
  h.page.readerWindowHeight = 720;
  h.page.readerTopInset = 30;
  h.page.readerBottomInset = 18;
  h.page.rebuildPageSpreads();
  h.flush();
  assert.equal(h.page.doublePageActive, false);
  const spread = h.page.pageSpreads;
  h.page.readerTopInset = 0;
  h.page.readerBottomInset = 0;
  h.page.rebuildPageSpreads();
  assert.equal(h.page.pageSpreads, spread);
});

test('disabling animations hides the system bars immediately', () => {
  const h = reader();
  h.page.animationsOn = false;
  h.page.toggleControls();
  h.page.syncReaderSystemBars();
  assert.deepEqual(h.controlAnimations, []);
  assert.deepEqual(h.systemBars, [[false, false]]);
});

test('sheets, loading and empty chapters keep the system bars visible', () => {
  const h = reader();
  const page = h.page;
  page.showControls = false;
  for (const [key, value] of [['showSheet', true], ['isLoading', true], ['errorText', 'offline'], ['totalImages', 0]]) {
    const previous = page[key];
    page[key] = value;
    page.syncReaderSystemBars();
    assert.equal(page.isImmersiveReading(), false);
    page[key] = previous;
  }
  assert.deepEqual(h.systemBars, []);
});

test('restoring the main window wins over a pending hide and updates both system bars', async () => {
  const calls = [];
  let finishHide;
  let started;
  const hideStarted = new Promise(resolve => { started = resolve; });
  const win = {
    setSpecificSystemBarEnabled(bar, visible, animated) {
      calls.push([bar, visible, animated]);
      if (!visible && bar === 'status') {
        return new Promise(resolve => {
          finishHide = resolve;
          started();
        });
      }
      return Promise.resolve();
    }
  };
  const hide = WindowHelper.setReaderSystemBars(win, false, true);
  await hideStarted;
  const restore = WindowHelper.setReaderSystemBars(win, true, false);
  finishHide();
  await Promise.all([hide, restore]);
  assert.deepEqual(calls, [['status', false, true], ['status', true, false], ['navigationIndicator', true, false]]);
});

test('side taps follow reading direction and keep center tap and progress restoration behavior',()=>{
  const h=reader();
  h.page.rebuildPageSpreads();
  h.flush();
  h.page.curlController.turn=delta=>{h.calls.push(['curl',delta]);return true;};
  h.page.turnEffect='curl';
  h.calls.length=0;
  h.page.onReaderPagerClick(30,600);
  h.page.onReaderPagerClick(570,600);
  h.page.onReaderPagerClick(300,600);
  h.page.progressMode=true;
  h.page.onReaderPagerClick(30,600);
  assert.deepEqual(h.calls,[['curl',1],['curl',-1],['center'],['center']]);
  h.page.progressMode=false;
  h.page.turnEffect='slide';
  h.page.readingMode=0;
  h.page.animationsOn=true;
  const target=h.page.pagerDisplayIndex+1;
  h.page.onReaderPagerClick(570,600);
  assert.deepEqual(h.calls.at(-1),[target,true]);
});

test('side taps and volume turns give the chapter boundary messages',()=>{
  const h=reader();
  h.page.rebuildPageSpreads();
  h.flush();
  h.page.onPagerChange(0);
  h.page.onReaderPagerClick(570,600);
  h.page.turnByVolume(-1);
  h.page.onPagerChange(h.page.pageSpreads.length-1);
  h.page.onReaderPagerClick(30,600);
  h.page.lastVolumeTurnAt=0;
  h.page.turnByVolume(1);
  assert.deepEqual(h.messages,['已经到顶啦！','已经到顶啦！','已经到尾啦！','已经到尾啦！']);
});

test('native pager reports outward swipes once in horizontal LTR, RTL and vertical modes',()=>{
  for(const mode of [0,1,2]){
    const h=reader();
    h.page.readingMode=mode;
    h.page.rebuildPageSpreads();
    h.flush();
    const start={id:1,windowX:300,windowY:300};
    for(const index of [0,h.page.pageSpreads.length-1]){
      h.page.onPagerChange(index);
      const offset=(index===0?80:-80)*(mode===1?-1:1);
      const end={id:1,windowX:300+(mode===2?0:offset),windowY:300+(mode===2?offset:0)};
      h.page.onReaderNativePagerTouch({type:0,touches:[start],changedTouches:[start]});
      h.page.onReaderNativePagerTouch({type:1,touches:[],changedTouches:[end]});
      h.page.onReaderNativePagerTouch({type:1,touches:[],changedTouches:[end]});
    }
    assert.deepEqual(h.messages,['已经到顶啦！','已经到尾啦！']);
  }
});

test('arriving at the last native slide, multitouch and short drags do not report a boundary',()=>{
  const h=reader();
  h.page.readingMode=0;
  h.page.rebuildPageSpreads();
  h.flush();
  const last=h.page.pageSpreads.length-1;
  const begin={id:1,windowX:300,windowY:300};
  const end={id:1,windowX:200,windowY:305};
  const down=()=>h.page.onReaderNativePagerTouch({type:0,touches:[begin],changedTouches:[begin]});
  const up=touch=>h.page.onReaderNativePagerTouch({type:1,touches:[],changedTouches:[touch]});
  h.page.onPagerChange(last-1);
  down();
  h.page.onPagerChange(last);
  up(end);
  down();
  up({...end,windowX:295});
  down();
  h.page.onReaderNativePagerTouch({type:2,touches:[begin,{id:2}],changedTouches:[]});
  up(end);
  assert.deepEqual(h.messages,[]);
});

test('a paired spread is ready only when both images are decoded and an old render cannot clear the new one',()=>{
  const h=reader();
  h.page.rebuildPageSpreads();
  h.flush();
  const spread=h.page.pageSpreads[h.page.pagerDisplayIndex];
  h.page.onReaderImageDecoded(spread.first,'image-'+spread.first,11,true);
  assert.equal(h.page.isReaderSpreadDecoded(h.page.pagerDisplayIndex),false);
  h.page.onReaderImageDecoded(spread.last,'image-'+spread.last,21,true);
  h.page.onReaderImageDecoded(spread.first,'image-'+spread.first,12,true);
  h.page.onReaderImageDecoded(spread.first,'image-'+spread.first,11,false);
  assert.equal(h.page.isReaderSpreadDecoded(h.page.pagerDisplayIndex),true);
  h.page.onReaderImageDecoded(spread.first,'image-'+spread.first,12,false);
  assert.equal(h.page.isReaderSpreadDecoded(h.page.pagerDisplayIndex),false);
});
