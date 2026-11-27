import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { readSpaceLabelHints } from './space-label-history.mjs';
import { buildDesiredState, buildExecutionPlan, compareState } from './state-engine.mjs';

const execFileAsync = promisify(execFile);

export async function planDesktop({ config, runtime, target, snapshot, machine, stateRoot, signal,
  contextSnapshot, sandboxWindowIds, displayProfile, displayPrepared, attemptedOptionalWindows }) {
  const options = { contextSnapshot, sandboxWindowIds };
  let desired = buildDesiredState(config, runtime, target, snapshot, options);
  const spaceLabelHints = await readSpaceLabelHints(stateRoot, desired, snapshot);
  if (Object.keys(spaceLabelHints).length) {
    desired = buildDesiredState(config, runtime, target, snapshot, { ...options, spaceLabelHints });
  }
  if (displayProfile) desired.orchestration.displayProfile = displayProfile;

  const runningApps = new Set();
  if (desired.workspaces.some(workspace => workspace.runner === 'primary_helper'
    && workspace.windows.some(role => !role.required && role.role === 'helper' && role.appKey === 'outlook'))
    && !snapshot.windows.some(window => window.app === 'Microsoft Outlook')) {
    try {
      const { stdout } = await execFileAsync('pgrep', ['-x', 'Microsoft Outlook'], { timeout: 1000, signal });
      if (stdout.trim()) runningApps.add('Microsoft Outlook');
    } catch (error) {
      if (signal?.aborted) throw signal.reason || error;
      // This read only determines whether an absent optional app can be reopened.
    }
  }
  const planning = { attemptedOptionalWindows, runningApps, displayPrepared };
  const comparison = compareState(snapshot, desired, machine, { ...planning, spaceLabelHints });
  const plan = buildExecutionPlan(snapshot, desired, comparison, planning);
  return { desired, comparison, plan };
}
