import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtemp, mkdir, writeFile, readFile, readdir, rm } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { starterConfig } from '../lib/config-v2.mjs';
import { starterV3 } from '../lib/config-v3.mjs';
import { generationDocument, hash } from '../lib/config-store.mjs';
import { chromium } from 'playwright';

const repo = new URL('../..', import.meta.url).pathname;
const token = 'review-fixes-token';
const snapshotId = '1234567890-1234abcd';
async function fixture(t, {version = 2, hook = ''} = {}) {
  const root = await mkdtemp(join(tmpdir(), 'spacewright-fixes-'));
  let child;
  t.after(async () => {
    try {
      if (child && child.exitCode === null && child.signalCode === null) {
        const exited = new Promise(resolve => child.once('exit', resolve));
        const timer = setTimeout(() => child.kill('SIGKILL'), 2000);
        child.kill('SIGTERM'); await exited; clearTimeout(timer);
      }
      assert.equal(existsSync(join(root, 'mutations')), false);
    } finally { await rm(root, {recursive:true,force:true}); }
  });
  const configRoot = join(root, 'config'), stateRoot = join(root, 'state'), bin = join(root, 'bin');
  await Promise.all([mkdir(configRoot), mkdir(stateRoot,{recursive:true}), mkdir(bin), mkdir(join(stateRoot,'history'),{recursive:true})]);
  const config = version === 3 ? starterV3() : starterConfig();
  const sourcePath = join(configRoot, `config.v${version}.json`), runtimePath = join(configRoot,'generated/runtime.json');
  const machinePath = join(stateRoot, 'machine.json');
  const machine = version === 3 ? {version:2,hardwareProfile:'macbook',hardwareProfileConfirmed:true,activeSetup:'built_in',topologySelections:{'built_in:wide':'built_in'},displayBindings:{built_in:'DISPLAY-1'}} : {version:1,displayBindings:{primary:'DISPLAY-1'}};
  const data = {displays:[{index:1,uuid:'DISPLAY-1','is-built-in':true,frame:{x:0,y:0,w:1200,h:900}}],spaces:[{index:1,uuid:'SPACE-1',display:1,label:'coding_solo',type:'float'}],windows:[]};
  const source = JSON.stringify(config, null, 4) + '\n';
  await writeFile(sourcePath,source);await writeFile(machinePath,JSON.stringify(machine));
  await writeFile(join(root,'data.json'),JSON.stringify(data));
  await writeFile(join(bin,'sysctl'),'#!/bin/sh\necho MacBookPro18,3\n',{mode:0o755});
  await writeFile(join(bin,'yabai'),`#!${process.execPath}
const fs=require('fs'),root=process.env.FIX_ROOT,args=process.argv.slice(2);
if(args[1]==='query') {if(args[2]==='--displays'&&fs.existsSync(root+'/block-discovery')){fs.writeFileSync(root+'/discovery-ready','yes');while(!fs.existsSync(root+'/discovery-continue'))Atomics.wait(new Int32Array(new SharedArrayBuffer(4)),0,0,10);}const data=JSON.parse(fs.readFileSync(root+'/data.json'));if(fs.existsSync(root+'/incomplete')&&args[2]!=='--displays')process.exit(1);console.log(JSON.stringify(data[args[2].slice(2)]));}
else if(args[0]==='--version') console.log('fixture');
else {fs.appendFileSync(root+'/mutations',JSON.stringify(args));process.exit(97);}
`,{mode:0o755});
  const snapshotPath=join(stateRoot,`history/${snapshotId}.json`), restored=starterConfig();restored.metadata.name='Historical content';
  await writeFile(snapshotPath,JSON.stringify({name:'Review restore',reason:'apply',createdAt:'2026-10-17T00:00:00Z',config:restored}));
  const env={...process.env,FIX_ROOT:root,PATH:`${bin}:${process.env.PATH}`};
  if(hook){const hookPath=join(root,'hook.mjs');await writeFile(hookPath,hook);env.NODE_OPTIONS=`--import=${hookPath}`;}
  child=spawn(process.execPath,[join(repo,'configurator/server.mjs'),`--package-root=${repo}`,`--config-root=${configRoot}`,`--state-root=${stateRoot}`,`--token=${token}`,'--port=0','--no-open'],{env,stdio:['ignore','pipe','pipe']});

  const url=await new Promise((resolve,reject)=>{let output='';const timer=setTimeout(()=>{child.kill('SIGKILL');reject(new Error(output||'server startup timed out'));},5000);child.once('error',error=>{clearTimeout(timer);reject(error);});child.stderr.on('data',c=>output+=c);child.stdout.on('data',c=>{output+=c;const match=output.match(/SPACEWRIGHT_CONFIGURATOR_URL=(http:\/\/[^?\s]+)/);if(match){clearTimeout(timer);resolve(match[1]);}});});
  const api=async(path,body)=>{const response=await fetch(new URL(path,url),{signal:AbortSignal.timeout(10000),headers:{'x-spacewright-token':token,'content-type':'application/json'},...(body===undefined?{}:{method:'POST',body:JSON.stringify(body)})});return {status:response.status,body:await response.json()};};
  const restore=body=>api(`/api/history/${snapshotId}/restore`,body);
  return {root,configRoot,stateRoot,sourcePath,runtimePath,machinePath,machine,config,source,data,snapshotPath,restored,api,restore,url};
}
async function diskFiles(f) {
  const result={};
  for(const root of [f.configRoot,join(f.stateRoot,'history')]) {
    const walk=async(path)=>{for(const entry of await readdir(path,{withFileTypes:true})){const child=join(path,entry.name);if(entry.isDirectory())await walk(child);else result[child]=await readFile(child,'utf8');}};
    await walk(root);
  }
  return result;
}
async function waitFor(path) {
  const deadline=Date.now()+5000;
  while(!existsSync(path)&&Date.now()<deadline)await new Promise(resolve=>setTimeout(resolve,10));
  assert.ok(existsSync(path),`timed out waiting for ${path}`);
}
const readHook = `import fs from 'node:fs/promises';import {existsSync,writeFileSync} from 'node:fs';import {syncBuiltinESMExports} from 'node:module';const read=fs.readFile;const root=process.env.FIX_ROOT;`;

