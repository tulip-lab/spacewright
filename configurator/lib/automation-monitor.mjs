import { classifyTopology, matchingRules, ruleContext } from './automation-policy.mjs';
import { describeDisplays, topologyKey } from './config-v3.mjs';

export function displayTopology(snapshot, config, machine) {
  if (snapshot.completeness !== 'complete') return null;
  if (config.version === 3) {
    const displays = describeDisplays(snapshot, machine);
    if (!displays.length) return null;
    const key = topologyKey(displays);
    // A replacement display or geometry change can also require a new runtime.
    const signature = JSON.stringify([key, displays.map(({ uuid, index, frame }) =>
      [uuid, index, frame.x, frame.y, frame.w, frame.h])]);
    return { key, signature };
  }
  const key = classifyTopology(snapshot.displays.map(display => ({
    ...display,
    'is-built-in': display.builtIn ?? display['is-built-in'],
    'is-visible': display.visible ?? display['is-visible']
  })));
  return key === 'unknown' ? null : { key, signature: key };
}

// One serialized queue owns sampling and dispatch, including during shutdown.
export function createAutomationMonitor({ readContext, queryDisplays, querySnapshot, activity, executeRule, activateSetup, intervalMs = 5000, now = Date.now }) {
  let lastTopology, candidateTopology, candidateSamples = 0, lastAutomationAt = 0, lastErrorAt = null;
  let stopped = true, timer = null, queue = Promise.resolve();
  const resetCandidate = () => { candidateTopology = null; candidateSamples = 0; };
  const enqueue = operation => {
    if (stopped) return Promise.resolve();
    const next = queue.then(() => stopped ? undefined : operation());
    queue = next.catch(error => { process.stderr.write(`automation monitor: ${error.message}\n`); });
    return next;
  };

  async function dispatch(event, expectedTopology) {
    const { config, machine } = await readContext();
    if (stopped) return;
    if (config.settings?.eventAutomationEnabled !== true) {
      await activity('info', 'event_ignored', { event, reason: 'automation_disabled' });
      return;
    }
    if (config.version !== 2) {
      await activity('info', 'event_ignored', { event, reason: 'rules_version_unsupported', version: config.version });
      return;
    }
    const candidates = (config.rules || []).filter(rule => rule.enabled && (!rule.when?.event || rule.when.event === event));
    if (!candidates.length) return;
    const snapshot = await querySnapshot(machine);
    if (stopped) return;
    if (snapshot.completeness !== 'complete') {
      await activity('error', 'event_query_unavailable', { event, message: snapshot.message });
      return;
    }
    const topology = displayTopology(snapshot, config, machine)?.key;
    if (!topology || expectedTopology && topology !== expectedTopology) return;
    const matches = matchingRules(config, ruleContext(config, event, snapshot, topology));
    await activity('info', 'event_evaluated', { event, topology, matches: matches.map(rule => rule.id) });
    for (const rule of matches) {
      if (stopped) return;
      await executeRule(config, rule);
    }
  }

  async function sample() {
    try {
      const { config, machine } = await readContext();
      if (stopped) return;
      const snapshot = await queryDisplays();
      if (stopped) return;
      if (snapshot.completeness !== 'complete') {
        resetCandidate();
        if (lastErrorAt === null || now() - lastErrorAt >= 60000) {
          lastErrorAt = now();
          await activity('error', 'topology_query_unavailable', { message: snapshot.message });
        }
        return;
      }
      lastErrorAt = null;
      const topology = displayTopology(snapshot, config, machine);
      if (!topology) { resetCandidate(); return; }
      if (lastTopology?.version !== config.version) {
        lastTopology = { ...topology, version: config.version };
        resetCandidate();
        return;
      }
      if (topology.signature === lastTopology.signature) { resetCandidate(); return; }
      if (topology.signature !== candidateTopology) {
        resetCandidate();
        candidateTopology = topology.signature;
      }
      if (++candidateSamples < (config.settings?.topologyStableSamples || 3)) return;
      const previousTopology = lastTopology;
      const previous = previousTopology.key;
      resetCandidate();
      await activity('info', 'topology_changed', { previous, topology: topology.key });
      if (stopped) return;
      if (config.version === 3) {
        // A mismatch or transient read failure is eligible for a fresh sample.
        if (await activateSetup(topology, () => stopped)) lastTopology = { ...topology, version: config.version };
        return;
      }
      lastTopology = { ...topology, version: config.version };
      if (config.version !== 2 || config.settings?.eventAutomationEnabled !== true) return;
      if (now() - lastAutomationAt < (config.settings?.topologyCooldownSeconds ?? 30) * 1000) {
        await activity('info', 'topology_automation_suppressed', { previous, topology: topology.key, reason: 'cooldown' });
        return;
      }
      lastAutomationAt = now();
      const event = ['solo', 'clamshell'].includes(topology.key) ? 'display_disconnected'
        : ['solo', 'clamshell'].includes(previous) ? 'display_connected' : 'topology_changed';
      await dispatch(event, topology.key);
    } catch (error) {
      resetCandidate();
      await activity('error', 'topology_monitor_failed', { message: error.message });
    }
  }

  return {
    start() {
      if (!stopped) return;
      stopped = false;
      const schedule = () => {
        timer = setTimeout(async () => { await enqueue(sample); if (!stopped) schedule(); }, intervalMs);
        timer.unref();
      };
      schedule();
    },
    sample: () => enqueue(sample),
    trigger: event => enqueue(() => dispatch(event)),
    async stop() { stopped = true; clearTimeout(timer); await queue; }
  };
}
