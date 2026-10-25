import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync, execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdtemp, mkdir, readFile, writeFile, rm, readdir } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { starterConfig, compileV2 } from '../lib/config-v2.mjs';
import { normalizeSnapshot, buildDesiredState, compareState, buildExecutionPlan } from '../lib/state-engine.mjs';
import { selectRole } from '../lib/window-policy.mjs';
import { discoverState } from '../lib/discovery.mjs';
import { generationDocument, stableRead, withConfigurationWrite } from '../lib/config-store.mjs';
import { acquireExecution, processIdentity, runBounded, verifyLease } from '../lib/execution-coordinator.mjs';
import { runWebTask, cancelWebTask } from '../lib/task-coordinator.mjs';
const exec = promisify(execFile);
const root = new URL('../..', import.meta.url).pathname;
const fish = (code) => execFileSync('fish', ['--no-config', '-c', code], { cwd: root, encoding: 'utf8' }).trim();
const machine = { version: 1, displayBindings: { primary: 'D' } };
const raw = () => ({ displays: [{ index: 1, uuid: 'D', frame: { x: 0, y: 0, w: 1200, h: 900 }, 'is-built-in': true }], spaces: [{ index: 1, uuid: 'S', display: 1, label: 'coding_solo', type: 'float' }], windows: [{ id: 10, pid: 100, app: 'Code', title: 'Editor', display: 1, space: 1, frame: { x: 0, y: 0, w: 600, h: 900 }, 'can-move': true, 'can-resize': true, 'is-visible': true }] });
const baseConfig = starterConfig();
const plan = (value, config = baseConfig) => {
  const snapshot = normalizeSnapshot(value, machine);
  const desired = buildDesiredState(config, compileV2(config), {kind:'workspace',id:'coding',mode:'solo'}, snapshot);
  return buildExecutionPlan(snapshot, desired, compareState(snapshot, desired, machine));
};
async function fixture(config = starterConfig()) {
  const directory = await mkdtemp(join(tmpdir(), 'spacewright-hardening-'));
  const configRoot = join(directory,'config'), stateRoot = join(directory,'state'), fakeBin = join(directory,'bin');
  await Promise.all([mkdir(configRoot), mkdir(stateRoot), mkdir(fakeBin)]);
  const dataFile = join(directory,'data.json'), logFile = join(directory,'commands.jsonl');
  await writeFile(dataFile, JSON.stringify(raw()));
  await writeFile(join(configRoot,'config.v2.json'), `${JSON.stringify(config,null,2)}\n`);
  await writeFile(join(stateRoot,'machine.json'), JSON.stringify(machine));
  const mock = `#!${process.execPath}
const fs = require('fs');
const data = JSON.parse(fs.readFileSync(process.env.MOCK_DATA,'utf8'));
const args = process.argv.slice(2); const kind=args[1]; const command=args[3];
if(args[0]==='--restart-service') {
 fs.appendFileSync(process.env.MOCK_LOG,JSON.stringify(args)+'\\n');
 data.restartCount=(data.restartCount || 0)+1;data.spaces.forEach(s=>s.label='');
 if(!data.axRecoveryIneffective)for(const w of data.windows)Object.assign(w,{'has-ax-reference':true,'can-move':true,'can-resize':true,role:'AXWindow',title:'Recovered'});
 fs.writeFileSync(process.env.MOCK_DATA,JSON.stringify(data));process.exit(0);
}
if(kind==='config') {
 const name=args[2]==='--space'?args[4]:args[2],key=args[2]==='--space'?args[3]+':'+name:name;
 data.settings ||= {};const value=data.settings[key] || (name==='external_bar'?'off:0:0':'4');
 const replacement=args[2]==='--space'?args[5]:args[3];
 if(replacement!=null){data.settings[key]=replacement;fs.writeFileSync(process.env.MOCK_DATA,JSON.stringify(data));}else console.log(value);
 process.exit(0);
}
if(kind==='query') {
 const key=args[2].slice(2); let result=data[key];
 if(key==='spaces' && args[3]==='--space') result=args[4] ? data.spaces.find(s=>s.index===Number(args[4])) : data.spaces.find(s=>s['has-focus']);
 if(key==='windows' && args[3]==='--window') result=data.windows.find(w=>w.id===Number(args[4]));
 if(!result) process.exit(3); console.log(JSON.stringify(result)); process.exit(0);
}
fs.appendFileSync(process.env.MOCK_LOG,JSON.stringify(args)+'\\n');
if(data.delay)Atomics.wait(new Int32Array(new SharedArrayBuffer(4)),0,0,data.delay);
if(data.fail || data.failId===Number(args[2])) process.exit(7);
if(kind==='window') {
 const w=data.windows.find(w=>w.id===Number(args[2])); if(!w)process.exit(3);
 if(!data.ineffective) {
 if(command==='--space') {w.space=Number(args[4]);w.display=data.spaces.find(s=>s.index===w.space).display;}
 if(command==='--grid') {const [rows,cols,x,y,width,height]=args[4].split(':').map(Number); const f=data.displays.find(d=>d.index===w.display).frame; w.frame={x:f.x+f.w*x/cols,y:f.y+f.h*y/rows,w:f.w*width/cols,h:f.h*height/rows};}
 if(command==='--move') {const p=args[4].split(':').slice(1).map(Number);w.frame.x=p[0];w.frame.y=p[1];}
 if(command==='--resize') {const p=args[4].split(':').slice(1).map(Number);w.frame.w=p[0];w.frame.h=p[1];}
 if(command==='--toggle' && args[4]==='native-fullscreen') w['is-native-fullscreen']=false;
 }
}
if(kind==='space' && command==='--label')data.spaces.find(s=>s.index===Number(args[2])).label=args[4];
if(kind==='space' && args[2]==='--create')data.spaces.push({index:Math.max(...data.spaces.map(s=>s.index))+1,uuid:'CREATED-'+data.spaces.length,display:Number(args[3]),label:'',type:'bsp'});
if(kind==='space' && command==='--layout')data.spaces.find(s=>s.index===Number(args[2])).type=args[4];
if(kind==='space' && args[2]==='--focus') {
 const index=data.spaces.find(s=>s.index===Number(args[3]) || s.label===args[3])?.index;data.spaces.forEach(s=>s['has-focus']=s.index===index);
 if(data.axObservation && !data.axRequiresService)for(const w of data.windows.filter(w=>w.space===index))Object.assign(w,{'has-ax-reference':true,'can-move':!data.axNeedsRefresh,'can-resize':true,role:'AXWindow',subrole:'AXStandardWindow',title:'Observed'});
}
if(kind==='space' && command==='--destroy') {
 const removed=data.spaces.find(s=>s.index===Number(args[2]));data.spaces=data.spaces.filter(s=>s!==removed);
 const indexes=new Map(data.spaces.map((s,i)=>[s.index,i+1]));data.windows.forEach(w=>w.space=indexes.get(w.space));data.spaces.forEach(s=>s.index=indexes.get(s.index));
}
if(kind==='space' && command==='--move') {
 const old=new Map(data.spaces.map(s=>[s.uuid,s.index])),space=data.spaces.find(s=>s.index===Number(args[2]));data.spaces=data.spaces.filter(s=>s!==space);data.spaces.splice(Number(args[4])-1,0,space);
 const indexes=new Map(data.spaces.map((s,i)=>[old.get(s.uuid),i+1]));data.windows.forEach(w=>w.space=indexes.get(w.space));data.spaces.forEach(s=>s.index=indexes.get(s.index));
}
fs.writeFileSync(process.env.MOCK_DATA,JSON.stringify(data));
`;
  await writeFile(join(fakeBin,'yabai'), mock, {mode:0o755});
  await writeFile(join(fakeBin,'open'), `#!${process.execPath}
const fs=require('fs'),d=JSON.parse(fs.readFileSync(process.env.MOCK_DATA,'utf8'));
fs.appendFileSync(process.env.MOCK_LOG,JSON.stringify(['open',...process.argv.slice(2)])+'\\n');
if(d.recoveryMode==='fail')process.exit(7);
if(d.recoveryMode==='timeout')process.exit(124);
if(d.recoveryMode!=='ineffective') { d.axNeedsRefresh=false;d.windows[0]['can-move']=true;if(d.recoveryMode==='replace')d.windows[0].id=20;if(d.recoveryMode==='reuse')d.windows[0].pid++; }
fs.writeFileSync(process.env.MOCK_DATA,JSON.stringify(d));
`,{mode:0o755});
  const env = {...process.env, HOME:directory,XDG_CONFIG_HOME:configRoot,XDG_CACHE_HOME:join(directory,'cache'),PATH:`${fakeBin}:${process.env.PATH}`,SPACEWRIGHT_CONFIG_ROOT:configRoot,SPACEWRIGHT_STATE_ROOT:stateRoot,MOCK_DATA:dataFile,MOCK_LOG:logFile};
  // The harness must outlive the backend deadline plus process-group cleanup;
  // otherwise durable multi-operation fixtures are killed as if they had hung.
  const cli = (args) => exec(join(root,'bin/spacewright'), args, {env, timeout:130000, maxBuffer:4000000});
  const setData = async (change) => {const data=JSON.parse(await readFile(dataFile,'utf8'));change(data);await writeFile(dataFile,JSON.stringify(data));};
  const commands = async () => (await readFile(logFile,'utf8').catch(()=>'' )).trim().split('\n').filter(Boolean).map(JSON.parse);
  return {directory,configRoot,stateRoot,dataFile,env,cli,setData,commands,close:()=>rm(directory,{recursive:true,force:true})};
}

