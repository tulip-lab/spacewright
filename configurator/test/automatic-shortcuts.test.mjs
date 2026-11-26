import test from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdtemp, mkdir, writeFile, readFile, readdir, chmod, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { starterV3, topologyKey, describeDisplays } from '../lib/config-v3.mjs';

const exec = promisify(execFile);
const cli = new URL('../../bin/spacewright', import.meta.url).pathname;
async function tree(root) {
  const result = {};
  for (const f of await readdir(root, { withFileTypes: true })) result[f.name] = f.isDirectory() ? await tree(join(root, f.name)) : await readFile(join(root, f.name), 'utf8');
  return result;
}
for (const setupId of ['single_wide', 'single_tall', 'wide_sidecar', 'tall_sidecar', 'wide_tall']) {
  test(`automatic shortcuts resolve ${setupId} without applying a display profile or writing state`, async () => {
    const root = await mkdtemp(join(tmpdir(), 'spacewright-auto-'));
    const configRoot = join(root, 'config'), stateRoot = join(root, 'state'), fakeBin = join(root, 'bin');
    await Promise.all([mkdir(configRoot), mkdir(stateRoot), mkdir(fakeBin)]);
    const config = starterV3(), setup = config.hardwareProfiles.mac_mini.setups[setupId];
    config.workspaces.coding.windows.editor.required = false;
    const displays = setup.match.displays.map((r, i) => ({index:i+1,uuid:`D${i}`,frame:{x:i*2400,y:0,w:r.orientation==='tall'?1200:2400,h:r.orientation==='tall'?1920:1600},spaces:[i+1]}));
    const machine = {version:2,hardwareProfile:'mac_mini',hardwareProfileConfirmed:true,activeSetup:'stale_setup',displayBindings:{},displayKinds:{},topologySelections:{}};
    setup.match.displays.forEach((r,i) => {machine.displayBindings[r.role]=displays[i].uuid;if(r.kind==='sidecar')machine.displayKinds[displays[i].uuid]='sidecar';});
    machine.topologySelections[topologyKey(describeDisplays({displays},machine))]=setupId;
    const spaces=displays.map(d=>({index:d.index,uuid:`S${d.index}`,display:d.index,label:'',type:'float',windows:[],'has-focus':d.index===1}));
    await writeFile(join(configRoot,'config.v3.json'),JSON.stringify(config));
    await writeFile(join(stateRoot,'machine.json'),JSON.stringify(machine));
    await writeFile(join(fakeBin,'yabai'),`#!${process.execPath}\nconst a=process.argv.slice(2);if(a[1]==='query'){if(a[2]==='--displays')console.log(${JSON.stringify(JSON.stringify(displays))});else if(a[2]==='--spaces')console.log(a.length>3?${JSON.stringify(JSON.stringify(spaces[0]))}:${JSON.stringify(JSON.stringify(spaces))});else if(a[2]==='--windows')console.log('[]');else process.exit(1);}else if(a[1]==='config')console.log('0');else process.exit(99);\n`);
    await chmod(join(fakeBin,'yabai'),0o755);
    const env={...process.env,PATH:`${fakeBin}:${process.env.PATH}`,SPACEWRIGHT_CONFIG_ROOT:configRoot,SPACEWRIGHT_STATE_ROOT:stateRoot};
    const run=async args=>exec(cli,args,{env,maxBuffer:4e6});
    try {
      const before=await tree(root);
      for(const args of [['mode','auto','--dry-run','--json'],['workspace','coding','--dry-run','--json']]) {
        const result=JSON.parse((await run(args)).stdout);
        assert.equal(result.dryRun,true);assert.equal(result.mutates,false);
        assert.equal(result.plan.target.mode,setup.compatibilityMode);
        assert.equal(result.plan.executionSteps.some(s=>s.action==='display_profile'),false);
        assert.deepEqual(result.desired.workspaces.map(w=>w.displayRole),[setup.lanes[0].role]);
      }
      await assert.rejects(run(['apply',setup.compatibilityMode,'--dry-run','--expected-setup=other_setup','--expected-hardware-profile=mac_mini']), e=>/current display setup changed/.test(e.stderr));
      const shown=(await run(['setup','show','--dry-run'])).stdout;
      assert.match(shown,new RegExp(setup.name.replaceAll('+','\\+')));
      assert.match(shown,/Ready/);
      assert.deepEqual(await tree(root),before);
      delete machine.topologySelections[topologyKey(describeDisplays({displays},machine))];
      await writeFile(join(stateRoot,'machine.json'),JSON.stringify(machine));
      await assert.rejects(run(['mode','auto','--dry-run']),e=>/confirm the current/.test(e.stderr));
      await assert.rejects(run(['workspace','coding','--dry-run']),e=>/has not been confirmed/.test(e.stderr));
    } finally {await rm(root,{recursive:true,force:true});}
  });
}

