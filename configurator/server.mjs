#!/usr/bin/env node

import http from 'node:http';
import { readFile, writeFile, rename, mkdir, copyFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { dirname, extname, join, resolve } from 'node:path';
import { randomBytes } from 'node:crypto';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { compileSkhd, compileV2, migrateV1, starterConfig, validateV2 } from './lib/config-v2.mjs';

const execFileAsync = promisify(execFile);
const args = Object.fromEntries(process.argv.slice(2).map((arg) => arg.split('=', 2)));
const packageRoot = resolve(args['--package-root'] || join(import.meta.dirname, '..'));
const configRoot = resolve(args['--config-root'] || join(process.env.HOME, '.config', 'spacewright'));
const stateRoot = resolve(args['--state-root'] || join(process.env.HOME, '.local', 'state', 'spacewright'));
const configFile = join(configRoot, 'config.v2.json');
const machineFile = join(stateRoot, 'machine.json');
const publicRoot = join(packageRoot, 'configurator', 'public');
const token = args['--token'] || randomBytes(24).toString('hex');
const listenPort = Number(args['--port'] || 0);

async function readConfig() {
  if (!existsSync(configFile)) return starterConfig();
  return JSON.parse(await readFile(configFile, 'utf8'));
}

async function readLegacyConfig() {
  const defaults = JSON.parse(await readFile(join(packageRoot, 'config', 'defaults.json'), 'utf8'));
  const userFile = join(configRoot, 'config.json');
  if (!existsSync(userFile)) return defaults;
  const user = JSON.parse(await readFile(userFile, 'utf8'));
  const merge = (base, override) => {
    if (!base || !override || typeof base !== 'object' || typeof override !== 'object' || Array.isArray(base) || Array.isArray(override)) return override;
    const result = { ...base };
    for (const [key, value] of Object.entries(override)) result[key] = key in base ? merge(base[key], value) : value;
    return result;
  };
  return merge(defaults, user);
}

async function readMachine() {
  if (!existsSync(machineFile)) return { version: 1, displayBindings: {} };
  const value = JSON.parse(await readFile(machineFile, 'utf8'));
  return { version: 1, displayBindings: value.displayBindings || {} };
}

function json(response, status, body) {
  response.writeHead(status, { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store', 'x-content-type-options': 'nosniff', 'x-frame-options': 'DENY' });
  response.end(JSON.stringify(body));
}

async function body(request) {
  let value = '';
  for await (const chunk of request) {
    value += chunk;
    if (value.length > 2_000_000) throw new Error('request body is too large');
  }
  return JSON.parse(value || '{}');
}

async function atomicWrite(path, value) {
  await mkdir(dirname(path), { recursive: true, mode: 0o700 });
  if (existsSync(path)) await copyFile(path, `${path}.backup`);
  const temporary = `${path}.tmp-${process.pid}`;
  await writeFile(temporary, value, { mode: 0o600 });
  await rename(temporary, path);
}

async function api(request, response, url) {
  if (request.method !== 'GET' && request.headers['x-spacewright-token'] !== token) return json(response, 403, { error: 'invalid session token' });
  if (url.pathname === '/api/config' && request.method === 'GET') return json(response, 200, { config: await readConfig(), path: configFile, source: existsSync(configFile) ? 'v2' : 'starter', legacyAvailable: true });
  if (url.pathname === '/api/legacy-preview' && request.method === 'GET') return json(response, 200, { config: migrateV1(await readLegacyConfig()), source: 'legacy-preview', writes: false });
  if (url.pathname === '/api/machine' && request.method === 'GET') return json(response, 200, { machine: await readMachine(), path: machineFile });
  if (url.pathname === '/api/validate' && request.method === 'POST') {
    const config = await body(request);
    const validation = validateV2(config);
    return json(response, validation.valid ? 200 : 422, { ...validation, runtime: validation.valid ? compileV2(config) : null });
  }
  if (url.pathname === '/api/save' && request.method === 'POST') {
    const config = await body(request);
    const validation = validateV2(config);
    if (!validation.valid) return json(response, 422, validation);
    await atomicWrite(configFile, `${JSON.stringify(config, null, 2)}\n`);
    return json(response, 200, { saved: true, path: configFile });
  }
  if (url.pathname === '/api/skhd' && request.method === 'POST') {
    const config = await body(request);
    const validation = validateV2(config);
    if (!validation.valid) return json(response, 422, validation);
    const path = join(configRoot, 'generated', 'spacewright.skhdrc');
    await atomicWrite(path, compileSkhd(config));
    return json(response, 200, { saved: true, path });
  }
  if (url.pathname === '/api/display-bindings' && request.method === 'POST') {
    const payload = await body(request);
    const config = await readConfig();
    if (!payload.displayBindings || typeof payload.displayBindings !== 'object' || Array.isArray(payload.displayBindings)) return json(response, 422, { error: 'displayBindings must be an object' });
    for (const [role, uuid] of Object.entries(payload.displayBindings)) {
      if (!config.displayRoles[role]) return json(response, 422, { error: `unknown display role: ${role}` });
      if (typeof uuid !== 'string' || !/^[A-Za-z0-9-]{8,}$/.test(uuid)) return json(response, 422, { error: `invalid display UUID for ${role}` });
    }
    const machine = { version: 1, displayBindings: payload.displayBindings };
    await atomicWrite(machineFile, `${JSON.stringify(machine, null, 2)}\n`);
    return json(response, 200, { saved: true, machine, path: machineFile });
  }
  if (url.pathname === '/api/displays' && request.method === 'GET') {
    try {
      const { stdout } = await execFileAsync('yabai', ['-m', 'query', '--displays'], { timeout: 2500, maxBuffer: 1_000_000 });
      return json(response, 200, { displays: JSON.parse(stdout), mutates: false });
    } catch (error) {
      return json(response, 200, { displays: [], unavailable: true, message: error.message, mutates: false });
    }
  }
  return json(response, 404, { error: 'not found' });
}

const mime = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8', '.svg': 'image/svg+xml' };
const server = http.createServer(async (request, response) => {
  try {
    const url = new URL(request.url, 'http://127.0.0.1');
    if (url.pathname.startsWith('/api/')) return await api(request, response, url);
    const relative = url.pathname === '/' ? 'index.html' : url.pathname.slice(1);
    if (relative.includes('..')) return json(response, 400, { error: 'invalid path' });
    const content = await readFile(join(publicRoot, relative));
    response.writeHead(200, {
      'content-type': mime[extname(relative)] || 'application/octet-stream',
      'cache-control': 'no-store',
      'content-security-policy': "default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self'; img-src 'self' data:; frame-ancestors 'none'",
      'x-content-type-options': 'nosniff',
      'x-frame-options': 'DENY'
    });
    response.end(content);
  } catch (error) {
    if (error.code === 'ENOENT') return json(response, 404, { error: 'not found' });
    json(response, 500, { error: error.message });
  }
});

server.listen(listenPort, '127.0.0.1', () => {
  const { port } = server.address();
  const url = `http://127.0.0.1:${port}/?token=${token}`;
  process.stdout.write(`SPACEWRIGHT_CONFIGURATOR_URL=${url}\n`);
  if (!process.argv.includes('--no-open')) execFile('open', [url], () => {});
});
