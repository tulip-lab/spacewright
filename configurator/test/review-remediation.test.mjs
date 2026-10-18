import test from 'node:test';
import assert from 'node:assert/strict';
import { execFile, spawn } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdtemp, mkdir, writeFile, readFile, readdir, rm } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { starterV3 } from '../lib/config-v3.mjs';
import { starterConfig } from '../lib/config-v2.mjs';
import { normalizeSnapshot } from '../lib/state-engine.mjs';
import { processIdentity, acquireExecution, sleep, groupIsLive, stopGroup } from '../lib/execution-coordinator.mjs';
import { withConfigurationWrite, stableRead, atomicText, generationDocument, verifyRuntimeDocument } from '../lib/config-store.mjs';

const exec = promisify(execFile);
const repo = new URL('../..', import.meta.url).pathname;
async function fixture(t) {
  const root = await mkdtemp(join(tmpdir(), 'spacewright-review-test-'));
  const configRoot = join(root, 'config'), stateRoot = join(root, 'state'), bin = join(root, 'bin');
  await Promise.all([mkdir(configRoot), mkdir(stateRoot), mkdir(bin)]);
  const servers=[];
  t.after(async () => {for(const stop of servers)await stop();await rm(root, { recursive: true, force: true });});
  const data = { displays: [{ index: 1, uuid: 'DISPLAY-1', frame: { x: 0, y: 0, w: 1200, h: 900 } }],
    spaces: [{ index: 1, uuid: 'SPACE-1', display: 1, label: 'coding_solo', type: 'float' }],
    windows: [{ id: 10, pid: process.pid, app: 'Code', space: 1, display: 1, frame: { x: 0, y: 0, w: 600, h: 900 }, 'can-move': true, 'can-resize': true }] };
  await writeFile(join(configRoot, 'config.v2.json'), JSON.stringify(starterConfig()));
  await writeFile(join(stateRoot, 'machine.json'), JSON.stringify({ displayBindings: { primary: 'DISPLAY-1' } }));
  await writeFile(join(root, 'data.json'), JSON.stringify(data));
  await writeFile(join(bin, 'yabai'), `#!${process.execPath}
const fs=require('fs'),root=process.env.REVIEW_ROOT,path=root+'/data.json',data=JSON.parse(fs.readFileSync(path)),args=process.argv.slice(2);
if(args[1]==='query'&&args[2]==='--displays'&&(fs.existsSync(root+'/discovery-block')||fs.existsSync(root+'/setup-discovery-block')&&fs.existsSync(process.env.SPACEWRIGHT_CONFIG_ROOT+'/.configuration-write'))){fs.writeFileSync(root+'/discovery-ready','yes');while(!fs.existsSync(root+'/discovery-continue'))Atomics.wait(new Int32Array(new SharedArrayBuffer(4)),0,0,10);}
if(args[1]==='query'&&args[2]==='--spaces'&&args[3]==='--space'){console.log(JSON.stringify(data.spaces.find(s=>s['has-focus'])));process.exit(0);}
if(args[1]==='query')console.log(JSON.stringify(data[args[2].slice(2)]));
else {fs.appendFileSync(root+'/mutations',JSON.stringify(args)+'\\n');if(args[1]==='window'&&args[3]==='--grid')data.windows[0].frame={...data.displays[0].frame};if(args[1]==='space'&&args[2]==='--focus')data.spaces.forEach(s=>s['has-focus']=s.index===Number(args[3])||s.label===args[3]);fs.writeFileSync(path,JSON.stringify(data));}
`, { mode: 0o755 });
  const env = { ...process.env, REVIEW_ROOT: root, PATH: `${bin}:${process.env.PATH}`, SPACEWRIGHT_CONFIG_ROOT: configRoot, SPACEWRIGHT_STATE_ROOT: stateRoot, SPACEWRIGHT_DISPLAY_PROFILES_ROOT:join(configRoot,'displayprofiles') };
  return { root, configRoot, stateRoot, bin, data, env, servers };
}
async function waitFor(path, timeout = 5000) {
  const until = Date.now() + timeout;
  while (!existsSync(path) && Date.now() < until) await sleep(20);
  assert.ok(existsSync(path), `timed out waiting for ${path}`);
}

test('R1 public run preserves runtime-id, workspace/mode and work_* options', async t => {
  const f = await fixture(t);
  const before = await readFile(join(f.root, 'data.json'), 'utf8');
  for (const target of [['spacewright_coding_solo'], ['coding', 'solo'], ['work_solo']]) {
    for (const options of [['--dry-run', '--json', '--no-reconcile'], ['--json', '--dry-run', '--timeout-seconds=10']]) {
      const result = await exec(join(repo, 'bin/spacewright'), ['run', ...target, ...options], { env: f.env });
      assert.equal(JSON.parse(result.stdout).dryRun, true);
      assert.equal(existsSync(join(f.root, 'mutations')), false);
      assert.equal(existsSync(join(f.stateRoot, 'runs')), false);
      assert.equal(await readFile(join(f.root, 'data.json'), 'utf8'), before);
    }
  }
  // A value-bearing first option must not disappear, even without dry-run.
  await assert.rejects(exec(join(repo, 'bin/spacewright'), ['run', 'spacewright_coding_solo', '--expected-plan-id=stale', '--json'], { env: f.env }), error => {
    assert.equal(JSON.parse(error.stdout).status, 'stale'); return true;
  });
  assert.equal(existsSync(join(f.root, 'mutations')), false);
  const applied = await exec(join(repo, 'bin/spacewright'), ['run', 'spacewright_coding_solo', '--json'], { env: f.env });
  assert.equal(JSON.parse(applied.stdout).status, 'completed');
  assert.equal(JSON.parse(await readFile(join(f.root, 'data.json'))).windows[0].frame.w, 1200);
});

for (const signal of ['SIGKILL', 'SIGINT', 'SIGTERM', 'timeout']) test(`R2 recovery registers and drains its worker on ${signal}`, async t => {
  const f = await fixture(t);
  f.data.spaces.push({ index: 2, uuid: 'SPACE-2', display: 1, label: 'destination', type: 'float' });
  const before = structuredClone(f.data);
  before.windows[0].processFingerprint = await processIdentity(process.pid);
  f.data.windows[0].space = 2;
  await writeFile(join(f.root, 'data.json'), JSON.stringify(f.data));
  const runId = '1000000000000-12345678';
  await mkdir(join(f.stateRoot, 'runs'));
  await writeFile(join(f.stateRoot, 'runs', `${runId}.json`), JSON.stringify({ before: normalizeSnapshot(before), effects: [{ windowId: 10, type: 'move_window', status: 'verified_success' }] }));
  await writeFile(join(f.bin, 'yabai'), `#!${process.execPath}
const fs=require('fs'),root=process.env.REVIEW_ROOT,args=process.argv.slice(2),data=JSON.parse(fs.readFileSync(root+'/data.json'));
if(args[1]==='query')console.log(JSON.stringify(data[args[2].slice(2)]));
else {
 const groups=fs.existsSync(process.env.SPACEWRIGHT_STATE_ROOT+'/execution.lock/groups')?fs.readdirSync(process.env.SPACEWRIGHT_STATE_ROOT+'/execution.lock/groups'):[];
 fs.writeFileSync(root+'/ready',JSON.stringify({group:process.ppid,groups}));
 const timer=setInterval(()=>{if(fs.existsSync(root+'/release-mutation')){fs.writeFileSync(root+'/late-mutation','yes');clearInterval(timer);}},20);
}
`, { mode: 0o755 });
  let group, lease;
  const controller = spawn(process.execPath, [join(repo, 'configurator/state-cli.mjs'), 'recover', runId, `--state-root=${f.stateRoot}`, `--config-root=${f.configRoot}`, `--timeout-seconds=${signal === 'timeout' ? 3 : 15}`, '--json'], { env: f.env, stdio: ['ignore', 'pipe', 'pipe'] });
  const exited = new Promise(resolve => controller.once('exit', resolve));
  try {
    await waitFor(join(f.root, 'ready'));
    const ready = JSON.parse(await readFile(join(f.root, 'ready')));
    group = ready.group;
    if (signal !== 'timeout') controller.kill(signal);
    const code = await exited;
    if (signal !== 'SIGKILL') assert.equal(code, signal === 'timeout' ? 124 : 130);
    lease = await acquireExecution(f.stateRoot, { controller: 'regression-test' }, { inherit: false });
    assert.equal(groupIsLive(group), false);
    await writeFile(join(f.root, 'release-mutation'), 'go');
    await sleep(150);
    assert.equal(existsSync(join(f.root, 'late-mutation')), false);
    assert.ok(ready.groups.includes(`${group}.json`), 'worker must be registered before backend starts');
  } finally {
    controller.kill('SIGKILL'); await exited;
    if (group) await stopGroup(group);
    await lease?.release();
  }
});

