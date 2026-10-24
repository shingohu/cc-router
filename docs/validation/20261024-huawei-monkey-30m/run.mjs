import { spawn, execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdirSync, writeFileSync, appendFileSync, createWriteStream, readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';

const exec = promisify(execFile);
const out = dirname(fileURLToPath(import.meta.url));
const repo = join(out, '../../..');
const serial = 'UJN0221619023373';
const pkg = 'dev.ccrouter.demo';
const seed = 20261024;
const durationMs = 30 * 60 * 1000;
const sampleMs = 30000;
const adb = ['-s', serial];
mkdirSync(join(out, 'samples'), { recursive: true });
mkdirSync(join(out, 'screenshots'), { recursive: true });
const iso = () => new Date().toISOString();
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
function record(event, data = {}) {
  const entry = { time: iso(), event, ...data };
  appendFileSync(join(out, 'events.ndjson'), JSON.stringify(entry) + '\n');
  console.log(JSON.stringify(entry));
}
async function run(args, timeout = 20000) {
  try {
    const result = await exec('adb', [...adb, ...args], { timeout, maxBuffer: 16 * 1024 * 1024 });
    return result.stdout + (result.stderr ? '\nSTDERR:\n' + result.stderr : '');
  } catch (e) { return `COMMAND_ERROR: ${e.message}\n${e.stdout ?? ''}\n${e.stderr ?? ''}`; }
}
const shell = command => run(['shell', command]);
async function save(name, args) {
  const text = await run(args);
  writeFileSync(join(out, name), text);
  return text;
}
async function screenshot(name) {
  try {
    const result = await exec('adb', [...adb, 'exec-out', 'screencap', '-p'], { encoding: 'buffer', timeout: 20000, maxBuffer: 12 * 1024 * 1024 });
    writeFileSync(join(out, 'screenshots', name + '.png'), result.stdout);
  } catch (e) { record('screenshot_error', { message: e.message }); }
}

let serviceUrl, vm, vmReady = false, vmNext = 0, forwards = [];
const vmPending = new Map();
let frameCount = 0;
const frameStream = createWriteStream(join(out, 'flutter-frames.ndjson'));
function rpc(method, params = {}) {
  return new Promise((resolve, reject) => {
    if (!vm || vm.readyState !== WebSocket.OPEN) return reject(new Error('VM disconnected'));
    const id = String(++vmNext);
    const timer = setTimeout(() => { vmPending.delete(id); reject(new Error('VM timeout: ' + method)); }, 8000);
    vmPending.set(id, { resolve, reject, timer });
    vm.send(JSON.stringify({ jsonrpc: '2.0', id, method, params }));
  });
}
async function connectVM() {
  if (!serviceUrl || vmReady) return;
  const remote = new URL(serviceUrl);
  const localPort = (await run(['forward', 'tcp:0', `tcp:${remote.port}`])).trim();
  if (!/^\d+$/.test(localPort)) throw new Error('adb forward failed: ' + localPort);
  forwards.push(localPort);
  const address = `ws://127.0.0.1:${localPort}${remote.pathname.endsWith('/') ? remote.pathname : remote.pathname + '/'}ws`;
  vm = new WebSocket(address);
  vm.addEventListener('message', e => {
    const message = JSON.parse(e.data);
    if (message.id && vmPending.has(message.id)) {
      const entry = vmPending.get(message.id); vmPending.delete(message.id); clearTimeout(entry.timer);
      message.error ? entry.reject(new Error(JSON.stringify(message.error))) : entry.resolve(message.result);
    } else if (message.method === 'streamNotify') {
      const event = message.params.event;
      if (event.extensionKind === 'Flutter.Frame') {
        frameCount++;
        frameStream.write(JSON.stringify({ observedAt: iso(), ...event.extensionData }) + '\n');
      }
      if (event.kind === 'IsolateExit') record('isolate_exit', { isolate: event.isolate?.id });
    }
  });
  await Promise.race([
    new Promise((resolve, reject) => { vm.addEventListener('open', resolve, { once: true }); vm.addEventListener('error', reject, { once: true }); }),
    sleep(10000).then(() => { throw new Error('VM socket open timeout'); }),
  ]);
  await rpc('streamListen', { streamId: 'Extension' });
  await rpc('streamListen', { streamId: 'Isolate' });
  vmReady = true;
  record('vm_connected', { port: localPort });
}
async function dartMemory(gc = false) {
  if (!vmReady) return null;
  const info = await rpc('getVM');
  const result = [];
  for (const isolate of info.isolates ?? []) {
    const memory = gc
      ? (await rpc('getAllocationProfile', { isolateId: isolate.id, gc: true })).memoryUsage
      : await rpc('getMemoryUsage', { isolateId: isolate.id });
    result.push({ id: isolate.id, name: isolate.name, memoryUsage: memory });
  }
  return result;
}

const logFile = createWriteStream(join(out, 'logcat.log'));
const logcat = spawn('adb', [...adb, 'logcat', '-v', 'threadtime', '-T', '1', 'flutter:V', 'AndroidRuntime:E', 'ActivityManager:I', 'ActivityTaskManager:I', 'libc:F', 'DEBUG:F', 'OpenGLRenderer:W', 'Choreographer:I', '*:S']);
let logTail = '';
logcat.stdout.on('data', data => {
  logFile.write(data); logTail = (logTail + data.toString()).slice(-16000);
  const matches = [...logTail.matchAll(/Dart VM service is listening on (http:\/\/127\.0\.0\.1:\d+\/[^\s]*)/g)];
  if (matches.length) serviceUrl = matches.at(-1)[1];
});
logcat.stderr.on('data', data => logFile.write(data));
let monkey, remotePid, sampleIndex = 0, start, initialPid;
async function sample(phase) {
  const n = String(sampleIndex++).padStart(3, '0');
  const elapsed = start === undefined ? 0 : Math.round((performance.now() - start) / 1000);
  const [pid, mem, cpu, focus, battery, gfx] = await Promise.all([
    shell(`pidof ${pkg}`), shell(`dumpsys meminfo ${pkg}`),
    shell(`dumpsys cpuinfo | grep -E '${pkg}|TOTAL:'`),
    shell("dumpsys activity activities | grep -E 'mResumedActivity|topResumedActivity'"),
    shell('dumpsys battery'), shell(`dumpsys gfxinfo ${pkg} framestats`),
  ]);
  const prefix = join(out, 'samples', `${n}-${phase}`);
  for (const [key, value] of Object.entries({ pid, mem, cpu, focus, battery, gfx })) writeFileSync(`${prefix}-${key}.txt`, value);
  let memory = null;
  try { memory = await dartMemory(); } catch (e) { record('vm_sample_error', { message: e.message }); }
  const totalPssKb = Number(/TOTAL PSS:\s+(\d+)/.exec(mem)?.[1] ?? /^\s*TOTAL\s+(\d+)/m.exec(mem)?.[1] ?? NaN);
  const totalRssKb = Number(/TOTAL RSS:\s+(\d+)/.exec(mem)?.[1] ?? NaN);
  const entry = { time: iso(), phase, sample: Number(n), elapsedSeconds: elapsed, pid: pid.trim(), totalPssKb, totalRssKb, dart: memory, flutterFrames: frameCount, foreground: focus.trim(), batteryTemperature: Number(/temperature:\s+(\d+)/.exec(battery)?.[1] ?? NaN) / 10 };
  appendFileSync(join(out, 'metrics.ndjson'), JSON.stringify(entry) + '\n');
  record('sample', { sample: Number(n), phase, elapsedSeconds: elapsed, pid: pid.trim(), totalPssKb, flutterFrames: frameCount });
  if (initialPid && initialPid !== pid.trim()) record('process_identity_changed', { initialPid, currentPid: pid.trim() });
  if (Number(n) % 10 === 0) {
    await screenshot(n + '-' + phase);
    await save(`samples/${n}-thermal.txt`, ['shell', 'dumpsys thermalservice']);
  }
}

try {
  const commit = (await exec('git', ['rev-parse', 'HEAD'], { cwd: repo })).stdout.trim();
  const apk = join(repo, 'demo/build/app/outputs/flutter-apk/app-profile.apk');
  const hash = createHash('sha256').update(readFileSync(apk)).digest('hex');
  writeFileSync(join(out, 'run-config.json'), JSON.stringify({ serial, package: pkg, commit, apkSha256: hash, mode: 'profile', seed, durationMs, sampleMs, throttleMs: 200, startedPreparationAt: iso(), vmFrames: 'Flutter.Frame via Extension stream; no timeline recording' }, null, 2));
  await save('device.txt', ['shell', 'getprop ro.product.manufacturer; getprop ro.product.model; getprop ro.build.version.release; getprop ro.build.version.sdk; getprop ro.build.display.id; wm size; wm density; dumpsys display; dumpsys battery']);
  await save('package.txt', ['shell', `dumpsys package ${pkg}`]);
  await save('launch.txt', ['shell', `am start -W -n ${pkg}/.MainActivity`]);
  await sleep(5000);
  if (!serviceUrl) {
    const startup = await shell(`logcat -d --pid=$(pidof ${pkg}) -v brief`);
    writeFileSync(join(out, 'startup-logcat.txt'), startup);
    serviceUrl = /Dart VM service is listening on (http:\/\/127\.0\.0\.1:\d+\/[^\s]*)/.exec(startup)?.[1];
  }
  if (!serviceUrl) throw new Error('Profile VM service unavailable; abort before timed Monkey.');
  await connectVM();
  initialPid = (await shell(`pidof ${pkg}`)).trim();
  await screenshot('initial');
  writeFileSync(join(out, 'baseline-dart-after-gc.json'), JSON.stringify(await dartMemory(true), null, 2));
  await sample('baseline');
  await shell(`dumpsys gfxinfo ${pkg} reset`);
  const monkeyArgs = ['-p', pkg, '-s', String(seed), '--throttle', '200', '--pct-touch', '45', '--pct-motion', '20', '--pct-pinchzoom', '5', '--pct-majornav', '20', '--pct-nav', '5', '--pct-appswitch', '5', '--pct-syskeys', '0', '--pct-trackball', '0', '--pct-flip', '0', '--pct-anyevent', '0', '--pct-permission', '0', '--ignore-crashes', '--ignore-timeouts', '--ignore-security-exceptions', '--monitor-native-crashes', '--ignore-native-crashes', '-v', '-v', '1000000'];
  writeFileSync(join(out, 'monkey-command.txt'), `adb -s ${serial} shell monkey ${monkeyArgs.join(' ')}\n`);
  const monkeyFile = createWriteStream(join(out, 'monkey.log'));
  monkey = spawn('adb', [...adb, 'shell', `echo CCROUTER_MONKEY_PID=$$; exec monkey ${monkeyArgs.join(' ')}`]);
  let monkeyText = '';
  monkey.stdout.on('data', data => {
    monkeyFile.write(data); monkeyText = (monkeyText + data).slice(-2000);
    remotePid ??= /CCROUTER_MONKEY_PID=(\d+)/.exec(monkeyText)?.[1];
  });
  monkey.stderr.on('data', data => monkeyFile.write(data));
  let monkeyExited = false;
  monkey.on('exit', code => { monkeyExited = true; monkeyFile.end(); record('monkey_exit', { code }); });
  start = performance.now();
  record('timed_monkey_started', { durationSeconds: durationMs / 1000, initialPid, seed, throttleMs: 200 });
  const stopAtDeadline = setTimeout(async () => {
    record('monkey_deadline', { elapsedSeconds: (performance.now() - start) / 1000, remotePid });
    if (remotePid) await shell(`kill -TERM ${remotePid}`);
    remotePid = undefined;
    monkey.kill('SIGTERM');
  }, durationMs);
  for (let tick = 1; tick <= durationMs / sampleMs; tick++) {
    const remaining = start + tick * sampleMs - performance.now();
    if (remaining > 0) await sleep(remaining);
    if (monkeyExited && performance.now() - start < durationMs - 1000) {
      record('premature_monkey_exit', { elapsedSeconds: (performance.now() - start) / 1000 });
      throw new Error('Monkey ended before the requested duration');
    }
    await sample('monkey');
  }
  clearTimeout(stopAtDeadline);
  record('timed_monkey_completed', { elapsedSeconds: (performance.now() - start) / 1000, frameCount });
  await screenshot('after-monkey');
  await save('exit-info.txt', ['shell', `dumpsys activity exit-info ${pkg}`]);
  await save('activity-after.txt', ['shell', `dumpsys activity activities`]);
  await save('meminfo-after.txt', ['shell', `dumpsys meminfo ${pkg}`]);
  await save('gfxinfo-after.txt', ['shell', `dumpsys gfxinfo ${pkg} framestats`]);
  record('cooldown_started', { note: 'Return with Back at most 16 times; no process restart or app-data clearing.' });
  for (let i = 0; i < 16; i++) { await shell('input keyevent 4'); await sleep(150); }
  await shell(`am start -W -n ${pkg}/.MainActivity`);
  await sleep(30000);
  await sample('cooldown-30s');
  writeFileSync(join(out, 'cooldown-dart-after-gc.json'), JSON.stringify(await dartMemory(true), null, 2));
  await sleep(30000);
  await sample('cooldown-60s-after-gc');
  await screenshot('cooldown-final');
  record('run_complete', { frameCount, finalPid: (await shell(`pidof ${pkg}`)).trim() });
} catch (e) {
  record('run_error', { message: e.stack }); process.exitCode = 1;
} finally {
  if (remotePid) await shell(`kill -TERM ${remotePid}`);
  monkey?.kill('SIGTERM');
  vm?.close();
  for (const value of vmPending.values()) clearTimeout(value.timer);
  frameStream.end(); logcat.kill('SIGTERM'); logFile.end();
  for (const port of forwards) await run(['forward', '--remove', `tcp:${port}`]);
  record('recorder_cleanup_complete');
}