for(const ineffective of [false,true])test(`persistent AX loss uses at most one service recovery (${ineffective?'ineffective':'recovered'})`,async()=>{
  const f=await fixture();
  try {
    await f.setData(data=>{
      data.axObservation=true;data.axRequiresService=true;data.axRecoveryIneffective=ineffective;
      data.spaces[0]['has-focus']=true;
      data.spaces.push({index:2,uuid:'AX-SPACE',display:1,label:'original',type:'float'});
      Object.assign(data.windows[0],{space:2,title:'',role:'','has-ax-reference':false,'can-move':false,'can-resize':false});
    });
    const preview=JSON.parse((await f.cli(['apply','coding','solo','--dry-run','--json'])).stdout);
    assert.equal(preview.plan.preparations[0].fallback.type,'restart_yabai');
    assert.equal((await f.commands()).length,0);
    let output;
    try {output=await f.cli(['apply','coding','solo','--json']);}
    catch(error){if(!ineffective)throw error;output=error;}
    const result=JSON.parse(output.stdout);
    assert.equal(result.status,ineffective?'failed':'completed');
    const commands=await f.commands();
    assert.equal(commands.filter(a=>a[0]==='--restart-service').length,1);
    const journal=JSON.parse(await readFile(result.journal,'utf8'));
    assert.equal(journal.serviceRecovery.status,'completed');
    assert.ok(journal.planRelations.some(r=>r.phase==='service_recovery'));
    const checkpoint=JSON.parse(await readFile(journal.serviceRecovery.checkpoint,'utf8'));
    assert.equal(checkpoint.status,'completed');
    const data=JSON.parse(await readFile(f.dataFile,'utf8'));
    assert.equal(data.spaces.find(s=>s.uuid==='AX-SPACE').label,'original');
    if(ineffective) {
      assert.match(result.error,/window references remain unavailable/);
      assert.ok(!commands.some(a=>a[1]==='window' || a.includes('--create')));
    }else assert.equal(journal.verification.converged,true);
  }finally{await f.close();}
});

