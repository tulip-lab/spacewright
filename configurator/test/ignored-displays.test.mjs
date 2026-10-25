import test from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdtemp, mkdir, readFile, writeFile, rm, readdir } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { starterV3, describeDisplays, resolveV3, resolveModeTransition, matchingSetups, topologyKey } from '../lib/config-v3.mjs';
import { starterConfig, compileV2 } from '../lib/config-v2.mjs';
import { normalizeSnapshot, buildDesiredState, compareState, buildExecutionPlan, geometryMatches } from '../lib/state-engine.mjs';
import { preparationsFor, preparationCommand } from '../lib/adapter-preparation.mjs';
import { selectRole } from '../lib/window-policy.mjs';
import { executePinnedWorkspace, executePinnedCleanup, validatePlanObjects } from '../lib/pinned-executor.mjs';

const exec = promisify(execFile);
const displays = [{index:1,uuid:'TALL',frame:{x:0,y:0,w:1200,h:1920}}, {index:2,uuid:'VIRTUAL',frame:{x:1200,y:0,w:1920,h:1080}}];
const machine = {hardwareProfile:'mac_mini',hardwareProfileConfirmed:true,displayBindings:{tall:'TALL',primary:'TALL'},displayKinds:{VIRTUAL:'ignored'},topologySelections:{'external:tall':'single_tall'}};
const window = (id,display,space,app='Code') => ({id,pid:100+id,app,display,space,role:'AXWindow',subrole:'AXStandardWindow',frame:{x:0,y:0,w:600,h:900},'can-move':true,'can-resize':true});
const raw = () => ({displays,spaces:[{index:1,uuid:'A',display:1,label:'coding_solo',type:'float'}, {index:2,uuid:'B',display:2,label:'virtual_user',type:'float'}, {index:3,uuid:'C',display:2,label:'coding_wide',type:'float'}, {index:4,uuid:'D',display:2,label:'',type:'float'}],windows:[window(10,1,1),window(20,2,2),window(30,2,2,'Unclaimed app')]});

test('only explicitly ignored UUIDs are omitted from setup matching, including reconnects',()=>{
  const config=starterV3();
  assert.deepEqual(matchingSetups(config,'mac_mini',{displays},machine),['single_tall']);
  for(const connected of [displays,displays.slice(0,1),displays]) {
    const resolution=resolveV3(config,{machine,snapshot:{displays:connected}});
    assert.equal(resolution.setupId,'single_tall');assert.equal(resolution.topologyKey,'external:tall');
  }
  const inventory=describeDisplays({displays},machine,{includeIgnored:true});
  assert.equal(inventory.length,2);assert.equal(inventory[1].ignored,true);
  assert.equal(topologyKey(inventory),'external:tall');
  assert.equal(resolveModeTransition(config,{machine,snapshot:{displays},mode:'tall'}).setupId,'single_tall');
  assert.throws(()=>resolveV3(config,{machine,snapshot:{displays:[displays[0],{...displays[1],uuid:'NEW-PHYSICAL'}]}}),/confirmation/);
});

