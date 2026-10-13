import { runBounded } from './execution-coordinator.mjs';
import { hardwareFamilyFromModel } from './config-v3.mjs';


export async function detectMacHardware({ modelIdentifier = '', productName = '', allowSystemProfiler = true, deadline = Number(process.env.SPACEWRIGHT_EXECUTION_DEADLINE_MS) || Date.now()+25000, signal } = {}) {
  const warnings = [];
  const sources = [];
  if (!modelIdentifier) {
    try {
      const result = await runBounded('sysctl', ['-n','hw.model'], {deadline:Math.min(deadline,Date.now()+10000),signal});
      if(result.code) throw new Error(result.stderr || 'model query failed');
      modelIdentifier = result.stdout.trim();
      sources.push('sysctl');
    } catch (error) { if (['SPACEWRIGHT_TIMEOUT','SPACEWRIGHT_CANCELLED'].includes(error.code)) throw error; warnings.push(`model identifier discovery failed: ${error.message}`); }
  } else sources.push('argument');

  let family = hardwareFamilyFromModel(modelIdentifier, productName);
  if (family === 'other' && !productName && allowSystemProfiler) {
    try {
      const result = await runBounded('system_profiler', ['SPHardwareDataType','-json'], {deadline:Math.min(deadline,Date.now()+15000),signal});
      if(result.code) throw new Error(result.stderr || 'hardware query failed');
      const output = result.stdout;
      productName = String(JSON.parse(output).SPHardwareDataType?.[0]?.machine_name || '').trim();
      if (productName) sources.push('system_profiler');
    } catch (error) { if (['SPACEWRIGHT_TIMEOUT','SPACEWRIGHT_CANCELLED'].includes(error.code)) throw error; warnings.push(`product name discovery failed: ${error.message}`); }
    family = hardwareFamilyFromModel(modelIdentifier, productName);
  }
  return {
    modelIdentifier,
    productName,
    family,
    source: sources.join('+') || 'fallback',
    ...(warnings.length ? { warning: warnings.join('; ') } : {})
  };
}
