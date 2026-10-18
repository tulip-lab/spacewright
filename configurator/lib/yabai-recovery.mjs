import { sameWindowIdentity } from './recovery.mjs';
import { executionCensus } from './window-policy.mjs';

const settingNames = ['top_padding', 'bottom_padding', 'left_padding', 'right_padding', 'window_gap'];
const sorted = values => [...values].sort();
const equal = (a, b) => JSON.stringify(a) === JSON.stringify(b);

function complete(snapshot) {
  if (snapshot.completeness !== 'complete') throw new Error('yabai recovery requires complete discovery');
  if (!snapshot.displays.length || !snapshot.spaces.length) throw new Error('yabai recovery requires displays and Spaces');
  const age = Date.now() - new Date(snapshot.capturedAt).getTime();
  if (!Number.isFinite(age) || age < 0 || age > 15000) throw new Error('yabai recovery discovery expired');
  for (const collection of [snapshot.displays, snapshot.spaces]) {
    if (collection.some(item => !item.uuid) || new Set(collection.map(item => item.uuid)).size !== collection.length
      || new Set(collection.map(item => item.index)).size !== collection.length) throw new Error('yabai recovery identities are ambiguous');
  }
  return snapshot;
}

export function recoveryPreview(snapshot) {
  complete(snapshot);
  // Restarting a bsp/stack service loses its tree. Do not pretend labels alone
  // can restore that desktop. SpaceWright's supported recovery is float-only.
  if (snapshot.spaces.some(s => s.layout !== 'float') || snapshot.windows.some(w => w.nativeFullscreen)) {
    throw new Error('safe yabai recovery requires float Spaces without native fullscreen windows; layout was not attempted');
  }
  const labels = snapshot.spaces.map(s => s.label).filter(Boolean);
  if (new Set(labels).size !== labels.length) throw new Error('yabai recovery refuses duplicate Space labels');
  return { dryRun: true, mutates: false, action: 'restart_yabai', maxAttempts: 1,
    spaces: snapshot.spaces.map(s => ({ uuid: s.uuid, label: s.label,
      displayUuid: snapshot.displays.find(d => d.index === s.display)?.uuid })),
    preserves: ['space_labels', 'space_padding', 'window_gap', 'external_bar', 'focused_space'],
    sideEffects: ['restart_yabai', 'reload_yabairc', 'rediscover_and_replan'] };
}

export function assertServiceRecoveryInput(expected, current) {
  complete(current);
  const displays = snapshot => snapshot.displays.map(({uuid,frame})=>({uuid,frame})).sort((a,b)=>a.uuid.localeCompare(b.uuid));
  const spaces = snapshot => snapshot.spaces.map(s=>({uuid:s.uuid,label:s.label,
    displayUuid:snapshot.displays.find(d=>d.index===s.display)?.uuid})).sort((a,b)=>a.uuid.localeCompare(b.uuid));
  if (!equal(displays(expected),displays(current)) || !equal(spaces(expected),spaces(current))) throw new Error('desktop identities changed before yabai recovery; replan required');
  const before=executionCensus(expected.windows), after=executionCensus(current.windows,before);
  if (before.length!==after.length || before.some(saved=>{
    const live=after.find(w=>w.id===saved.id);
    return !sameWindowIdentity(saved,live)
      || expected.spaces.find(s=>s.index===saved.space)?.uuid!==current.spaces.find(s=>s.index===live.space)?.uuid;
  })) throw new Error('window identities or ownership changed before yabai recovery; replan required');
}