test('R3 tracked transactions release pre-write rejections but retain partial generations', async t => {
  const f = await fixture(t), source = join(f.configRoot, 'config.v2.json'), machine = join(f.stateRoot, 'machine.json');
  await assert.rejects(withConfigurationWrite(f.configRoot, async () => {
    await assert.rejects(withConfigurationWrite(f.configRoot, async () => {}), /active or incomplete/);
    throw new Error('invalid candidate');
  }, { trackWrites: true }), /invalid candidate/);
  assert.equal((await stableRead(source, machine)).config.version, 2);
  await assert.rejects(withConfigurationWrite(f.configRoot, async transaction => {
    transaction.beginWrite();
    await atomicText(machine, JSON.stringify({ displayBindings: { primary: 'CHANGED' } }));
    throw new Error('injected second-file failure');
  }, { trackWrites: true }), /second-file failure/);
  await assert.rejects(stableRead(source, machine), /incomplete or in progress/);
  await assert.rejects(withConfigurationWrite(f.configRoot, async () => {}, { repair: true }), /writer is still active/);
});

test('R2 a group that cannot be stopped retains the old execution ownership', async t => {
  const f = await fixture(t);
  const exitedOwner = spawn(process.execPath, ['-e', ''], { stdio: 'ignore' });
  await new Promise(resolve => exitedOwner.once('exit', resolve));
  const worker = spawn(process.execPath, ['-e', 'setInterval(()=>{},1000)'], { detached: true, stdio: 'ignore' });
  const exited = new Promise(resolve => worker.once('exit', resolve));
  const kill = process.kill;
  try {
    const groups = join(f.stateRoot, 'execution.lock/groups');
    await mkdir(groups, { recursive: true });
    const owner = { pid: exitedOwner.pid, token: 'old-token', runId: 'old-run' };
    await writeFile(join(f.stateRoot, 'execution.lock/owner.json'), JSON.stringify(owner));
    await writeFile(join(groups, `${worker.pid}.json`), JSON.stringify({ pid: worker.pid, processIdentity: await processIdentity(worker.pid) }));
    // Simulate ineffective signals for this test-owned group only.
    process.kill = (pid, signal) => pid === -worker.pid && ['SIGTERM', 'SIGKILL'].includes(signal) ? true : kill(pid, signal);
    await assert.rejects(acquireExecution(f.stateRoot, {}, { inherit: false }), /did not stop; execution ownership retained/);
    assert.deepEqual(JSON.parse(await readFile(join(f.stateRoot, 'execution.lock/owner.json'))), owner);
    assert.equal(groupIsLive(worker.pid), true);
  } finally {
    process.kill = kill;
    await stopGroup(worker.pid);
    await exited;
  }
});

