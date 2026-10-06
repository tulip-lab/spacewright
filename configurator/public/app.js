import { confirmAction, promptValue } from './dialog.js';

const token = new URLSearchParams(location.search).get('token');
const headers = { 'content-type': 'application/json', 'x-spacewright-token': token || '' };
const state = { config: null, savedConfig: null, serverRevision: null, source: null, requiresInitialSave: false, legacyAvailable: false, machine: { version: 1, displayBindings: {} }, view: new URLSearchParams(location.search).get('view') || 'current', mode: new URLSearchParams(location.search).get('mode') || 'wide', selectedWorkspace: null, shortcutView: 'workspace', workspaceSearch: '', workspaceTab: 'apps', appSearch: '', appInventory: null, externalShortcuts: [], shortcutSources: [], autoImportedShortcuts: 0, recordingCleanup: null, runtime: null, liveSnapshot: null, livePlan: null, runPreview: null, dirty: false, importChanges: [], undoStack: [], redoStack: [], lastDraft: null };
const root = document.querySelector('#workspace');
let renderEpoch = 0;
let undoBatchTimer = null;

function previewConfig() {
  return {
    version: 2,
    metadata: { name: 'SpaceWright preview' },
    apps: {
      code: { name: 'Visual Studio Code', match: { appNames: ['Code', 'Visual Studio Code'] } },
      chatgpt: { name: 'ChatGPT', match: { appNames: ['ChatGPT'] } },
      hermes: { name: 'Hermes', match: { appNames: ['Hermes'] } },
      terminal: { name: 'Terminal', match: { appNames: ['Warp', 'Terminal'] } }
    },
    aiProviders: {
      hermes: { name: 'Hermes', app: 'hermes' },
      chatgpt: { name: 'ChatGPT', app: 'chatgpt' }
    },
    aiRouting: {
      assignments: { coding: { role: 'assistant', provider: 'chatgpt', overrides: {} } },
      fallbackWorkspace: 'coding', focusOwner: true
    },
    displayRoles: {
      primary: { name: 'MacBook display', portableMatch: { builtIn: true } },
      task: { name: 'Studio display', portableMatch: { orientation: 'wide' } }
    },
    workspaces: {
      coding: {
        name: 'Coding', spaceLabel: 'coding',
        windows: {
          editor: { app: 'code', required: true, selector: { movable: true } },
          assistant: { app: 'chatgpt', required: false, selector: { movable: true } },
          terminal: { app: 'terminal', required: false, selector: { movable: true } }
        },
        variants: {
          solo: { layout: { type: 'window', role: 'editor' } },
          wide: { layout: { type: 'split', direction: 'columns', weights: [2, 1], children: [{ type: 'window', role: 'editor' }, { type: 'split', direction: 'rows', weights: [1, 1], children: [{ type: 'window', role: 'assistant' }, { type: 'window', role: 'terminal' }] }] } },
          tall: { layout: { type: 'split', direction: 'rows', weights: [1, 1], children: [{ type: 'window', role: 'editor' }, { type: 'window', role: 'assistant' }] } }
        }
      },
      research: {
        name: 'Research', spaceLabel: 'research',
        windows: { library: { app: 'code', required: true }, notes: { app: 'chatgpt', required: false } },
        variants: {
          solo: { layout: { type: 'window', role: 'library' } },
          wide: { layout: { type: 'split', direction: 'columns', weights: [1, 1], children: [{ type: 'window', role: 'library' }, { type: 'window', role: 'notes' }] } },
          tall: { layout: { type: 'split', direction: 'rows', weights: [1, 1], children: [{ type: 'window', role: 'library' }, { type: 'window', role: 'notes' }] } }
        }
      }
    },
    modes: {
      solo: { displays: [{ role: 'primary', workspaceOrder: ['coding', 'research'] }] },
      wide: { displays: [{ role: 'primary', workspaceOrder: [] }, { role: 'task', workspaceOrder: ['research', 'coding'] }] },
      tall: { displays: [{ role: 'primary', workspaceOrder: [] }, { role: 'task', workspaceOrder: ['coding', 'research'] }] }
    },
    shortcuts: [
      { id: 'preview-wide', keys: { modifiers: ['alt', 'shift'], key: 'w' }, action: { type: 'activateMode', mode: 'wide' } }
    ]
  };
}

