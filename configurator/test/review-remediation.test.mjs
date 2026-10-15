import test from 'node:test';
import assert from 'node:assert/strict';
import { execFile, spawn } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdtemp, mkdir, writeFile, readFile, readdir, rm } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
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
  const env = { ...process.env, REVIEW_ROOT: root, PATH: `${bin}:${process.env.PATH}`, SPACEWRIGHT_CONFIG_ROOT: configRoot, SPACEWRIGHT_STATE_ROOT: stateRoot };
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

for (const scenario of ['resize', 'reconcile', 'no-display', 'command-failure', 'incomplete', 'unstable', 'config', 'machine', 'window', 'space', 'extra-space', 'display']) {
  test(`R6 display phase replans with fixed ownership: ${scenario}`, async t => {
    const f = await fixture(t), packageRoot = join(f.root, 'package');
    await mkdir(join(packageRoot, 'bin'), { recursive: true });
    const config = starterConfig();
    config.profiles = { resize: { name: 'Resize', mode: 'solo', workspaces: ['coding'], displayConfig: { profile: 'solo' } } };
    if (scenario === 'no-display') delete config.profiles.resize.displayConfig;
    await writeFile(join(f.configRoot, 'config.v2.json'), JSON.stringify(config));
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
 data.displays[0].frame.w=1600;
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
    const result = await exec(process.execPath, [join(repo, 'configurator/state-cli.mjs'), 'apply', '--profile=resize', '--json', `--config-root=${f.configRoot}`, `--state-root=${f.stateRoot}`, `--package-root=${packageRoot}`, `--timeout-seconds=${scenario === 'unstable' ? 3 : 15}`], { env: { ...f.env, REVIEW_SCENARIO: scenario } }).catch(error => error);
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
    } else if (['resize', 'reconcile'].includes(scenario)) {
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