test('unfinished service restoration blocks apply and a fresh repair before any desktop mutation',async()=>{
  const f=await fixture();
  try {
    await mkdir(join(f.stateRoot,'service-recovery'));
    await writeFile(join(f.stateRoot,'service-recovery','123456-1234abcd.json'),JSON.stringify({status:'restoring'}));
    for(const args of [['apply','coding','solo','--json'],['repair-yabai']]) {
      await assert.rejects(f.cli(args),error=>{
        assert.match(error.stderr,/repair-yabai --resume=123456-1234abcd/);return true;
      });
    }
    assert.deepEqual(await f.commands(),[]);
  }finally{await f.close();}
});
test('zero service recovery budget prevents the restart after failed AX observation',async()=>{
  const config=starterConfig();config.settings={executionBudgets:{serviceRecovery:0}};
  const f=await fixture(config);
  try {
    await f.setData(data=>{
      data.axRequiresService=true;data.spaces[0]['has-focus']=true;
      data.spaces.push({index:2,uuid:'AX-SPACE',display:1,label:'original',type:'float'});
      Object.assign(data.windows[0],{space:2,title:'',role:'','has-ax-reference':false,'can-move':false,'can-resize':false});
    });
    await assert.rejects(f.cli(['apply','coding','solo','--json']),error=>{
      assert.match(error.stderr,/serviceRecovery execution budget exhausted/);return true;
    });
    const commands=await f.commands();
    assert.ok(!commands.some(a=>a[0]==='--restart-service' || a[1]==='window'));
  }finally{await f.close();}
});

test('Space AX observation restores focus and replans optional windows before fixed layout',async()=>{
  const config=starterConfig();
  config.workspaces.coding.variants.solo.layout={type:'canvas',regions:[{role:'editor',grid:'1:2:0:0:1:1'},{role:'assistant',grid:'1:2:1:0:1:1'}]};
  const f=await fixture(config);
  try {
    await f.setData(data=>{
      data.axObservation=true;data.spaces[0]['has-focus']=true;
      data.spaces.push({index:2,uuid:'AX-SPACE',display:1,label:'',type:'float'});
      Object.assign(data.windows[0],{space:2,title:'',role:'','has-ax-reference':false,'can-move':false,'can-resize':false});
      data.windows.push({...data.windows[0],id:11,app:'ChatGPT'});
    });
    const {stdout}=await exec(join(root,'bin/spacewright'),['apply','coding','solo','--json'],{env:f.env,timeout:30000,maxBuffer:4000000});
    const result=JSON.parse(stdout);assert.equal(result.status,'completed');
    const journal=JSON.parse(await readFile(result.journal,'utf8'));
    assert.equal(journal.preparationPlan.preparations[0].type,'observe_space');
    assert.equal(journal.planRelations.length,1);
    assert.deepEqual(journal.plan.selectedWindows.map(w=>w.id),[10,11]);
    assert.equal(journal.after.spaces.find(s=>s.focused).uuid,'S');
    const commands=await f.commands();
    assert.deepEqual(commands.slice(0,2),[['-m','space','--focus','2'],['-m','space','--focus','1']]);
    assert.ok(commands.slice(2).some(a=>a[1]==='window' && a[2]==='11' && a[3]==='--grid'));
    assert.ok(!commands.some(a=>a[0]==='open' || a.includes('--restart-service')));
  }finally{await f.close();}
});
for(const recovery of ['refresh','fullscreen'])test(`AX observation can precede a separate ${recovery} preparation without layout in between`,async()=>{
  const config=starterConfig();config.workspaces.coding.variants.solo.runtime={runner:'primary_helper'};
  const f=await fixture(config);
  try {
    await f.setData(data=>{
      data.axObservation=true;data.axNeedsRefresh=recovery==='refresh';
      data.spaces[0]['has-focus']=true;
      data.spaces.push({index:2,uuid:'AX-SPACE',display:1,label:'',type:'float'});
      Object.assign(data.windows[0],{space:2,title:'',role:'','has-ax-reference':false,'can-move':false,'is-native-fullscreen':recovery==='fullscreen'});
    });
    const {stdout}=await exec(join(root,'bin/spacewright'),['apply','coding','solo','--json'],{env:f.env,timeout:30000,maxBuffer:4000000});
    const result=JSON.parse(stdout);assert.equal(result.status,'completed');
    const journal=JSON.parse(await readFile(result.journal,'utf8'));
    assert.equal(journal.planRelations.length,2);
    assert.deepEqual(journal.preparationPlans.map(p=>p.preparations[0].type),['observe_space',recovery==='refresh'?'refresh_app':'native_fullscreen']);
    assert.equal(journal.operations.filter(o=>o.type==='adapter_preparation').length,2);
    const commands=await f.commands(),recoveryIndex=commands.findIndex(a=>a[0]==='open' || a[3]==='--toggle');
    assert.ok(recoveryIndex>=2);assert.ok(!commands.slice(0,recoveryIndex).some(a=>a[1]==='window' && a[3]!=='--toggle'));
  }finally{await f.close();}
});