export function assertRecoveryContinuity(checkpoint, snapshot) {
  complete(snapshot);
  if (checkpoint.schemaVersion !== 1 || !Array.isArray(checkpoint.displays) || !Array.isArray(checkpoint.spaces)
    || !Array.isArray(checkpoint.windows) || !checkpoint.settings) throw new Error('invalid yabai recovery checkpoint');
  if (!/^(off|main|all):\d+:\d+$/.test(checkpoint.externalBar)
    || checkpoint.spaces.some(s => typeof s.label !== 'string' || !s.displayUuid
      || settingNames.some(name => typeof checkpoint.settings[s.uuid]?.[name] !== 'string' || !/^\d+$/.test(checkpoint.settings[s.uuid][name])))) {
    throw new Error('invalid saved Space settings');
  }
  const displays = value => value.map(d => ({ uuid: d.uuid, frame: d.frame })).sort((a, b) => a.uuid.localeCompare(b.uuid));
  if (!equal(displays(checkpoint.displays), displays(snapshot.displays))) throw new Error('displays changed during yabai recovery; restore stopped');
  if (!equal(sorted(checkpoint.spaces.map(s => s.uuid)), sorted(snapshot.spaces.map(s => s.uuid)))) throw new Error('Space identities changed during yabai recovery; restore stopped');
  for (const saved of checkpoint.spaces) {
    const current = snapshot.spaces.find(s => s.uuid === saved.uuid);
    if (snapshot.displays.find(d => d.index === current.display)?.uuid !== saved.displayUuid
      || current.layout !== 'float' || current.label && current.label !== saved.label) throw new Error('Space ownership or label changed during yabai recovery; restore stopped');
  }
  const windows = executionCensus(snapshot.windows, checkpoint.windows);
  // Restarting yabai can discover additional app windows. Restoring Space
  // metadata does not move them; the caller rediscovers and replans afterward.
  // Every saved window must still retain its identity and Space ownership.
  if (checkpoint.windows.some(saved => {
    const current = windows.find(w => w.id === saved.id);
    return !sameWindowIdentity(saved, current) || snapshot.spaces.find(s => s.index === current.space)?.uuid !== saved.spaceUuid;
  })) throw new Error('window identities or ownership changed during yabai recovery; layout was not attempted');
  if (snapshot.windows.some(w => w.nativeFullscreen)) throw new Error('native fullscreen appeared during yabai recovery');
  return snapshot;
}