for (const scenario of ['mode-v2', 'mode-v3', 'mode-v3-wide', 'mode-v3-tall', 'resize', 'reconcile', 'no-display', 'command-failure', 'incomplete', 'unstable', 'config', 'machine', 'window', 'space', 'extra-space', 'display']) {
  test(`R6 display phase replans with fixed ownership: ${scenario}`, async t => {
    const f = await fixture(t), packageRoot = join(f.root, 'package');
    await mkdir(join(packageRoot, 'bin'), { recursive: true });
    const config = starterConfig();
    config.profiles = { resize: { name: 'Resize', mode: 'solo', workspaces: ['coding'], displayConfig: { profile: 'solo' } } };
    if (scenario === 'no-display') delete config.profiles.resize.displayConfig;
    await writeFile(join(f.configRoot, 'config.v2.json'), JSON.stringify(config));
    if(scenario.startsWith('mode-')) {
      const profiles=join(f.configRoot,'displayprofiles'); await mkdir(profiles);
      await writeFile(join(profiles,'display-solo-primary.fish'),'#!/bin/sh\nexit 0\n',{mode:0o755});
      for (const direction of ['wide','tall']) await writeFile(join(profiles,`display-primary-plus-${direction}-left.fish`),'#!/bin/sh\nexit 0\n',{mode:0o755});
      if(scenario.startsWith('mode-v3')) {
        const v3=starterV3(), setups=v3.hardwareProfiles.mac_mini.setups;
        v3.hardwareProfiles.mac_mini.setups={single_wide:setups.single_wide,single_tall:setups.single_tall};
        if(scenario==='mode-v3')setups.single_wide.compatibilityMode='solo';
        v3.workspaces.coding.configurations.wide.layout={type:'window',role:'editor'};
        await writeFile(join(f.configRoot,'config.v3.json'),JSON.stringify(v3));
        await writeFile(join(f.stateRoot,'machine.json'),JSON.stringify({hardwareProfile:'mac_mini',hardwareProfileConfirmed:true,activeSetup:'single_tall',topologySelections:{'external:wide':'single_wide','external:tall':'single_tall'},displayBindings:{wide:'DISPLAY-1',tall:'DISPLAY-1'}}));
        f.data.displays[0].frame.h=scenario==='mode-v3-tall'?900:1920;f.data.spaces[0].label=scenario==='mode-v3-tall'?'coding_tall':'coding_wide';
        await writeFile(join(f.root,'data.json'),JSON.stringify(f.data));
        await writeFile(join(f.bin,'sysctl'),'#!/bin/sh\necho Macmini9,1\n',{mode:0o755});
      }
    }
    const originalYabai = await readFile(join(f.bin, 'yabai'), 'utf8');
    await writeFile(join(f.bin, 'yabai'), originalYabai.replace("if(args[1]==='query')", `
if(fs.existsSync(root+'/display-done')) {
 if(process.env.REVIEW_SCENARIO==='incomplete'&&args[2]!=='--displays')process.exit(1);
 if(process.env.REVIEW_SCENARIO==='unstable'&&args[2]==='--displays'){data.displays[0].frame.w++;fs.writeFileSync(path,JSON.stringify(data));}
}
if(args[1]==='query')`), { mode: 0o755 });
    await writeFile(join(packageRoot, 'bin/spacewright'), `#!${process.execPath}
const fs=require('fs'),root=process.env.REVIEW_ROOT,path=root+'/data.json',data=JSON.parse(fs.readFileSync(path)),args=process.argv.slice(2),scenario=process.env.REVIEW_SCENARIO;
const owner=JSON.parse(fs.readFileSync(process.env.SPACEWRIGHT_STATE_ROOT+'/execution.lock/owner.json'));
const envelope=JSON.parse(fs.readFileSync(process.env.SPACEWRIGHT_EXECUTION_ENVELOPE));
fs.appendFileSync(root+'/commands',JSON.stringify({args,token:owner.token,deadline:owner.deadlineAt,plan:envelope.plan})+'\\n');
if(args[0]==='display'){
 data.displays[0].frame.w=1600; if(scenario.startsWith('mode-v3'))data.displays[0].frame.h=scenario==='mode-v3-tall'?1920:900;
 if(scenario==='config'){const p=process.env.SPACEWRIGHT_CONFIG_ROOT+'/config.v2.json',c=JSON.parse(fs.readFileSync(p));c.metadata.name='external change';fs.writeFileSync(p,JSON.stringify(c));}
 if(scenario==='machine'){const p=process.env.SPACEWRIGHT_STATE_ROOT+'/machine.json';fs.writeFileSync(p,JSON.stringify({displayBindings:{primary:'OTHER-DISPLAY'}}));}
 if(scenario==='window')data.windows[0].id=11;
 if(scenario==='space')data.spaces[0].uuid='REPLACED-SPACE';
 if(scenario==='extra-space')data.spaces.push({index:2,uuid:'UNPLANNED-SPACE',display:1,label:'',type:'float'});
 if(scenario==='display')data.displays[0].uuid='REPLACED-DISPLAY';
 fs.writeFileSync(path,JSON.stringify(data));fs.writeFileSync(root+'/display-done','yes');
 if(scenario==='command-failure')process.exit(7);
}else if(args[0]==='run'){
 if(envelope.plan.workspaces[0].targetDisplay.frame.w!==(scenario==='no-display'?1200:1600))process.exit(9);
 if(scenario!=='reconcile'||fs.existsSync(root+'/layout-attempted'))data.windows[0].frame={...data.displays[0].frame};
 fs.writeFileSync(root+'/layout-attempted','yes');fs.writeFileSync(path,JSON.stringify(data));
}
`, { mode: 0o755 });
    const result = await exec(process.execPath, [join(repo, 'configurator/state-cli.mjs'), 'apply', ...(scenario.startsWith('mode-')?[scenario==='mode-v3-wide'?'wide':scenario==='mode-v3-tall'?'tall':'solo','--mode-transition']:['--profile=resize']), '--json', `--config-root=${f.configRoot}`, `--state-root=${f.stateRoot}`, `--package-root=${packageRoot}`, `--timeout-seconds=${scenario === 'unstable' ? 3 : 15}`], { env: { ...f.env, REVIEW_SCENARIO: scenario } }).catch(error => error);
    const applied = JSON.parse(result.stdout);
    const commands = (await readFile(join(f.root, 'commands'), 'utf8')).trim().split('\n').map(JSON.parse);
    const journal = JSON.parse(await readFile(applied.journal, 'utf8'));
    assert.equal(commands.filter(c => c.args[0] === 'display').length, scenario === 'no-display' ? 0 : 1);
    assert.equal(journal.effects.filter(e => e.type === 'display_profile').length, scenario === 'no-display' ? 0 : 1);
    assert.equal(existsSync(join(f.stateRoot, 'execution.lock')), false);
    if (scenario === 'no-display') {
      assert.equal(applied.status, 'completed', result.stdout);
      assert.equal(journal.planRelations, undefined);
      assert.equal(journal.verification.converged, true);
    } else if (['mode-v2','mode-v3','mode-v3-wide','mode-v3-tall','resize', 'reconcile'].includes(scenario)) {
      assert.equal(applied.status, 'completed', result.stdout);
      assert.equal(journal.verification.converged, true);
      assert.ok(commands.some(c => c.args[0] === 'run'));
      assert.equal(new Set(commands.map(c => c.token)).size, 1);
      assert.equal(new Set(commands.map(c => c.deadline)).size, 1);
      assert.equal(journal.before.displays[0].frame.w, 1200);
      assert.equal(journal.layoutBefore.displays[0].frame.w, 1600);
      assert.equal(journal.planRelations[0].phase, 'display');
      assert.notEqual(journal.planRelations[0].fromPlanId, journal.planRelations[0].toPlanId);
      assert.deepEqual(commands[0].plan.selectedWindows, journal.plan.selectedWindows);
      assert.equal(journal.plan.workspaces[0].targetSpace.uuid, 'SPACE-1');
      assert.equal(journal.plan.executionSteps.some(s => s.action === 'display_profile'), false);
      if (scenario === 'reconcile') assert.equal(commands.filter(c => c.args[0] === 'run').length, 2);
    } else {
      assert.equal(applied.status, scenario === 'unstable' ? 'timed_out' : 'failed', result.stdout);
      assert.deepEqual(commands.map(c => c.args[0]), ['display']);
      assert.match(applied.error, { 'command-failure': /display.*failed/, incomplete: /discovery.*(partial|unavailable)/, unstable: /(stabil|deadline)/, config: /configuration changed/, machine: /machine.*changed/, window: /windows or ownership changed/, space: /Space.*changed/, 'extra-space': /Space.*changed/, display: /display.*changed/ }[scenario]);
    }
  });
}

for (const dryRun of [true, false]) test(`F1 public mode rejects invalid config before display (dry=${dryRun})`, async t => {
  const f = await fixture(t);
  const config = starterConfig(); Object.values(config.workspaces.coding.windows)[0].app = 'missing_app';
  await writeFile(join(f.configRoot, 'config.v2.json'), JSON.stringify(config));
  const profiles = join(f.root, 'profiles'); await mkdir(profiles);
  await writeFile(join(profiles, 'display-solo-primary.fish'), `#!/bin/sh\ntouch '${f.root}/profile-ran'\n`, {mode:0o755});
  const adapter = join(f.root,'fish-adapter'); await writeFile(adapter, '#!/bin/sh\nif test "$1" = -lc; then exec fish --no-config -c "$2"; else exec fish "$@"; fi\n',{mode:0o755});
  const result = await exec(join(repo, 'bin/spacewright'), ['mode', 'solo', ...(dryRun ? ['--dry-run'] : [])], {env:{...f.env,SPACEWRIGHT_TRANSITION_FISH:adapter,SPACEWRIGHT_DISPLAY_PROFILES_ROOT:profiles,SPACEWRIGHT_BANNER_DISABLE:'1'},timeout:10000}).catch(error=>error);
  assert.ok(result.code, 'invalid config must exit nonzero');
  assert.match(result.stderr, /unknown app|missing_app/);
  assert.equal(existsSync(join(f.root, 'profile-ran')), false);
  assert.equal(existsSync(join(f.root, 'mutations')), false);
  if(dryRun) {
    assert.equal(existsSync(join(f.stateRoot,'runs')),false);
    assert.equal(existsSync(join(f.stateRoot,'mode-transition')),false);
  }
});