test('per-Space partial discovery fails closed and prevents empty Space destruction', () => {
  const output=fish(`
    source lib/spacewright/common/ws_core.fish
    source lib/spacewright/common/workspace_finalize.fish
    set -gx WORKSPACE_DISABLE_YABAI_AUTO_RESTART 1
    function ws_query_spaces; echo '[{"index":1,"uuid":"S1","display":1,"label":""},{"index":2,"uuid":"S2","display":1,"label":"sandbox_solo"}]'; end
    function spacewright_config_effective; echo '{}'; end
    function ws_yabai
      if test "$argv[2]" = space; echo MUTATED; return 0; end
      if test "$argv[5]" = 1; echo '[]'; return 0; end
      return 1
    end
    set -l windows (ws_query_windows workspace_plan all)
    echo discovery_status=$status
    echo windows_count=(count $windows)
    workspace_cleanup_empty_spaces --policy managed
    echo cleanup_status=$status
  `);
  assert.match(output,/discovery_status=1/);assert.match(output,/windows_count=0/);assert.match(output,/cleanup_status=1/);assert.doesNotMatch(output,/MUTATED/);
});

test('window operation reports command failure, timeout and identity-bound cache hit', () => {
  const output=fish(`
    source lib/spacewright/common/ws_core.fish
    source lib/spacewright/common/ws_window.fish
    set -gx SPACEWRIGHT_STATE_ROOT (mktemp -d)
    set -gx SPACEWRIGHT_RUNTIME_GENERATION G
    set -g fail 7
    function ws_yabai
      if test "$argv[2]" = query; echo '{"id":10,"pid":100,"app":"Code","space":1}'; return 0; end
      return $fail
    end
    ws_window 10 --grid 1:1:0:0:1:1; echo failed=$status
    set fail 142
    ws_window 10 --grid 1:1:0:0:1:1; echo timeout=$status
    set fail 0
    ws_window 10 --grid 1:1:0:0:1:1; echo cached=$status
    set -gx SPACEWRIGHT_RUNTIME_GENERATION G2
    ws_window 10 --grid 1:1:0:0:1:1; echo new_generation=$status
    functions -e ws_yabai
    function ws_yabai; return 142; end
    ws_window 10 --space 2; echo query_timeout=$status
    rm -rf "$SPACEWRIGHT_STATE_ROOT"
  `);
  assert.match(output,/failed=4/);assert.match(output,/timeout=124/);assert.match(output,/cached=124/);assert.match(output,/new_generation=0/);assert.match(output,/query_timeout=124/);
});

test('selection rejects minimized, native fullscreen, mismatched bundle and required ambiguity', () => {
  const windows=normalizeSnapshot({windows:[...raw().windows,{...raw().windows[0],id:11,'is-minimized':true},{...raw().windows[0],id:12,'is-native-fullscreen':true},{...raw().windows[0],id:13,'bundle-id':'wrong'}]}).windows;
  const role={appNames:['Code'],bundleIds:['correct'],cardinality:'many'};
  assert.deepEqual(selectRole(windows,role).selected.map(w=>w.id),[10]);
  assert.equal(selectRole([...windows.slice(0,1),{...windows[0],id:99}],{...role,cardinality:'one'}).ambiguous,true);
});

test('target preconditions ignore unrelated title/frame but invalidate selected identity, Space and config', () => {
  const original=raw();original.windows.push({...structuredClone(original.windows[0]),id:99,app:'Unrelated'});
  const before=plan(original);const unrelated=structuredClone(original);unrelated.windows[1].title='Changed';unrelated.windows[1].frame.x=300;
  assert.equal(plan(unrelated).planId,before.planId);assert.notEqual(normalizeSnapshot(original).snapshotId,normalizeSnapshot(unrelated).snapshotId);
  for (const change of [(v)=>v.windows[0].pid++, (v)=>v.spaces[0].uuid='NEW', (v)=>v.displays[0].frame.w=1600]) {
    const v=structuredClone(original);change(v);assert.notEqual(plan(v).planId,before.planId);
  }
  const config=starterConfig();config.metadata.name='changed';assert.notEqual(plan(original,config).planId,before.planId);
  const partial=plan({...original,completeness:'partial',missingQueries:['windows:space:2']});assert.equal(partial.executable,false);
  assert.equal(before.scope,'workspace');assert.ok(!before.runnerCommands.some(c=>['finalize','order','postprocess'].includes(c[0])));
});