for(const scenario of ['no-revision','stale','missing','broken','invalid','bad-id','success','concurrent','active-v3','runtime-failure','read-back','log-failure'])test(`R2 history restore transaction: ${scenario}`,{timeout:15000},async t=>{
  const hook=scenario==='read-back'?readHook+`fs.readFile=async function(path,...args){const value=await read.call(this,path,...args);if(String(path).endsWith('/generated/runtime.json')){const doc=JSON.parse(value);doc.workspaces={};return JSON.stringify(doc);}return value;};syncBuiltinESMExports();`:'';
  const f=await fixture(t,{hook});
  const current=(await f.api('/api/config')).body;
  if(scenario==='missing')await rm(f.snapshotPath);
  if(scenario==='broken')await writeFile(f.snapshotPath,'{');
  if(scenario==='invalid')await writeFile(f.snapshotPath,JSON.stringify({config:{version:2}}));
  if(scenario==='active-v3')await writeFile(join(f.configRoot,'config.v3.json'),JSON.stringify(starterV3()));
  if(scenario==='runtime-failure')await mkdir(f.runtimePath,{recursive:true});
  if(scenario==='log-failure')await mkdir(join(f.stateRoot,'activity.jsonl'));
  const before=await diskFiles(f);
  if(scenario==='concurrent') {
    const save=structuredClone(f.config);save.metadata.name='Concurrent save';
    const results=await Promise.all([f.restore({baseRevision:current.revision}),f.api('/api/save',{config:save,baseRevision:current.revision})]);
    assert.deepEqual(results.map(r=>r.status).sort(),[200,409]);
    const saved=JSON.parse(await readFile(f.sourcePath));const runtime=JSON.parse(await readFile(f.runtimePath));
    assert.deepEqual(runtime,generationDocument(saved,null,await readFile(f.sourcePath,'utf8')));return;
  }
  const result=scenario==='bad-id'?await f.api('/api/history/invalid/restore',{baseRevision:current.revision}):await f.restore(scenario==='no-revision'?{}:{baseRevision:scenario==='stale'?'stale':current.revision});
  const expected={ 'no-revision':428,stale:409,missing:404,broken:422,invalid:422,'bad-id':404,'active-v3':409,'runtime-failure':500,'read-back':500 }[scenario]||200;
  assert.equal(result.status,expected,JSON.stringify(result.body));
  if(expected===200){assert.deepEqual(JSON.parse(await readFile(f.sourcePath)),f.restored);assert.equal(result.body.verified,true);assert.deepEqual(JSON.parse(await readFile(f.runtimePath)),generationDocument(f.restored,null,await readFile(f.sourcePath,'utf8')));const snapshots=await readdir(join(f.stateRoot,'history'));assert.ok((await Promise.all(snapshots.map(async name=>JSON.parse(await readFile(join(f.stateRoot,'history',name)))))).some(d=>d.reason==='before-restore'&&d.config.metadata.name===f.config.metadata.name));if(scenario==='log-failure')assert.ok(result.body.warnings.length);}
  else if(expected!==500){assert.deepEqual(await diskFiles(f),before);assert.equal(existsSync(join(f.configRoot,'.configuration-write')),false);}
  else {assert.equal(existsSync(join(f.configRoot,'.configuration-write')),true);assert.equal((await f.api('/api/config')).status,500);}
});

