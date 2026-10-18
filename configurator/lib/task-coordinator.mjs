import { runBounded } from './execution-coordinator.mjs';
export function cancelWebTask(task) {
  task.cancelRequested = true;
  if (task.status === 'queued') task.status = 'cancelled';
  task.abort?.abort(Object.assign(new Error('task cancelled'), { code: 'SPACEWRIGHT_CANCELLED' }));
}
export async function runWebTask(task, commands, { executable, env, activity, append, beforeCommand, timeoutMs = 120000 }) {
  task.abort = new AbortController();
  const deadline = Date.now() + timeoutMs;
  try {
    if (task.cancelRequested || task.status === 'cancelled') { task.status = 'cancelled'; task.exitCode = 130; return; }
    task.status = 'running'; task.startedAt = new Date().toISOString();
    await activity('info', 'task_started', { id: task.id, target: task.target });
    for (const args of commands) {
      if (task.cancelRequested) break;
      await beforeCommand?.();
      if (task.cancelRequested) break;
      append(task, `$ spacewright ${args.join(' ')}`);
      const result = await runBounded(executable, args, { deadline, signal: task.abort.signal, env: { ...env, SPACEWRIGHT_EXECUTION_DEADLINE_MS: String(deadline) },
        onChild: (child) => { task.child = child; }, onOutput: (channel, value) => { for (const line of value.split('\n').filter(Boolean)) append(task, `${channel === 'stderr' ? 'ERR' : 'OUT'} ${line}`); } });
      task.exitCode = result.code;
      // apply returns a verified completion document. A zero exit code alone is insufficient.
      let completion;
      try { completion = JSON.parse(result.stdout); } catch {}
      if (result.code !== 0 || !(completion?.noop || completion?.status === 'completed' && completion?.verification?.converged)) { task.exitCode ||= 1; break; }
    }
    task.status = task.cancelRequested ? 'cancelled' : task.exitCode === 0 ? 'completed' : 'failed';
  } catch (error) {
    task.status = error.code === 'SPACEWRIGHT_CANCELLED' ? 'cancelled' : error.code === 'SPACEWRIGHT_TIMEOUT' ? 'timed_out' : 'failed';
    task.exitCode = task.status === 'cancelled' ? 130 : task.status === 'timed_out' ? 124 : 1;
    task.error = error.message; append(task, `ERR ${error.message}`);
  } finally {
    task.child = null; task.finishedAt = new Date().toISOString();
    try { await activity(task.status === 'completed' ? 'info' : 'error', 'task_finished', { id: task.id, status: task.status, exitCode: task.exitCode }); }
    catch (error) { task.loggingError = error.message; append(task, `ERR activity write failed: ${error.message}`); }
  }
}
