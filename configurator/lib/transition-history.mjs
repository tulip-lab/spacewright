import { mkdir, readFile, readdir, rename, rm, writeFile } from 'node:fs/promises';
import { join } from 'node:path';

const HISTORY_LIMIT = 100;
let sequence = 0;

function historyRoot(stateRoot) {
  return join(stateRoot, 'transition-history');
}

function validRunId(runId) {
  return typeof runId === 'string' && /^[0-9]+-[0-9]+-[a-f0-9]{8}$/.test(runId);
}

export async function writeTransitionRecord(stateRoot, record) {
  if (!validRunId(record?.runId)) throw new Error('invalid transition history run id');
  const root = historyRoot(stateRoot);
  await mkdir(root, { recursive: true, mode: 0o700 });
  sequence += 1;
  const path = join(root, `${record.runId}.json`);
  const temporary = `${path}.${process.pid}.${sequence}.tmp`;
  await writeFile(temporary, `${JSON.stringify(record, null, 2)}\n`, { mode: 0o600 });
  await rename(temporary, path);
  const names = (await readdir(root)).filter((name) => /^[0-9]+-[0-9]+-[a-f0-9]{8}\.json$/.test(name)).sort().reverse();
  await Promise.all(names.slice(HISTORY_LIMIT).map((name) => rm(join(root, name), { force: true })));
}

export async function readTransitionHistory(stateRoot, limit = 50) {
  const root = historyRoot(stateRoot);
  let names;
  try { names = await readdir(root); } catch (error) {
    if (error.code === 'ENOENT') return [];
    throw error;
  }
  const entries = [];
  for (const name of names.filter((item) => /^[0-9]+-[0-9]+-[a-f0-9]{8}\.json$/.test(item)).sort().reverse().slice(0, Math.max(1, Math.min(Number(limit) || 50, HISTORY_LIMIT)))) {
    try { entries.push(JSON.parse(await readFile(join(root, name), 'utf8'))); } catch {}
  }
  return entries;
}

export async function clearTransitionHistory(stateRoot) {
  await rm(historyRoot(stateRoot), { recursive: true, force: true });
}

export { HISTORY_LIMIT };
