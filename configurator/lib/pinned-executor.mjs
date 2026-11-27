import { sameWindowIdentity } from './recovery.mjs';
import { windowOccupiesSpace } from './finalization-policy.mjs';
import { selectorResult,assertWindowCensus } from './window-policy.mjs';
import { geometryMatches } from './state-engine.mjs';

export async function confirmPendingMutation(verify, discover, {poll, check, delay=ms=>new Promise(resolve=>setTimeout(resolve,ms))}) {
  for(let attempt=0;attempt<5;attempt++) {
    await check();
    try { return await verify(await discover()); }
    catch(error) {
      if(!['SPACEWRIGHT_GEOMETRY_PENDING','SPACEWRIGHT_FOCUS_PENDING'].includes(error.code) || attempt===4)throw error;
      await poll();await delay(100);
    }
  }
}

function complete(snapshot) {
  if(snapshot.completeness!=='complete')throw new Error(snapshot.message || 'incomplete discovery; no mutation permitted');
  const age=Date.now()-new Date(snapshot.capturedAt).getTime();
  if(!Number.isFinite(age) || age<0 || age>15000)throw new Error('discovery expired; replan required');
  return snapshot;
}
export function validatePlanObjects(plan,snapshot) {
  complete(snapshot);
  if(plan.scope==='mode') {
    assertWindowCensus(plan.preconditions.windows,snapshot.windows,plan.selectedWindows);
  }
  for(const expected of plan.selectedWindows) {
    const current=snapshot.windows.find(w=>w.id===expected.id);
    if(!sameWindowIdentity(expected,current) || !selectorResult(current,{windowId:expected.id,appNames:[expected.app],selector:expected.selector}).matches)throw new Error('fixed object precondition changed; replan required');
  }
  return snapshot;
}
function displayFor(snapshot,expected) {
  const display=snapshot.displays.find(d=>d.uuid===expected?.uuid);
  if(!display || display.ignored || snapshot.displays.filter(d=>d.uuid===display.uuid).length!==1 || JSON.stringify(display.frame)!==JSON.stringify(expected.frame) || JSON.stringify(display.gridGeometry)!==JSON.stringify(expected.gridGeometry))throw new Error('planned display/grid geometry changed; replan required');
  return display;
}
function spaceFor(snapshot,uuid,labels) {
  if(!uuid)throw new Error('planned Space UUID is missing; replan required');
  const space=snapshot.spaces.find(s=>s.uuid===uuid);
  if(!space || space.ignoredDisplay || snapshot.spaces.filter(s=>s.uuid===uuid).length!==1 || !labels.includes(space.label) || snapshot.spaces.filter(s=>s.label===space.label && space.label).length>1)throw new Error('planned Space identity/label changed; replan required');
  return space;
}
function focusAnchor(snapshot, space) {
  return { uuid: space.uuid, label: space.label, displayUuid: snapshot.displays.find(d => d.index === space.display)?.uuid };
}

function resolveFocusAnchor(snapshot, anchor) {
  const space = spaceFor(snapshot, anchor.uuid, [anchor.label]);
  const display = snapshot.displays.find(d => d.index === space.display);
  if (!anchor.displayUuid || display?.uuid !== anchor.displayUuid || display.ignored) {
    throw new Error('focus recovery Space changed displays; replan required');
  }
  return space;
}

async function focusForResize(snapshot, anchor, type, mutate) {
  const space = resolveFocusAnchor(snapshot, anchor);
  if (space.focused) return;
  await mutate(['-m', 'space', '--focus', String(space.index)], {
    type, spaceUuid: anchor.uuid, targetDisplayUuid: anchor.displayUuid, reversible: false
  }, after => {
    if (after.completeness !== 'complete') {
      throw Object.assign(new Error(`resize focus discovery incomplete: ${after.message}`), { code: 'SPACEWRIGHT_FOCUS_PENDING' });
    }
    const focused = resolveFocusAnchor(complete(after), anchor);
    if (!focused.focused || !focused.visible) {
      throw Object.assign(new Error('resize focus did not settle'), { code: 'SPACEWRIGHT_FOCUS_PENDING' });
    }
    return true;
  });
}