for(const scenario of ['unknown-app','schema','unconfirmed','binding','partial','unavailable','v2','v3'])test(`R4 structured diagnostics: ${scenario}`,async t=>{
  const f=await fixture(t,{version:scenario==='v2'?2:3});
  if(scenario==='unknown-app')f.config.workspaces.coding.windows.editor.app='does_not_exist';
  if(scenario==='schema')f.config.workspaces=null;
  if(['unknown-app','schema'].includes(scenario))await writeFile(f.sourcePath,JSON.stringify(f.config));
  if(scenario==='unconfirmed'){f.machine.hardwareProfileConfirmed=false;await writeFile(f.machinePath,JSON.stringify(f.machine));}
  if(scenario==='binding'){f.machine.displayBindings.built_in='MISSING';await writeFile(f.machinePath,JSON.stringify(f.machine));}
  if(scenario==='partial')await writeFile(join(f.root,'incomplete'),'yes');
  if(scenario==='unavailable')await writeFile(join(f.root,'bin/yabai'),'#!/bin/sh\nexit 1\n',{mode:0o755});
  const before=await diskFiles(f),machineBefore=await readFile(f.machinePath,'utf8');
  const result=await f.api('/api/diagnostics');assert.equal(result.status,200,JSON.stringify(result.body));
  const checks=Object.fromEntries(result.body.checks.map(check=>[check.id,check]));
  if(['unknown-app','schema'].includes(scenario)){assert.equal(checks.schema.ok,false);assert.equal(checks.hardware_setup.ok,null);assert.equal(checks.compiled_runtime.ok,null);assert.match(checks.schema.detail,scenario==='unknown-app'?/does_not_exist|unknown app/:/workspaces/);}
  if(['unconfirmed','binding','partial','unavailable'].includes(scenario)){assert.notEqual(checks.hardware_setup.ok,true);assert.equal(checks.compiled_runtime.ok,null);assert.equal(result.body.reconciliation,null);}
  if(['v2','v3'].includes(scenario)){assert.equal(checks.schema.ok,true);if(scenario==='v3')assert.equal(checks.hardware_setup.ok,true);}
  assert.deepEqual(await diskFiles(f),before);assert.equal(await readFile(f.machinePath,'utf8'),machineBefore);
});