for(const scenario of ['missing-config','broken-json','bad-layout','bad-mode','guard','binding','incomplete','missing-window','ambiguous','profile'])test(`F1 public mode read-only gate: ${scenario}`,async t=>{
  const f=await fixture(t), path=join(f.configRoot,'config.v2.json');
  const profiles=join(f.configRoot,'displayprofiles');await mkdir(profiles);
  await writeFile(join(profiles,'display-solo-primary.fish'),`#!/bin/sh\ntouch '${f.root}/profile-ran'\n`,{mode:0o755});
  const config=starterConfig();
  if(scenario==='missing-config')await rm(path);
  if(scenario==='broken-json')await writeFile(path,'{');
  if(scenario==='bad-layout'){config.workspaces.coding.variants.solo.layout={type:'invalid'};await writeFile(path,JSON.stringify(config));}
  if(scenario==='bad-mode'){delete config.modes.solo;await writeFile(path,JSON.stringify(config));}
  if(scenario==='guard')await mkdir(join(f.configRoot,'.configuration-write'));
  if(scenario==='binding')await writeFile(join(f.stateRoot,'machine.json'),'{}');
  if(scenario==='incomplete')await writeFile(join(f.bin,'yabai'),'#!/bin/sh\nexit 1\n',{mode:0o755});
  if(scenario==='missing-window')f.data.windows=[];
  if(scenario==='ambiguous')f.data.windows.push({...f.data.windows[0],id:11});
  if(scenario==='profile')await rm(join(profiles,'display-solo-primary.fish'));
  await writeFile(join(f.root,'data.json'),JSON.stringify(f.data));
  const result=await exec(join(repo,'bin/spacewright'),['mode','solo','--dry-run'],{env:f.env,timeout:10000}).catch(e=>e);
  assert.ok(result.code,result.stdout);assert.equal(existsSync(join(f.root,'profile-ran')),false);assert.equal(existsSync(join(f.root,'mutations')),false);
  assert.equal(existsSync(join(f.stateRoot,'runs')),false);assert.equal(existsSync(join(f.stateRoot,'mode-transition')),false);
});

for(const scenario of ['config','machine','late-config','late-machine','active-version','cancel','timeout'])test(`F1 preflight ready signal rejects ${scenario} before display`,async t=>{
  const f=await fixture(t), packageRoot=join(f.root,'package');await mkdir(join(packageRoot,'bin'),{recursive:true});
  await writeFile(join(packageRoot,'bin/spacewright'),`#!/bin/sh\ntouch '${f.root}/mutation'\n`,{mode:0o755});
  await mkdir(join(f.configRoot,'displayprofiles'));
  await writeFile(join(f.configRoot,'displayprofiles/display-solo-primary.fish'),'#!/bin/sh\nexit 0\n',{mode:0o755});
  const original=await readFile(join(f.bin,'yabai'),'utf8');
  await writeFile(join(f.bin,'yabai'),original.replace("if(args[1]==='query')console.log(JSON.stringify(data[args[2].slice(2)]));",`
if(args[1]==='query') {
 if(args[2]==='--windows') {
  const count=Number(fs.existsSync(root+'/count')?fs.readFileSync(root+'/count'):0)+1;fs.writeFileSync(root+'/count',String(count));
  if(count===Number(process.env.READY_QUERY || 2)){fs.writeFileSync(root+'/ready','yes');const timer=setInterval(()=>{if(fs.existsSync(root+'/continue')){clearInterval(timer);console.log(JSON.stringify(data.windows));}},20);}
  else console.log(JSON.stringify(data.windows));
 } else console.log(JSON.stringify(data[args[2].slice(2)]));
}`),{mode:0o755});
  const child=spawn(process.execPath,[join(repo,'configurator/state-cli.mjs'),'apply','solo','--mode-transition','--json',`--package-root=${packageRoot}`,`--config-root=${f.configRoot}`,`--state-root=${f.stateRoot}`,`--timeout-seconds=${scenario==='timeout'?3:15}`],{env:{...f.env,READY_QUERY:scenario.startsWith('late-')?'3':'2'},stdio:['ignore','pipe','pipe']});
  let output='';child.stdout.on('data',chunk=>output+=chunk);child.stderr.resume();
  const exited=new Promise(resolve=>child.once('exit',resolve));
  t.after(async()=>{if(child.exitCode===null)child.kill('SIGKILL');await exited;});
  await waitFor(join(f.root,'ready'));
  if(scenario.endsWith('config')){const config=starterConfig();config.metadata.name='Changed after preflight';await writeFile(join(f.configRoot,'config.v2.json'),JSON.stringify(config));}
  if(scenario.endsWith('machine'))await writeFile(join(f.stateRoot,'machine.json'),JSON.stringify({displayBindings:{primary:'DISPLAY-1'},changed:true}));
  if(scenario==='active-version')await writeFile(join(f.configRoot,'config.v3.json'),JSON.stringify(starterV3()));
  if(scenario==='cancel')child.kill('SIGINT');
  if(scenario!=='timeout')await writeFile(join(f.root,'continue'),'go');
  const code=await exited;assert.equal(code,scenario==='cancel'?130:scenario==='timeout'?124:1,output);
  assert.equal(existsSync(join(f.root,'mutation')),false);
  assert.equal(existsSync(join(f.stateRoot,'execution.lock')),false);
});

for (const version of [2,3]) test(`F1 successful public mode keeps one lease and executes the display profile once (v${version})`,async t=>{
  const f=await fixture(t),profiles=join(f.configRoot,'displayprofiles');await mkdir(profiles);
  await writeFile(join(profiles,'display-solo-primary.fish'),`#!${process.execPath}
const fs=require('fs'),root=process.env.REVIEW_ROOT,path=root+'/data.json',data=JSON.parse(fs.readFileSync(path));
fs.appendFileSync(root+'/profile-ran','once\\n');data.displays[0].frame.w=1600;fs.writeFileSync(path,JSON.stringify(data));
`,{mode:0o755});
  if (version === 3) {
    f.data.displays[0]['is-built-in']=true;f.data.spaces[0].label='coding_laptop';
    await writeFile(join(f.root,'data.json'),JSON.stringify(f.data));
    await writeFile(join(f.configRoot,'config.v3.json'),JSON.stringify(starterV3()));
    await writeFile(join(f.stateRoot,'machine.json'),JSON.stringify({hardwareProfile:'macbook',hardwareProfileConfirmed:true,topologySelections:{'built_in:wide':'built_in'},displayBindings:{built_in:'DISPLAY-1'}}));
    await writeFile(join(f.bin,'sysctl'),'#!/bin/sh\necho MacBookPro18,3\n',{mode:0o755});
  }
  const result=await exec(join(repo,'bin/spacewright'),['mode','solo'],{env:{...f.env,SPACEWRIGHT_BANNER_DISABLE:'1',WORKSPACE_DISPLAY_SETTLE_SECONDS:'0'},timeout:20000}).catch(async error => {throw new Error(`${error.stderr} mutations=${await readFile(join(f.root,'mutations'),'utf8').catch(()=> '')} data=${await readFile(join(f.root,'data.json'),'utf8')}`);});
  assert.match(result.stdout,/SPACEWRIGHT_VERIFIED/);
  assert.equal(await readFile(join(f.root,'profile-ran'),'utf8'),'once\n');
  const journals=await readdir(join(f.stateRoot,'runs')),journal=JSON.parse(await readFile(join(f.stateRoot,'runs',journals[0])));
  assert.equal(journal.status,'completed');assert.equal(journal.effects.filter(e=>e.type==='display_profile').length,1);
  assert.equal(journal.layoutBefore.displays[0].frame.w,1600);assert.equal(journal.verification.converged,true);
  assert.equal(existsSync(join(f.stateRoot,'execution.lock')),false);
});

