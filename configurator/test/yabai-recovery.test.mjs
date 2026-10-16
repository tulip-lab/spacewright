import test from 'node:test';
import assert from 'node:assert/strict';
import { recoverYabai, recoveryPreview, assertServiceRecoveryInput } from '../lib/yabai-recovery.mjs';
import { starterConfig, compileV2 } from '../lib/config-v2.mjs';
import { buildDesiredState, compareState, buildExecutionPlan } from '../lib/state-engine.mjs';
import { executionCensus, isObservationOverlay, selectRole } from '../lib/window-policy.mjs';
import { validatePlanObjects, executePinnedWorkspace } from '../lib/pinned-executor.mjs';
import { windowOccupiesSpace } from '../lib/finalization-policy.mjs';
import { axReferenceError, AX_UNAVAILABLE_EXIT } from '../lib/adapter-preparation.mjs';

const snapshot = () => ({completeness:'complete',capturedAt:new Date().toISOString(),
  displays:[{index:1,uuid:'D',frame:{x:0,y:0,w:1200,h:1800}}],
  spaces:[{index:1,uuid:'A',label:'work',display:1,layout:'float',focused:true},
    {index:2,uuid:'B',label:'personal',display:1,layout:'float'}],
  windows:[{id:10,pid:100,processFingerprint:'process-100',app:'Dia',bundleId:'',space:1,
    role:'AXWindow',subrole:'AXStandardWindow',hasAxReference:false,frameVerified:true,
    frame:{x:4,y:35,w:1192,h:1700},movable:false,resizable:false}]});
function fixture() {
  let live = snapshot(), checkpoint;
  const commands = [], saves = [], consumed = [];
  const defaults = {top_padding:'4',bottom_padding:'4',left_padding:'4',right_padding:'4',window_gap:'4'};
  const settings = {A:{...defaults,left_padding:'16'},B:{...defaults,window_gap:'12'}};
  let external = 'all:12:0';
  const dependencies = {
    discover:async()=>structuredClone(live),check:async()=>{},delay:async()=>{},
    consume:async kind=>{consumed.push(kind);if(consumed.filter(k=>k==='serviceRecovery').length>1)throw new Error('serviceRecovery execution budget exhausted');},
    persist:async value=>{checkpoint=structuredClone(value);saves.push(checkpoint.status);},
    query:async args=>args[2]==='external_bar'?external:settings[live.spaces.find(s=>s.index===Number(args[3])).uuid][args[4]],
    mutate:async(args,intent,verify)=>{
      commands.push(args);
      if(args[0]==='--restart-service') {
        assert.equal(checkpoint.status,'restart_attempted');
        for(const s of live.spaces){s.label='';settings[s.uuid]={...defaults};s.index=3-s.index;}
        live.windows[0].space=2;live.windows[0].hasAxReference=true;external='off:0:0';
      } else if(args[1]==='space' && args[3]==='--label')live.spaces.find(s=>s.index===Number(args[2])).label=args[4];
      else if(args[1]==='config' && args[2]==='external_bar')external=args[3];
      else if(args[1]==='config')settings[live.spaces.find(s=>s.index===Number(args[3])).uuid][args[4]]=args[5];
      else if(args[1]==='space' && args[2]==='--focus')live.spaces.forEach(s=>s.focused=s.index===Number(args[3]));
      else throw new Error(`unplanned command ${args}`);
      assert.equal(await verify(),true);
    }
  };
  return {dependencies,commands,saves,consumed,settings,get live(){return live;},get checkpoint(){return checkpoint;}};
}

test('one service restart restores labels and settings by UUID after indexes change',async()=>{
  const f=fixture();
  const result=await recoverYabai(f.dependencies);
  assert.equal(result.status,'completed');
  assert.deepEqual(f.live.spaces.map(s=>[s.uuid,s.index,s.label]),[['A',2,'work'],['B',1,'personal']]);
  assert.equal(f.settings.A.left_padding,'16');assert.equal(f.settings.B.window_gap,'12');
  assert.deepEqual(f.saves.slice(0,2),['saved','restart_attempted']);
  assert.equal(f.commands.filter(a=>a[0]==='--restart-service').length,1);
  assert.deepEqual(f.consumed,['serviceRecovery']);
  assert.ok(f.commands.some(a=>a[2]==='2' && a[3]==='--label' && a[4]==='work'));
  assert.ok(!f.commands.some(a=>a[1]==='window' || a.includes('--destroy') || a.includes('--create')));
});