for(const version of [2,3])for(const scenario of ['healthy','body','body-and-digest','source','compiler','source-version','format','context','generation','missing','broken','metadata','geometry','machine','guard','changed-machine','changed-source','changed-version','changed-runtime'])test(`R3 diagnostic runtime v${version}: ${scenario}`,{timeout:15000},async t=>{
  const hook=['changed-machine','changed-source','changed-version','changed-runtime'].includes(scenario)?readHook+`let changed=false;fs.readFile=async function(path,...args){const value=await read.call(this,path,...args);if(String(path).endsWith('/generated/runtime.json')&&!changed){changed=true;writeFileSync(root+'/ready','yes');while(!existsSync(root+'/continue'))await new Promise(r=>setTimeout(r,10));}return value;};syncBuiltinESMExports();`:'';
  const f=await fixture(t,{version,hook});
  let resolution=null;
  if(version===3){const setup=(await f.api('/api/v3/setup')).body;resolution={machine:setup.machine,hardware:setup.hardware,snapshot:setup.snapshot};}
  if (scenario === 'body') { f.source=JSON.stringify(f.config,null,2)+'\n';await writeFile(f.sourcePath,f.source); }
  const healthy=generationDocument(f.config,resolution,f.source),runtime=structuredClone(healthy);
  if(scenario==='body'||scenario==='body-and-digest')runtime.workspaces={};
  if(scenario==='body-and-digest'){const {generated,...body}=runtime;runtime.generated.runtime_sha256=hash(body);}
  const fields={source:'source_sha256',compiler:'compiler_version','source-version':'source_version',format:'format_version',context:'context_sha256',generation:'generation_id'};
  if(fields[scenario])runtime.generated[fields[scenario]]='changed';
  if(scenario==='metadata')delete runtime.generated.runtime_sha256;
  await mkdir(join(f.configRoot,'generated'),{recursive:true});
  if(scenario!=='missing')await writeFile(f.runtimePath,scenario==='broken'?'{':JSON.stringify(runtime,null,4)+'\n');
  if(scenario==='geometry'){f.data.displays[0].frame.w+=100;await writeFile(join(f.root,'data.json'),JSON.stringify(f.data));}
  if(scenario==='machine'){f.machine.marker='changed';await writeFile(f.machinePath,JSON.stringify(f.machine));}
  if(scenario==='guard')await mkdir(join(f.configRoot,'.configuration-write'));
  let result;
  if(scenario.startsWith('changed-')) {
    const pending=f.api('/api/diagnostics');await waitFor(join(f.root,'ready'));
    if(scenario==='changed-machine'){f.machine.marker='during discovery';await writeFile(f.machinePath,JSON.stringify(f.machine));}
    if(scenario==='changed-source')await writeFile(f.sourcePath,JSON.stringify({...f.config,metadata:{name:'During diagnostic'}}));
    if(scenario==='changed-version') {if(version===2)await writeFile(join(f.configRoot,'config.v3.json'),JSON.stringify(starterV3()));else await rm(f.sourcePath);}
    if(scenario==='changed-runtime')await writeFile(f.runtimePath,JSON.stringify({...runtime,workspaces:{}}));
    await writeFile(join(f.root,'continue'),'yes');result=await pending;
  } else result=await f.api('/api/diagnostics');
  assert.equal(result.status,200,JSON.stringify(result.body));
  const check=result.body.checks.find(c=>c.id==='compiled_runtime');
  if(scenario==='healthy'||version===2&&['geometry','machine'].includes(scenario))assert.equal(check.ok,true,check.detail);
  else if(scenario==='guard'||scenario.startsWith('changed-')){assert.equal(check.ok,null,check.detail);assert.match(check.detail,/progress|generation|changed|incomplete/i);}
  else {assert.equal(check.ok,false,check.detail);assert.notEqual(check.detail,'source digest is current');}
});

