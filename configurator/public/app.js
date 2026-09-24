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
  return ['metadata', 'apps', 'displayRoles', 'workspaces', 'modes', 'shortcuts', 'profiles', 'rules', 'settings'].filter((key) => JSON.stringify(before?.[key]) !== JSON.stringify(after?.[key]));
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
  const assigned = new Set(mode.displays.flatMap((display) => display.workspaceOrder));
  const unassigned = ids(state.config.workspaces).filter((id) => !assigned.has(id));
  const destinationOptions = (current) => `<option value="unassigned" ${current === 'unassigned' ? 'selected' : ''}>Unassigned</option>${mode.displays.map((display, index) => `<option value="${index}" ${String(current) === String(index) ? 'selected' : ''}>${escapeHtml(state.config.displayRoles[display.role]?.name || display.role)}</option>`).join('')}`;
  const chip = (workspaceId, from, index) => {
    const workspace = state.config.workspaces[workspaceId];
    const assignedLane = from !== 'unassigned';
    return `<div class="drop-slot" data-drop-lane="${from}" data-drop-index="${index}"></div><div class="workspace-chip" draggable="true" data-workspace="${workspaceId}" data-from="${from}"><span class="order">${assignedLane ? String(index + 1).padStart(2, '0') : '—'}</span><span><strong>${escapeHtml(workspace?.name || workspaceId)}</strong><small>${escapeHtml(workspaceId)}</small></span><span class="chip-controls"><select data-relocate="${workspaceId}" data-current-lane="${from}" aria-label="Display for ${escapeHtml(workspace?.name || workspaceId)}">${destinationOptions(from)}</select>${assignedLane ? `<span class="chip-actions"><button class="quiet" data-move-up="${workspaceId}" data-lane="${from}" aria-label="Move ${escapeHtml(workspace?.name || workspaceId)} up">↑</button><button class="quiet" data-move-down="${workspaceId}" data-lane="${from}" aria-label="Move ${escapeHtml(workspace?.name || workspaceId)} down">↓</button></span>` : ''}</span></div>`;
  };
  const lane = (items, laneId) => `${items.map((workspaceId, index) => chip(workspaceId, laneId, index)).join('')}<div class="drop-slot end" data-drop-lane="${laneId}" data-drop-index="${items.length}">${items.length ? 'Drop at end' : 'Drop a workspace here'}</div>`;
  root.innerHTML = title('Topology / sequence', `${state.mode} mode`, 'Drag workspaces within or between display roles. Their vertical order is the Space order and execution order.', modeSwitch()) + onboarding() +
    `<div class="display-deck">${mode.displays.map((display, displayIndex) => `
      <article class="display-card"><div class="display-screen" data-display="${displayIndex}">
        <div class="display-title"><span>${escapeHtml(state.config.displayRoles[display.role]?.name || display.role)}</span><span>${escapeHtml(display.role)}</span></div>
        <div class="lane">${lane(display.workspaceOrder, displayIndex)}</div>
      </div></article>`).join('')}<article class="card unassigned-card"><div class="display-title"><span>Unassigned</span><span>${unassigned.length}</span></div><p>Keep a workspace here when it should not open in this mode.</p><div class="lane">${lane(unassigned, 'unassigned')}</div></article><article class="card"><h3>Add Display Lane</h3><div class="field"><label for="lane-role">Display role</label><select id="lane-role" name="lane-role">${ids(state.config.displayRoles).map((role) => `<option value="${role}">${escapeHtml(state.config.displayRoles[role].name)}</option>`).join('')}</select></div><button id="add-lane" class="primary">+ Add to ${state.mode}</button></article></div>`;
  root.querySelectorAll('[data-mode]').forEach((button) => button.onclick = () => { state.mode = button.dataset.mode; render(); });
  let dragged;
  const placeWorkspace = (id, target, index) => {
    const sourceLane = mode.displays.findIndex((display) => display.workspaceOrder.includes(id));
    const sourceIndex = sourceLane < 0 ? -1 : mode.displays[sourceLane].workspaceOrder.indexOf(id);
    let insertionIndex = Number(index);
    if (target !== 'unassigned' && sourceLane === Number(target) && sourceIndex < insertionIndex) insertionIndex--;
    for (const display of mode.displays) display.workspaceOrder = display.workspaceOrder.filter((workspaceId) => workspaceId !== id);
    if (target !== 'unassigned') mode.displays[Number(target)].workspaceOrder.splice(insertionIndex, 0, id);
    markDirty(); render();
  };
  root.querySelectorAll('.workspace-chip').forEach((node) => node.ondragstart = () => { dragged = { id: node.dataset.workspace }; });
  root.querySelectorAll('[data-drop-lane]').forEach((slot) => {
    slot.ondragover = (event) => { event.preventDefault(); slot.classList.add('active'); };
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
  const [a, b, c, d] = roles;
  if (kind === 'full' || !b) return { type: 'window', role: a };
  if (kind === 'half-columns') return { type: 'split', direction: 'columns', weights: [1, 1], children: [{ type: 'window', role: a }, { type: 'window', role: b }] };
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

function workspaceEditor(id) {
  const workspace = state.config.workspaces[id];
  const roles = ids(workspace.windows);
  const variant = workspace.variants[state.mode];
  const canvas = variant?.layout?.type === 'canvas';
  return `<article class="card workspace-editor" style="grid-column:1/-1">
    <div class="row"><div class="field"><label for="workspace-name">Workspace name</label><input id="workspace-name" name="workspace-name" autocomplete="off" data-bind="name" value="${escapeHtml(workspace.name)}"></div><div class="field"><label for="workspace-id">Stable ID</label><input id="workspace-id" value="${escapeHtml(id)}" disabled></div></div>
    <div class="field"><label for="workspace-label">Space label prefix</label><input id="workspace-label" name="workspace-label" autocomplete="off" data-bind="spaceLabel" value="${escapeHtml(workspace.spaceLabel)}"></div>
    <div class="actions"><button id="rename-workspace" class="quiet">Rename ID</button><button id="delete-workspace" class="danger">Delete Workspace</button></div>
    <section class="layout-workbench"><div class="layout-stage"><div class="layout-heading"><div><p class="kicker">${escapeHtml(state.mode)} layout</p><h3>Arrange windows</h3></div><button id="edit-canvas" class="${canvas ? 'quiet' : 'primary'}">${canvas ? 'Reset equal columns' : 'Edit freely'}</button></div>${canvasPreview(variant?.layout, workspace)}<p class="layout-hint">${canvas ? 'Drag a window to move it. Drag its lower-right corner to resize. The grid snaps to 12 columns and 12 rows.' : 'Choose Edit freely to drag and resize every window, or start from a preset below.'}</p><div class="layout-preset-groups"><div><span>Two windows</span><div class="actions layout-presets"><button class="template-button" data-template="full">Full</button><button class="template-button" data-template="half-columns">Left | Right</button><button class="template-button" data-template="half-rows">Top / Bottom</button><button class="template-button" data-template="third-columns">⅓ | ⅔</button><button class="template-button" data-template="two-third-columns">⅔ | ⅓</button></div></div><div><span>Three windows</span><div class="actions layout-presets"><button class="template-button" data-template="three-columns">3 columns</button><button class="template-button" data-template="three-rows">3 rows</button><button class="template-button" data-template="left-stack">Left split ↕</button><button class="template-button" data-template="right-stack">Right split ↕</button><button class="template-button" data-template="top-split">Top split ↔</button><button class="template-button" data-template="bottom-split">Bottom split ↔</button></div></div><div><span>Four windows</span><div class="actions layout-presets"><button class="template-button" data-template="quad">2 × 2 grid</button><button class="template-button" data-template="main-left">Main left + 3</button><button class="template-button" data-template="main-top">Main top + 3</button></div></div></div></div>
    <aside class="window-inspector"><div class="layout-heading"><div><p class="kicker">Windows</p><h3>Apps in this workspace</h3></div><button id="add-window-role" class="primary">+ Add app window</button></div>${Object.entries(workspace.windows).map(([role, window]) => { const region = canvas ? variant.layout.regions.find((item) => item.role === role) : null; const grid = region ? gridValues(region) : null; return `<details class="window-card" ${region ? 'open' : ''}><summary><span><strong>${escapeHtml(state.config.apps[window.app]?.name || window.app)}</strong><small>${escapeHtml(role)}</small></span><span>${grid ? `${grid.w}×${grid.h}` : 'Preset'}</span></summary><div class="window-fields"><div class="field"><label for="window-app-${role}">Application</label><select id="window-app-${role}" data-window-app="${role}">${ids(state.config.apps).map((appId) => `<option value="${appId}" ${appId === window.app ? 'selected' : ''}>${escapeHtml(state.config.apps[appId].name)}</option>`).join('')}</select></div>${grid ? `<div class="geometry-grid"><label>Left <input type="number" min="0" max="11" data-geometry="x:${role}" value="${grid.x}"></label><label>Top <input type="number" min="0" max="11" data-geometry="y:${role}" value="${grid.y}"></label><label>Width <input type="number" min="1" max="12" data-geometry="w:${role}" value="${grid.w}"></label><label>Height <input type="number" min="1" max="12" data-geometry="h:${role}" value="${grid.h}"></label></div>` : ''}<label class="check"><input type="checkbox" data-required="${role}" ${window.required ? 'checked' : ''}> This window is required</label><details class="advanced"><summary>Window matching options</summary><div class="selector-grid"><label><input type="checkbox" data-selector="movable:${role}" ${window.selector?.movable ? 'checked' : ''}> movable</label><label><input type="checkbox" data-selector="visible:${role}" ${window.selector?.visible ? 'checked' : ''}> visible</label><label><input type="checkbox" data-selector="non_empty_title:${role}" ${window.selector?.non_empty_title ? 'checked' : ''}> titled</label><input aria-label="Title includes for ${escapeHtml(role)}" placeholder="Title includes…" data-selector-text="title_include:${role}" value="${escapeHtml(window.selector?.title_include || '')}"><input aria-label="Title excludes for ${escapeHtml(role)}" placeholder="Title excludes…" data-selector-text="title_exclude:${role}" value="${escapeHtml(window.selector?.title_exclude || '')}"></div></details><div class="actions"><button class="quiet" data-rename-window="${role}">Rename role</button><button class="danger" data-delete-window="${role}">Remove window</button></div></div></details>`; }).join('')}<button class="quiet manage-apps" data-go-apps>Manage application list →</button></aside></section>
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
  root.querySelector('[data-go-apps]').onclick = () => { state.view = 'apps'; render(); };
  root.querySelector('#edit-canvas').onclick = () => {
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
    const workspace = state.config.workspaces[state.selectedWorkspace]; const role = button.dataset.deleteWindow;
    if (Object.keys(workspace.windows).length === 1) return toast('A workspace must keep at least 1 window role.', true);
    if (!confirm(`Remove window “${role}” from this workspace and all of its layouts?`)) return;
    delete workspace.windows[role];
    for (const variant of Object.values(workspace.variants)) {
      if (variant.layout.type === 'canvas') variant.layout.regions = variant.layout.regions.filter((region) => region.role !== role);
      else if (layoutRoles(variant.layout).has(role)) variant.layout = canvasFromLayout(variant.layout, ids(workspace.windows));
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
  root.querySelector('#add-window-role').onclick = () => {
    const windows = state.config.workspaces[state.selectedWorkspace].windows;
    let index = 1; while (windows[`window_${index}`]) index++;
    windows[`window_${index}`] = { app: ids(state.config.apps)[0], required: false, selector: { movable: true } };
    const variant = state.config.workspaces[state.selectedWorkspace].variants[state.mode];
    variant.layout = canvasFromLayout(variant.layout, ids(windows));
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

function automationView() {
  state.config.profiles ||= {};
  state.config.rules ||= [];
  state.config.settings ||= {};
  const profiles = Object.entries(state.config.profiles).map(([id, profile]) => `<article class="card"><p class="kicker">${escapeHtml(id)}</p><h3>${escapeHtml(profile.name)}</h3><p><span class="badge">${escapeHtml(profile.mode)}</span> ${(profile.workspaces || []).map(escapeHtml).join(' · ') || 'all workspaces'}</p><div class="actions"><button class="quiet" data-preview-profile="${id}">Dry run</button><button class="danger" data-delete-profile="${id}">Delete</button></div></article>`).join('');
  const rules = state.config.rules.map((rule, index) => `<article class="card"><p class="kicker">${escapeHtml(rule.id)}</p><h3>${escapeHtml(rule.when.event)}</h3><p>${escapeHtml(rule.when.topology || rule.when.orientation || 'any topology')} → ${escapeHtml(rule.then.activateProfile || rule.then.activateWorkspace)}</p><label class="check"><input type="checkbox" data-rule-enabled="${index}" ${rule.enabled ? 'checked' : ''}> Enabled</label><button class="danger" data-delete-rule="${index}">Delete</button></article>`).join('');
  root.innerHTML = title('Automation', 'Profiles, workspace restore & event rules', 'Profiles bundle mode, display, workspace, geometry and focus settings. Every activation can be previewed without moving windows.', '<button id="evaluate-rules" class="quiet">Evaluate current topology</button><button id="preview-mode" class="quiet">Preview current mode</button>') + `<label class="check automation-toggle"><input id="automation-enabled" type="checkbox" ${state.config.settings.eventAutomationEnabled ? 'checked' : ''}> Automatically run matching enabled rules while this configurator service is running. Save configuration to apply.</label><div id="dry-run-output"></div><div class="cards">${profiles}<article class="card"><h3>Add profile</h3><div class="field"><label for="profile-id">ID</label><input id="profile-id" value="research"></div><div class="field"><label for="profile-name">Name</label><input id="profile-name" value="Research"></div><div class="field"><label for="profile-mode">Mode</label><select id="profile-mode"><option>solo</option><option>wide</option><option>tall</option></select></div><button id="add-profile" class="primary">Add Profile</button></article></div><div class="section-head compact"><div><p class="kicker">Rule engine</p><h2>Event-driven activation</h2></div></div><div class="cards">${rules}<article class="card"><h3>Add topology rule</h3><div class="field"><label for="rule-event">Event</label><select id="rule-event"><option>display_connected</option><option>display_disconnected</option><option>topology_changed</option><option>wake</option><option>manual</option></select></div><div class="field"><label for="rule-topology">Topology</label><select id="rule-topology"><option value="">Any</option>${['solo','wide_left','wide_right','tall_left','tall_right','dual_external','clamshell'].map((item) => `<option>${item}</option>`).join('')}</select></div><div class="field"><label for="rule-profile">Activate profile</label><select id="rule-profile">${Object.entries(state.config.profiles).map(([id, profile]) => `<option value="${id}">${escapeHtml(profile.name)}</option>`).join('')}</select></div><button id="add-rule" class="primary" ${Object.keys(state.config.profiles).length ? '' : 'disabled'}>Add Rule</button></article></div>`;
  const showPlan = async (profile) => { try { const result = await request('/api/preview', { method: 'POST', body: JSON.stringify({ config: state.config, profile, mode: state.mode }) }); root.querySelector('#dry-run-output').innerHTML = `<div class="change-summary"><strong>Dry run · no desktop changes</strong><pre>${escapeHtml(JSON.stringify(result, null, 2))}</pre></div>`; } catch (error) { toast(error.message, true); } };
  root.querySelector('#preview-mode').onclick = () => showPlan(null);
  root.querySelector('#automation-enabled').onchange = (event) => { state.config.settings.eventAutomationEnabled = event.target.checked; markDirty(); };
  root.querySelector('#evaluate-rules').onclick = async () => { try { const result = await request('/api/rules/evaluate', { method: 'POST', body: JSON.stringify({ event: 'manual', execute: false }) }); root.querySelector('#dry-run-output').innerHTML = `<div class="change-summary"><strong>Rule evaluation · no desktop changes</strong><pre>${escapeHtml(JSON.stringify(result, null, 2))}</pre></div>`; } catch (error) { toast(error.message, true); } };
  root.querySelectorAll('[data-preview-profile]').forEach((button) => button.onclick = () => showPlan(button.dataset.previewProfile));
  root.querySelector('#add-profile').onclick = () => { const id = root.querySelector('#profile-id').value.trim(); if (!validId(id) || state.config.profiles[id]) return toast('Choose a unique lowercase profile ID.', true); state.config.profiles[id] = { name: root.querySelector('#profile-name').value.trim(), mode: root.querySelector('#profile-mode').value, workspaces: [] }; markDirty(); render(); };
  root.querySelectorAll('[data-delete-profile]').forEach((button) => button.onclick = () => { const id = button.dataset.deleteProfile; if (state.config.rules.some((rule) => rule.then.activateProfile === id)) return toast('Delete rules that use this profile first.', true); delete state.config.profiles[id]; markDirty(); render(); });
  root.querySelectorAll('[data-rule-enabled]').forEach((input) => input.onchange = () => { state.config.rules[Number(input.dataset.ruleEnabled)].enabled = input.checked; markDirty(); });
  root.querySelectorAll('[data-delete-rule]').forEach((button) => button.onclick = () => { state.config.rules.splice(Number(button.dataset.deleteRule), 1); markDirty(); render(); });
  root.querySelector('#add-rule').onclick = () => { const topology = root.querySelector('#rule-topology').value; const when = { event: root.querySelector('#rule-event').value, ...(topology ? { topology } : {}) }; let number = 1; while (state.config.rules.some((rule) => rule.id === `rule_${number}`)) number++; state.config.rules.push({ id: `rule_${number}`, enabled: true, when, then: { activateProfile: root.querySelector('#rule-profile').value } }); markDirty(); render(); };
}

async function historyView() {
  root.innerHTML = title('Configuration history', 'Snapshots & restore points', 'Each successful Apply creates an immutable snapshot after verified read-back.') + '<p>Loading history…</p>';
  try { const { snapshots } = await request('/api/history'); root.innerHTML = title('Configuration history', 'Snapshots & restore points', 'Compare, rename, restore or delete saved configurations.') + `<div class="cards">${snapshots.map((snapshot) => `<article class="card"><p class="kicker">${escapeHtml(snapshot.reason)}</p><h3>${escapeHtml(snapshot.name)}</h3><p>${escapeHtml(snapshot.createdAt)}</p><div class="actions"><button class="quiet" data-compare-snapshot="${snapshot.id}">Compare</button><button class="quiet" data-rename-snapshot="${snapshot.id}">Rename</button><button class="primary" data-restore-snapshot="${snapshot.id}">Restore</button><button class="danger" data-delete-snapshot="${snapshot.id}">Delete</button></div></article>`).join('') || '<div class="empty-lane">No snapshots yet. Save a configuration to create one.</div>'}</div><div id="snapshot-compare"></div>`;
    root.querySelectorAll('[data-compare-snapshot]').forEach((button) => button.onclick = async () => { const result = await request(`/api/history/${button.dataset.compareSnapshot}`); root.querySelector('#snapshot-compare').innerHTML = `<pre class="review-json">${escapeHtml(JSON.stringify(result.changes, null, 2))}</pre>`; });
    root.querySelectorAll('[data-rename-snapshot]').forEach((button) => button.onclick = async () => { const name = prompt('Snapshot name'); if (!name) return; await request(`/api/history/${button.dataset.renameSnapshot}/rename`, { method: 'POST', body: JSON.stringify({ name }) }); render(); });
    root.querySelectorAll('[data-restore-snapshot]').forEach((button) => button.onclick = async () => { if (!confirm('Restore this snapshot as the active configuration?')) return; const result = await request(`/api/history/${button.dataset.restoreSnapshot}/restore`, { method: 'POST' }); state.config = result.config; state.savedConfig = structuredClone(result.config); state.dirty = false; render(); });
    root.querySelectorAll('[data-delete-snapshot]').forEach((button) => button.onclick = async () => { if (!confirm('Delete this snapshot?')) return; await request(`/api/history/${button.dataset.deleteSnapshot}`, { method: 'DELETE' }); render(); });
  } catch (error) { root.innerHTML = `<div class="errors">${escapeHtml(error.message)}</div>`; }
}

async function diagnosticsView() {
  root.innerHTML = title('Diagnostics', 'System readiness & activity', 'Checks are read-only and never move windows or change display state.', '<button id="run-self-test" class="primary">Run self-test</button><button id="copy-diagnostics" class="quiet">Copy</button><button id="export-diagnostics" class="quiet">Export</button>') + '<p>Running checks…</p>';
  try { const [diagnostics, activity] = await Promise.all([request('/api/diagnostics'), request('/api/activity')]); const documentText = JSON.stringify({ diagnostics, activity: activity.entries }, null, 2); root.innerHTML = title('Diagnostics', `Topology: ${diagnostics.topology}`, 'System, backend, schema and workspace checks. Copy or export this report when requesting support.', '<button id="run-self-test" class="primary">Run self-test</button><button id="copy-diagnostics" class="quiet">Copy</button><button id="export-diagnostics" class="quiet">Export</button>') + `<div class="cards">${diagnostics.checks.map((check) => `<article class="card diagnostic ${check.ok ? 'ok' : 'failed'}"><p class="kicker">${check.ok ? '✓ ready' : '⚠ attention'}</p><h3>${escapeHtml(check.id)}</h3><p>${escapeHtml(check.detail)}</p></article>`).join('')}</div><div class="section-head compact"><div><p class="kicker">Activity log</p><h2>Recent events</h2></div></div><pre class="review-json">${escapeHtml(activity.entries.map((entry) => `${entry.timestamp} ${entry.level.toUpperCase()} ${entry.event}`).join('\n') || 'No activity yet.')}</pre>`;
    root.querySelector('#copy-diagnostics').onclick = async () => { await navigator.clipboard.writeText(documentText); toast('Diagnostics copied'); };
    root.querySelector('#export-diagnostics').onclick = () => { const blob = new Blob([documentText], { type: 'application/json' }); const link = document.createElement('a'); link.href = URL.createObjectURL(blob); link.download = 'spacewright-diagnostics.json'; link.click(); URL.revokeObjectURL(link.href); };
    root.querySelector('#run-self-test').onclick = async () => { try { await request('/api/self-test', { method: 'POST' }); toast('Self-test passed'); render(); } catch (error) { toast(error.message, true); } };
  } catch (error) { root.innerHTML = `<div class="errors">${escapeHtml(error.message)}</div>`; }
}

async function tasksView() {
  state.config.profiles ||= {};
  root.innerHTML = title('Run control', 'Activate and monitor workspaces', 'Preview first, then explicitly confirm any operation that moves windows or changes Spaces.') + '<p>Loading tasks…</p>';
  try {
    const { tasks } = await request('/api/tasks');
    const targetOptions = [
      ...['solo', 'wide', 'tall'].map((id) => `<option value="mode:${id}">Mode · ${id}</option>`),
      ...Object.entries(state.config.profiles).map(([id, profile]) => `<option value="profile:${id}">Profile · ${escapeHtml(profile.name)}</option>`),
      ...Object.entries(state.config.workspaces).map(([id, workspace]) => `<option value="workspace:${id}">Workspace · ${escapeHtml(workspace.name)}</option>`)
    ].join('');
    root.innerHTML = title('Run control', 'Activate and monitor workspaces', 'Preview first, then explicitly confirm any operation that moves windows or changes Spaces.') + `<article class="card run-control"><div class="row"><div class="field"><label for="run-target">Target</label><select id="run-target">${targetOptions}</select></div><div class="field"><label for="run-mode">Workspace mode</label><select id="run-mode"><option>solo</option><option selected>wide</option><option>tall</option></select></div></div><label class="check"><input id="execution-confirm" type="checkbox"> I understand that Run now may launch apps, create or focus Spaces, and move or resize windows.</label><div class="actions"><button id="preview-target" class="quiet">Preview dry run</button><button id="run-target-now" class="primary" disabled>Run now</button></div><div id="run-preview"></div></article><div class="section-head compact"><div><p class="kicker">Task queue</p><h2>Recent executions</h2></div><button id="refresh-tasks" class="quiet">Refresh</button></div><div class="cards">${tasks.map((task) => `<article class="card task-card" data-task-id="${task.id}"><p class="kicker">${escapeHtml(task.status)}</p><h3>${escapeHtml(task.kind)} · ${escapeHtml(task.target)}</h3><p>${escapeHtml(task.createdAt)}</p><pre>${escapeHtml(task.logs.join('\n') || 'Waiting for output…')}</pre>${['queued','running'].includes(task.status) ? `<button class="danger" data-cancel-task="${task.id}">Cancel</button>` : ''}</article>`).join('') || '<div class="empty-lane">No tasks have run in this server session.</div>'}</div>`;
    const selection = () => { const [kind, target] = root.querySelector('#run-target').value.split(':'); return { kind, target, mode: root.querySelector('#run-mode').value }; };
    const syncMode = () => { root.querySelector('#run-mode').disabled = !root.querySelector('#run-target').value.startsWith('workspace:'); };
    syncMode(); root.querySelector('#run-target').onchange = syncMode;
    root.querySelector('#execution-confirm').onchange = (event) => { root.querySelector('#run-target-now').disabled = !event.target.checked; };
    root.querySelector('#preview-target').onclick = async () => { const value = selection(); const payload = value.kind === 'profile' ? { config: state.config, profile: value.target } : { config: state.config, mode: value.kind === 'mode' ? value.target : value.mode }; try { const result = await request('/api/preview', { method: 'POST', body: JSON.stringify(payload) }); root.querySelector('#run-preview').innerHTML = `<div class="change-summary"><strong>Dry run · no desktop changes</strong><pre>${escapeHtml(JSON.stringify(result, null, 2))}</pre></div>`; } catch (error) { toast(error.message, true); } };
    root.querySelector('#run-target-now').onclick = async () => { const value = selection(); if (!confirm(`Run ${value.kind} “${value.target}” now? This will change the live desktop.`)) return; try { const result = await request('/api/execute', { method: 'POST', body: JSON.stringify({ ...value, confirmed: true }) }); toast(`Task ${result.task.id} started`); setTimeout(() => render(), 400); } catch (error) { toast(error.message, true); } };
    root.querySelector('#refresh-tasks').onclick = render;
    root.querySelectorAll('[data-cancel-task]').forEach((button) => button.onclick = async () => { try { await request(`/api/tasks/${button.dataset.cancelTask}/cancel`, { method: 'POST' }); toast('Cancellation requested'); render(); } catch (error) { toast(error.message, true); } });
  } catch (error) { root.innerHTML = `<div class="errors">${escapeHtml(error.message)}</div>`; }
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
  else if (state.view === 'automation') automationView();
  else if (state.view === 'history') historyView();
  else if (state.view === 'diagnostics') diagnosticsView();
  else if (state.view === 'tasks') tasksView();
  else reviewView();
  syncUrl();
}

document.querySelectorAll('#nav button').forEach((button) => button.onclick = () => { state.view = button.dataset.view; render(); });
root.addEventListener('input', markDirty);
root.addEventListener('change', markDirty);
document.querySelector('#validate').onclick = async () => { try { const result = await request('/api/validate', { method: 'POST', body: JSON.stringify(state.config) }); toast(result.warnings?.length ? `Valid with ${result.warnings.length} warning(s)` : 'Configuration is valid'); } catch (error) { toast(error.message, true); } };
document.querySelector('#save').onclick = async (event) => { const button = event.currentTarget; button.disabled = true; button.textContent = 'Checking diff…'; try { const diff = await request('/api/diff', { method: 'POST', body: JSON.stringify(state.config) }); if (!diff.count) return toast('No changes to apply'); if (!confirm(`Apply ${diff.count} configuration change(s)? A snapshot will be created first.`)) return; button.textContent = 'Saving…'; const result = await request('/api/save', { method: 'POST', body: JSON.stringify(state.config) }); state.source = 'v2'; state.savedConfig = structuredClone(state.config); state.importChanges = []; state.dirty = false; document.querySelector('#status').textContent = 'Local · read/write · verified'; toast(`Saved and read-back verified: ${result.path}`); } catch (error) { toast(error.message, true); } finally { button.disabled = false; button.textContent = 'Save configuration'; } };
document.querySelector('#export-config').onclick = () => { const link = document.createElement('a'); link.href = '/api/export'; link.download = 'spacewright.yaml'; link.click(); };
document.querySelector('#import-config').onclick = () => document.querySelector('#import-file').click();
document.querySelector('#import-file').onchange = async (event) => { try { const result = await request('/api/import', { method: 'POST', body: JSON.stringify({ text: await event.target.files[0].text() }) }); const imported = result.config; state.importChanges = changedSections(state.savedConfig, imported); state.config = imported; state.source = 'import-preview'; state.selectedWorkspace = null; markDirty(); state.view = 'review'; render(); toast(`Imported validated preview with ${state.importChanges.length} changed section(s).`); } catch (error) { toast(error.message, true); } finally { event.target.value = ''; } };
document.querySelector('#revert-changes').onclick = () => { if (!state.dirty || confirm('Discard all unsaved changes?')) { state.config = structuredClone(state.savedConfig); state.dirty = false; state.selectedWorkspace = null; document.querySelector('#status').textContent = 'Local · read/write'; render(); } };
document.querySelector('#reset-defaults').onclick = async () => { if (!confirm('Replace the editor contents with SpaceWright defaults? This remains unsaved until Apply.')) return; const result = await request('/api/defaults'); state.config = result.config; state.selectedWorkspace = null; markDirty(); render(); };
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
      if (!['map', 'displays', 'workspaces', 'apps', 'shortcuts', 'automation', 'history', 'diagnostics', 'tasks', 'review'].includes(state.view)) state.view = 'map';
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