const escapeHtml = (value = '') => String(value).replace(/[&<>"]/g, (char) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[char]);
const ids = (object) => Object.keys(object || {});
const title = (kicker, heading, copy, actions = '') => `<div class="section-head"><div><p class="kicker">${kicker}</p><h2>${heading}</h2><p>${copy}</p></div>${actions}</div>`;

function markDirty() {
  if (state.lastDraft && JSON.stringify(state.lastDraft) !== JSON.stringify(state.config)) {
    if (!undoBatchTimer) state.undoStack.push(structuredClone(state.lastDraft));
    state.undoStack = state.undoStack.slice(-50);
    state.redoStack = [];
    state.lastDraft = structuredClone(state.config);
    clearTimeout(undoBatchTimer);
    undoBatchTimer = setTimeout(() => { undoBatchTimer = null; syncPersistenceControls(); }, 500);
  }
  state.dirty = state.requiresInitialSave || JSON.stringify(state.config) !== JSON.stringify(state.savedConfig);
  state.runPreview = null;
  document.querySelector('#status').textContent = state.dirty ? 'Unsaved changes' : 'Local · read/write';
  syncPersistenceControls();
}

function markClean(status = 'Local · read/write') {
  clearTimeout(undoBatchTimer); undoBatchTimer = null;
  state.dirty = state.requiresInitialSave;
  state.undoStack = [];
  state.redoStack = [];
  state.lastDraft = structuredClone(state.config);
  document.querySelector('#status').textContent = state.dirty ? 'Starter · unsaved' : status;
  syncPersistenceControls();
}

function syncPersistenceControls() {
  const draft = document.querySelector('#draft-state');
  const save = document.querySelector('#save');
  const undo = document.querySelector('#undo');
  const redo = document.querySelector('#redo');
  if (!draft || !save) return;
  draft.textContent = state.dirty ? 'Draft has unsaved changes' : 'Saved configuration';
  draft.classList.toggle('dirty', state.dirty);
  save.disabled = !state.dirty;
  undo.disabled = !state.undoStack.length;
  redo.disabled = !state.redoStack.length;
}

function moveDraftHistory(direction) {
  clearTimeout(undoBatchTimer); undoBatchTimer = null;
  const source = direction === 'undo' ? state.undoStack : state.redoStack;
  const target = direction === 'undo' ? state.redoStack : state.undoStack;
  if (!source.length) return;
  target.push(structuredClone(state.config));
  state.config = source.pop();
  state.lastDraft = structuredClone(state.config);
  state.runPreview = null;
  state.dirty = state.requiresInitialSave || JSON.stringify(state.config) !== JSON.stringify(state.savedConfig);
  document.querySelector('#status').textContent = state.dirty ? 'Unsaved changes' : 'Local · read/write';
  render();
}

function viewIsCurrent(view, epoch) { return state.view === view && renderEpoch === epoch; }

function validId(value) { return /^[a-z][a-z0-9_]*$/.test(value); }
function renameKey(object, from, to) { object[to] = object[from]; delete object[from]; }
function visitLayout(node, callback) { if (!node) return; callback(node); for (const child of node.children || []) visitLayout(child, callback); for (const region of node.regions || []) callback(region); }

async function requestId(label, current, collection) {
  const next = await promptValue(label, current, 'Use a lowercase ID beginning with a letter; digits and underscores are allowed.');
  if (!next || next === current) return null;
  if (!validId(next)) return toast('Use a lowercase ID beginning with a letter; digits and underscores are allowed.', true);
  if (collection[next]) return toast(`ID “${next}” already exists.`, true);
  return next;
}

function syncUrl() {
  const url = new URL(location.href);
  url.searchParams.set('view', state.view);
  url.searchParams.set('mode', state.mode);
  history.replaceState(null, '', url);
}

function changedSections(before, after) {
  return ['metadata', 'apps', 'aiProviders', 'aiRouting', 'displayRoles', 'workspaces', 'modes', 'shortcuts', 'profiles', 'rules', 'settings'].filter((key) => JSON.stringify(before?.[key]) !== JSON.stringify(after?.[key]));
}

const MODES = ['solo', 'tall', 'wide'];
const modifierOrder = ['ctrl', 'alt', 'shift', 'cmd', 'fn'];
function chordKey(keys = {}) { return `${[...(keys.modifiers || [])].sort((a, b) => modifierOrder.indexOf(a) - modifierOrder.indexOf(b)).join('+')}+${String(keys.key || '').toLowerCase()}`; }
function chordLabel(keys) { return [...(keys?.modifiers || []).map((item) => ({ ctrl: '⌃', alt: '⌥', shift: '⇧', cmd: '⌘', fn: 'fn' })[item] || item), keys?.key || '?'].join(' '); }
function shortcutConflicts(config = state.config) {
  const seen = new Map(); const conflicts = [];
  for (const shortcut of config.shortcuts || []) { const chord = chordKey(shortcut.keys); if (seen.has(chord)) conflicts.push([seen.get(chord), shortcut]); else seen.set(chord, shortcut); }
  return conflicts;
}
function matchingShortcut(workspaceId, mode) { return (state.config.shortcuts || []).find((item) => item.action.type === 'activateWorkspace' && item.action.workspace === workspaceId && item.action.mode === mode); }
function externalShortcut(workspaceId, mode) { return state.externalShortcuts.find((item) => item.action.type === 'activateWorkspace' && item.action.workspace === workspaceId && item.action.mode === mode); }
function bindingConflict(shortcut) { return shortcut && shortcutConflicts().find((pair) => pair.includes(shortcut))?.find((item) => item !== shortcut); }
function shortcutStatus(shortcut, external) { const conflict = bindingConflict(shortcut); return conflict ? `Conflict with ${actionLabel(conflict)}` : shortcut ? 'Configured' : external ? 'External binding · not yet imported' : 'Not configured'; }
function importableExternalShortcuts() {
  const shortcuts=state.config.shortcuts||[];
  return state.externalShortcuts.filter((item)=>item.action.type!=='externalCommand'&&!shortcuts.some((existing)=>chordKey(existing.keys)===chordKey(item.keys))&&(item.action.type==='activateMode'||state.config.workspaces[item.action.workspace]?.variants?.[item.action.mode]));
}
function autoImportExternalShortcuts() {
  const imported=importableExternalShortcuts();
  for(const item of imported)(state.config.shortcuts ||= []).push({id:crypto.randomUUID(),keys:structuredClone(item.keys),action:structuredClone(item.action)});
  state.autoImportedShortcuts=imported.length;
  if(imported.length)state.dirty=true;
}
function workspacePlacement(config, mode, workspaceId) {
  for (const display of config?.modes?.[mode]?.displays || []) { const index = display.workspaceOrder.indexOf(workspaceId); if (index >= 0) return { role: display.role, index }; }
  return null;
}
function actionLabel(shortcut, config = state.config) {
  if (shortcut.action.type === 'activateWorkspace') return `${config.workspaces[shortcut.action.workspace]?.name || shortcut.action.workspace} · ${shortcut.action.mode}`;
  if (shortcut.action.type === 'activateMode') return `Switch to ${shortcut.action.mode}`;
  return `External command · ${shortcut.action.command}`;
}
function humanWarning(warning) {
  const layout = warning.match(/^workspaces\.([a-z0-9_]+)\.variants\.(solo|tall|wide)\.layout does not place optional window role "([^"]+)"$/);
  if (layout) { const [,workspaceId,mode,role]=layout; const workspace=state.config.workspaces[workspaceId]; const app=state.config.apps[workspace?.windows?.[role]?.app]?.name||role; return { workspaceId, mode, title:`${workspace?.name||workspaceId} · ${mode}`, text:`Optional window ${app} is not in this layout. Running ${mode} will leave it unarranged.` }; }
  return { title:'Configuration warning', text:warning };
}

function planPreview(result) {
  const comparison = result.comparison;
  const plan = result.plan;
  const actionRows = (plan.actions || []).map((action) => `<li><b>${escapeHtml(action.type.replaceAll('_', ' '))}</b> ${escapeHtml(action.workspaceId || action.mode || action.target?.id || '')}${action.role ? ` · ${escapeHtml(action.role)}` : ''}</li>`).join('');
  const commandRows = (plan.executionSteps || []).map((step) => `<li><code>spacewright ${escapeHtml(step.command.join(' '))}</code></li>`).join('');
  return `<section class="comparison-summary ${comparison.converged ? 'converged' : ''}"><div><p class="kicker">Dry run · no desktop changes</p><h3>${comparison.counts.blocker} blockers · ${comparison.counts.change} changes · ${comparison.counts.warning} warnings</h3><p>${comparison.converged ? '✓ Converged.' : plan.executable ? 'Ready to apply.' : 'Blocked.'} Plan ${escapeHtml(plan.planId)}.</p></div></section><div class="change-summary"><strong>${plan.actions.length ? 'Planned changes' : 'No changes required'}</strong>${actionRows ? `<ol>${actionRows}</ol>` : ''}${commandRows ? `<details><summary>Exact commands</summary><ol>${commandRows}</ol></details>` : ''}</div>`;
}

function toast(message, error = false) {
  const node = document.querySelector('#toast-template').content.firstElementChild.cloneNode(true);
  node.textContent = message;
  if (error) node.style.background = '#9f2d1c';
  document.body.append(node);
  setTimeout(() => node.remove(), 4200);
}

function closeRecording() { state.recordingCleanup?.(); state.recordingCleanup = null; }
function recordShortcut(onComplete) {
  closeRecording();
  const overlay = document.createElement('dialog');
  overlay.className = 'modal-dialog modal-dialog-wide';
  overlay.innerHTML = `<section class="recording-dialog" aria-labelledby="recording-title"><p class="kicker">Keyboard input</p><h2 id="recording-title">Recording shortcut</h2><div class="recording-keys" id="recording-keys">Press a combination…</div><p>Esc cancels. Function keys F1–F12, numbers and modifiers are supported. Browser events cannot reliably detect Fn, so use the selector below when needed.</p><div class="manual-key"><label>Manual key <select id="manual-key"><option value="">Choose…</option>${['0','1','2','3','4','5','6','7','8','9',...Array.from({length:12},(_,i)=>`F${i+1}`)].map((key)=>`<option>${key}</option>`).join('')}</select></label><label><input type="checkbox" id="manual-fn"> fn</label></div><div class="actions"><button class="quiet" id="cancel-recording">Cancel</button></div></section>`;
  document.body.append(overlay);
  let candidate = null;
  const cleanup = () => { removeEventListener('keydown', listener, true); if (overlay.open) overlay.close(); overlay.remove(); state.recordingCleanup = null; };
  const finish = (keys) => { cleanup(); onComplete(keys); };
  const listener = (event) => {
    event.preventDefault(); event.stopPropagation();
    if (event.key === 'Escape') return cleanup();
    const modifiers = [['ctrlKey','ctrl'],['altKey','alt'],['shiftKey','shift'],['metaKey','cmd']].filter(([field]) => event[field]).map(([,name]) => name);
    if (['Control','Alt','Shift','Meta','Fn'].includes(event.key)) { overlay.querySelector('#recording-keys').textContent = modifiers.length ? chordLabel({ modifiers, key: '…' }) : 'Press a complete combination…'; return; }
    const key = /^F(?:[1-9]|1[0-2])$/i.test(event.key) ? event.key.toUpperCase() : event.key.length === 1 ? event.key.toLowerCase() : event.key;
    candidate = { modifiers, key }; overlay.querySelector('#recording-keys').textContent = chordLabel(candidate); setTimeout(() => state.recordingCleanup && finish(candidate), 280);
  };
  addEventListener('keydown', listener, true);
  overlay.addEventListener('cancel', (event) => { event.preventDefault(); cleanup(); });
  overlay.onclick = (event) => { if (event.target === overlay) cleanup(); };
  overlay.querySelector('#cancel-recording').onclick = cleanup;
  overlay.querySelector('#manual-key').onchange = (event) => { if (!event.target.value) return; const modifiers = overlay.querySelector('#manual-fn').checked ? ['fn'] : []; finish({ modifiers, key: event.target.value }); };
  state.recordingCleanup = cleanup;
  overlay.showModal();
}

function openNewWorkspaceDialog() {
  const overlay=document.createElement('dialog');overlay.className='modal-dialog modal-dialog-wide';
  const roleOptions=(state.config.modes[state.mode]?.displays||[]).map((display,index)=>`<option value="${index}">${escapeHtml(state.config.displayRoles[display.role]?.name||display.role)}</option>`).join('');
  overlay.innerHTML=`<section class="app-picker"><p class="kicker">New Workspace</p><h2>Add directly to work_${escapeHtml(state.mode)}</h2><div class="field"><label for="new-workspace-name">Workspace name</label><input id="new-workspace-name" autocomplete="off" value="New Workspace"></div><div class="field"><label for="new-workspace-id">Stable ID</label><input id="new-workspace-id" autocomplete="off" value="new_workspace"></div><div class="field"><label for="new-workspace-app">Primary application</label><select id="new-workspace-app">${ids(state.config.apps).map((id)=>`<option value="${id}">${escapeHtml(state.config.apps[id].name)}</option>`).join('')}</select></div><div class="field"><label for="new-workspace-display">Add to display</label><select id="new-workspace-display">${roleOptions}</select></div><fieldset><legend>Available modes</legend>${MODES.map((mode)=>`<label><input type="checkbox" data-new-mode="${mode}" ${mode===state.mode?'checked':''}> ${mode}</label>`).join('')}</fieldset><p class="layout-hint">Only the selected modes receive a layout. Other modes can be enabled later from the Workspace editor.</p><div class="actions"><button class="primary" id="confirm-new-workspace">Create Workspace</button><button class="quiet" id="cancel-new-workspace">Cancel</button></div></section>`;
  document.body.append(overlay); const close=()=>{if(overlay.open)overlay.close();overlay.remove();}; overlay.addEventListener('cancel',(event)=>{event.preventDefault();close();}); overlay.onclick=(event)=>{if(event.target===overlay)close();};overlay.querySelector('#cancel-new-workspace').onclick=close;
  overlay.querySelector('#confirm-new-workspace').onclick=()=>{const name=overlay.querySelector('#new-workspace-name').value.trim();const id=overlay.querySelector('#new-workspace-id').value.trim();if(!name||!validId(id)||state.config.workspaces[id])return toast('Choose a name and a unique lowercase stable ID.',true);const app=overlay.querySelector('#new-workspace-app').value;const modes=[...overlay.querySelectorAll('[data-new-mode]:checked')].map((input)=>input.dataset.newMode);if(!modes.length)return toast('Select at least one available mode.',true);state.config.workspaces[id]={name,spaceLabel:id,windows:{primary:{app,required:true,selector:{movable:true}}},variants:Object.fromEntries(modes.map((mode)=>[mode,{layout:{type:'window',role:'primary'}}]))};for(const mode of modes){const displays=state.config.modes[mode].displays;const target=mode===state.mode?Number(overlay.querySelector('#new-workspace-display').value):0;displays[target].workspaceOrder.push(id);}state.selectedWorkspace=id;markDirty();close();render();toast(`${name} was added to work_${state.mode}.`);};
  overlay.showModal();
  overlay.querySelector('#new-workspace-name').focus();
}

async function request(path, options = {}) {
  const response = await fetch(path, { ...options, headers: { ...headers, ...(options.headers || {}) } });
  const payload = await response.json();
  if (!response.ok) throw Object.assign(new Error(payload.error || payload.errors?.join('\n') || 'Request failed'), { payload });
  return payload;
}

function modeSwitch() {
  return `<div class="mode-switch" role="group" aria-label="Workspace mode">${['solo', 'wide', 'tall'].map((mode) => `<button data-mode="${mode}" aria-pressed="${state.mode === mode}" class="${state.mode === mode ? 'active' : ''}">${mode}</button>`).join('')}</div>`;
}

function onboarding() {
  const steps = [
    ['Applications', Object.keys(state.config.apps).length > 0],
    ['Display roles', Object.keys(state.config.displayRoles).length > 0],
    ['Workspaces', Object.keys(state.config.workspaces).length > 0],
    ['3 mode maps', ['solo', 'wide', 'tall'].every((mode) => state.config.modes[mode]?.displays?.length)],
    ['Shortcuts', (state.config.shortcuts || []).length > 0 || state.externalShortcuts.length > 0]
  ];
  const complete = steps.filter(([, done]) => done).length;
  return `<aside class="onboarding" aria-label="Configuration progress"><div><p class="kicker">Setup progress</p><strong>${complete} / ${steps.length} ready</strong></div>${steps.map(([label, done]) => `<span class="${done ? 'done' : ''}">${done ? '✓' : '○'} ${label}</span>`).join('')}</aside>`;
}

function mapView() {
  const mode = state.config.modes[state.mode] || { displays: [] };
  const assigned = new Set(mode.displays.flatMap((display) => display.workspaceOrder));
  const unassigned = ids(state.config.workspaces).filter((id) => !assigned.has(id));
  const destinationOptions = (current) => `<option value="unassigned" ${current === 'unassigned' ? 'selected' : ''}>Unassigned</option>${mode.displays.map((display, index) => `<option value="${index}" ${String(current) === String(index) ? 'selected' : ''}>${escapeHtml(state.config.displayRoles[display.role]?.name || display.role)}</option>`).join('')}`;
  const chip = (workspaceId, from, index) => {
    const workspace = state.config.workspaces[workspaceId];
    const assignedLane = from !== 'unassigned';
    return `<div class="drop-slot" data-drop-lane="${from}" data-drop-index="${index}"></div><div class="workspace-chip" draggable="true" data-workspace="${workspaceId}" data-from="${from}"><span class="order">${assignedLane ? String(index + 1).padStart(2, '0') : '—'}</span><span><strong>${escapeHtml(workspace?.name || workspaceId)}</strong><small>${escapeHtml(workspaceId)}</small></span><span class="chip-controls"><select data-relocate="${workspaceId}" data-current-lane="${from}" aria-label="Display for ${escapeHtml(workspace?.name || workspaceId)}">${destinationOptions(from)}</select>${assignedLane ? `<span class="chip-actions"><button class="quiet" data-move-up="${workspaceId}" data-lane="${from}" aria-label="Move ${escapeHtml(workspace?.name || workspaceId)} up">↑</button><button class="quiet" data-move-down="${workspaceId}" data-lane="${from}" aria-label="Move ${escapeHtml(workspace?.name || workspaceId)} down">↓</button></span>` : ''}</span></div>`;
  };
  const lane = (items, laneId) => `${items.map((workspaceId, index) => chip(workspaceId, laneId, index)).join('')}<div class="drop-slot end" data-drop-lane="${laneId}" data-drop-index="${items.length}">${items.length ? 'Drop at end' : 'Drop a workspace here'}</div>`;
  const selectedCount=mode.displays.reduce((count,display)=>count+display.workspaceOrder.length,0);
  const managedModeShortcut=(state.config.shortcuts||[]).find((item)=>item.action.type==='activateMode'&&item.action.mode===state.mode);const externalModeShortcut=state.externalShortcuts.find((item)=>item.action.type==='activateMode'&&item.action.mode===state.mode);
  root.innerHTML = title('Work mode configuration', `Choose workspaces for work_${state.mode}`, `This is the source of truth for work_${state.mode}. Drag workspaces into a display lane to include them; move them to Unassigned to exclude them. Lane order is both Space order and execution order.`, `<div class="mode-title-actions">${modeSwitch()}<button class="primary" id="new-workspace-in-mode">+ New Workspace</button></div>`) + `<aside class="mode-plan-callout"><div><strong>work_${escapeHtml(state.mode)} currently runs ${selectedCount} workspace${selectedCount===1?'':'s'}</strong><span>Changes remain a draft until you save the configuration.</span></div><div class="mode-shortcut-inline"><small>Mode shortcut</small><b>${managedModeShortcut||externalModeShortcut?escapeHtml(chordLabel((managedModeShortcut||externalModeShortcut).keys)):'Not configured'}</b>${!managedModeShortcut&&externalModeShortcut?'<em>Imported from skhd</em>':''}<button class="quiet" id="set-mode-shortcut">${managedModeShortcut?'Change shortcut':externalModeShortcut?'Use or change':'Set shortcut'}</button></div></aside>` + onboarding() +
    `<div class="display-deck">${mode.displays.map((display, displayIndex) => `
      <article class="display-card"><div class="display-screen" data-display="${displayIndex}">
        <div class="display-title"><span><strong>${escapeHtml(state.config.displayRoles[display.role]?.name || display.role)}</strong><small>role · ${escapeHtml(display.role)}</small></span><span>${display.workspaceOrder.length} workspace${display.workspaceOrder.length === 1 ? '' : 's'}</span></div>
        ${state.machine.displayBindings[display.role] ? `<p class="display-binding"><span class="badge">Bound</span> ${escapeHtml(state.machine.displayBindings[display.role])}</p>` : '<p class="display-binding unbound">Not bound to a physical display on this Mac</p>'}
        <div class="lane">${lane(display.workspaceOrder, displayIndex)}</div>
      </div></article>`).join('')}<article class="card unassigned-card"><div class="display-title"><span>Unassigned</span><span>${unassigned.length}</span></div><p>Keep a workspace here when it should not open in this mode.</p><div class="lane">${lane(unassigned, 'unassigned')}</div></article><article class="card"><h3>Add Display Lane</h3><div class="field"><label for="lane-role">Display role</label><select id="lane-role" name="lane-role">${ids(state.config.displayRoles).map((role) => `<option value="${role}">${escapeHtml(state.config.displayRoles[role].name)}</option>`).join('')}</select></div><button id="add-lane" class="primary">+ Add to ${state.mode}</button></article></div>`;
  root.querySelectorAll('[data-mode]').forEach((button) => button.onclick = () => { state.mode = button.dataset.mode; render(); });
  root.querySelector('#new-workspace-in-mode').onclick=openNewWorkspaceDialog;
  root.querySelector('#set-mode-shortcut').onclick=()=>{if(!managedModeShortcut&&externalModeShortcut){const conflict=(state.config.shortcuts||[]).find((item)=>chordKey(item.keys)===chordKey(externalModeShortcut.keys));if(!conflict){(state.config.shortcuts||[]).push({id:crypto.randomUUID(),keys:structuredClone(externalModeShortcut.keys),action:{type:'activateMode',mode:state.mode}});markDirty();render();return;}}recordShortcut((keys)=>{const conflict=(state.config.shortcuts||[]).find((item)=>item!==managedModeShortcut&&chordKey(item.keys)===chordKey(keys));if(conflict)return toast(`${chordLabel(keys)} already triggers ${actionLabel(conflict)}.`,true);if(managedModeShortcut)managedModeShortcut.keys=keys;else(state.config.shortcuts||[]).push({id:crypto.randomUUID(),keys,action:{type:'activateMode',mode:state.mode}});markDirty();render();});};
  let dragged;
  const placeWorkspace = (id, target, index) => {
    const sourceLane = mode.displays.findIndex((display) => display.workspaceOrder.includes(id));
    const sourceIndex = sourceLane < 0 ? -1 : mode.displays[sourceLane].workspaceOrder.indexOf(id);
    let insertionIndex = Number(index);
    if (target !== 'unassigned' && sourceLane === Number(target) && sourceIndex < insertionIndex) insertionIndex--;
    for (const display of mode.displays) display.workspaceOrder = display.workspaceOrder.filter((workspaceId) => workspaceId !== id);
    if (target !== 'unassigned') {
      const targetDisplay = mode.displays[Number(target)];
      targetDisplay.workspaceOrder.splice(insertionIndex, 0, id);
      const runtime = state.config.workspaces[id]?.variants?.[state.mode]?.runtime;
      if (runtime?.displayRole) runtime.displayRole = targetDisplay.role === 'primary' ? 'primary' : `${targetDisplay.role}__${state.mode}`;
    }
    markDirty(); render();
  };
  root.querySelectorAll('.workspace-chip').forEach((node) => node.ondragstart = () => { dragged = { id: node.dataset.workspace }; });
  root.querySelectorAll('[data-drop-lane]').forEach((slot) => {
    slot.ondragover = (event) => { event.preventDefault(); slot.classList.add('active'); slot.textContent = `Place on ${state.config.displayRoles[mode.displays[Number(slot.dataset.dropLane)]?.role]?.name || 'Unassigned'} as Space ${Number(slot.dataset.dropIndex) + 1}`; };
    slot.ondragleave = () => slot.classList.remove('active');
    slot.ondrop = (event) => {
      event.preventDefault();
      if (!dragged) return;
      placeWorkspace(dragged.id, slot.dataset.dropLane, slot.dataset.dropIndex);
    };
  });
  root.querySelectorAll('[data-relocate]').forEach((select) => select.onchange = () => {
    const target = select.value;
    const index = target === 'unassigned' ? 0 : mode.displays[Number(target)].workspaceOrder.length;
    placeWorkspace(select.dataset.relocate, target, index);
  });
  root.querySelector('#add-lane').onclick = () => {
    const role = root.querySelector('#lane-role').value;
    if (mode.displays.some((display) => display.role === role)) return toast(`${role} already has a lane`, true);
    mode.displays.push({ role, workspaceOrder: [] });
    markDirty();
    render();
  };
  for (const direction of ['up', 'down']) root.querySelectorAll(`[data-move-${direction}]`).forEach((button) => button.onclick = (event) => {
    event.stopPropagation();
    const order = mode.displays[Number(button.dataset.lane)].workspaceOrder;
    const index = order.indexOf(button.dataset[`move${direction[0].toUpperCase()}${direction.slice(1)}`]);
    const target = direction === 'up' ? index - 1 : index + 1;
    if (index < 0 || target < 0 || target >= order.length) return;
    [order[index], order[target]] = [order[target], order[index]];
    markDirty(); render();
  });
}

async function displaysView() {
  root.innerHTML = title('Display roles', 'Name the surfaces', 'Roles are portable. Connected UUIDs remain machine-local and are never written into the portable configuration.', '<button id="discover" class="quiet">Discover connected displays</button>') +
    `<div class="cards">${Object.entries(state.config.displayRoles).map(([id, role]) => `<article class="card"><p class="kicker" translate="no">${escapeHtml(id)}</p><h3>${escapeHtml(role.name)}</h3>${state.machine.displayBindings[id] ? `<p><span class="badge">Bound on this Mac</span></p><details class="machine-details"><summary>Machine Details</summary><p class="machine-id">UUID · ${escapeHtml(state.machine.displayBindings[id])}</p></details>` : '<p class="unbound">Not bound on this Mac</p>'}<div class="field"><label for="display-name-${id}">Display name</label><input id="display-name-${id}" name="display-name-${id}" autocomplete="off" data-display-name="${id}" value="${escapeHtml(role.name)}"></div><div class="field"><label for="display-orientation-${id}">Portable match</label><select id="display-orientation-${id}" name="display-orientation-${id}" data-orientation="${id}"><option value="">Any orientation</option><option value="wide" ${role.portableMatch?.orientation === 'wide' ? 'selected' : ''}>Wide</option><option value="tall" ${role.portableMatch?.orientation === 'tall' ? 'selected' : ''}>Tall</option></select></div><label><input type="checkbox" data-built-in="${id}" ${role.portableMatch?.builtIn ? 'checked' : ''}> Built-in display</label><div class="actions"><button class="quiet" data-rename-display="${id}">Rename ID</button><button class="danger" data-delete-display="${id}">Delete Role</button></div></article>`).join('')}<article class="card"><h3>Add display role</h3><button id="add-display-role" class="primary">+ New role</button></article></div><div id="discovery"></div>`;
  root.querySelectorAll('[data-display-name]').forEach((input) => input.oninput = () => state.config.displayRoles[input.dataset.displayName].name = input.value);
  root.querySelectorAll('[data-orientation]').forEach((select) => select.onchange = () => {
    const match = state.config.displayRoles[select.dataset.orientation].portableMatch ||= {};
    if (select.value) match.orientation = select.value; else delete match.orientation;
  });
  root.querySelectorAll('[data-built-in]').forEach((input) => input.onchange = () => {
    const match = state.config.displayRoles[input.dataset.builtIn].portableMatch ||= {};
    if (input.checked) match.builtIn = true; else delete match.builtIn;
  });
  root.querySelector('#add-display-role').onclick = () => { let index = 1; while (state.config.displayRoles[`display_${index}`]) index++; state.config.displayRoles[`display_${index}`] = { name: `Display ${index}`, portableMatch: {} }; markDirty(); render(); };
  root.querySelectorAll('[data-rename-display]').forEach((button) => button.onclick = async () => {
    const oldId = button.dataset.renameDisplay; const newId = await requestId('New Display Role ID', oldId, state.config.displayRoles); if (!newId) return;
    renameKey(state.config.displayRoles, oldId, newId);
    for (const mode of Object.values(state.config.modes)) for (const display of mode.displays) if (display.role === oldId) display.role = newId;
    if (state.machine.displayBindings[oldId]) { state.machine.displayBindings[newId] = state.machine.displayBindings[oldId]; delete state.machine.displayBindings[oldId]; await request('/api/display-bindings', { method: 'POST', body: JSON.stringify({ displayBindings: state.machine.displayBindings, config: state.config }) }); }
    markDirty(); render();
  });
  root.querySelectorAll('[data-delete-display]').forEach((button) => button.onclick = async () => {
    const id = button.dataset.deleteDisplay; const references = Object.entries(state.config.modes).filter(([, mode]) => mode.displays.some((display) => display.role === id)).map(([mode]) => mode);
    if (references.length) return toast(`Display role “${id}” is used by modes: ${references.join(', ')}. Move those lanes first.`, true);
    if (!await confirmAction(`Delete display role “${id}”?`, { confirmLabel: 'Delete Role', danger: true })) return;
    delete state.config.displayRoles[id];
    if (state.machine.displayBindings[id]) { delete state.machine.displayBindings[id]; await request('/api/display-bindings', { method: 'POST', body: JSON.stringify({ displayBindings: state.machine.displayBindings, config: state.config }) }); }
    markDirty(); render();
  });
  root.querySelector('#discover').onclick = async () => {
    const target = root.querySelector('#discovery'); target.innerHTML = '<p>Reading yabai display inventory…</p>';
    try {
      const result = await request('/api/displays');
      target.innerHTML = result.displays.length ? `<div class="cards display-inventory">${result.displays.map((display) => { const frame=display.frame||{}; const orientation=Number(frame.h||0)>Number(frame.w||0)?'Portrait':'Landscape'; const boundRole=Object.entries(state.machine.displayBindings).find(([,uuid])=>uuid===display.uuid)?.[0]; return `<article class="card"><p class="kicker">Connected display</p><h3>${escapeHtml(display.label || `Display ${display.index}`)}</h3><div class="display-facts"><span>Position <strong>${frame.x??'?'} × ${frame.y??'?'}</strong></span><span>Resolution <strong>${frame.w||'?'} × ${frame.h||'?'}</strong></span><span>Orientation <strong>${orientation}</strong></span><span>Role <strong>${escapeHtml(boundRole ? state.config.displayRoles[boundRole]?.name || boundRole : 'Unbound')}</strong></span></div><details class="machine-details"><summary>Machine Details</summary><p class="machine-id">UUID · ${escapeHtml(display.uuid || 'Unavailable')}</p></details><div class="field"><label>Bind to role</label><select data-ui-only aria-label="Bind display ${escapeHtml(display.index)} to role" name="binding-${escapeHtml(display.index)}" data-binding-role="${escapeHtml(display.uuid || '')}">${ids(state.config.displayRoles).map((role) => `<option value="${role}" ${state.machine.displayBindings[role] === display.uuid ? 'selected' : ''}>${escapeHtml(state.config.displayRoles[role].name)}</option>`).join('')}</select></div><button class="primary" data-bind-display="${escapeHtml(display.uuid || '')}" data-display-index="${escapeHtml(display.index)}" ${display.uuid ? '' : 'disabled'}>Bind on This Mac</button></article>`; }).join('')}</div>` : `<div class="errors">${escapeHtml(result.message || 'No displays returned by yabai')}</div>`;
      target.querySelectorAll('[data-bind-display]').forEach((button) => button.onclick = async () => {
        const uuid = button.dataset.bindDisplay;
        const role = target.querySelector(`[data-binding-role="${CSS.escape(uuid)}"]`).value;
        for (const [boundRole, boundUuid] of Object.entries(state.machine.displayBindings)) if (boundUuid === uuid) delete state.machine.displayBindings[boundRole];
        state.machine.displayBindings[role] = uuid;
        try {
          const saved = await request('/api/display-bindings', { method: 'POST', body: JSON.stringify({ displayBindings: state.machine.displayBindings, config: state.config }) });
          state.machine = saved.machine;
          toast(`Bound display ${button.dataset.displayIndex} to ${role}`);
          render();
        } catch (error) { toast(error.message, true); }
      });
    } catch (error) { target.innerHTML = `<div class="errors">${escapeHtml(error.message)}</div>`; }
  };
}

function layoutTemplate(kind, roles) {
  const [a, b, c, d] = roles;
  if (kind === 'full' || !b) return { type: 'window', role: a };
  if (kind === 'half-columns') return { type: 'split', direction: 'columns', weights: [1, 1], children: [{ type: 'window', role: a }, { type: 'window', role: b }] };
  if (kind === 'half-rows') return { type: 'split', direction: 'rows', weights: [1, 1], children: [{ type: 'window', role: a }, { type: 'window', role: b }] };
  if (kind === 'third-columns') return { type: 'split', direction: 'columns', weights: [1, 2], children: [{ type: 'window', role: b }, { type: 'window', role: a }] };
  if (kind === 'two-third-columns') return { type: 'split', direction: 'columns', weights: [2, 1], children: [{ type: 'window', role: a }, { type: 'window', role: b }] };
  if (kind === 'right-stack' && c) return { type: 'split', direction: 'columns', weights: [1, 2], children: [{ type: 'window', role: a }, { type: 'split', direction: 'rows', weights: [1, 1], children: [{ type: 'window', role: b }, { type: 'window', role: c }] }] };
  if (kind === 'left-stack' && c) return { type: 'split', direction: 'columns', weights: [1, 2], children: [{ type: 'split', direction: 'rows', weights: [1, 1], children: [{ type: 'window', role: b }, { type: 'window', role: c }] }, { type: 'window', role: a }] };
  if (kind === 'top-split' && c) return { type: 'split', direction: 'rows', weights: [1, 1], children: [{ type: 'split', direction: 'columns', weights: [1, 1], children: [{ type: 'window', role: b }, { type: 'window', role: c }] }, { type: 'window', role: a }] };
  if (kind === 'bottom-split' && c) return { type: 'split', direction: 'rows', weights: [1, 1], children: [{ type: 'window', role: a }, { type: 'split', direction: 'columns', weights: [1, 1], children: [{ type: 'window', role: b }, { type: 'window', role: c }] }] };
  if (kind === 'three-columns' && c) return { type: 'split', direction: 'columns', weights: [1, 1, 1], children: [a, b, c].map((role) => ({ type: 'window', role })) };
  if (kind === 'three-rows' && c) return { type: 'split', direction: 'rows', weights: [1, 1, 1], children: [a, b, c].map((role) => ({ type: 'window', role })) };
  if (kind === 'quad' && d) return { type: 'split', direction: 'rows', weights: [1, 1], children: [[a, b], [c, d]].map((pair) => ({ type: 'split', direction: 'columns', weights: [1, 1], children: pair.map((role) => ({ type: 'window', role })) })) };
  if (kind === 'main-left' && d) return { type: 'split', direction: 'columns', weights: [2, 1], children: [{ type: 'window', role: a }, { type: 'split', direction: 'rows', weights: [1, 1, 1], children: [b, c, d].map((role) => ({ type: 'window', role })) }] };
  if (kind === 'main-top' && d) return { type: 'split', direction: 'rows', weights: [2, 1], children: [{ type: 'window', role: a }, { type: 'split', direction: 'columns', weights: [1, 1, 1], children: [b, c, d].map((role) => ({ type: 'window', role })) }] };
  return { type: 'split', direction: 'rows', weights: [1, 1], children: [{ type: 'window', role: b }, { type: 'window', role: a }] };
}

function layoutNode(node) {
  if (node.type === 'window') return `<div class="layout-region" style="flex:1 1 0">${escapeHtml(node.role)}</div>`;
  if (node.type === 'empty') return '<div class="layout-region" style="flex:1 1 0">empty</div>';
  if (node.type === 'canvas') return `<div style="position:relative;flex:1">${node.regions.map((region, index) => {
    if (!region.grid) return `<div class="badge" style="position:absolute;left:8px;bottom:${8 + index * 28}px">${escapeHtml(region.role)} · absolute</div>`;
    const [rows, cols, x, y, width, height] = region.grid.split(':').map(Number);
    return `<div class="layout-region" style="position:absolute;left:${x/cols*100}%;top:${y/rows*100}%;width:${width/cols*100}%;height:${height/rows*100}%;border:2px solid #1b2422">${escapeHtml(region.role)}</div>`;
  }).join('')}</div>`;
  return `<div class="layout-region split ${node.direction}" style="flex:1 1 0">${node.children.map((child, index) => `<div style="display:flex;min-width:0;min-height:0;flex:${node.weights[index]} 1 0">${layoutNode(child)}</div>`).join('')}</div>`;
}

function layoutRoles(node, roles = new Set()) {
  visitLayout(node, (item) => { if (item.role) roles.add(item.role); });
  return roles;
}

function canvasFromLayout(layout, roles) {
  const placed = [...layoutRoles(layout)].filter((role) => roles.includes(role));
  const ordered = [...placed, ...roles.filter((role) => !placed.includes(role))];
  const count = Math.max(ordered.length, 1);
  return {
    type: 'canvas',
    regions: ordered.map((role, index) => {
      const x = Math.floor(index * 12 / count);
      const next = Math.floor((index + 1) * 12 / count);
      return { role, grid: `12:12:${x}:0:${Math.max(1, next - x)}:12` };
    })
  };
}

function gridValues(region) {
  if (!region.grid) return { x: 0, y: 0, w: 6, h: 6 };
  const [rows, cols, x, y, w, h] = region.grid.split(':').map(Number);
  return {
    x: Math.round(x / cols * 12), y: Math.round(y / rows * 12),
    w: Math.max(1, Math.round(w / cols * 12)), h: Math.max(1, Math.round(h / rows * 12))
  };
}

function setRegionGrid(region, values) {
  const x = Math.max(0, Math.min(11, Number(values.x)));
  const y = Math.max(0, Math.min(11, Number(values.y)));
  const w = Math.max(1, Math.min(12 - x, Number(values.w)));
  const h = Math.max(1, Math.min(12 - y, Number(values.h)));
  region.grid = `12:12:${x}:${y}:${w}:${h}`;
  delete region.move_abs;
  delete region.resize_abs;
}

function canvasPreview(layout, workspace) {
  if (layout?.type !== 'canvas') return `<div class="layout-preview">${layoutNode(layout)}</div>`;
  return `<div class="layout-preview canvas-editor" data-canvas>${layout.regions.map((region, index) => {
    const { x, y, w, h } = gridValues(region);
    const app = workspace.windows[region.role]?.app;
    return `<button class="canvas-window" data-region="${index}" data-role="${escapeHtml(region.role)}" style="--x:${x};--y:${y};--w:${w};--h:${h}" aria-label="Move and resize ${escapeHtml(region.role)}"><span class="window-app">${escapeHtml(state.config.apps[app]?.name || app || 'Unassigned')}</span><strong>${escapeHtml(region.role)}</strong><small>${x},${y} · ${w}×${h}</small><i aria-hidden="true"></i></button>`;
  }).join('')}</div>`;
}

function workspaceShortcutPanel(workspaceId) {
  return `<section class="workspace-shortcuts"><div class="layout-heading"><div><p class="kicker">Keyboard shortcuts</p><h3>Open this workspace</h3></div><button class="quiet" data-go-shortcuts>View keyboard layout →</button></div><div class="workspace-shortcut-grid">${MODES.map((mode) => {
    const actual = matchingShortcut(workspaceId, mode); const external = externalShortcut(workspaceId, mode); const conflict = bindingConflict(actual);
    return `<article class="shortcut-row ${conflict ? 'has-conflict' : ''}"><div><strong>${mode}</strong><small>${workspacePlacement(state.config, mode, workspaceId) ? `Suggested number ${workspacePlacement(state.config, mode, workspaceId).index + 1}` : 'Not placed in this mode'}</small></div><span class="shortcut-value">${actual || external ? escapeHtml(chordLabel((actual || external).keys)) : '—'}</span><span class="shortcut-state">${escapeHtml(shortcutStatus(actual, external))}</span><div class="actions"><button class="quiet" data-workspace-shortcut="${mode}">${actual ? 'Change' : external ? 'Import / change' : 'Add'}</button>${actual ? `<button class="quiet" data-clear-workspace-shortcut="${mode}">Clear</button>` : ''}</div></article>`;
  }).join('')}</div></section>`;
}

function workspaceEditor(id) {
  const workspace = state.config.workspaces[id];
  const roles = ids(workspace.windows);
  const variant = workspace.variants[state.mode];
  const canvas = variant?.layout?.type === 'canvas';
  const availability = MODES.map((mode) => `<label class="mode-availability"><input type="checkbox" data-mode-enabled="${mode}" ${workspace.variants[mode] ? 'checked' : ''}> ${mode}</label>`).join('');
  if (!variant) return `<article class="card workspace-editor"><div class="editor-mode-banner">Editing <strong>${escapeHtml(state.mode)}</strong> · ${escapeHtml(workspace.name)}</div><div class="row"><div class="field"><label>Workspace name</label><input data-bind="name" value="${escapeHtml(workspace.name)}"></div><div class="field"><label>Stable ID</label><input value="${escapeHtml(id)}" disabled></div></div><div class="mode-availability-row"><span>Available modes</span>${availability}</div><p class="empty-lane">This workspace is disabled in ${escapeHtml(state.mode)} mode.</p><div class="actions"><button id="enable-current-mode" class="primary">Enable in ${escapeHtml(state.mode)}</button><button id="duplicate-workspace" class="quiet">Duplicate Workspace</button></div></article>`;
  const placement = workspacePlacement(state.config, state.mode, id); const displayName = placement ? state.config.displayRoles[placement.role]?.name || placement.role : 'Unassigned';
  return `<article class="card workspace-editor">
    <div class="workspace-context"><strong>${escapeHtml(workspace.name)} · ${escapeHtml(state.mode)} · ${escapeHtml(displayName)} · ${placement ? `Space ${placement.index + 1}` : 'No Space'}</strong><small>Mode-specific placement and layout</small></div>
    <div class="row"><div class="field"><label for="workspace-name">Workspace name</label><input id="workspace-name" name="workspace-name" autocomplete="off" data-bind="name" value="${escapeHtml(workspace.name)}"></div><div class="field"><label for="workspace-id">Stable ID</label><input id="workspace-id" value="${escapeHtml(id)}" disabled></div></div>
    <div class="field"><label for="workspace-label">Space label prefix</label><input id="workspace-label" name="workspace-label" autocomplete="off" data-bind="spaceLabel" value="${escapeHtml(workspace.spaceLabel)}"></div>
    <div class="mode-availability-row"><span>Available modes</span>${availability}</div>
    <div class="actions"><button id="rename-workspace" class="quiet">Rename ID</button><button id="duplicate-workspace" class="quiet">Duplicate Workspace</button><button id="copy-layout" class="quiet">Copy ${escapeHtml(state.mode)} layout…</button><button id="delete-workspace" class="danger">Delete Workspace</button></div>
    <nav class="workspace-tabs" role="tablist" aria-label="Workspace editor sections">${[['overview','Overview'],['apps','Apps & Shortcuts'],['layout','Layout'],['advanced','Window Matching / Advanced']].map(([key,label])=>`<button id="workspace-tab-${key}" role="tab" aria-controls="workspace-pane-${key}" aria-selected="${state.workspaceTab === key}" data-workspace-tab="${key}" class="${state.workspaceTab === key ? 'active' : ''}">${label}</button>`).join('')}</nav>
    <section id="workspace-pane-overview" role="tabpanel" aria-labelledby="workspace-tab-overview" class="workspace-pane ${state.workspaceTab === 'overview' ? 'active' : ''}" data-pane="overview"><div class="overview-grid"><div><span>Display</span><strong>${escapeHtml(displayName)}</strong></div><div><span>Space order</span><strong>${placement ? placement.index + 1 : 'Unassigned'}</strong></div><div><span>Windows</span><strong>${roles.length}</strong></div><div><span>Available modes</span><strong>${MODES.filter((mode)=>workspace.variants[mode]).join(' · ')}</strong></div></div></section>
    <section id="workspace-pane-apps" role="tabpanel" aria-labelledby="workspace-tab-apps" class="workspace-pane ${state.workspaceTab === 'apps' ? 'active' : ''}" data-pane="apps">${workspaceShortcutPanel(id)}<div class="window-inspector"><div class="layout-heading"><div><p class="kicker">Application windows</p><h3>Roles stay stable when apps change</h3></div><button id="add-window-role" class="primary">+ Add app window</button></div>${Object.entries(workspace.windows).map(([role, window]) => { const region = canvas ? variant.layout.regions.find((item) => item.role === role) : null; const grid = region ? gridValues(region) : null; return `<article class="app-role-row"><div class="app-avatar">${escapeHtml((state.config.apps[window.app]?.name || window.app).slice(0,2).toUpperCase())}</div><div><strong>${escapeHtml(state.config.apps[window.app]?.name || window.app)}</strong><small>${escapeHtml(role)} · ${window.required ? 'Required' : 'Optional'} · ${grid ? `${grid.w}×${grid.h}` : 'Preset layout'}</small></div><button class="quiet" data-replace-app="${role}">Replace App</button></article>`; }).join('')}<button class="quiet manage-apps" data-go-apps>Manage application registry →</button></div></section>
    <section id="workspace-pane-layout" role="tabpanel" aria-labelledby="workspace-tab-layout" class="workspace-pane ${state.workspaceTab === 'layout' ? 'active' : ''}" data-pane="layout"><div class="layout-stage"><div class="layout-heading"><div><p class="kicker">${escapeHtml(state.mode)} layout</p><h3>Arrange windows</h3></div><button id="edit-canvas" class="${canvas ? 'quiet' : 'primary'}">${canvas ? 'Reset equal columns' : 'Edit freely'}</button></div>${canvasPreview(variant?.layout, workspace)}${canvas?`<div class="layout-geometry-list">${variant.layout.regions.map((region)=>{const grid=gridValues(region);return `<div><strong>${escapeHtml(region.role)}</strong><div class="geometry-grid"><label>Left <input type="number" min="0" max="11" data-geometry="x:${region.role}" value="${grid.x}"></label><label>Top <input type="number" min="0" max="11" data-geometry="y:${region.role}" value="${grid.y}"></label><label>Width <input type="number" min="1" max="12" data-geometry="w:${region.role}" value="${grid.w}"></label><label>Height <input type="number" min="1" max="12" data-geometry="h:${region.role}" value="${grid.h}"></label></div></div>`;}).join('')}</div>`:''}<p class="layout-hint">${canvas ? 'Drag a window to move it. Drag its lower-right corner to resize. The grid snaps to 12 columns and 12 rows.' : 'Choose Edit freely to drag and resize every window, or start from a preset below.'}</p><div class="layout-preset-groups"><div><span>Presets</span><div class="actions layout-presets">${['full','half-columns','half-rows','third-columns','two-third-columns','three-columns','three-rows','left-stack','right-stack','top-split','bottom-split','quad','main-left','main-top'].map((preset)=>`<button class="template-button" data-template="${preset}">${preset.replaceAll('-',' ')}</button>`).join('')}</div></div></div></div></section>
    <section id="workspace-pane-advanced" role="tabpanel" aria-labelledby="workspace-tab-advanced" class="workspace-pane ${state.workspaceTab === 'advanced' ? 'active' : ''}" data-pane="advanced"><div class="window-inspector"><div class="layout-heading"><div><p class="kicker">Window matching</p><h3>Advanced role settings</h3></div></div><details class="activation-card" open><summary><span><strong>Workspace activation</strong><small>Controls whether this variant participates in reconciliation</small></span></summary><div class="window-fields"><label>Activation <select data-activation-type><option value="always" ${(variant.activation?.type || (variant.runtime?.runner === 'office_document' ? 'windowPresent' : 'always')) === 'always' ? 'selected' : ''}>Always</option><option value="windowPresent" ${(variant.activation?.type || (variant.runtime?.runner === 'office_document' ? 'windowPresent' : 'always')) === 'windowPresent' ? 'selected' : ''}>When a window is present</option></select></label><label>Activation role <select data-activation-role>${roles.map((role)=>`<option value="${escapeHtml(role)}" ${(variant.activation?.role || 'primary') === role ? 'selected' : ''}>${escapeHtml(role)}</option>`).join('')}</select></label></div></details>${Object.entries(workspace.windows).map(([role, window]) => `<details class="window-card"><summary><span><strong>${escapeHtml(role)}</strong><small>${escapeHtml(state.config.apps[window.app]?.name || window.app)}</small></span><span>${window.required ? 'Required' : 'Optional'}</span></summary><div class="window-fields"><label class="check"><input type="checkbox" data-required="${role}" ${window.required ? 'checked' : ''}> This window is required</label><label>Ownership <select data-ownership="${role}"><option value="lastApplicable" ${(window.ownership || 'lastApplicable') === 'lastApplicable' ? 'selected' : ''}>Last applicable workspace</option><option value="independent" ${window.ownership === 'independent' ? 'selected' : ''}>Independent selector</option></select></label><label>Cardinality <select data-cardinality="${role}"><option value="one" ${(window.cardinality || 'one') === 'one' ? 'selected' : ''}>One window</option><option value="many" ${window.cardinality === 'many' ? 'selected' : ''}>All matching windows</option></select></label><div class="selector-grid"><label><input type="checkbox" data-selector="movable:${role}" ${window.selector?.movable ? 'checked' : ''}> movable</label><label><input type="checkbox" data-selector="visible:${role}" ${window.selector?.visible ? 'checked' : ''}> visible</label><label><input type="checkbox" data-selector="non_empty_title:${role}" ${window.selector?.non_empty_title ? 'checked' : ''}> titled</label><input aria-label="Title includes for ${escapeHtml(role)}" placeholder="Title includes…" data-selector-text="title_include:${role}" value="${escapeHtml(window.selector?.title_include || '')}"><input aria-label="Title excludes for ${escapeHtml(role)}" placeholder="Title excludes…" data-selector-text="title_exclude:${role}" value="${escapeHtml(window.selector?.title_exclude || '')}"><input aria-label="Accessibility role for ${escapeHtml(role)}" placeholder="AX role, e.g. AXWindow" data-selector-text="role:${role}" value="${escapeHtml(window.selector?.role || '')}"><input aria-label="Accessibility subrole for ${escapeHtml(role)}" placeholder="AX subrole, e.g. AXStandardWindow" data-selector-text="subrole:${role}" value="${escapeHtml(window.selector?.subrole || '')}"></div><div class="actions"><button class="quiet" data-rename-window="${role}">Rename role</button><button class="danger" data-delete-window="${role}">Remove window</button></div></div></details>`).join('')}</div></section>
  </article>`;
}

function openAppPicker(workspaceId, role) {
  const workspace = state.config.workspaces[workspaceId]; const current = workspace.windows[role];
  const overlay = document.createElement('dialog'); overlay.className = 'modal-dialog modal-dialog-wide';
  const close = () => { if (overlay.open) overlay.close(); overlay.remove(); };
  const renderPicker = (query = '') => {
    const used = new Set(Object.values(workspace.windows).map((item) => item.app));
    const running = new Set(state.appInventory?.apps || []); const normalized = query.toLowerCase();
    const choices = Object.entries(state.config.apps).filter(([id, app]) => `${id} ${app.name} ${app.match.appNames.join(' ')}`.toLowerCase().includes(normalized)).sort(([a],[b]) => Number(used.has(b))-Number(used.has(a)));
    overlay.innerHTML = `<section class="app-picker" aria-labelledby="app-picker-title"><p class="kicker">Replace application</p><h2 id="app-picker-title">${escapeHtml(workspace.name)} · ${escapeHtml(role)}</h2><p>The role, required state, layout and general matching settings stay unchanged.</p><label class="field"><span>Search applications</span><input id="app-picker-search" name="application-search" autocomplete="off" type="search" placeholder="Name, stable ID or macOS alias" value="${escapeHtml(query)}"></label><div class="app-picker-list">${choices.map(([id,app])=>`<button data-pick-app="${id}" class="app-picker-option"><span class="app-avatar">${escapeHtml(app.name.slice(0,2).toUpperCase())}</span><span><strong>${escapeHtml(app.name)}</strong><small>${escapeHtml(id)} · ${escapeHtml(app.match.appNames.join(', '))}</small></span><span>${running.has(app.name) || app.match.appNames.some((name)=>running.has(name)) ? '<b class="detected">Running</b>' : 'Registered'}</span></button>`).join('') || '<p class="empty-lane">No registered applications match.</p>'}</div><div class="actions"><button class="quiet" id="add-picker-app">+ Add application…</button><button class="quiet" id="cancel-picker">Cancel</button></div></section>`;
    overlay.querySelector('#app-picker-search').oninput = (event) => { const cursor = event.target.selectionStart; renderPicker(event.target.value); const input = overlay.querySelector('#app-picker-search'); input.focus(); input.setSelectionRange(cursor,cursor); };
    overlay.querySelector('#cancel-picker').onclick = close;
    overlay.querySelector('#add-picker-app').onclick = async () => { const name = await promptValue('Application Display Name'); if (!name?.trim()) return; const aliases = await promptValue('macOS Application Aliases', name.trim(), 'Separate multiple aliases with commas.'); let id = name.trim().toLowerCase().replace(/[^a-z0-9]+/g,'_').replace(/^([^a-z])/, 'app_$1'); let suffix = 2; const base = id; while (state.config.apps[id]) id = `${base}_${suffix++}`; state.config.apps[id] = { name: name.trim(), match: { appNames: (aliases || name).split(',').map((item)=>item.trim()).filter(Boolean) } }; choose(id); };
    overlay.querySelectorAll('[data-pick-app]').forEach((button)=>button.onclick=()=>choose(button.dataset.pickApp));
  };
  const choose = (appId) => {
    const oldApp = current.app; const hasSpecific = Boolean(current.selector?.title_include || current.selector?.title_exclude);
    overlay.innerHTML = `<section class="app-picker scope-picker"><p class="kicker">Preview impact</p><h2>${escapeHtml(state.config.apps[oldApp]?.name || oldApp)} → ${escapeHtml(state.config.apps[appId].name)}</h2><p><strong>${escapeHtml(workspace.name)} · ${escapeHtml(state.mode)}</strong><br><code>${escapeHtml(role)}</code> keeps its layout, role and ${current.required ? 'Required' : 'Optional'} state.</p>${hasSpecific ? '<div class="conflict-banner">This role has title-specific matching. Review it after replacement; it may not apply to the new app.</div>' : ''}<fieldset><legend>Apply to</legend><label><input type="radio" name="replace-scope" value="mode" checked> ${escapeHtml(state.mode)} only</label><label><input type="radio" name="replace-scope" value="all"> All modes in this workspace</label></fieldset><div class="actions"><button class="primary" id="confirm-replace">Replace App</button><button class="quiet" id="back-picker">Back</button></div></section>`;
    overlay.querySelector('#back-picker').onclick=()=>renderPicker();
    overlay.querySelector('#confirm-replace').onclick=()=>{ const scope=overlay.querySelector('[name="replace-scope"]:checked').value; if(scope==='all'){ current.app=appId; for(const variant of Object.values(workspace.variants)) if(variant.runtime?.windows) for(const item of variant.runtime.windows) if(item.role===role)item.app_key=appId; } else { const variant=workspace.variants[state.mode]; variant.runtime ||= {}; variant.runtime.windows ||= Object.entries(workspace.windows).map(([windowRole,item])=>({role:windowRole,app_key:item.app,required:item.required,...(item.ownership?{ownership:item.ownership}:{}),...(item.cardinality?{cardinality:item.cardinality}:{}),...(item.selector?{selector:structuredClone(item.selector)}:{})})); const item=variant.runtime.windows.find((entry)=>entry.role===role); item.app_key=appId; } markDirty(); close(); render(); toast(`${workspace.name} · ${state.mode}: ${role} changed from ${state.config.apps[oldApp]?.name || oldApp} to ${state.config.apps[appId].name}. Layout and role were preserved.`); };
  };
  overlay.addEventListener('cancel',(event)=>{event.preventDefault();close();}); overlay.onclick=(event)=>{if(event.target===overlay)close();}; document.body.append(overlay); renderPicker(); overlay.showModal(); overlay.querySelector('#app-picker-search').focus();
}

function workspacesView() {
  if (!state.selectedWorkspace || !state.config.workspaces[state.selectedWorkspace]) state.selectedWorkspace = ids(state.config.workspaces)[0];
  const mode = state.config.modes[state.mode] || { displays: [] };
  const query = state.workspaceSearch.toLowerCase();
  const workspaceCard = (id, displayIndex, index) => { const workspace = state.config.workspaces[id]; if (!workspace || (query && !`${workspace.name} ${id}`.toLowerCase().includes(query))) return ''; return `<div class="workspace-list-card ${id === state.selectedWorkspace ? 'selected' : ''}" draggable="true" tabindex="0" role="button" data-select="${id}" data-display-index="${displayIndex}" data-space-index="${index}" aria-label="${escapeHtml(workspace.name)}, Space ${index + 1}. Use arrow keys to reorder."><span class="order">${index + 1}</span><span><strong>${escapeHtml(workspace.name)}</strong><small>${escapeHtml(id)} · Space ${index + 1}</small></span><span class="reorder-hint">↑↓</span></div>`; };
  const lanes = mode.displays.map((display, displayIndex) => `<section class="workspace-display-group"><header><div><h3>${escapeHtml(state.config.displayRoles[display.role]?.name || display.role)}</h3><p>Role <code>${escapeHtml(display.role)}</code> · ${display.workspaceOrder.length} workspace${display.workspaceOrder.length === 1 ? '' : 's'}</p></div>${state.machine.displayBindings[display.role] ? `<span class="binding-status">${escapeHtml(state.machine.displayBindings[display.role])}</span>` : '<span class="binding-status unbound">No physical display bound</span>'}</header><div class="workspace-drop-lane" data-workspace-lane="${displayIndex}">${display.workspaceOrder.map((id, index) => workspaceCard(id, displayIndex, index)).join('') || '<p class="empty-lane">Drop an enabled workspace here</p>'}</div></section>`).join('');
  root.innerHTML = title('Workspace catalogue', 'Workspaces by display', 'One stable workspace identity can have a different display, Space order, layout and availability in each mode.', modeSwitch()) +
    `<div class="workspace-toolbar"><label class="workspace-search"><span>Search</span><input id="workspace-search" data-ui-only type="search" placeholder="Workspace name or ID" value="${escapeHtml(state.workspaceSearch)}"></label><button class="primary" id="add-workspace">+ New workspace</button></div><div class="workspace-master-detail"><aside class="workspace-groups">${lanes}</aside>${workspaceEditor(state.selectedWorkspace)}</div>`;
  root.querySelectorAll('[data-mode]').forEach((button) => button.onclick = () => { state.mode = button.dataset.mode; render(); });
  const workspaceTabs = [...root.querySelectorAll('[data-workspace-tab]')];
  workspaceTabs.forEach((button, index) => {
    const activate = (focus = false) => { state.workspaceTab = button.dataset.workspaceTab; render(); if (focus) root.querySelector(`[data-workspace-tab="${state.workspaceTab}"]`)?.focus(); };
    button.onclick = () => activate();
    button.onkeydown = (event) => {
      const offsets = { ArrowLeft: -1, ArrowRight: 1 };
      if (!(event.key in offsets) && !['Home', 'End'].includes(event.key)) return;
      event.preventDefault();
      const target = event.key === 'Home' ? 0 : event.key === 'End' ? workspaceTabs.length - 1 : (index + offsets[event.key] + workspaceTabs.length) % workspaceTabs.length;
      state.workspaceTab = workspaceTabs[target].dataset.workspaceTab;
      render();
      root.querySelector(`[data-workspace-tab="${state.workspaceTab}"]`)?.focus();
    };
  });
  root.querySelectorAll('[data-select]').forEach((button) => button.onclick = () => { state.selectedWorkspace = button.dataset.select; render(); });
  let draggedWorkspace = null;
  const moveWorkspace = (id, targetDisplay, targetIndex) => { const source = workspacePlacement(state.config, state.mode, id); let index = targetIndex; if (source?.role === mode.displays[targetDisplay].role && source.index < index) index--; for (const display of mode.displays) display.workspaceOrder = display.workspaceOrder.filter((item) => item !== id); mode.displays[targetDisplay].workspaceOrder.splice(index, 0, id); const fixedNumbers = (state.config.shortcuts || []).filter((item) => item.action.type === 'activateWorkspace' && item.action.workspace === id && item.action.mode === state.mode && /^[0-9]$/.test(item.keys.key)); markDirty(); render(); if (fixedNumbers.length) toast(`Order changed. Explicit ${fixedNumbers.map((item) => chordLabel(item.keys)).join(', ')} binding${fixedNumbers.length === 1 ? ' was' : 's were'} preserved; review Shortcuts before saving.`); };
  root.querySelectorAll('.workspace-list-card').forEach((card) => { card.ondragstart = () => { draggedWorkspace = card.dataset.select; }; card.ondragover = (event) => { event.preventDefault(); card.classList.add('drop-before'); }; card.ondragleave = () => card.classList.remove('drop-before'); card.ondrop = (event) => { event.preventDefault(); moveWorkspace(draggedWorkspace, Number(card.dataset.displayIndex), Number(card.dataset.spaceIndex)); }; card.onkeydown = (event) => { if (!['ArrowUp','ArrowDown'].includes(event.key)) return; event.preventDefault(); const displayIndex = Number(card.dataset.displayIndex); const index = Number(card.dataset.spaceIndex); const target = event.key === 'ArrowUp' ? index - 1 : index + 2; if (target < 0 || target > mode.displays[displayIndex].workspaceOrder.length) return; moveWorkspace(card.dataset.select, displayIndex, target); }; });
  root.querySelectorAll('[data-workspace-lane]').forEach((lane) => { lane.ondragover = (event) => { event.preventDefault(); lane.classList.add('drop-target'); }; lane.ondragleave = () => lane.classList.remove('drop-target'); lane.ondrop = (event) => { if (event.target.closest('.workspace-list-card')) return; event.preventDefault(); const displayIndex = Number(lane.dataset.workspaceLane); moveWorkspace(draggedWorkspace, displayIndex, mode.displays[displayIndex].workspaceOrder.length); }; });
  root.querySelector('#workspace-search').oninput = (event) => { state.workspaceSearch = event.target.value; workspacesView(); root.querySelector('#workspace-search').focus(); };
  root.querySelector('[data-bind="name"]').oninput = (event) => { state.config.workspaces[state.selectedWorkspace].name = event.target.value; markDirty(); };
  root.querySelectorAll('[data-mode-enabled]').forEach((input) => input.onchange = async () => {
    const workspace = state.config.workspaces[state.selectedWorkspace]; const modeId = input.dataset.modeEnabled;
    if (input.checked) workspace.variants[modeId] = structuredClone(workspace.variants[state.mode] || workspace.variants[MODES.find((item) => workspace.variants[item])]);
    else { if (!await confirmAction(`Disable ${workspace.name} in ${modeId}? Its ${modeId} layout and placement will be removed from the draft.`, { confirmLabel: 'Disable Mode', danger: true })) { input.checked = true; return; } delete workspace.variants[modeId]; for (const display of state.config.modes[modeId].displays) display.workspaceOrder = display.workspaceOrder.filter((item) => item !== state.selectedWorkspace); const assignment=state.config.aiRouting?.assignments?.[state.selectedWorkspace];if(assignment?.overrides)delete assignment.overrides[modeId];if(assignment?.roleOverrides)delete assignment.roleOverrides[modeId]; }
    markDirty(); render();
  });
  root.querySelector('#enable-current-mode')?.addEventListener('click', () => { const workspace = state.config.workspaces[state.selectedWorkspace]; workspace.variants[state.mode] = structuredClone(workspace.variants[MODES.find((item) => workspace.variants[item])]); state.config.modes[state.mode].displays[0].workspaceOrder.push(state.selectedWorkspace); markDirty(); render(); });
  root.querySelector('#duplicate-workspace')?.addEventListener('click', () => { const source = state.selectedWorkspace; let suffix = 2; while (state.config.workspaces[`${source}_${suffix}`]) suffix++; const id = `${source}_${suffix}`; state.config.workspaces[id] = structuredClone(state.config.workspaces[source]); state.config.workspaces[id].name += ' Copy'; for (const modeId of MODES) { const placement = workspacePlacement(state.config, modeId, source); if (placement && state.config.workspaces[id].variants[modeId]) state.config.modes[modeId].displays.find((display) => display.role === placement.role).workspaceOrder.splice(placement.index + 1, 0, id); } state.selectedWorkspace = id; markDirty(); render(); });
  root.querySelector('#copy-layout')?.addEventListener('click', async () => { const targets = MODES.filter((modeId) => modeId !== state.mode); const selected = await promptValue(`Copy ${state.mode} Layout`, targets.join(', '), `Enter target modes separated by commas: ${targets.join(', ')}.`); if (!selected) return; const requested = selected.split(',').map((item) => item.trim()).filter((item) => targets.includes(item)); if (!requested.length) return toast('No valid target modes selected.', true); if (!await confirmAction(`Replace the layout in ${requested.join(', ')}?`, { confirmLabel: 'Replace Layout', danger: true })) return; const workspace = state.config.workspaces[state.selectedWorkspace]; for (const modeId of requested) workspace.variants[modeId] = { ...(workspace.variants[modeId] || {}), layout: structuredClone(workspace.variants[state.mode].layout) }; markDirty(); render(); });
  if (root.querySelector('[data-bind="spaceLabel"]')) root.querySelector('[data-bind="spaceLabel"]').oninput = (event) => { state.config.workspaces[state.selectedWorkspace].spaceLabel = event.target.value; markDirty(); };
  root.querySelectorAll('[data-replace-app]').forEach((button) => button.onclick = () => openAppPicker(state.selectedWorkspace, button.dataset.replaceApp));
  root.querySelectorAll('[data-workspace-shortcut]').forEach((button) => button.onclick = () => { const modeId = button.dataset.workspaceShortcut; const existing = matchingShortcut(state.selectedWorkspace, modeId); recordShortcut((keys) => { const conflict=(state.config.shortcuts||[]).find((item)=>item!==existing&&chordKey(item.keys)===chordKey(keys)); if(conflict)return toast(`${chordLabel(keys)} already triggers ${actionLabel(conflict)}. Binding unchanged.`,true); if(existing)existing.keys=keys; else (state.config.shortcuts ||= []).push({id:crypto.randomUUID(),keys,action:{type:'activateWorkspace',workspace:state.selectedWorkspace,mode:modeId}}); markDirty(); render(); }); });
  root.querySelectorAll('[data-clear-workspace-shortcut]').forEach((button)=>button.onclick=async()=>{const shortcut=matchingShortcut(state.selectedWorkspace,button.dataset.clearWorkspaceShortcut); if(shortcut&&await confirmAction(`Clear ${actionLabel(shortcut)}?`, { confirmLabel: 'Clear Shortcut', danger: true })){state.config.shortcuts.splice(state.config.shortcuts.indexOf(shortcut),1);markDirty();render();}});
  root.querySelector('[data-go-shortcuts]')?.addEventListener('click',()=>{state.view='shortcuts';render();});
  if (root.querySelector('[data-go-apps]')) root.querySelector('[data-go-apps]').onclick = () => { state.view = 'apps'; render(); };
  if (root.querySelector('#edit-canvas')) root.querySelector('#edit-canvas').onclick = () => {
    const workspace = state.config.workspaces[state.selectedWorkspace];
    workspace.variants[state.mode] = { layout: canvasFromLayout(workspace.variants[state.mode]?.layout, ids(workspace.windows)) };
    markDirty(); render();
  };
  root.querySelectorAll('[data-geometry]').forEach((input) => input.onchange = () => {
    const [field, role] = input.dataset.geometry.split(':');
    const layout = state.config.workspaces[state.selectedWorkspace].variants[state.mode].layout;
    const region = layout.regions.find((item) => item.role === role);
    const values = gridValues(region); values[field] = input.value;
    setRegionGrid(region, values); markDirty(); render();
  });
  root.querySelectorAll('.canvas-window').forEach((windowNode) => {
    windowNode.onpointerdown = (event) => {
      if (event.button !== 0) return;
      event.preventDefault();
      const canvas = root.querySelector('[data-canvas]');
      const layout = state.config.workspaces[state.selectedWorkspace].variants[state.mode].layout;
      const region = layout.regions[Number(windowNode.dataset.region)];
      const start = gridValues(region);
      const bounds = canvas.getBoundingClientRect();
      const resizing = event.target.tagName === 'I';
      const origin = { x: event.clientX, y: event.clientY };
      windowNode.setPointerCapture(event.pointerId);
      windowNode.onpointermove = (move) => {
        const dx = Math.round((move.clientX - origin.x) / bounds.width * 12);
        const dy = Math.round((move.clientY - origin.y) / bounds.height * 12);
        const values = resizing ? { ...start, w: start.w + dx, h: start.h + dy } : { ...start, x: start.x + dx, y: start.y + dy };
        setRegionGrid(region, values);
        const next = gridValues(region);
        windowNode.style.setProperty('--x', next.x); windowNode.style.setProperty('--y', next.y); windowNode.style.setProperty('--w', next.w); windowNode.style.setProperty('--h', next.h);
        windowNode.querySelector('small').textContent = `${next.x},${next.y} · ${next.w}×${next.h}`;
      };
      windowNode.onpointerup = () => { windowNode.onpointermove = null; markDirty(); render(); };
    };
  });
  root.querySelectorAll('[data-required]').forEach((input) => input.onchange = () => { const workspace=state.config.workspaces[state.selectedWorkspace];const role=input.dataset.required;workspace.windows[role].required=input.checked;const runtimeWindow=workspace.variants[state.mode].runtime?.windows?.find((item)=>item.role===role);if(runtimeWindow)runtimeWindow.required=input.checked;markDirty(); });
  root.querySelector('[data-activation-type]')?.addEventListener('change', (event) => { const variant=state.config.workspaces[state.selectedWorkspace].variants[state.mode];variant.activation=event.target.value==='always'?{type:'always'}:{type:'windowPresent',role:root.querySelector('[data-activation-role]').value};markDirty();render(); });
  root.querySelector('[data-activation-role]')?.addEventListener('change', (event) => { const variant=state.config.workspaces[state.selectedWorkspace].variants[state.mode];if(variant.activation?.type==='windowPresent'){variant.activation.role=event.target.value;markDirty();} });
  root.querySelectorAll('[data-ownership]').forEach((input) => input.onchange = () => { const workspace=state.config.workspaces[state.selectedWorkspace];const role=input.dataset.ownership;workspace.windows[role].ownership=input.value;const runtimeWindow=workspace.variants[state.mode].runtime?.windows?.find((item)=>item.role===role);if(runtimeWindow)runtimeWindow.ownership=input.value;markDirty(); });
  root.querySelectorAll('[data-cardinality]').forEach((input) => input.onchange = () => { const workspace=state.config.workspaces[state.selectedWorkspace];const role=input.dataset.cardinality;workspace.windows[role].cardinality=input.value;const runtimeWindow=workspace.variants[state.mode].runtime?.windows?.find((item)=>item.role===role);if(runtimeWindow)runtimeWindow.cardinality=input.value;markDirty(); });
  root.querySelectorAll('[data-selector]').forEach((input) => input.onchange = () => { const [field, role] = input.dataset.selector.split(':'); const workspace=state.config.workspaces[state.selectedWorkspace];const selector = workspace.windows[role].selector ||= {}; if (input.checked) selector[field] = true; else delete selector[field];const runtimeWindow=workspace.variants[state.mode].runtime?.windows?.find((item)=>item.role===role);if(runtimeWindow)runtimeWindow.selector=structuredClone(selector);markDirty(); });
  root.querySelectorAll('[data-selector-text]').forEach((input) => input.oninput = () => { const [field, role] = input.dataset.selectorText.split(':'); const workspace=state.config.workspaces[state.selectedWorkspace];const selector = workspace.windows[role].selector ||= {}; if (input.value) selector[field] = input.value; else delete selector[field];const runtimeWindow=workspace.variants[state.mode].runtime?.windows?.find((item)=>item.role===role);if(runtimeWindow)runtimeWindow.selector=structuredClone(selector);markDirty(); });
  if (root.querySelector('#rename-workspace')) root.querySelector('#rename-workspace').onclick = async () => {
    const oldId = state.selectedWorkspace; const newId = await requestId('New Workspace ID', oldId, state.config.workspaces); if (!newId) return;
    renameKey(state.config.workspaces, oldId, newId);
    for (const mode of Object.values(state.config.modes)) for (const display of mode.displays) display.workspaceOrder = display.workspaceOrder.map((id) => id === oldId ? newId : id);
    for (const shortcut of state.config.shortcuts || []) if (shortcut.action.workspace === oldId) shortcut.action.workspace = newId;
    if (state.config.aiRouting?.assignments?.[oldId]) renameKey(state.config.aiRouting.assignments, oldId, newId);
    if (state.config.aiRouting?.fallbackWorkspace === oldId) state.config.aiRouting.fallbackWorkspace = newId;
    state.selectedWorkspace = newId; markDirty(); render();
  };
  if (root.querySelector('#delete-workspace')) root.querySelector('#delete-workspace').onclick = async () => {
    const id = state.selectedWorkspace;
    if (Object.keys(state.config.workspaces).length === 1) return toast('A configuration must keep at least 1 workspace.', true);
    if (state.config.aiRouting?.fallbackWorkspace === id) return toast('Choose a different AI fallback workspace before deleting this workspace.', true);
    if (!await confirmAction(`Delete workspace “${id}” and remove it from every mode and shortcut?`, { confirmLabel: 'Delete Workspace', danger: true })) return;
    delete state.config.workspaces[id];
    for (const mode of Object.values(state.config.modes)) for (const display of mode.displays) display.workspaceOrder = display.workspaceOrder.filter((workspaceId) => workspaceId !== id);
    state.config.shortcuts = (state.config.shortcuts || []).filter((shortcut) => shortcut.action.workspace !== id);
    if (state.config.aiRouting?.assignments) delete state.config.aiRouting.assignments[id];
    state.selectedWorkspace = null; markDirty(); render();
  };
  root.querySelectorAll('[data-rename-window]').forEach((button) => button.onclick = async () => {
    const workspace = state.config.workspaces[state.selectedWorkspace]; const oldRole = button.dataset.renameWindow; const newRole = await requestId('New Window Role ID', oldRole, workspace.windows); if (!newRole) return;
    renameKey(workspace.windows, oldRole, newRole);
    const assignment = state.config.aiRouting?.assignments?.[state.selectedWorkspace];
    if (assignment?.role === oldRole) assignment.role = newRole;
    for (const mode of Object.keys(assignment?.roleOverrides || {})) if (assignment.roleOverrides[mode] === oldRole) assignment.roleOverrides[mode] = newRole;
    for (const variant of Object.values(workspace.variants)) {
      visitLayout(variant.layout, (node) => { if (node.role === oldRole) node.role = newRole; });
      if (variant.activation?.role === oldRole) variant.activation.role = newRole;
      for (const runtimeWindow of variant.runtime?.windows || []) if (runtimeWindow.role === oldRole) runtimeWindow.role = newRole;
      for (const action of variant.runtime?.primaryAloneLayout || []) if (action.role === oldRole) action.role = newRole;
    }
    markDirty(); render();
  });
  root.querySelectorAll('[data-delete-window]').forEach((button) => button.onclick = async () => {
    const workspace = state.config.workspaces[state.selectedWorkspace]; const role = button.dataset.deleteWindow;
    if (Object.keys(workspace.windows).length === 1) return toast('A workspace must keep at least 1 window role.', true);
    const assignment = state.config.aiRouting?.assignments?.[state.selectedWorkspace];
    if (assignment?.role === role || Object.values(assignment?.roleOverrides || {}).includes(role)) return toast('This role is used by AI Routing. Remove or change that route first.', true);
    if (!await confirmAction(`Remove window “${role}” from this workspace and all of its layouts?`, { confirmLabel: 'Remove Window', danger: true })) return;
    delete workspace.windows[role];
    for (const variant of Object.values(workspace.variants)) {
      if (variant.layout.type === 'canvas') variant.layout.regions = variant.layout.regions.filter((region) => region.role !== role);
      else if (layoutRoles(variant.layout).has(role)) variant.layout = canvasFromLayout(variant.layout, ids(workspace.windows));
      if (variant.activation?.role === role) variant.activation = { type: 'always' };
      if (variant.runtime?.windows) variant.runtime.windows = variant.runtime.windows.filter((window) => window.role !== role);
    }
    markDirty(); render();
  });
  root.querySelectorAll('[data-template]').forEach((button) => button.onclick = () => {
    const roleCount = ids(state.config.workspaces[state.selectedWorkspace].windows).length;
    const needsThree = ['right-stack', 'left-stack', 'top-split', 'bottom-split', 'three-columns', 'three-rows'];
    const needsFour = ['quad', 'main-left', 'main-top'];
    if (needsThree.includes(button.dataset.template) && roleCount < 3) return toast('This preset needs at least three app windows', true);
    if (needsFour.includes(button.dataset.template) && roleCount < 4) return toast('This preset needs at least four app windows', true);
    state.config.workspaces[state.selectedWorkspace].variants[state.mode] = { layout: layoutTemplate(button.dataset.template, ids(state.config.workspaces[state.selectedWorkspace].windows)) };
    markDirty(); render();
  });
  if (root.querySelector('#add-window-role')) root.querySelector('#add-window-role').onclick = () => {
    const workspace = state.config.workspaces[state.selectedWorkspace]; const windows = workspace.windows;
    let index = 1; while (windows[`window_${index}`]) index++;
    const role=`window_${index}`; windows[role] = { app: ids(state.config.apps)[0], required: false, selector: { movable: true } };
    const variant = workspace.variants[state.mode];
    variant.layout = canvasFromLayout(variant.layout, ids(windows));
    if (variant.runtime?.windows) variant.runtime.windows.push({role,app_key:windows[role].app,required:false,selector:{movable:true}});
    if (variant.runtime && variant.runtime.windows?.length > 2 && variant.runtime.runner === 'primary_helper') { variant.runtime.runner='generic_layout'; delete variant.runtime.primaryAloneLayout; }
    markDirty(); render();
  };
  root.querySelector('#add-workspace').onclick = () => {
    const base = 'workspace'; let index = 1; while (state.config.workspaces[`${base}_${index}`]) index++;
    const id = `${base}_${index}`;
    const app = ids(state.config.apps)[0];
    state.config.workspaces[id] = { name: `Workspace ${index}`, spaceLabel: id, windows: { primary: { app, required: true, selector: { movable: true } } }, variants: Object.fromEntries(['solo','wide','tall'].map((mode) => [mode, { layout: { type: 'window', role: 'primary' } }])) };
    state.config.modes[state.mode].displays[0].workspaceOrder.push(id); state.selectedWorkspace = id; markDirty(); render();
  };
}

function aiView() {
  const providers = state.config.aiProviders || {};
  const routing = state.config.aiRouting;
  if (!routing || !Object.keys(providers).length) {
    const likelyApps = Object.entries(state.config.apps).filter(([id, app]) => /hermes|chatgpt|claude|copilot|gemini/i.test(`${id} ${app.name}`));
    root.innerHTML = title('AI routing', 'Give AI windows a stable role', 'Choose an AI once for each workspace. Solo, Wide and Tall inherit that choice unless you deliberately override one mode.') + `<section class="ai-empty"><div class="ai-orbit" aria-hidden="true"><span>AI</span></div><div><p class="kicker">Semantic layer</p><h3>One assignment, three layouts</h3><p>SpaceWright will route the selected provider into the workspace role and keep its window context with the workspace you came from.</p><button id="enable-ai-routing" class="primary" ${likelyApps.length ? '' : 'disabled'}>Set up AI routing</button>${likelyApps.length ? `<small>Detected candidates: ${likelyApps.map(([,app])=>escapeHtml(app.name)).join(' · ')}</small>` : '<small>Register ChatGPT or Hermes on the Apps page first.</small>'}</div></section>`;
    root.querySelector('#enable-ai-routing')?.addEventListener('click', () => {
      state.config.aiProviders = Object.fromEntries(likelyApps.map(([app, item]) => [app, { name: item.name, app }]));
      state.config.aiRouting = { assignments: {}, fallbackWorkspace: ids(state.config.workspaces)[0], focusOwner: true };
      markDirty(); render();
    });
    return;
  }
  const providerEntries = Object.entries(providers);
  const providerOptions = (selected, inherit = false) => `${inherit ? '<option value="">Inherit default</option>' : ''}${providerEntries.map(([id, provider]) => `<option value="${id}" ${selected === id ? 'selected' : ''}>${escapeHtml(provider.name)}</option>`).join('')}`;
  const workspaceOptions = Object.entries(state.config.workspaces).map(([id, workspace]) => `<option value="${id}">${escapeHtml(workspace.name)}</option>`).join('');
  const providerCards = providerEntries.map(([id, provider], index) => `<article class="ai-provider-card"><div class="ai-provider-index">${String(index + 1).padStart(2,'0')}</div><div><span>Provider</span><input aria-label="Provider name for ${escapeHtml(id)}" data-ai-provider-name="${id}" value="${escapeHtml(provider.name)}"><small>${escapeHtml(id)}</small></div><label>Application<select data-ai-provider-app="${id}">${Object.entries(state.config.apps).map(([appId, app])=>`<option value="${appId}" ${provider.app===appId?'selected':''}>${escapeHtml(app.name)}</option>`).join('')}</select></label><button class="quiet" data-delete-ai-provider="${id}" aria-label="Delete ${escapeHtml(provider.name)}">Remove</button></article>`).join('');
  const assignments = Object.entries(routing.assignments || {}).map(([workspaceId, assignment]) => {
    const workspace = state.config.workspaces[workspaceId];
    if (!workspace) return '';
    return `<article class="ai-route-row"><header><span class="ai-route-signal"></span><div><strong>${escapeHtml(workspace.name)}</strong><small>${escapeHtml(workspaceId)} · default role <code>${escapeHtml(assignment.role)}</code></small></div></header><label class="ai-default-select"><span>Shared default</span><select data-ai-default="${workspaceId}">${providerOptions(assignment.provider)}</select></label><div class="ai-mode-overrides">${MODES.map((mode)=>{const enabled=Boolean(workspace.variants?.[mode]);const effective=assignment.overrides?.[mode]||assignment.provider;const effectiveRole=assignment.roleOverrides?.[mode]||assignment.role;return `<label class="${enabled?'':'disabled'}"><span>${mode}<b>${escapeHtml(providers[effective]?.name||effective)} · ${escapeHtml(effectiveRole)}</b></span><select data-ai-override="${workspaceId}:${mode}" ${enabled?'':'disabled'}>${providerOptions(assignment.overrides?.[mode]||'',true)}</select></label>`;}).join('')}</div><button class="quiet" data-delete-ai-route="${workspaceId}">Remove route</button></article>`;
  }).join('');
  root.innerHTML = title('AI routing', 'One AI choice, shared across every shape', 'Workspace roles stay semantic. The shared default flows through Solo, Wide and Tall; mode overrides are explicit exceptions.') + `<section class="ai-command-strip"><div><span>Providers</span><strong>${providerEntries.length}</strong></div><div><span>Routed workspaces</span><strong>${Object.keys(routing.assignments||{}).length}</strong></div><label><span>Context fallback</span><select id="ai-fallback">${Object.entries(state.config.workspaces).map(([id, workspace])=>`<option value="${id}" ${routing.fallbackWorkspace===id?'selected':''}>${escapeHtml(workspace.name)}</option>`).join('')}</select></label><label class="check"><input id="ai-focus-owner" type="checkbox" ${routing.focusOwner?'checked':''}> Focus the contextual AI workspace after a mode run</label></section><div class="section-head compact"><div><p class="kicker">Provider registry</p><h2>Available AI identities</h2></div></div><div class="ai-provider-list">${providerCards}</div><article class="ai-add-provider"><input id="ai-provider-id" placeholder="provider_id" aria-label="New provider ID"><input id="ai-provider-name" placeholder="Display name" aria-label="New provider display name"><select id="ai-provider-app" aria-label="Provider application">${Object.entries(state.config.apps).map(([id,app])=>`<option value="${id}">${escapeHtml(app.name)}</option>`).join('')}</select><button id="add-ai-provider" class="quiet">+ Provider</button></article><div class="section-head compact"><div><p class="kicker">Assignment matrix</p><h2>Workspace → AI</h2><p>Green is the shared default. Blue labels show the effective provider in each mode.</p></div></div><div class="ai-routing-matrix">${assignments || '<p class="empty-lane">No workspace has a semantic AI role yet.</p>'}</div><article class="ai-add-route"><div><p class="kicker">New route</p><h3>Declare one window role as AI</h3></div><label>Workspace<select id="ai-route-workspace">${workspaceOptions}</select></label><label>Window role<select id="ai-route-role"></select></label><label>Default provider<select id="ai-route-provider">${providerOptions(providerEntries[0]?.[0])}</select></label><button id="add-ai-route" class="primary">Add route</button></article><p class="ai-footnote">Existing concrete app values remain as compatibility fallbacks. The compiled runtime uses this routing layer as the authority.</p>`;
  const updateRouteRoles = () => { const workspaceId=root.querySelector('#ai-route-workspace').value; root.querySelector('#ai-route-role').innerHTML=ids(state.config.workspaces[workspaceId]?.windows).map((role)=>`<option value="${role}">${escapeHtml(role)}</option>`).join(''); };
  updateRouteRoles(); root.querySelector('#ai-route-workspace').onchange=updateRouteRoles;
  root.querySelector('#ai-fallback').onchange=(event)=>{routing.fallbackWorkspace=event.target.value;markDirty();};
  root.querySelector('#ai-focus-owner').onchange=(event)=>{routing.focusOwner=event.target.checked;markDirty();};
  root.querySelectorAll('[data-ai-provider-name]').forEach((input)=>input.onchange=()=>{providers[input.dataset.aiProviderName].name=input.value.trim();markDirty();render();});
  root.querySelectorAll('[data-ai-provider-app]').forEach((select)=>select.onchange=()=>{providers[select.dataset.aiProviderApp].app=select.value;markDirty();render();});
  root.querySelectorAll('[data-ai-default]').forEach((select)=>select.onchange=()=>{routing.assignments[select.dataset.aiDefault].provider=select.value;markDirty();render();});
  root.querySelectorAll('[data-ai-override]').forEach((select)=>select.onchange=()=>{const [workspaceId,mode]=select.dataset.aiOverride.split(':');const assignment=routing.assignments[workspaceId];assignment.overrides ||= {};if(select.value)assignment.overrides[mode]=select.value;else delete assignment.overrides[mode];markDirty();render();});
  root.querySelectorAll('[data-delete-ai-route]').forEach((button)=>button.onclick=()=>{delete routing.assignments[button.dataset.deleteAiRoute];markDirty();render();});
  root.querySelectorAll('[data-delete-ai-provider]').forEach((button)=>button.onclick=()=>{const id=button.dataset.deleteAiProvider;if(Object.values(routing.assignments).some((assignment)=>assignment.provider===id||Object.values(assignment.overrides||{}).includes(id)))return toast('Reassign workspaces before removing this provider.',true);delete providers[id];markDirty();render();});
  root.querySelector('#add-ai-provider').onclick=()=>{const id=root.querySelector('#ai-provider-id').value.trim();const name=root.querySelector('#ai-provider-name').value.trim();if(!validId(id)||!name||providers[id])return toast('Choose a unique lowercase provider ID and a display name.',true);providers[id]={name,app:root.querySelector('#ai-provider-app').value};markDirty();render();};
  root.querySelector('#add-ai-route').onclick=()=>{const workspaceId=root.querySelector('#ai-route-workspace').value;if(routing.assignments[workspaceId])return toast('This workspace already has an AI route.',true);routing.assignments[workspaceId]={role:root.querySelector('#ai-route-role').value,provider:root.querySelector('#ai-route-provider').value,overrides:{}};markDirty();render();};
}

function appsView() {
  const running = new Set(state.appInventory?.apps || []); const query=state.appSearch.toLowerCase();
  const references=(appId)=>[...Object.entries(state.config.workspaces).flatMap(([workspaceId,workspace])=>{
    const results=[];
    for(const [role,window] of Object.entries(workspace.windows)) if(window.app===appId) results.push(`${workspace.name||workspaceId} · ${role}`);
    for(const [mode,variant] of Object.entries(workspace.variants)) for(const runtimeWindow of variant.runtime?.windows||[]) if(runtimeWindow.app_key===appId) results.push(`${workspace.name||workspaceId} · ${mode} runtime · ${runtimeWindow.role}`);
    return [...new Set(results)];
  }), ...Object.entries(state.config.aiProviders || {}).filter(([,provider])=>provider.app===appId).map(([providerId])=>`AI provider · ${providerId}`)];
  const rows=Object.entries(state.config.apps).filter(([id,app])=>`${id} ${app.name} ${app.match.appNames.join(' ')} ${(app.match.bundleIds||[]).join(' ')}`.toLowerCase().includes(query)).map(([id,app])=>{const used=references(id);const detected=running.has(app.name)||app.match.appNames.some((name)=>running.has(name));return `<details class="app-list-row"><summary><span class="app-name-cell"><i class="app-avatar">${escapeHtml(app.name.slice(0,2).toUpperCase())}</i><span><strong>${escapeHtml(app.name)}</strong><small>${escapeHtml(id)}</small></span></span><span><b class="detection ${detected?'detected':''}">${state.appInventory ? detected?'Running':'Not detected':'Not checked'}</b></span><span>${escapeHtml(app.match.appNames.join(', '))}</span><span>${used.length?escapeHtml(used.join(', ')):'—'}</span><span>Expand</span></summary><div class="app-row-editor"><div class="field"><label>Display name</label><input data-app-name="${id}" value="${escapeHtml(app.name)}"></div><div class="field"><label>macOS aliases</label><input data-app-aliases="${id}" value="${escapeHtml(app.match.appNames.join(', '))}"></div><div class="field"><label>Bundle identifiers</label><input data-app-bundles="${id}" value="${escapeHtml((app.match.bundleIds||[]).join(', '))}" placeholder="com.example.App"></div><div class="actions"><button class="quiet" data-rename-app="${id}">Rename ID</button><button class="danger" data-delete-app="${id}">Delete App</button></div></div></details>`;}).join('');
  const unmatched=(state.appInventory?.apps||[]).filter((name)=>!Object.values(state.config.apps).some((app)=>app.name===name||app.match.appNames.includes(name)));
  root.innerHTML = title('Application registry', 'Applications at a glance', 'Search the shared registry used by every Workspace picker. Expand a row only when details need editing.', '<button id="discover-apps" class="quiet">Discover Open Apps</button><button id="add-app" class="primary">+ Add Application</button>') + `<label class="workspace-search app-search"><span>Search applications</span><input id="app-search" data-ui-only type="search" placeholder="Name, stable ID or alias" value="${escapeHtml(state.appSearch)}"></label>${state.appInventory?`<div class="discovery-summary"><strong>${running.size} open · ${running.size-unmatched.length} matched · ${unmatched.length} not registered</strong>${unmatched.length?`<p>${unmatched.map((name)=>`<button class="shortcut-pill" data-add-discovered="${escapeHtml(name)}">+ ${escapeHtml(name)}</button>`).join(' ')}</p>`:'<p>Every open application matches the registry.</p>'}</div>`:''}<div class="app-list-head"><span>App</span><span>Detection</span><span>Aliases</span><span>Used By</span><span>Actions</span></div><div class="app-list">${rows||'<p class="empty-lane">No applications match your search.</p>'}</div>`;
  root.querySelectorAll('[data-app-name]').forEach((input) => input.oninput = () => state.config.apps[input.dataset.appName].name = input.value);
  root.querySelectorAll('[data-app-aliases]').forEach((input) => input.oninput = () => state.config.apps[input.dataset.appAliases].match.appNames = input.value.split(',').map((v) => v.trim()).filter(Boolean));
  root.querySelectorAll('[data-app-bundles]').forEach((input) => input.oninput = () => { const values=input.value.split(',').map((v)=>v.trim()).filter(Boolean); if(values.length)state.config.apps[input.dataset.appBundles].match.bundleIds=values;else delete state.config.apps[input.dataset.appBundles].match.bundleIds; });
  root.querySelector('#app-search').oninput=(event)=>{state.appSearch=event.target.value;appsView();root.querySelector('#app-search').focus();};
  const addApp=(name)=>{let id=(name||'application').toLowerCase().replace(/[^a-z0-9]+/g,'_').replace(/^([^a-z])/,'app_$1');let i=2,base=id;while(state.config.apps[id])id=`${base}_${i++}`;state.config.apps[id]={name:name||'Application',match:{appNames:[name||'Application']}};markDirty();render();};
  root.querySelector('#add-app').onclick = async () => { const name=await promptValue('Application Display Name','Application'); if(name?.trim())addApp(name.trim()); };
  root.querySelectorAll('[data-add-discovered]').forEach((button)=>button.onclick=()=>addApp(button.dataset.addDiscovered));
  root.querySelectorAll('[data-rename-app]').forEach((button) => button.onclick = async () => {
    const oldId = button.dataset.renameApp; const newId = await requestId('New Application ID', oldId, state.config.apps); if (!newId) return;
    renameKey(state.config.apps, oldId, newId);
    for (const provider of Object.values(state.config.aiProviders || {})) if (provider.app === oldId) provider.app = newId;
    for (const workspace of Object.values(state.config.workspaces)) for (const window of Object.values(workspace.windows)) if (window.app === oldId) window.app = newId;
    for (const workspace of Object.values(state.config.workspaces)) for (const variant of Object.values(workspace.variants)) for (const runtimeWindow of variant.runtime?.windows || []) if (runtimeWindow.app_key === oldId) runtimeWindow.app_key = newId;
    markDirty(); render();
  });
  root.querySelectorAll('[data-delete-app]').forEach((button) => button.onclick = async () => {
    const id = button.dataset.deleteApp; const appReferences = references(id);
    if (appReferences.length) return toast(`Application “${id}” is used by: ${appReferences.join(', ')}. Reassign those roles first.`, true);
    if (Object.keys(state.config.apps).length === 1) return toast('A configuration must keep at least 1 application.', true);
    if (!await confirmAction(`Delete application “${id}”?`, { confirmLabel: 'Delete Application', danger: true })) return;
    delete state.config.apps[id]; markDirty(); render();
  });
  root.querySelector('#discover-apps').onclick = async () => { try { state.appInventory=await request('/api/apps'); appsView(); if(state.appInventory.unavailable)toast(state.appInventory.message||'Open app discovery unavailable',true); } catch (error) { toast(error.message, true); } };
}

function shortcutsView() {
  const shortcuts = state.config.shortcuts || [];
  const conflicts = shortcutConflicts();
  const currentOrder = (state.config.modes[state.mode]?.displays || []).flatMap((display) => display.workspaceOrder);
  const workspaceNumber=(workspaceId)=>{const direct=[...shortcuts,...state.externalShortcuts].find((item)=>item.action.type==='activateWorkspace'&&item.action.workspace===workspaceId&&/^[0-9]$/.test(item.keys.key));if(direct)return Number(direct.keys.key);if(workspaceId.startsWith('coding_')&&state.externalShortcuts.some((item)=>item.action.type==='externalCommand'&&/^coding_(solo|tall|wide)$/.test(item.action.command)))return 1;return 99;};
  const orderedWorkspaceIds=ids(state.config.workspaces).sort((a,b)=>workspaceNumber(a)-workspaceNumber(b)||(currentOrder.indexOf(a)<0?99:currentOrder.indexOf(a))-(currentOrder.indexOf(b)<0?99:currentOrder.indexOf(b))||a.localeCompare(b));
  const workspaceRows = orderedWorkspaceIds.map((workspaceId) => { const index = currentOrder.indexOf(workspaceId);const number=workspaceNumber(workspaceId);const groupOnly=number===1&&workspaceId.startsWith('coding_')&&!shortcuts.some((item)=>item.action.type==='activateWorkspace'&&item.action.workspace===workspaceId); return `<tr><th><span class="sequence-key">${number<10?number:'—'}</span>${escapeHtml(state.config.workspaces[workspaceId].name)}<small>${escapeHtml(workspaceId)} · ${groupOnly?'covered by external Coding group':index>=0?`Space ${index+1} in ${escapeHtml(state.mode)}`:'not included in this Work Mode'}</small></th>${MODES.map((mode) => { const matches = shortcuts.filter((item) => item.action.type === 'activateWorkspace' && item.action.workspace === workspaceId && item.action.mode === mode); const external=externalShortcut(workspaceId,mode); return `<td>${matches.length ? matches.map((item) => `<button class="shortcut-pill" data-edit-shortcut="${escapeHtml(item.id)}">${escapeHtml(chordLabel(item.keys))}</button>`).join(' ') : external ? `<span class="external-binding">${escapeHtml(chordLabel(external.keys))}<small>External · not yet imported</small></span>` : groupOnly?`<span class="group-binding">${escapeHtml(mode)} via coding_${escapeHtml(mode)}</span>`:'<span class="not-configured">Not configured</span>'}</td>`; }).join('')}</tr>`; }).join('');
  const managedChordKeys=new Set(shortcuts.map((shortcut)=>chordKey(shortcut.keys)));
  const externalOnly=state.externalShortcuts.filter((shortcut)=>!managedChordKeys.has(chordKey(shortcut.keys)));
  const keyRows = [...shortcuts].sort((a, b) => chordKey(a.keys).localeCompare(chordKey(b.keys))).map((shortcut) => `<tr><th><button class="shortcut-pill" data-edit-shortcut="${escapeHtml(shortcut.id)}">${escapeHtml(chordLabel(shortcut.keys))}</button></th><td>${escapeHtml(actionLabel(shortcut))}<small>Managed by v2</small></td><td><button class="quiet" data-clear-shortcut="${escapeHtml(shortcut.id)}">Clear</button></td></tr>`).join('')+externalOnly.sort((a,b)=>chordKey(a.keys).localeCompare(chordKey(b.keys))).map((shortcut)=>`<tr><th><span class="external-binding">${escapeHtml(chordLabel(shortcut.keys))}</span></th><td>${escapeHtml(actionLabel(shortcut))}<small>${escapeHtml(shortcut.source)} · external</small></td><td>${shortcut.action.type==='externalCommand'?'<span class="not-configured">Display only</span>':'<span class="not-configured">Available to import</span>'}</td></tr>`).join('');
  const table = state.shortcutView === 'workspace' ? `<table class="shortcut-table"><thead><tr><th>Workspace / number</th>${MODES.map((mode) => `<th>${mode}</th>`).join('')}</tr></thead><tbody>${workspaceRows}</tbody></table>` : `<table class="shortcut-table"><thead><tr><th>Actual key</th><th>Triggers</th><th>Action</th></tr></thead><tbody>${keyRows || '<tr><td colspan="3">No configured shortcuts</td></tr>'}</tbody></table>`;
  const importable=state.externalShortcuts.filter((external)=>!shortcuts.some((item)=>JSON.stringify(item.action)===JSON.stringify(external.action)&&chordKey(item.keys)===chordKey(external.keys)));
  const modeOverview=MODES.map((mode)=>{const managed=shortcuts.find((item)=>item.action.type==='activateMode'&&item.action.mode===mode);const external=state.externalShortcuts.find((item)=>item.action.type==='activateMode'&&item.action.mode===mode);return `<article><strong>${mode}</strong><span>${managed||external?escapeHtml(chordLabel((managed||external).keys)):'—'}</span><small>${managed?'Managed by v2':external?'External binding':'Not configured'}</small></article>`;}).join('');
  const safeImportable=importable.filter((item)=>item.action.type!=='externalCommand');
  const numericBindings=[...shortcuts,...externalOnly].filter((item)=>/^[0-9]$/.test(item.keys.key));
  const numberRows=Array.from({length:10},(_,number)=>{const bindings=numericBindings.filter((item)=>item.keys.key===String(number));return `<tr><th><span class="number-keycap">${number}</span></th><td>${bindings.length?bindings.map((item)=>`<div class="number-binding"><span>${escapeHtml(chordLabel(item.keys))}</span><strong>${escapeHtml(actionLabel(item))}</strong><small>${item.action.type==='externalCommand'?'External Workspace group':item.action.type==='activateMode'?'Work Mode':'Workspace'}</small></div>`).join(''):'<span class="not-configured">No binding</span>'}</td></tr>`;}).join('');
  root.innerHTML = title('Keyboard layer', 'Actual configured shortcuts', 'The 0–9 map includes Work Modes, individual Workspaces, and legacy Workspace groups. Safe legacy bindings are automatically added to the v2 draft; saving remains your explicit choice.', '<button id="scan-shortcuts" class="quiet">Rescan existing bindings</button><button id="restore-shortcuts" class="quiet">Restore saved bindings</button><button id="generate-skhd" class="primary">Generate Fragment</button>') + `${state.autoImportedShortcuts?`<div class="auto-import-summary"><strong>${state.autoImportedShortcuts} existing binding${state.autoImportedShortcuts===1?'':'s'} added to the v2 draft</strong><span>Review them below, then Save configuration when ready. The original skhd file has not been changed.</span></div>`:''}<section class="mode-shortcut-overview"><div class="shortcut-section-title"><div><p class="kicker">Mode shortcuts</p><strong>work_solo · work_tall · work_wide</strong></div><button class="quiet" id="configure-work-modes">Configure included Workspaces →</button></div><div>${modeOverview}</div></section><details class="number-map" open><summary><span><b>Actual 0–9 number map</b><small>Read from the v2 draft and active skhd configuration</small></span></summary><div class="table-wrap"><table class="shortcut-table number-map-table"><tbody>${numberRows}</tbody></table></div></details>${importable.length?`<div class="migration-preview"><strong>${safeImportable.length} newly mappable binding${safeImportable.length===1?'':'s'} · ${importable.length-safeImportable.length} legacy Workspace-group command${importable.length-safeImportable.length===1?'':'s'} kept read-only</strong><p>Inspected: ${escapeHtml(state.shortcutSources.join(', ')||'SpaceWright sources')}</p><ul>${importable.map((item)=>`<li>${escapeHtml(chordLabel(item.keys))} → ${escapeHtml(actionLabel(item))}${item.action.type==='externalCommand'?' · Workspace group; not one Workspace':shortcuts.some((existing)=>chordKey(existing.keys)===chordKey(item.keys))?' · conflict':''}</li>`).join('')}</ul></div>`:''}${conflicts.length ? `<div class="conflict-banner"><strong>${conflicts.length} conflict${conflicts.length === 1 ? '' : 's'} block saving</strong>${conflicts.map(([a,b]) => `<p>${escapeHtml(chordLabel(a.keys))}: ${escapeHtml(actionLabel(a))} conflicts with ${escapeHtml(actionLabel(b))}</p>`).join('')}</div>` : ''}<div class="shortcut-view-switch"><button data-shortcut-view="workspace" class="${state.shortcutView === 'workspace' ? 'active' : ''}">By Workspace</button><button data-shortcut-view="key" class="${state.shortcutView === 'key' ? 'active' : ''}">By Key</button></div><p class="workspace-binding-note">Rows are ordered by actual number key. “Not configured” means there is no shortcut targeting that single Workspace; it may still run as part of a Work Mode or Workspace group.</p><div class="table-wrap">${table}</div><article class="card shortcut-builder"><h3>Add a binding</h3><div class="row"><div class="field"><label>Action</label><select id="shortcut-action" data-ui-only><option value="workspace">Activate Workspace</option><option value="mode">Activate Mode</option></select></div><div class="field"><label>Mode</label><select id="shortcut-mode" data-ui-only>${MODES.map((mode) => `<option>${mode}</option>`).join('')}</select></div></div><div class="field" id="shortcut-workspace-field"><label>Workspace</label><select id="shortcut-workspace" data-ui-only>${ids(state.config.workspaces).map((id) => `<option value="${id}">${escapeHtml(state.config.workspaces[id].name)}</option>`).join('')}</select></div><button id="capture-new-shortcut" class="primary">Record key combination</button><p class="layout-hint">Existing bindings are never overwritten. Fn can be selected manually in the recorder.</p></article>`;
  root.querySelector('#configure-work-modes').onclick=()=>{state.view='map';render();};
  root.querySelectorAll('[data-shortcut-view]').forEach((button) => button.onclick = () => { state.shortcutView = button.dataset.shortcutView; render(); });
  root.querySelectorAll('[data-edit-shortcut]').forEach((button) => button.onclick = () => { const shortcut = shortcuts.find((item) => item.id === button.dataset.editShortcut); if (!shortcut) return; recordShortcut((keys) => { const conflict = shortcuts.find((item) => item.id !== shortcut.id && chordKey(item.keys) === chordKey(keys)); if (conflict) return toast(`${chordLabel(keys)} already triggers ${actionLabel(conflict)}. Binding unchanged.`, true); shortcut.keys = keys; markDirty(); render(); }); });
  root.querySelector('#shortcut-action').onchange = (event) => { root.querySelector('#shortcut-workspace-field').hidden = event.target.value === 'mode'; };
  root.querySelector('#capture-new-shortcut').onclick = () => recordShortcut((keys) => { const conflict = shortcuts.find((item) => chordKey(item.keys) === chordKey(keys)); if (conflict) return toast(`${chordLabel(keys)} already triggers ${actionLabel(conflict)}. Nothing was changed.`, true); const mode = root.querySelector('#shortcut-mode').value; const action = root.querySelector('#shortcut-action').value === 'mode' ? { type: 'activateMode', mode } : { type: 'activateWorkspace', workspace: root.querySelector('#shortcut-workspace').value, mode }; shortcuts.push({ id: crypto.randomUUID(), keys, action }); markDirty(); render(); });
  root.querySelector('#scan-shortcuts').onclick=async()=>{try{const result=await request('/api/shortcuts');state.externalShortcuts=result.bindings||[];state.shortcutSources=result.inspected||[];autoImportExternalShortcuts();if(state.autoImportedShortcuts)markDirty();render();}catch(error){toast(error.message,true);}};
  root.querySelector('#restore-shortcuts').onclick = async () => { if (!await confirmAction('Restore all shortcut bindings to the currently saved version?', { confirmLabel: 'Restore Shortcuts', danger: true })) return; state.config.shortcuts = structuredClone(state.savedConfig.shortcuts || []); state.autoImportedShortcuts = 0; markDirty(); render(); };
  root.querySelectorAll('[data-clear-shortcut]').forEach((button) => button.onclick = async () => { const index = shortcuts.findIndex((item) => item.id === button.dataset.clearShortcut); if (index >= 0 && await confirmAction(`Clear ${actionLabel(shortcuts[index])}?`, { confirmLabel: 'Clear Shortcut', danger: true })) { shortcuts.splice(index, 1); markDirty(); render(); } });
  root.querySelector('#generate-skhd').onclick = async () => { try { const result = await request('/api/skhd', { method: 'POST', body: JSON.stringify(state.config) }); toast(`Generated ${result.path}`); } catch (error) { toast(error.message, true); } };
}

function automationView() {
  const profileConfig = state.config.profiles || {};
  const ruleConfig = state.config.rules || [];
  const settings = state.config.settings || {};
  const profiles = Object.entries(profileConfig).map(([id, profile]) => `<article class="card profile-editor"><p class="kicker">${escapeHtml(id)}</p><div class="field"><label>Name</label><input data-profile-name="${id}" value="${escapeHtml(profile.name)}"></div><div class="row"><div class="field"><label>Mode</label><select data-profile-mode="${id}">${MODES.map((mode) => `<option ${profile.mode === mode ? 'selected' : ''}>${mode}</option>`).join('')}</select></div><div class="field"><label>Display profile</label><select data-profile-display="${id}"><option value="">Do not change displays</option>${['solo','wide_left','tall_left'].map((value) => `<option ${profile.displayConfig?.profile === value ? 'selected' : ''}>${value}</option>`).join('')}</select></div></div><div class="field"><label>Final workspace focus</label><select data-profile-focus="${id}"><option value="">Keep runner result</option>${Object.entries(state.config.workspaces).map(([workspaceId, workspace]) => `<option value="${workspaceId}" ${profile.focusBehaviour?.workspace === workspaceId ? 'selected' : ''}>${escapeHtml(workspace.name)}</option>`).join('')}</select></div><details><summary>Included workspaces · ${(profile.workspaces || []).length || 'all in mode'}</summary><div class="profile-workspaces">${Object.entries(state.config.workspaces).filter(([, workspace]) => workspace.variants?.[profile.mode]).map(([workspaceId, workspace]) => `<label class="check"><input type="checkbox" data-profile-workspace="${id}" value="${workspaceId}" ${(profile.workspaces || []).includes(workspaceId) ? 'checked' : ''}> ${escapeHtml(workspace.name)}</label>`).join('')}</div></details><label class="check"><input type="checkbox" data-profile-reconcile="${id}" ${profile.settings?.reconcile !== false ? 'checked' : ''}> Retry once when verified drift remains</label><div class="actions"><button class="quiet" data-preview-profile="${id}">Dry run</button><button class="danger" data-delete-profile="${id}">Delete</button></div></article>`).join('');
  const rules = ruleConfig.map((rule, index) => `<article class="card"><p class="kicker">${escapeHtml(rule.id)}</p><h3>${escapeHtml(rule.when.event)}</h3><p>${escapeHtml(rule.when.topology || rule.when.orientation || 'any topology')} → ${escapeHtml(rule.then.activateProfile || rule.then.activateWorkspace)}</p><label class="check"><input type="checkbox" data-rule-enabled="${index}" ${rule.enabled ? 'checked' : ''}> Enabled</label><button class="danger" data-delete-rule="${index}">Delete</button></article>`).join('');
  root.innerHTML = title('Automation', 'Profiles, workspace restore & event rules', 'Profiles bundle mode, display, workspace, geometry and focus settings. Every activation can be previewed without moving windows.', '<button id="evaluate-rules" class="quiet">Evaluate current topology</button><button id="preview-mode" class="quiet">Preview current mode</button>') + `<section class="automation-settings"><label class="check automation-toggle"><input id="automation-enabled" type="checkbox" ${settings.eventAutomationEnabled ? 'checked' : ''}> Automatically run matching enabled rules while this configurator service is running. Save configuration to apply.</label><div class="row"><div class="field"><label for="topology-samples">Stable observations</label><input id="topology-samples" type="number" min="1" max="12" value="${settings.topologyStableSamples || 3}"></div><div class="field"><label for="topology-cooldown">Cooldown seconds</label><input id="topology-cooldown" type="number" min="0" max="600" value="${settings.topologyCooldownSeconds ?? 30}"></div></div></section><div id="dry-run-output"></div><div class="cards">${profiles}<article class="card"><h3>Add profile</h3><div class="field"><label for="profile-id">ID</label><input id="profile-id" value="research"></div><div class="field"><label for="profile-name">Name</label><input id="profile-name" value="Research"></div><div class="field"><label for="profile-mode">Mode</label><select id="profile-mode"><option>solo</option><option>wide</option><option>tall</option></select></div><button id="add-profile" class="primary">Add Profile</button></article></div><div class="section-head compact"><div><p class="kicker">Rule engine</p><h2>Event-driven activation</h2></div></div><div class="cards">${rules}<article class="card"><h3>Add topology rule</h3><div class="field"><label for="rule-event">Event</label><select id="rule-event"><option>display_connected</option><option>display_disconnected</option><option>topology_changed</option><option>wake</option><option>manual</option></select></div><div class="field"><label for="rule-topology">Topology</label><select id="rule-topology"><option value="">Any</option>${['solo','wide_left','wide_right','tall_left','tall_right','dual_external','clamshell'].map((item) => `<option>${item}</option>`).join('')}</select></div><div class="field"><label for="rule-profile">Activate profile</label><select id="rule-profile">${Object.entries(profileConfig).map(([id, profile]) => `<option value="${id}">${escapeHtml(profile.name)}</option>`).join('')}</select></div><button id="add-rule" class="primary" ${Object.keys(profileConfig).length ? '' : 'disabled'}>Add Rule</button></article></div>`;
  const showPlan = async (profile) => { try { const result = await request('/api/preview', { method: 'POST', body: JSON.stringify({ config: state.config, profile, mode: state.mode }) }); root.querySelector('#dry-run-output').innerHTML = planPreview(result); } catch (error) { toast(error.message, true); } };
  root.querySelector('#preview-mode').onclick = () => showPlan(null);
  root.querySelector('#automation-enabled').onchange = (event) => { (state.config.settings ||= {}).eventAutomationEnabled = event.target.checked; markDirty(); };
  root.querySelector('#topology-samples').onchange = (event) => { (state.config.settings ||= {}).topologyStableSamples = Math.max(1, Math.min(12, Number(event.target.value) || 3)); markDirty(); };
  root.querySelector('#topology-cooldown').onchange = (event) => { (state.config.settings ||= {}).topologyCooldownSeconds = Math.max(0, Math.min(600, Number(event.target.value) || 0)); markDirty(); };
  root.querySelector('#evaluate-rules').onclick = async () => { try { const result = await request('/api/rules/evaluate', { method: 'POST', body: JSON.stringify({ config: state.config, event: 'manual', execute: false }) }); root.querySelector('#dry-run-output').innerHTML = `<div class="change-summary"><strong>Draft rule evaluation · no desktop changes</strong><pre>${escapeHtml(JSON.stringify(result, null, 2))}</pre></div>`; } catch (error) { toast(error.message, true); } };
  root.querySelectorAll('[data-preview-profile]').forEach((button) => button.onclick = () => showPlan(button.dataset.previewProfile));
  root.querySelector('#add-profile').onclick = () => { const id = root.querySelector('#profile-id').value.trim(); if (!validId(id) || profileConfig[id]) return toast('Choose a unique lowercase profile ID.', true); (state.config.profiles ||= {})[id] = { name: root.querySelector('#profile-name').value.trim(), mode: root.querySelector('#profile-mode').value, workspaces: [], settings: { reconcile: true } }; markDirty(); render(); };
  root.querySelectorAll('[data-profile-name]').forEach((input) => { input.setAttribute('aria-label', `Name for profile ${input.dataset.profileName}`); input.onchange = () => { state.config.profiles[input.dataset.profileName].name = input.value.trim(); markDirty(); }; });
  root.querySelectorAll('[data-profile-mode]').forEach((select) => { select.setAttribute('aria-label', `Mode for profile ${select.dataset.profileMode}`); select.onchange = () => { const profile = state.config.profiles[select.dataset.profileMode]; profile.mode = select.value; profile.workspaces = (profile.workspaces || []).filter((workspaceId) => state.config.workspaces[workspaceId]?.variants?.[select.value]); if (profile.focusBehaviour?.workspace && !state.config.workspaces[profile.focusBehaviour.workspace]?.variants?.[select.value]) delete profile.focusBehaviour; markDirty(); render(); }; });
  root.querySelectorAll('[data-profile-display]').forEach((select) => { select.setAttribute('aria-label', `Display profile for ${select.dataset.profileDisplay}`); select.onchange = () => { const profile = state.config.profiles[select.dataset.profileDisplay]; if (select.value) profile.displayConfig = { profile: select.value }; else delete profile.displayConfig; markDirty(); }; });
  root.querySelectorAll('[data-profile-focus]').forEach((select) => { select.setAttribute('aria-label', `Final focus for profile ${select.dataset.profileFocus}`); select.onchange = () => { const profile = state.config.profiles[select.dataset.profileFocus]; if (select.value) { profile.focusBehaviour = { workspace: select.value }; if (profile.workspaces?.length && !profile.workspaces.includes(select.value)) profile.workspaces.push(select.value); } else delete profile.focusBehaviour; markDirty(); render(); }; });
  root.querySelectorAll('[data-profile-workspace]').forEach((input) => input.onchange = () => { const profile = state.config.profiles[input.dataset.profileWorkspace]; profile.workspaces = [...root.querySelectorAll(`[data-profile-workspace="${input.dataset.profileWorkspace}"]:checked`)].map((item) => item.value); if (profile.focusBehaviour?.workspace && profile.workspaces.length && !profile.workspaces.includes(profile.focusBehaviour.workspace)) delete profile.focusBehaviour; markDirty(); render(); });
  root.querySelectorAll('[data-profile-reconcile]').forEach((input) => input.onchange = () => { const profile = state.config.profiles[input.dataset.profileReconcile]; profile.settings ||= {}; profile.settings.reconcile = input.checked; markDirty(); });
  root.querySelectorAll('[data-delete-profile]').forEach((button) => button.onclick = () => { const id = button.dataset.deleteProfile; if (ruleConfig.some((rule) => rule.then.activateProfile === id)) return toast('Delete rules that use this profile first.', true); delete state.config.profiles[id]; markDirty(); render(); });
  root.querySelectorAll('[data-rule-enabled]').forEach((input) => input.onchange = () => { state.config.rules[Number(input.dataset.ruleEnabled)].enabled = input.checked; markDirty(); });
  root.querySelectorAll('[data-delete-rule]').forEach((button) => button.onclick = () => { state.config.rules.splice(Number(button.dataset.deleteRule), 1); markDirty(); render(); });
  root.querySelector('#add-rule').onclick = () => { const topology = root.querySelector('#rule-topology').value; const when = { event: root.querySelector('#rule-event').value, ...(topology ? { topology } : {}) }; const rules = state.config.rules ||= []; let number = 1; while (rules.some((rule) => rule.id === `rule_${number}`)) number++; rules.push({ id: `rule_${number}`, enabled: true, when, then: { activateProfile: root.querySelector('#rule-profile').value } }); markDirty(); render(); };
}

async function historyView(epoch = renderEpoch) {
  root.innerHTML = title('Run history', 'Workspace activity & restore points', 'Loading keyboard, CLI and configuration history…') + '<div class="history-loading" aria-live="polite">Reading local history…</div>';
  try {
    const [{ snapshots }, { transitions, retention }] = await Promise.all([request('/api/history'), request('/api/transition-history')]);
    if (!viewIsCurrent('history', epoch)) return;
    const completed = transitions.filter((item) => item.status === 'completed').length;
    const latest = transitions[0];
    const formatTime = (value) => value ? new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value)) : 'In progress';
    const formatDuration = (value) => value === null || value === undefined ? 'Running' : value < 1000 ? `${value} ms` : `${(value / 1000).toFixed(value < 10_000 ? 1 : 0)} s`;
    const transitionMarkup = (item) => {
      const warnings = item.warnings || []; const skipped = item.skipped || []; const errors = item.errors || [];
      return `<article class="transition-row status-${escapeHtml(item.status)}" data-transition-status="${escapeHtml(item.status)}" data-transition-scope="${escapeHtml(item.scope || 'mode')}"><div class="transition-rail" aria-hidden="true"></div><div class="transition-main"><header><span class="status-pill">${escapeHtml(String(item.status || 'unknown').replaceAll('_', ' '))}</span><span class="transition-scope">${escapeHtml(item.scope || 'mode')}</span><time datetime="${escapeHtml(item.startedAt)}">${escapeHtml(formatTime(item.startedAt))}</time></header><h3>${escapeHtml(item.targetLabel || item.workspace || item.mode || 'Workspace transition')}</h3><p>${escapeHtml(item.phase || 'No final message recorded')}</p><div class="transition-facts"><span><b>${escapeHtml(formatDuration(item.durationMs))}</b> duration</span><span><b>${item.step || 0}</b> phases</span><span><b>${warnings.length}</b> warnings</span><span><b>${skipped.length}</b> skipped</span></div></div><details class="transition-detail"><summary>Inspect diagnostics</summary><dl><div><dt>Run ID</dt><dd>${escapeHtml(item.runId)}</dd></div><div><dt>Target</dt><dd>${escapeHtml(item.targetKey || `${item.scope}:${item.workspace || item.mode}`)}</dd></div><div><dt>Started from</dt><dd>${escapeHtml(item.sourceSpaceLabel || 'Unlabeled Space')}</dd></div></dl>${errors.length ? `<section><h4>Failure signals</h4><ul>${errors.map((line) => `<li>${escapeHtml(line)}</li>`).join('')}</ul></section>` : ''}${skipped.length ? `<section><h4>Skipped or unavailable</h4><ul>${skipped.map((line) => `<li>${escapeHtml(line)}</li>`).join('')}</ul></section>` : ''}${warnings.length ? `<section><h4>Warnings</h4><ul>${warnings.map((line) => `<li>${escapeHtml(line)}</li>`).join('')}</ul></section>` : ''}<section><h4>Log tail</h4><pre>${escapeHtml((item.logTail || []).join('\n') || 'No output was recorded.')}</pre></section></details></article>`;
    };
    root.innerHTML = title('Run history', 'Workspace activity & restore points', 'Every guarded keyboard and CLI transition is kept locally with its target, duration, outcome and diagnostic signals.', '<button id="refresh-history" class="quiet">Refresh</button><button id="clear-transition-history" class="danger">Clear run history</button>') + `<section class="history-metrics" aria-label="Run history summary"><article><span>Recorded runs</span><strong>${transitions.length}</strong><small>latest ${Math.min(transitions.length, retention)} of ${retention} retained</small></article><article><span>Completion rate</span><strong>${transitions.length ? Math.round((completed / transitions.length) * 100) : 0}%</strong><small>${completed} completed</small></article><article><span>Latest target</span><strong>${escapeHtml(latest?.targetLabel || 'No runs')}</strong><small>${escapeHtml(latest ? formatTime(latest.startedAt) : 'Use a workspace shortcut to begin')}</small></article><article><span>Latest result</span><strong class="metric-status status-${escapeHtml(latest?.status || 'idle')}">${escapeHtml(latest?.status || 'idle')}</strong><small>${latest ? `${latest.warnings?.length || 0} warnings · ${latest.skipped?.length || 0} skipped` : 'Nothing recorded yet'}</small></article></section><section class="history-toolbar"><label>Status<select id="history-status"><option value="all">All results</option>${['completed','running','failed','cancelled','replaced','timed_out'].map((status) => `<option value="${status}">${status.replaceAll('_', ' ')}</option>`).join('')}</select></label><label>Scope<select id="history-scope"><option value="all">All targets</option><option value="workspace">Workspace</option><option value="mode">Whole mode</option></select></label><span id="history-count" aria-live="polite"></span></section><div id="transition-list" class="transition-list"></div><div class="section-head compact"><div><p class="kicker">Configuration history</p><h2>Snapshots & restore points</h2><p>Compare, rename, restore or delete saved configuration versions.</p></div></div><div class="cards">${snapshots.map((snapshot) => `<article class="card"><p class="kicker">${escapeHtml(snapshot.reason)}</p><h3>${escapeHtml(snapshot.name)}</h3><p>${escapeHtml(formatTime(snapshot.createdAt))}</p><div class="actions"><button class="quiet" data-compare-snapshot="${snapshot.id}">Compare</button><button class="quiet" data-rename-snapshot="${snapshot.id}">Rename</button><button class="primary" data-restore-snapshot="${snapshot.id}">Restore</button><button class="danger" data-delete-snapshot="${snapshot.id}">Delete</button></div></article>`).join('') || '<div class="empty-lane">No snapshots yet. Save a configuration to create one.</div>'}</div><div id="snapshot-compare"></div>`;
    const renderTransitions = () => {
      const status = root.querySelector('#history-status').value; const scope = root.querySelector('#history-scope').value;
      const visible = transitions.filter((item) => (status === 'all' || item.status === status) && (scope === 'all' || (item.scope || 'mode') === scope));
      root.querySelector('#transition-list').innerHTML = visible.map(transitionMarkup).join('') || '<div class="empty-lane history-empty"><strong>No matching transitions</strong><span>Change the filters or use a workspace shortcut to create a record.</span></div>';
      root.querySelector('#history-count').textContent = `${visible.length} shown`;
    };
    renderTransitions();
    root.querySelector('#history-status').onchange = renderTransitions;
    root.querySelector('#history-scope').onchange = renderTransitions;
    root.querySelector('#refresh-history').onclick = render;
    root.querySelector('#clear-transition-history').onclick = async () => { if (!transitions.length) return toast('Run history is already empty'); if (!await confirmAction('Clear all recorded workspace and mode transitions?', { confirmLabel: 'Clear Run History', danger: true })) return; await request('/api/transition-history', { method: 'DELETE' }); toast('Run history cleared'); render(); };
    root.querySelectorAll('[data-compare-snapshot]').forEach((button) => button.onclick = async () => { const result = await request(`/api/history/${button.dataset.compareSnapshot}`); root.querySelector('#snapshot-compare').innerHTML = `<pre class="review-json">${escapeHtml(JSON.stringify(result.changes, null, 2))}</pre>`; });
    root.querySelectorAll('[data-rename-snapshot]').forEach((button) => button.onclick = async () => { const name = await promptValue('Snapshot Name'); if (!name) return; await request(`/api/history/${button.dataset.renameSnapshot}/rename`, { method: 'POST', body: JSON.stringify({ name }) }); render(); });
    root.querySelectorAll('[data-restore-snapshot]').forEach((button) => button.onclick = async () => { if (!await confirmAction('Restore this snapshot as the active configuration?', { confirmLabel: 'Restore Snapshot', danger: true })) return; const result = await request(`/api/history/${button.dataset.restoreSnapshot}/restore`, { method: 'POST' }); state.config = result.config; state.savedConfig = structuredClone(result.config); state.serverRevision = result.revision; state.source = 'v2'; state.requiresInitialSave = false; markClean('Local · restored'); render(); });
    root.querySelectorAll('[data-delete-snapshot]').forEach((button) => button.onclick = async () => { if (!await confirmAction('Delete this snapshot?', { confirmLabel: 'Delete Snapshot', danger: true })) return; await request(`/api/history/${button.dataset.deleteSnapshot}`, { method: 'DELETE' }); render(); });
  } catch (error) {
    if (!viewIsCurrent('history', epoch)) return;
    root.innerHTML = title('Run history', 'History is unavailable', 'No desktop changes were made.', '<button id="retry-history" class="quiet">Retry</button>') + `<div class="errors">${escapeHtml(error.message)}</div>`;
    root.querySelector('#retry-history').onclick = () => render();
  }
}