test('an interrupted restart has a durable checkpoint that resumes without another restart',async()=>{
  const f=fixture(),mutate=f.dependencies.mutate;
  f.dependencies.mutate=async(args,...rest)=>{await mutate(args,...rest);if(args[0]==='--restart-service')throw new Error('interrupted');};
  await assert.rejects(recoverYabai(f.dependencies),/interrupted/);
  assert.equal(f.checkpoint.status,'restart_attempted');
  const saved=structuredClone(f.checkpoint);f.dependencies.mutate=mutate;
  await recoverYabai({...f.dependencies,resume:saved});
  assert.equal(f.commands.filter(a=>a[0]==='--restart-service').length,1);
  assert.deepEqual(f.live.spaces.map(s=>s.label),['work','personal']);
});

for(const fault of ['partial','duplicate_label','bsp','fullscreen'])test(`unsafe ${fault} discovery never restarts yabai`,async()=>{
  const f=fixture();
  if(fault==='partial')f.live.completeness='partial';
  if(fault==='duplicate_label')f.live.spaces[1].label='work';
  if(fault==='bsp')f.live.spaces[1].layout='bsp';
  if(fault==='fullscreen')f.live.windows[0].nativeFullscreen=true;
  await assert.rejects(recoverYabai(f.dependencies));assert.deepEqual(f.commands,[]);
});

for(const fault of ['space','display','window','label'])test(`changed ${fault} identity after restart stops before label or layout mutations`,async()=>{
  const f=fixture(),mutate=f.dependencies.mutate;
  f.dependencies.mutate=async(args,intent,verify)=>mutate(args,intent,async()=>{
    if(args[0]==='--restart-service') {
      if(fault==='space')f.live.spaces[0].uuid='REUSED';
      if(fault==='display')f.live.displays[0].frame.w++;
      if(fault==='window')f.live.windows[0].pid++;
      if(fault==='label')f.live.spaces[1].label='foreign';
    }
    return verify();
  });
  await assert.rejects(recoverYabai(f.dependencies),/changed/);
  assert.deepEqual(f.commands,[['--restart-service']]);
  assert.equal(f.checkpoint.status,'restart_attempted');
});

for(const fault of ['checkpoint','budget','cancel'])test(`${fault} failure blocks service mutation`,async()=>{
  const f=fixture();
  if(fault==='checkpoint')f.dependencies.persist=async()=>{throw new Error('disk unavailable');};
  if(fault==='budget')f.dependencies.consume=async()=>{throw new Error('serviceRecovery execution budget exhausted');};
  if(fault==='cancel')f.dependencies.check=async()=>{if(f.checkpoint)throw Object.assign(new Error('cancelled'),{code:'SPACEWRIGHT_CANCELLED'});};
  await assert.rejects(recoverYabai(f.dependencies));assert.deepEqual(f.commands,[]);
});

test('dry-run preview explicitly declares service effects without running any command',()=>{
  const result=recoveryPreview(snapshot());assert.equal(result.mutates,false);
  assert.equal(result.maxAttempts,1);assert.ok(result.sideEffects.includes('reload_yabairc'));
});
test('automatic recovery rejects changes since the failed observation before restarting',async()=>{
  for (const change of [f=>f.live.windows[0].pid++,f=>f.live.spaces[0].label='changed',f=>f.live.displays[0].uuid='changed']) {
    const f=fixture(),expected=structuredClone(f.live);change(f);
    await assert.rejects(recoverYabai({...f.dependencies,expectedSnapshot:expected}),/changed/);
    assert.deepEqual(f.commands,[]);
  }
  const before=snapshot(),after=structuredClone(before);after.windows[0].hasAxReference=true;after.windows[0].movable=true;
  assert.doesNotThrow(()=>assertServiceRecoveryInput(before,after));
});

const overlay = (id=20,title='Computer Use') => ({id,pid:200,app:'ChatGPT',bundleId:'com.openai.codex',
  title,role:'AXWindow',subrole:'AXSystemDialog',hasAxReference:true,frameVerified:true,
  frame:{x:10,y:10,w:360,h:264},resizable:false,space:1});
