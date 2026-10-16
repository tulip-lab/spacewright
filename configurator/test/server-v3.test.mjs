import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {generationDocument} from '../lib/config-store.mjs';
import { spawn } from 'node:child_process';
import { chmod, mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { chromium } from 'playwright';
import { starterV3 } from '../lib/config-v3.mjs';
import { starterConfig } from '../lib/config-v2.mjs';
import YAML from 'yaml';

const packageRoot = new URL('../..', import.meta.url).pathname;
const systemChrome = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

async function startServer(configRoot, stateRoot, fakeBin, extraEnv = {}) {
  const token = 'v3-integration-token';
  const child = spawn(process.execPath, [
    join(packageRoot, 'configurator/server.mjs'),
    `--package-root=${packageRoot}`,
    `--config-root=${configRoot}`,
    `--state-root=${stateRoot}`,
    `--token=${token}`,
    '--port=0',
    '--no-open'
  ], { env: { ...process.env, PATH: `${fakeBin}:${process.env.PATH}`, ...extraEnv }, stdio: ['ignore', 'pipe', 'pipe'] });
  const url = await new Promise((resolve, reject) => {
    let output = '';
    const timer = setTimeout(() => reject(new Error(`server did not start: ${output}`)), 5000);
    child.once('error', reject);
    child.stderr.on('data', (chunk) => { output += chunk; });
    child.stdout.on('data', (chunk) => {
      output += chunk;
      const match = output.match(/SPACEWRIGHT_CONFIGURATOR_URL=(http:\/\/[^?\s]+)/);
      if (match) { clearTimeout(timer); resolve(match[1]); }
    });
  });
  return { child, token, url };
}

async function json(url, path, token, options = {}) {
  const response = await fetch(new URL(path.slice(1), url), { ...options, headers: { 'content-type': 'application/json', ...(token ? { 'x-spacewright-token': token } : {}), ...(options.headers || {}) } });
  return { status: response.status, body: await response.json() };
}

for (const scenario of ['v2-only', 'v3-only', 'both']) test(`R5 portable import/export round trip: ${scenario}`, async context => {
  const root = await mkdtemp(join(tmpdir(), 'spacewright-portable-'));
  const configRoot = join(root, 'config'), stateRoot = join(root, 'state'), fakeBin = join(root, 'bin');
  await Promise.all([mkdir(configRoot), mkdir(stateRoot), mkdir(fakeBin)]);
  const v2 = starterConfig(), v3 = starterV3();
  v2.metadata.name = 'Distinct v2'; v3.metadata.name = 'Distinct v3';
  v2.workspaces.coding.name = 'Portable Coding v2'; v3.workspaces.coding.name = 'Portable Coding v3';
  if (scenario !== 'v3-only') await writeFile(join(configRoot, 'config.v2.json'), JSON.stringify(v2));
  if (scenario !== 'v2-only') await writeFile(join(configRoot, 'config.v3.json'), JSON.stringify(v3));
  await writeFile(join(stateRoot, 'machine.json'), JSON.stringify({ version: 2, hardwareProfile: 'mac_mini', hardwareProfileConfirmed: true, displayBindings: { tall: 'DISPLAY-TALL-1234' }, topologySelections: { 'external:tall': 'single_tall' }, activeSetup: 'single_tall' }));
  await writeFile(join(fakeBin, 'sysctl'), '#!/bin/sh\necho Macmini9,1\n', { mode: 0o755 });
  await writeFile(join(fakeBin, 'yabai'), `#!/bin/sh
case "$3" in
 --displays) echo '[{"index":1,"uuid":"DISPLAY-TALL-1234","frame":{"x":0,"y":0,"w":1200,"h":1920},"is-built-in":false}]';;
 *) echo '[]';;
esac
`, { mode: 0o755 });
  const { child, token, url } = await startServer(configRoot, stateRoot, fakeBin);
  context.after(async () => { child.kill('SIGTERM'); await new Promise(resolve => child.once('exit', resolve)); await rm(root, { recursive: true, force: true }); });
  const expected = scenario === 'v2-only' ? v2 : v3;
  const exported = await fetch(new URL('/api/export', url), { headers: { 'x-spacewright-token': token } });
  assert.equal(exported.status, 200);
  const text = await exported.text();
  assert.deepEqual(YAML.parse(text), expected);
  assert.equal(text.includes('DISPLAY-TALL-1234'), false);
  const file = join(configRoot, `config.v${expected.version}.json`);
  const before = await readFile(file, 'utf8'), machineBefore = await readFile(join(stateRoot, 'machine.json'), 'utf8');
  const preview = await json(url, '/api/import', token, { method: 'POST', body: JSON.stringify({ text }) });
  assert.equal(preview.status, 200, JSON.stringify(preview.body)); assert.deepEqual(preview.body.config, expected);
  assert.equal(await readFile(file, 'utf8'), before);
  assert.equal(await readFile(join(stateRoot, 'machine.json'), 'utf8'), machineBefore);
  assert.equal(existsSync(join(configRoot, 'generated')), false);
  const endpoint = expected.version === 3 ? '/api/v3' : '/api';
  const document = await json(url, `${endpoint}/config`, token);
  const saved = await json(url, `${endpoint}/save`, token, { method: 'POST', body: JSON.stringify({ config: preview.body.config, baseRevision: document.body.revision }) });
  assert.equal(saved.status, 200, JSON.stringify(saved.body));
  assert.deepEqual((await json(url, `${endpoint}/config`, token)).body.config, expected);
  for (const invalid of [{ version: 4 }, { ...expected, workspaces: null }, null]) {
    const rejected = await json(url, '/api/import', token, { method: 'POST', body: JSON.stringify({ text: JSON.stringify(invalid) }) });
    assert.equal(rejected.status, 422); assert.equal(rejected.body.valid, false);
  }
  {
    const browser = await chromium.launch({ headless: true, ...(existsSync(systemChrome) ? { executablePath: systemChrome } : {}) });
    context.after(() => browser.close());
    const page = await browser.newPage(); const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.goto(`${url}?token=${token}&view=${expected.version === 3 ? 'hardware' : 'review'}`);
    await page.locator(expected.version === 3 ? '#v3-save' : '#save').waitFor();
    const candidate = structuredClone(expected); candidate.workspaces.coding.name = `Imported v${expected.version} workspace`;
    await page.locator('#import-file').setInputFiles({ name: 'portable.yaml', mimeType: 'application/yaml', buffer: Buffer.from(YAML.stringify(candidate)) });
    if (expected.version === 3) await page.getByText(candidate.workspaces.coding.name, { exact: true }).first().waitFor();
    else await page.getByText(/Imported validated preview/).waitFor();
    assert.equal(await readFile(file, 'utf8'), JSON.stringify(expected, null, 2) + '\n');
    const saveResponse = page.waitForResponse(response => response.url().endsWith(`${endpoint}/save`));
    await page.locator(expected.version === 3 ? '#v3-save' : '#save').click();
    if (expected.version === 2) await page.locator('dialog.modal-dialog').getByRole('button', { name:'Save Changes' }).click();
    assert.equal((await saveResponse).status(), 200);
    assert.deepEqual(JSON.parse(await readFile(file, 'utf8')), candidate);
    assert.deepEqual(errors, []);
  }
  await writeFile(file, JSON.stringify({ version: 4 }));
  const invalidExport = await fetch(new URL('/api/export', url), { headers: { 'x-spacewright-token': token } });
  assert.equal(invalidExport.status, 422);
});

test('v3 server confirms a Mac mini display setup and saves a digest-bound runtime', async (context) => {
  const root = await mkdtemp(join(tmpdir(), 'spacewright-server-v3-'));
  const configRoot = join(root, 'config');
  const stateRoot = join(root, 'state');
  const fakeBin = join(root, 'fake-bin');
  await Promise.all([mkdir(configRoot), mkdir(stateRoot), mkdir(fakeBin)]);
  const config = starterV3();
  await writeFile(join(configRoot, 'config.v3.json'), `${JSON.stringify(config, null, 2)}\n`);
  await writeFile(join(fakeBin, 'sysctl'), '#!/bin/sh\nprintf "%s\\n" "Macmini9,1"\n');
  await writeFile(join(fakeBin, 'yabai'), `#!/bin/sh
case "$3" in
  --displays) printf '%s\n' '[{"index":1,"uuid":"DISPLAY-TALL-1234","frame":{"x":0,"y":0,"w":1200,"h":1920},"is-built-in":false,"spaces":[1]}]' ;;
  --spaces) printf '%s\n' '[{"index":1,"uuid":"SPACE-CODING","display":1,"label":"coding_tall","type":"float"}]' ;;
  --windows) printf '%s\n' '[{"id":10,"app":"Code","display":1,"space":1,"frame":{"x":0,"y":0,"w":1200,"h":1920},"can-move":true,"can-resize":true,"is-visible":true}]' ;;
esac
`);
  await Promise.all([chmod(join(fakeBin, 'sysctl'), 0o755), chmod(join(fakeBin, 'yabai'), 0o755)]);
  const { child, token, url } = await startServer(configRoot, stateRoot, fakeBin);
  context.after(async () => { child.kill('SIGTERM'); await rm(root, { recursive: true, force: true }); });

  const unauthenticated = await json(url, '/api/v3/config');
  assert.equal(unauthenticated.status, 403);
  const document = await json(url, '/api/v3/config', token);
  assert.equal(document.status, 200);
  assert.equal(document.body.source, 'v3');
  const detected = await json(url, '/api/v3/setup', token);
  assert.equal(detected.status, 200);
  assert.equal(detected.body.hardwareSelection.id, 'mac_mini', JSON.stringify(detected.body));
  assert.deepEqual(detected.body.setupCandidates, ['single_tall'], JSON.stringify(detected.body));
  assert.equal(detected.body.ready, false);

  const confirmed = await json(url, '/api/v3/setup/confirm', token, {
    method: 'POST',
    body: JSON.stringify({ config, hardwareProfile: 'mac_mini', setup: 'single_tall' })
  });
  assert.equal(confirmed.status, 200, JSON.stringify(confirmed.body));
  assert.equal(confirmed.body.machine.displayBindings.tall, 'DISPLAY-TALL-1234');
  assert.equal(confirmed.body.machine.topologySelections['external:tall'], 'single_tall');

  const saved = await json(url, '/api/v3/save', token, {
    method: 'POST',
    body: JSON.stringify({ config, baseRevision: document.body.revision })
  });
  assert.equal(saved.status, 200, JSON.stringify(saved.body));
  assert.equal(saved.body.verified, true);
  const runtime = JSON.parse(await readFile(join(configRoot, 'generated', 'runtime.json'), 'utf8'));
  assert.equal(runtime.source_version, 3);
  assert.equal(runtime.active_hardware_profile, 'mac_mini');
  assert.equal(runtime.active_setup, 'single_tall');
  assert.match(runtime.generated.source_sha256, /^[a-f0-9]{64}$/);

  const activated = await json(url, '/api/v3/setup/activate', token, { method: 'POST', body: '{}' });
  assert.equal(activated.status, 200);
  assert.equal(activated.body.compatibilityMode, 'tall');

  const machineBefore = await readFile(join(stateRoot, 'machine.json'), 'utf8');
  const runtimeBefore = await readFile(join(configRoot, 'generated', 'runtime.json'), 'utf8');
  const rejectedBindings = await json(url, '/api/display-bindings', token, {
    method: 'POST', body: JSON.stringify({ displayBindings: { primary: 'DISPLAY-TALL-1234' } })
  });
  assert.equal(rejectedBindings.status, 422, JSON.stringify(rejectedBindings.body));
  const rejectedTopology = await json(url, '/api/display-bindings', token, {
    method: 'POST', body: JSON.stringify({ displayBindings: { wide: 'DISPLAY-TALL-1234' } })
  });
  assert.equal(rejectedTopology.status, 422, JSON.stringify(rejectedTopology.body));
  assert.match(rejectedTopology.body.error, /confirmed topology/);
  assert.equal(await readFile(join(stateRoot, 'machine.json'), 'utf8'), machineBefore);
  assert.equal(await readFile(join(configRoot, 'generated', 'runtime.json'), 'utf8'), runtimeBefore);
  assert.equal(existsSync(join(configRoot, '.configuration-write')), false);
  assert.equal((await json(url, '/api/v3/config', token)).status, 200);
  const validBindings = await json(url, '/api/display-bindings', token, {
    method: 'POST', body: JSON.stringify({ displayBindings: { tall: 'DISPLAY-TALL-1234' } })
  });
  assert.equal(validBindings.status, 200, JSON.stringify(validBindings.body));

  const preview = await json(url, '/api/preview', token, {
    method: 'POST',
    body: JSON.stringify({ kind: 'workspace', target: 'coding' })
  });
  assert.equal(preview.status, 200, JSON.stringify(preview.body));
  assert.equal(preview.body.resolution.hardwareProfileId, 'mac_mini');
  assert.equal(preview.body.resolution.setupId, 'single_tall');
  assert.equal(preview.body.plan.target.mode, 'tall');

  const browser = await chromium.launch({ headless: true, ...(existsSync(systemChrome) ? { executablePath: systemChrome } : {}) });
  context.after(() => browser.close());
  const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
  const pageErrors = [];
  page.on('pageerror', (error) => pageErrors.push(error.message));
  const pageUrl = new URL(url);
  pageUrl.searchParams.set('token', token);
  pageUrl.searchParams.set('view', 'hardware');
  await page.goto(pageUrl.href);
  try {
    await page.getByRole('heading', { name: 'Mac → setup → workspace configuration' }).waitFor({ timeout: 20_000 });
  } catch (error) {
    throw new Error(`${error.message}\npage=${(await page.content()).slice(0, 2000)}\npageErrors=${pageErrors.join('; ')}`);
  }
  assert.equal(new URL(page.url()).searchParams.has('token'), false);
  assert.match(await page.locator('.v3-detection').innerText(), /Macmini9,1 · mac_mini[\s\S]*confirmed as single_tall/);
  assert.equal(await page.locator('[data-v3-setup="single_tall"]').getAttribute('class'), 'active');
  assert.equal(await page.locator('[data-v3-assignment="coding"]').inputValue(), 'tall');
  assert.equal(await page.locator('#v3-configuration').inputValue(), 'tall');
  await page.getByRole('button', { name: 'Edit exact grid' }).click();
  assert.equal(await page.locator('.canvas-window').count(), 1);
  const unlabeledControls = await page.evaluate(() => [...document.querySelectorAll('input:not([type="hidden"]):not([hidden]), select')].filter((control) => {
    if (control.getAttribute('aria-label')) return false;
    if (control.id && document.querySelector(`label[for="${CSS.escape(control.id)}"]`)) return false;
    return !control.closest('label');
  }).map((control) => control.outerHTML));
  assert.deepEqual(unlabeledControls, []);
  await page.setViewportSize({ width: 780, height: 1000 });
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth), true);
  assert.deepEqual(pageErrors, []);

  const candidate = structuredClone(config);
  candidate.hardwareProfiles.mac_mini.setups.single_tall_custom = structuredClone(candidate.hardwareProfiles.mac_mini.setups.single_tall);
  candidate.hardwareProfiles.mac_mini.setups.single_tall_custom.name = 'Single tall custom';
  const candidateConfirmation = await json(url, '/api/v3/setup/confirm', token, {
    method: 'POST',
    body: JSON.stringify({ config: candidate, hardwareProfile: 'mac_mini', setup: 'single_tall_custom' })
  });
  assert.equal(candidateConfirmation.status, 200, JSON.stringify(candidateConfirmation.body));
  assert.equal(candidateConfirmation.body.setupState.ready, true);
  assert.equal(candidateConfirmation.body.setupState.confirmedSetup, 'single_tall_custom');
  const candidateSave = await json(url, '/api/v3/save', token, {
    method: 'POST',
    body: JSON.stringify({ config: candidate, baseRevision: saved.body.revision })
  });
  assert.equal(candidateSave.status, 200, JSON.stringify(candidateSave.body));

  // Inject a second-file publish failure after machine state has been saved.
  const partialMachine = JSON.parse(await readFile(join(stateRoot, 'machine.json')));
  partialMachine.activeSetup = null;
  await writeFile(join(stateRoot, 'machine.json'), JSON.stringify(partialMachine));
  await rm(join(configRoot, 'generated/runtime.json'));
  await mkdir(join(configRoot, 'generated/runtime.json'));
  const interrupted = await json(url, '/api/v3/setup/activate', token, { method:'POST', body:'{}' });
  assert.equal(interrupted.status, 500);
  assert.equal(JSON.parse(await readFile(join(stateRoot, 'machine.json'))).activeSetup, 'single_tall_custom');
  assert.equal(existsSync(join(configRoot, '.configuration-write')), true);
  assert.equal((await json(url, '/api/v3/config', token)).status, 500);
});

