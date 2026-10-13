#!/usr/bin/env node
import { acquireExecution,runBounded } from '../configurator/lib/execution-coordinator.mjs';
// Smoke is a batch of independent mocked scenarios, not one desktop layout.
// Product-budget limits are separately tested using normal authenticated leases.
if(process.env.SPACEWRIGHT_TEST_ISOLATED!=='1')throw new Error('smoke must run inside isolated-check.mjs');
const lease=await acquireExecution(process.env.SPACEWRIGHT_STATE_ROOT,{controller:'smoke',budgets:{confirmation:4096,commandRetry:256,appRecovery:256,serviceRecovery:256,reconciliation:256}},{inherit:false});
const abort=new AbortController();
for(const signal of ['SIGINT','SIGTERM'])process.once(signal,()=>abort.abort(new Error('smoke cancelled')));
try {
  const result=await runBounded('fish',['--no-config','-c','source "$SPACEWRIGHT_PACKAGE_ROOT/conf.d/spacewright.fish"; work_smoke'],{env:{...process.env,...lease.env},deadline:new Date(lease.owner.deadlineAt).getTime(),signal:abort.signal,onChild:lease.trackChild,onOutput:(channel,text)=>process[channel].write(text)});
  process.exitCode=result.code;
}finally{await lease.release();}
