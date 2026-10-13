import { execFile, spawn } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdir, readFile, readdir, rename, rm, stat, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { randomBytes } from 'node:crypto';
const exec = promisify(execFile);
export const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
export async function readJson(path, fallback = null) {
  try { return JSON.parse(await readFile(path, 'utf8')); } catch (error) { if (error.code === 'ENOENT' || error instanceof SyntaxError) return fallback; throw error; }
}
export async function atomicJson(path, value) {
  await mkdir(dirname(path), { recursive: true, mode: 0o700 });
  const temp = `${path}.${process.pid}.${randomBytes(6).toString('hex')}.tmp`;
  try { await writeFile(temp, `${JSON.stringify(value, null, 2)}\n`, { mode: 0o600 }); await rename(temp, path); }
  finally { await rm(temp, { force: true }); }
}
export function processIsLive(pid) {
  if (!Number.isInteger(pid) || pid <= 1) return false;
  try { process.kill(pid, 0); return true; } catch (error) { return error.code !== 'ESRCH'; }
}
export async function processIdentity(pid) {
  if (!processIsLive(pid)) return null;
  try { return (await exec('ps', ['-p', String(pid), '-o', 'lstart=', '-o', 'command='], { timeout: 2000 })).stdout.trim(); }
  catch { return null; }
}
export function signalGroup(pid, signal = 'SIGTERM') {
  if (!Number.isInteger(pid) || pid <= 1) return;
  try { process.kill(-pid, signal); } catch (error) { if (error.code !== 'ESRCH') throw error; }
}
export function groupIsLive(pid) {
  try { process.kill(-pid, 0); return true; } catch (error) { return error.code !== 'ESRCH'; }
}
export async function stopGroup(pid, graceMs = 750) {
  if (!pid) return;
  signalGroup(pid);
  const until = Date.now() + graceMs;
  while (groupIsLive(pid) && Date.now() < until) await sleep(25);
  if (groupIsLive(pid)) signalGroup(pid, 'SIGKILL');
  const killedUntil = Date.now() + 2000;
  while (groupIsLive(pid) && Date.now() < killedUntil) await sleep(25);
  if (groupIsLive(pid)) throw Object.assign(new Error(`process group ${pid} did not stop; execution ownership retained`), { code: 'SPACEWRIGHT_GROUP_ACTIVE', pid });
}
export async function verifyLease(stateRoot, env = process.env, pid = process.pid) {
  const owner = await readJson(join(stateRoot, 'execution.lock', 'owner.json'));
  if (!owner?.token || owner.token !== env.SPACEWRIGHT_EXECUTION_TOKEN || owner.runId !== env.SPACEWRIGHT_EXECUTION_RUN_ID) return false;
  if (!processIsLive(owner.pid) || !owner.processIdentity || await processIdentity(owner.pid) !== owner.processIdentity) return false;
  // A copied environment is insufficient: the caller must be in the owner's process tree.
  for (let depth = 0; depth < 64 && pid > 1; depth++) {
    if (pid === owner.pid) return true;
    try { pid = Number((await exec('ps', ['-p', String(pid), '-o', 'ppid='], { timeout: 2000 })).stdout.trim()); }
    catch { return false; }
  }
  return false;
}
export async function releaseLock(stateRoot, owner) {
  const root = join(stateRoot, 'execution.lock');
  const current = await readJson(join(root, 'owner.json'));
  if (current?.token !== owner.token || current?.runId !== owner.runId || current?.pid !== owner.pid) return;
  await drainGroups(root);
  await finishInterruptedJournals(root);
  const released = `${root}.released-${owner.token}`;
  try { await rename(root, released); await rm(released, { recursive: true, force: true }); }
  catch (error) { if (error.code !== 'ENOENT') throw error; }
}
export async function acquireExecution(stateRoot, requestedOwner = {}, { replaceInteractive = false, inherit = true } = {}) {
  if (inherit && await verifyLease(stateRoot)) {
    const owner = await readJson(join(stateRoot, 'execution.lock', 'owner.json'));
    return executionLease(stateRoot, owner, true);
  }
  await mkdir(stateRoot, { recursive: true, mode: 0o700 });
  const root = join(stateRoot, 'execution.lock');
  const owner = { ...requestedOwner, pid: process.pid, token: randomBytes(24).toString('hex'), processIdentity: await processIdentity(process.pid) };
  owner.runId ||= `${Date.now()}-${randomBytes(4).toString('hex')}`;
  for (let attempt = 0; attempt < 20; attempt++) {
    try {
      await mkdir(root, { mode: 0o700 });
      try { await atomicJson(join(root, 'owner.json'), owner); }
      catch (error) { await rm(root, { recursive: true, force: true }); throw error; }
      return executionLease(stateRoot, owner);
    } catch (error) { if (error.code !== 'EEXIST') throw error; }
    const existing = await readJson(join(root, 'owner.json'));
    if (!existing) {
      if (Date.now() - (await stat(root)).mtimeMs < 30_000) throw new Error('another SpaceWright mutation is acquiring the execution lock; retry shortly');
    } else if (processIsLive(existing.pid)) {
      const identity = await processIdentity(existing.pid);
      if (!identity || identity !== existing.processIdentity || existing.controller !== 'mode-transition' || !identity.includes('configurator/mode-transition.mjs')) throw new Error(`execution lock has an unrecognized live owner or another mutation (pid ${existing.pid}); refusing to replace it`);
      if (replaceInteractive && existing.targetKey === owner.targetKey) return { duplicate: true, owner: existing };
      if (!replaceInteractive) throw new Error(`another SpaceWright mutation is active (run ${existing.runId})`);
      process.kill(existing.pid, 'SIGTERM');
      const until = Date.now() + 4000;
      while (processIsLive(existing.pid) && Date.now() < until) await sleep(50);
      if (processIsLive(existing.pid)) {
        await stopGroup(existing.childPid);
        process.kill(existing.pid, 'SIGKILL');
        const untilKilled = Date.now() + 2000;
        while (processIsLive(existing.pid) && Date.now() < untilKilled) await sleep(25);
        if (processIsLive(existing.pid)) throw new Error('old controller did not exit; ownership retained');
      }
      await stopGroup(existing.childPid);
    } else if (existing?.childPid) await stopGroup(existing.childPid);
    await drainGroups(root);
    await finishInterruptedJournals(root);
    const current = await readJson(join(root, 'owner.json'));
    if (JSON.stringify(current) !== JSON.stringify(existing)) continue;
    const stale = `${root}.stale-${owner.token}`;
    try { await rename(root, stale); await rm(stale, { recursive: true, force: true }); }
    catch (error) { if (error.code !== 'ENOENT') throw error; }
  }
  throw new Error('could not acquire execution lock');
}
async function drainGroups(root) {
  for (const pid of await ownedGroups(root)) {
    const record = await readJson(join(root,'groups',`${pid}.json`));
    if (groupIsLive(pid) && processIsLive(pid) && (!record?.processIdentity || await processIdentity(pid) !== record.processIdentity)) throw new Error('registered process group identity is unknown; ownership retained');
    await stopGroup(pid);
  }
}
async function finishInterruptedJournals(root) {
  const names = await readdir(join(root,'journals')).catch((error) => {if(error.code==='ENOENT')return [];throw error;});
  for(const name of names) {
    const record = await readJson(join(root,'journals',name));
    if(!record?.path)continue;
    const journal = await readJson(record.path);
    if(!journal || !['preflight','running'].includes(journal.status))continue;
    journal.status='failed';journal.exitCode=1;journal.finishedAt=new Date().toISOString();journal.error='execution controller exited before a terminal result; child processes stopped';
    for(const step of journal.steps || [])if(step.status==='running'){step.status='failed';step.finishedAt=journal.finishedAt;}
    try{await atomicJson(record.path,journal);}catch(error){process.stderr.write(`terminal journal write failed: ${error.message}; run=${journal.runId} status=failed\n`);}
  }
}
async function ownedGroups(root) {
  const names = await readdir(join(root, 'groups')).catch((error) => { if (error.code === 'ENOENT') return []; throw error; });
  return names.filter((n) => /^[0-9]+\.json$/.test(n)).map((n) => Number(n.slice(0,-5)));
}
function executionLease(stateRoot, owner, inherited = false) {
  let trackedPid = null;
  const groups = join(stateRoot, 'execution.lock', 'groups');
  return { owner, inherited, env: leaseEnvironment(owner), release: inherited ? async () => {} : () => releaseLock(stateRoot, owner),
    trackJournal: async (path) => { const journals=join(stateRoot,'execution.lock','journals');await mkdir(journals,{recursive:true,mode:0o700});await atomicJson(join(journals,`${randomBytes(8).toString('hex')}.json`),{path}); },
    trackChild: async (child) => {
      if (child?.pid) {
        trackedPid = child.pid;
        await mkdir(groups, {recursive:true,mode:0o700});
        await atomicJson(join(groups, `${trackedPid}.json`), {pid:trackedPid,runId:owner.runId,processIdentity:await processIdentity(trackedPid)});
      } else if (trackedPid && !groupIsLive(trackedPid)) {
        await rm(join(groups, `${trackedPid}.json`), {force:true}); trackedPid = null;
      }
    }
  };
}
export function leaseEnvironment(owner) {
  return { SPACEWRIGHT_EXECUTION_TOKEN: owner.token, SPACEWRIGHT_EXECUTION_RUN_ID: owner.runId,
    ...(owner.deadlineAt ? { SPACEWRIGHT_EXECUTION_DEADLINE_MS: String(new Date(owner.deadlineAt).getTime()) } : {}) };
}
export async function runBounded(executable, args, { env = process.env, deadline = Date.now() + 120000, signal, onChild = () => {}, onOutput = () => {}, graceMs = 750 } = {}) {
  if (signal?.aborted) throw signal.reason || new Error('cancelled');
  const remaining = deadline - Date.now();
  if (remaining <= 0) throw Object.assign(new Error('execution deadline exceeded'), { code: 'SPACEWRIGHT_TIMEOUT' });
  const child = spawn(executable, args, { env, detached: true, stdio: ['ignore', 'pipe', 'pipe'] });

  let reason = null;
  let stopping = null;
  const stop = (error) => { reason ||= error; stopping ||= stopGroup(child.pid,graceMs); stopping.catch(() => {}); };
  const abort = () => stop(signal.reason || Object.assign(new Error('cancelled'), { code: 'SPACEWRIGHT_CANCELLED' }));
  signal?.addEventListener('abort', abort, { once: true });
  const timeout = setTimeout(() => stop(Object.assign(new Error('execution deadline exceeded'), { code: 'SPACEWRIGHT_TIMEOUT' })), remaining);
  const output = { stdout: '', stderr: '' };
  for (const name of ['stdout', 'stderr']) child[name].on('data', (chunk) => { output[name] += chunk; onOutput(name, String(chunk)); });
  const completion = new Promise((resolve, reject) => {
    child.once('error', reject);
    child.once('close', (code, signalName) => resolve({ code: code ?? 130, signal: signalName, ...output }));
  });
  completion.catch(() => {});
  try {
    await onChild(child);
    const result = await completion;
    if (stopping) await stopping;
    // Descendants may close inherited pipes then continue mutating. Drain them before release.
    if (child.pid && groupIsLive(child.pid)) await stopGroup(child.pid);
    if (reason) throw reason;
    return result;
  } catch (error) { await stopGroup(child.pid); throw error; }
  finally { clearTimeout(timeout); signal?.removeEventListener('abort', abort); if (stopping) await stopping; await onChild(null); }
}
