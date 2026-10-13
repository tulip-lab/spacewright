import { processIdentity, runBounded } from './execution-coordinator.mjs';
import { normalizeSnapshot } from './state-engine.mjs';
import { existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';
const packageRoot=fileURLToPath(new URL('../..',import.meta.url));
export async function discoverGridGeometry(displays,spaces,{executable='yabai',deadline=Date.now()+5000,signal,run=runBounded,onWindowFrames=()=>{}}={}) {
  // Fixture/query providers may already supply geometry or omit native display
  // IDs. Native yabai always supplies IDs; its usable frame must be discovered.
  if(!displays.some(d=>d.id && !d.gridGeometry))return displays;
  const binary=join(packageRoot,'bin','spacewright-screen-geometry');
  const result=await run(existsSync(binary)?binary:'/usr/bin/swift',existsSync(binary)?[]:[join(packageRoot,'helpers','spacewright-screen-geometry.swift')],{deadline:Math.min(deadline,Date.now()+5000),signal});
  if(result.code)throw new Error(`usable display geometry unavailable: ${result.stderr}`);
  const native=JSON.parse(result.stdout);
  const screens=native.displays;
  if(!Array.isArray(screens))throw new Error('native display geometry is invalid');
  if(!Array.isArray(native.windows))throw new Error('native window geometry is invalid');
  onWindowFrames(native.windows);
  const config=async args=>{
    const r=await run(executable,['-m','config',...args],{deadline:Math.min(deadline,Date.now()+3000),signal});
    if(r.code)throw new Error(`grid configuration query failed: ${r.stderr}`);
    return r.stdout.trim();
  };
  const external=(await config(['external_bar'])).split(':');
  if(!['off','main','all'].includes(external[0]) || external.length!==3 || !external.slice(1).every(v=>Number.isFinite(Number(v))))throw new Error('invalid external bar geometry');
  return Promise.all(displays.map(async display=>{
    if(!display.id || display.gridGeometry)return display;
    const matches=screens.filter(s=>s.uuid.toUpperCase()===display.uuid.toUpperCase());
    if(matches.length!==1)throw new Error('display usable frame missing or ambiguous');
    const active=spaces.find(s=>s.display===display.index && s['is-visible']) || spaces.find(s=>s.display===display.index);
    if(!active)throw new Error('display has no active Space for grid geometry');
    const values=await Promise.all(['top_padding','bottom_padding','left_padding','right_padding','window_gap'].map(key=>config(['--space',String(active.index),key])));
    if(!values.every(v=>/^\d+$/.test(v)))throw new Error('invalid grid padding/gap');
    const [top,bottom,left,right,gap]=values.map(Number), frame={...matches[0].frame};
    // NSScreen already excludes the menu bar. External bar padding is additional.
    if(external[0]==='all' || external[0]==='main' && display.index===1) {
      frame.y+=Number(external[1]);frame.h-=Number(external[1])+Number(external[2]);
    }
    return {...display,gridGeometry:{frame,padding:{top,bottom,left,right},gap}};
  }));
}
export function applyNativeWindowFrames(windows,frames) {
  if(frames===null)return {windows,missing:[]}; // fixture provider without native IDs
  const missing=[];
  const resolved=windows.map(window=>{
    const candidates=frames.filter(f=>Number(f.id)===Number(window.id));
    const native=candidates.length===1 && Number(candidates[0].pid)===Number(window.pid)?candidates[0]:null;
    const valid=native && ['x','y','w','h'].every(k=>Number.isFinite(native.frame?.[k])) && native.frame.w>=0 && native.frame.h>=0;
    if(valid)return {...window,frame:native.frame,frameVerified:true};
    // Noninteractive root/helper surfaces can be absent from WindowServer.
    // Movable windows used for layout cannot silently use cached AX bounds.
    if(window['can-move'] && !window['is-minimized'] && !window['is-native-fullscreen'])missing.push(`window_geometry:${window.id}`);
    return {...window,frameVerified:false};
  });
  return {windows:resolved,missing};
}
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
  let displays = results[0].status === 'fulfilled' ? results[0].value : [];
  const spaces = results[1].status === 'fulfilled' ? results[1].value : [];
  let windows = results[2].status === 'fulfilled' ? results[2].value : [];
  const missingQueries = results.slice(0, 2).flatMap((r, i) => r.status === 'rejected' ? [i ? 'spaces' : 'displays'] : []);
  let nativeFrames=null;
  try { displays=await discoverGridGeometry(displays,spaces,{executable,deadline,signal,onWindowFrames:value=>{nativeFrames=value;}}); }
  catch(error) { missingQueries.push(`grid_geometry:${error.message}`); }
  if (results[2].status === 'rejected') {
    windows = [];
    if (!spaces.length) missingQueries.push('windows');
    else {
      const fallback = await Promise.allSettled(spaces.map((s) => query('--windows', '--space', String(s.index))));
      fallback.forEach((r, i) => r.status === 'fulfilled' ? windows.push(...r.value) : missingQueries.push(`windows:space:${spaces[i].index}`));
      windows = [...new Map(windows.map((w) => [w.id, w])).values()];
    }
  }
  const geometry=applyNativeWindowFrames(windows,nativeFrames);
  windows=geometry.windows;missingQueries.push(...geometry.missing);
  const pids = [...new Set(windows.map((w) => Number(w.pid)).filter((pid) => pid > 1))];
  const processes = new Map(await Promise.all(pids.map(async (pid) => [pid, await processIdentity(pid)])));
  windows = windows.map((w) => ({ ...w, processFingerprint: processes.get(Number(w.pid)) || null }));
  const completeness = missingQueries.length ? (displays.length || spaces.length || windows.length ? 'partial' : 'unavailable') : 'complete';
  return normalizeSnapshot({ capturedAt, displays, spaces, windows, completeness, missingQueries,
    ...(completeness !== 'complete' ? { message: `live yabai discovery ${completeness}; missing ${missingQueries.join(', ')}` } : {}) }, machine);
}