async function restoreResizeFocus(query, target, returnTo, mutate) {
  let previous = target;
  for (const anchor of returnTo) {
    const snapshot = complete(await query());
    // The user may have switched Spaces during the retry.
    if (!resolveFocusAnchor(snapshot, previous).focused) return;
    await focusForResize(snapshot, anchor, 'resize_focus_restore', mutate);
    previous = anchor;
  }
}

async function resizeWithFocusRetry({ before, resolve, apply, query, discover, mutate, retry, keepFocus }, allowFocusRetry) {
  try {
    await apply(before);
  } catch (error) {
    if (error.code !== 'SPACEWRIGHT_GEOMETRY_PENDING' || !allowFocusRetry || before.space.visible) throw error;
    const snapshot = await discover();
    const next = resolve(snapshot);
    const visible = snapshot.spaces.filter(s => s.display === next.space.display && s.visible);
    const focused = snapshot.spaces.filter(s => s.focused);
    if (next.space.visible || visible.length !== 1 || focused.length !== 1 || focused[0].ignoredDisplay) throw error;
    const target = focusAnchor(snapshot, next.space);
    const returnTo = [...new Map([...visible, ...focused].map(s => [s.uuid, focusAnchor(snapshot, s)])).values()];
    for (const anchor of returnTo) resolveFocusAnchor(snapshot, anchor);
    await retry();
    const fresh = await discover();
    resolve(fresh);
    if (!resolveFocusAnchor(fresh, returnTo.at(-1)).focused || !resolveFocusAnchor(fresh, returnTo[0]).visible) throw error;
    let completed = false;
    try {
      await focusForResize(fresh, target, 'resize_focus', mutate);
      const focusedTarget = resolve(await discover());
      if (!focusedTarget.space.focused || !focusedTarget.space.visible) throw error;
      await apply(focusedTarget);
      completed = true;
    } finally {
      if (!completed || !keepFocus) await restoreResizeFocus(query, target, returnTo, mutate);
    }
  }
}

