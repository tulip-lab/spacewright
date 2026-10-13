// The coordinator registers this process group before opening fd 3. If it
// crashes before registration, EOF without a grant exits without executing.
import { createReadStream } from 'node:fs';
import { spawn } from 'node:child_process';
let grant='';
for await (const chunk of createReadStream(null,{fd:3}))grant+=chunk;
if(grant!=='execute\n')process.exit(125);
const [executable,...args]=process.argv.slice(2);
const child=spawn(executable,args,{stdio:['ignore','inherit','inherit'],env:process.env});
child.once('error',error=>{process.stderr.write(`${error.message}\n`);process.exitCode=1;});
child.once('exit',(code,signal)=>{process.exitCode=code ?? (signal==='SIGTERM'?143:130);});
