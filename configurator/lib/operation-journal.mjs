import { mkdir, open, rename, readdir, readFile, rm } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { randomBytes } from 'node:crypto';
// Intent and acknowledgment survive a controller crash. Sync both the file
// and directory; an unavailable journal is a mutation blocker.
export async function durableJson(path, value) {
  await mkdir(dirname(path), {recursive:true,mode:0o700});
  const temp=`${path}.${randomBytes(8).toString('hex')}.tmp`;
  let handle;
  try {
    handle=await open(temp,'wx',0o600);
    await handle.writeFile(`${JSON.stringify(value,null,2)}\n`);await handle.sync();await handle.close();handle=null;
    await rename(temp,path);
    const dir=await open(dirname(path),'r');try{await dir.sync();}finally{await dir.close();}
  } finally {await handle?.close();await rm(temp,{force:true});}
}
export function operationRoot(stateRoot,runId) {
  if (!/^[a-zA-Z0-9_-]+$/.test(runId)) throw new Error('invalid operation run id');
  return join(stateRoot,'runs',`${runId}.operations`);
}
export async function operationRecords(stateRoot,runId) {
  const root=operationRoot(stateRoot,runId);
  const names=await readdir(root).catch(e=>{if(e.code==='ENOENT')return [];throw e;});
  return Promise.all(names.filter(n=>n.endsWith('.json')).sort().map(async n=>JSON.parse(await readFile(join(root,n),'utf8'))));
}
export async function journalMutation({stateRoot,runId,intent,run,verify}) {
  const id=`${Date.now()}-${randomBytes(8).toString('hex')}`, path=join(operationRoot(stateRoot,runId),`${id}.json`);
  const record={id,runId,...intent,status:'attempted_unknown',startedAt:new Date().toISOString()};
  await durableJson(path,record);
  try {
    const result=await run();
    record.exitCode=result.code;
    record.status=result.code===0?'attempted_unknown':'failed';
    // A zero exit is only an acknowledgment of the command, not its effect.
    await durableJson(path,record);
    if(result.code!==0) throw Object.assign(new Error(result.stderr || `mutation exited ${result.code}`),{code:result.code===124?'SPACEWRIGHT_TIMEOUT':result.code===130?'SPACEWRIGHT_CANCELLED':undefined});
    record.postcondition=await verify();
    if (!record.postcondition) throw new Error('mutation postcondition failed');
    record.status='verified_success';record.finishedAt=new Date().toISOString();
    await durableJson(path,record);
    return result;
  } catch (error) {
    record.error=error.message;
    if (record.exitCode != null) record.status='failed';
    if(error.code==='SPACEWRIGHT_CANCELLED')record.status='cancelled';
    if(error.code==='SPACEWRIGHT_TIMEOUT')record.status='timed_out';
    record.finishedAt=new Date().toISOString();
    try{await durableJson(path,record);}catch(writeError){process.stderr.write(`operation journal unavailable: ${writeError.message}; run=${runId} operation=${id} status=${record.status}\n`);}
    throw error;
  }
}