test('known observation overlays can appear and disappear without invalidating an aggregate layout',()=>{
  const value=snapshot();value.windows[0].hasAxReference=true;
  const plan={scope:'mode',preconditions:{windows:executionCensus(value.windows)},selectedWindows:[]};
  validatePlanObjects(plan,{...value,windows:[...value.windows,overlay(),overlay(21,'Computer Use Controls')]});
  assert.deepEqual(executionCensus([overlay()]),[]);
  assert.equal(windowOccupiesSpace(overlay()),true);
  assert.equal(executionCensus([overlay()],[20]).length,1);
  assert.equal(selectRole([{...overlay(),movable:true}],{appNames:['ChatGPT'],selector:{movable:true}}).selected.length,0);
  assert.equal(selectRole([{...overlay(),movable:true}],{appNames:['ChatGPT'],windowId:20,selector:{movable:true}}).selected.length,1);
  validatePlanObjects(plan,value);
});
test('permission prompts, ordinary dialogs and changed overlay fingerprints still invalidate the census',()=>{
  const value=snapshot(),plan={scope:'mode',preconditions:{windows:value.windows},selectedWindows:[]};
  for(const change of [{title:'Allow Accessibility Access?'},{app:'Dia'},{bundleId:'other.app'},
    {resizable:true},{subrole:'AXDialog'},{hasAxReference:false},{frameVerified:false},
    {frame:{x:0,y:0,w:1200,h:900}}]) {
    const window={...overlay(),...change};assert.equal(isObservationOverlay(window),false);
    assert.throws(()=>validatePlanObjects(plan,{...value,windows:[...value.windows,window]}),/census changed/);
  }
});
test('AX diagnostics name affected apps and windows and use a distinct recovery exit',()=>{
  const error=axReferenceError({windows:[{id:25370,app:'Dia'}]});
  assert.equal(error.code,'SPACEWRIGHT_AX_UNAVAILABLE');assert.equal(AX_UNAVAILABLE_EXIT,76);
  assert.match(error.message,/Dia \(25370\)/);assert.match(error.message,/repair-yabai/);
});
test('an app minimum size reports the exact window and requested/actual geometry',async()=>{
  const value=snapshot(),config=starterConfig(),machine={displayBindings:{primary:'D'}};
  value.displays[0].frame.h=800;value.spaces[0].label='coding_solo';value.spaces[0].windows=[10];value.spaces[1].windows=[];
  Object.assign(value.windows[0],{app:'Code',movable:true,resizable:true});
  config.workspaces.coding.variants.solo.layout={type:'canvas',regions:[{role:'editor',grid:'2:1:0:0:1:1'}]};
  const desired=buildDesiredState(config,compileV2(config),{kind:'workspace',id:'coding',mode:'solo'},value);
  const plan=buildExecutionPlan(value,desired,compareState(value,desired,machine));
  await assert.rejects(executePinnedWorkspace(plan,'coding',{
    discover:async()=>value,
    mutate:async(args,intent,verify)=>{
      assert.equal(args[3],'--grid');value.windows[0].frame={x:0,y:0,w:1200,h:620};return verify(value);
    }
  }),/Code \(10\).*expected.*actual.*minimum window size/);
});
for(const target of [{kind:'mode',id:'solo',mode:'solo'},{kind:'workspace',id:'coding',mode:'solo'}])test(`observation overlay churn preserves the ${target.kind} plan digest and app selection`,()=>{
  const value=snapshot(),config=starterConfig();
  value.spaces[0].label='coding_solo';value.windows[0].app='Code';value.windows[0].movable=true;value.windows[0].resizable=true;
  config.modes.solo.displays=[{role:'primary',workspaceOrder:['coding']}];
  const machine={displayBindings:{primary:'D'}};
  const make=raw=>{
    const normalized=structuredClone(raw);
    for(const space of normalized.spaces)space.windows=normalized.windows.filter(w=>w.space===space.index).map(w=>w.id);
    const desired=buildDesiredState(config,compileV2(config),target,normalized);
    const comparison=compareState(normalized,desired,machine);
    return buildExecutionPlan(normalized,desired,comparison);
  };
  const before=make(value);value.windows.push({...overlay(),movable:true},{...overlay(21,'Computer Use Controls'),movable:true});
  const after=make(value);
  assert.equal(after.planId,before.planId);assert.deepEqual(after.selectedWindows,before.selectedWindows);
});
