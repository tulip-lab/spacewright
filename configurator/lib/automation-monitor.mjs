import { classifyTopology, matchingRules, ruleContext } from './automation-policy.mjs';
// One serialized queue owns sampling and event dispatch. Stop drains that queue
// before the server cancels/drains tasks, so no late event can enqueue work.
export function createAutomationMonitor({readConfig,querySnapshot,activity,executeRule,activateSetup,intervalMs=5000,now=Date.now}) {
  let lastTopology,candidateTopology,candidateSamples=0,lastAutomationAt=0,lastErrorAt=0;
  let stopped=true,timer=null,queue=Promise.resolve();
  const topologyFor=snapshot=>classifyTopology(snapshot.displays.map(d=>({...d,'is-built-in':d.builtIn,'is-visible':d.visible})));
  const enqueue=operation=>{
    if(stopped)return Promise.resolve();
    const next=queue.then(()=>stopped?undefined:operation());
    queue=next.catch(error=>{process.stderr.write(`automation monitor: ${error.message}\n`);});return next;
  };
  async function dispatch(config,event,snapshot,topology) {
    if(stopped)return;
    config=await readConfig();if(stopped)return;
    if(config.settings?.eventAutomationEnabled!==true){await activity('info','event_ignored',{event,reason:'automation_disabled'});return;}
    if(config.version!==2){await activity('info','event_ignored',{event,reason:'rules_version_unsupported',version:config.version});return;}
    const matches=matchingRules(config,ruleContext(config,event,snapshot,topology));
    await activity('info','event_evaluated',{event,topology,matches:matches.map(r=>r.id)});
    for(const rule of matches){if(stopped)return;await executeRule(config,rule);}
  }
  async function sample() {
    try {
      const snapshot=await querySnapshot();if(stopped)return;
      if(snapshot.completeness!=='complete') {
        candidateTopology=null;candidateSamples=0;
        if(now()-lastErrorAt>=60000){lastErrorAt=now();await activity('error','topology_query_unavailable',{message:snapshot.message});}return;
      }
      lastErrorAt=0;const topology=topologyFor(snapshot);
      if(topology==='unknown'){candidateTopology=null;candidateSamples=0;return;}
      if(lastTopology==null){lastTopology=topology;return;}
      if(topology===lastTopology){candidateTopology=null;candidateSamples=0;return;}
      if(candidateTopology!==topology){candidateTopology=topology;candidateSamples=0;}
      candidateSamples++;
      const config=await readConfig();if(stopped)return;
      if(candidateSamples<(config.settings?.topologyStableSamples || 3))return;
      const previous=lastTopology;lastTopology=topology;candidateTopology=null;candidateSamples=0;
      await activity('info','topology_changed',{previous,topology});if(stopped)return;
      if(await activateSetup(topology,()=>stopped))return;
      if(config.settings?.eventAutomationEnabled!==true)return;
      if(now()-lastAutomationAt<(config.settings?.topologyCooldownSeconds ?? 30)*1000){await activity('info','topology_automation_suppressed',{previous,topology,reason:'cooldown'});return;}
      lastAutomationAt=now();
      const event=['solo','clamshell'].includes(topology)?'display_disconnected':['solo','clamshell'].includes(previous)?'display_connected':'topology_changed';
      await dispatch(config,event,snapshot,topology);
    } catch(error) {await activity('error','topology_monitor_failed',{message:error.message});}
  }
  const monitor={
    start(){if(!stopped)return;stopped=false;const schedule=()=>{timer=setTimeout(async()=>{await enqueue(sample);if(!stopped)schedule();},intervalMs);timer.unref();};schedule();},
    sample:()=>enqueue(sample),
    trigger:event=>enqueue(async()=>{
      const config=await readConfig();if(stopped)return;
      if(config.settings?.eventAutomationEnabled!==true){await activity('info','event_ignored',{event,reason:'automation_disabled'});return;}
      if(config.version!==2){await activity('info','event_ignored',{event,reason:'rules_version_unsupported',version:config.version});return;}
      const snapshot=await querySnapshot();if(stopped)return;
      if(snapshot.completeness!=='complete'){await activity('error','event_query_unavailable',{event,message:snapshot.message});return;}
      const topology=topologyFor(snapshot);if(topology==='unknown')return;
      await dispatch(config,event,snapshot,topology);
    }),
    async stop(){stopped=true;clearTimeout(timer);await queue;}
  };
  return monitor;
}