for (const scenario of ['v2-only','v3-only','both']) test(`F2 backup restore uses active portable generation: ${scenario}`, async context => {
  const root=await mkdtemp(join(tmpdir(),'spacewright-backup-'));
  const configRoot=join(root,'config'),stateRoot=join(root,'state'),fakeBin=join(root,'bin');
  await Promise.all([mkdir(configRoot),mkdir(stateRoot),mkdir(fakeBin)]);
  const current=scenario==='v2-only'?starterConfig():starterV3(), backup=structuredClone(current);
  current.metadata.name='Current unique document'; backup.metadata.name='Restored unique document'; backup.workspaces.coding.name='Restored coding';
  const source=join(configRoot,`config.v${current.version}.json`), sourceText=JSON.stringify(current);
  await writeFile(source,sourceText);await writeFile(`${source}.backup`,JSON.stringify(backup));
  const legacyText=JSON.stringify(starterConfig());
  if(scenario==='both') { await writeFile(join(configRoot,'config.v2.json'),legacyText);await writeFile(join(configRoot,'config.v2.json.backup'),legacyText); }
  const machine=JSON.stringify({version:2,hardwareProfile:'mac_mini',hardwareProfileConfirmed:true,displayBindings:{tall:'DISPLAY-TALL-1234'},topologySelections:{'external:tall':'single_tall'},activeSetup:'single_tall'});
  await writeFile(join(stateRoot,'machine.json'),machine);
  await writeFile(join(fakeBin,'sysctl'),'#!/bin/sh\necho Macmini9,1\n',{mode:0o755});
  await writeFile(join(fakeBin,'yabai'),`#!/bin/sh
case "$3" in
 --displays) echo '[{"index":1,"uuid":"DISPLAY-TALL-1234","frame":{"x":0,"y":0,"w":1200,"h":1920}}]';;
 *) echo '[]';;
esac
`,{mode:0o755});
  const {child,token,url}=await startServer(configRoot,stateRoot,fakeBin);
  context.after(async()=>{child.kill('SIGTERM');await new Promise(resolve=>child.once('exit',resolve));await rm(root,{recursive:true,force:true});});
  const preview=await json(url,'/api/config-backup',token);
  assert.equal(preview.status,200);assert.equal(preview.body.version,current.version);assert.deepEqual(preview.body.config,backup);
  const post=payload=>json(url,'/api/restore-backup',token,{method:'POST',body:JSON.stringify(payload)});
  assert.equal((await post({})).status,428);
  const payload={version:preview.body.version,baseRevision:preview.body.baseRevision,backupRevision:preview.body.backupRevision};
  assert.equal((await post({...payload,baseRevision:'stale'})).status,409);
  assert.equal((await post({...payload,backupRevision:'stale'})).status,409);
  assert.equal(await readFile(source,'utf8'),sourceText);
  for(const bad of ['{', JSON.stringify({...backup,version:current.version===3?2:3}),JSON.stringify({...backup,workspaces:null})]) {
    await writeFile(`${source}.backup`,bad);
    const rejected=await post({...payload,backupRevision:createHash('sha256').update(bad).digest('hex')});
    assert.equal(rejected.status,422);assert.equal(await readFile(source,'utf8'),sourceText);
    assert.equal(existsSync(join(configRoot,'generated')),false);assert.equal(existsSync(join(configRoot,'.configuration-write')),false);
  }
  await writeFile(`${source}.backup`,JSON.stringify(backup));
  if(current.version===3)for(const broken of [{hardwareProfileConfirmed:false},{displayBindings:{tall:'MISSING-DISPLAY'}}]) {
    await writeFile(join(stateRoot,'machine.json'),JSON.stringify({...JSON.parse(machine),...broken}));
    assert.equal((await post(payload)).status,422);assert.equal(await readFile(source,'utf8'),sourceText);
    assert.equal(existsSync(join(configRoot,'.configuration-write')),false);
    await writeFile(join(stateRoot,'machine.json'),machine);
  }
  const restored=await post(payload);assert.equal(restored.status,200,JSON.stringify(restored.body));
  assert.deepEqual(JSON.parse(await readFile(source)),backup);
  assert.equal(await readFile(`${source}.backup`,'utf8'),sourceText,'restore must retain the previous current bytes for undo');
  assert.equal(await readFile(join(stateRoot,'machine.json'),'utf8'),machine);
  const runtime=JSON.parse(await readFile(join(configRoot,'generated/runtime.json')));
  assert.equal(runtime.source_version,current.version);assert.equal(runtime.generated.source_version,current.version);
  assert.equal(runtime.generated.source_sha256,createHash('sha256').update(await readFile(source)).digest('hex'));
  let resolution=null;
  if(current.version===3){const setup=(await json(url,'/api/v3/setup',token)).body;resolution={machine:setup.machine,hardware:setup.hardware,snapshot:setup.snapshot};}
  assert.deepEqual(runtime,generationDocument(backup,resolution,await readFile(source,'utf8')));

  if(scenario==='both'){assert.equal(await readFile(join(configRoot,'config.v2.json'),'utf8'),legacyText);assert.equal(await readFile(join(configRoot,'config.v2.json.backup'),'utf8'),legacyText);}
  const undo=await json(url,'/api/config-backup',token);
  assert.equal((await post({version:undo.body.version,baseRevision:undo.body.baseRevision,backupRevision:undo.body.backupRevision})).status,200);
  assert.deepEqual(JSON.parse(await readFile(source)),current);
  if(scenario==='v3-only') {
    const browser=await chromium.launch({headless:true,...(existsSync(systemChrome)?{executablePath:systemChrome}:{})});
    context.after(()=>browser.close());const page=await browser.newPage();
    await page.goto(`${url}?token=${token}&view=hardware`);await page.locator('#v3-save').waitFor();
    await page.locator('.more-menu summary').click();await page.locator('#restore-backup').click();await page.locator('dialog [value=confirm]').click();
    await page.getByText('Restored the previous valid configuration',{exact:true}).waitFor();
    await page.getByText('Restored coding',{exact:true}).first().waitFor();
    await page.locator('#v3-tall-top-percent').fill('57');await page.locator('#v3-tall-top-percent').dispatchEvent('change');
    const savedResponse=page.waitForResponse(response=>response.url().endsWith('/api/v3/save'));
    await page.locator('#v3-save').click();assert.equal((await savedResponse).status(),200);
    const saved=JSON.parse(await readFile(source));assert.equal(saved.workspaces.coding.name,'Restored coding');assert.equal(saved.settings.tallTopPercent,57);
  }
  if(current.version===3){
    const runtimeBefore=await readFile(join(configRoot,'generated/runtime.json'),'utf8');
    const unsupported=await json(url,'/api/capture/merge',token,{method:'POST',body:JSON.stringify({captureId:'unused',config:starterConfig()})});assert.equal(unsupported.status,409);assert.equal(unsupported.body.code,'capture_version_unsupported');
    await mkdir(join(stateRoot,'history'),{recursive:true});
    await writeFile(join(stateRoot,'history/123456789-1234abcd.json'),JSON.stringify({config:starterConfig()}));
    assert.equal((await json(url,'/api/history/123456789-1234abcd/restore',token,{method:'POST'})).status,409);
    const rejected=await json(url,'/api/save',token,{method:'POST',body:JSON.stringify({config:starterConfig(),baseRevision:restored.body.revision})});
    assert.equal(rejected.status,409);assert.equal(await readFile(join(configRoot,'generated/runtime.json'),'utf8'),runtimeBefore);
  }
});