export async function executePinnedWorkspace(plan,workspaceId,{discover,mutate,retryResize,createdSpaces={},registerCreated=async()=>{}}) {
  const query=discover;discover=async()=>validatePlanObjects(plan,await query());
  const byId=plan.workspaces.filter(w=>w.workspaceId===workspaceId);
  const matches=byId.length?byId:plan.workspaces.filter(w=>w.runtimeId===workspaceId);
  if(matches.length!==1)throw new Error('workspace outside fixed plan or runtime id is ambiguous');
  const workspace=matches[0];
  let uuid=workspace.targetSpace?.uuid || createdSpaces[workspace.workspaceId];
  let snapshot=complete(await discover());
  const display=displayFor(snapshot,workspace.targetDisplay);
  const creating=!uuid;
  if(creating) {
    if(!plan.actions.some(a=>a.type==='ensure_space' && a.workspaceId===workspace.workspaceId) || snapshot.spaces.some(s=>s.label===workspace.label))throw new Error('unplanned Space creation; replan required');
    const before=new Set(snapshot.spaces.map(s=>s.uuid));
    await mutate(['-m','space','--create',String(display.index)],{type:'ensure_space',workspaceId:workspace.workspaceId,targetDisplayUuid:display.uuid,reversible:false},s=>{const added=s.spaces.filter(x=>!before.has(x.uuid));return added.length===1 && added[0].display===display.index?{createdSpaceUuid:added[0].uuid,targetDisplayUuid:display.uuid}:false;});
    snapshot=complete(await discover());
    const added=snapshot.spaces.filter(s=>!before.has(s.uuid));
    if(added.length!==1 || added[0].display!==display.index)throw new Error('created Space is ambiguous; replan required');
    uuid=added[0].uuid;createdSpaces[workspace.workspaceId]=uuid;
    await registerCreated(createdSpaces);
    await mutate(['-m','space',String(added[0].index),'--label',workspace.label],{type:'label',workspaceId:workspace.workspaceId,spaceUuid:uuid,reversible:false},s=>s.spaces.find(x=>x.uuid===uuid)?.label===workspace.label);
  }
  const resolveSpace = current => spaceFor(current, uuid, [workspace.label, workspace.targetSpace?.label || '']);
  let initialSnapshot = creating ? null : snapshot;
  if(creating || plan.actions.some(a=>a.type==='set_space_layout' && a.workspaceId===workspace.workspaceId)) {
    const space = resolveSpace(initialSnapshot || complete(await discover()));
    const layout = workspace.spaceLayout || 'float';
    initialSnapshot = null;
    await mutate(['-m','space',String(space.index),'--layout',layout],{type:'set_space_layout',workspaceId:workspace.workspaceId,spaceUuid:uuid,layout,reversible:false},s=>s.spaces.find(x=>x.uuid===uuid)?.layout===layout);
  }
  for(const action of plan.actions.filter(a=>a.workspaceId===workspace.workspaceId)) {
    if(action.type==='recover_space_label' || action.type==='move_space') {
      const current = initialSnapshot || complete(await discover());
      const space = resolveSpace(current);
      initialSnapshot = null;
      const operation=action.type==='move_space'?'--display':'--label';
      const currentDisplay=displayFor(current,workspace.targetDisplay);
      const value=operation==='--display'?String(currentDisplay.index):workspace.label;
      await mutate(['-m','space',String(space.index),operation,value],{type:action.type,spaceUuid:uuid,workspaceId:workspace.workspaceId,reversible:false},s=>{const live=s.spaces.find(x=>x.uuid===uuid);return operation==='--display'?live?.display===currentDisplay.index:live?.label===value;});
    }
  }
  const selected=plan.selectedWindows.filter(w=>w.workspaceId===workspace.workspaceId);
  const keepResizeFocus = plan.scope === 'workspace'
    && plan.actions.some(action => action.type === 'focus_workspace' && action.workspaceId === workspace.workspaceId);
  for(const expected of selected) {
    const actions=plan.actions.filter(a=>a.windowId===expected.id && a.workspaceId===workspace.workspaceId);
    if(creating && !actions.some(a=>a.type==='move_window'))actions.unshift({type:'move_window'});
    for(const action of actions) {
      const snapshot = initialSnapshot || complete(await discover());
      initialSnapshot = null;
      const current = snapshot.windows.find(w => w.id === expected.id);
      if(!sameWindowIdentity(expected,current) || !selectorResult(current,{windowId:expected.id,appNames:[expected.app],selector:expected.selector}).matches)throw new Error('planned window identity/precondition changed; replan required');
      const space=spaceFor(snapshot,uuid,[workspace.label,workspace.targetSpace?.label || '']);
      const display=displayFor(snapshot,workspace.targetDisplay);
      const intent={type:action.type,windowId:expected.id,identity:expected,spaceUuid:uuid,targetDisplayUuid:display.uuid,recoveryCandidate:current,recoverySpaceUuid:snapshot.spaces.find(s=>s.index===current.space)?.uuid,reversible:true};
      if(action.type==='move_window') {
        await mutate(['-m','window',String(expected.id),'--space',String(space.index)],intent,s=>sameWindowIdentity(expected,s.windows.find(w=>w.id===expected.id)) && s.windows.find(w=>w.id===expected.id)?.space===s.spaces.find(x=>x.uuid===uuid)?.index);
      } else if(action.type==='resize_window') {
        const commands=action.grid?[['--grid',action.grid]]:Object.entries(action.geometry || {}).map(([key,value])=>key==='grid'?['--grid',value]:[key==='move_abs'?'--move':'--resize',`abs:${value.replace(/^abs:/,'')}`]);
        let beforeCommand = snapshot;
        for(const [op,value] of commands) {
          const resolve = snapshot => {
            const space = spaceFor(complete(snapshot), uuid, [workspace.label]);
            const display = displayFor(snapshot, workspace.targetDisplay);
            const window = snapshot.windows.find(w => w.id === expected.id);
            if (!sameWindowIdentity(expected, window) || window.space !== space.index || space.display !== display.index) {
              throw new Error('planned resize window or Space changed; replan required');
            }
            return { space, display, window };
          };
          const apply = ({window}) => mutate(['-m','window',String(expected.id),op,value],{
            ...intent, recoveryCandidate:window, recoverySpaceUuid:uuid, geometry:action.grid || action.geometry
          },s=>{
            const { window: live, display } = resolve(s);
            const result=geometryMatches(live,display,op==='--grid'?{grid:value}:op==='--move'?{move_abs:value}:{resize_abs:value});
            if(!result.matches)throw Object.assign(new Error(`window geometry postcondition failed for ${expected.app} (${expected.id}): expected ${JSON.stringify(result.expected)}, actual ${JSON.stringify(live.frame)}; check the application's minimum window size and configured layout region`),{code:'SPACEWRIGHT_GEOMETRY_PENDING'});
            return true;
          });
          await resizeWithFocusRetry({
            before:resolve(beforeCommand || await discover()), resolve, apply, query, discover, mutate,
            retry:retryResize, keepFocus:keepResizeFocus
          }, action.focusRetry === 'hidden_space_once' && Boolean(retryResize));
          beforeCommand = null;
        }
      }
    }
  }
  return createdSpaces;
}
export async function executePinnedCleanup(plan,{discover,mutate}) {
  const query=discover;discover=async()=>validatePlanObjects(plan,await query());
  for(const action of plan.actions.filter(a=>a.type==='remove_empty_space')) {
    const snapshot=complete(await discover());
    const space=spaceFor(snapshot,action.spaceUuid,[action.label]);
    const display=snapshot.displays.find(d=>d.uuid===action.displayUuid);
    if(!display || space.display!==display.index)throw new Error('cleanup display changed; replan required');
    if(snapshot.windows.some(w=>w.space===space.index && windowOccupiesSpace(w,plan.nonoccupyingGhostApps)))throw new Error('planned cleanup Space is occupied; retained');
    if(snapshot.spaces.filter(s=>s.display===space.display).length<=1)throw new Error('cleanup would remove the last surviving Space');
    await mutate(['-m','space',String(space.index),'--destroy'],{...action,reversible:false},s=>!s.spaces.some(x=>x.uuid===action.spaceUuid));
  }
}
export async function executePinnedOrder(plan,{discover,mutate,createdSpaces={}}) {
  const query=discover;discover=async()=>validatePlanObjects(plan,await query());
  if(!plan.actions.some(a=>a.type==='order_spaces'))return;
  const order=plan.actions.find(a=>a.type==='order_spaces');
  for(const displayUuid of new Set(plan.workspaces.map(w=>w.targetDisplay?.uuid).filter(Boolean))) {
    const workspaces=plan.workspaces.filter(w=>w.targetDisplay?.uuid===displayUuid && (w.targetSpace || createdSpaces[w.workspaceId]) && (!order.spaces || order.spaces.some(s=>s.workspaceId===w.workspaceId)));
    let previous=null;
    for(const workspace of workspaces) {
      const snapshot=complete(await discover()), display=displayFor(snapshot,workspace.targetDisplay);
      const uuid=workspace.targetSpace?.uuid || createdSpaces[workspace.workspaceId], space=spaceFor(snapshot,uuid,[workspace.label]);
      if(space.display!==display.index)throw new Error('order target display changed');
      if(previous) {
        const anchor=spaceFor(snapshot,previous,[...plan.workspaces.map(w=>w.label)]);
        if(space.index<anchor.index) {
          // Resolve both identities immediately before issue; never reuse an old index.
          await mutate(['-m','space',String(space.index),'--move',String(anchor.index)],{type:'order_spaces',spaceUuid:uuid,anchorUuid:previous,targetDisplayUuid:displayUuid,reversible:false},s=>s.spaces.find(x=>x.uuid===uuid)?.index>s.spaces.find(x=>x.uuid===previous)?.index);
        }
      }
      previous=uuid;
    }
  }
}
