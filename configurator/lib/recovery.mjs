export function sameWindowIdentity(expected, current) {
  return Boolean(current && expected.id === current.id && expected.app === current.app
    && expected.pid === current.pid && (expected.bundleId || '') === (current.bundleId || '')
    && (!expected.processFingerprint || expected.processFingerprint === current.processFingerprint));
}
export function recoveryTarget(window, spaceUuid, snapshot) {
  if (snapshot.completeness !== 'complete') throw new Error(snapshot.message || 'recovery discovery is incomplete');
  const current = snapshot.windows.find((w) => w.id === window.id);
  if (!sameWindowIdentity(window, current)) throw Object.assign(new Error(current ? 'window identity changed' : 'window no longer exists'), {code:'SPACEWRIGHT_RECOVERY_SKIP'});
  const space = snapshot.spaces.find((s) => s.uuid === spaceUuid);
  if (!space) throw Object.assign(new Error('original Space no longer exists'), {code:'SPACEWRIGHT_RECOVERY_SKIP'});
  return {current,space};
}
export async function restoreWindow(window, spaceUuid, {discover, run, beforeCommand = async () => {}}) {
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
    }
    const {current,space} = recoveryTarget(window,spaceUuid,await discover());
    if (current.space !== space.index || Object.keys(window.frame).some((key) => Math.abs(current.frame[key]-window.frame[key])>2)) throw new Error('restore postcondition failed');
    return {status:'completed',windowId:window.id,attempted};
  } catch (error) { error.attempted = attempted; throw error; }
}