function mergeCapturedWorkspace(capture) {
  const draft = structuredClone(capture.draft);
  if (state.config.workspaces[draft.workspaceId]) throw new Error(`Workspace ID “${draft.workspaceId}” already exists.`);
  const appMap = {};
  for (const [capturedId, captured] of Object.entries(draft.apps || {})) {
    const aliases = captured.match?.appNames || [];
    const existing = Object.entries(state.config.apps).find(([, app]) => (app.match?.appNames || []).some((name) => aliases.includes(name)));
    if (existing) { appMap[capturedId] = existing[0]; continue; }
    let nextId = capturedId; let suffix = 2;
    while (state.config.apps[nextId]) nextId = `${capturedId}_${suffix++}`;
    state.config.apps[nextId] = captured;
    appMap[capturedId] = nextId;
  }
  for (const window of Object.values(draft.workspace.windows || {})) window.app = appMap[window.app] || window.app;
  state.config.workspaces[draft.workspaceId] = draft.workspace;
  const displayRole = Object.entries(state.machine.displayBindings || {}).find(([, uuid]) => uuid === capture.capturedFrom.displayUuid)?.[0];
  const lane = state.config.modes?.[capture.capturedFrom.mode]?.displays?.find((display) => display.role === displayRole);
  if (lane) lane.workspaceOrder.push(draft.workspaceId);
  state.selectedWorkspace = draft.workspaceId;
  state.mode = capture.capturedFrom.mode;
  state.workspaceTab = 'layout';
  markDirty();
  return { workspaceId: draft.workspaceId, assigned: Boolean(lane), displayRole };
}