// All commands, writes and waits are supplied by the lease-owning caller. This
// module never bypasses cancellation, total deadlines or the operation journal.
export async function recoverYabai({ discover, query, mutate, persist, check, consume, resume, expectedSnapshot,
  delay = ms => new Promise(resolve => setTimeout(resolve, ms)) }) {
  let checkpoint = resume;
  const checkedDiscovery = async () => { await check(); const value = await discover(); await check(); return value; };
  if (!checkpoint) {
    const before = await checkedDiscovery();
    recoveryPreview(before);
    if (expectedSnapshot) assertServiceRecoveryInput(expectedSnapshot,before);
    const settings = {};
    for (const space of before.spaces) {
      settings[space.uuid] = {};
      for (const name of settingNames) {
        await check();
        const value = (await query(['-m', 'config', '--space', String(space.index), name])).trim();
        if (!/^\d+$/.test(value)) throw new Error(`cannot preserve ${name}; yabai recovery was not started`);
        settings[space.uuid][name] = value;
      }
    }
    const externalBar = (await query(['-m', 'config', 'external_bar'])).trim();
    if (!/^(off|main|all):\d+:\d+$/.test(externalBar)) throw new Error('cannot preserve external_bar; yabai recovery was not started');
    checkpoint = { schemaVersion: 1, status: 'saved', createdAt: new Date().toISOString(),
      displays: before.displays.map(({uuid, frame}) => ({uuid, frame})),
      spaces: before.spaces.map(s => ({ uuid: s.uuid, index: s.index, label: s.label,
        displayUuid: before.displays.find(d => d.index === s.display)?.uuid })),
      windows: executionCensus(before.windows).map(w => ({ id: w.id, pid: w.pid, app: w.app, bundleId: w.bundleId,
        processFingerprint: w.processFingerprint, spaceUuid: before.spaces.find(s => s.index === w.space)?.uuid })),
      focusedSpaceUuid: before.spaces.find(s => s.focused)?.uuid, settings, externalBar };
    // Persist before consuming the restart budget or touching the service.
    await persist(checkpoint);
    const fresh = await checkedDiscovery();
    if (expectedSnapshot) assertServiceRecoveryInput(expectedSnapshot,fresh);
    assertRecoveryContinuity(checkpoint, fresh);
    if (checkpoint.spaces.some(s => {
      const current = fresh.spaces.find(c => c.uuid === s.uuid);
      return current.label !== s.label || current.index !== s.index;
    })) throw new Error('Space labels or indexes changed before yabai recovery');
    await consume('serviceRecovery');
    await check();
    checkpoint.status = 'restart_attempted'; await persist(checkpoint);
    await mutate(['--restart-service'], { type: 'restart_yabai', reversible: false }, async () => {
      for (let attempt = 0; attempt < 40; attempt++) {
        const snapshot = await checkedDiscovery();
        if (snapshot.completeness === 'complete') { assertRecoveryContinuity(checkpoint, snapshot); return true; }
        await consume('confirmation'); await delay(100);
      }
      throw new Error('yabai did not become available after restart; resume the saved recovery checkpoint');
    });
  }
  if (!['saved', 'restart_attempted', 'restoring', 'completed'].includes(checkpoint.status)) throw new Error('invalid yabai recovery checkpoint status');
  assertRecoveryContinuity(checkpoint, await checkedDiscovery());
  checkpoint.status = 'restoring'; await persist(checkpoint);
  for (const saved of checkpoint.spaces) {
    let snapshot = assertRecoveryContinuity(checkpoint, await checkedDiscovery());
    let space = snapshot.spaces.find(s => s.uuid === saved.uuid);
    if (space.label !== saved.label) {
      await mutate(['-m', 'space', String(space.index), '--label', saved.label],
        {type:'restore_space_label', spaceUuid:saved.uuid, label:saved.label, reversible:false},
        async () => (await checkedDiscovery()).spaces.find(s => s.uuid === saved.uuid)?.label === saved.label);
    }
    for (const name of settingNames) {
      const value = checkpoint.settings[saved.uuid]?.[name];
      if (typeof value !== 'string' || !/^\d+$/.test(value)) throw new Error('invalid saved Space settings');
      let args = ['-m', 'config', '--space', String(space.index), name];
      if ((await query(args)).trim() === value) continue;
      snapshot = assertRecoveryContinuity(checkpoint, await checkedDiscovery());
      space = snapshot.spaces.find(s => s.uuid === saved.uuid);
      args = ['-m', 'config', '--space', String(space.index), name];
      await mutate([...args, value], {type:'restore_space_setting', spaceUuid:saved.uuid, name, value, reversible:false},
        async () => {
          const fresh = assertRecoveryContinuity(checkpoint, await checkedDiscovery());
          return (await query(['-m','config','--space',String(fresh.spaces.find(s=>s.uuid===saved.uuid).index),name])).trim() === value;
        });
    }
  }
  if (!/^(off|main|all):\d+:\d+$/.test(checkpoint.externalBar)) throw new Error('invalid saved external_bar setting');
  if ((await query(['-m','config','external_bar'])).trim() !== checkpoint.externalBar) {
    await check();
    await mutate(['-m','config','external_bar',checkpoint.externalBar], {type:'restore_external_bar',reversible:false},
      async () => (await query(['-m','config','external_bar'])).trim() === checkpoint.externalBar);
  }
  const final = assertRecoveryContinuity(checkpoint, await checkedDiscovery());
  const focused = final.spaces.find(s => s.uuid === checkpoint.focusedSpaceUuid);
  if (focused && !focused.focused) {
    await mutate(['-m','space','--focus',String(focused.index)], {type:'restore_focus',spaceUuid:focused.uuid,reversible:false},
      async () => (await checkedDiscovery()).spaces.some(s=>s.uuid===focused.uuid && s.focused));
  }
  const after = assertRecoveryContinuity(checkpoint, await checkedDiscovery());
  if (checkpoint.spaces.some(s => after.spaces.find(c => c.uuid === s.uuid)?.label !== s.label)) throw new Error('Space labels were not restored');
  for (const saved of checkpoint.spaces) {
    const space = after.spaces.find(s => s.uuid === saved.uuid);
    for (const name of settingNames) {
      if ((await query(['-m','config','--space',String(space.index),name])).trim() !== checkpoint.settings[saved.uuid][name]) throw new Error('Space settings were not restored');
    }
  }
  if ((await query(['-m','config','external_bar'])).trim() !== checkpoint.externalBar) throw new Error('external bar setting was not restored');
  const verified = assertRecoveryContinuity(checkpoint, await checkedDiscovery());
  if (after.spaces.some(s => verified.spaces.find(v=>v.uuid===s.uuid)?.index !== s.index)
    || checkpoint.spaces.some(s => verified.spaces.find(v=>v.uuid===s.uuid)?.label !== s.label)) throw new Error('Space indexes or labels changed during recovery verification');
  checkpoint.status = 'completed'; checkpoint.finishedAt = new Date().toISOString(); await persist(checkpoint);
  return checkpoint;
}
