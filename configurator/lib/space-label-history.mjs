import { readdir, readFile } from 'node:fs/promises';
import { join } from 'node:path';

// yabai Space labels are runtime state and disappear when its service restarts.
// Completed journals provide a durable, UUID-based observation of the last
// verified label assignment without making the consumer configuration own it.
export async function readSpaceLabelHints(stateRoot, desired, snapshot, limit = 100) {
  const wanted = new Set(desired.workspaces.map((workspace) => workspace.label));
  const liveUuids = new Set(snapshot.spaces.map((space) => space.uuid).filter(Boolean));
  const hints = {};
  let names;
  try { names = await readdir(join(stateRoot, 'runs')); }
  catch (error) { if (error.code === 'ENOENT') return hints; throw error; }
  const journals = names.filter((name) => /^[0-9]+-[a-f0-9]+\.json$/.test(name)).sort().reverse().slice(0, limit);
  for (const name of journals) {
    let journal;
    try { journal = JSON.parse(await readFile(join(stateRoot, 'runs', name), 'utf8')); }
    catch { continue; }
    if (journal.status !== 'completed') continue;
    for (const space of journal.after?.spaces || []) {
      if (!space.label || !space.uuid || !wanted.has(space.label) || !liveUuids.has(space.uuid) || hints[space.label]) continue;
      hints[space.label] = space.uuid;
    }
    if ([...wanted].every((label) => hints[label])) break;
  }
  return hints;
}
