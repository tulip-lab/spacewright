import { mkdir, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { readJson, assertExecutionAllowed, sleep,DEFAULT_BUDGETS } from './execution-coordinator.mjs';
import { durableJson } from './operation-journal.mjs';
export {DEFAULT_BUDGETS};
export async function consumeBudget(stateRoot,kind,{env=process.env,pid=process.pid}={}) {
  if(!(kind in DEFAULT_BUDGETS))throw new Error('unknown execution budget');
  const root=join(stateRoot,'execution.lock'), gate=join(root,'budget.lock');
  const until=Date.now()+2000;
  while(true) {
    await assertExecutionAllowed(stateRoot,env,pid);
    try {await mkdir(gate,{mode:0o700});break;}catch(error){if(error.code!=='EEXIST')throw error;}
    if(Date.now()>=until)throw new Error('execution budget writer active or interrupted; ownership retained');
    await sleep(10);
  }
  try {
    const owner=await assertExecutionAllowed(stateRoot,env,pid);
    const document=await readJson(join(root,'budgets.json'));
    if(!document || document.runId!==owner.runId || document.token!==owner.token)throw new Error('execution budget state is unavailable');
    if(document.remaining[kind]<=0)throw new Error(`${kind} execution budget exhausted`);
    document.remaining[kind]--;document.consumed[kind]++;
    await durableJson(join(root,'budgets.json'),document);
    return {remaining:document.remaining[kind],deadline:new Date(owner.deadlineAt).getTime()};
  } finally {await rm(gate,{recursive:true,force:true});}
}