async function currentView(epoch = renderEpoch) {
  root.innerHTML = title('Current state', 'What macOS is running now', 'Live discovery is read-only. Compare it with a workspace or mode before choosing whether to run anything.') + '<p>Discovering displays, Spaces and windows…</p>';
  try {
    const { snapshot } = await request('/api/state');
    if (!viewIsCurrent('current', epoch)) return;
    state.liveSnapshot = snapshot;
    if (snapshot.unavailable) {
      root.innerHTML = title('Current state', 'Live state is unavailable', 'SpaceWright will fail closed and will not infer a single-display setup when discovery fails.', '<button id="retry-state" class="quiet">Retry</button>') + `<div class="errors">${escapeHtml(snapshot.message || 'yabai discovery failed')}</div>`;
      root.querySelector('#retry-state').onclick = currentView;
      return;
    }
    const workspaceOptions = Object.entries(state.config.workspaces).filter(([, workspace]) => workspace.variants?.[state.mode]).map(([id, workspace]) => `<option value="${id}">${escapeHtml(workspace.name)} · ${escapeHtml(id)}</option>`).join('');
    const spaceOptions = snapshot.spaces.map((space) => `<option value="${escapeHtml(space.uuid)}">Space ${space.index}${space.label ? ` · ${escapeHtml(space.label)}` : ''}</option>`).join('');
    const displays = snapshot.displays.map((display) => {
      const spaces = snapshot.spaces.filter((space) => space.display === display.index);
      return `<article class="live-display"><header><div><p class="kicker">${escapeHtml(display.role || 'unbound')}</p><h3>${escapeHtml(display.label || `Display ${display.index}`)}</h3></div><span>${spaces.length} Spaces</span></header><div class="live-spaces">${spaces.map((space) => { const windows = snapshot.windows.filter((window) => window.space === space.index); return `<section class="live-space ${space.focused ? 'focused' : ''}"><strong>Space ${space.index}${space.focused ? ' · focused' : ''}</strong><small>${escapeHtml(space.label || 'unlabelled')} · ${escapeHtml(space.layout || 'layout unknown')}</small><div>${windows.map((window) => `<span title="Window ${window.id}">${escapeHtml(window.app || 'Unknown app')} <small>#${window.id}</small></span>`).join('') || '<em>No managed windows</em>'}</div></section>`; }).join('')}</div></article>`;
    }).join('');
    root.innerHTML = title('Current state', `${snapshot.displays.length} displays · ${snapshot.spaces.length} Spaces · ${snapshot.windows.length} windows`, `Captured ${new Date(snapshot.capturedAt).toLocaleString()}. Window titles are intentionally omitted from this overview.`, '<button id="refresh-state" class="quiet">Refresh</button>') +
      `<section class="live-controls"><article class="card"><p class="kicker">Compare</p><h3>Actual ↔ desired</h3>${modeSwitch()}<div class="field"><label for="current-workspace">Workspace</label><select id="current-workspace" data-ui-only>${workspaceOptions}</select></div><div class="actions"><button id="compare-workspace" class="primary" ${workspaceOptions ? '' : 'disabled'}>Compare workspace</button><button id="compare-mode" class="quiet">Compare work_${escapeHtml(state.mode)}</button></div></article><article class="card"><p class="kicker">Capture</p><h3>Save this arrangement as a draft</h3><div class="field"><label for="capture-space">Source Space</label><select id="capture-space" data-ui-only>${spaceOptions}</select></div><div class="row"><div class="field"><label for="capture-id">Stable ID</label><input id="capture-id" data-ui-only value="captured_workspace"></div><div class="field"><label for="capture-name">Name</label><input id="capture-name" data-ui-only value="Captured Workspace"></div></div><button id="capture-space-now" class="quiet">Capture into editor</button><p class="layout-hint">Creates an unsaved draft. It does not move a window or change a Space.</p></article></section><div id="live-comparison"></div><div class="live-display-grid">${displays}</div>`;
    root.querySelector('#refresh-state').onclick = currentView;
    root.querySelectorAll('[data-mode]').forEach((button) => button.onclick = () => { state.mode = button.dataset.mode; currentView(); });
    const showComparison = async (payload) => {
      const output = root.querySelector('#live-comparison'); output.innerHTML = '<p>Comparing…</p>';
      try {
        const result = await request('/api/preview', { method: 'POST', body: JSON.stringify({ config: state.config, ...payload }) });
        state.livePlan = result.plan;
        const drifts = result.comparison.drifts || [];
        output.innerHTML = `<section class="comparison-summary ${result.comparison.converged ? 'converged' : ''}"><div><p class="kicker">${result.comparison.converged ? '✓ converged' : 'Drift detected'}</p><h3>${result.comparison.counts.blocker} blockers · ${result.comparison.counts.change} changes · ${result.comparison.counts.warning} warnings</h3><p>Plan ${escapeHtml(result.plan.planId)} is ${result.plan.executable ? 'executable' : 'blocked'}. No changes were applied.</p></div></section><div class="drift-list">${drifts.map((item) => `<article class="drift ${escapeHtml(item.severity)}"><b>${escapeHtml(item.code.replaceAll('_', ' '))}</b><span>${escapeHtml(item.workspaceId || item.message || 'system')}</span></article>`).join('') || '<div class="empty-lane">Actual state already matches the selected target.</div>'}</div>`;
      } catch (error) { output.innerHTML = `<div class="errors">${escapeHtml(error.message)}</div>`; }
    };
    root.querySelector('#compare-workspace').onclick = () => showComparison({ kind: 'workspace', target: root.querySelector('#current-workspace').value, mode: state.mode });
    root.querySelector('#compare-mode').onclick = () => showComparison({ kind: 'mode', target: state.mode });
    root.querySelector('#capture-space-now').onclick = async () => {
      const workspaceId = root.querySelector('#capture-id').value.trim(); const name = root.querySelector('#capture-name').value.trim();
      if (!validId(workspaceId) || !name) return toast('Choose a name and a unique lowercase stable ID.', true);
      if (state.config.workspaces[workspaceId]) return toast(`Workspace “${workspaceId}” already exists.`, true);
      try {
        const capture = await request('/api/capture', { method: 'POST', body: JSON.stringify({ workspaceId, name, mode: state.mode, spaceUuid: root.querySelector('#capture-space').value }) });
        const merged = mergeCapturedWorkspace(capture);
        state.view = 'workspaces'; render();
        toast(`${name} captured as an unsaved draft${merged.assigned ? ` on ${merged.displayRole}` : '; assign it to a display lane before saving'}.`);
      } catch (error) { toast(error.message, true); }
    };
  } catch (error) { if (viewIsCurrent('current', epoch)) root.innerHTML = title('Current state', 'Discovery failed', 'Nothing was changed.') + `<div class="errors">${escapeHtml(error.message)}</div>`; }
}