for(const scenario of ['conflict','same-page-save','success'])test(`R2 browser history restore: ${scenario}`,{timeout:30000},async t=>{
  const f=await fixture(t);
  const chrome='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
  const browser=await chromium.launch({headless:true,...(existsSync(chrome)?{executablePath:chrome}:{})});t.after(()=>browser.close());
  const page=await browser.newPage({viewport:{width:1440,height:1000}}),errors=[];page.on('pageerror',error=>errors.push(error.message));
  await page.goto(`${f.url}?token=${token}&view=apps`);await page.waitForLoadState('networkidle');
  await page.locator('.app-list-row').filter({has:page.locator('[data-app-name="code"]')}).locator('summary').click();
  await page.locator('[data-app-name="code"]').fill('Preserved local draft');
  await page.locator('[data-app-name="code"]').dispatchEvent('change');
  await page.locator('#nav [data-view="history"]').click();await page.locator(`[data-restore-snapshot="${snapshotId}"]`).click();
  const initial=(await f.api('/api/config')).body;
  if(scenario==='conflict') {
    const config=structuredClone(f.config);config.metadata.name='Other page saved';
    assert.equal((await f.api('/api/save',{config,baseRevision:initial.revision})).status,200);
  }
  if(scenario==='same-page-save') {
    // Saving in the same page updates the mutable serverRevision while the
    // original restoration confirmation remains open.
    await page.evaluate(()=>document.querySelector('#save').click());
    const saved=page.waitForResponse(response=>response.url().endsWith('/api/save'));
    await page.locator('dialog').last().getByRole('button',{name:'Save Changes'}).click();assert.equal((await saved).status(),200);
  }
  const response=page.waitForResponse(response=>response.url().endsWith(`/api/history/${snapshotId}/restore`));
  await page.locator('dialog').getByRole('button',{name:'Restore Snapshot'}).click();
  const restored=await response;assert.equal(restored.status(),scenario==='success'?200:409);
  assert.equal(restored.request().postDataJSON().baseRevision,initial.revision);
  if(scenario!=='success') {
    await page.getByText('The configuration changed. Your draft is preserved; reload and compare before restoring.',{exact:true}).waitFor();
    await page.locator('#nav [data-view="apps"]').click();
    assert.equal(await page.locator('[data-app-name="code"]').inputValue(),'Preserved local draft');
    const disk=JSON.parse(await readFile(f.sourcePath));assert.equal(scenario==='conflict'?disk.metadata.name:disk.apps.code.name,scenario==='conflict'?'Other page saved':'Preserved local draft');
  } else {
    await page.locator('#nav [data-view="apps"]').click();await page.locator('.app-list-row').filter({has:page.locator('[data-app-name="code"]')}).locator('summary').click();
    await page.locator('[data-app-name="code"]').fill('After restoration');await page.locator('[data-app-name="code"]').dispatchEvent('change');
    const saved=page.waitForResponse(response=>response.url().endsWith('/api/save'));
    await page.locator('#save').click();await page.locator('dialog').getByRole('button',{name:'Save Changes'}).click();assert.equal((await saved).status(),200);
    assert.equal(JSON.parse(await readFile(f.sourcePath)).apps.code.name,'After restoration');
  }
  assert.deepEqual(errors,[]);
});

