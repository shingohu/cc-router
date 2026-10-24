import { readFileSync, appendFileSync, writeFileSync } from 'node:fs';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

// The first live recorder queried getIsolate, whose payload omits memoryUsage.
// This companion fills the current run with getMemoryUsage and 1s CPU samples.
// The main recorder is corrected for subsequent runs; neither sampler forces GC.
const out = dirname(fileURLToPath(import.meta.url));
const eventsPath = join(out, 'events.ndjson');
const exec = promisify(execFile);
const events = readFileSync(eventsPath, 'utf8').trim().split('\n').map(JSON.parse);
const port = events.find(e => e.event === 'vm_connected').port;
const startedAt = Date.parse(events.find(e => e.event === 'timed_monkey_started').time);
const log = readFileSync(join(out, 'logcat.log'), 'utf8');
const matches = [...log.matchAll(/Dart VM service is listening on (http:\/\/127\.0\.0\.1:\d+\/[^\s]*)/g)];
const service = new URL(matches.at(-1)[1]);
const vm = new WebSocket(`ws://127.0.0.1:${port}${service.pathname}ws`);
let next = 0;
const pending = new Map();
vm.addEventListener('message', e => {
  const message = JSON.parse(e.data), entry = pending.get(message.id);
  if (!entry) return;
  pending.delete(message.id); clearTimeout(entry.timer);
  message.error ? entry.reject(new Error(JSON.stringify(message.error))) : entry.resolve(message.result);
});
await new Promise((resolve, reject) => { vm.addEventListener('open', resolve, { once: true }); vm.addEventListener('error', reject, { once: true }); });
function rpc(method, params = {}) {
  return new Promise((resolve, reject) => {
    const id = String(++next), timer = setTimeout(() => { pending.delete(id); reject(new Error('VM timeout')); }, 8000);
    pending.set(id, { resolve, reject, timer });
    vm.send(JSON.stringify({ jsonrpc: '2.0', id, method, params }));
  });
}
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
let index = 0;
try {
  while (Date.now() - startedAt < 35 * 60 * 1000) {
    if (readFileSync(eventsPath, 'utf8').includes('recorder_cleanup_complete')) break;
    const entry = { time: new Date().toISOString(), elapsedSeconds: Math.round((Date.now() - startedAt) / 1000) };
    try {
      const info = await rpc('getVM');
      entry.isolates = await Promise.all(info.isolates.map(async isolate => ({ id: isolate.id, name: isolate.name, memoryUsage: await rpc('getMemoryUsage', { isolateId: isolate.id }) })));
    } catch (e) { entry.vmError = e.message; }
    try {
      const pid = (await exec('adb', ['-s', 'UJN0221619023373', 'shell', 'pidof dev.ccrouter.demo'], { timeout: 10000 })).stdout.trim();
      if (!/^\d+$/.test(pid)) throw new Error('Unexpected PID: ' + pid);
      const top = await exec('adb', ['-s', 'UJN0221619023373', 'shell', `top -b -n 2 -d 1 -p ${pid}`], { timeout: 15000, maxBuffer: 1024 * 1024 });
      writeFileSync(join(out, 'samples', `cpu-top-${String(index).padStart(3, '0')}.txt`), top.stdout + top.stderr);
      const lines = top.stdout.split('\n').filter(line => new RegExp(`^\\s*${pid}\\s`).test(line));
      entry.cpuTopLastLine = lines.at(-1);
    } catch (e) { entry.cpuError = e.message; }
    appendFileSync(join(out, 'dart-memory-cpu.ndjson'), JSON.stringify(entry) + '\n');
    console.log(JSON.stringify(entry)); index++;
    await sleep(30000);
  }
} finally {
  vm.close();
  for (const entry of pending.values()) clearTimeout(entry.timer);
}