async function diagnosticsView(epoch = renderEpoch) {
  root.innerHTML = title('Diagnostics', 'System readiness & activity', 'Checks are read-only and never move windows or change display state.', '<button id="run-self-test" class="primary">Run self-test</button><button id="copy-diagnostics" class="quiet">Copy</button><button id="export-diagnostics" class="quiet">Export</button>') + '<p>Running checks…</p>';
  try { const [diagnostics, activity] = await Promise.all([request('/api/diagnostics'), request('/api/activity')]); if (!viewIsCurrent('diagnostics', epoch)) return; const documentText = JSON.stringify({ diagnostics, activity: activity.entries }, null, 2); root.innerHTML = title('Diagnostics', `Topology: ${diagnostics.topology}`, 'System, backend, schema and workspace checks. Copy or export this report when requesting support.', '<button id="run-self-test" class="primary">Run self-test</button><button id="copy-diagnostics" class="quiet">Copy</button><button id="export-diagnostics" class="quiet">Export</button>') + `<div class="cards">${diagnostics.checks.map((check) => `<article class="card diagnostic ${check.ok === null ? 'unknown' : check.ok ? 'ok' : 'failed'}"><p class="kicker">${check.ok === null ? 'Not verified' : check.ok ? 'Ready' : 'Attention'}</p><h3>${escapeHtml(check.id)}</h3><p>${escapeHtml(check.detail)}</p></article>`).join('')}</div><div class="section-head compact"><div><p class="kicker">Shortcut & CLI transitions</p><h2>Recent guarded runs</h2></div><button class="quiet" id="open-run-history">Open full history</button></div><pre class="review-json">${escapeHtml((diagnostics.recentTransitions || []).map((run) => `${run.startedAt} ${String(run.status).toUpperCase()} ${run.targetLabel || run.targetKey || run.mode} ${run.durationMs ?? '-'}ms warnings=${run.warnings?.length || 0} skipped=${run.skipped?.length || 0}`).join('\n') || 'No guarded transitions recorded yet.')}</pre><div class="section-head compact"><div><p class="kicker">Apply journals</p><h2>Recent reconciliation runs</h2></div></div><pre class="review-json">${escapeHtml((diagnostics.recentRuns || []).map((run) => `${run.createdAt} ${String(run.status).toUpperCase()} ${run.target?.kind || ''}:${run.target?.id || ''} ${run.runId}`).join('\n') || 'No apply runs recorded yet.')}</pre><div class="section-head compact"><div><p class="kicker">Activity log</p><h2>Recent events</h2></div></div><pre class="review-json">${escapeHtml(activity.entries.map((entry) => `${entry.timestamp} ${entry.level.toUpperCase()} ${entry.event}`).join('\n') || 'No activity yet.')}</pre>`;
    root.querySelector('#copy-diagnostics').onclick = async () => { await navigator.clipboard.writeText(documentText); toast('Diagnostics copied'); };
    root.querySelector('#export-diagnostics').onclick = () => { const blob = new Blob([documentText], { type: 'application/json' }); const link = document.createElement('a'); link.href = URL.createObjectURL(blob); link.download = 'spacewright-diagnostics.json'; link.click(); URL.revokeObjectURL(link.href); };
    root.querySelector('#run-self-test').onclick = async () => { try { await request('/api/self-test', { method: 'POST' }); toast('Self-test passed'); render(); } catch (error) { toast(error.message, true); } };
    root.querySelector('#open-run-history').onclick = () => { state.view = 'history'; render(); };
  } catch (error) { if (viewIsCurrent('diagnostics', epoch)) root.innerHTML = `<div class="errors">${escapeHtml(error.message)}</div>`; }
}

