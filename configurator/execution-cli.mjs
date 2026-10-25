#!/usr/bin/env node
import { normalizeSnapshot } from './lib/state-engine.mjs';
import { selectRole } from './lib/window-policy.mjs';
import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { acquireExecution, runBounded, verifyLease, processIdentity,assertExecutionAllowed } from './lib/execution-coordinator.mjs';
import { discoverState } from './lib/discovery.mjs';
import { executePinnedWorkspace, executePinnedCleanup, executePinnedOrder, confirmWindowGeometry } from './lib/pinned-executor.mjs';
import { durableJson, journalMutation, operationRoot } from './lib/operation-journal.mjs';
import { readJson } from './lib/execution-coordinator.mjs';
import { consumeBudget } from './lib/execution-budget.mjs';
import { preparationCommand,preparationDepartureCommand,verifyPreparation,axReferenceError,AX_UNAVAILABLE_EXIT } from './lib/adapter-preparation.mjs';
const [action, executable, ...args] = process.argv.slice(2);
const stateRoot = process.env.SPACEWRIGHT_STATE_ROOT;
try {
  if (action === 'select') {
    const value = JSON.parse(await readFile('/dev/stdin', 'utf8'));
    const role = value.plan.windows[value.index];
    const selected = selectRole(normalizeSnapshot({windows:value.windows}).windows, { ...role, allowNativeFullscreen:value.plan.preparation === true, appNames: role.app_names || [], bundleIds: role.bundle_ids || [] }, {used:value.used || [], targetSpace:value.targetSpace});
    if (selected.ambiguous) { if (role.required) throw new Error('required window match is ambiguous'); }
    else for (const window of selected.selected) process.stdout.write(`${window.id}\n`);
  } else if (action === 'verify') {
    await assertExecutionAllowed(stateRoot);
  } else if (action === 'budget') {
    await consumeBudget(stateRoot,executable);
  } else if (action === 'exec') {
    let deadline = Number(process.env.SPACEWRIGHT_EXECUTION_DEADLINE_MS) || Date.now() + 120000;
    const lease = await acquireExecution(stateRoot, { controller: 'direct', deadlineAt: new Date(deadline).toISOString() });
    deadline=Math.min(deadline,new Date(lease.owner.deadlineAt).getTime());
    if(process.env.SPACEWRIGHT_SUBSTEP_TIMEOUT_MS)deadline=Math.min(deadline,Date.now()+Number(process.env.SPACEWRIGHT_SUBSTEP_TIMEOUT_MS));
    const abort = new AbortController();
    for (const sig of ['SIGTERM', 'SIGINT']) process.once(sig, () => {void lease.cancel().catch(error=>process.stderr.write(`cancellation state write failed: ${error.message}\n`));abort.abort(Object.assign(new Error('cancelled'), { code: 'SPACEWRIGHT_CANCELLED' }));});
    try {
      const result = await runBounded(executable, args, { env: { ...process.env, ...lease.env }, deadline, signal: abort.signal,
        onChild: lease.trackChild, onOutput: (stream, value) => process[stream].write(value) });
      process.exitCode = result.code;
    } finally { await lease.release(); }
  } else if (['pinned-workspace','pinned-cleanup','pinned-finalize','pinned-postprocess','prepare-operation'].includes(action)) {
    await assertExecutionAllowed(stateRoot);
    const envelope = JSON.parse(await readFile(process.env.SPACEWRIGHT_EXECUTION_ENVELOPE,'utf8'));
    const lease = await acquireExecution(stateRoot);
    const operationRunId=process.env.SPACEWRIGHT_OPERATION_RUN_ID || lease.owner.runId;
    const deadline = Number(lease.env.SPACEWRIGHT_EXECUTION_DEADLINE_MS);
    const abort = new AbortController();
    for(const sig of ['SIGTERM','SIGINT'])process.once(sig,()=>abort.abort(Object.assign(new Error('cancelled'),{code:'SPACEWRIGHT_CANCELLED'})));
    const createdFile=join(operationRoot(stateRoot,operationRunId),'created-spaces.json');
    const createdSpaces=await readJson(createdFile,{});
    const discover=()=>discoverState(envelope.machine,{deadline,signal:abort.signal});
    const mutate=async(arguments_,intent,verify)=>{
      await assertExecutionAllowed(stateRoot);
      const result=await journalMutation({stateRoot,runId:operationRunId,intent:{...intent,arguments:arguments_,attempted:true},
        run:()=>runBounded('yabai',arguments_,{deadline:Math.min(deadline,Date.now()+3000),signal:abort.signal,onChild:lease.trackChild}),
        verify:async()=>intent.type==='resize_window'
          ? confirmWindowGeometry(verify,discover,{check:()=>assertExecutionAllowed(stateRoot),poll:()=>consumeBudget(stateRoot,'confirmation')})
          : verify(await discover())});
      process.stderr.write(`[MUTATION] ${JSON.stringify({...intent,attempted:true,status:'verified_success'})}\n`);
      return result;
    };
    const dependencies={discover,mutate,createdSpaces,registerCreated:spaces=>durableJson(createdFile,spaces)};
    if(action==='prepare-operation') {
      const preparation=envelope.plan.preparations[Number(executable)];
      if(!preparation)throw new Error('adapter preparation outside plan');
      await consumeBudget(stateRoot,preparation.budget);
      const phaseDeadline=Math.min(deadline,Date.now()+preparation.phaseLimitMs);
      let relation;
      const check=()=>{if(abort.signal.aborted)throw abort.signal.reason;if(Date.now()>=deadline)throw Object.assign(new Error('execution deadline exceeded'),{code:'SPACEWRIGHT_TIMEOUT'});if(Date.now()>=phaseDeadline)throw preparation.type==='observe_space'?axReferenceError(preparation):Object.assign(new Error('adapter deadline exceeded'),{code:'SPACEWRIGHT_TIMEOUT'});};
      // The operation record stores the input incarnation and explicit output
      // incarnations before any new immutable layout plan can be issued.
      try {
        const before=await discover();
        const departure=preparationDepartureCommand(preparation,before);
        if(departure)await mutate(departure[1],{type:'preparation_focus_departure',spaceUuid:preparation.departureSpaceUuid,reversible:false},after=>after.completeness==='complete' && after.spaces.some(s=>s.uuid===preparation.departureSpaceUuid && s.focused));
        const [exe,arguments_]=preparationCommand(preparation,before);
        await journalMutation({stateRoot,runId:operationRunId,intent:{type:'adapter_preparation',preparation,windowId:null,identity:preparation.window,reversible:false},
          run:()=>runBounded(exe,arguments_,{deadline:phaseDeadline,signal:abort.signal,onChild:lease.trackChild}),
          verify:async()=>{relation=await verifyPreparation(preparation,{discover:()=>discoverState(envelope.machine,{deadline:phaseDeadline,signal:abort.signal}),check,poll:()=>consumeBudget(stateRoot,'confirmation')});return relation;}});
      } finally {
        if(preparation.type==='observe_space' && preparation.returnSpaceUuid) {
          const snapshot=await discover();
          if(snapshot.completeness!=='complete')throw new Error('focus restoration discovery incomplete');
          const space=snapshot.spaces.find(s=>s.uuid===preparation.returnSpaceUuid);
          if(!space)throw new Error('original focus Space disappeared');
          if(!space.focused)await mutate(['-m','space','--focus',String(space.index)],{type:'preparation_focus_restore',spaceUuid:space.uuid,reversible:false},after=>after.completeness==='complete' && after.spaces.some(s=>s.uuid===space.uuid && s.focused));
        }
      }
      process.stdout.write(`${JSON.stringify(relation)}\n`);
    } else if(action==='pinned-postprocess') {
      const hook=envelope.plan.fixedPostprocessors.find(h=>h.name===executable);
      if(!hook)throw new Error('postprocessor outside fixed plan');
      const snapshot=await discover();
      if(snapshot.completeness!=='complete')throw new Error('incomplete postprocessor discovery');
      for(const object of hook.objects) {
        const window=snapshot.windows.find(w=>w.id===object.id);
        if(!window || window.app!==object.app || window.pid!==object.pid || window.bundleId!==object.bundleId || object.processFingerprint && window.processFingerprint!==object.processFingerprint)throw new Error('postprocessor object changed; replan required');
      }
      // Its final geometry and ownership are already part of workspace actions.
      // The final aggregate comparison validates those same postconditions.
    } else if(action==='pinned-workspace') {
      await executePinnedWorkspace(envelope.plan,executable,dependencies);
      await durableJson(createdFile,createdSpaces);
    } else {
      await executePinnedCleanup(envelope.plan,dependencies);
      if(action==='pinned-finalize')await executePinnedOrder(envelope.plan,dependencies);
    }
  } else if (action === 'window-check') {
    if (!await verifyLease(stateRoot)) throw new Error('execution ownership is not valid');
    const envelope = JSON.parse(await readFile(process.env.SPACEWRIGHT_EXECUTION_ENVELOPE, 'utf8'));
    const expected = envelope.plan.selectedWindows.find((w) => w.id === Number(executable));
    const current = JSON.parse(await readFile('/dev/stdin', 'utf8'));
    if (!expected || current.id !== expected.id || current.app !== expected.app || Number(current.pid || 0) !== expected.pid || String(current['bundle-id'] || '') !== expected.bundleId) throw new Error(`planned window ${executable} identity changed; replan required`);
    if ((await processIdentity(expected.pid) || null) !== (expected.processFingerprint || null)) throw new Error('planned application process lifetime changed; replan required');
    const s = expected.selector;
    if (current['is-minimized'] || current['is-native-fullscreen'] || s.movable && !current['can-move'] || s.resizable && !current['can-resize'] || s.visible && current['is-visible'] === false
      || s.non_empty_title && !current.title || s.title_include && !String(current.title || '').includes(s.title_include)
      || s.title_exclude && String(current.title || '').includes(s.title_exclude) || s.role && current.role !== s.role || s.subrole && current.subrole !== s.subrole) throw new Error(`planned window ${executable} precondition changed; replan required`);
  } else throw new Error('unknown execution coordination action');
} catch (error) { process.stderr.write(`SpaceWright: ${error.message}\n`); process.exitCode = error.code === 'SPACEWRIGHT_AX_UNAVAILABLE' ? AX_UNAVAILABLE_EXIT : error.code === 'SPACEWRIGHT_CANCELLED' ? 130 : error.code === 'SPACEWRIGHT_TIMEOUT' ? 124 : 1; }