for(const scenario of ['other-version-only','runtime-write-failure','read-back-mismatch'])test(`F2 restore fails closed: ${scenario}`,async context=>{
  const root=await mkdtemp(join(tmpdir(),'spacewright-backup-failure-')),configRoot=join(root,'config'),stateRoot=join(root,'state'),fakeBin=join(root,'bin');
  await Promise.all([mkdir(configRoot),mkdir(stateRoot),mkdir(fakeBin)]);
  const current=starterConfig(),backup=structuredClone(current);backup.metadata.name='Recovery source';
  const file=join(configRoot,'config.v2.json'),source=JSON.stringify(current),backupSource=JSON.stringify(backup);
  await writeFile(file,source);
  await writeFile(scenario==='other-version-only'?join(configRoot,'config.v3.json.backup'):`${file}.backup`,backupSource);
  const extraEnv={};
  if(scenario==='runtime-write-failure') {await mkdir(join(configRoot,'generated/runtime.json'),{recursive:true});}
  if(scenario==='read-back-mismatch') {
    const hook=join(root,'read-back-hook.mjs');
    await writeFile(hook,`import fs from 'node:fs/promises';import{syncBuiltinESMExports}from 'node:module';const read=fs.readFile;fs.readFile=async function(path,...args){const value=await read.call(this,path,...args);if(String(path)==='${configRoot}/generated/runtime.json'){const doc=JSON.parse(value);doc.generated.runtime_sha256='injected-corruption';return JSON.stringify(doc);}return value;};syncBuiltinESMExports();`);
    extraEnv.NODE_OPTIONS=`--import=${hook}`;
  }
  const {child,token,url}=await startServer(configRoot,stateRoot,fakeBin,extraEnv);
  context.after(async()=>{child.kill('SIGTERM');await new Promise(resolve=>child.once('exit',resolve));await rm(root,{recursive:true,force:true});});
  const preview=await json(url,'/api/config-backup',token);
  if(scenario==='other-version-only') {
    assert.equal(preview.status,404);
    const rejected=await json(url,'/api/restore-backup',token,{method:'POST',body:JSON.stringify({version:2,baseRevision:'present',backupRevision:'present'})});
    assert.equal(rejected.status,409);assert.equal(await readFile(file,'utf8'),source);assert.equal(existsSync(join(configRoot,'generated')),false);return;
  }
  assert.equal(preview.status,200);
  const result=await json(url,'/api/restore-backup',token,{method:'POST',body:JSON.stringify({version:2,baseRevision:preview.body.baseRevision,backupRevision:preview.body.backupRevision})});
  assert.equal(result.status,500,JSON.stringify(result.body));assert.equal(existsSync(join(configRoot,'.configuration-write')),true);
  assert.equal(await readFile(`${file}.backup`,'utf8'),source);
  const refused=await json(url,'/api/config',token);assert.equal(refused.status,500);assert.match(refused.body.error,/incomplete|in progress/);
});