for (const source of ['starter', 'example']) test(`R1 optional orientation passes public MacBook mode preflight: ${source}`, async t => {
  const f = await fixture(t);
  const config = source === 'starter' ? starterV3() : JSON.parse(await readFile(join(repo, 'examples/config-v3.json')));
  f.data.displays[0]['is-built-in'] = true;
  await writeFile(join(f.root, 'data.json'), JSON.stringify(f.data));
  await writeFile(join(f.configRoot, 'config.v3.json'), JSON.stringify(config));
  await writeFile(join(f.stateRoot, 'machine.json'), JSON.stringify({hardwareProfile:'macbook',hardwareProfileConfirmed:true,topologySelections:{'built_in:wide':'built_in'},displayBindings:{built_in:'DISPLAY-1'}}));
  await writeFile(join(f.bin, 'sysctl'), '#!/bin/sh\necho MacBookPro18,3\n', {mode:0o755});
  await mkdir(join(f.configRoot, 'displayprofiles'));
  await writeFile(join(f.configRoot, 'displayprofiles/display-solo-primary.fish'), '#!/bin/sh\nexit 0\n', {mode:0o755});
  const result = await exec(join(repo, 'bin/spacewright'), ['mode','solo','--dry-run'], {env:f.env,timeout:10000});
  assert.match(result.stdout, /status=executable/);
  assert.equal(existsSync(join(f.root,'mutations')),false);
  assert.equal(existsSync(join(f.stateRoot,'runs')),false);
  assert.equal(existsSync(join(f.stateRoot,'mode-transition')),false);
});

// Current review contracts exercise public producers and their formal readers.
async function reviewTree(path) {
  const result = {};
  for (const entry of await readdir(path, {withFileTypes:true})) result[entry.name] = entry.isDirectory()
    ? await reviewTree(join(path,entry.name)) : await readFile(join(path,entry.name),'utf8');
  return result;
}
async function portableV3(f) {
  const config=starterV3();
  await writeFile(join(f.configRoot,'config.v3.json'),JSON.stringify(config));
  f.data.displays[0]['is-built-in']=true;
  await writeFile(join(f.root,'data.json'),JSON.stringify(f.data));
  await writeFile(join(f.stateRoot,'machine.json'),JSON.stringify({version:2,hardwareProfile:'macbook',hardwareProfileConfirmed:true,topologySelections:{'built_in:wide':'built_in'},activeSetup:'built_in',displayBindings:{built_in:'DISPLAY-1'}}));
  await writeFile(join(f.bin,'sysctl'),'#!/bin/sh\necho MacBookPro18,3\n',{mode:0o755});
  return config;
}
async function reviewServer(t,f,{hook='',mockExecutor=false}={}) {
  const packageRoot=mockExecutor?join(f.root,'package'):repo;
  if(mockExecutor) {
    await mkdir(join(packageRoot,'bin'),{recursive:true});
    await mkdir(join(packageRoot,'config'),{recursive:true});
    await writeFile(join(packageRoot,'config/defaults.json'),await readFile(join(repo,'config/defaults.json')));
    await writeFile(join(packageRoot,'VERSION'),await readFile(join(repo,'VERSION')));
    await writeFile(join(packageRoot,'bin/spacewright'),`#!${process.execPath}\nrequire('fs').appendFileSync(process.env.REVIEW_ROOT+'/dispatches',JSON.stringify(process.argv.slice(2))+'\\n');console.log(JSON.stringify({noop:true}));\n`,{mode:0o755});
  }
  const env={...f.env};
  if(hook){const path=join(f.root,'hook.mjs');await writeFile(path,hook);env.NODE_OPTIONS=`--import=${path}`;}
  const child=spawn(process.execPath,[join(repo,'configurator/server.mjs'),`--package-root=${packageRoot}`,`--config-root=${f.configRoot}`,`--state-root=${f.stateRoot}`,'--token=current-review','--port=0','--no-open'],{env,stdio:['ignore','pipe','pipe']});
  const exited=new Promise(resolve=>child.once('exit',resolve));
  f.servers.push(async()=>{child.kill('SIGTERM');await exited;});
  const url=await new Promise((resolve,reject)=>{let output='';const timer=setTimeout(()=>reject(Error(output||'server startup timed out')),5000);child.stderr.on('data',d=>output+=d);child.stdout.on('data',d=>{output+=d;const match=output.match(/SPACEWRIGHT_CONFIGURATOR_URL=(http:\/\/[^?\s]+)/);if(match){clearTimeout(timer);resolve(match[1]);}});});
  const api=async(path,body)=>{const response=await fetch(new URL(path,url),{signal:AbortSignal.timeout(10000),headers:{'x-spacewright-token':'current-review','content-type':'application/json'},...(body===undefined?{}:{method:'POST',body:JSON.stringify(body)})});return {status:response.status,body:await response.json()};};
  return {child,api};
}
async function waitUntil(check) {
  const end=Date.now()+6000;
  while(Date.now()<end){if(await check())return;await sleep(20);}
  assert.fail('timed out waiting for review condition');
}

for(const version of [2,3])test(`SW-02 public compile preview v${version} is read-only and rejects unknown options`,async t=>{
  const f=await fixture(t);if(version===3)await portableV3(f);
  const run=(...args)=>exec(join(repo,'bin/spacewright'),['config-compile',...args],{env:f.env});
  for(const existing of [false,true]) {
    if(existing){await mkdir(join(f.configRoot,'generated'),{recursive:true});await writeFile(join(f.configRoot,'generated/runtime.json'),'custom runtime bytes');}
    const before=[await reviewTree(f.configRoot),await reviewTree(f.stateRoot)];
    const result=await run('--dry-run');assert.match(result.stdout,/dry_run=true/);
    assert.deepEqual([await reviewTree(f.configRoot),await reviewTree(f.stateRoot)],before);
    await assert.rejects(run('--typo'),/unknown option/);
    assert.deepEqual([await reviewTree(f.configRoot),await reviewTree(f.stateRoot)],before);
  }
});

test('SW-03 failed public diff releases no guard and valid source is immediately readable',async t=>{
  const f=await fixture(t),source=join(f.configRoot,'config.v2.json'),machine=join(f.stateRoot,'machine.json');
  const original=await readFile(source,'utf8');await writeFile(source,'{broken');
  const before=await reviewTree(f.configRoot);
  await assert.rejects(exec(join(repo,'bin/spacewright'),['config-diff'],{env:f.env}));
  assert.deepEqual(await reviewTree(f.configRoot),before);
  await writeFile(source,original);assert.equal((await stableRead(source,machine)).config.version,2);
  await exec(join(repo,'bin/spacewright'),['config-compile'],{env:f.env});
  const same=await exec(join(repo,'bin/spacewright'),['config-diff'],{env:f.env});assert.match(same.stdout,/runtime is current/);
  await writeFile(join(f.configRoot,'generated/runtime.json'),'{}\n');
  const different=await exec(join(repo,'bin/spacewright'),['config-diff'],{env:f.env});assert.match(different.stdout,/^[+-].*workspaces/m);assert.doesNotMatch(different.stdout,/runtime is current/);
});

