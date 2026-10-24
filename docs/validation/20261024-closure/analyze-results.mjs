import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
const out = dirname(fileURLToPath(import.meta.url));
const ndjson = path => readFileSync(path, 'utf8').trim().split('\n').map(JSON.parse);
const describe = directory => {
  const events = ndjson(join(directory, 'controlled-events.ndjson'));
  const samples = events.filter(e => e.event === 'sample').map(e => {
    const mem = readFileSync(join(directory, 'samples', `${e.phase}-${e.cycle}-mem.txt`), 'utf8');
    const native = /^  Native Heap\s+(\d+)\s+\d+\s+\d+\s+\d+\s+\d+\s+(\d+)\s+(\d+)\s+(\d+)/m.exec(mem);
    return { phase: e.phase, cycle: e.cycle, time: e.time, pid: e.pid, isolateId: e.isolateId,
      pssMiB: e.totalPssKb / 1024, dartHeapAfterGCMiB: e.afterGC.heapUsage / 1048576,
      nativePssMiB: Number(native?.[1]) / 1024, nativeAllocatedMiB: Number(native?.[3]) / 1024,
      graphicsMiB: Number(/Graphics:\s+(\d+)/.exec(mem)?.[1]) / 1024,
      routeCount: e.routes.length, thermalStatus: e.thermalStatus,
    };
  });
  return { summary: JSON.parse(readFileSync(join(directory, 'controlled-summary.json'), 'utf8')), samples };
};
const cpu = JSON.parse(readFileSync(join(out, 'random5m/samples/slow-4692-cpu.json'), 'utf8'));
const ticks = new Map();
for (const sample of cpu.samples) for (const index of new Set(sample.stack)) ticks.set(index, (ticks.get(index) ?? 0) + 1);
const hotFunctions = [...ticks].sort((a, b) => b[1] - a[1]).slice(0, 30).map(([index, samples]) => ({
  samples, name: cpu.functions[index].function?.name, owner: cpu.functions[index].function?.owner?.name,
  uri: cpu.functions[index].function?.owner?.library?.uri,
}));
const timeline = JSON.parse(readFileSync(join(out, 'random5m/samples/slow-4692-timeline.json'), 'utf8'));
const stacks = new Map(), spans = [];
for (const event of timeline.traceEvents) {
  const stack = stacks.get(event.tid) ?? []; stacks.set(event.tid, stack);
  if (event.ph === 'B') stack.push(event);
  if (event.ph === 'E') {
    const begin = stack.pop();
    if (begin) spans.push({ name: begin.name, ms: (event.ts - begin.ts) / 1000 });
  }
}
writeFileSync(join(out, 'analysis.json'), JSON.stringify({
  fixed: describe(out), random: describe(join(out, 'random5m')),
  slowFrame: { number: 4692, sampleCount: cpu.sampleCount, hotFunctions, longestSpans: spans.sort((a, b) => b.ms - a.ms).slice(0, 20) },
}, null, 2));
