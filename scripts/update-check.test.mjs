import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const studio = process.env.DEVECO_STUDIO_HOME || path.join(process.env.ProgramFiles || 'C:\\Program Files','Huawei','DevEco Studio');
const ts = require(path.join(process.env.DEVECO_SDK_HOME || path.join(studio,'sdk'),
  'default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = process.env.BIKA_PROJECT_ROOT || fileURLToPath(new URL('../',import.meta.url));
const read = file => fs.readFileSync(path.join(root,'entry/src/main/ets',file),'utf8').replace(/\r\n/g,'\n');
const release = (tag='v1.5.0', extra={}) => ({ status:200, body:JSON.stringify({ tag_name:tag, body:'fixture notes',
  html_url:'https://example.invalid/untrusted', draft:false, prerelease:false, ...extra }), headers:{} });
const failure = code => Object.assign(new Error('Internet error'),{code});
function load(source, deps={},globals={}) {
  const context={exports:{},require:name=>deps[name]??{},console,...globals}; vm.createContext(context);
  vm.runInContext(ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2021,module:ts.ModuleKind.CommonJS}}).outputText,context);
  return context.exports;
}
function harness(rcpQueue=[release()],httpQueue=[]) {
  const calls=[],sessions=[],requests=[];
  const next=queue=>{const value=queue.shift(); if(value instanceof Error)throw value;
    if(!value)throw failure(999); return value;};
  const rcp={Request:class {constructor(url,method,headers){Object.assign(this,{url,method,headers});}},
    createSession(config){const session={config,closed:false,async fetch(req){calls.push({kind:'rcp',req,config});
      const r=next(rcpQueue); return {statusCode:r.status,headers:r.headers,toString:()=>r.body};},close(){session.closed=true;}};
      sessions.push(session);return session;}};
  const http={RequestMethod:{GET:'GET'},HttpDataType:{STRING:'STRING'},createHttp(){
    const req={closed:false,async request(url,options){calls.push({kind:'http',url,options}); const r=next(httpQueue);
      return {responseCode:r.status,result:r.body,header:r.headers};},destroy(){req.closed=true;}};
    requests.push(req);return req;}};
  const {AppUpdateService}=load(read('network/AppUpdateService.ets'),{'@kit.RemoteCommunicationKit':{rcp},'@kit.NetworkKit':{http}});
  return {AppUpdateService,calls,sessions,requests};
}

