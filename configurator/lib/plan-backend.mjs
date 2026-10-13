// Compose the closed public backend commands after selection and scope policy.
export function executionStepsFor({ desired, actions, affectedWorkspaces, affectedWorkspaceIds, needsFinalization, orchestration }) {
  const executionSteps = [];
  if (actions.some((action) => action.type === 'apply_display_profile')) executionSteps.push({ type: 'command', action: 'display_profile', command: ['display', orchestration.displayProfile] });
  if (affectedWorkspaces.length) {
    const includePostprocessors = desired.target.kind === 'mode';
    if (includePostprocessors) for (const hook of (desired.postprocessors || []).filter((item) => item.afterCommand == null)) executionSteps.push({ type: 'command', action: 'postprocess', command: ['postprocess', hook.name] });
    for (const workspace of desired.workspaces) {
      if (affectedWorkspaceIds.has(workspace.workspaceId)) executionSteps.push({ type: 'command', action: 'workspace', workspaceId: workspace.workspaceId, command: ['run', workspace.workspaceId, desired.target.mode] });
      if (includePostprocessors) for (const hook of (desired.postprocessors || []).filter((item) => item.afterCommand === workspace.runtimeId)) executionSteps.push({ type: 'command', action: 'postprocess', command: ['postprocess', hook.name] });
    }
  }
  if (needsFinalization) executionSteps.push({ type: 'command', action: 'finalize_mode', command: ['finalize', desired.target.mode] });
  if (actions.some((action) => action.type === 'focus_workspace')) executionSteps.push({ type: 'command', action: 'focus', command: ['focus', orchestration.focusWorkspace, desired.target.mode] });
  return executionSteps;
}
