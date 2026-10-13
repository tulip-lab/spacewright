import { execFile, spawn } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdir, readFile, readdir, rename, rm, stat, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { randomBytes } from 'node:crypto';
import { operationRecords } from './operation-journal.mjs';
const exec = promisify(execFile);
// Kept here to avoid an initialization cycle with the authenticated consumer.
export const DEFAULT_BUDGETS=Object.freeze({confirmation:256,commandRetry:2,appRecovery:2,serviceRecovery:1,reconciliation:1});
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
  owner.deadlineAt ||= new Date(Date.now()+120000).toISOString();
  owner.runId ||= `${Date.now()}-${randomBytes(4).toString('hex')}`;
  for (let attempt = 0; attempt < 20; attempt++) {
    try {
      await mkdir(root, { mode: 0o700 });
      try {
        const remaining={...DEFAULT_BUDGETS,...requestedOwner.budgets};
        if(Object.keys(remaining).some(k=>!(k in DEFAULT_BUDGETS) || !Number.isInteger(remaining[k]) || remaining[k]<0))throw new Error('invalid execution budgets');
        await atomicJson(join(root,'budgets.json'),{runId:owner.runId,token:owner.token,remaining,consumed:Object.fromEntries(Object.keys(remaining).map(k=>[k,0]))});
        await atomicJson(join(root, 'owner.json'), owner);
      }
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
    journal.operations=await operationRecords(dirname(root),journal.runId);
    journal.effects=[...(journal.effects || []),...journal.operations.filter(r=>r.id && !(journal.effects || []).some(e=>e.id===r.id))];
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
    cancel:async()=>{
      const current=await readJson(join(stateRoot,'execution.lock','owner.json'));
      if(current?.token!==owner.token)return;
      await writeFile(join(stateRoot,'execution.lock','cancelled.json'),JSON.stringify({runId:owner.runId,token:owner.token,at:new Date().toISOString()}),{flag:'wx',mode:0o600}).catch(error=>{if(!['ENOENT','EEXIST'].includes(error.code))throw error;});
    },
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
export async function assertExecutionAllowed(stateRoot,env=process.env,pid=process.pid) {
  if(!await verifyLease(stateRoot,env,pid))throw new Error('execution requires a verified lease');
  const root=join(stateRoot,'execution.lock'),owner=await readJson(join(root,'owner.json')),cancelled=await readJson(join(root,'cancelled.json'));
  if(owner.cancelledAt || cancelled?.token===owner.token)throw Object.assign(new Error('execution cancelled'),{code:'SPACEWRIGHT_CANCELLED'});
  if(Date.now()>=new Date(owner.deadlineAt).getTime())throw Object.assign(new Error('execution deadline exceeded'),{code:'SPACEWRIGHT_TIMEOUT'});
  return owner;
}
export async function runBounded(executable, args, { env = process.env, deadline = Date.now() + 120000, signal, onChild = () => {}, onOutput = () => {}, graceMs = 750 } = {}) {
  if (signal?.aborted) throw signal.reason || new Error('cancelled');
  const remaining = deadline - Date.now();
  if (remaining <= 0) throw Object.assign(new Error('execution deadline exceeded'), { code: 'SPACEWRIGHT_TIMEOUT' });
  const child = spawn(process.execPath, [new URL('./process-worker.mjs',import.meta.url).pathname,executable,...args], { env, detached: true, stdio: ['ignore', 'pipe', 'pipe', 'pipe'] });

  let reason = null;
  let stopping = null;
  const stop = (error) => { reason ||= error; stopping ||= stopGroup(child.pid,graceMs); stopping.catch(() => {}); };
  const abort = () => stop(signal.reason || Object.assign(new Error('cancelled'), { code: 'SPACEWRIGHT_CANCELLED' }));
  signal?.addEventListener('abort', abort, { once: true });
  const timeout = setTimeout(() => stop(Object.assign(new Error('execution deadline exceeded'), { code: 'SPACEWRIGHT_TIMEOUT' })), remaining);
  const output = { stdout: '', stderr: '' };
  for (const name of ['stdout', 'stderr']) child[name].on('data', (chunk) => { output[name] += chunk;try{onOutput(name,String(chunk));}catch(error){stop(error);} });
  const completion = new Promise((resolve, reject) => {
    child.once('error', reject);
    child.once('close', (code, signalName) => resolve({ code: code ?? 130, signal: signalName, ...output }));
  });
  completion.catch(() => {});
  try {
    await onChild(child);
    if(reason)throw reason;
    await new Promise((resolve,reject)=>{child.stdio[3].once('error',reject);child.stdio[3].end('execute\n',error=>error?reject(error):resolve());});
    const result = await completion;
    if (stopping) await stopping;
    // Descendants may close inherited pipes then continue mutating. Drain them before release.
    if (child.pid && groupIsLive(child.pid)) await stopGroup(child.pid);
    if (reason) throw reason;
    return result;
  } catch (error) { await stopGroup(child.pid); throw error; }
  finally { clearTimeout(timeout); signal?.removeEventListener('abort', abort); if (stopping) await stopping; await onChild(null); }
}