test('ignored displays supply configured and Sandbox windows while remaining excluded destinations',()=>{
  const snapshot=normalizeSnapshot(raw(),machine),config=starterConfig();
  config.modes.solo.displays=[{role:'primary',workspaceOrder:['coding']}];
  config.settings={...config.settings,cleanupEmptySpaces:'all'};
  assert.equal(snapshot.displays.length,2);assert.equal(snapshot.spaces.length,4);assert.equal(snapshot.windows.length,3);
  assert.deepEqual(snapshot.spaces.find(s=>s.uuid==='B').windows,[20,30]);
  assert.equal(snapshot.windows.find(w=>w.id===20).ignoredDisplay,true);
  assert.deepEqual(selectRole(snapshot.windows,{appNames:['Code'],selector:{movable:true}},{targetSpace:1}).selected.map(w=>w.id),[10]);
  assert.deepEqual(selectRole(snapshot.windows,{windowId:20,appNames:['Code']}).selected.map(w=>w.id),[20]);
  const desired=buildDesiredState(config,compileV2(config),{kind:'mode',id:'solo',mode:'solo'},snapshot);
  assert.deepEqual(desired.workspaces.find(w=>w.workspaceId==='__sandbox').windows.map(w=>w.windowId),[20,30]);
  const comparison=compareState(snapshot,desired,machine);
  const plan=buildExecutionPlan(snapshot,desired,comparison);
  assert.deepEqual(plan.selectedWindows.map(w=>w.id).sort((a,b)=>a-b),[10,20,30]);
  assert.ok(plan.executable);
  assert.ok(plan.workspaces.every(w=>w.targetDisplay?.uuid==='TALL'));
  assert.ok(plan.actions.some(a=>a.type==='ensure_space' && a.workspaceId==='__sandbox'));
  assert.ok(!plan.actions.some(a=>a.type==='remove_empty_space' && ['B','C','D'].includes(a.spaceUuid)));
  assert.equal(plan.preconditions.windows.length,3);
  const changed=raw();changed.windows.push(window(40,2,2,'Remote app'));
  const after=normalizeSnapshot(changed,machine);
  validatePlanObjects(plan,after);
  const afterDesired=buildDesiredState(config,compileV2(config),{kind:'mode',id:'solo',mode:'solo'},after);
  assert.notEqual(buildExecutionPlan(after,afterDesired,compareState(after,afterDesired,machine)).planId,plan.planId);
  assert.ok(afterDesired.workspaces.find(w=>w.workspaceId==='__sandbox').windows.some(w=>w.windowId===40));
  desired.orchestration.displayProfile='solo';
  assert.ok(buildExecutionPlan(snapshot,desired,comparison).blockers.some(b=>b.code==='display_profile_with_ignored_display'));

});

test('Space ownership conflicts on an ignored display fail closed rather than moving the Space',()=>{
  const value=raw();value.spaces[0].label='';value.spaces[1].label='coding_solo';
  const snapshot=normalizeSnapshot(value,machine),config=starterConfig();
  const desired=buildDesiredState(config,compileV2(config),{kind:'workspace',id:'coding',mode:'solo'},snapshot);
  const plan=buildExecutionPlan(snapshot,desired,compareState(snapshot,desired,machine));
  assert.equal(plan.executable,false);assert.ok(plan.blockers.some(b=>b.code==='space_on_ignored_display'));
});

test('executor permits virtual window sources but refuses changed identity and ignored targets',async()=>{
  const value=raw(),config=starterConfig();
  const snapshot=normalizeSnapshot(value,machine);
  const desired=buildDesiredState(config,compileV2(config),{kind:'workspace',id:'coding',mode:'solo'},snapshot);
  const plan=buildExecutionPlan(snapshot,desired,compareState(snapshot,desired,machine));
  let mutations=0;
  const run=live=>executePinnedWorkspace(plan,'coding',{discover:async()=>live,mutate:async()=>{mutations++;}});
  const moved=structuredClone(snapshot);moved.windows[0].pid++;
  await assert.rejects(run(moved),/fixed object precondition changed/);
  const ignored=structuredClone(snapshot);ignored.displays[0].ignored=true;
  await assert.rejects(run(ignored),/planned display/);
  const cleanup={...plan,actions:[{type:'remove_empty_space',spaceUuid:'C',label:'coding_wide',displayUuid:'VIRTUAL'}]};
  await assert.rejects(executePinnedCleanup(cleanup,{discover:async()=>snapshot,mutate:async()=>{mutations++;}}),/planned Space/);
  assert.equal(mutations,0);
});


test('configured app on a virtual display is moved and resized on a managed display, including AX preparation',async()=>{
  const value=raw();value.windows=value.windows.filter(w=>w.id!==10);
  const snapshot=normalizeSnapshot(value,machine),config=starterConfig();
  const target={kind:'workspace',id:'coding',mode:'solo'};
  const desired=buildDesiredState(config,compileV2(config),target,snapshot);
  const plan=buildExecutionPlan(snapshot,desired,compareState(snapshot,desired,machine));
  assert.ok(plan.executable);assert.deepEqual(plan.selectedWindows.map(w=>w.id),[20]);
  const mutations=[];
  await executePinnedWorkspace(plan,'coding',{discover:async()=>normalizeSnapshot(value,machine),mutate:async(args,intent,verify)=>{
    mutations.push(intent.type);
    const w=value.windows.find(w=>w.id===intent.windowId);
    if(intent.type==='move_window'){w.space=1;w.display=1;}
    if(intent.type==='resize_window')w.frame=geometryMatches(normalizeSnapshot(value,machine).windows.find(w=>w.id===intent.windowId),snapshot.displays[0],{grid:intent.geometry}).expected;
    assert.ok(await verify(normalizeSnapshot(value,machine)));
  }});
  assert.ok(mutations.includes('move_window'));assert.ok(mutations.includes('resize_window'));
  assert.equal(value.windows.find(w=>w.id===20).display,1);
  assert.equal(value.windows.find(w=>w.id===30).display,2);
  const axless=normalizeSnapshot(raw(),machine);axless.windows=axless.windows.filter(w=>w.id!==10);
  axless.windows.find(w=>w.id===20).hasAxReference=false;
  const observation=preparationsFor(axless,desired).find(p=>p.type==='observe_space');
  assert.ok(observation.windows.some(w=>w.id===20));
  assert.deepEqual(preparationCommand(observation,axless),['yabai',['-m','space','--focus','2']]);
});

