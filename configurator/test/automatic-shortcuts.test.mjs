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