test('configuration guard rejects interrupted saves and serializes independent writers', async () => {
  const dir=await mkdtemp(join(tmpdir(),'spacewright-config-guard-'));const path=join(dir,'config.v2.json');await writeFile(path,JSON.stringify(starterConfig()));
  try {
    await assert.rejects(withConfigurationWrite(dir,async()=>{await assert.rejects(withConfigurationWrite(dir,async()=>{}),/active or incomplete/);throw new Error('interrupted');}),/interrupted/);
    await assert.rejects(stableRead(path),/incomplete or in progress/);
    const config=starterConfig();const a=generationDocument(config,null);config.metadata.name='new';const b=generationDocument(config,null);assert.notEqual(a.generated.generation_id,b.generated.generation_id);
  } finally {await rm(dir,{recursive:true,force:true});}
});

test('unknown live lock owners are never reclaimed and copied tokens cannot bypass ancestry', async () => {
  const dir=await mkdtemp(join(tmpdir(),'spacewright-lease-'));
  try {
    const lease=await acquireExecution(dir,{controller:'test'}, {inherit:false});
    assert.equal(await verifyLease(dir,lease.env),true);
    assert.equal(await verifyLease(dir,lease.env,process.ppid),false);
    await assert.rejects(acquireExecution(dir,{}, {inherit:false}),/unrecognized live owner/);
    assert.equal(await verifyLease(dir,{SPACEWRIGHT_EXECUTION_TOKEN:'fake',SPACEWRIGHT_EXECUTION_RUN_ID:lease.owner.runId}),false);
    const unknown=join(dir,'execution.lock','owner.json');await writeFile(unknown,JSON.stringify({pid:process.pid,runId:'unknown'}));
    await assert.rejects(acquireExecution(dir,{}, {inherit:false}),/unrecognized live owner/);
  } finally {await rm(dir,{recursive:true,force:true});}
});

test('cancel escalates an unresponsive process group within a bounded grace period', async () => {
  const abort=new AbortController();const started=Date.now();
  const pending=runBounded(process.execPath,['-e',"process.on('SIGTERM',()=>{}); setInterval(()=>{},100)"],{signal:abort.signal,deadline:Date.now()+5000});
  setTimeout(()=>abort.abort(Object.assign(new Error('cancelled'),{code:'SPACEWRIGHT_CANCELLED'})),150);
  await assert.rejects(pending,/cancelled/);assert.ok(Date.now()-started<3500);
});

test('web tasks reject unverified zero exits and finish despite activity-log failures', async () => {
  const task={id:'x',status:'queued',logs:[]};
  await runWebTask(task,[[]],{executable:'/usr/bin/true',env:process.env,append:(t,l)=>t.logs.push(l),activity:async()=>{throw new Error('log unavailable');}});
  assert.equal(task.status,'failed');assert.ok(task.finishedAt);assert.match(task.loggingError,/log unavailable/);
  const cancelled={id:'y',status:'queued',logs:[]};cancelWebTask(cancelled);await runWebTask(cancelled,[[]],{executable:'/usr/bin/true',env:process.env,append:()=>{},activity:async()=>{}});assert.equal(cancelled.status,'cancelled');assert.ok(cancelled.finishedAt);
});

test('real Fish backend consumes pinned identities, dry-run is inert and a second apply is a noop', async () => {
  const f=await fixture();try {
    const preview=JSON.parse((await f.cli(['apply','coding','solo','--dry-run','--json'])).stdout);assert.equal(preview.mutates,false);assert.deepEqual(await f.commands(),[]);
    const applied=JSON.parse((await f.cli(['apply','coding','solo','--json'])).stdout);assert.equal(applied.status,'completed');assert.equal(applied.verification.converged,true);
    const journal=JSON.parse(await readFile(applied.journal,'utf8'));assert.deepEqual(journal.plan.selectedWindows.map(w=>w.id),[10]);assert.ok(journal.effects.some(e=>e.windowId===10));
    const count=(await f.commands()).length;assert.ok(count>0);
    const again=JSON.parse((await f.cli(['run','coding','solo','--json'])).stdout);assert.equal(again.noop,true);assert.equal((await f.commands()).length,count);
    const recovered=JSON.parse((await f.cli(['recover',applied.runId,'--json'])).stdout);assert.equal(recovered.status,'completed');assert.deepEqual(recovered.restored,[10]);
  } finally {await f.close();}
});

test('many-role execution operates every planned object and validates each grid', async () => {
  const config=starterConfig();config.workspaces.coding.windows.editor.cardinality='many';const f=await fixture(config);
  try {
    await f.setData(d=>d.windows.push({...d.windows[0],id:11,pid:101}));
    const applied=JSON.parse((await f.cli(['apply','coding','solo','--json'])).stdout);assert.equal(applied.status,'completed');
    assert.deepEqual(applied.plan.selectedWindows.map(w=>w.id),[10,11]);assert.deepEqual((await f.commands()).filter(a=>a[3]==='--grid').map(a=>Number(a[2])),[10,11]);
  } finally {await f.close();}
});

