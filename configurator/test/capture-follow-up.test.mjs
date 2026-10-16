import test from 'node:test';
import assert from 'node:assert/strict';
import {execFile,spawn} from 'node:child_process';
import {promisify} from 'node:util';
import {mkdtemp,mkdir,writeFile,readFile,rm} from 'node:fs/promises';
import {existsSync} from 'node:fs';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {chromium} from 'playwright';
import {starterConfig,validateV2} from '../lib/config-v2.mjs';
import {normalizeSnapshot,captureWorkspace} from '../lib/state-engine.mjs';
import {mergeCapturedWorkspace} from '../lib/capture-merge.mjs';

const exec=promisify(execFile),repo=new URL('../..',import.meta.url).pathname;
async function fixture(t) {
  const root=await mkdtemp(join(tmpdir(),'spacewright-capture-')),configRoot=join(root,'config'),stateRoot=join(root,'state'),bin=join(root,'bin');
  await Promise.all([mkdir(configRoot),mkdir(stateRoot),mkdir(bin)]);
  const config=starterConfig();config.apps.finder={name:'Finder',match:{appNames:['Finder']}};config.workspaces.coding.windows.editor.app='finder';
  const machine={version:1,displayBindings:{primary:'DISPLAY-PRIMARY'}};
  const data={displays:[{index:1,uuid:'DISPLAY-PRIMARY',frame:{x:0,y:0,w:1200,h:900},'is-built-in':true}],spaces:[{index:1,uuid:'SPACE-CAPTURE',display:1,label:'captured_solo',type:'float','has-focus':true}],windows:[0,1].map(index=>({id:10+index,pid:process.pid,app:'Code',title:index?'B & C':'<A "quoted">',role:'AXWindow',subrole:'AXStandardWindow',display:1,space:1,frame:{x:index*600,y:0,w:600,h:900},'can-move':true,'can-resize':true,'is-visible':true}))};
  await writeFile(join(configRoot,'config.v2.json'),JSON.stringify(config));await writeFile(join(stateRoot,'machine.json'),JSON.stringify(machine));
  await writeFile(join(root,'data.json'),JSON.stringify(data));
  await writeFile(join(bin,'yabai'),`#!${process.execPath}
const fs=require('fs'),root=process.env.CAPTURE_ROOT,path=root+'/data.json',data=JSON.parse(fs.readFileSync(path)),args=process.argv.slice(2);
if(args[1]==='query') {
 const values=data[args[2].slice(2)];
 if(args[3]==='--window')console.log(JSON.stringify(data.windows.find(w=>w.id===Number(args[4]))));
 else if(args[3]==='--space')console.log(JSON.stringify(args[4]?values.find(s=>s.index===Number(args[4])):values[0]));
 else console.log(JSON.stringify(values));
} else {
 fs.appendFileSync(root+'/mutations',JSON.stringify(args)+'\\n');
 const window=data.windows.find(w=>w.id===Number(args[2]));
 if(args[1]==='window'&&args[3]==='--grid') {
  const [rows,cols,x,y,w,h]=args[4].split(':').map(Number),display=data.displays[0].frame;
  window.frame={x:display.x+display.w*x/cols,y:display.y+display.h*y/rows,w:display.w*w/cols,h:display.h*h/rows};
 }
 fs.writeFileSync(path,JSON.stringify(data));
}
`,{mode:0o755});
  const env={...process.env,CAPTURE_ROOT:root,PATH:`${bin}:${process.env.PATH}`,SPACEWRIGHT_CONFIG_ROOT:configRoot,SPACEWRIGHT_STATE_ROOT:stateRoot};
  t.after(()=>rm(root,{recursive:true,force:true}));
  return {root,configRoot,stateRoot,config,machine,data,env};
}
async function service(t,f) {
  const token='capture-test-token',child=spawn(process.execPath,[join(repo,'configurator/server.mjs'),`--config-root=${f.configRoot}`,`--state-root=${f.stateRoot}`,`--package-root=${repo}`,`--token=${token}`,'--port=0','--no-open'],{env:f.env,stdio:['ignore','pipe','pipe']});
  const url=await new Promise((resolve,reject)=>{let output='';const timer=setTimeout(()=>reject(new Error(output)),5000);child.stderr.on('data',chunk=>output+=chunk);child.stdout.on('data',chunk=>{output+=chunk;const match=output.match(/SPACEWRIGHT_CONFIGURATOR_URL=(http:\/\/[^?\s]+)/);if(match){clearTimeout(timer);resolve(match[1]);}});});
  t.after(async()=>{if(child.exitCode===null){child.kill('SIGTERM');await new Promise(resolve=>child.once('exit',resolve));}});
  const request=async(path,payload)=>{const result=await fetch(new URL(path,url),{method:payload?'POST':'GET',headers:{'x-spacewright-token':token,'content-type':'application/json'},...(payload?{body:JSON.stringify(payload)}:{})});return {status:result.status,body:await result.json()};};
  return {url,token,request};
}