test('R4 browser renders semantic diagnostic errors without modifying configuration',{timeout:30000},async t=>{
  const f=await fixture(t,{version:3});
  const chrome='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
  const browser=await chromium.launch({headless:true,...(existsSync(chrome)?{executablePath:chrome}:{})});t.after(()=>browser.close());
  const page=await browser.newPage({viewport:{width:1440,height:1000}}),errors=[];page.on('pageerror',e=>errors.push(e.message));
  await page.goto(`${f.url}?token=${token}&view=hardware`);await page.waitForLoadState('networkidle');
  f.config.workspaces.coding.windows.editor.app='unknown_diagnostic_app';await writeFile(f.sourcePath,JSON.stringify(f.config));
  const before=await diskFiles(f);
  await page.locator('#nav [data-view="diagnostics"]').click();
  await page.locator('.diagnostic').filter({has:page.getByRole('heading',{name:'schema',exact:true})}).getByText(/unknown_diagnostic_app/).waitFor();
  assert.equal(await page.locator('.diagnostic.unknown').filter({has:page.getByRole('heading',{name:'hardware_setup',exact:true})}).count(),1);
  assert.equal(await page.locator('.diagnostic.unknown').filter({has:page.getByRole('heading',{name:'compiled_runtime',exact:true})}).count(),1);
  assert.deepEqual(errors,[]);assert.deepEqual(await diskFiles(f),before);
});


test('R3 machine changes during discovery invalidate the complete diagnostic view',async t=>{
  const f=await fixture(t,{version:3});
  const setup=(await f.api('/api/v3/setup')).body;
  const runtime=generationDocument(f.config,{machine:setup.machine,hardware:setup.hardware,snapshot:setup.snapshot},f.source);
  await mkdir(join(f.configRoot,'generated'));await writeFile(f.runtimePath,JSON.stringify(runtime));
  await writeFile(join(f.root,'block-discovery'),'yes');
  const pending=f.api('/api/diagnostics');await waitFor(join(f.root,'discovery-ready'));
  f.machine.displayBindings.built_in='REPLACED';await writeFile(f.machinePath,JSON.stringify(f.machine));
  await writeFile(join(f.root,'discovery-continue'),'yes');
  const result=await pending;assert.equal(result.status,200);
  for(const id of ['schema','hardware_setup','compiled_runtime']) {
    const check=result.body.checks.find(c=>c.id===id);assert.equal(check.ok,null,check.detail);assert.match(check.detail,/generation.*changed/);
  }
  assert.equal(result.body.reconciliation,null);assert.equal(await readFile(f.runtimePath,'utf8'),JSON.stringify(runtime));
});

test('R2 queued restore rechecks active v3 after the preceding writer releases its guard',{timeout:15000},async t=>{
  const hook=readHook+`
const originalThen=Promise.prototype.then;let queued=0;
Promise.prototype.then=function(fulfilled,...rest){if(fulfilled?.name==='guarded'&&++queued===2)writeFileSync(root+'/queued','yes');return originalThen.call(this,fulfilled,...rest);};
const remove=fs.rm;let held=false;
fs.rm=async function(path,...args){if(String(path).endsWith('/.configuration-write')&&!held){held=true;writeFileSync(root+'/writer-ready','yes');while(!existsSync(root+'/writer-continue'))await new Promise(r=>setTimeout(r,10));}return remove.call(this,path,...args);};syncBuiltinESMExports();`;
  const f=await fixture(t,{hook});
  const initial=(await f.api('/api/config')).body;
  const config=structuredClone(f.config);config.metadata.name='First writer';
  const saving=f.api('/api/save',{config,baseRevision:initial.revision});await waitFor(join(f.root,'writer-ready'));
  const runtimeBefore=await readFile(f.runtimePath,'utf8'),sourceBefore=await readFile(f.sourcePath,'utf8');
  const restoring=f.restore({baseRevision:initial.revision});await waitFor(join(f.root,'queued'));
  await writeFile(join(f.configRoot,'config.v3.json'),JSON.stringify(starterV3()));
  await writeFile(join(f.root,'writer-continue'),'yes');
  assert.equal((await saving).status,200);const result=await restoring;
  assert.equal(result.status,409);assert.equal(result.body.code,'active_version_conflict');
  assert.equal(await readFile(f.sourcePath,'utf8'),sourceBefore);assert.equal(await readFile(f.runtimePath,'utf8'),runtimeBefore);
  assert.equal(existsSync(join(f.configRoot,'.configuration-write')),false);
});