for (const scenario of ['fail','ineffective']) test(`apply journals ${scenario} as failure instead of declaring completion`,async()=>{
  const f=await fixture();try {await f.setData(d=>d[scenario]=true);await assert.rejects(f.cli(['apply','coding','solo','--json']),error=>{const result=JSON.parse(error.stdout);assert.equal(result.status,'failed');return true;});const files=(await readdir(join(f.stateRoot,'runs'))).filter(n=>/^\d+-[a-f0-9]{8}\.json$/.test(n));assert.equal(JSON.parse(await readFile(join(f.stateRoot,'runs',files[0]),'utf8')).status,'failed');}finally{await f.close();}
});

for (const scenario of ['identity','missing-window','missing-space','reordered-space','ineffective']) test(`recovery verifies ${scenario}`,async()=>{
  const f=await fixture();try {
    const applied=JSON.parse((await f.cli(['apply','coding','solo','--json'])).stdout);
    await f.setData(d=>{if(scenario==='identity')d.windows[0].pid++;if(scenario==='missing-window')d.windows=[];if(scenario==='missing-space')d.spaces=[];if(scenario==='reordered-space'){d.spaces[0].index=3;d.windows[0].space=3;}if(scenario==='ineffective')d.ineffective=true;});
    let result;try{result=JSON.parse((await f.cli(['recover',applied.runId,'--json'])).stdout);}catch(error){result=JSON.parse(error.stdout);}
    assert.equal(result.status,scenario==='reordered-space'?'completed':scenario==='ineffective'?'failed':'skipped');
    if(scenario==='reordered-space')assert.ok((await f.commands()).some(a=>a[3]==='--space'&&a[4]==='3'));
  }finally{await f.close();}
});

test('v3 generation includes topology, bindings, hardware, and rejects unavailable context', async () => {
  const {starterV3}=await import('../lib/config-v3.mjs');
  const config=starterV3();
  const context={machine:{version:2,hardwareProfile:'mac_mini',hardwareProfileConfirmed:true,displayBindings:{tall:'T'},topologySelections:{'external:tall':'single_tall'}},hardware:{family:'mac_mini',modelIdentifier:'Macmini9,1'},snapshot:{unavailable:false,displays:[{index:1,uuid:'T',frame:{x:0,y:0,w:1200,h:1920},builtIn:false}]}};
  const first=generationDocument(config,context);
  const moved=structuredClone(context);moved.snapshot.displays[0].frame.x=1200;assert.notEqual(generationDocument(config,moved).generated.generation_id,first.generated.generation_id);
  const bound=structuredClone(context);bound.machine.displayBindings.tall='NEW';assert.throws(()=>generationDocument(config,bound),/binding/);
  const hardware=structuredClone(context);hardware.hardware.modelIdentifier='Macmini10,1';assert.notEqual(generationDocument(config,hardware).generated.generation_id,first.generated.generation_id);
  const unavailable=structuredClone(context);unavailable.snapshot.unavailable=true;assert.throws(()=>generationDocument(config,unavailable),/unavailable/);
});

test('concurrent apply and direct run share one mutation owner', async () => {
  const f=await fixture();try{
    await f.setData(d=>d.delay=900);
    const first=f.cli(['apply','coding','solo','--json']);
    const deadline=Date.now()+5000;
    while(!(await f.commands()).length && Date.now()<deadline)await new Promise(r=>setTimeout(r,25));
    assert.ok((await f.commands()).length);
    await assert.rejects(f.cli(['run','coding','solo','--json']),/live owner|another mutation|active/);
    assert.equal(JSON.parse((await first).stdout).status,'completed');
    assert.equal((await f.commands()).filter(a=>a[1]==='window').length,1);
  }finally{await f.close();}
});

test('total deadline stops discovery without a mutation', async () => {
  const f=await fixture();try{
    await assert.rejects(f.cli(['apply','coding','solo','--timeout-seconds=0.001','--json']),error=>{assert.equal(error.code,124);assert.equal(JSON.parse(error.stdout).status,'timed_out');return true;});
    assert.deepEqual(await f.commands(),[]);
  }finally{await f.close();}
});

test('Office multi-document placement shares the planner and verifier geometry', async()=>{
  const config=starterConfig();
  config.workspaces.coding.windows={primary:{app:'code',required:true,cardinality:'many'}};
  config.workspaces.coding.variants={wide:{layout:{type:'window',role:'primary'},runtime:{runner:'office_document'}}};
  for(const mode of ['solo','tall'])for(const display of config.modes[mode].displays)display.workspaceOrder=[];
  config.modes.wide.displays=[{role:'primary',workspaceOrder:['coding']}];config.shortcuts=[];
  const f=await fixture(config);try{
    await f.setData(d=>{d.spaces[0].label='coding_wide';d.windows.push({...structuredClone(d.windows[0]),id:11,pid:101});});
    const applied=JSON.parse((await f.cli(['apply','coding','wide','--json'])).stdout);
    assert.equal(applied.status,'completed');assert.deepEqual(applied.plan.selectedWindows.map(w=>w.id),[10,11]);
    assert.deepEqual((await f.commands()).filter(a=>a[3]==='--grid').map(a=>a[4]),['1:2:1:0:1:1']);
  }finally{await f.close();}
});

