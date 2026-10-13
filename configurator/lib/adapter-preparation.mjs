import { selectRole } from './window-policy.mjs';
import { sameWindowIdentity } from './recovery.mjs';
const complexRunners=new Set(['office_document','gtd_support','primary_helper','gtd_review','gtd_meeting','gtd_ai','fixed_adapter']);
const identity=w=>({id:w.id,app:w.app,pid:w.pid,bundleId:w.bundleId,processFingerprint:w.processFingerprint});
export function preparationsFor(snapshot,desired) {
  const owners=new Map();for(const ws of desired.workspaces)for(const role of ws.windows)if(role.ownership!=='independent')owners.set(role.appKey,ws.workspaceId);
  for(const rule of desired.contextualApps || [])owners.set(rule.appKey,rule.ownerWorkspaceId);
  const preparations=[],seen=new Set();
  for(const workspace of desired.workspaces)for(const role of workspace.windows) {
    if(role.ownership!=='independent' && owners.get(role.appKey)!==workspace.workspaceId)continue;
    const selectable={...role,allowNativeFullscreen:true,selector:{...role.selector,movable:false,visible:false}};
    const {selected,ambiguous}=selectRole(snapshot.windows,selectable);
    if(ambiguous)continue;
    for(const window of selected) {
      const type=window.nativeFullscreen?'native_fullscreen':complexRunners.has(workspace.runner) && (!window.movable || role.selector.visible && !window.visible)?'refresh_app':null;
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
  if(!sameWindowIdentity(preparation.window,before.windows.find(w=>w.id===preparation.window.id)))throw new Error('adapter input identity changed; replan required');
  if(preparation.type==='native_fullscreen')return ['yabai',['-m','window',String(preparation.window.id),'--toggle','native-fullscreen']];
  if(preparation.commandPolicy==='outlook_reopen')return ['osascript',['-e','on run argv','-e','tell application (item 1 of argv) to activate','-e','tell application (item 1 of argv) to reopen','-e','end run',preparation.window.app]];
  return ['open',['-a',preparation.window.app]];
}
export async function verifyPreparation(preparation,{discover,poll,check=()=>{},delay=ms=>new Promise(r=>setTimeout(r,ms))}) {
  for(let attempt=0;attempt<12;attempt++) {
    check();if(attempt){await poll();await delay(250);check();}
    const after=await discover();
    if(after.completeness!=='complete')throw new Error('adapter rediscovery incomplete');
    const selection=selectRole(after.windows,preparation.selection);
    if(!selection.ambiguous && selection.selected.length) return {before:identity(preparation.window),after:selection.selected.map(identity),requiresReplan:true};
  }
  throw new Error('adapter completed without an effective selectable window');
}
export async function executePreparation(preparation,{discover,command,...dependencies}) {
  const check=dependencies.check || (()=>{});
  check();const before=await discover();
  const args=preparationCommand(preparation,before);
  await command(...args);
  return verifyPreparation(preparation,{discover,...dependencies});
}
