import {compileV2, validateV2} from './config-v2.mjs';
import {buildDesiredState, compareState} from './state-engine.mjs';
import {selectRole} from './window-policy.mjs';

const reject = message => { throw Object.assign(new Error(message),{code:'capture_merge_conflict'}); };

// Verify against the original local snapshot. No current geometry or unrelated
// workspace drift is required to converge before accepting an editor draft.
export function mergeCapturedWorkspace(config, capture, snapshot, machine) {
  if(config?.version !== 2) reject('Capture merge currently supports the v2 editor only.');
  const next=structuredClone(config), draft=structuredClone(capture.draft), appMap={};
  if(next.workspaces[draft.workspaceId]) reject(`Workspace ID “${draft.workspaceId}” already exists.`);
  for(const [id,app] of Object.entries(draft.apps)) {
    const existing=Object.entries(next.apps).find(([,candidate])=>(candidate.match?.appNames || []).some(name=>app.match.appNames.includes(name)));
    if(existing) { appMap[id]=existing[0]; continue; }
    let key=id, suffix=2; while(next.apps[key])key=`${id}_${suffix++}`;
    next.apps[key]=app;appMap[id]=key;
  }
  for(const role of Object.values(draft.workspace.windows))role.app=appMap[role.app];
  next.workspaces[draft.workspaceId]=draft.workspace;
  const mode=capture.capturedFrom.mode;
  const displayRole=Object.entries(machine.displayBindings || {}).find(([,uuid])=>uuid===capture.capturedFrom.displayUuid)?.[0];
  const lane=next.modes?.[mode]?.displays.find(lane=>lane.role===displayRole);
  if(!lane)reject('Bind the captured display and add its lane to this mode before merging.');
  lane.workspaceOrder.push(draft.workspaceId);
  const validation=validateV2(next);
  if(!validation.valid)reject(`Captured draft is invalid: ${validation.errors.join('; ')}`);
  const desired=buildDesiredState(next,compileV2(next),{kind:'mode',id:mode,mode},snapshot);
  const comparison=compareState(snapshot,desired,machine);
  const captured=desired.workspaces.find(w=>w.workspaceId===draft.workspaceId);
  const used=new Set();
  for(const expected of capture.matching) {
    const role=captured.windows.find(r=>r.role===expected.role);
    const result=selectRole(snapshot.windows,role);
    const match=comparison.matches.find(m=>m.workspaceId===draft.workspaceId && m.role===expected.role);
    if(result.eligible.length!==1 || result.selected[0]?.id!==expected.windowId || used.has(expected.windowId)
      || JSON.stringify(match?.selectedWindowIds)!==JSON.stringify([expected.windowId]))reject(`Alias or ownership conflict for captured role “${expected.role}”; review app aliases and existing workspace ownership.`);
    used.add(expected.windowId);
  }
  const beforeDesired=buildDesiredState(config,compileV2(config),{kind:'mode',id:mode,mode},snapshot);
  const before=compareState(snapshot,beforeDesired,machine);
  const capturedApps=new Set(captured.windows.map(r=>r.appKey));
  for(const workspace of beforeDesired.workspaces)for(const role of workspace.windows.filter(r=>capturedApps.has(r.appKey))) {
    const old=before.matches.find(m=>m.workspaceId===workspace.workspaceId && m.role===role.role);
    const updated=comparison.matches.find(m=>m.workspaceId===workspace.workspaceId && m.role===role.role);
    const identity=m=>JSON.stringify({selected:m?.selectedWindowIds || [],owner:m?.supersededByWorkspaceId || null});
    if(identity(old)!==identity(updated))reject(`Capture would change ownership in existing workspace “${workspace.workspaceId}”, role “${role.role}”. Review workspace ownership before capturing.`);
  }
  if(comparison.drifts.some(d=>d.severity==='blocker' && (d.workspaceId===draft.workspaceId || d.workspaceIds?.includes(draft.workspaceId))))reject('Captured workspace has a display, label or ownership conflict.');
  return {config:next,workspaceId:draft.workspaceId,displayRole,assigned:true,matching:capture.matching,warnings:capture.warnings};
}