test('direct public display/finalize/postprocessor dry-runs never call the backend',()=>{
 const output=fish(`source conf.d/spacewright.fish
 function ws_yabai; echo MUTATED; return 99; end
 display_apply_solo --dry-run
 workspace_finalize_mode solo --dry-run
 workspace_reconcile_primary_fixed_spaces --dry-run
 gtd_ai_expand_hermes_when_alone --dry-run`);
 assert.doesNotMatch(output,/MUTATED/);assert.equal(output.split('\n').filter(l=>l.startsWith('dry_run=')).length,4);
});

test('recovery reports partial failure and records nonrecoverable effects',async()=>{
 const f=await fixture();try{
  const config=JSON.parse(await readFile(join(f.configRoot,'config.v2.json'),'utf8'));config.workspaces.coding.windows.editor.cardinality='many';await writeFile(join(f.configRoot,'config.v2.json'),`${JSON.stringify(config,null,2)}\n`);
  await f.setData(d=>d.windows.push({...structuredClone(d.windows[0]),id:11,pid:101}));
  const applied=JSON.parse((await f.cli(['apply','coding','solo','--json'])).stdout);
  const journal=JSON.parse(await readFile(applied.journal,'utf8'));journal.effects.push({type:'space_destroy',reversible:false});await writeFile(applied.journal,JSON.stringify(journal));
  await f.setData(d=>d.failId=11);
  await assert.rejects(f.cli(['recover',applied.runId,'--json']),e=>{const r=JSON.parse(e.stdout);assert.equal(r.status,'partial');assert.deepEqual(r.restored,[10]);assert.equal(r.failed[0].windowId,11);assert.equal(r.nonrecoverable[0].type,'space_destroy');return true;});
 }finally{await f.close();}
});

for(const scenario of ['replace','reuse','fail','ineffective','timeout'])test(`explicit app preparation records ${scenario} and replans before layout`,async()=>{
 const config=starterConfig();config.workspaces.coding.variants.solo.runtime={runner:'office_document'};
 const f=await fixture(config);try{
  await f.setData(d=>{d.windows[0]['can-move']=false;d.recoveryMode=scenario;});
  const preview=JSON.parse((await f.cli(['apply','coding','solo','--dry-run','--json'])).stdout);
  assert.equal(preview.plan.preparations[0].type,'refresh_app');assert.deepEqual(await f.commands(),[]);
  let applied;try{applied=JSON.parse((await f.cli(['apply','coding','solo','--json'])).stdout);}catch(e){applied=JSON.parse(e.stdout);}
  const journal=JSON.parse(await readFile(applied.journal,'utf8'));
  if(['replace','reuse'].includes(scenario)) {
   assert.equal(applied.status,'completed');assert.equal(journal.planRelations.length,1);
   const expected=scenario==='replace'?20:10;assert.deepEqual(journal.plan.selectedWindows.map(w=>w.id),[expected]);
   const operation=journal.operations.find(r=>r.type==='adapter_preparation');assert.equal(operation.status,'verified_success');
   assert.equal(operation.postcondition.after[0].id,expected);
   if(scenario==='reuse')assert.equal(operation.postcondition.after[0].pid,101);
   const count=(await f.commands()).length;const again=JSON.parse((await f.cli(['apply','coding','solo','--json'])).stdout);assert.equal(again.noop,true);assert.equal((await f.commands()).length,count);
  } else {
   if(scenario==='ineffective')assert.ok(['failed','timed_out'].includes(applied.status));
   else assert.equal(applied.status,scenario==='timeout'?'timed_out':'failed');
   assert.ok(!(await f.commands()).some(a=>a[1]==='window'));
  }
 }finally{await f.close();}
});
test('native fullscreen preparation is acknowledged before an immutable replacement plan',async()=>{
 const f=await fixture();try{
  await f.setData(d=>d.windows[0]['is-native-fullscreen']=true);
  const applied=JSON.parse((await f.cli(['apply','coding','solo','--json'])).stdout);assert.equal(applied.status,'completed');
  const journal=JSON.parse(await readFile(applied.journal,'utf8'));assert.equal(journal.preparationPlan.preparations[0].type,'native_fullscreen');assert.equal(journal.planRelations.length,1);
  assert.equal(journal.operations.filter(r=>r.type==='adapter_preparation')[0].status,'verified_success');
 }finally{await f.close();}
});