for(const form of ['v2-explicit','v3-explicit','v3-auto'])for(const scenario of ['missing','ambiguous','binding','valid','optional'])test(`SW-04 ${form} ${scenario} workspace preview uses apply preflight`,async t=>{
  const f=await fixture(t),config=form.startsWith('v3')?await portableV3(f):starterConfig();
  if(scenario==='missing'||scenario==='optional')f.data.windows=[];
  if(scenario==='ambiguous')f.data.windows.push({...f.data.windows[0],id:20});
  if(scenario==='binding'){const machine=JSON.parse(await readFile(join(f.stateRoot,'machine.json')));for(const role of Object.keys(machine.displayBindings))machine.displayBindings[role]='MISSING-UUID';await writeFile(join(f.stateRoot,'machine.json'),JSON.stringify(machine));}
  if(scenario==='optional'){config.workspaces.coding.windows.editor.required=false;await writeFile(join(f.configRoot,`config.v${config.version}.json`),JSON.stringify(config));}
  await writeFile(join(f.root,'data.json'),JSON.stringify(f.data));
  const before=[await reviewTree(f.configRoot),await reviewTree(f.stateRoot)];
  const run=async args=>{try{return {code:0,...await exec(join(repo,'bin/spacewright'),args,{env:f.env})};}catch(error){return error;}};
  const expected=await run(['apply','coding','solo','--dry-run','--json']);
  const actual=await run(['workspace','coding',...(form==='v3-auto'?[]:['solo']),'--dry-run','--json']);
  assert.equal(actual.code,expected.code);
  if(expected.stdout.trim()) {
    const a=JSON.parse(actual.stdout),e=JSON.parse(expected.stdout);
    assert.deepEqual(a.plan.blockers,e.plan.blockers);assert.deepEqual(a.plan.actions,e.plan.actions);
    assert.equal(a.plan.scope,'workspace');assert.deepEqual(a.plan.target,e.plan.target);
    assert.ok(!a.plan.actions.some(action=>['reorder_spaces','create_sandbox','postprocess'].includes(action.type)));
    assert.equal(a.plan.executable,['valid','optional'].includes(scenario));
  }else {assert.notEqual(actual.code,0);assert.match(actual.stderr,/confirm|binding|setup|role/i);}
  assert.deepEqual([await reviewTree(f.configRoot),await reviewTree(f.stateRoot)],before);
  assert.equal(existsSync(join(f.root,'mutations')),false);
});

for(const scenario of ['v2-enabled','v2-disabled','v3-only','both-disabled','both-enabled'])test(`SW-01 wake and manual rules use active version: ${scenario}`,async t=>{
  const f=await fixture(t),legacy=starterConfig();legacy.settings={...legacy.settings,eventAutomationEnabled:scenario!=='v2-disabled'};
  legacy.rules=[{id:'legacy_wake',enabled:true,when:{event:'wake'},then:{activateWorkspace:'coding',mode:'solo'}}];
  await writeFile(join(f.configRoot,'config.v2.json'),JSON.stringify(legacy));
  if(!scenario.startsWith('v2')) {
    const active=await portableV3(f);active.settings={...active.settings,eventAutomationEnabled:scenario==='both-enabled'};
    await writeFile(join(f.configRoot,'config.v3.json'),JSON.stringify(active));
    if(scenario==='v3-only')await rm(join(f.configRoot,'config.v2.json'));
    // The selected v3 is confirmed and actually executable, so downstream refusal cannot mask a bad dispatch.
    const preview=await exec(join(repo,'bin/spacewright'),['apply','coding','solo','--dry-run','--json'],{env:f.env});
    assert.equal(JSON.parse(preview.stdout).plan.executable,true);
  }
  const s=await reviewServer(t,f,{mockExecutor:true});s.child.kill('SIGUSR1');
  await waitUntil(async()=>{const text=await readFile(join(f.stateRoot,'activity.jsonl'),'utf8').catch(()=>'');return /event_(ignored|evaluated)/.test(text);});
  if(scenario==='v2-enabled')await waitUntil(async()=>(await s.api('/api/tasks')).body.tasks[0]?.status==='completed');
  const tasks=(await s.api('/api/tasks')).body.tasks;
  assert.equal(tasks.length,scenario==='v2-enabled'?1:0);
  assert.equal(existsSync(join(f.root,'dispatches')),scenario==='v2-enabled');
  const manual=await s.api('/api/rules/evaluate',{event:'wake'});
  assert.equal(manual.status,scenario.startsWith('v2')?200:409);
  if(!scenario.startsWith('v2'))assert.equal(manual.body.code,'rules_version_unsupported');
});

for(const producer of ['confirm','activate','bindings'])for(const format of ['compact','two','four','newlines'])test(`SW-05 ${producer} preserves ${format} source digest through diagnostics`,async t=>{
  const f=await fixture(t),config=await portableV3(f),path=join(f.configRoot,'config.v3.json');
  const source=JSON.stringify(config,null,format==='two'?2:format==='four'?4:undefined)+(format==='newlines'?'\n\n':'');await writeFile(path,source);
  const s=await reviewServer(t,f);
  const result=producer==='bindings'?await s.api('/api/display-bindings',{displayBindings:{built_in:'DISPLAY-1'}}):await s.api(`/api/v3/setup/${producer}`,producer==='confirm'?{hardwareProfile:'macbook',setup:'built_in'}:{});
  assert.equal(result.status,200,JSON.stringify(result.body));assert.equal(await readFile(path,'utf8'),source);
  const setup=(await s.api('/api/v3/setup')).body;
  const expected=generationDocument(config,{machine:setup.machine,hardware:setup.hardware,snapshot:setup.snapshot},source);
  const actual=JSON.parse(await readFile(join(f.configRoot,'generated/runtime.json')));
  assert.equal(verifyRuntimeDocument(actual,expected).ok,true,JSON.stringify(actual.generated));
  const diagnostics=(await s.api('/api/diagnostics')).body;
  assert.equal(diagnostics.checks.find(c=>c.id==='compiled_runtime').ok,true);
  assert.equal(existsSync(join(f.configRoot,'.configuration-write')),false);
});

for(const version of [2,3])test(`SW-02/SW-03 v${version} pre-write failures stay read-only and partial compilation stays guarded`,async t=>{
  const f=await fixture(t);if(version===3)await portableV3(f);
  const path=join(f.configRoot,`config.v${version}.json`),source=await readFile(path,'utf8'),machinePath=join(f.stateRoot,'machine.json');
  const run=(command,...args)=>exec(join(repo,'bin/spacewright'),[command,...args],{env:f.env});
  for(const failure of ['source','guard',...(version===3?['machine','unconfirmed']:[])]) {
    const machine=await readFile(machinePath,'utf8');
    if(failure==='source')await writeFile(path,'{broken');
    if(failure==='guard'){await mkdir(join(f.configRoot,'.configuration-write'));await writeFile(join(f.configRoot,'.configuration-write/owner'),'0');}
    if(failure==='machine')await writeFile(machinePath,'{broken');
    if(failure==='unconfirmed')await writeFile(machinePath,JSON.stringify({...JSON.parse(machine),hardwareProfileConfirmed:false}));
    const before=[await reviewTree(f.configRoot),await reviewTree(f.stateRoot)];
    for(const [command,args] of [['config-compile',['--dry-run','--repair-incomplete-save']],['config-diff',[]]]) {
      await assert.rejects(run(command,...args));
      assert.deepEqual([await reviewTree(f.configRoot),await reviewTree(f.stateRoot)],before);
    }
    if(failure!=='guard') {
      await assert.rejects(run('config-compile'));
      assert.deepEqual([await reviewTree(f.configRoot),await reviewTree(f.stateRoot)],before);
    }
    if(failure==='guard')await rm(join(f.configRoot,'.configuration-write'),{recursive:true});
    await writeFile(path,source);await writeFile(machinePath,machine);
    assert.equal((await stableRead(path,machinePath)).config.version,version);
  }
  for(const flag of ['--dry-run=false','--repair-incomplete-save=false','--state-root','unexpected']) {
    const before=await reviewTree(f.configRoot);await assert.rejects(run('config-compile',flag));assert.deepEqual(await reviewTree(f.configRoot),before);
  }
  await run('config-compile');assert.equal(existsSync(join(f.configRoot,'.configuration-write')),false);
  const runtime=join(f.configRoot,'generated/runtime.json');await rm(runtime);await mkdir(runtime);
  const before=await reviewTree(f.configRoot);await assert.rejects(run('config-diff'));assert.deepEqual(await reviewTree(f.configRoot),before);
  await assert.rejects(run('config-compile'));assert.equal(existsSync(join(f.configRoot,'.configuration-write')),true);
  assert.deepEqual(await reviewTree(join(f.configRoot,'generated')),{'runtime.json':{}});
  await assert.rejects(stableRead(path,machinePath),/incomplete or in progress/);
});

