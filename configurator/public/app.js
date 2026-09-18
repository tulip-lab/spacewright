const token = new URLSearchParams(location.search).get('token');
const headers = { 'content-type': 'application/json', 'x-spacewright-token': token || '' };
const state = { config: null, savedConfig: null, source: null, legacyAvailable: false, machine: { version: 1, displayBindings: {} }, view: new URLSearchParams(location.search).get('view') || 'map', mode: new URLSearchParams(location.search).get('mode') || 'wide', selectedWorkspace: null, runtime: null, dirty: false, importChanges: [] };
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

function markDirty() {
  state.dirty = true;
  document.querySelector('#status').textContent = 'Unsaved changes';
}

function validId(value) { return /^[a-z][a-z0-9_]*$/.test(value); }
function renameKey(object, from, to) { object[to] = object[from]; delete object[from]; }
function visitLayout(node, callback) { if (!node) return; callback(node); for (const child of node.children || []) visitLayout(child, callback); for (const region of node.regions || []) callback(region); }

function requestId(label, current, collection) {
  const next = prompt(label, current)?.trim();
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
  return ['metadata', 'apps', 'displayRoles', 'workspaces', 'modes', 'shortcuts'].filter((key) => JSON.stringify(before?.[key]) !== JSON.stringify(after?.[key]));
}

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

function onboarding() {
  const steps = [
    ['Applications', Object.keys(state.config.apps).length > 0],
    ['Display roles', Object.keys(state.config.displayRoles).length > 0],
    ['Workspaces', Object.keys(state.config.workspaces).length > 0],
    ['3 mode maps', ['solo', 'wide', 'tall'].every((mode) => state.config.modes[mode]?.displays?.length)],
    ['Shortcuts', (state.config.shortcuts || []).length > 0]
  ];
  const complete = steps.filter(([, done]) => done).length;
  return `<aside class="onboarding" aria-label="Configuration progress"><div><p class="kicker">Setup progress</p><strong>${complete} / ${steps.length} ready</strong></div>${steps.map(([label, done]) => `<span class="${done ? 'done' : ''}">${done ? '✓' : '○'} ${label}</span>`).join('')}</aside>`;
}

