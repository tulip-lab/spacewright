const token = new URLSearchParams(location.search).get('token');
const headers = { 'content-type': 'application/json', 'x-spacewright-token': token || '' };
const state = { config: null, source: null, legacyAvailable: false, machine: { version: 1, displayBindings: {} }, view: 'map', mode: 'wide', selectedWorkspace: null, runtime: null };
const root = document.querySelector('#workspace');

function previewConfig() {
  return {
    version: 2,
    metadata: { name: 'SpaceWright preview' },
    apps: {
      code: { name: 'Visual Studio Code', match: { appNames: ['Code', 'Visual Studio Code'] } },
      chatgpt: { name: 'ChatGPT', match: { appNames: ['ChatGPT'] } },
      terminal: { name: 'Terminal', match: { appNames: ['Warp', 'Terminal'] } }
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

function toast(message, error = false) {
  const node = document.querySelector('#toast-template').content.firstElementChild.cloneNode(true);
  node.textContent = message;
  if (error) node.style.background = '#9f2d1c';
  document.body.append(node);
  setTimeout(() => node.remove(), 4200);
}

async function request(path, options = {}) {
  const response = await fetch(path, { ...options, headers: { ...headers, ...(options.headers || {}) } });
  const payload = await response.json();
  if (!response.ok) throw Object.assign(new Error(payload.error || payload.errors?.join('\n') || 'Request failed'), { payload });
  return payload;
}

function modeSwitch() {
  return `<div class="mode-switch">${['solo', 'wide', 'tall'].map((mode) => `<button data-mode="${mode}" class="${state.mode === mode ? 'active' : ''}">${mode}</button>`).join('')}</div>`;
}

function mapView() {
  const mode = state.config.modes[state.mode] || { displays: [] };
  root.innerHTML = title('Topology / sequence', `${state.mode} mode`, 'Drag workspaces within or between display roles. Their vertical order is the Space order and execution order.', modeSwitch()) +
    `<div class="display-deck">${mode.displays.map((display, displayIndex) => `
      <article class="display-card"><div class="display-screen" data-display="${displayIndex}">
        <div class="display-title"><span>${escapeHtml(state.config.displayRoles[display.role]?.name || display.role)}</span><span>${escapeHtml(display.role)}</span></div>
        <div class="lane">${display.workspaceOrder.length ? display.workspaceOrder.map((workspaceId, index) => {
          const workspace = state.config.workspaces[workspaceId];
          return `<div class="workspace-chip" draggable="true" data-workspace="${workspaceId}" data-from="${displayIndex}"><span class="order">${String(index + 1).padStart(2, '0')}</span><span><strong>${escapeHtml(workspace?.name || workspaceId)}</strong><small>${escapeHtml(workspaceId)}</small></span><span>↕</span></div>`;
        }).join('') : '<div class="empty-lane">Drop a workspace here</div>'}</div>
      </div></article>`).join('')}<article class="card"><h3>Add display lane</h3><div class="field"><label>Display role</label><select id="lane-role">${ids(state.config.displayRoles).map((role) => `<option value="${role}">${escapeHtml(state.config.displayRoles[role].name)}</option>`).join('')}</select></div><button id="add-lane" class="primary">+ Add to ${state.mode}</button></article></div>`;
  root.querySelectorAll('[data-mode]').forEach((button) => button.onclick = () => { state.mode = button.dataset.mode; render(); });
  let dragged;
  root.querySelectorAll('.workspace-chip').forEach((chip) => chip.ondragstart = () => { dragged = { id: chip.dataset.workspace, from: Number(chip.dataset.from) }; });
  root.querySelectorAll('[data-display]').forEach((display) => {
    display.ondragover = (event) => event.preventDefault();
    display.ondrop = () => {
      if (!dragged) return;
      const target = Number(display.dataset.display);
      mode.displays[dragged.from].workspaceOrder = mode.displays[dragged.from].workspaceOrder.filter((id) => id !== dragged.id);
      mode.displays[target].workspaceOrder.push(dragged.id);
      render();
    };
  });
  root.querySelector('#add-lane').onclick = () => {
    const role = root.querySelector('#lane-role').value;
    if (mode.displays.some((display) => display.role === role)) return toast(`${role} already has a lane`, true);
    mode.displays.push({ role, workspaceOrder: [] });
    render();
  };
}

async function displaysView() {
  root.innerHTML = title('Display roles', 'Name the surfaces', 'Roles are portable. Connected UUIDs remain machine-local and are never written into the portable configuration.', '<button id="discover" class="quiet">Discover connected displays</button>') +
    `<div class="cards">${Object.entries(state.config.displayRoles).map(([id, role]) => `<article class="card"><p class="kicker">${escapeHtml(id)}</p><h3>${escapeHtml(role.name)}</h3>${state.machine.displayBindings[id] ? `<p><span class="badge">Bound</span> <span class="machine-id">${escapeHtml(state.machine.displayBindings[id])}</span></p>` : '<p class="unbound">Not bound on this Mac</p>'}<div class="field"><label>Display name</label><input data-display-name="${id}" value="${escapeHtml(role.name)}"></div><div class="field"><label>Portable match</label><select data-orientation="${id}"><option value="">Any orientation</option><option value="wide" ${role.portableMatch?.orientation === 'wide' ? 'selected' : ''}>Wide</option><option value="tall" ${role.portableMatch?.orientation === 'tall' ? 'selected' : ''}>Tall</option></select></div><label><input type="checkbox" data-built-in="${id}" ${role.portableMatch?.builtIn ? 'checked' : ''}> Built-in display</label></article>`).join('')}<article class="card"><h3>Add display role</h3><button id="add-display-role" class="primary">+ New role</button></article></div><div id="discovery"></div>`;
  root.querySelectorAll('[data-display-name]').forEach((input) => input.oninput = () => state.config.displayRoles[input.dataset.displayName].name = input.value);
  root.querySelectorAll('[data-orientation]').forEach((select) => select.onchange = () => {
    const match = state.config.displayRoles[select.dataset.orientation].portableMatch ||= {};
    if (select.value) match.orientation = select.value; else delete match.orientation;
  });
  root.querySelectorAll('[data-built-in]').forEach((input) => input.onchange = () => {
    const match = state.config.displayRoles[input.dataset.builtIn].portableMatch ||= {};
    if (input.checked) match.builtIn = true; else delete match.builtIn;
  });
  root.querySelector('#add-display-role').onclick = () => { let index = 1; while (state.config.displayRoles[`display_${index}`]) index++; state.config.displayRoles[`display_${index}`] = { name: `Display ${index}`, portableMatch: {} }; render(); };
  root.querySelector('#discover').onclick = async () => {
    const target = root.querySelector('#discovery'); target.innerHTML = '<p>Reading yabai display inventory…</p>';
    try {
      const result = await request('/api/displays');
      target.innerHTML = result.displays.length ? `<div class="cards" style="margin-top:22px">${result.displays.map((display) => `<article class="card"><p class="kicker">Connected display</p><h3>Display ${display.index}</h3><p class="machine-id">${escapeHtml(display.uuid || 'No UUID')}</p><span class="badge">${display.frame?.w || '?'} × ${display.frame?.h || '?'}</span><div class="field"><label>Bind to role</label><select data-binding-role="${escapeHtml(display.uuid || '')}">${ids(state.config.displayRoles).map((role) => `<option value="${role}" ${state.machine.displayBindings[role] === display.uuid ? 'selected' : ''}>${escapeHtml(state.config.displayRoles[role].name)}</option>`).join('')}</select></div><button class="primary" data-bind-display="${escapeHtml(display.uuid || '')}" data-display-index="${escapeHtml(display.index)}" ${display.uuid ? '' : 'disabled'}>Bind on this Mac</button></article>`).join('')}</div>` : `<div class="errors">${escapeHtml(result.message || 'No displays returned by yabai')}</div>`;
      target.querySelectorAll('[data-bind-display]').forEach((button) => button.onclick = async () => {
        const uuid = button.dataset.bindDisplay;
        const role = target.querySelector(`[data-binding-role="${CSS.escape(uuid)}"]`).value;
        for (const [boundRole, boundUuid] of Object.entries(state.machine.displayBindings)) if (boundUuid === uuid) delete state.machine.displayBindings[boundRole];
        state.machine.displayBindings[role] = uuid;
        try {
          const saved = await request('/api/display-bindings', { method: 'POST', body: JSON.stringify({ displayBindings: state.machine.displayBindings }) });
          state.machine = saved.machine;
          toast(`Bound display ${button.dataset.displayIndex} to ${role}`);
          render();
        } catch (error) { toast(error.message, true); }
      });
    } catch (error) { target.innerHTML = `<div class="errors">${escapeHtml(error.message)}</div>`; }
  };
}

function layoutTemplate(kind, roles) {
  const [a, b, c] = roles;
  if (kind === 'full' || !b) return { type: 'window', role: a };
  if (kind === 'half-columns') return { type: 'split', direction: 'columns', weights: [1, 1], children: [{ type: 'window', role: a }, { type: 'window', role: b }] };
  if (kind === 'third-columns') return { type: 'split', direction: 'columns', weights: [1, 2], children: [{ type: 'window', role: b }, { type: 'window', role: a }] };
  if (kind === 'right-stack' && c) return { type: 'split', direction: 'columns', weights: [1, 2], children: [{ type: 'window', role: a }, { type: 'split', direction: 'rows', weights: [1, 1], children: [{ type: 'window', role: b }, { type: 'window', role: c }] }] };
  if (kind === 'left-stack' && c) return { type: 'split', direction: 'columns', weights: [1, 2], children: [{ type: 'split', direction: 'rows', weights: [1, 1], children: [{ type: 'window', role: b }, { type: 'window', role: c }] }, { type: 'window', role: a }] };
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

function workspaceEditor(id) {
  const workspace = state.config.workspaces[id];
  const roles = ids(workspace.windows);
  const variant = workspace.variants[state.mode];
  return `<article class="card" style="grid-column:1/-1">
    <div class="row"><div class="field"><label>Workspace name</label><input data-bind="name" value="${escapeHtml(workspace.name)}"></div><div class="field"><label>Stable id</label><input value="${escapeHtml(id)}" disabled></div></div>
    <div class="field"><label>Space label prefix</label><input data-bind="spaceLabel" value="${escapeHtml(workspace.spaceLabel)}"></div>
    <div class="actions"><button class="template-button" data-template="full">Full</button><button class="template-button" data-template="half-columns">½ + ½</button><button class="template-button" data-template="third-columns">⅓ + ⅔</button><button class="template-button" data-template="half-rows">Top + bottom</button><button class="template-button" data-template="right-stack">Right stacked</button><button class="template-button" data-template="left-stack">Left stacked</button></div>
    <div class="layout-preview">${variant ? layoutNode(variant.layout) : '<div class="layout-region">No variant</div>'}</div>
    <div class="window-list">${Object.entries(workspace.windows).map(([role, window]) => `<div class="window-row"><strong>${escapeHtml(role)}</strong><select data-window-app="${role}">${ids(state.config.apps).map((appId) => `<option value="${appId}" ${appId === window.app ? 'selected' : ''}>${escapeHtml(state.config.apps[appId].name)}</option>`).join('')}</select><label><input type="checkbox" data-required="${role}" ${window.required ? 'checked' : ''}> required</label></div>`).join('')}</div><button id="add-window-role" class="quiet" style="margin-top:12px">+ Window role</button>
  </article>`;
}

function workspacesView() {
  if (!state.selectedWorkspace || !state.config.workspaces[state.selectedWorkspace]) state.selectedWorkspace = ids(state.config.workspaces)[0];
  root.innerHTML = title('Workspace catalogue', 'Rooms for your work', 'A workspace has one identity, a set of window roles, and a layout variant for each display mode.', modeSwitch()) +
    `<div class="cards"><aside class="card"><h3>Workspaces</h3>${ids(state.config.workspaces).map((id) => `<button class="quiet" style="width:100%;margin:4px 0" data-select="${id}">${escapeHtml(state.config.workspaces[id].name)}</button>`).join('')}<button class="primary" id="add-workspace" style="margin-top:16px">+ New workspace</button></aside>${workspaceEditor(state.selectedWorkspace)}</div>`;
  root.querySelectorAll('[data-mode]').forEach((button) => button.onclick = () => { state.mode = button.dataset.mode; render(); });
  root.querySelectorAll('[data-select]').forEach((button) => button.onclick = () => { state.selectedWorkspace = button.dataset.select; render(); });
  root.querySelector('[data-bind="name"]').oninput = (event) => state.config.workspaces[state.selectedWorkspace].name = event.target.value;
  root.querySelector('[data-bind="spaceLabel"]').oninput = (event) => state.config.workspaces[state.selectedWorkspace].spaceLabel = event.target.value;
  root.querySelectorAll('[data-window-app]').forEach((select) => select.onchange = () => state.config.workspaces[state.selectedWorkspace].windows[select.dataset.windowApp].app = select.value);
  root.querySelectorAll('[data-required]').forEach((input) => input.onchange = () => state.config.workspaces[state.selectedWorkspace].windows[input.dataset.required].required = input.checked);
  root.querySelectorAll('[data-template]').forEach((button) => button.onclick = () => {
    if ((button.dataset.template === 'right-stack' || button.dataset.template === 'left-stack') && ids(state.config.workspaces[state.selectedWorkspace].windows).length < 3) return toast('A stacked region needs at least three window roles', true);
    state.config.workspaces[state.selectedWorkspace].variants[state.mode] = { layout: layoutTemplate(button.dataset.template, ids(state.config.workspaces[state.selectedWorkspace].windows)) };
    render();
  });
  root.querySelector('#add-window-role').onclick = () => {
    const windows = state.config.workspaces[state.selectedWorkspace].windows;
    let index = 1; while (windows[`window_${index}`]) index++;
    windows[`window_${index}`] = { app: ids(state.config.apps)[0], required: false, selector: { movable: true } };
    render();
  };
  root.querySelector('#add-workspace').onclick = () => {
    const base = 'workspace'; let index = 1; while (state.config.workspaces[`${base}_${index}`]) index++;
    const id = `${base}_${index}`;
    const app = ids(state.config.apps)[0];
    state.config.workspaces[id] = { name: `Workspace ${index}`, spaceLabel: id, windows: { primary: { app, required: true, selector: { movable: true } } }, variants: Object.fromEntries(['solo','wide','tall'].map((mode) => [mode, { layout: { type: 'window', role: 'primary' } }])) };
    state.config.modes[state.mode].displays[0].workspaceOrder.push(id); state.selectedWorkspace = id; render();
  };
}

function appsView() {
  root.innerHTML = title('Application registry', 'Name the actors', 'App aliases match the names reported by macOS. One key may recognize several installed names.') + `<div class="cards">${Object.entries(state.config.apps).map(([id, app]) => `<article class="card"><p class="kicker">${escapeHtml(id)}</p><h3>${escapeHtml(app.name)}</h3><div class="field"><label>Display name</label><input data-app-name="${id}" value="${escapeHtml(app.name)}"></div><div class="field"><label>macOS names, comma separated</label><input data-app-aliases="${id}" value="${escapeHtml(app.match.appNames.join(', '))}"></div></article>`).join('')}<article class="card"><h3>Add application</h3><button id="add-app" class="primary">+ Add app</button></article></div>`;
  root.querySelectorAll('[data-app-name]').forEach((input) => input.oninput = () => state.config.apps[input.dataset.appName].name = input.value);
  root.querySelectorAll('[data-app-aliases]').forEach((input) => input.oninput = () => state.config.apps[input.dataset.appAliases].match.appNames = input.value.split(',').map((v) => v.trim()).filter(Boolean));
  root.querySelector('#add-app').onclick = () => { let i = 1; while (state.config.apps[`app_${i}`]) i++; state.config.apps[`app_${i}`] = { name: `Application ${i}`, match: { appNames: [`Application ${i}`] } }; render(); };
}

function shortcutsView() {
  root.innerHTML = title('Keyboard layer', 'Shortcuts with guardrails', 'Only SpaceWright actions are generated. Your existing skhdrc is never parsed or overwritten.', '<button id="generate-skhd" class="primary">Generate fragment</button>') + `<div class="cards">${(state.config.shortcuts || []).map((shortcut, index) => `<article class="card"><p class="kicker">Binding ${String(index + 1).padStart(2,'0')}</p><h3>${escapeHtml([...shortcut.keys.modifiers, shortcut.keys.key].join(' + '))}</h3><p><span class="badge">${escapeHtml(shortcut.action.type)}</span> ${escapeHtml(shortcut.action.workspace || shortcut.action.mode || '')}</p><button class="danger" data-remove-shortcut="${index}">Remove</button></article>`).join('')}<article class="card"><h3>Add mode shortcut</h3><div class="row"><div class="field"><label>Key</label><input id="shortcut-key" maxlength="1" value="w"></div><div class="field"><label>Mode</label><select id="shortcut-mode"><option>solo</option><option>wide</option><option>tall</option></select></div></div><button id="add-shortcut" class="primary">Add Alt + Shift binding</button></article><article class="card"><h3>Add workspace shortcut</h3><div class="field"><label>Workspace</label><select id="shortcut-workspace">${ids(state.config.workspaces).map((id) => `<option value="${id}">${escapeHtml(state.config.workspaces[id].name)}</option>`).join('')}</select></div><div class="row"><div class="field"><label>Key</label><input id="workspace-shortcut-key" maxlength="1" value="1"></div><div class="field"><label>Mode</label><select id="workspace-shortcut-mode"><option>solo</option><option>wide</option><option>tall</option></select></div></div><button id="add-workspace-shortcut" class="primary">Add workspace binding</button></article></div>`;
  root.querySelectorAll('[data-remove-shortcut]').forEach((button) => button.onclick = () => { state.config.shortcuts.splice(Number(button.dataset.removeShortcut), 1); render(); });
  root.querySelector('#add-shortcut').onclick = () => { state.config.shortcuts.push({ id: crypto.randomUUID(), keys: { modifiers: ['alt','shift'], key: root.querySelector('#shortcut-key').value }, action: { type: 'activateMode', mode: root.querySelector('#shortcut-mode').value } }); render(); };
  root.querySelector('#add-workspace-shortcut').onclick = () => { state.config.shortcuts.push({ id: crypto.randomUUID(), keys: { modifiers: ['alt'], key: root.querySelector('#workspace-shortcut-key').value }, action: { type: 'activateWorkspace', workspace: root.querySelector('#shortcut-workspace').value, mode: root.querySelector('#workspace-shortcut-mode').value } }); render(); };
  root.querySelector('#generate-skhd').onclick = async () => { try { const result = await request('/api/skhd', { method: 'POST', body: JSON.stringify(state.config) }); toast(`Generated ${result.path}`); } catch (error) { toast(error.message, true); } };
}

async function reviewView() {
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
    state.runtime = result.runtime;
    root.innerHTML = title('Compile / inspect', 'Ready to save', 'The portable v2 document compiles into this deterministic runtime plan.', migrationAction) + `<pre class="review-json">${escapeHtml(JSON.stringify(result.runtime, null, 2))}</pre>`;
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
    root.innerHTML = title('Compile / inspect', 'Needs attention', 'No runtime plan will be produced until every reference is valid.') + `<div class="errors">${escapeHtml(error.message).replaceAll('\n','<br>')}</div>`;
  }
}

function render() {
  document.querySelectorAll('#nav button').forEach((button) => button.classList.toggle('active', button.dataset.view === state.view));
  if (state.view === 'map') mapView();
  else if (state.view === 'displays') displaysView();
  else if (state.view === 'workspaces') workspacesView();
  else if (state.view === 'apps') appsView();
  else if (state.view === 'shortcuts') shortcutsView();
  else reviewView();
}

document.querySelectorAll('#nav button').forEach((button) => button.onclick = () => { state.view = button.dataset.view; render(); });
document.querySelector('#validate').onclick = async () => { try { await request('/api/validate', { method: 'POST', body: JSON.stringify(state.config) }); toast('Configuration is valid'); } catch (error) { toast(error.message, true); } };
document.querySelector('#save').onclick = async () => { try { const result = await request('/api/save', { method: 'POST', body: JSON.stringify(state.config) }); state.source = 'v2'; document.querySelector('#status').textContent = 'Local · read/write'; toast(`Saved ${result.path}`); } catch (error) { toast(error.message, true); } };

async function initialize() {
  if (location.protocol === 'file:') {
    state.config = previewConfig();
    document.body.classList.add('preview-mode');
    document.querySelector('#status').textContent = 'Preview · read only';
    document.querySelector('#path').textContent = 'Run “spacewright configure” to edit your configuration';
    document.querySelector('#save').disabled = true;
    document.querySelector('#validate').disabled = true;
    render();
  } else {
    try {
      const [payload, machinePayload] = await Promise.all([request('/api/config'), request('/api/machine')]);
      state.config = payload.config;
      state.source = payload.source;
      state.legacyAvailable = payload.legacyAvailable;
      state.machine = machinePayload.machine;
      document.querySelector('#status').textContent = payload.source === 'v2' ? 'Local · read/write' : 'Starter · unsaved';
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
