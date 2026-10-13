export function sameWindowIdentity(expected, current) {
  return Boolean(current && expected.id === current.id && expected.app === current.app
    && expected.pid === current.pid && (expected.bundleId || '') === (current.bundleId || '')
    && (expected.processFingerprint || null) === (current.processFingerprint || null));
}
export function recoveryCandidates(journal) {
  const candidates=new Map();
  for(const operation of journal.effects || []) {
    if(!operation.windowId || operation.status==='not_attempted' || operation.reversible===false)continue;
    const original=journal.before?.windows.find(w=>w.id===operation.windowId), observed=operation.recoveryCandidate;
    const window=original && (!observed || sameWindowIdentity(original,observed))?original:observed;
    if(!window || candidates.has(window.id))continue;
    const spaceUuid=window===original?journal.before.spaces.find(s=>s.index===window.space)?.uuid:operation.recoverySpaceUuid;
    candidates.set(window.id,{window,spaceUuid});
  }
  return [...candidates.values()];
}
export function recoveryTarget(window, spaceUuid, snapshot) {
  if (snapshot.completeness !== 'complete') throw new Error(snapshot.message || 'recovery discovery is incomplete');
  const current = snapshot.windows.find((w) => w.id === window.id);
  if (!sameWindowIdentity(window, current)) throw Object.assign(new Error(current ? 'window identity changed' : 'window no longer exists'), {code:'SPACEWRIGHT_RECOVERY_SKIP'});
  const space = snapshot.spaces.find((s) => s.uuid === spaceUuid);
  if (!space) throw Object.assign(new Error('original Space no longer exists'), {code:'SPACEWRIGHT_RECOVERY_SKIP'});
  return {current,space};
}
export async function restoreWindow(window, spaceUuid, {discover, run, beforeCommand = async () => {},afterCommand=async()=>{}}) {
  const commands = [['--space', null]];
  if (window.movable) commands.push(['--move', `abs:${Math.round(window.frame.x)}:${Math.round(window.frame.y)}`]);
  if (window.resizable) commands.push(['--resize', `abs:${Math.round(window.frame.w)}:${Math.round(window.frame.h)}`]);
  const attempted = [];
  try {
    for (const [operation, value] of commands) {
      const {space} = recoveryTarget(window, spaceUuid, await discover());
      const args = ['-m','window',String(window.id),operation,value ?? String(space.index)];
      await beforeCommand(args);
      attempted.push(args);
      await run('yabai',args);
      const {current,space:resolved}=recoveryTarget(window,spaceUuid,await discover());
      const expected=operation==='--space'?{space:resolved.index}:operation==='--move'?{x:Math.round(window.frame.x),y:Math.round(window.frame.y)}:{w:Math.round(window.frame.w),h:Math.round(window.frame.h)};
      const matches=Object.entries(expected).every(([k,v])=>k==='space'?current.space===v:Math.abs(current.frame[k]-v)<=2);
      await afterCommand(args,matches);
      if(!matches)throw new Error('restore command postcondition failed');
    }
    const {current,space} = recoveryTarget(window,spaceUuid,await discover());
    if (current.space !== space.index || Object.keys(window.frame).some((key) => Math.abs(current.frame[key]-window.frame[key])>2)) throw new Error('restore postcondition failed');
    return {status:'completed',windowId:window.id,attempted};
  } catch (error) { error.attempted = attempted; throw error; }
}