for(const [next,current,expected] of [
  ['1.5.0','1.4.7',true],['1.4.7','1.5.0',false],['1.5.0','1.5.0',false],['1.4.10','1.4.9',true],
  ['1.10.0','1.9.99',true],['2.0.0','1.99.99',true],['v1.5.0','V1.4.7',true],['1.4.99','1.5.0',false]
]) test(`numeric version comparison: ${next} vs ${current}`,()=>{
  assert.equal(harness().AppUpdateService.isNewer(next,current),expected);
});
test('invalid versions do not invent an update or fallback to an old local version',()=>{
  const {AppUpdateService:s}=harness(); for(const value of ['','1.5','1.5.0-beta','01.5.0','999999999999999999999.0.0']){
    assert.throws(()=>s.isNewer(value,'1.4.7')); assert.throws(()=>s.isNewer('1.5.0',value));
  }
});
test('successful RCP request has public GitHub headers and a canonical release link',async()=>{
  const h=harness(); const r=await h.AppUpdateService.latest(false); assert.equal(r.version,'1.5.0');
  assert.equal(r.url,'https://github.com/LoMoCatAp/Bika-HarmonyOS/releases/tag/v1.5.0');
  assert.equal(h.calls.length,1); assert.equal(h.calls[0].config.requestConfiguration.proxy,'no-proxy');
  assert.equal(h.calls[0].req.headers['User-Agent'],'Bika-HarmonyOS');
  assert.equal(h.calls[0].req.headers.Accept,'application/vnd.github+json');
  assert.equal(h.calls[0].req.headers.Authorization,undefined); assert(h.sessions[0].closed);
});
test('RCP Internet error falls back to a separately configured HTTP request',async()=>{
  const h=harness([failure(1007900999)],[release('v1.4.7')]); const r=await h.AppUpdateService.latest(false);
  assert.equal(r.version,'1.4.7'); assert.deepEqual(h.calls.map(v=>v.kind),['rcp','http']);
  assert.equal(h.calls[1].options.usingProxy,false); assert.equal(h.calls[1].options.remoteValidation,undefined);
  assert(h.sessions.every(v=>v.closed)); assert(h.requests.every(v=>v.closed));
});
test('system proxy preference applies to both transports',async()=>{
  const h=harness([failure(1007900995)],[release()]); await h.AppUpdateService.latest(true);
  assert.equal(h.calls[0].config.requestConfiguration.proxy,'system'); assert.equal(h.calls[1].options.usingProxy,true);
});
test('a broken or absent HTTP system proxy can fall back to a normal domain connection',async()=>{
  const h=harness([failure(1007900995),release()],[failure(2300005)]); await h.AppUpdateService.latest(true);
  assert.deepEqual(h.calls.map(v=>v.kind),['rcp','http','rcp']);
  assert.equal(h.calls[2].config.requestConfiguration.proxy,'no-proxy'); assert(h.sessions.every(v=>v.closed));
});
test('total network failure produces a useful message and closes every request',async()=>{
  const h=harness([failure(1007900999)],[failure(2300999)]);
  await assert.rejects(h.AppUpdateService.latest(false),error=>!error.message.includes('Internet error')&&error.message.includes('2300999'));
  assert.equal(h.calls.length,2); assert(h.sessions.every(v=>v.closed)); assert(h.requests.every(v=>v.closed));
});
test('timeout has a distinct user-facing error',async()=>{
  const h=harness([failure(1007900028)],[failure(2300028)]); await assert.rejects(h.AppUpdateService.latest(false),/连接 GitHub 超时/);
});
test('a primary rate limit stops retries and blocks immediate repeated checks',async()=>{
  const h=harness([{status:403,body:'rate limit exceeded',headers:{'X-RateLimit-Remaining':'0','Retry-After':'120'}}]);
  await assert.rejects(h.AppUpdateService.latest(false),/过于频繁/); await assert.rejects(h.AppUpdateService.latest(false),/过于频繁/);
  assert.equal(h.calls.length,1); assert.equal(h.requests.length,0);
});
test('secondary rate limits are not retried through another transport',async()=>{
  const h=harness([{status:429,body:'slow down',headers:{}}]); await assert.rejects(h.AppUpdateService.latest(true),/过于频繁/);
  assert.equal(h.calls.length,1);
});
test('ordinary HTTP 403 remains a service error rather than falsely claiming rate limiting',async()=>{
  const h=harness([{status:403,body:'forbidden',headers:{}}]); await assert.rejects(h.AppUpdateService.latest(false),/HTTP 403/);
  assert.equal(h.calls.length,1);
});
test('HTTP 404 is not treated as latest or as a generic network error',async()=>{
  const h=harness([{status:404,body:'{}',headers:{}}]); await assert.rejects(h.AppUpdateService.latest(false),/暂无可用的正式发布版本/);
});
test('upstream HTTP 500 is not blindly retried',async()=>{
  const h=harness([{status:500,body:'error',headers:{}}]); await assert.rejects(h.AppUpdateService.latest(false),/HTTP 500/);
  assert.equal(h.calls.length,1);
});
test('HTML or malformed JSON does not report a successful update check',async()=>{
  for(const body of ['<html>proxy page</html>','{bad']) {
    const h=harness([{status:200,body,headers:{}}]); await assert.rejects(h.AppUpdateService.latest(false),/返回内容异常/);
  }
});
test('missing metadata, drafts, prereleases and non-version tags cannot prompt an update',async()=>{
  for(const r of [{status:200,body:'null',headers:{}},{status:200,body:'[]',headers:{}},release('v1.5.0',{draft:true}),
    release('v1.5.0',{prerelease:true}),release('latest')]) {
    const h=harness([r]); await assert.rejects(h.AppUpdateService.latest(false));
  }
});
test('null release notes become an empty string rather than visible null text',async()=>{
  const h=harness([release('v1.5.0',{body:null})]); assert.equal((await h.AppUpdateService.latest(false)).body,'');
});

function pageHarness() {
  const source=read('pages/IndexPage.ets'), start=source.indexOf('  private async checkUpdate()');
  const end=source.indexOf('  /** Markdown',start); const h=harness(); const messages=[]; let finish;
  h.AppUpdateService.latest=async()=>await new Promise(resolve=>finish=resolve);
  const {Page}=load('export class Page {\n'+source.slice(start,end)+'\n}',{}, {AppUpdateService:h.AppUpdateService,
    ApiService:{isProxyMode:()=>false},AppStorage:{get:()=> '1.5.0'},showImmersiveToast:value=>messages.push(value)});
  const page=new Page(); Object.assign(page,{checkingUpdate:false,visibleSubpage:'settings',showAboutSheet:false});
  return {page,messages,respond:release=>finish(release)};
}
test('settings page does not show the published 1.4.7 as an update for local 1.5.0',async()=>{
  const h=pageHarness(), pending=h.page.checkUpdate(); h.respond({version:'1.4.7',body:'notes',url:'url'}); await pending;
  assert.equal(h.page.showAboutSheet,false); assert(h.messages[0].message.includes('暂无更新')); assert.equal(h.page.checkingUpdate,false);
});
test('a genuinely newer version opens the existing update sheet',async()=>{
  const h=pageHarness(), pending=h.page.checkUpdate(); h.respond({version:'1.5.1',body:'new',url:'url'}); await pending;
  assert.equal(h.page.showAboutSheet,true); assert.equal(h.page.updateVersion,'1.5.1'); assert.equal(h.page.updateBody,'new');
});
test('leaving settings prevents delayed requests from opening an update sheet elsewhere',async()=>{
  const h=pageHarness(), pending=h.page.checkUpdate(); h.page.visibleSubpage='';
  h.respond({version:'1.5.1',body:'new',url:'url'}); await pending; assert.equal(h.page.showAboutSheet,false);
  assert.equal(h.messages.length,0); assert.equal(h.page.checkingUpdate,false);
});
