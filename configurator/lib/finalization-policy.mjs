// Pure scope policy. Destruction always uses the full discovered occupancy,
// never the subset selected for layout.
import { remapTallLayout } from './config-v2.mjs';

export function assertWorkspaceSpaceContinuity(plan, snapshot, effects = []) {
  for (const workspace of plan.workspaces) {
    if (!workspace.targetSpace) {
      if (snapshot.spaces.some(s => s.label === workspace.label)
        && !effects.some(e => e.type === 'ensure_space' && e.workspaceId === workspace.workspaceId)) {
        throw new Error('target Space appeared after planning; replan required');
      }
      continue;
    }
    const uuid = workspace.targetSpace.uuid;
    if (!uuid) continue;
    const current = snapshot.spaces.find(s => s.uuid === uuid);
    // Inactive workspaces may be removed by this plan's cleanup phase. Only a
    // verified operation for the exact planned identity authorizes that absence.
    const removed = !current && !plan.selectedWindows.some(w => w.workspaceId === workspace.workspaceId)
      && plan.actions.some(a => a.type === 'remove_empty_space' && a.spaceUuid === uuid
        && a.label === workspace.targetSpace.label
        && effects.some(e => e.type === a.type && e.spaceUuid === uuid && e.label === a.label
          && e.displayUuid === a.displayUuid && e.status === 'verified_success' && e.postcondition === true));
    if (!removed && (!current || ![workspace.targetSpace.label, workspace.label].includes(current.label))) {
      throw new Error('planned Space disappeared or its label changed; replan required');
    }
  }
}

export function variantLabels(config, ids, mode) {
  const claims = Object.entries(config.workspaces).flatMap(([id,w]) => Object.entries(w.variants).map(([variant,v]) => ({workspaceId:id,mode:variant,label:v.spaceLabel || `${w.spaceLabel}_${variant}`})));
  const opposite=claims.filter(c=>ids.includes(c.workspaceId) && c.mode!==mode && !claims.some(t=>ids.includes(t.workspaceId) && t.mode===mode && t.label===c.label))
    .map(c=>({...c,conflict:claims.some(other=>other.label===c.label && other.workspaceId!==c.workspaceId)}));
  return [...new Map(opposite.map(c=>[`${c.workspaceId}:${c.label}`,c])).values()];
}
export function cleanupCandidates(snapshot, desired,activeIds=new Set(desired.workspaces.map(w=>w.workspaceId))) {
  const drifts=[];
  if (snapshot.completeness!=='complete') return drifts;
  const claims=[...(desired.oppositeVariants || []),...desired.workspaces.filter(w=>!activeIds.has(w.workspaceId)).map(w=>({workspaceId:w.workspaceId,label:w.label,conflict:new Set(desired.labelOwners?.[w.label] || [w.workspaceId]).size>1}))];
  for (const claim of claims) {
    const spaces=snapshot.spaces.filter(s=>s.label===claim.label);
    if (claim.conflict || spaces.length>1) { drifts.push({code:'opposite_label_conflict',severity:'blocker',workspaceId:claim.workspaceId,label:claim.label}); continue; }
    for (const space of spaces) {
      if(!space.uuid){drifts.push({code:'cleanup_space_identity_missing',severity:'blocker',workspaceId:claim.workspaceId,label:claim.label});continue;}
      const occupied=snapshot.windows.some(w=>w.space===space.index && windowOccupiesSpace(w,desired.nonoccupyingGhostApps));
      const survivor=snapshot.spaces.some(s=>s.display===space.display && s.uuid!==space.uuid && !claims.some(c=>c.label===s.label));
      if (occupied || !survivor) {drifts.push({code:'opposite_space_retained',severity:'warning',workspaceId:claim.workspaceId,spaceUuid:space.uuid,reason:occupied?'occupied':'last_survivor'});continue;}
      drifts.push({code:'empty_space_cleanup_required',severity:'change',spaceUuid:space.uuid,display:space.display,displayUuid:snapshot.displays.find(d=>d.index===space.display)?.uuid,label:space.label,cleanupScope:desired.target.kind==='workspace'?'workspace':'mode'});
    }
  }
  return drifts;
}
export function sandboxWorkspace(snapshot, desired, runtime, selectedIds) {
  const claimed=(window)=>Object.values(runtime.workspaces || {}).some(w=>w.label===snapshot.spaces.find(s=>s.index===window.space)?.label && (w.windows || []).some(r=>runtime.apps?.[r.app_key]?.names?.includes(window.app)));
  const windows=snapshot.windows.filter(w=>!selectedIds.has(w.id) && !claimed(w) && w.movable && w.resizable && !w.sticky && !w.minimized && !w.nativeFullscreen).sort((a,b)=>a.id-b.id);
  if (!windows.length) return null;
  const displayRole=desired.target.mode==='solo'?'primary':desired.workspaces.find(w=>w.displayRole!=='primary')?.displayRole || desired.workspaces[0]?.displayRole;
  const display=snapshot.displays.find(d=>d.role===displayRole);
  // Two side-by-side windows on a portrait display can fall below app minimum
  // widths. Stack them in the two physical panels, retaining the Tall split.
  const columns=windows.length===2 && display?.frame.h>display?.frame.w ? 1 : Math.ceil(Math.sqrt(windows.length));
  const rows=Math.ceil(windows.length/columns);
  const layout=windows.map((w,i)=>({role:`window_${w.id}`,grid:`${rows}:${columns}:${i%columns}:${Math.floor(i/columns)}:1:1`}));
  return {workspaceId:'__sandbox',runtimeId:'__sandbox',runner:'generic_layout',mode:desired.target.mode,name:'Sandbox',label:`sandbox_${desired.target.mode}`,displayRole,activation:{type:'always'},
    windows:windows.map(w=>({role:`window_${w.id}`,appKey:`sandbox_${w.id}`,appNames:[w.app],bundleIds:w.bundleId?[w.bundleId]:[],required:true,ownership:'independent',cardinality:'one',windowId:w.id,selector:{movable:true}})),
    layout:desired.target.mode==='tall' ? remapTallLayout(layout,runtime.settings?.tallTopPercent ?? 50) : layout};
}

export function windowOccupiesSpace(window, knownGhostApps = []) {
  if (window.sticky) return false;
  const emptyNonmovableShell = !window.title && !window.role && !window.subrole && !window.movable;
  if (emptyNonmovableShell && window.frameVerified === false && knownGhostApps.includes(window.app)) return false;
  // Some applications leave an invisible root surface behind after their last
  // interactive window closes.  Requiring every negative signal keeps this
  // generic rule narrower than the reviewed per-application compatibility list.
  const headlessRootSurface = emptyNonmovableShell
    && !window.resizable
    && !window.visible
    && !window.hasAxReference
    && window.frameVerified === false;
  return !headlessRootSurface;
}