test('public ignore-display dry-run is inert, saves local policy, and prevents ignoring the last managed screen',async()=>{
  const root=await mkdtemp(join(tmpdir(),'spacewright-ignore-'));
  const configRoot=join(root,'config'),stateRoot=join(root,'state'),snapshot=join(root,'snapshot.json');
  try {
    await mkdir(configRoot);await mkdir(stateRoot);
    await writeFile(join(configRoot,'config.v3.json'),JSON.stringify(starterV3()));
    const initial={...machine,displayKinds:{}};
    await writeFile(join(stateRoot,'machine.json'),JSON.stringify(initial));
    await writeFile(snapshot,JSON.stringify({displays}));
    const common=[`--config-root=${configRoot}`,`--state-root=${stateRoot}`,`--snapshot=${snapshot}`,'--model=Macmini9,1'];
    const run=async(...args)=>JSON.parse((await exec(new URL('../../bin/spacewright',import.meta.url).pathname,['setup',...args,...common])).stdout);
    const before=await readFile(join(stateRoot,'machine.json'),'utf8');
    assert.equal((await run('ignore-display','VIRTUAL','--dry-run')).mutates,false);
    assert.equal(await readFile(join(stateRoot,'machine.json'),'utf8'),before);
    assert.deepEqual(await readdir(configRoot),['config.v3.json']);
    assert.equal((await run('ignore-display','VIRTUAL')).setup,'single_tall');
    assert.equal((await run('status')).ready,true);
    assert.equal(JSON.parse(await readFile(join(stateRoot,'machine.json'))).displayKinds.VIRTUAL,'ignored');
    assert.equal(JSON.parse(await readFile(join(configRoot,'generated/runtime.json'))).active_setup,'single_tall');
    const saved=await readFile(join(stateRoot,'machine.json'),'utf8');
    await assert.rejects(run('ignore-display','TALL'),/unmatched/);
    await assert.rejects(run('ignore-display','UNKNOWN'),/connected display UUID/);
    assert.equal(await readFile(join(stateRoot,'machine.json'),'utf8'),saved);
    // Including a display also requires a confirmed topology; no silent dual-screen adoption.
    await assert.rejects(run('include-display','VIRTUAL'),/confirmation/);
  } finally {await rm(root,{recursive:true,force:true});}
});

test('direct Fish display profiles refuse connected ignored displays before executing consumer scripts',async()=>{
  const root=await mkdtemp(join(tmpdir(),'spacewright-ignore-profile-'));
  try {
    await writeFile(join(root,'machine.json'),JSON.stringify({displayKinds:{VIRTUAL:'ignored'}}));
    await assert.rejects(exec('fish',['--no-config','-c',`
      source lib/spacewright/display/display_entries.fish
      function workspace_execution_owned; return 0; end
      function ws_query_displays; echo '[{"uuid":"VIRTUAL"}]'; end
      function unsafe_profile; echo UNEXPECTED_PROFILE; end
      display_apply_profile_mode unsafe_profile tall
    `],{cwd:new URL('../..',import.meta.url).pathname,env:{...process.env,SPACEWRIGHT_STATE_ROOT:root}}),error=>{
      assert.match(error.stderr,/cannot preserve ignored displays/);
      assert.equal(error.stdout.includes('UNEXPECTED_PROFILE'),false);
      return true;
    });
  } finally {await rm(root,{recursive:true,force:true});}
});
