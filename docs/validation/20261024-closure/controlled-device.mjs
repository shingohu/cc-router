import { execFile, spawn } from 'node:child_process';
import { promisify } from 'node:util';
import { readFileSync, writeFileSync, appendFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';

// Fixed, same-engine UI workload, not a replacement for the earlier 30m Monkey.
const exec = promisify(execFile);
const serial = 'UJN0221619023373', pkg = 'dev.ccrouter.demo';
const base = dirname(fileURLToPath(import.meta.url));
const randomMode = process.argv.includes('--monkey');
const out = randomMode ? join(base, 'random5m') : base;
const repo = join(base, '../../..');
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const adb = async (...args) => (await exec('adb', ['-s', serial, ...args], {
  timeout: 25000, maxBuffer: 32 * 1024 * 1024,
})).stdout;
const shell = command => adb('shell', command);
const record = (event, data = {}) => {
  const item = { time: new Date().toISOString(), event, ...data };
  appendFileSync(join(out, 'controlled-events.ndjson'), JSON.stringify(item) + '\n');
  console.log(JSON.stringify(item));
};
const save = (name, value) => writeFileSync(join(out, name), typeof value === 'string' ? value : JSON.stringify(value));
let vm, port, logcat, monkey, monkeyPid, isolateId, pid, baseline, next = 0, frameCount = 0;
let activeCapture;
const pending = new Map(), captures = [], frames = [];
mkdirSync(join(out, 'samples'), { recursive: true });
const rpc = (method, params = {}) => new Promise((resolve, reject) => {
  const id = String(++next);
  const timer = setTimeout(() => { pending.delete(id); reject(new Error(`timeout: ${method}`)); }, 15000);
  pending.set(id, { resolve, reject, timer });
  vm.send(JSON.stringify({ jsonrpc: '2.0', id, method, params }));
});
async function slowFrame(frame) {
  if (captures.length >= 8 || activeCapture) return;
  const capture = (async () => {
    const range = { timeOriginMicros: Math.max(0, frame.startTime - 20000), timeExtentMicros: frame.elapsed + 40000 };
    const timeline = await rpc('getVMTimeline', range);
    const cpu = await rpc('getCpuSamples', { isolateId, ...range });
    save(`samples/slow-${frame.number}-timeline.json`, timeline);
    save(`samples/slow-${frame.number}-cpu.json`, cpu);
    record('slow_frame', { frame, timelineEvents: timeline.traceEvents?.length, cpuSamples: cpu.sampleCount });
  })().catch(error => record('capture_error', { message: error.message }));
  captures.push(capture);
  activeCapture = capture;
  await capture;
  activeCapture = undefined;
}
async function snapshot() {
  const data = await rpc('ext.ccrouter.snapshot', { isolateId });
  return data.runtime.entries.filter(entry => entry.kind === 'route');
}
async function click(label) {
  await shell('uiautomator dump /data/local/tmp/ccrouter-controlled-ui.xml');
  const xml = await shell('cat /data/local/tmp/ccrouter-controlled-ui.xml');
  const tag = [...xml.matchAll(/<node\b[^>]*>/g)].map(match => match[0]).find(tag =>
    tag.includes(`content-desc="${label}`) && tag.includes('clickable="true"'));
  const bounds = /bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"/.exec(tag ?? '');
  if (!bounds) throw new Error(`UI target unavailable: ${label}`);
  const [, x1, y1, x2, y2] = bounds.map(Number);
  const point = [Math.floor((x1 + x2) / 2), Math.floor((y1 + y2) / 2)];
  await adb('shell', 'input', 'tap', ...point.map(String));
  return point;
}
async function screenshot(name) {
  const result = await exec('adb', ['-s', serial, 'exec-out', 'screencap', '-p'], {
    encoding: 'buffer', timeout: 20000, maxBuffer: 10 * 1024 * 1024,
  });
  writeFileSync(join(out, name), result.stdout);
}
async function sample(phase, cycle) {
  const currentVM = await rpc('getVM');
  const currentPid = (await shell(`pidof ${pkg}`)).trim();
  if (currentPid !== pid || !currentVM.isolates.some(i => i.id === isolateId)) {
    throw new Error('Process/isolate changed; same-engine run invalid');
  }
  const routes = await snapshot();
  if (!randomMode && (routes.length !== baseline.length || routes[0].id !== baseline[0].id)) {
    throw new Error('Managed root identity or settled stack changed');
  }
  const memoryBeforeGC = await rpc('getMemoryUsage', { isolateId });
  const systemIsolates = [];
  for (const isolate of currentVM.systemIsolates ?? []) {
    try { systemIsolates.push({ id: isolate.id, name: isolate.name, memory: await rpc('getMemoryUsage', { isolateId: isolate.id }) }); }
    catch (error) { systemIsolates.push({ id: isolate.id, name: isolate.name, error: error.message }); }
  }
  const allocation = await rpc('getAllocationProfile', { isolateId, gc: true });
  const afterGC = allocation.memoryUsage;
  save(`samples/${phase}-${cycle}-allocations.json`, allocation.members.map(member => ({
    name: member.class?.name, instancesCurrent: member.instancesCurrent, bytesCurrent: member.bytesCurrent,
  })).filter(member => member.instancesCurrent > 0));
  const memory = await shell(`dumpsys meminfo ${pkg}`);
  const thermal = await shell('dumpsys thermalservice');
  const activity = await shell('dumpsys activity activities');
  const cpu = await shell(`top -b -n 1 -p ${pid}`);
  save(`samples/${phase}-${cycle}-mem.txt`, memory);
  save(`samples/${phase}-${cycle}-thermal.txt`, thermal);
  save(`samples/${phase}-${cycle}-activity.txt`, activity);
  save(`samples/${phase}-${cycle}-cpu.txt`, cpu);
  record('sample', { phase, cycle, pid, isolateId, systemIsolates, frames: frameCount, routes, memoryBeforeGC, afterGC,
    totalPssKb: Number(/TOTAL PSS:\s+(\d+)/.exec(memory)?.[1]),
    thermalStatus: Number(/Thermal Status:\s+(\d+)/.exec(thermal)?.[1]),
    resumedActivity: activity.split('\n').filter(line => /mResumedActivity|topResumedActivity/.test(line)),
  });
}

try {
  pid = (await shell(`pidof ${pkg}`)).trim();
  if (!/^\d+$/.test(pid)) throw new Error('Expected one running Demo process');
  if ((await shell('ps -A')).split('\n').some(line => /\bscreenrecord\b|com\.huawei\.screenrecorder/.test(line))) {
    throw new Error('System screen recording present; stop before a controlled run');
  }
  const startup = await adb('logcat', '-d', `--pid=${pid}`, '-v', 'brief');
  const service = /Dart VM service is listening on (http:\/\/127\.0\.0\.1:\d+\/[^\s]*)/.exec(startup)?.[1];
  if (!service) throw new Error('No VM URL for current process');
  const url = new URL(service);
  port = (await adb('forward', 'tcp:0', `tcp:${url.port}`)).trim();
  vm = new WebSocket(`ws://127.0.0.1:${port}${url.pathname}ws`);
  vm.addEventListener('message', e => {
    const message = JSON.parse(e.data), entry = pending.get(message.id);
    if (entry) {
      pending.delete(message.id); clearTimeout(entry.timer);
      message.error ? entry.reject(new Error(JSON.stringify(message.error))) : entry.resolve(message.result);
    } else if (message.method === 'streamNotify') {
      const event = message.params.event;
      if (event.extensionKind === 'Flutter.Frame') {
        const frame = event.extensionData;
        frames.push(frame); frameCount++;
        appendFileSync(join(out, 'controlled-frames.ndjson'), JSON.stringify(frame) + '\n');
        if (frame.build > 100000 || frame.raster > 100000) void slowFrame(frame);
      }
      if (event.kind === 'IsolateExit') record('isolate_exit', { id: event.isolate?.id });
    }
  });
  await new Promise((resolve, reject) => {
    vm.addEventListener('open', resolve, { once: true }); vm.addEventListener('error', reject, { once: true });
  });
  isolateId = (await rpc('getVM')).isolates.find(i => i.name === 'main').id;
  record('profiler', { flags: (await rpc('getFlagList')).flags.filter(flag =>
    /profiler|profile_period|timeline_recorder/.test(flag.name)) });
  const clock = await rpc('getVMTimelineMicros');
  const profiler = await rpc('getCpuSamples', { isolateId, timeOriginMicros: Math.max(0, clock.timestamp - 1000000), timeExtentMicros: 1000000 });
  record('profiler_probe', { samples: profiler.sampleCount });
  await rpc('setVMTimelineFlags', { recordedStreams: ['Dart', 'Embedder', 'GC'] });
  record('timeline_flags', { result: await rpc('getVMTimelineFlags') });
  await rpc('streamListen', { streamId: 'Extension' });
  await rpc('streamListen', { streamId: 'Isolate' });
  logcat = spawn('adb', ['-s', serial, 'logcat', `--pid=${pid}`, '-T', '1', '-v', 'threadtime']);
  logcat.stdout.on('data', data => appendFileSync(join(out, 'controlled-logcat.log'), data));
  baseline = await snapshot();
  save('controlled-baseline-routes.json', baseline);
  if (baseline.length !== 1) throw new Error('Start on exactly one Managed home route');
  const apk = readFileSync(join(repo, 'demo/build/app/outputs/flutter-apk/app-profile.apk'));
  save('controlled-config.json', { serial, pkg, pid, isolateId, cyclesPerScenario: randomMode ? null : 120,
    randomMode, seed: randomMode ? 20261024 : null, durationMs: randomMode ? 300000 : null,
    apkSha256: createHash('sha256').update(apk).digest('hex'),
    startedAt: new Date().toISOString(), profiler: true, timeline: ['Dart', 'Embedder', 'GC'],
    note: 'GC at baseline and each 20-cycle settled checkpoint; profiling overhead enabled throughout',
  });
  await sample('baseline', 0);
  if (randomMode) {
    // Omit app switches/system keys to isolate one live engine; this differs from the 30m run.
    const args = ['-p', pkg, '-s', '20261024', '--throttle', '200', '--pct-touch', '45', '--pct-motion', '25',
      '--pct-pinchzoom', '5', '--pct-majornav', '20', '--pct-nav', '5', '--pct-appswitch', '0',
      '--pct-syskeys', '0', '--pct-trackball', '0', '--pct-flip', '0', '--pct-anyevent', '0', '--pct-permission', '0',
      '--ignore-crashes', '--ignore-timeouts', '--ignore-security-exceptions', '--monitor-native-crashes', '-v', '-v', '1000000'];
    save('monkey-args.json', args);
    monkey = spawn('adb', ['-s', serial, 'shell', `echo CCROUTER_PID=$$; exec monkey ${args.join(' ')}`]);
    let prefix = '', exited = false;
    monkey.stdout.on('data', data => {
      appendFileSync(join(out, 'monkey.log'), data); prefix = (prefix + data).slice(-4000);
      monkeyPid ??= /CCROUTER_PID=(\d+)/.exec(prefix)?.[1];
    });
    monkey.stderr.on('data', data => appendFileSync(join(out, 'monkey.log'), data));
    monkey.on('exit', () => { exited = true; });
    const started = performance.now();
    record('random_started', { durationMs: 300000 });
    for (let tick = 1; tick <= 10; tick++) {
      await sleep(Math.max(0, started + tick * 30000 - performance.now()));
      if (exited) throw new Error('Monkey exited before deadline');
      if (tick === 10 && monkeyPid) {
        await shell(`kill -TERM ${monkeyPid}`); monkeyPid = undefined; monkey.kill('SIGTERM');
      }
      await sample('random', tick * 30);
    }
    record('random_completed', { elapsedMs: performance.now() - started });
  } else {
  for (const scenario of [
    { phase: 'typed-detail', tab: '导航&#10;', button: 'Push + typed result', route: 'demo_navigation_lab.detail' },
    { phase: 'cupertino', tab: '展示&#10;', button: 'Cupertino PageRoute', route: 'demo_navigation_lab.presentation.cupertino' },
  ]) {
    await click(scenario.tab); await sleep(500);
    const point = await click(scenario.button);
    for (let cycle = 1; cycle <= 120; cycle++) {
      if (cycle > 1) await adb('shell', 'input', 'tap', ...point.map(String));
      await sleep(550);
      const opened = await snapshot();
      if (opened.length !== baseline.length + 1 || !opened.some(e => e.routeId === scenario.route)) {
        throw new Error(`Unexpected opened stack at ${scenario.phase}/${cycle}: ${JSON.stringify(opened)}`);
      }
      if (cycle === 1) await screenshot(`${scenario.phase}-opened.png`);
      await adb('shell', 'input', 'keyevent', '4');
      await sleep(550);
      const closed = await snapshot();
      if (closed.length !== baseline.length || closed[0].id !== baseline[0].id) {
        throw new Error(`Unexpected returned stack at ${scenario.phase}/${cycle}`);
      }
      if (cycle % 20 === 0) { await sleep(1500); await sample(scenario.phase, cycle); }
    }
  }
  }
  await sleep(30000); await sample('idle-30s', 240);
  await sleep(30000); await sample('idle-60s', 240);
  await screenshot('controlled-final.png');
  await Promise.all(captures);
  const stats = key => {
    const sorted = frames.map(f => f[key] / 1000).sort((a, b) => a - b);
    return { count: sorted.length, p50Ms: sorted[Math.floor(sorted.length * .5)], p95Ms: sorted[Math.floor(sorted.length * .95)], maxMs: sorted.at(-1), over100ms: sorted.filter(x => x > 100).length };
  };
  save('controlled-summary.json', { completed: true, cycles: randomMode ? null : 240, randomMode, pid, isolateId, build: stats('build'), raster: stats('raster'), endedAt: new Date().toISOString() });
  record('completed', { cycles: randomMode ? null : 240, frames: frameCount });
} catch (error) {
  record('failed', { message: error.stack }); process.exitCode = 1;
} finally {
  await Promise.all(captures);
  if (monkeyPid) await shell(`kill -TERM ${monkeyPid}`);
  monkey?.kill('SIGTERM');
  logcat?.kill('SIGTERM'); vm?.close();
  for (const entry of pending.values()) clearTimeout(entry.timer);
  if (port) await adb('forward', '--remove', `tcp:${port}`);
}