test('SW-03 cancelled public diff has no candidate files or configuration guard',async t=>{
  const f=await fixture(t);await portableV3(f);
  const temporary=join(f.root,'temporary');await mkdir(temporary);
  await writeFile(join(f.root,'discovery-block'),'yes');
  const before=[await reviewTree(f.configRoot),await reviewTree(f.stateRoot)];
  const child=spawn(join(repo,'bin/spacewright'),['config-diff'],{env:{...f.env,TMPDIR:temporary},detached:true,stdio:'ignore'});
  const exited=new Promise(resolve=>child.once('exit',resolve));
  try {await waitFor(join(f.root,'discovery-ready'));await stopGroup(child.pid);await exited;}
  finally {await stopGroup(child.pid);}
  assert.deepEqual([await reviewTree(f.configRoot),await reviewTree(f.stateRoot)],before);
  assert.deepEqual(await readdir(temporary),[]);
});

// Accelerate only the monitor's sampling timer, never discovery/task deadlines.
const fastMonitor=`const timeout=globalThis.setTimeout;globalThis.setTimeout=(fn,ms,...args)=>timeout(fn,ms===5000&&new Error().stack.split('\\n')[2]?.includes('automation-monitor.mjs')?60:ms,...args);`;
for(const format of ['compact','two','four','newlines'])test(`SW-01/SW-05 topology activates confirmed v3 with ${format} bytes and never legacy rules`,async t=>{
  const f=await fixture(t),config=await portableV3(f),sourcePath=join(f.configRoot,'config.v3.json');
  config.settings={...config.settings,topologyStableSamples:1,eventAutomationEnabled:true};
  const source=JSON.stringify(config,null,format==='two'?2:format==='four'?4:undefined)+(format==='newlines'?'\n\n':'');await writeFile(sourcePath,source);
  const legacy=starterConfig();legacy.settings={eventAutomationEnabled:true,topologyStableSamples:1};legacy.rules=[{id:'old_topology',enabled:true,when:{event:'display_connected'},then:{activateWorkspace:'coding',mode:'solo'}}];await writeFile(join(f.configRoot,'config.v2.json'),JSON.stringify(legacy));
  await writeFile(join(f.bin,'sysctl'),'#!/bin/sh\necho Macmini9,1\n',{mode:0o755});
  await writeFile(join(f.stateRoot,'machine.json'),JSON.stringify({version:2,hardwareProfile:'mac_mini',hardwareProfileConfirmed:true,topologySelections:{'external:tall':'single_tall'},displayBindings:{tall:'DISPLAY-1'}}));
  const s=await reviewServer(t,f,{hook:fastMonitor,mockExecutor:true});
  // Wait until the initial topology has actually been sampled.
  await writeFile(join(f.root,'discovery-block'),'yes');await waitFor(join(f.root,'discovery-ready'));await writeFile(join(f.root,'discovery-continue'),'yes');
  await sleep(100);
  f.data.displays[0]['is-built-in']=false;f.data.displays[0].frame={x:0,y:0,w:1200,h:1920};await writeFile(join(f.root,'data.json'),JSON.stringify(f.data));
  await waitUntil(async()=>/v3_setup_activated/.test(await readFile(join(f.stateRoot,'activity.jsonl'),'utf8').catch(()=>'')));
  assert.equal((await s.api('/api/tasks')).body.tasks.length,0);assert.equal(existsSync(join(f.root,'dispatches')),false);
  assert.equal(await readFile(sourcePath,'utf8'),source);
  const setup=(await s.api('/api/v3/setup')).body,runtime=JSON.parse(await readFile(join(f.configRoot,'generated/runtime.json')));
  assert.equal(verifyRuntimeDocument(runtime,generationDocument(config,{machine:setup.machine,hardware:setup.hardware,snapshot:setup.snapshot},source)).ok,true);
  assert.equal((await s.api('/api/diagnostics')).body.checks.find(c=>c.id==='compiled_runtime').ok,true);
});

for(const enabled of [false,true])test(`SW-01 v2 topology honors automation ${enabled}`,async t=>{
  const f=await fixture(t),config=starterConfig();config.settings={eventAutomationEnabled:enabled,topologyStableSamples:1,topologyCooldownSeconds:0};
  config.rules=[{id:'connected',enabled:true,when:{event:'display_connected'},then:{activateWorkspace:'coding',mode:'solo'}},{id:'not_matched',enabled:true,when:{event:'wake'},then:{activateWorkspace:'coding',mode:'solo'}}];await writeFile(join(f.configRoot,'config.v2.json'),JSON.stringify(config));
  f.data.displays[0]['is-built-in']=true;await writeFile(join(f.root,'data.json'),JSON.stringify(f.data));
  const s=await reviewServer(t,f,{hook:fastMonitor,mockExecutor:true});
  await writeFile(join(f.root,'discovery-block'),'yes');await waitFor(join(f.root,'discovery-ready'));await writeFile(join(f.root,'discovery-continue'),'yes');await sleep(100);
  f.data.displays.push({index:2,uuid:'DISPLAY-2',frame:{x:1200,y:0,w:1200,h:900},'is-built-in':false});await writeFile(join(f.root,'data.json'),JSON.stringify(f.data));
  await waitUntil(async()=>/topology_changed/.test(await readFile(join(f.stateRoot,'activity.jsonl'),'utf8').catch(()=>'')));
  if(enabled)await waitUntil(async()=>(await s.api('/api/tasks')).body.tasks[0]?.status==='completed');
  assert.equal((await s.api('/api/tasks')).body.tasks.length,enabled?1:0);
  if(enabled)assert.equal((await readFile(join(f.root,'dispatches'),'utf8')).trim().split('\n').length,1);
});

for(const change of ['source','machine','version'])for(const producer of ['confirm','activate','bindings'])test(`SW-05 ${producer} refuses concurrent ${change} generation`,async t=>{
  const f=await fixture(t);await portableV3(f);const s=await reviewServer(t,f);
  await writeFile(join(f.root,'discovery-block'),'yes');
  const pending=producer==='bindings'?s.api('/api/display-bindings',{displayBindings:{built_in:'DISPLAY-1'}}):s.api(`/api/v3/setup/${producer}`,producer==='confirm'?{hardwareProfile:'macbook',setup:'built_in'}:{});
  await waitFor(join(f.root,'discovery-ready'));
  const path=join(f.configRoot,'config.v3.json');
  if(change==='source')await writeFile(path,JSON.stringify(starterV3(),null,4));
  if(change==='machine'){const machine=JSON.parse(await readFile(join(f.stateRoot,'machine.json')));machine.marker='concurrent';await writeFile(join(f.stateRoot,'machine.json'),JSON.stringify(machine));}
  if(change==='version')await rm(path);
  const before=[await reviewTree(f.configRoot),await reviewTree(f.stateRoot)];delete before[0]['.configuration-write'];
  await writeFile(join(f.root,'discovery-continue'),'yes');const result=await pending;
  assert.equal(result.status,500,JSON.stringify(result.body));assert.match(result.body.error,/generation changed/);
  assert.deepEqual([await reviewTree(f.configRoot),await reviewTree(f.stateRoot)],before);
  const selected=change==='version'?join(f.configRoot,'config.v2.json'):path;await stableRead(selected,join(f.stateRoot,'machine.json'));
});