async function tasksView(epoch = renderEpoch) {
  root.innerHTML = title('Run control', 'Activate and monitor workspaces', 'Preview first, then explicitly confirm any operation that moves windows or changes Spaces.') + '<p>Loading tasks…</p>';
  try {
    const { tasks } = await request('/api/tasks');
    if (!viewIsCurrent('tasks', epoch)) return;
    const targetOptions = [
      ...['solo', 'wide', 'tall'].map((id) => `<option value="mode:${id}">Mode · ${id}</option>`),
      ...Object.entries(state.config.profiles || {}).map(([id, profile]) => `<option value="profile:${id}">Profile · ${escapeHtml(profile.name)}</option>`),
      ...Object.entries(state.config.workspaces).map(([id, workspace]) => `<option value="workspace:${id}">Workspace · ${escapeHtml(workspace.name)}</option>`)
    ].join('');
    const draftNotice = state.dirty ? '<div class="run-safety warning"><strong>Save or revert your draft before running.</strong><span>Execution is pinned to the saved configuration, so an unsaved draft cannot be run accidentally.</span></div>' : '<div class="run-safety"><strong>Saved configuration</strong><span>Preview creates a short-lived, digest-pinned execution plan.</span></div>';
    root.innerHTML = title('Run control', 'Activate and monitor workspaces', 'Preview the saved target, inspect the exact changes, then explicitly confirm execution.') + draftNotice + `<article class="card run-control"><div class="row"><div class="field"><label for="run-target">Target</label><select id="run-target" data-ui-only>${targetOptions}</select></div><div class="field"><label for="run-mode">Workspace mode</label><select id="run-mode" data-ui-only><option>solo</option><option selected>wide</option><option>tall</option></select></div></div><label class="check"><input id="execution-confirm" data-ui-only type="checkbox"> I understand that Run Now may launch apps, create or focus Spaces, and move or resize windows.</label><div class="actions"><button id="preview-target" class="quiet" ${state.dirty ? 'disabled' : ''}>Preview Saved Plan</button><button id="run-target-now" class="primary" disabled>Run Pinned Plan</button></div><div id="run-preview"></div></article><div class="section-head compact"><div><p class="kicker">Task queue</p><h2>Recent executions</h2></div><button id="refresh-tasks" class="quiet">Refresh</button></div><div class="cards">${tasks.map((task) => `<article class="card task-card" data-task-id="${task.id}"><p class="kicker">${escapeHtml(task.status)}</p><h3>${escapeHtml(task.kind)} · ${escapeHtml(task.target)}</h3><p>${escapeHtml(task.createdAt)}</p><pre>${escapeHtml(task.logs.join('\n') || 'Waiting for output…')}</pre>${['queued','running'].includes(task.status) ? `<button class="danger" data-cancel-task="${task.id}">Cancel</button>` : ''}</article>`).join('') || '<div class="empty-lane">No tasks have run in this server session.</div>'}</div>`;
    const selection = () => { const [kind, target] = root.querySelector('#run-target').value.split(':'); return { kind, target, mode: root.querySelector('#run-mode').value }; };
    const invalidatePreview = () => { state.runPreview = null; root.querySelector('#run-preview').innerHTML = ''; root.querySelector('#execution-confirm').checked = false; root.querySelector('#run-target-now').disabled = true; };
    const syncMode = () => { root.querySelector('#run-mode').disabled = !root.querySelector('#run-target').value.startsWith('workspace:'); invalidatePreview(); };
    syncMode(); root.querySelector('#run-target').onchange = syncMode; root.querySelector('#run-mode').onchange = invalidatePreview;
    root.querySelector('#execution-confirm').onchange = (event) => { root.querySelector('#run-target-now').disabled = !event.target.checked || !state.runPreview; };
    root.querySelector('#preview-target').onclick = async () => { const value = selection(); try { const result = await request('/api/preview', { method: 'POST', body: JSON.stringify({ config: state.savedConfig, ...value }) }); if (!viewIsCurrent('tasks', epoch)) return; state.runPreview = { selection: value, plan: result.plan, snapshotId: result.snapshot.snapshotId }; root.querySelector('#run-preview').innerHTML = planPreview(result); root.querySelector('#execution-confirm').checked = false; root.querySelector('#run-target-now').disabled = true; } catch (error) { toast(error.message, true); } };
    root.querySelector('#run-target-now').onclick = async () => { const value = selection(); const preview = state.runPreview; if (!preview || JSON.stringify(preview.selection) !== JSON.stringify(value)) return toast('Preview this target again before running.', true); try { const result = await request('/api/execute', { method: 'POST', body: JSON.stringify({ ...value, confirmed: true, expectedPlanId: preview.plan.planId, expectedConfigDigest: preview.plan.configDigest, expectedSnapshotId: preview.snapshotId }) }); state.runPreview = null; toast(`Task ${result.task.id} started`); setTimeout(() => render(), 400); } catch (error) { state.runPreview = null; toast(error.message, true); render(); } };
    root.querySelector('#refresh-tasks').onclick = render;
    root.querySelectorAll('[data-cancel-task]').forEach((button) => button.onclick = async () => { try { await request(`/api/tasks/${button.dataset.cancelTask}/cancel`, { method: 'POST' }); toast('Cancellation requested'); render(); } catch (error) { toast(error.message, true); } });
  } catch (error) { if (viewIsCurrent('tasks', epoch)) root.innerHTML = `<div class="errors">${escapeHtml(error.message)}</div>`; }
}

