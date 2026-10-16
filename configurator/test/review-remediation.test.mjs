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
import { withConfigurationWrite, stableRead, atomicText } from '../lib/config-store.mjs';

const exec = promisify(execFile);
const repo = new URL('../..', import.meta.url).pathname;
async function fixture(t) {
  const root = await mkdtemp(join(tmpdir(), 'spacewright-review-test-'));
  const configRoot = join(root, 'config'), stateRoot = join(root, 'state'), bin = join(root, 'bin');
  await Promise.all([mkdir(configRoot), mkdir(stateRoot), mkdir(bin)]);
  t.after(() => rm(root, { recursive: true, force: true }));
  const data = { displays: [{ index: 1, uuid: 'DISPLAY-1', frame: { x: 0, y: 0, w: 1200, h: 900 } }],
    spaces: [{ index: 1, uuid: 'SPACE-1', display: 1, label: 'coding_solo', type: 'float' }],
    windows: [{ id: 10, pid: process.pid, app: 'Code', space: 1, display: 1, frame: { x: 0, y: 0, w: 600, h: 900 }, 'can-move': true, 'can-resize': true }] };
  await writeFile(join(configRoot, 'config.v2.json'), JSON.stringify(starterConfig()));
  await writeFile(join(stateRoot, 'machine.json'), JSON.stringify({ displayBindings: { primary: 'DISPLAY-1' } }));
  await writeFile(join(root, 'data.json'), JSON.stringify(data));
  await writeFile(join(bin, 'yabai'), `#!${process.execPath}
const fs=require('fs'),root=process.env.REVIEW_ROOT,path=root+'/data.json',data=JSON.parse(fs.readFileSync(path)),args=process.argv.slice(2);
if(args[1]==='query')console.log(JSON.stringify(data[args[2].slice(2)]));
else {fs.appendFileSync(root+'/mutations',JSON.stringify(args)+'\\n');if(args[1]==='window'&&args[3]==='--grid')data.windows[0].frame={...data.displays[0].frame};fs.writeFileSync(path,JSON.stringify(data));}
`, { mode: 0o755 });
  const env = { ...process.env, REVIEW_ROOT: root, PATH: `${bin}:${process.env.PATH}`, SPACEWRIGHT_CONFIG_ROOT: configRoot, SPACEWRIGHT_STATE_ROOT: stateRoot, SPACEWRIGHT_DISPLAY_PROFILES_ROOT:join(configRoot,'displayprofiles') };
  return { root, configRoot, stateRoot, bin, data, env };
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
