import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { hardwareFamilyFromModel } from './config-v3.mjs';

const execFileAsync = promisify(execFile);

export async function detectMacHardware({ modelIdentifier = '', productName = '', allowSystemProfiler = true } = {}) {
  const warnings = [];
  const sources = [];
  if (!modelIdentifier) {
    try {
      modelIdentifier = (await execFileAsync('sysctl', ['-n', 'hw.model'], { timeout: 10_000 })).stdout.trim();
      sources.push('sysctl');
    } catch (error) { warnings.push(`model identifier discovery failed: ${error.message}`); }
  } else sources.push('argument');

  let family = hardwareFamilyFromModel(modelIdentifier, productName);
  if (family === 'other' && !productName && allowSystemProfiler) {
    try {
      const output = (await execFileAsync('system_profiler', ['SPHardwareDataType', '-json'], { timeout: 15_000, maxBuffer: 2_000_000 })).stdout;
      productName = String(JSON.parse(output).SPHardwareDataType?.[0]?.machine_name || '').trim();
      if (productName) sources.push('system_profiler');
    } catch (error) { warnings.push(`product name discovery failed: ${error.message}`); }
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
