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
export async function withConfigurationWrite(configRoot, operation, { repair = false } = {}) {
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
  try { const result = await operation(); completed = true; return result; }
  finally { if (completed) await rm(guard, { recursive: true, force: true }); }
}
