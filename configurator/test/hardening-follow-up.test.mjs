import test from 'node:test';
import assert from 'node:assert/strict';
import { starterConfig, compileV2 } from '../lib/config-v2.mjs';
import { normalizeSnapshot, buildDesiredState, compareState, buildExecutionPlan,geometryMatches } from '../lib/state-engine.mjs';
import { gridFrame } from '../lib/grid-geometry.mjs';
import { discoverGridGeometry,applyNativeWindowFrames } from '../lib/discovery.mjs';
import { executePinnedWorkspace,executePinnedCleanup,executePinnedOrder } from '../lib/pinned-executor.mjs';
import { journalMutation,operationRecords } from '../lib/operation-journal.mjs';
import { acquireExecution } from '../lib/execution-coordinator.mjs';
import { consumeBudget } from '../lib/execution-budget.mjs';
import { mkdtemp,rm,writeFile,readFile,mkdir } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { execFile,execFileSync } from 'node:child_process';
import { promisify } from 'node:util';
import { createAutomationMonitor } from '../lib/automation-monitor.mjs';
import { executePreparation } from '../lib/adapter-preparation.mjs';
import { withConfigurationWrite,stableRead,atomicText,generationDocument } from '../lib/config-store.mjs';
import { spawn } from 'node:child_process';
const machine = {displayBindings:{primary:'D'}};
const raw = () => ({displays:[{index:1,uuid:'D',frame:{x:0,y:0,w:1000,h:800}}], spaces:[{index:1,uuid:'S',display:1,label:'coding_solo'},{index:2,uuid:'O',display:1,label:'custom_wide'},{index:3,uuid:'USER',display:1,label:'personal'}],windows:[{id:10,pid:100,app:'Code',display:1,space:1,frame:{x:0,y:0,w:1000,h:800},'can-move':true,'can-resize':true}]});
test('display profiles receive the confirmed machine UUID instead of an inherited legacy UUID',async()=>{
  const directory=await mkdtemp(join(tmpdir(),'spacewright-primary-contract-'));
  try {
    await writeFile(join(directory,'machine.json'),JSON.stringify({displayBindings:{primary:'CURRENT'}}));
    const output=execFileSync('fish',['--no-config','-c',`
      source conf.d/spacewright.fish
      set -gx SPACEWRIGHT_STATE_ROOT "$TEST_MACHINE_ROOT"
      set -gx WORKSPACE_PRIMARY_DISPLAY_UUID STALE
      function workspace_execution_owned; return 0; end
      function fixture_profile; echo received=$WORKSPACE_PRIMARY_DISPLAY_UUID; end
      function display_reload; return 0; end
      function work_reload; return 0; end
      function display_verify_mode; return 0; end
      display_apply_profile_mode fixture_profile tall
      echo inherited=$WORKSPACE_PRIMARY_DISPLAY_UUID
    `],{encoding:'utf8',env:{...process.env,TEST_MACHINE_ROOT:directory}});
    assert.match(output,/received=CURRENT/);assert.match(output,/inherited=STALE/);
  }finally{await rm(directory,{recursive:true,force:true});}
});
function make(value=raw(), config=starterConfig(), target={kind:'workspace',id:'coding',mode:'solo'}) {
  config.workspaces.coding.variants.wide.spaceLabel='custom_wide';
  const snapshot=normalizeSnapshot(value,machine), desired=buildDesiredState(config,compileV2(config),target,snapshot);
  const comparison=compareState(snapshot,desired,machine);
  return {snapshot,desired,comparison,plan:buildExecutionPlan(snapshot,desired,comparison)};
}
test('49/51 tall planning rejects equal heights and converges only after both fixed grids are applied',async()=>{
  const config=starterConfig();config.settings={tallTopPercent:49};
  for(const display of config.modes.tall.displays)display.role='primary';
  config.workspaces.coding.variants.tall.layout={type:'canvas',regions:[{role:'editor',grid:'2:1:0:0:1:1'},{role:'assistant',grid:'2:1:0:1:1:1'}]};
  const value=raw();value.spaces[0].label='coding_tall';value.spaces[0].type='float';value.spaces.splice(1,1);
  value.windows[0].frame.h=400;
  value.windows.push({...value.windows[0],id:11,app:'ChatGPT',frame:{x:0,y:400,w:1000,h:400}});
  const target={kind:'workspace',id:'coding',mode:'tall'};
  const {plan,comparison}=make(value,config,target);
  assert.equal(comparison.converged,false);
  assert.deepEqual(plan.actions.filter(a=>a.type==='resize_window').map(a=>a.grid),['100:1:0:0:1:49','100:1:0:49:1:51']);
  await executePinnedWorkspace(plan,'coding',{discover:async()=>normalizeSnapshot(value,machine),mutate:async(args,intent,verify)=>{
    assert.equal(args[3],'--grid');value.windows.find(w=>w.id===Number(args[2])).frame=gridFrame(value.displays[0],args[4]);assert.equal(verify(normalizeSnapshot(value,machine)),true);
  }});
  const applied=make(value,config,target);assert.equal(applied.comparison.converged,true);assert.equal(applied.plan.actions.length,0);
  assert.deepEqual(value.windows.map(w=>w.frame.h),[392,408]);
});
test('precise grid geometry includes menu/Dock work area, padding, gaps and negative origins',()=>{
  const display={frame:{x:-1620,y:0,w:1620,h:2025},gridGeometry:{frame:{x:-1620,y:31,w:1620,h:1994},padding:{top:4,bottom:4,left:4,right:4},gap:4}};
  const top=gridFrame(display,'100:3:0:0:2:49'),bottom=gridFrame(display,'100:3:0:49:2:51');
  assert.equal(top.y,35);assert.equal(top.h,971.18);assert.equal(bottom.h,1010.82);
  assert.equal(geometryMatches({frame:top},display,{grid:'100:3:0:0:2:49'}).matches,true);
  assert.equal(geometryMatches({frame:{...top,h:991}},display,{grid:'100:3:0:0:2:49'}).matches,false);
  assert.equal(geometryMatches({frame:{...bottom,h:991}},display,{grid:'100:3:0:49:2:51'}).matches,false);
  assert.equal(geometryMatches({frame:{...top,h:Math.round(top.h)}},display,{grid:'100:3:0:0:2:49'}).matches,true);
});
test('tall percentages remain consumer configuration rather than hardcoded 49/51',()=>{
  for(const percent of [40,49,60]) {
    const config=starterConfig();config.settings={tallTopPercent:percent};
    config.workspaces.coding.variants.tall.layout={type:'canvas',regions:[{role:'editor',grid:'2:1:0:0:1:1'},{role:'assistant',grid:'2:1:0:1:1:1'}]};
    const desired=buildDesiredState(config,compileV2(config),{kind:'workspace',id:'coding',mode:'tall'});
    assert.deepEqual(desired.workspaces[0].layout.map(l=>l.grid),[`100:1:0:0:1:${percent}`,`100:1:0:${percent}:1:${100-percent}`]);
  }
});
test('overflowing adapter grids compare the same edge-clamped frame that yabai applies',()=>{
  const display={frame:{x:0,y:0,w:1620,h:2025},gridGeometry:{frame:{x:0,y:31,w:1620,h:1994},padding:{top:4,bottom:4,left:4,right:4},gap:4}};
  assert.deepEqual(gridFrame(display,'20:10:0:15:6:6'),gridFrame(display,'20:10:0:15:6:5'));
  const expected=gridFrame(display,'20:10:0:15:6:6');
  assert.ok(expected);assert.equal(geometryMatches({frame:expected},display,{grid:'20:10:0:15:6:6'}).matches,true);
  assert.deepEqual(gridFrame(display,'2:2:5:5:0:0'),gridFrame(display,'2:2:1:1:1:1'));
  assert.equal(gridFrame(display,'0:2:0:0:1:1'),null);
  assert.equal(gridFrame(display,'2:2:-1:0:1:1'),null);
});
test('native bounds replace stale yabai frames only for an exact unique ID and owner PID',()=>{
  const stale={id:10,pid:100,frame:{x:154,y:31,w:1612,h:971},'can-move':true};
  const native={id:10,pid:100,frame:{x:4,y:35,w:1612,h:971}};
  const good=applyNativeWindowFrames([stale],[native]);
  assert.deepEqual(good.windows[0].frame,native.frame);assert.deepEqual(good.missing,[]);
  for(const frames of [[],[{...native,pid:101}],[native,native],[{...native,frame:{...native.frame,h:NaN}}]]) {
    const result=applyNativeWindowFrames([stale],frames);assert.deepEqual(result.missing,['window_geometry:10']);assert.deepEqual(result.windows[0].frame,stale.frame);
  }
  const unmapped=applyNativeWindowFrames([{...stale,'can-move':false}],[]);
  assert.deepEqual(unmapped.missing,[]);assert.equal(unmapped.windows[0].frameVerified,false);
  assert.equal(geometryMatches(unmapped.windows[0],{frame:{x:0,y:0,w:1620,h:2025}},{grid:'1:1:0:0:1:1'}).comparable,false);
  assert.deepEqual(applyNativeWindowFrames([stale],null).windows,[stale]);
});
test('native grid discovery resolves the exact UUID and active Space and rejects failed padding queries',async()=>{
  const displays=[{id:1,index:1,uuid:'D',frame:{x:0,y:0,w:1620,h:2025}}],spaces=[{index:4,display:1,'is-visible':true}];
  const calls=[];
  const run=async(exe,args)=>{calls.push([exe,args]);return {code:0,stdout:args[0]==='-m'?(args.at(-1)==='external_bar'?'off:0:0':'4'):JSON.stringify({displays:[{uuid:'D',frame:{x:0,y:31,w:1620,h:1994}}],windows:[]})};};
  const result=await discoverGridGeometry(displays,spaces,{executable:'fixture-yabai',deadline:Date.now()+5000,run});
  assert.equal(gridFrame(result[0],'100:3:0:0:2:49').h,971.18);
  assert.equal(calls.filter(([,a])=>a.includes('--space')).length,5);
  assert.ok(calls.filter(([,a])=>a.includes('--space')).every(([,a])=>a[3]==='4'));
  await assert.rejects(discoverGridGeometry(displays,spaces,{executable:'fixture-yabai',deadline:Date.now()+5000,run:async(exe,args)=>args.at(-1)==='window_gap'?{code:1,stderr:'query unavailable'}:run(exe,args)}),/grid configuration query failed/);
  await assert.rejects(discoverGridGeometry(displays,spaces,{deadline:Date.now()+5000,run:async()=>({code:0,stdout:'[]'})}),/native display geometry is invalid/);
});
test('workspace cleanup names only its configured opposite UUID, including shared runtime ids',()=>{
  const config=starterConfig();config.workspaces.coding.variants.solo.command='shared';config.workspaces.coding.variants.wide.command='shared';
  const {plan}=make(raw(),config);
  assert.deepEqual(plan.actions.filter(a=>a.type==='remove_empty_space').map(a=>a.spaceUuid),['O']);
  assert.ok(plan.executionSteps.some(s=>s.action==='cleanup_workspace'));
  assert.ok(!plan.runnerCommands.some(c=>['finalize','postprocess','order'].includes(c[0])));
});
test('shared runtime ids cannot replace a variant-specific role contract with another mode',()=>{
  const config=starterConfig();
  for(const mode of ['solo','wide'])config.workspaces.coding.variants[mode].command='shared';
  config.workspaces.coding.variants.solo.runtime={runner:"generic_layout",windows:[{role:'editor',app_key:'code',required:true}]};
  config.workspaces.coding.variants.wide.layout={type:'window',role:'editor'};
  config.workspaces.coding.variants.wide.runtime={runner:"generic_layout",windows:[{role:'editor',app_key:'chatgpt',required:true}]};
  assert.deepEqual(make(raw(),config).plan.selectedWindows.map(w=>w.id),[10]);
});
test('partial discovery, occupied opposite variants and conflicting labels prevent local destruction',()=>{
  const partial=raw();partial.completeness='partial'; assert.equal(make(partial).plan.executable,false);
  const occupied=raw();occupied.windows.push({...occupied.windows[0],id:99,app:'Other',space:2});
  assert.equal(make(occupied).plan.actions.filter(a=>a.type==='remove_empty_space').length,0);
  const duplicate=raw();duplicate.spaces.push({...duplicate.spaces[1],uuid:'DUP',index:4});
  assert.equal(make(duplicate).plan.executable,false);
  const config=starterConfig();config.workspaces.other=structuredClone(config.workspaces.coding);config.workspaces.other.spaceLabel='other';config.workspaces.other.variants.wide.spaceLabel='custom_wide';
  assert.equal(make(raw(),config).plan.executable,false);
});
test('an inactive workspace plans only its empty target and opposite UUIDs while preserving user Spaces',()=>{
  const config=starterConfig();config.workspaces.coding.variants.solo.activation={type:'windowPresent',role:'editor'};
  const value=raw();value.windows=[];
  const {plan}=make(value,config);
  assert.deepEqual(new Set(plan.actions.filter(a=>a.type==='remove_empty_space').map(a=>a.spaceUuid)),new Set(['S','O']));
  assert.deepEqual(plan.runnerCommands,[['pinned-cleanup']]);
});
test('opposite modes sharing one configured label produce one UUID cleanup action',()=>{
  const config=starterConfig();config.workspaces.coding.variants.tall.spaceLabel='custom_wide';
  assert.deepEqual(make(raw(),config).plan.actions.filter(a=>a.type==='remove_empty_space').map(a=>a.spaceUuid),['O']);
});
test('absolute canvas geometry produces comparable drift and exact backend geometry',()=>{
  const config=starterConfig();config.workspaces.coding.variants.solo.layout={type:'canvas',regions:[{role:'editor',move_abs:'100:200',resize_abs:'300:400'}]};
  const {plan,comparison}=make(raw(),config);
  assert.equal(comparison.converged,false);
  assert.deepEqual(plan.actions.find(a=>a.type==='resize_window').geometry,{move_abs:'100:200',resize_abs:'300:400'});
});
test('mode Sandbox carries exact independent objects and geometry in the fixed plan',()=>{
  const value=raw();value.windows.push({...value.windows[0],id:99,app:'Other',space:3});
  const {plan}=make(value,starterConfig(),{kind:'mode',id:'solo',mode:'solo'});
  assert.ok(plan.selectedWindows.some(w=>w.id===99 && w.workspaceId==='__sandbox'));
  assert.ok(plan.actions.some(a=>a.type==='ensure_space' && a.workspaceId==='__sandbox'));
  assert.ok(plan.actions.some(a=>a.type==='resize_window' && a.windowId===99));
});
test('native fullscreen and observed unmovable complex apps preview an explicit preparation and new-plan boundary',()=>{
  const native=raw();native.windows[0]['is-native-fullscreen']=true;
  const {plan}=make(native);
  assert.equal(plan.preparations[0].type,'native_fullscreen');
  assert.equal(plan.preparations[0].window.id,10);
  assert.equal(plan.executable,true);
  const config=starterConfig();config.workspaces.coding.variants.solo.runtime={runner:'office_document'};
  const blocked=raw();blocked.windows[0]['can-move']=false;
  assert.equal(make(blocked,config).plan.preparations[0].type,'refresh_app');
});
test('cleanup resolves reordered UUIDs and preserves occupied, relabeled, partial and last-survivor Spaces',async()=>{
  const {plan}=make();
  for(const fault of ['none','occupied','relabeled','partial','last','display']) {
    const value=raw();value.spaces[1].index=42;
    if(fault==='occupied')value.windows.push({...value.windows[0],id:99,space:42});
    if(fault==='relabeled')value.spaces[1].label='changed';
    if(fault==='partial')value.completeness='partial';
    if(fault==='last')value.spaces=[value.spaces[1]];
    if(fault==='display')value.displays[0].uuid='changed';
    const commands=[];
    const dependencies={discover:async()=>normalizeSnapshot(value,machine),mutate:async(args,intent,verify)=>{commands.push(args);value.spaces=value.spaces.filter(s=>s.uuid!=='O');assert.ok(verify(normalizeSnapshot(value,machine)));}};
    if(fault==='none'){await executePinnedCleanup(plan,dependencies);assert.deepEqual(commands,[['-m','space','42','--destroy']]);assert.ok(value.spaces.some(s=>s.uuid==='USER'));}
    else {await assert.rejects(executePinnedCleanup(plan,dependencies));assert.equal(commands.length,0);}
  }
});
test('a missing or reused fixed ID never selects an alternative and selected optional failure propagates',async()=>{
  const config=starterConfig();config.workspaces.coding.variants.solo.layout={type:'canvas',regions:[{role:'editor',grid:'1:2:0:0:1:1'},{role:'assistant',grid:'1:2:1:0:1:1'}]};
  const value=raw();value.windows.push({...value.windows[0],id:11,app:'ChatGPT'});const {plan}=make(value,config);
  for(const fault of ['missing','reused','optional']) {
    const live=structuredClone(value),commands=[];
    if(fault==='missing')live.windows[0].id=20;
    if(fault==='reused')live.windows[0].pid++;
    await assert.rejects(executePinnedWorkspace(plan,'coding',{discover:async()=>normalizeSnapshot(live,machine),mutate:async(args)=>{commands.push(args);if(fault==='optional' && args[2]==='11')throw new Error('optional command failed');live.windows[0].frame.w=500;}}));
    if(fault!=='optional')assert.equal(commands.length,0);else assert.ok(commands.some(a=>a[2]==='11'));
  }
});
test('intent precedes mutation, zero exits require postconditions and unavailable storage prevents issuing',async()=>{
  const dir=await mkdtemp(join(tmpdir(),'spacewright-journal-'));let issued=0;
  try {
    await assert.rejects(journalMutation({stateRoot:dir,runId:'test',intent:{windowId:10},run:async()=>{issued++;const records=await operationRecords(dir,'test');assert.equal(records[0].status,'attempted_unknown');return {code:0};},verify:async()=>false}),/postcondition/);
    assert.equal((await operationRecords(dir,'test'))[0].status,'failed');
    const blocked=join(dir,'blocked');await writeFile(blocked,'file');
    await assert.rejects(journalMutation({stateRoot:blocked,runId:'test',intent:{windowId:20},run:async()=>{issued++;},verify:async()=>true}));assert.equal(issued,1);
  }finally{await rm(dir,{recursive:true,force:true});}
});
test('concurrent child budget consumers share atomic limits and cannot extend the run deadline',async()=>{
  const dir=await mkdtemp(join(tmpdir(),'spacewright-budget-'));
  const lease=await acquireExecution(dir,{budgets:{commandRetry:2},deadlineAt:new Date(Date.now()+10000).toISOString()},{inherit:false});
  try {
    const exec=promisify(execFile);const code=`import {consumeBudget} from ${JSON.stringify(new URL('../lib/execution-budget.mjs',import.meta.url).href)}; await consumeBudget(process.env.SPACEWRIGHT_STATE_ROOT,'commandRetry');`;
    const results=await Promise.allSettled(Array.from({length:6},()=>exec(process.execPath,['--input-type=module','-e',code],{env:{...process.env,...lease.env,SPACEWRIGHT_STATE_ROOT:dir,SPACEWRIGHT_EXECUTION_DEADLINE_MS:String(Date.now()+100000)}})));
    assert.equal(results.filter(r=>r.status==='fulfilled').length,2);
    const document=JSON.parse(await readFile(join(dir,'execution.lock','budgets.json'),'utf8'));assert.equal(document.remaining.commandRetry,0);assert.equal(document.consumed.commandRetry,2);
    const ownerPath=join(dir,'execution.lock','owner.json');const owner=JSON.parse(await readFile(ownerPath,'utf8'));owner.deadlineAt=new Date(Date.now()-1).toISOString();await writeFile(ownerPath,JSON.stringify(owner));
    await assert.rejects(consumeBudget(dir,'appRecovery',{env:lease.env}),/deadline/);
    owner.deadlineAt=new Date(Date.now()+10000).toISOString();owner.cancelledAt=new Date().toISOString();await writeFile(ownerPath,JSON.stringify(owner));
    await assert.rejects(consumeBudget(dir,'serviceRecovery',{env:lease.env}),/cancelled/);
  }finally{await lease.release();await rm(dir,{recursive:true,force:true});}
});
test('copied lease variables cannot issue a direct legacy backend mutation',async()=>{
  const dir=await mkdtemp(join(tmpdir(),'spacewright-forged-lease-'));
  try {
    await writeFile(join(dir,'yabai'),'#!/bin/sh\necho UNEXPECTED_MUTATION\n',{mode:0o755});
    const output=execFileSync('fish',['--no-config','-c','source conf.d/spacewright.fish; ws_yabai -m window 10 --space 2; echo result=$status'],{encoding:'utf8',env:{...process.env,PATH:`${dir}:${process.env.PATH}`,SPACEWRIGHT_EXECUTION_RUN_ID:'forged',SPACEWRIGHT_EXECUTION_TOKEN:'forged',SPACEWRIGHT_STATE_ROOT:join(dir,'state')}});
    assert.doesNotMatch(output,/UNEXPECTED_MUTATION/);assert.match(output,/result=[1-9]/);
  }finally{await rm(dir,{recursive:true,force:true});}
});
test('legacy complete-workspace replay stops when the shared reconciliation budget refuses it',()=>{
  const output=execFileSync('fish',['--no-config','-c',`
    source conf.d/spacewright.fish
    function workspace_execution_owned; return 0; end
    function ws_execution_budget; echo budget=$argv[1]; return 1; end
    set -gx SPACEWRIGHT_EXECUTION_RUN_ID fixture
    set -gx WORKSPACE_SKIP_FINALIZATION 1
    set -g __WORKSPACE_YABAI_RESTART_GENERATION 0
    set -g calls 0
    function mock_body
      set -g calls (math "$calls + 1")
      set -g __WORKSPACE_YABAI_RESTART_GENERATION (math "$__WORKSPACE_YABAI_RESTART_GENERATION + 1")
    end
    workspace_run_finalized_entry --mode solo --command mock_body
    echo result=$status calls=$calls
  `],{encoding:'utf8'});
  assert.match(output,/budget=reconciliation/);assert.match(output,/result=1 calls=1/);
});
test('mode ordering resolves both UUIDs after renumbering and does not collect a new window',async()=>{
  const config=starterConfig();config.apps.other={name:'Other',match:{appNames:['Other']}};
  config.workspaces.other=structuredClone(config.workspaces.coding);config.workspaces.other.spaceLabel='other';config.workspaces.other.windows.editor.app='other';
  config.modes.solo.displays[0].workspaceOrder.push('other');
  const value=raw();value.spaces[0].index=2;value.windows[0].space=2;value.spaces[1]={index:1,uuid:'OTHER',display:1,label:'other_solo',type:'float'};value.windows.push({...value.windows[0],id:20,app:'Other',space:1});
  const {plan}=make(value,config,{kind:'mode',id:'solo',mode:'solo'});const commands=[];
  const dependencies={discover:async()=>normalizeSnapshot(value,machine),mutate:async(args,intent,verify)=>{commands.push(args);value.spaces[0].index=1;value.spaces[1].index=2;value.windows[0].space=1;value.windows[1].space=2;assert.ok(verify(normalizeSnapshot(value,machine)));}};
  await executePinnedOrder(plan,dependencies);assert.deepEqual(commands,[['-m','space','1','--move','2']]);
  value.windows.push({...value.windows[0],id:99,app:'New'});
  await assert.rejects(executePinnedOrder(plan,dependencies),/census/);assert.equal(commands.length,1);
});
test('Hermes postprocessing uses final ownership and custom labels in the same geometry policy',()=>{
  const config=starterConfig();config.apps.hermes={name:'Hermes',match:{appNames:['Hermes']}};config.workspaces.coding.windows.editor.app='hermes';
  config.workspaces.coding.variants.solo.spaceLabel='custom_ai';config.workspaces.coding.variants.solo.layout={type:'canvas',regions:[{role:'editor',grid:'1:2:0:0:1:1'}]};config.modes.solo.postprocessors=[{name:'gtd_ai_expand_hermes_when_alone',afterCommand:'spacewright_coding_solo'}];
  const value=raw();value.spaces[0].label='custom_ai';value.windows[0].app='Hermes';
  const {plan,comparison}=make(value,config,{kind:'mode',id:'solo',mode:'solo'});
  assert.equal(comparison.drifts.filter(d=>d.code==='window_geometry_mismatch').length,0);assert.deepEqual(plan.fixedPostprocessors[0].objects.map(w=>w.id),[10]);
});
test('a fixed adapter cannot declare mixed ownership converged or evict foreign objects in workspace scope',()=>{
  const config=starterConfig();config.workspaces.coding.variants.solo.runtime={runner:'fixed_adapter',runnerOptions:{adapter:'coding_control'}};
  const value=raw();value.windows.push({...value.windows[0],id:99,app:'Foreign','can-move':false});
  const local=make(value,config);assert.equal(local.comparison.converged,false);assert.equal(local.plan.executable,false);
  const global=make(value,config,{kind:'mode',mode:'solo',id:'solo'});assert.equal(global.plan.executable,false);
  value.windows[1]['can-move']=true;
  assert.equal(make(value,config).plan.executable,false);
  const movable=make(value,config,{kind:'mode',mode:'solo',id:'solo'});assert.equal(movable.plan.executable,true);assert.ok(movable.plan.selectedWindows.some(w=>w.workspaceId==='__sandbox' && w.id===99));
});
test('adapter verification rejects ambiguity, failed commands, ineffective success and expiry',async()=>{
  const config=starterConfig();config.workspaces.coding.variants.solo.runtime={runner:'office_document'};
  const value=raw();value.windows[0]['can-move']=false;const {plan}=make(value,config);const preparation=plan.preparations[0];
  for(const fault of ['ambiguous','failed','ineffective','timeout']) {
    const live=structuredClone(value);let polls=0;
    await assert.rejects(executePreparation(preparation,{discover:async()=>normalizeSnapshot(live,machine),
      command:async()=>{if(fault==='failed')throw new Error('failure');if(fault==='ambiguous'){live.windows[0]['can-move']=true;live.windows.push({...live.windows[0],id:20});}},
      poll:async()=>{polls++;},delay:async()=>{},check:()=>{if(fault==='timeout')throw Object.assign(new Error('deadline'),{code:'SPACEWRIGHT_TIMEOUT'});}}));
    if(['ambiguous','ineffective'].includes(fault))assert.equal(polls,11);
  }
});
test('monitor serializes sampling, resets debounce after partial discovery and drains events on stop',async()=>{
  let sampling=0,maxSampling=0,queries=0,release,activated=0;
  const gate=new Promise(resolve=>release=resolve),events=[];
  const solo={completeness:'complete',windows:[],spaces:[],displays:[{builtIn:true,frame:{w:1000,h:800}}]};
  const wide={...solo,displays:[...solo.displays,{builtIn:false,frame:{x:1000,w:1000,h:800}}]};
  const monitor=createAutomationMonitor({intervalMs:100000,readConfig:async()=>({settings:{topologyStableSamples:2,eventAutomationEnabled:true},apps:{},workspaces:{},rules:[]}),
    querySnapshot:async()=>{sampling++;maxSampling=Math.max(maxSampling,sampling);queries++;if(queries===1)await gate;sampling--;return queries===3?{...solo,completeness:'partial'}:queries===1?solo:wide;},
    activity:async(...args)=>events.push(args),executeRule:async()=>{throw new Error('unexpected rule');},activateSetup:async()=>{activated++;return true;}});
  monitor.start();const first=monitor.sample(),second=monitor.sample();release();await Promise.all([first,second]);assert.equal(maxSampling,1);
  await monitor.sample();await monitor.sample();assert.equal(activated,0);await monitor.sample();assert.equal(activated,1);
  const pending=monitor.trigger('wake');await monitor.stop();await pending;const count=queries;await monitor.sample();await monitor.trigger('wake');assert.equal(queries,count);
});
test('an interrupted multi-file save leaves a guard and rejects both ordinary and machine-only readers',async()=>{
  const dir=await mkdtemp(join(tmpdir(),'spacewright-save-interruption-'));const source=join(dir,'config.v2.json'),machinePath=join(dir,'machine.json');
  try {
    await atomicText(source,JSON.stringify(starterConfig()));await atomicText(machinePath,JSON.stringify({displayBindings:{primary:'OLD'}}));
    await assert.rejects(withConfigurationWrite(dir,async()=>{await atomicText(machinePath,JSON.stringify({displayBindings:{primary:'NEW'}}));await assert.rejects(stableRead(source,machinePath),/incomplete/);throw new Error('power lost before runtime publish');}),/power lost/);
    await assert.rejects(stableRead(source,machinePath),/incomplete/);
    await assert.rejects(stableRead(join(dir,'not-yet-created.json'),machinePath,{allowMissingConfig:true}),/incomplete/);
  }finally{await rm(dir,{recursive:true,force:true});}
});
test('a generation cannot bind new source bytes to runtime compiled from an older document',()=>{
  const before=starterConfig(),after=structuredClone(before);after.metadata.name='external edit';
  assert.throws(()=>generationDocument(before,null,JSON.stringify(after)),/source.*configuration/);
  assert.doesNotThrow(()=>generationDocument(before,null,JSON.stringify(before)));
});
test('registration completes before a child can mutate, and a crash retains only operated recovery objects',async()=>{
  const dir=await mkdtemp(join(tmpdir(),'spacewright-controller-crash-')),runId='1790000000000-aabbccdd',marker=join(dir,'issued');
  const coordinator=new URL('../lib/execution-coordinator.mjs',import.meta.url).href,journalModule=new URL('../lib/operation-journal.mjs',import.meta.url).href;
  const code=`import {acquireExecution,runBounded} from ${JSON.stringify(coordinator)};import {durableJson,journalMutation} from ${JSON.stringify(journalModule)};import {writeFile} from 'node:fs/promises';
const root=${JSON.stringify(dir)},runId=${JSON.stringify(runId)};const lease=await acquireExecution(root,{runId},{inherit:false});await lease.trackJournal(root+'/runs/'+runId+'.json');await durableJson(root+'/runs/'+runId+'.json',{runId,status:'running',steps:[{status:'running'}],before:{windows:[{id:10},{id:99}]},effects:[]});
await journalMutation({stateRoot:root,runId,intent:{windowId:10,identity:{id:10}},run:()=>runBounded(process.execPath,['-e',${JSON.stringify(`require('fs').writeFileSync(${JSON.stringify(marker)},'issued');process.on('SIGTERM',()=>{});setInterval(()=>{},100);`)}],{onChild:async child=>{await lease.trackChild(child);if(child)await writeFile(root+'/registered','yes');}}),verify:async()=>true});`;
  const child=spawn(process.execPath,['--input-type=module','-e',code],{stdio:['ignore','ignore','pipe']});let error='';child.stderr.on('data',chunk=>error+=chunk);
  try {
    const until=Date.now()+5000;while(Date.now()<until){try{await readFile(marker);break;}catch{await new Promise(r=>setTimeout(r,25));}}
    assert.equal(await readFile(join(dir,'registered'),'utf8'),'yes',error);assert.equal(await readFile(marker,'utf8'),'issued');
    child.kill('SIGKILL');await new Promise(resolve=>child.once('exit',resolve));
    const replacement=await acquireExecution(dir,{runId:'replacement'},{inherit:false});
    const journal=JSON.parse(await readFile(join(dir,'runs',`${runId}.json`),'utf8'));assert.equal(journal.status,'failed');assert.deepEqual(journal.effects.map(e=>e.windowId),[10]);assert.equal(journal.operations[0].status,'attempted_unknown');
    await replacement.release();
  }finally{child.kill('SIGKILL');await rm(dir,{recursive:true,force:true});}
});
