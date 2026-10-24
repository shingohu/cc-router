import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const out = dirname(fileURLToPath(import.meta.url));
function text(name) { return existsSync(join(out, name)) ? readFileSync(join(out, name), 'utf8') : ''; }
function rows(name) { return text(name).split('\n').filter(Boolean).flatMap(line => { try { return [JSON.parse(line)]; } catch { return []; } }); }
function stats(values) {
  values = values.filter(Number.isFinite).sort((a, b) => a - b);
  if (!values.length) return null;
  const q = p => values[Math.min(values.length - 1, Math.ceil(values.length * p) - 1)];
  return { count: values.length, min: values[0], mean: values.reduce((a, b) => a + b, 0) / values.length, p50: q(.5), p90: q(.9), p95: q(.95), p99: q(.99), max: values.at(-1) };
}
function slope(points) {
  if (points.length < 3) return null;
  const xs = points.map(p => p[0]), ys = points.map(p => p[1]);
  const x = xs.reduce((a, b) => a + b) / points.length, y = ys.reduce((a, b) => a + b) / points.length;
  return xs.reduce((sum, value, i) => sum + (value - x) * (ys[i] - y), 0) / xs.reduce((sum, value) => sum + (value - x) ** 2, 0);
}
const metrics = rows('metrics.ndjson'), heaps = rows('dart-memory-cpu.ndjson'), frames = rows('flutter-frames.ndjson'), events = rows('events.ndjson');
const start = events.find(e => e.event === 'timed_monkey_started');
const end = events.find(e => e.event === 'monkey_deadline');
const endMs = end ? Date.parse(end.time) : Infinity;
const monkeyMetrics = metrics.filter(m => m.phase === 'monkey');
const framesTimed = frames.filter(f => Date.parse(f.observedAt) >= Date.parse(start?.time) && Date.parse(f.observedAt) <= endMs);
const cpu = heaps.filter(h => h.elapsedSeconds <= 1800).map(h => Number(h.cpuTopLastLine?.trim().split(/\s+/)[8]));
const heapPoints = heaps.filter(h => h.elapsedSeconds <= 1800 && h.isolates?.[0]?.memoryUsage).map(h => [h.elapsedSeconds / 60, h.isolates[0].memoryUsage.heapUsage / 1048576]);
const monkey = text('monkey.log'), logcat = text('logcat.log');
const count = regex => [...monkey.matchAll(regex)].length;
const isolateIds = [...new Set(heaps.filter(h => h.elapsedSeconds <= 1800).flatMap(h => h.isolates?.map(i => i.id) ?? []))];
const isolateSegments = isolateIds.map(id => {
  const group = heaps.filter(h => h.elapsedSeconds <= 1800 && h.isolates?.some(i => i.id === id));
  const memory = monkeyMetrics.filter(m => m.dart?.some(i => i.id === id));
  return { id, firstHeapSampleSeconds: group[0]?.elapsedSeconds, lastHeapSampleSeconds: group.at(-1)?.elapsedSeconds,
    heapMiB: stats(group.map(h => h.isolates.find(i => i.id === id).memoryUsage.heapUsage / 1048576)),
    pssMiB: stats(memory.map(m => m.totalPssKb / 1024)) };
});
const recordingStartMs = Date.parse('2026-10-24T04:43:02.194Z');
const environmentSegments = [false, true].map(recording => {
  const selectedFrames = framesTimed.filter(f => (Date.parse(f.observedAt) >= recordingStartMs) === recording);
  const selectedMemory = monkeyMetrics.filter(m => (Date.parse(m.time) >= recordingStartMs) === recording);
  return { label: recording ? 'after-system-screen-recording-start' : 'before-system-screen-recording-start',
    frameCount: selectedFrames.length, buildMs: stats(selectedFrames.map(f => f.build / 1000)),
    rasterMs: stats(selectedFrames.map(f => f.raster / 1000)),
    buildOrRasterOver16_667ms: selectedFrames.filter(f => f.build > 1000000 / 60 || f.raster > 1000000 / 60).length,
    pssMiB: stats(selectedMemory.map(m => m.totalPssKb / 1024)) };
});
const summary = {
  recordedAt: new Date().toISOString(), start, end,
  latest: metrics.at(-1), samples: metrics.length,
  uniquePids: [...new Set(metrics.map(m => m.pid))],
  isolateSegments,
  environmentSegments,
  pssMiB: stats(monkeyMetrics.map(m => m.totalPssKb / 1024)),
  pssSlopeAfter5MinutesMiBPerMinute: slope(monkeyMetrics.filter(m => m.elapsedSeconds >= 300).map(m => [m.elapsedSeconds / 60, m.totalPssKb / 1024])),
  dartHeapMiB: stats(heapPoints.map(p => p[1])),
  dartHeapSlopeAfter5MinutesMiBPerMinute: slope(heapPoints.filter(p => p[0] >= 5)),
  cpuOneSecondPercentOfOneCore: stats(cpu),
  batteryTemperatureC: stats(monkeyMetrics.map(m => m.batteryTemperature)),
  frames: {
    count: framesTimed.length, buildMs: stats(framesTimed.map(f => f.build / 1000)), rasterMs: stats(framesTimed.map(f => f.raster / 1000)), totalSpanMs: stats(framesTimed.map(f => f.elapsed / 1000)),
    buildOrRasterOver16_667ms: framesTimed.filter(f => f.build > 1000000 / 60 || f.raster > 1000000 / 60).length,
    buildOrRasterOver33_333ms: framesTimed.filter(f => f.build > 1000000 / 30 || f.raster > 1000000 / 30).length,
  },
  monkeyLogEvents: { touch: count(/^:Sending Touch/gm), key: count(/^:Sending Key/gm), switch: count(/^:Switch:/gm), throttle: count(/^Sleeping for 200 milliseconds/gm), periodicCounters: [...monkey.matchAll(/Sending event #(\d+)/g)].map(m => Number(m[1])).slice(-3) },
  crashOrANRLines: monkey.split('\n').filter(line => /CRASH:|NOT RESPONDING|ANR in|Native crash|INJECT_EVENTS|Permission Denial|SecurityException/.test(line)),
  flutterErrorLines: logcat.split('\n').filter(line => /\bE flutter\s*:|Unhandled Exception|EXCEPTION CAUGHT|FATAL EXCEPTION|ANR in dev\.ccrouter/.test(line)),
  recorderErrors: events.filter(e => /error|premature|identity_changed/.test(e.event)),
};
writeFileSync(join(out, 'summary.json'), JSON.stringify(summary, null, 2));
console.log(JSON.stringify(summary, null, 2));
