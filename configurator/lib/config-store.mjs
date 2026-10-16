import { createHash, randomBytes } from 'node:crypto';
import { mkdir, readFile, rename, rm, stat, writeFile,open } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { CONFIG_COMPILER_VERSION, compileV2 } from './config-v2.mjs';
import { compileV3 } from './config-v3.mjs';
import { isDeepStrictEqual } from 'node:util';
export const hash = (value) => createHash('sha256').update(typeof value === 'string' ? value : JSON.stringify(value)).digest('hex');
export function generationDocument(config, resolution, source = `${JSON.stringify(config, null, 2)}\n`) {
  if(!isDeepStrictEqual(JSON.parse(source),config))throw new Error('source bytes no longer match the configuration being compiled');
  const runtime = config.version === 3 ? compileV3(config, resolution) : compileV2(config);
  const context = config.version === 3 ? {
    machine: resolution.machine,
    hardware: {modelIdentifier:resolution.hardware?.modelIdentifier || '',family:resolution.hardware?.family || '',productName:resolution.hardware?.productName || ''},
    // Exclude focus and window/Space state; include display geometry and physical identity.
    displays: resolution.snapshot.displays.map((d) => ({ uuid: d.uuid, index: d.index, frame: d.frame, builtIn: d.builtIn ?? d['is-built-in'] })).sort((a, b) => a.uuid.localeCompare(b.uuid))
  } : null;
  const generated = { format_version: 2, compiler_version: CONFIG_COMPILER_VERSION, source_version: config.version,
    source_sha256: hash(source), context_sha256: hash(context), runtime_sha256: hash(runtime) };
  generated.generation_id = hash(generated).slice(0, 24);
  return { ...runtime, generated };
}
// Hash the parsed body in producer insertion order; file indentation/newlines
// are not part of runtime_sha256. Source bytes deliberately remain significant.
export function verifyRuntimeDocument(actual, expected) {
  const object = value => value && typeof value === 'object' && !Array.isArray(value);
  if (!object(actual) || !object(actual.generated)) return {ok:false,detail:'compiled runtime or generated metadata is invalid; run spacewright config-compile'};
  const {generated, ...body} = actual;
  const errors = [];
  for (const field of Object.keys(expected.generated)) {
    if (generated[field] !== expected.generated[field]) errors.push(`${field} is missing or stale`);
  }
  const bodyDigest = hash(body);
  if (bodyDigest !== generated.runtime_sha256) errors.push('runtime body integrity does not match runtime_sha256');
  if (bodyDigest !== expected.generated.runtime_sha256) errors.push('runtime body differs from the active compiled configuration');
  const generation = Object.fromEntries(Object.keys(expected.generated).filter(key => key !== 'generation_id').map(key => [key,generated[key]]));
  if (generated.generation_id !== hash(generation).slice(0,24)) errors.push('generation_id does not match its metadata');
  return errors.length ? {ok:false,detail:`${errors.join('; ')}; run spacewright config-compile`}
    : {ok:true,detail:'compiled runtime body, source, versions, context and generation are current'};
}

export async function stableRead(configPath, machinePath, { ownedWrite = false,allowMissingConfig=false } = {}) {
  const guard = join(dirname(configPath), '.configuration-write');
  const read = async () => {
    let source;
    try{source=await readFile(configPath,'utf8');}catch(error){if(error.code!=='ENOENT' || !allowMissingConfig)throw error;source='{}';}
    let machine = '{}';
    if (machinePath) try { machine = await readFile(machinePath, 'utf8'); } catch (error) { if (error.code !== 'ENOENT') throw error; }
    return { source, machine };
  };
  const checkGuard = async () => { try { await stat(guard); if (ownedWrite && Number(await readFile(join(guard,'owner'),'utf8')) === process.pid) return; throw new Error('configuration save is incomplete or in progress; refusing mixed generation'); } catch (error) { if (error.code !== 'ENOENT') throw error; } };
  await checkGuard();
  const before = await read();
  const after = await read();
  await checkGuard();
  if (before.source !== after.source || before.machine !== after.machine) throw new Error('configuration generation changed while loading');
  return { config: JSON.parse(before.source), machine: JSON.parse(before.machine), source: before.source };
}
export async function atomicText(path, value) {
  await mkdir(dirname(path), { recursive: true, mode: 0o700 });
  const temp = `${path}.${process.pid}.${randomBytes(6).toString('hex')}.tmp`;
  try {
    const handle=await open(temp,'wx',0o600);try{await handle.writeFile(value);await handle.sync();}finally{await handle.close();}
    await rename(temp,path);
    const directory=await open(dirname(path),'r');try{await directory.sync();}finally{await directory.close();}
  }
  finally { await rm(temp, { force: true }); }
}
// The guard is retained on incomplete writes. Readers fail closed, including
// after a crash. A subsequent explicit save can repair once the dead owner is checked.
export async function withConfigurationWrite(configRoot, operation, { repair = false, trackWrites = false } = {}) {
  const guard = join(configRoot, '.configuration-write');
  await mkdir(configRoot, { recursive: true, mode: 0o700 });
  if (repair) {
    try {
      const guardStat = await stat(guard);
      const pid = Number(await readFile(join(guard,'owner'),'utf8').catch(() => '0'));
      if (pid > 1) {
        let alive = true; try { process.kill(pid,0); } catch (error) { alive = error.code !== 'ESRCH'; }
        if (alive) throw new Error('configuration writer is still active; refusing repair');
      } else if (Date.now()-guardStat.mtimeMs < 30000) throw new Error('configuration writer may be starting; retry repair later');
      const stale = `${guard}.incomplete-${randomBytes(6).toString('hex')}`;
      await rename(guard,stale); await rm(stale,{recursive:true,force:true});
    } catch (error) { if (error.code !== 'ENOENT') throw error; }
  }
  await mkdir(guard, { mode: 0o700 }).catch((error) => { if (error.code === 'EEXIST') throw new Error('configuration write is active or incomplete; repair the saved generation before retrying'); throw error; });
  await writeFile(join(guard, 'owner'), String(process.pid), { mode: 0o600 });
  let completed = false;
  // Uninstrumented callers remain conservative. Opted-in callers must mark the
  // first persistent action (including backups) before attempting it.
  let started = !trackWrites;
  const transaction = { beginWrite: () => { started = true; } };
  try { const result = await operation(transaction); completed = true; return result; }
  finally { if (completed || !started) await rm(guard, { recursive: true, force: true }); }
}