test('mode execution creates a recorded Sandbox UUID and converges without collecting new objects',async()=>{
 const f=await fixture();try{
  await f.setData(d=>{d.spaces.push({index:2,uuid:'OPPOSITE',display:1,label:'coding_wide',type:'float'},{index:3,uuid:'USER',display:1,label:'personal',type:'float'});d.windows.push({...d.windows[0],id:99,pid:101,app:'Other',space:3});});
  const preview=JSON.parse((await f.cli(['apply','solo','--dry-run','--json'])).stdout);assert.deepEqual(preview.plan.selectedWindows.map(w=>w.id),[10,99]);assert.deepEqual(await f.commands(),[]);
  const applied=JSON.parse((await f.cli(['apply','solo','--json'])).stdout);assert.equal(applied.status,'completed');
  const journal=JSON.parse(await readFile(applied.journal,'utf8'));const created=journal.operations.find(r=>r.type==='ensure_space');assert.match(created.postcondition.createdSpaceUuid,/CREATED/);
  const data=JSON.parse(await readFile(f.dataFile,'utf8'));assert.ok(data.spaces.some(s=>s.uuid==='USER'));assert.ok(!data.spaces.some(s=>s.uuid==='OPPOSITE'));assert.equal(data.spaces.find(s=>s.index===data.windows.find(w=>w.id===99).space).label,'sandbox_solo');
  const count=(await f.commands()).length;const again=JSON.parse((await f.cli(['apply','solo','--json'])).stdout);assert.equal(again.noop,true);assert.equal((await f.commands()).length,count);
 }finally{await f.close();}
});
test('workspace execution cleans only its empty opposite UUID and has no global finalization effects',async()=>{
 const f=await fixture();try{
  await f.setData(d=>d.spaces.push({index:2,uuid:'OPPOSITE',display:1,label:'coding_wide',type:'float'},{index:3,uuid:'OTHER',display:1,label:'gtd_other',type:'float'},{index:4,uuid:'USER',display:1,label:'personal',type:'float'}));
  const applied=JSON.parse((await f.cli(['apply','coding','solo','--json'])).stdout);assert.equal(applied.status,'completed');
  const commands=await f.commands();assert.equal(commands.filter(a=>a[3]==='--destroy').length,1);assert.ok(!commands.some(a=>a[3]==='--move' || a[2]==='--create'));
  const data=JSON.parse(await readFile(f.dataFile,'utf8'));assert.deepEqual(data.spaces.map(s=>s.uuid),['S','OTHER','USER']);
  const count=commands.length;const again=JSON.parse((await f.cli(['apply','coding','solo','--json'])).stdout);assert.equal(again.noop,true);assert.equal((await f.commands()).length,count);
 }finally{await f.close();}
});
test('completed label history keeps fixed candidate preference during unlabeled-Space execution',async()=>{
 const f=await fixture();try{
  await f.setData(d=>{d.spaces[0].label='';d.spaces.push({index:2,uuid:'OTHER',display:1,label:'',type:'float'});d.windows.push({...d.windows[0],id:20,pid:101,space:2});});
  await mkdir(join(f.stateRoot,'runs'),{recursive:true});
  await writeFile(join(f.stateRoot,'runs','100-aaaaaaaa.json'),JSON.stringify({status:'completed',after:{spaces:[{index:1,uuid:'S',label:'coding_solo'},{index:2,uuid:'OTHER',label:''}]}}));
  const applied=JSON.parse((await f.cli(['apply','coding','solo','--json'])).stdout);
  assert.equal(applied.status,'completed');assert.deepEqual(applied.plan.selectedWindows.map(w=>w.id),[10]);
  assert.ok(!(await f.commands()).some(a=>a[1]==='window' && a[2]==='20'));
  const again=JSON.parse((await f.cli(['apply','coding','solo','--json'])).stdout);
  assert.equal(again.noop,true);const noopFiles=(await readdir(join(f.stateRoot,'runs'))).filter(n=>n.endsWith('.json')).sort();
  const journal=JSON.parse(await readFile(join(f.stateRoot,'runs',noopFiles.at(-1)),'utf8'));
  assert.equal(journal.after.spaces.find(s=>s.uuid==='S').label,'coding_solo');
 }finally{await f.close();}
});


test('reconciliation validates late empty-Space cleanup against its own plan',async()=>{
  const config=starterConfig();
  config.workspaces.coding.variants.solo.activation={type:'windowPresent',role:'editor'};
  config.workspaces.chat={name:'Chat',spaceLabel:'chat',windows:{primary:{app:'chatgpt',required:true,selector:{movable:true}}},variants:{solo:{layout:{type:'window',role:'primary'}}}};
  config.modes.solo.displays[0].workspaceOrder.push('chat');
  const f=await fixture(config);
  try {
    await f.setData(data=>{
      data.windows[0].app='ChatGPT';
      data.spaces.push({index:2,uuid:'CHAT',display:1,label:'chat_solo',type:'float'});
    });
    const output=await f.cli(['apply','solo','--json']);
    const result=JSON.parse(output.stdout);
    assert.equal(result.status,'completed');
    const journal=JSON.parse(await readFile(result.journal,'utf8'));
    const reconciliation=journal.steps.find(step=>step.type==='reconciliation');
    assert.equal(reconciliation.status,'completed');
    assert.ok(reconciliation.finishedAt);
    assert.ok(journal.planRelations.some(relation=>relation.phase==='reconciliation' && relation.toPlanId===journal.reconciliationPlan.planId));
    assert.ok(journal.effects.some(effect=>effect.type==='remove_empty_space' && effect.spaceUuid==='S' && effect.status==='verified_success'));
    assert.equal(journal.verification.converged,true);
  } finally {await f.close();}
});