function mapView() {
  const mode = state.config.modes[state.mode] || { displays: [] };
  root.innerHTML = title('Topology / sequence', `${state.mode} mode`, 'Drag workspaces within or between display roles. Their vertical order is the Space order and execution order.', modeSwitch()) + onboarding() +
    `<div class="display-deck">${mode.displays.map((display, displayIndex) => `
      <article class="display-card"><div class="display-screen" data-display="${displayIndex}">
        <div class="display-title"><span>${escapeHtml(state.config.displayRoles[display.role]?.name || display.role)}</span><span>${escapeHtml(display.role)}</span></div>
        <div class="lane">${display.workspaceOrder.length ? display.workspaceOrder.map((workspaceId, index) => {
          const workspace = state.config.workspaces[workspaceId];
          return `<div class="workspace-chip" draggable="true" data-workspace="${workspaceId}" data-from="${displayIndex}"><span class="order">${String(index + 1).padStart(2, '0')}</span><span><strong>${escapeHtml(workspace?.name || workspaceId)}</strong><small>${escapeHtml(workspaceId)}</small></span><span class="chip-actions"><button class="quiet" data-move-up="${workspaceId}" data-lane="${displayIndex}" aria-label="Move ${escapeHtml(workspace?.name || workspaceId)} up">↑</button><button class="quiet" data-move-down="${workspaceId}" data-lane="${displayIndex}" aria-label="Move ${escapeHtml(workspace?.name || workspaceId)} down">↓</button></span></div>`;
        }).join('') : '<div class="empty-lane">Drop a workspace here</div>'}</div>
      </div></article>`).join('')}<article class="card"><h3>Add Display Lane</h3><div class="field"><label for="lane-role">Display role</label><select id="lane-role" name="lane-role">${ids(state.config.displayRoles).map((role) => `<option value="${role}">${escapeHtml(state.config.displayRoles[role].name)}</option>`).join('')}</select></div><button id="add-lane" class="primary">+ Add to ${state.mode}</button></article></div>`;
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
      markDirty();
      render();
    };
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
    `<div class="cards">${Object.entries(state.config.displayRoles).map(([id, role]) => `<article class="card"><p class="kicker" translate="no">${escapeHtml(id)}</p><h3>${escapeHtml(role.name)}</h3>${state.machine.displayBindings[id] ? `<p><span class="badge">Bound</span> <span class="machine-id">${escapeHtml(state.machine.displayBindings[id])}</span></p>` : '<p class="unbound">Not bound on this Mac</p>'}<div class="field"><label for="display-name-${id}">Display name</label><input id="display-name-${id}" name="display-name-${id}" autocomplete="off" data-display-name="${id}" value="${escapeHtml(role.name)}"></div><div class="field"><label for="display-orientation-${id}">Portable match</label><select id="display-orientation-${id}" name="display-orientation-${id}" data-orientation="${id}"><option value="">Any orientation</option><option value="wide" ${role.portableMatch?.orientation === 'wide' ? 'selected' : ''}>Wide</option><option value="tall" ${role.portableMatch?.orientation === 'tall' ? 'selected' : ''}>Tall</option></select></div><label><input type="checkbox" data-built-in="${id}" ${role.portableMatch?.builtIn ? 'checked' : ''}> Built-in display</label><div class="actions"><button class="quiet" data-rename-display="${id}">Rename ID</button><button class="danger" data-delete-display="${id}">Delete Role</button></div></article>`).join('')}<article class="card"><h3>Add display role</h3><button id="add-display-role" class="primary">+ New role</button></article></div><div id="discovery"></div>`;
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
    const oldId = button.dataset.renameDisplay; const newId = requestId('New display role ID', oldId, state.config.displayRoles); if (!newId) return;
    renameKey(state.config.displayRoles, oldId, newId);
    for (const mode of Object.values(state.config.modes)) for (const display of mode.displays) if (display.role === oldId) display.role = newId;
    if (state.machine.displayBindings[oldId]) { state.machine.displayBindings[newId] = state.machine.displayBindings[oldId]; delete state.machine.displayBindings[oldId]; await request('/api/display-bindings', { method: 'POST', body: JSON.stringify({ displayBindings: state.machine.displayBindings, config: state.config }) }); }
    markDirty(); render();
  });
  root.querySelectorAll('[data-delete-display]').forEach((button) => button.onclick = async () => {
    const id = button.dataset.deleteDisplay; const references = Object.entries(state.config.modes).filter(([, mode]) => mode.displays.some((display) => display.role === id)).map(([mode]) => mode);
    if (references.length) return toast(`Display role “${id}” is used by modes: ${references.join(', ')}. Move those lanes first.`, true);
    if (!confirm(`Delete display role “${id}”?`)) return;
    delete state.config.displayRoles[id];
    if (state.machine.displayBindings[id]) { delete state.machine.displayBindings[id]; await request('/api/display-bindings', { method: 'POST', body: JSON.stringify({ displayBindings: state.machine.displayBindings, config: state.config }) }); }
    markDirty(); render();
  });
  root.querySelector('#discover').onclick = async () => {
    const target = root.querySelector('#discovery'); target.innerHTML = '<p>Reading yabai display inventory…</p>';
    try {
      const result = await request('/api/displays');
      target.innerHTML = result.displays.length ? `<div class="cards" style="margin-top:22px">${result.displays.map((display) => `<article class="card"><p class="kicker">Connected display</p><h3>Display ${display.index}</h3><p class="machine-id">${escapeHtml(display.uuid || 'No UUID')}</p><span class="badge">${display.frame?.w || '?'} × ${display.frame?.h || '?'}</span><div class="field"><label>Bind to role</label><select aria-label="Bind display ${escapeHtml(display.index)} to role" name="binding-${escapeHtml(display.index)}" data-binding-role="${escapeHtml(display.uuid || '')}">${ids(state.config.displayRoles).map((role) => `<option value="${role}" ${state.machine.displayBindings[role] === display.uuid ? 'selected' : ''}>${escapeHtml(state.config.displayRoles[role].name)}</option>`).join('')}</select></div><button class="primary" data-bind-display="${escapeHtml(display.uuid || '')}" data-display-index="${escapeHtml(display.index)}" ${display.uuid ? '' : 'disabled'}>Bind on this Mac</button></article>`).join('')}</div>` : `<div class="errors">${escapeHtml(result.message || 'No displays returned by yabai')}</div>`;
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
    <div class="row"><div class="field"><label for="workspace-name">Workspace name</label><input id="workspace-name" name="workspace-name" autocomplete="off" data-bind="name" value="${escapeHtml(workspace.name)}"></div><div class="field"><label for="workspace-id">Stable ID</label><input id="workspace-id" value="${escapeHtml(id)}" disabled></div></div>
    <div class="field"><label for="workspace-label">Space label prefix</label><input id="workspace-label" name="workspace-label" autocomplete="off" data-bind="spaceLabel" value="${escapeHtml(workspace.spaceLabel)}"></div>
    <div class="actions"><button id="rename-workspace" class="quiet">Rename ID</button><button id="delete-workspace" class="danger">Delete Workspace</button></div>
    <div class="actions"><button class="template-button" data-template="full">Full</button><button class="template-button" data-template="half-columns">½ + ½</button><button class="template-button" data-template="third-columns">⅓ + ⅔</button><button class="template-button" data-template="half-rows">Top + bottom</button><button class="template-button" data-template="right-stack">Right stacked</button><button class="template-button" data-template="left-stack">Left stacked</button></div>
    <div class="layout-preview">${variant ? layoutNode(variant.layout) : '<div class="layout-region">No variant</div>'}</div>
    <div class="window-list">${Object.entries(workspace.windows).map(([role, window]) => `<div class="window-row"><strong translate="no">${escapeHtml(role)}</strong><select aria-label="Application for ${escapeHtml(role)}" name="window-app-${role}" data-window-app="${role}">${ids(state.config.apps).map((appId) => `<option value="${appId}" ${appId === window.app ? 'selected' : ''}>${escapeHtml(state.config.apps[appId].name)}</option>`).join('')}</select><label><input type="checkbox" data-required="${role}" ${window.required ? 'checked' : ''}> required</label><label><input type="checkbox" data-selector="movable:${role}" ${window.selector?.movable ? 'checked' : ''}> movable</label><label><input type="checkbox" data-selector="visible:${role}" ${window.selector?.visible ? 'checked' : ''}> visible</label><label><input type="checkbox" data-selector="non_empty_title:${role}" ${window.selector?.non_empty_title ? 'checked' : ''}> titled</label><input aria-label="Title includes for ${escapeHtml(role)}" name="title-include-${role}" autocomplete="off" placeholder="Title includes…" data-selector-text="title_include:${role}" value="${escapeHtml(window.selector?.title_include || '')}"><input aria-label="Title excludes for ${escapeHtml(role)}" name="title-exclude-${role}" autocomplete="off" placeholder="Title excludes…" data-selector-text="title_exclude:${role}" value="${escapeHtml(window.selector?.title_exclude || '')}"><span class="actions"><button class="quiet" data-rename-window="${role}">Rename Role</button><button class="danger" data-delete-window="${role}">Delete Role</button></span></div>`).join('')}</div><button id="add-window-role" class="quiet" style="margin-top:12px">+ Window role</button>
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
  root.querySelectorAll('[data-selector]').forEach((input) => input.onchange = () => { const [field, role] = input.dataset.selector.split(':'); const selector = state.config.workspaces[state.selectedWorkspace].windows[role].selector ||= {}; if (input.checked) selector[field] = true; else delete selector[field]; });
  root.querySelectorAll('[data-selector-text]').forEach((input) => input.oninput = () => { const [field, role] = input.dataset.selectorText.split(':'); const selector = state.config.workspaces[state.selectedWorkspace].windows[role].selector ||= {}; if (input.value) selector[field] = input.value; else delete selector[field]; });
  root.querySelector('#rename-workspace').onclick = () => {
    const oldId = state.selectedWorkspace; const newId = requestId('New workspace ID', oldId, state.config.workspaces); if (!newId) return;
    renameKey(state.config.workspaces, oldId, newId);
    for (const mode of Object.values(state.config.modes)) for (const display of mode.displays) display.workspaceOrder = display.workspaceOrder.map((id) => id === oldId ? newId : id);
    for (const shortcut of state.config.shortcuts || []) if (shortcut.action.workspace === oldId) shortcut.action.workspace = newId;
    state.selectedWorkspace = newId; markDirty(); render();
  };
  root.querySelector('#delete-workspace').onclick = () => {
    const id = state.selectedWorkspace;
    if (Object.keys(state.config.workspaces).length === 1) return toast('A configuration must keep at least 1 workspace.', true);
    if (!confirm(`Delete workspace “${id}” and remove it from every mode and shortcut?`)) return;
    delete state.config.workspaces[id];
    for (const mode of Object.values(state.config.modes)) for (const display of mode.displays) display.workspaceOrder = display.workspaceOrder.filter((workspaceId) => workspaceId !== id);
    state.config.shortcuts = (state.config.shortcuts || []).filter((shortcut) => shortcut.action.workspace !== id);
    state.selectedWorkspace = null; markDirty(); render();
  };
  root.querySelectorAll('[data-rename-window]').forEach((button) => button.onclick = () => {
    const workspace = state.config.workspaces[state.selectedWorkspace]; const oldRole = button.dataset.renameWindow; const newRole = requestId('New window role ID', oldRole, workspace.windows); if (!newRole) return;
    renameKey(workspace.windows, oldRole, newRole);
    for (const variant of Object.values(workspace.variants)) {
      visitLayout(variant.layout, (node) => { if (node.role === oldRole) node.role = newRole; });
      for (const runtimeWindow of variant.runtime?.windows || []) if (runtimeWindow.role === oldRole) runtimeWindow.role = newRole;
      for (const action of variant.runtime?.primaryAloneLayout || []) if (action.role === oldRole) action.role = newRole;
    }
    markDirty(); render();
  });
  root.querySelectorAll('[data-delete-window]').forEach((button) => button.onclick = () => {
    const workspace = state.config.workspaces[state.selectedWorkspace]; const role = button.dataset.deleteWindow; let used = false;
    for (const variant of Object.values(workspace.variants)) visitLayout(variant.layout, (node) => { if (node.role === role) used = true; });
    if (used) return toast(`Window role “${role}” is still placed in a layout. Replace its layout first.`, true);
    if (Object.keys(workspace.windows).length === 1) return toast('A workspace must keep at least 1 window role.', true);
    if (!confirm(`Delete window role “${role}”?`)) return;
    delete workspace.windows[role]; markDirty(); render();
  });
  root.querySelectorAll('[data-template]').forEach((button) => button.onclick = () => {
    if ((button.dataset.template === 'right-stack' || button.dataset.template === 'left-stack') && ids(state.config.workspaces[state.selectedWorkspace].windows).length < 3) return toast('A stacked region needs at least three window roles', true);
    state.config.workspaces[state.selectedWorkspace].variants[state.mode] = { layout: layoutTemplate(button.dataset.template, ids(state.config.workspaces[state.selectedWorkspace].windows)) };
    markDirty(); render();
  });
  root.querySelector('#add-window-role').onclick = () => {
    const windows = state.config.workspaces[state.selectedWorkspace].windows;
    let index = 1; while (windows[`window_${index}`]) index++;
    windows[`window_${index}`] = { app: ids(state.config.apps)[0], required: false, selector: { movable: true } };
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

function appsView() {
  root.innerHTML = title('Application registry', 'Name the actors', 'App aliases match the names reported by macOS. One key may recognize several installed names.', '<button id="discover-apps" class="quiet">Discover Open Apps</button>') + `<div class="cards">${Object.entries(state.config.apps).map(([id, app]) => `<article class="card"><p class="kicker" translate="no">${escapeHtml(id)}</p><h3>${escapeHtml(app.name)}</h3><div class="field"><label for="app-name-${id}">Display name</label><input id="app-name-${id}" name="app-name-${id}" autocomplete="off" data-app-name="${id}" value="${escapeHtml(app.name)}"></div><div class="field"><label for="app-aliases-${id}">macOS names, comma separated</label><input id="app-aliases-${id}" name="app-aliases-${id}" autocomplete="off" data-app-aliases="${id}" value="${escapeHtml(app.match.appNames.join(', '))}"></div><div class="actions"><button class="quiet" data-rename-app="${id}">Rename ID</button><button class="danger" data-delete-app="${id}">Delete App</button></div></article>`).join('')}<article class="card"><h3>Add Application</h3><button id="add-app" class="primary">+ Add App</button></article><div id="app-discovery"></div></div>`;
  root.querySelectorAll('[data-app-name]').forEach((input) => input.oninput = () => state.config.apps[input.dataset.appName].name = input.value);
  root.querySelectorAll('[data-app-aliases]').forEach((input) => input.oninput = () => state.config.apps[input.dataset.appAliases].match.appNames = input.value.split(',').map((v) => v.trim()).filter(Boolean));
  root.querySelector('#add-app').onclick = () => { let i = 1; while (state.config.apps[`app_${i}`]) i++; state.config.apps[`app_${i}`] = { name: `Application ${i}`, match: { appNames: [`Application ${i}`] } }; markDirty(); render(); };
  root.querySelectorAll('[data-rename-app]').forEach((button) => button.onclick = () => {
    const oldId = button.dataset.renameApp; const newId = requestId('New application ID', oldId, state.config.apps); if (!newId) return;
    renameKey(state.config.apps, oldId, newId);
    for (const workspace of Object.values(state.config.workspaces)) for (const window of Object.values(workspace.windows)) if (window.app === oldId) window.app = newId;
    for (const workspace of Object.values(state.config.workspaces)) for (const variant of Object.values(workspace.variants)) for (const runtimeWindow of variant.runtime?.windows || []) if (runtimeWindow.app_key === oldId) runtimeWindow.app_key = newId;
    markDirty(); render();
  });
  root.querySelectorAll('[data-delete-app]').forEach((button) => button.onclick = () => {
    const id = button.dataset.deleteApp; const references = [];
    for (const [workspaceId, workspace] of Object.entries(state.config.workspaces)) for (const [role, window] of Object.entries(workspace.windows)) if (window.app === id) references.push(`${workspaceId}.${role}`);
    if (references.length) return toast(`Application “${id}” is used by: ${references.join(', ')}. Reassign those roles first.`, true);
    if (Object.keys(state.config.apps).length === 1) return toast('A configuration must keep at least 1 application.', true);
    if (!confirm(`Delete application “${id}”?`)) return;
    delete state.config.apps[id]; markDirty(); render();
  });
  root.querySelector('#discover-apps').onclick = async () => { try { const result = await request('/api/apps'); root.querySelector('#app-discovery').innerHTML = result.apps.length ? `<article class="card"><h3>Open applications</h3><p>${result.apps.map(escapeHtml).join(' · ')}</p></article>` : `<div class="errors">${escapeHtml(result.message || 'No applications reported by yabai')}</div>`; } catch (error) { toast(error.message, true); } };
}

function shortcutsView() {
  root.innerHTML = title('Keyboard layer', 'Shortcuts with guardrails', 'Only SpaceWright actions are generated. Your existing skhdrc is never parsed or overwritten.', '<button id="generate-skhd" class="primary">Generate Fragment</button>') + `<div class="cards">${(state.config.shortcuts || []).map((shortcut, index) => `<article class="card"><p class="kicker">Binding ${String(index + 1).padStart(2,'0')}</p><h3>${escapeHtml([...shortcut.keys.modifiers, shortcut.keys.key].join(' + '))}</h3><p><span class="badge">${escapeHtml(shortcut.action.type)}</span> ${escapeHtml(shortcut.action.workspace || shortcut.action.mode || '')}</p><button class="danger" data-remove-shortcut="${index}">Remove Shortcut</button></article>`).join('')}<article class="card"><h3>Add Mode Shortcut</h3><div class="row"><div class="field"><label for="shortcut-key">Key</label><input id="shortcut-key" name="shortcut-key" autocomplete="off" maxlength="1" value="w"></div><div class="field"><label for="shortcut-mode">Mode</label><select id="shortcut-mode" name="shortcut-mode"><option>solo</option><option>wide</option><option>tall</option></select></div></div><button id="add-shortcut" class="primary">Add Alt + Shift Binding</button></article><article class="card"><h3>Add Workspace Shortcut</h3><div class="field"><label for="shortcut-workspace">Workspace</label><select id="shortcut-workspace" name="shortcut-workspace">${ids(state.config.workspaces).map((id) => `<option value="${id}">${escapeHtml(state.config.workspaces[id].name)}</option>`).join('')}</select></div><div class="row"><div class="field"><label for="workspace-shortcut-key">Key</label><input id="workspace-shortcut-key" name="workspace-shortcut-key" autocomplete="off" maxlength="1" value="1"></div><div class="field"><label for="workspace-shortcut-mode">Mode</label><select id="workspace-shortcut-mode" name="workspace-shortcut-mode"><option>solo</option><option>wide</option><option>tall</option></select></div></div><button id="add-workspace-shortcut" class="primary">Add Workspace Binding</button></article></div>`;
  root.querySelectorAll('[data-remove-shortcut]').forEach((button) => button.onclick = () => { if (!confirm('Remove this shortcut?')) return; state.config.shortcuts.splice(Number(button.dataset.removeShortcut), 1); markDirty(); render(); });
  root.querySelector('#add-shortcut').onclick = () => { state.config.shortcuts.push({ id: crypto.randomUUID(), keys: { modifiers: ['alt','shift'], key: root.querySelector('#shortcut-key').value }, action: { type: 'activateMode', mode: root.querySelector('#shortcut-mode').value } }); markDirty(); render(); };
  root.querySelector('#add-workspace-shortcut').onclick = () => { state.config.shortcuts.push({ id: crypto.randomUUID(), keys: { modifiers: ['alt'], key: root.querySelector('#workspace-shortcut-key').value }, action: { type: 'activateWorkspace', workspace: root.querySelector('#shortcut-workspace').value, mode: root.querySelector('#workspace-shortcut-mode').value } }); markDirty(); render(); };
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
    const warnings = result.warnings?.length ? `<div class="errors"><strong>Warnings</strong><br>${result.warnings.map(escapeHtml).join('<br>')}</div>` : '';
    const importSummary = state.importChanges.length ? `<div class="change-summary"><strong>Imported preview changes:</strong> ${state.importChanges.map(escapeHtml).join(', ')}</div>` : '';
    root.innerHTML = title('Compile / inspect', 'Ready to save', 'The portable v2 document compiles into this deterministic runtime plan.', migrationAction) + importSummary + warnings + `<pre class="review-json">${escapeHtml(JSON.stringify(result.runtime, null, 2))}</pre>`;
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
  syncUrl();
}

document.querySelectorAll('#nav button').forEach((button) => button.onclick = () => { state.view = button.dataset.view; render(); });
root.addEventListener('input', markDirty);
root.addEventListener('change', markDirty);
document.querySelector('#validate').onclick = async () => { try { const result = await request('/api/validate', { method: 'POST', body: JSON.stringify(state.config) }); toast(result.warnings?.length ? `Valid with ${result.warnings.length} warning(s)` : 'Configuration is valid'); } catch (error) { toast(error.message, true); } };
document.querySelector('#save').onclick = async (event) => { const button = event.currentTarget; button.disabled = true; button.textContent = 'Saving…'; try { const result = await request('/api/save', { method: 'POST', body: JSON.stringify(state.config) }); state.source = 'v2'; state.savedConfig = structuredClone(state.config); state.importChanges = []; state.dirty = false; document.querySelector('#status').textContent = 'Local · read/write'; toast(`Saved ${result.path}; compiled ${result.runtimePath}`); } catch (error) { toast(error.message, true); } finally { button.disabled = false; button.textContent = 'Save Configuration'; } };
document.querySelector('#export-config').onclick = () => { const blob = new Blob([`${JSON.stringify(state.config, null, 2)}\n`], { type: 'application/json' }); const link = document.createElement('a'); link.href = URL.createObjectURL(blob); link.download = 'spacewright-config.v2.json'; link.click(); URL.revokeObjectURL(link.href); };
document.querySelector('#import-config').onclick = () => document.querySelector('#import-file').click();
document.querySelector('#import-file').onchange = async (event) => { try { const imported = JSON.parse(await event.target.files[0].text()); await request('/api/validate', { method: 'POST', body: JSON.stringify(imported) }); state.importChanges = changedSections(state.savedConfig, imported); state.config = imported; state.source = 'import-preview'; state.selectedWorkspace = null; markDirty(); state.view = 'review'; render(); toast(`Imported preview changes ${state.importChanges.length} section(s); review before saving.`); } catch (error) { toast(error.message, true); } finally { event.target.value = ''; } };
document.querySelector('#restore-backup').onclick = async () => { if (!confirm('Restore the previous valid configuration and replace the current file?')) return; try { const result = await request('/api/restore-backup', { method: 'POST' }); state.config = result.config; state.savedConfig = structuredClone(result.config); state.source = 'v2'; state.dirty = false; state.selectedWorkspace = null; render(); toast('Restored the previous valid configuration'); } catch (error) { toast(error.message, true); } };
addEventListener('beforeunload', (event) => { if (!state.dirty) return; event.preventDefault(); event.returnValue = ''; });

async function initialize() {
  if (location.protocol === 'file:') {
    state.config = previewConfig();
    state.savedConfig = structuredClone(state.config);
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
      state.savedConfig = structuredClone(payload.config);
      if (!['map', 'displays', 'workspaces', 'apps', 'shortcuts', 'review'].includes(state.view)) state.view = 'map';
      if (!['solo', 'wide', 'tall'].includes(state.mode)) state.mode = 'wide';
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
