import { readFileSync, writeFileSync, appendFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const out = dirname(fileURLToPath(import.meta.url));
const eventsPath = join(out, 'events.ndjson');
const port = readFileSync(eventsPath, 'utf8').trim().split('\n').map(JSON.parse).find(e => e.event === 'vm_connected').port;
const source = readFileSync(join(out, 'logcat.log'), 'utf8');
const service = new URL([...source.matchAll(/Dart VM service is listening on (http:\/\/127\.0\.0\.1:\d+\/[^\s]*)/g)].at(-1)[1]);
const vm = new WebSocket(`ws://127.0.0.1:${port}${service.pathname}ws`);
const pending = new Map();
let next = 0, captured = 0, busy = false, isolateId;
const already = new Set();
function rpc(method, params = {}) {
  return new Promise((resolve, reject) => {
    const id = String(++next), timer = setTimeout(() => { pending.delete(id); reject(new Error('timeout: ' + method)); }, 15000);
    pending.set(id, { resolve, reject, timer });
    vm.send(JSON.stringify({ jsonrpc: '2.0', id, method, params }));
  });
}
function record(value) { appendFileSync(join(out, 'slow-frame-capture.ndjson'), JSON.stringify({ time: new Date().toISOString(), ...value }) + '\n'); }
async function capture(frame) {
  if (busy || captured >= 10 || already.has(frame.number)) return;
  busy = true; captured++; already.add(frame.number);
  try {
    const params = { timeOriginMicros: Math.max(0, frame.startTime - 10000), timeExtentMicros: frame.elapsed + 20000 };
    const timeline = await rpc('getVMTimeline', params);
    writeFileSync(join(out, `slow-frame-${frame.number}-timeline.json`), JSON.stringify(timeline));
    let samples;
    try {
      samples = await rpc('getCpuSamples', { isolateId, ...params });
      writeFileSync(join(out, `slow-frame-${frame.number}-cpu.json`), JSON.stringify(samples));
    } catch (e) { record({ frame, cpuError: e.message }); }
    record({ frame, timelineEvents: timeline.traceEvents?.length, cpuSamples: samples?.sampleCount });
  } catch (e) { record({ frame, error: e.message }); }
  finally { busy = false; }
}
vm.addEventListener('message', e => {
  const message = JSON.parse(e.data), entry = pending.get(message.id);
  if (entry) {
    pending.delete(message.id); clearTimeout(entry.timer);
    message.error ? entry.reject(new Error(JSON.stringify(message.error))) : entry.resolve(message.result);
  } else if (message.method === 'streamNotify' && message.params.event.extensionKind === 'Flutter.Frame') {
    const frame = message.params.event.extensionData;
    if (frame.build > 100000 || frame.raster > 100000) void capture(frame);
  }
});
await new Promise((resolve, reject) => { vm.addEventListener('open', resolve, { once: true }); vm.addEventListener('error', reject, { once: true }); });
isolateId = (await rpc('getVM')).isolates.find(i => i.name === 'main').id;
record({ method: 'getVMTimelineFlags', result: await rpc('getVMTimelineFlags') });
// Try the existing profiler ring for the early long frame; do not enable or
// clear timeline/profiler streams in the middle of the timed workload.
const prior = readFileSync(join(out, 'flutter-frames.ndjson'), 'utf8').trim().split('\n').map(JSON.parse).filter(f => f.build > 100000 || f.raster > 100000);
for (const frame of prior) await capture(frame);
await rpc('streamListen', { streamId: 'Extension' });
await new Promise(resolve => {
  const timer = setInterval(() => {
    if (readFileSync(eventsPath, 'utf8').includes('recorder_cleanup_complete')) { clearInterval(timer); resolve(); }
  }, 5000);
  vm.addEventListener('close', () => { clearInterval(timer); resolve(); }, { once: true });
});
vm.close();
for (const entry of pending.values()) clearTimeout(entry.timer);
