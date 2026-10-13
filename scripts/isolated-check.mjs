#!/usr/bin/env node
// One inherited OS sandbox protects all Fish/Node/install/release descendants.
import { mkdtempSync, mkdirSync, writeFileSync, rmSync, copyFileSync, chmodSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { spawn } from 'node:child_process';
const root = mkdtempSync(join(tmpdir(), 'spacewright-check-'));
const blocked = ['yabai', 'displayplacer', 'open', 'launchctl', 'osascript', 'killall'];
for (const name of ['home', 'config', 'state', 'cache', 'logs', 'bin']) mkdirSync(join(root, name));
for (const name of blocked) writeFileSync(join(root, 'bin', name), '#!/bin/sh\necho "[TEST BLOCKED] $0 $*" >&2\nexit 97\n', { mode: 0o755 });
// macOS forbids setuid executables inside a process sandbox. Preserve real
// process identity/ancestry checks with an unprivileged copy of Apple's ps.
copyFileSync('/bin/ps',join(root,'bin','ps'));chmodSync(join(root,'bin','ps'),0o755);
const env = { ...process.env, HOME: join(root, 'home'), XDG_CONFIG_HOME: join(root, 'config'), XDG_STATE_HOME: join(root, 'state'),
  XDG_CACHE_HOME: join(root, 'cache'), SPACEWRIGHT_CONFIG_ROOT: join(root, 'config'), SPACEWRIGHT_STATE_ROOT: join(root, 'state'),
  SPACEWRIGHT_LOG_ROOT: join(root, 'logs'), PATH: `${join(root, 'bin')}:${process.env.PATH}`, SPACEWRIGHT_TEST_ISOLATED: '1', WORKSPACE_DISABLE_YABAI_AUTO_RESTART: '1' };
for (const key of ['SPACEWRIGHT_EXECUTION_TOKEN', 'SPACEWRIGHT_EXECUTION_RUN_ID', 'SPACEWRIGHT_EXECUTION_ENVELOPE', 'SPACEWRIGHT_EXECUTION_CONFIG', 'SPACEWRIGHT_EXECUTION_DEADLINE_MS', 'SPACEWRIGHT_ROOT', 'SPACEWRIGHT_PACKAGE_ROOT']) delete env[key];
// The allow-default profile still blocks absolute paths and symlink-resolved
// Homebrew binaries; fixtures under temporary directories remain executable.
if (process.platform !== 'darwin') throw new Error('isolated desktop checks require the macOS process sandbox');
const profile = `(version 1)(allow default)(deny appleevent-send)(deny process-exec (require-all (regex #"/(${blocked.join('|')})$") (require-not (subpath "/private/tmp")) (require-not (subpath "/tmp")) (require-not (subpath "/private/var/folders")) (require-not (subpath "/var/folders"))))`;
const args = process.argv.slice(2);
const command = args.length ? args : ['fish', '--no-config', resolve('scripts/check.fish')];
const child = spawn('/usr/bin/sandbox-exec', ['-p', profile, ...command], { env, stdio: 'inherit' });
for (const sig of ['SIGTERM', 'SIGINT']) process.on(sig, () => child.kill(sig));
child.on('error', (error) => { process.stderr.write(`${error.message}\n`); rmSync(root, { recursive: true, force: true }); process.exitCode = 1; });
child.on('close', (code) => { rmSync(root, { recursive: true, force: true }); process.exitCode = code ?? 1; });