for(const change of ['disable','v3','rule'])test(`SW-01 queued rule rechecks ${change} before dispatching a child`,async t=>{
  const f=await fixture(t),config=starterConfig();config.settings={eventAutomationEnabled:true};
  config.rules=[{id:'one',enabled:true,when:{event:'wake'},then:{activateWorkspace:'coding',mode:'solo'}}];await writeFile(join(f.configRoot,'config.v2.json'),JSON.stringify(config));
  const s=await reviewServer(t,f,{mockExecutor:true});
  await writeFile(join(f.root,'package/bin/spacewright'),`#!${process.execPath}
const fs=require('fs'),root=process.env.REVIEW_ROOT;fs.appendFileSync(root+'/dispatches','dispatch\\n');fs.writeFileSync(root+'/task-ready','yes');const timer=setInterval(()=>{if(fs.existsSync(root+'/task-continue')){clearInterval(timer);console.log(JSON.stringify({noop:true}));}},10);
`,{mode:0o755});
  s.child.kill('SIGUSR1');await waitFor(join(f.root,'task-ready'));
  s.child.kill('SIGUSR1');await waitUntil(async()=>(await s.api('/api/tasks')).body.tasks.length===2);
  if(change==='v3')await portableV3(f);
  else {if(change==='disable')config.settings.eventAutomationEnabled=false;else config.rules[0].then.mode='wide';await writeFile(join(f.configRoot,'config.v2.json'),JSON.stringify(config));}
  await writeFile(join(f.root,'task-continue'),'yes');
  await waitUntil(async()=>(await s.api('/api/tasks')).body.tasks.every(task=>!['running','queued'].includes(task.status)));
  const tasks=(await s.api('/api/tasks')).body.tasks;assert.deepEqual(tasks.map(task=>task.status).sort(),['completed','failed']);
  assert.match(tasks.find(task=>task.status==='failed').logs.join('\n'),/active configuration changed/);
  assert.equal((await readFile(join(f.root,'dispatches'),'utf8')).trim(),'dispatch');
});

for(const change of ['source','machine','version'])test(`SW-05 topology producer refuses concurrent ${change}`,async t=>{
  const f=await fixture(t),config=await portableV3(f);config.settings={topologyStableSamples:1};
  await writeFile(join(f.configRoot,'config.v3.json'),JSON.stringify(config));
  await writeFile(join(f.bin,'sysctl'),'#!/bin/sh\necho Macmini9,1\n',{mode:0o755});
  const machinePath=join(f.stateRoot,'machine.json');
  await writeFile(machinePath,JSON.stringify({version:2,hardwareProfile:'mac_mini',hardwareProfileConfirmed:true,topologySelections:{'external:tall':'single_tall'},displayBindings:{tall:'DISPLAY-1'}}));
  const s=await reviewServer(t,f,{hook:fastMonitor,mockExecutor:true});
  await writeFile(join(f.root,'discovery-block'),'yes');await waitFor(join(f.root,'discovery-ready'));await writeFile(join(f.root,'discovery-continue'),'yes');await sleep(100);
  await rm(join(f.root,'discovery-ready'));await rm(join(f.root,'discovery-block'));await rm(join(f.root,'discovery-continue'));
  await writeFile(join(f.root,'setup-discovery-block'),'yes');
  f.data.displays[0]['is-built-in']=false;f.data.displays[0].frame={x:0,y:0,w:1200,h:1920};await writeFile(join(f.root,'data.json'),JSON.stringify(f.data));
  await waitFor(join(f.root,'discovery-ready'));
  const path=join(f.configRoot,'config.v3.json');
  if(change==='source')await writeFile(path,JSON.stringify(config,null,4));
  if(change==='machine'){const machine=JSON.parse(await readFile(machinePath));machine.marker='changed';await writeFile(machinePath,JSON.stringify(machine));}
  if(change==='version')await rm(path);
  const before=await reviewTree(f.configRoot);delete before['.configuration-write'];const machineBefore=await readFile(machinePath,'utf8');
  await writeFile(join(f.root,'discovery-continue'),'yes');
  await waitUntil(async()=>/topology_monitor_failed/.test(await readFile(join(f.stateRoot,'activity.jsonl'),'utf8')));
  assert.deepEqual(await reviewTree(f.configRoot),before);assert.equal(await readFile(machinePath,'utf8'),machineBefore);
  assert.equal((await s.api('/api/tasks')).body.tasks.length,0);assert.equal(existsSync(join(f.root,'dispatches')),false);
});

for(const change of ['source','machine','version'])test(`SW-02/SW-03 compilation refuses concurrent ${change} with no persistent output`,async t=>{
  const f=await fixture(t);await portableV3(f);
  for(const command of ['config-compile','config-diff']) {
    await portableV3(f);await rm(join(f.root,'discovery-ready'),{force:true});await rm(join(f.root,'discovery-continue'),{force:true});await writeFile(join(f.root,'discovery-block'),'yes');
    const child=spawn(join(repo,'bin/spacewright'),[command,...(command==='config-compile'?['--dry-run']:[])],{env:f.env,stdio:'ignore'});
    const exited=new Promise(resolve=>child.once('exit',resolve));
    await waitFor(join(f.root,'discovery-ready'));
    const sourcePath=join(f.configRoot,'config.v3.json');
    if(change==='source')await writeFile(sourcePath,JSON.stringify(starterV3(),null,4));
    if(change==='machine'){const path=join(f.stateRoot,'machine.json'),machine=JSON.parse(await readFile(path));machine.marker='changed';await writeFile(path,JSON.stringify(machine));}
    if(change==='version')await rm(sourcePath);
    const before=[await reviewTree(f.configRoot),await reviewTree(f.stateRoot)];
    await writeFile(join(f.root,'discovery-continue'),'yes');assert.notEqual(await exited,0);
    assert.deepEqual([await reviewTree(f.configRoot),await reviewTree(f.stateRoot)],before);
  }
});

for(const failure of ['runtime-write','runtime-readback','late-source'])test(`SW-05 activation ${failure} retains an incomplete generation guard`,async t=>{
  const f=await fixture(t);await portableV3(f);
  const hook=failure==='runtime-readback'?`import fs from 'node:fs/promises';import {syncBuiltinESMExports} from 'node:module';const read=fs.readFile;fs.readFile=async function(path,...args){const value=await read.call(this,path,...args);return String(path).endsWith('/generated/runtime.json')?JSON.stringify({...JSON.parse(value),workspaces:{}}):value;};syncBuiltinESMExports();`
    :failure==='late-source'?`import fs from 'node:fs/promises';import {syncBuiltinESMExports} from 'node:module';const rename=fs.rename;fs.rename=async function(from,to){const result=await rename.call(this,from,to);if(String(to).endsWith('/generated/runtime.json')){const path=process.env.SPACEWRIGHT_CONFIG_ROOT+'/config.v3.json';const config=JSON.parse(await fs.readFile(path));await fs.writeFile(path,JSON.stringify(config,null,4));}return result;};syncBuiltinESMExports();`:'';
  if(failure==='runtime-write')await mkdir(join(f.configRoot,'generated/runtime.json'),{recursive:true});
  const s=await reviewServer(t,f,{hook});const result=await s.api('/api/v3/setup/activate',{});
  assert.equal(result.status,500);assert.equal(existsSync(join(f.configRoot,'.configuration-write')),true);
  await assert.rejects(stableRead(join(f.configRoot,'config.v3.json'),join(f.stateRoot,'machine.json')),/incomplete or in progress/);
});