test('F3 public capture → merge → validate → plan → simulated apply → verify preserves each role',async t=>{
  const f=await fixture(t),s=await service(t,f);
  const cli=await exec(join(repo,'bin/spacewright'),['capture','captured','solo','--label=captured'],{env:f.env});
  const captured=await s.request('/api/capture',{workspaceId:'captured',mode:'solo',spaceLabel:'captured'});
  assert.equal(captured.status,200,JSON.stringify(captured.body));assert.deepEqual(JSON.parse(cli.stdout).draft,captured.body.draft);
  const merged=await s.request('/api/capture/merge',{captureId:captured.body.captureId,config:f.config});
  assert.equal(merged.status,200,JSON.stringify(merged.body));assert.equal(validateV2(merged.body.config).valid,true);
  const validated=await s.request('/api/validate',merged.body.config);assert.equal(validated.status,200);
  await writeFile(join(f.configRoot,'config.v2.json'),JSON.stringify(merged.body.config));
  // Scramble the geometry after capture: successful verification must restore
  // each title to its own original half, rather than swap identical selectors.
  f.data.windows.reverse();f.data.windows[0].frame.x=0;f.data.windows[1].frame.x=600;
  await writeFile(join(f.root,'data.json'),JSON.stringify(f.data));
  const plan=JSON.parse((await exec(join(repo,'bin/spacewright'),['plan','captured','solo','--json'],{env:f.env})).stdout);
  assert.equal(plan.plan.executable,true);assert.deepEqual(plan.plan.selectedWindows.map(w=>w.id),[10,11]);
  const applied=JSON.parse((await exec(join(repo,'bin/spacewright'),['apply','captured','solo','--json'],{env:f.env})).stdout);
  assert.equal(applied.status,'completed');
  const verified=JSON.parse((await exec(join(repo,'bin/spacewright'),['verify','captured','solo','--json'],{env:f.env})).stdout);assert.equal(verified.converged,true);
  const final=JSON.parse(await readFile(join(f.root,'data.json')));
  assert.equal(final.windows.find(w=>w.title==='<A "quoted">').frame.x,0);
  assert.equal(final.windows.find(w=>w.title==='B & C').frame.x,600);
  const portable=JSON.stringify(captured.body.draft);assert.equal(/windowId|pid|DISPLAY-PRIMARY|SPACE-CAPTURE/.test(portable),false);
});

for(const scenario of ['alias-expansion','ownership'])test(`F3 merge refuses ${scenario} without changing the draft`,async t=>{
  const f=await fixture(t),snapshot=normalizeSnapshot(f.data,f.machine),capture=captureWorkspace(snapshot,{workspaceId:'captured',mode:'solo',spaceLabel:'captured'});
  if(scenario==='alias-expansion'){
    f.config.apps.code.match.appNames.push('Code Helper');snapshot.windows.push({...snapshot.windows[0],id:99,app:'Code Helper'});
  } else f.config.workspaces.coding.windows.editor.app='code';
  const before=JSON.stringify(f.config);
  assert.throws(()=>mergeCapturedWorkspace(f.config,capture,snapshot,f.machine),e=>e.code==='capture_merge_conflict');
  assert.equal(JSON.stringify(f.config),before);
});

test('F3 CLI and HTTP refuse ambiguous capture with no successful draft',async t=>{
  const f=await fixture(t),s=await service(t,f);f.data.windows[1].title=f.data.windows[0].title;
  await writeFile(join(f.root,'data.json'),JSON.stringify(f.data));
  await assert.rejects(exec(join(repo,'bin/spacewright'),['capture','captured','solo'],{env:f.env}),error=>{assert.equal(error.stdout,'');assert.match(error.stderr,/Cannot uniquely capture/);return true;});
  const result=await s.request('/api/capture',{workspaceId:'captured',mode:'solo'});
  assert.equal(result.status,422);assert.equal(result.body.code,'capture_ambiguous');assert.equal(result.body.details.candidateCount,2);assert.equal(result.body.draft,undefined);
  assert.equal(existsSync(join(f.root,'mutations')),false);
});

test('F3 browser capture accepts checked selectors and preserves a conflicting dirty draft',async t=>{
  const f=await fixture(t),s=await service(t,f),chrome='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
  const browser=await chromium.launch({headless:true,...(existsSync(chrome)?{executablePath:chrome}:{})});t.after(()=>browser.close());
  const page=await browser.newPage({viewport:{width:1440,height:1000}}),errors=[];page.on('pageerror',e=>errors.push(e.message));
  await page.goto(`${s.url}?token=${s.token}&mode=solo&view=current`);
  await page.locator('#capture-id').fill('captured');await page.locator('#capture-name').fill('Captured');
  await page.getByRole('button',{name:'Capture into editor'}).click();
  await page.locator('#workspace-id').waitFor();assert.equal(await page.locator('#workspace-id').inputValue(),'captured');
  assert.match(await page.locator('#status').innerText(),/Unsaved/);
  assert.match(await page.locator('.capture-preview').innerText(),/<A "quoted">/);
  assert.equal(await page.locator('.capture-preview script').count(),0);
  await page.screenshot({path:join(tmpdir(),'spacewright-capture-preview.png')});
  // A second capture of the same windows would steal ownership from this draft.
  await page.locator('#nav [data-view=current]').click();await page.locator('#capture-id').fill('conflicting');await page.locator('#capture-name').fill('Conflicting');
  const response=page.waitForResponse(r=>r.url().endsWith('/api/capture/merge'));
  await page.getByRole('button',{name:'Capture into editor'}).click();assert.equal((await response).status(),422);
  assert.match(await page.locator('#status').innerText(),/Unsaved/);
  await page.locator('#nav [data-view=workspaces]').click();assert.equal(await page.locator('#workspace-id').inputValue(),'captured');
  assert.equal(existsSync(join(f.root,'mutations')),false);assert.deepEqual(errors,[]);
});
