import { processIdentity, runBounded } from './execution-coordinator.mjs';
import { normalizeSnapshot } from './state-engine.mjs';
export async function discoverState(machine = {}, { deadline = Date.now() + 15000, signal, executable = 'yabai' } = {}) {
  const capturedAt = new Date().toISOString();
  const query = async (...args) => {
    const result = await runBounded(executable, ['-m', 'query', ...args], { deadline: Math.min(deadline, Date.now() + 5000), signal });
    if (result.code) throw new Error(result.stderr || `query ${args.join(' ')} failed (${result.code})`);
    const value = JSON.parse(result.stdout);
    if (!Array.isArray(value)) throw new Error(`invalid query ${args.join(' ')}`);
    return value;
  };
  const results = await Promise.allSettled([query('--displays'), query('--spaces'), query('--windows')]);
  const displays = results[0].status === 'fulfilled' ? results[0].value : [];
  const spaces = results[1].status === 'fulfilled' ? results[1].value : [];
  let windows = results[2].status === 'fulfilled' ? results[2].value : [];
  const missingQueries = results.slice(0, 2).flatMap((r, i) => r.status === 'rejected' ? [i ? 'spaces' : 'displays'] : []);
  if (results[2].status === 'rejected') {
    windows = [];
    if (!spaces.length) missingQueries.push('windows');
    else {
      const fallback = await Promise.allSettled(spaces.map((s) => query('--windows', '--space', String(s.index))));
      fallback.forEach((r, i) => r.status === 'fulfilled' ? windows.push(...r.value) : missingQueries.push(`windows:space:${spaces[i].index}`));
      windows = [...new Map(windows.map((w) => [w.id, w])).values()];
    }
  }
  const pids = [...new Set(windows.map((w) => Number(w.pid)).filter((pid) => pid > 1))];
  const processes = new Map(await Promise.all(pids.map(async (pid) => [pid, await processIdentity(pid)])));
  windows = windows.map((w) => ({ ...w, processFingerprint: processes.get(Number(w.pid)) || null }));
  const completeness = missingQueries.length ? (displays.length || spaces.length || windows.length ? 'partial' : 'unavailable') : 'complete';
  return normalizeSnapshot({ capturedAt, displays, spaces, windows, completeness, missingQueries,
    ...(completeness !== 'complete' ? { message: `live yabai discovery ${completeness}; missing ${missingQueries.join(', ')}` } : {}) }, machine);
}
