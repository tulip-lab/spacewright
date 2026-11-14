import test from 'node:test';
import assert from 'node:assert/strict';
import { starterConfig, compileV2 } from '../lib/config-v2.mjs';
import { normalizeSnapshot, buildDesiredState, compareState, buildExecutionPlan } from '../lib/state-engine.mjs';
import { preparationCommand, preparationsFor, verifyPreparation } from '../lib/adapter-preparation.mjs';
import { processIdentities, processIdentity } from '../lib/execution-coordinator.mjs';

const machine = { displayBindings: { primary: 'D' } };
function mailPlan({ recovered = false, attemptedRefresh = false, attemptedObservation = false, outlookWindowId = 11,
  noOutlookWindow = false, outlookRunning = false } = {}) {
  const config = starterConfig();
  config.apps.outlook = { name: 'Outlook', match: { appNames: ['Microsoft Outlook'] } };
  config.workspaces.coding.windows = {
    primary: { app: 'code', required: true },
    helper: { app: 'outlook', required: false }
  };
  const variant = {
    layout: { type: 'canvas', regions: [
      { role: 'primary', grid: '1:2:0:0:1:1' },
      { role: 'helper', grid: '1:2:1:0:1:1' }
    ] },
    runtime: { runner: 'primary_helper', primaryAloneLayout: [{ role: 'primary', grid: '1:1:0:0:1:1' }] }
  };
  for (const mode of ['solo', 'wide', 'tall']) config.workspaces.coding.variants[mode] = variant;
  const raw = {
    displays: [{ index: 1, uuid: 'D', frame: { x: 0, y: 0, w: 1000, h: 800 } }],
    spaces: [{ index: 1, uuid: 'S', display: 1, label: 'coding_solo', type: 'float' },
      { index: 2, uuid: 'O', display: 1, label: 'support_solo', type: 'float' }],
    windows: [
      { id: 10, pid: 100, app: 'Code', title: 'Editor', display: 1, space: 1,
        frame: { x: 0, y: 0, w: recovered ? 500 : 1000, h: 800 }, 'can-move': true, 'can-resize': true },
      ...(!noOutlookWindow ? [{ id: outlookWindowId, pid: 101, app: 'Microsoft Outlook', display: 1, space: 2,
        frame: { x: 500, y: 0, w: 500, h: 800 }, 'has-ax-reference': recovered,
        'can-move': recovered, 'can-resize': recovered }] : [])
    ]
  };
  const snapshot = normalizeSnapshot(raw, machine);
  const desired = buildDesiredState(config, compileV2(config), { kind: 'workspace', id: 'coding', mode: 'solo' }, snapshot);
  const runningApps = new Set(outlookRunning ? ['Microsoft Outlook'] : []);
  const attemptedOptionalWindows = new Set([
    ...(attemptedRefresh ? ['coding:helper:refresh_app'] : []),
    ...(attemptedObservation ? ['coding:helper:observe_space'] : [])
  ]);
  const comparison = compareState(snapshot, desired, machine, { runningApps,attemptedOptionalWindows });
  const plan = buildExecutionPlan(snapshot, desired, comparison,
    { attemptedOptionalWindows,runningApps });
  return { snapshot, desired, comparison, plan };
}

test('AX-less optional Outlook gets one bounded reopen before mail layout planning', async () => {
  const { snapshot, desired, comparison, plan } = mailPlan();
  assert.ok(comparison.drifts.some(d => d.code === 'optional_windows_unavailable' && d.role === 'helper'));
  assert.equal(plan.executable, true);
  assert.equal(plan.preparations.length, 1);
  const preparation = plan.preparations[0];
  assert.equal(preparation.commandPolicy, 'outlook_reopen');
  assert.equal(preparation.bestEffort, true);
  const observation = mailPlan({ attemptedRefresh: true }).plan.preparations[0];
  assert.equal(observation.type, 'observe_space');
  assert.equal(observation.spaceUuid, 'O');
  assert.equal(preparationsFor(snapshot, desired, { attemptedOptionalWindows: new Set(['coding:helper:refresh_app','coding:helper:observe_space']) }).length, 0);
  assert.equal(mailPlan({ attemptedRefresh: true, outlookWindowId: 22 }).plan.preparations[0].type, 'observe_space');
  const exhausted = mailPlan({ attemptedRefresh: true, attemptedObservation: true });
  assert.equal(exhausted.plan.preparations.length, 0);
  assert.equal(exhausted.plan.executable, false);
  assert.ok(exhausted.plan.blockers.some(b=>b.code==='outlook_window_unavailable'));
  const [exe, args] = preparationCommand(preparation, snapshot);
  assert.equal(exe, 'osascript');
  assert.equal(args.at(-1), 'Microsoft Outlook');
  const unavailable = await verifyPreparation(preparation,
    { discover: async () => snapshot, poll: async () => {}, delay: async () => {} });
  assert.equal(unavailable.outcome, 'optional_unavailable');
  assert.equal(mailPlan({ recovered: true }).plan.preparations.length, 0);
  assert.ok(mailPlan({ recovered: true }).plan.selectedWindows.some(w => w.role === 'helper' && w.id === 11));
});

test('running Outlook without a window is reopened once, then must become selectable', () => {
  const first = mailPlan({ noOutlookWindow: true, outlookRunning: true });
  assert.equal(first.plan.executable, true);
  assert.equal(first.plan.preparations[0].type, 'refresh_app');
  assert.equal(first.plan.preparations[0].window.id, null);
  assert.equal(preparationCommand(first.plan.preparations[0], first.snapshot)[0], 'osascript');
  const exhausted = mailPlan({ noOutlookWindow: true, outlookRunning: true, attemptedRefresh: true });
  assert.equal(exhausted.plan.executable, false);
  assert.ok(exhausted.plan.blockers.some(blocker => blocker.code === 'outlook_window_unavailable'));
  assert.equal(mailPlan({ noOutlookWindow: true }).plan.preparations.length, 0);
});

test('batched process identity matches individual verification and excludes missing processes', async () => {
  const identities = await processIdentities([process.pid, process.pid, 2147483647]);
  assert.equal(identities.get(process.pid), await processIdentity(process.pid));
  assert.equal(identities.get(2147483647), null);
});