async function reviewView(epoch = renderEpoch) {
  const migrationAction = state.source === 'starter' && state.legacyAvailable ? '<button id="import-legacy" class="quiet">Import current v1 setup</button>' : '';
  root.innerHTML = title('Compile / inspect', 'Before anything moves', 'Validation and compilation are read-only. Inspect the exact normalized runtime plan below.', migrationAction) + '<p>Compiling…</p>';
  if (migrationAction) root.querySelector('#import-legacy').onclick = async () => {
    try {
      const result = await request('/api/legacy-preview');
      state.config = result.config;
      state.source = result.source;
      state.selectedWorkspace = null;
      document.querySelector('#status').textContent = 'Migration preview · unsaved';
      toast('Imported the current v1 setup as an unsaved preview');
      render();
    } catch (error) { toast(error.message, true); }
  };
  try {
    const result = await request('/api/validate', { method: 'POST', body: JSON.stringify(state.config) });
    if (!viewIsCurrent('review', epoch)) return;
    state.runtime = result.runtime;
    const warningItems=(result.warnings||[]).map(humanWarning);
    const warnings = warningItems.length ? `<div class="review-warnings"><strong>Warnings</strong>${warningItems.map((item,index)=>`<article><div><b>${escapeHtml(item.title)}</b><p>${escapeHtml(item.text)}</p></div>${item.workspaceId?`<div class="actions"><button class="quiet" data-edit-warning="${index}">Edit Layout</button><button class="quiet" data-ignore-warning="${index}">Ignore</button></div>`:''}</article>`).join('')}</div>` : '';
    const importSummary = state.importChanges.length ? `<div class="change-summary"><strong>Imported preview changes:</strong> ${state.importChanges.map(escapeHtml).join(', ')}</div>` : '';
    const changes = [];
    for (const workspaceId of new Set([...ids(state.savedConfig?.workspaces), ...ids(state.config.workspaces)])) for (const mode of MODES) { const before = workspacePlacement(state.savedConfig, mode, workspaceId); const after = workspacePlacement(state.config, mode, workspaceId); if (JSON.stringify(before) !== JSON.stringify(after)) { const name = state.config.workspaces[workspaceId]?.name || state.savedConfig.workspaces[workspaceId]?.name || workspaceId; changes.push(`${name} · ${mode}: ${before ? `${state.savedConfig.displayRoles[before.role]?.name || before.role}, Space ${before.index + 1}` : 'disabled'} → ${after ? `${state.config.displayRoles[after.role]?.name || after.role}, Space ${after.index + 1}` : 'disabled'}`); } }
    const beforeShortcuts = new Map((state.savedConfig?.shortcuts || []).map((item) => [item.id, item])); const afterShortcuts = new Map((state.config.shortcuts || []).map((item) => [item.id, item]));
    for (const id of new Set([...beforeShortcuts.keys(), ...afterShortcuts.keys()])) { const before = beforeShortcuts.get(id); const after = afterShortcuts.get(id); if (JSON.stringify(before) !== JSON.stringify(after)) changes.push(`Shortcut: ${before ? `${chordLabel(before.keys)} → ${actionLabel(before, state.savedConfig)}` : 'not configured'} → ${after ? `${chordLabel(after.keys)} → ${actionLabel(after)}` : 'cleared'}`); }
    for(const workspaceId of new Set([...ids(state.savedConfig?.workspaces),...ids(state.config.workspaces)])){const before=state.savedConfig?.workspaces?.[workspaceId],after=state.config.workspaces?.[workspaceId];if(!before||!after)continue;for(const role of new Set([...ids(before.windows),...ids(after.windows)])){const oldApp=before.windows?.[role]?.app,newApp=after.windows?.[role]?.app;if(oldApp!==newApp)changes.push(`${after.name} · ${role}: ${state.savedConfig.apps?.[oldApp]?.name||oldApp||'none'} → ${state.config.apps?.[newApp]?.name||newApp||'none'}; layout and role preserved`);}}
    const missing = []; for (const [workspaceId, workspace] of Object.entries(state.config.workspaces)) for (const mode of MODES) if (!workspace.variants[mode]) missing.push(`${workspace.name} · ${mode}`);
    const conflicts = shortcutConflicts();
    const summary = `<section class="review-summary"><h3>Human-readable changes</h3>${changes.length ? `<ul>${changes.map((item) => `<li>${escapeHtml(item)}</li>`).join('')}</ul>` : '<p>No workspace placement, Space order or shortcut changes.</p>'}${conflicts.length ? `<div class="conflict-banner"><strong>Shortcut conflicts block saving</strong>${conflicts.map(([a,b]) => `<p>${escapeHtml(chordLabel(a.keys))}: ${escapeHtml(actionLabel(a))} / ${escapeHtml(actionLabel(b))}</p>`).join('')}</div>` : '<p class="review-ok">✓ No shortcut conflicts</p>'}<p><strong>Modes not configured:</strong> ${missing.length ? missing.map(escapeHtml).join(', ') : 'None'}</p></section>`;
    root.innerHTML = title('Compile / inspect', warningItems.length ? 'Ready to save with warnings' : 'Ready to save', 'Review display placement, Space order, app replacements and actual shortcut changes before saving.', migrationAction) + importSummary + warnings + summary + `<details class="advanced-json"><summary>Advanced details · normalized runtime JSON</summary><pre class="review-json">${escapeHtml(JSON.stringify(result.runtime, null, 2))}</pre></details>`;
    root.querySelectorAll('[data-edit-warning]').forEach((button)=>button.onclick=()=>{const item=warningItems[Number(button.dataset.editWarning)];state.selectedWorkspace=item.workspaceId;state.mode=item.mode;state.workspaceTab='layout';state.view='workspaces';render();});
    root.querySelectorAll('[data-ignore-warning]').forEach((button)=>button.onclick=()=>button.closest('article').remove());
    if (migrationAction) root.querySelector('#import-legacy').onclick = async () => {
      try {
        const migrated = await request('/api/legacy-preview');
        state.config = migrated.config;
        state.source = migrated.source;
        state.selectedWorkspace = null;
        document.querySelector('#status').textContent = 'Migration preview · unsaved';
        toast('Imported the current v1 setup as an unsaved preview');
        render();
      } catch (error) { toast(error.message, true); }
    };
  } catch (error) {
    if (viewIsCurrent('review', epoch)) root.innerHTML = title('Compile / inspect', 'Needs attention', 'No runtime plan will be produced until every reference is valid.') + `<div class="errors">${escapeHtml(error.message).replaceAll('\n','<br>')}</div>`;
  }
}