test('confirmed display combinations keep their own bindings across automatic shortcuts', async () => {
  const root = await mkdtemp(join(tmpdir(), 'spacewright-topology-switch-'));
  const configRoot = join(root, 'config'), stateRoot = join(root, 'state'), fakeBin = join(root, 'bin');
  const displayFile = join(root, 'displays.json');
  const machinePath = join(stateRoot, 'machine.json');
  const env = { ...process.env, PATH: `${fakeBin}:${process.env.PATH}`, SPACEWRIGHT_CONFIG_ROOT: configRoot, SPACEWRIGHT_STATE_ROOT: stateRoot };
  const run = async (...args) => JSON.parse((await exec(cli, args, { env, maxBuffer: 4e6 })).stdout);
  const display = (uuid, tall) => ({ uuid, frame: { x: 0, y: 0, w: tall ? 1200 : 1920, h: tall ? 1920 : 1200 } });
  const tall = display('TALL-SINGLE', true), wide = display('WIDE-SINGLE', false);
  const dualTall = display('TALL-DUAL', true), dualWide = display('WIDE-DUAL', false);
  const sidecar = display('SIDECAR', false);
  const ignored = display('IGNORED', false);
  const combinations = [
    ['single_tall', [tall], { tall: tall.uuid }],
    ['single_wide', [wide], { wide: wide.uuid }],
    ['tall_sidecar', [sidecar, dualTall], { tall: dualTall.uuid, sidecar: sidecar.uuid }],
    ['wide_tall', [dualTall, dualWide], { tall: dualTall.uuid, wide: dualWide.uuid }],
    ['wide_sidecar', [wide, sidecar], { wide: wide.uuid, sidecar: sidecar.uuid }]
  ];
  const selectDisplays = async (displays) => writeFile(displayFile, JSON.stringify(displays.map((d, i) => ({ ...d, index: i + 1, spaces: [i + 1] }))));
  try {
    await Promise.all([mkdir(configRoot), mkdir(stateRoot), mkdir(fakeBin)]);
    await writeFile(join(fakeBin, 'sysctl'), '#!/bin/sh\nprintf "%s\\n" "Macmini9,1"\n', { mode: 0o755 });
    await writeFile(join(fakeBin, 'yabai'), `#!${process.execPath}
const displays = JSON.parse(require('node:fs').readFileSync(${JSON.stringify(displayFile)}, 'utf8'));
const spaces = displays.map(d => ({index:d.index, uuid:'S'+d.index, display:d.index, label:'', type:'float', 'has-focus':d.index===1}));
const args = process.argv.slice(2);
if (args[1] !== 'query') process.exit(99);
if (args[2] === '--displays') console.log(JSON.stringify(displays));
else if (args[2] === '--spaces') console.log(JSON.stringify(args.length > 3 ? spaces[0] : spaces));
else if (args[2] === '--windows') console.log('[]');
else process.exit(99);
`, { mode: 0o755 });
    const config = starterV3();
    config.workspaces.coding.windows.editor.required = false;
    await writeFile(join(configRoot, 'config.v3.json'), JSON.stringify(config));
    const legacy = { version: 2, hardwareProfile: 'mac_mini', hardwareProfileConfirmed: true, activeSetup: 'wide_tall',
      displayBindings: { tall: dualTall.uuid, wide: dualWide.uuid },
      displayKinds: { [sidecar.uuid]: 'sidecar', [ignored.uuid]: 'ignored' },
      topologySelections: { 'external:tall+external:wide': 'wide_tall' } };
    await writeFile(machinePath, JSON.stringify(legacy));
    for (const [setup, displays, bindings] of combinations) {
      if (setup === 'wide_tall') continue;
      await selectDisplays(displays);
      assert.deepEqual((await run('setup', 'confirm', 'mac_mini', setup)).displayBindings, bindings);
    }
    await selectDisplays([dualWide, dualTall]);
    assert.deepEqual((await run('setup', 'status')).displayBindings, legacy.displayBindings);
    assert.equal((await run('setup', 'status')).ready, true);
    await run('setup', 'confirm', 'mac_mini', 'wide_tall');

    const savedMachine = await readFile(machinePath, 'utf8');
    const states = JSON.parse(savedMachine);
    assert.equal(Object.keys(states.topologyBindings).length, combinations.length);
    for (const [setup, displays, bindings] of [...combinations, combinations[0]]) {
      await selectDisplays([...displays].reverse());
      const status = await run('setup', 'status');
      assert.equal(status.confirmedSetup, setup);
      assert.equal(status.ready, true);
      assert.deepEqual(status.displayBindings, bindings);
      for (const args of [['mode', 'auto'], ['workspace', 'coding']]) {
        const plan = await run(...args, '--dry-run', '--json');
        assert.equal(plan.plan.executable, true);
        assert.equal(plan.plan.target.mode, config.hardwareProfiles.mac_mini.setups[setup].compatibilityMode);
        assert.deepEqual(plan.comparison.displayBindings, bindings);
        assert.equal(plan.plan.workspaces[0].targetDisplay.uuid, bindings[plan.desired.workspaces[0].displayRole]);
        assert.equal(plan.plan.executionSteps.some(step => step.action === 'display_profile'), false);
      }
    }
    await assert.rejects(
      run('apply', 'tall', '--dry-run', '--expected-setup=single_tall', '--expected-hardware-profile=mac_mini',
        '--expected-topology=external:tall+sidecar:wide'),
      error => /current display setup changed/.test(error.stderr)
    );
    const replacementTall = display('REPLACEMENT-TALL', true), replacementWide = display('REPLACEMENT-WIDE', false);
    for (const [connected, expected] of [
      [[replacementTall], { tall: replacementTall.uuid }],
      [[ignored, replacementWide], { wide: replacementWide.uuid }],
      [[replacementWide, replacementTall], { wide: replacementWide.uuid, tall: replacementTall.uuid }],
      [[sidecar, replacementWide], { sidecar: sidecar.uuid, wide: replacementWide.uuid }]
    ]) {
      await selectDisplays(connected);
      const status = await run('setup', 'status');
      assert.equal(status.ready, true);
      assert.deepEqual(status.displayBindings, expected);
      for (const args of [['mode', 'auto'], ['workspace', 'coding']]) {
        const result = await run(...args, '--dry-run', '--json');
        assert.equal(result.plan.executable, true);
        assert.deepEqual(result.comparison.displayBindings, expected);
        assert.equal(result.plan.workspaces[0].targetDisplay.uuid, expected[result.desired.workspaces[0].displayRole]);
      }
    }
    assert.equal(await readFile(machinePath, 'utf8'), savedMachine);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});
