import { selectRole } from './window-policy.mjs';
import { sameWindowIdentity } from './recovery.mjs';
const complexRunners=new Set(['office_document','gtd_support','primary_helper','gtd_review','gtd_meeting','gtd_ai','fixed_adapter']);
const identity=w=>({id:w.id,app:w.app,pid:w.pid,bundleId:w.bundleId,processFingerprint:w.processFingerprint});
export const AX_UNAVAILABLE_EXIT = 76;
export function axReferenceError(preparation) {
  const windows = preparation.windows.map(w => `${w.app} (${w.id})`).join(', ');
  return Object.assign(new Error(`yabai window references unavailable after Space observation: ${windows}. A bounded service recovery is required before layout; use spacewright repair-yabai if automatic recovery cannot complete.`), { code: 'SPACEWRIGHT_AX_UNAVAILABLE' });
}
function spaceObservations(snapshot,desired) {
  const spaces=new Map();
  for(const workspace of desired.workspaces)for(const role of workspace.windows) {
    // A one-window role with a unique selectable object needs no recovery of
    // other, AX-less surfaces from that app. Keep those surfaces in discovery
    // and occupancy checks, but do not let them block the selected window.
    const selection=selectRole(snapshot.windows,role);
    if(role.cardinality!=='many' && !selection.ambiguous && selection.selected.length
      && selection.selected.every(w=>w.hasAxReference!==false))continue;
    for(const window of snapshot.windows) {
      // Without an AX reference, titles, roles and capabilities are unknown,
      // not evidence that an observed app window is absent or unlayoutable.
      if(role.windowId!=null && role.windowId!==window.id)continue;
      if(window.hasAxReference!==false || !role.appNames.includes(window.app) || window.minimized || window.sticky
        || !window.frameVerified || window.frame.w<=0 || window.frame.h<=0)continue;
      const space=snapshot.spaces.find(s=>s.index===window.space);
      if(!space)continue;
      let preparation=spaces.get(space.uuid);
      if(!preparation) {
        preparation={type:'observe_space',workspaceId:workspace.workspaceId,role:role.role,window:identity(window),windows:[],roles:[],spaceUuid:space.uuid,
          displayUuid:snapshot.displays.find(d=>d.index===space.display)?.uuid,
          departureSpaceUuid:snapshot.spaces.find(s=>s.display===space.display && s.uuid!==space.uuid)?.uuid,
          returnSpaceUuid:snapshot.spaces.find(s=>s.focused)?.uuid,
          sideEffects:['focus_space','restore_focus'],phaseLimitMs:8000,budget:'confirmation',requiresReplan:true,
          fallback:{type:'restart_yabai',maxAttempts:1,budget:'serviceRecovery',sideEffects:['restart_yabai','restore_space_labels_and_settings','rediscover_and_replan']}};
        spaces.set(space.uuid,preparation);
      }
      if(!preparation.windows.some(w=>w.id===window.id))preparation.windows.push(identity(window));
      if(!preparation.roles.some(r=>r.workspaceId===workspace.workspaceId && r.role===role.role))preparation.roles.push({workspaceId:workspace.workspaceId,role:role.role});
    }
  }
  return [...spaces.values()];
}
export function preparationsFor(snapshot,desired) {
  const owners=new Map();for(const ws of desired.workspaces)for(const role of ws.windows)if(role.ownership!=='independent')owners.set(role.appKey,ws.workspaceId);
  for(const rule of desired.contextualApps || [])owners.set(rule.appKey,rule.ownerWorkspaceId);
  const observations=spaceObservations(snapshot,desired);
  const preparations=[...observations],seen=new Set();
  for(const workspace of desired.workspaces)for(const role of workspace.windows) {
    if(role.ownership!=='independent' && owners.get(role.appKey)!==workspace.workspaceId)continue;
    const selectable={...role,allowNativeFullscreen:true,selector:{...role.selector,movable:false,resizable:false,visible:false}};
    const {selected,ambiguous}=selectRole(snapshot.windows,selectable);
    if(ambiguous)continue;
    for(const window of selected) {
      if(window.hasAxReference===false)continue; // Observe its Space before app recovery.
      const type=window.nativeFullscreen?'native_fullscreen':complexRunners.has(workspace.runner) && (!window.movable || role.selector.visible && !window.visible)?'refresh_app':null;
      // Optional roles must remain optional even when yabai exposes a stale,
      // unselectable app surface. Preparing that surface would otherwise turn
      // an optional_window_missing warning into a mode-wide hard failure.
      if(type && !role.required)continue;
      if(!type || seen.has(`${type}:${window.app}:${type==='native_fullscreen'?window.id:''}`))continue;
      seen.add(`${type}:${window.app}:${type==='native_fullscreen'?window.id:''}`);
      preparations.push({type,workspaceId:workspace.workspaceId,role:role.role,adapter:workspace.runner,commandPolicy:role.appKey==='outlook' && type==='refresh_app'?'outlook_reopen':type,window:identity(window),selection:role,
        sideEffects:type==='native_fullscreen'?['exit_native_fullscreen','possible_window_replacement']:['activate_app','possible_window_creation_or_replacement'],
        phaseLimitMs:8000,budget:'appRecovery',requiresReplan:true});
    }
  }
  return preparations;
}
export function preparationCommand(preparation,before) {
  if(before.completeness!=='complete')throw new Error('adapter discovery incomplete');
  if(preparation.type==='observe_space') {
    const space=before.spaces.find(s=>s.uuid===preparation.spaceUuid);
    if(!space || before.displays.find(d=>d.index===space.display)?.uuid!==preparation.displayUuid)throw new Error('observation Space changed; replan required');
    for(const expected of preparation.windows) {
      const current=before.windows.find(w=>w.id===expected.id);
      if(!sameWindowIdentity(expected,current) || current.space!==space.index)throw new Error('observation window changed; replan required');
    }
    return ['yabai',['-m','space','--focus',String(space.index)]];
  }
  if(!sameWindowIdentity(preparation.window,before.windows.find(w=>w.id===preparation.window.id)))throw new Error('adapter input identity changed; replan required');
  if(preparation.type==='native_fullscreen')return ['yabai',['-m','window',String(preparation.window.id),'--toggle','native-fullscreen']];
  if(preparation.commandPolicy==='outlook_reopen')return ['osascript',['-e','on run argv','-e','tell application (item 1 of argv) to activate','-e','tell application (item 1 of argv) to reopen','-e','end run',preparation.window.app]];
  return ['open',['-a',preparation.window.app]];
}
export function preparationDepartureCommand(preparation,before) {
  if(preparation.type!=='observe_space')return null;
  preparationCommand(preparation,before); // Validate every identity before focus changes.
  const target=before.spaces.find(s=>s.uuid===preparation.spaceUuid);
  if(!target.focused)return null;
  const departure=before.spaces.find(s=>s.uuid===preparation.departureSpaceUuid && s.display===target.display);
  if(!departure)throw new Error('AX observation needs another Space to leave and revisit the focused Space');
  return ['yabai',['-m','space','--focus',String(departure.index)]];
}
export async function verifyPreparation(preparation,{discover,poll,check=()=>{},delay=ms=>new Promise(r=>setTimeout(r,ms))}) {
  let sawComplete=false,lastIncomplete=null;
  for(let attempt=0;attempt<12;attempt++) {
    check();if(attempt){await poll();await delay(250);check();}
    const after=await discover();
    if(after.completeness!=='complete') {lastIncomplete=after;continue;}
    sawComplete=true;
    if(preparation.type==='observe_space') {
      const space=after.spaces.find(s=>s.uuid===preparation.spaceUuid);
      if(!space || after.displays.find(d=>d.index===space.display)?.uuid!==preparation.displayUuid)throw new Error('observation Space changed; replan required');
      const windows=preparation.windows.map(expected=>{
        const current=after.windows.find(w=>w.id===expected.id);
        if(!sameWindowIdentity(expected,current) || current.space!==space.index)throw new Error('observation window changed; replan required');
        return current;
      });
      if(space.focused && windows.every(w=>w.hasAxReference))return {before:preparation.windows,after:windows.map(identity),requiresReplan:true};
      continue;
    }
    const selection=selectRole(after.windows,preparation.selection);
    if(!selection.ambiguous && selection.selected.length) return {before:identity(preparation.window),after:selection.selected.map(identity),requiresReplan:true};
  }
  if(!sawComplete)throw new Error(lastIncomplete?.message || 'adapter rediscovery incomplete');
  if (preparation.type === 'observe_space') throw axReferenceError(preparation);
  throw new Error('adapter completed without an effective selectable window');
}
export async function executePreparation(preparation,{discover,command,...dependencies}) {
  const check=dependencies.check || (()=>{});
  check();const before=await discover();
  const departure=preparationDepartureCommand(preparation,before);
  if(departure)await command(...departure);
  const args=preparationCommand(preparation,before);
  await command(...args);
  return verifyPreparation(preparation,{discover,...dependencies});
}