function render() {
  const epoch = ++renderEpoch;
  closeRecording();
  document.querySelectorAll('#nav button').forEach((button) => { const active = button.dataset.view === state.view; button.classList.toggle('active', active); if (active) button.setAttribute('aria-current', 'page'); else button.removeAttribute('aria-current'); });
  if (state.view === 'current') currentView(epoch);
  else if (state.view === 'map') mapView();
  else if (state.view === 'displays') displaysView();
  else if (state.view === 'workspaces') workspacesView();
  else if (state.view === 'ai') aiView();
  else if (state.view === 'apps') appsView();
  else if (state.view === 'shortcuts') shortcutsView();
  else if (state.view === 'automation') automationView();
  else if (state.view === 'history') historyView(epoch);
  else if (state.view === 'diagnostics') diagnosticsView(epoch);
  else if (state.view === 'tasks') tasksView(epoch);
  else reviewView(epoch);
  syncUrl();
  syncPersistenceControls();
}

document.querySelectorAll('#nav button').forEach((button) => button.onclick = () => { state.view = button.dataset.view; render(); });
root.addEventListener('input', (event) => { if (!event.target.matches('[data-ui-only]')) markDirty(); });
root.addEventListener('change', (event) => { if (!event.target.matches('[data-ui-only]')) markDirty(); });
document.querySelector('#validate').onclick = () => { state.view = 'review'; render(); };
document.querySelector('#undo').onclick = () => moveDraftHistory('undo');
document.querySelector('#redo').onclick = () => moveDraftHistory('redo');
addEventListener('keydown', (event) => {
  if (!(event.metaKey || event.ctrlKey) || event.key.toLowerCase() !== 'z' || event.target.matches('input, textarea, select, [contenteditable="true"]')) return;
  event.preventDefault();
  moveDraftHistory(event.shiftKey ? 'redo' : 'undo');
});
document.querySelector('#save').onclick = async (event) => { const button = event.currentTarget; if (!state.dirty) return; if (shortcutConflicts().length) { state.view = 'shortcuts'; render(); return toast('Resolve shortcut conflicts before saving.', true); } button.disabled = true; button.textContent = 'Checking Diff…'; try { const payload = { config: state.config, baseRevision: state.serverRevision }; const diff = await request('/api/diff', { method: 'POST', body: JSON.stringify(payload) }); if (!diff.count && !state.requiresInitialSave) { markClean(); return toast('No changes to save'); } const changeCount = diff.count || 1; if (!await confirmAction(`Save ${changeCount} configuration change(s)? A recovery snapshot will be created first.`, { title: 'Save Configuration', confirmLabel: 'Save Changes' })) return; button.textContent = 'Saving…'; const result = await request('/api/save', { method: 'POST', body: JSON.stringify(payload) }); state.source = 'v2'; state.requiresInitialSave = false; state.savedConfig = structuredClone(state.config); state.serverRevision = result.revision; state.importChanges = []; state.autoImportedShortcuts = 0; markClean('Local · read/write · verified'); toast(`Saved and read-back verified: ${result.path}`); } catch (error) { if (error.payload?.code === 'configuration_conflict') toast('The configuration changed outside this page. Reload to review it before saving.', true); else toast(error.message, true); } finally { button.textContent = 'Save Configuration'; syncPersistenceControls(); } };
document.querySelector('#export-config').onclick = () => { const link = document.createElement('a'); link.href = '/api/export'; link.download = 'spacewright.yaml'; link.click(); };
document.querySelector('#import-config').onclick = () => document.querySelector('#import-file').click();
document.querySelector('#import-file').onchange = async (event) => { try { const result = await request('/api/import', { method: 'POST', body: JSON.stringify({ text: await event.target.files[0].text() }) }); const imported = result.config; state.importChanges = changedSections(state.savedConfig, imported); state.config = imported; state.source = 'import-preview'; state.selectedWorkspace = null; markDirty(); state.view = 'review'; render(); toast(`Imported validated preview with ${state.importChanges.length} changed section(s).`); } catch (error) { toast(error.message, true); } finally { event.target.value = ''; } };
document.querySelector('#revert-changes').onclick = async () => { if (!state.dirty || await confirmAction('Discard all unsaved changes?', { confirmLabel: 'Discard Draft', danger: true })) { state.config = structuredClone(state.savedConfig); state.autoImportedShortcuts = 0; state.selectedWorkspace = null; markClean(); render(); } };
document.querySelector('#reset-defaults').onclick = async () => { if (!await confirmAction('Replace the editor contents with SpaceWright defaults? This remains unsaved until you save it.', { confirmLabel: 'Load Defaults', danger: true })) return; const result = await request('/api/defaults'); state.config = result.config; state.selectedWorkspace = null; markDirty(); render(); };
document.querySelector('#restore-backup').onclick = async () => { if (!await confirmAction('Restore the previous valid configuration and replace the current file?', { confirmLabel: 'Restore Backup', danger: true })) return; try { const result = await request('/api/restore-backup', { method: 'POST' }); state.config = result.config; state.savedConfig = structuredClone(result.config); state.serverRevision = result.revision; state.source = 'v2'; state.requiresInitialSave = false; state.selectedWorkspace = null; markClean('Local · restored'); render(); toast('Restored the previous valid configuration'); } catch (error) { toast(error.message, true); } };
addEventListener('beforeunload', (event) => { if (!state.dirty) return; event.preventDefault(); event.returnValue = ''; });

async function initialize() {
  if (location.protocol === 'file:') {
    state.config = previewConfig();
    state.savedConfig = structuredClone(state.config);
    state.lastDraft = structuredClone(state.config);
    document.body.classList.add('preview-mode');
    document.querySelector('#status').textContent = 'Preview · read only';
    document.querySelector('#path').textContent = 'Run “spacewright configure” to edit your configuration';
    document.querySelector('#save').disabled = true;
    document.querySelector('#validate').disabled = true;
    state.view = 'map'; render();
  } else {
    try {
      const [payload, machinePayload, shortcutPayload] = await Promise.all([request('/api/config'), request('/api/machine'), request('/api/shortcuts')]);
      state.config = payload.config;
      state.savedConfig = structuredClone(payload.config);
      state.lastDraft = structuredClone(payload.config);
      state.serverRevision = payload.revision;
      if (!['current', 'map', 'displays', 'workspaces', 'apps', 'shortcuts', 'automation', 'history', 'diagnostics', 'tasks', 'review'].includes(state.view)) state.view = 'current';
      if (!['solo', 'wide', 'tall'].includes(state.mode)) state.mode = 'wide';
      state.source = payload.source;
      state.requiresInitialSave = payload.source === 'starter';
      state.legacyAvailable = payload.legacyAvailable;
      state.machine = machinePayload.machine;
      state.externalShortcuts = shortcutPayload.bindings || [];
      state.shortcutSources = shortcutPayload.inspected || [];
      autoImportExternalShortcuts();
      if (state.autoImportedShortcuts) markDirty();
      else if (payload.source === 'v2') markClean();
      else markDirty();
      document.querySelector('#status').textContent = state.autoImportedShortcuts ? `Local · ${state.autoImportedShortcuts} shortcut${state.autoImportedShortcuts===1?'':'s'} ready to save` : payload.source === 'v2' ? 'Local · read/write' : 'Starter · unsaved';
      document.querySelector('#path').textContent = payload.path;
      render();
      if (payload.source === 'starter') toast('No v2 file yet. Review can import your current v1 setup before saving.');
    } catch (error) {
      document.querySelector('#status').textContent = 'Could not load';
      root.innerHTML = `<div class="errors">${escapeHtml(error.message)}</div>`;
    }
  }
}

initialize();
