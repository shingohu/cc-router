import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { writeFileSync, mkdirSync } from 'node:fs';
import { resolve, basename, join } from 'node:path';

// Offline evidence tool: no device mutations; inputs are explicit local artifacts.
const exec = promisify(execFile);
const [traceArg, elfArg, outputArg] = process.argv.slice(2);
if (!traceArg || !elfArg || !outputArg) throw new Error('Usage: node symbolize.mjs TRACE UNSTRIPPED_ELF OUTPUT_DIR');
const trace = resolve(traceArg), elf = resolve(elfArg), out = resolve(outputArg);
const llvm = process.env.CCROUTER_LLVM_BIN;
if (!llvm) throw new Error('Set CCROUTER_LLVM_BIN to the NDK LLVM bin directory');
const tp = process.env.CCROUTER_TRACE_PROCESSOR ?? '/tmp/ccrouter-trace-processor-native';
const run = (file, args) => exec(file, args, { maxBuffer: 128 * 1024 * 1024, timeout: 120000 });
const query = async (table, fields, where = '') => {
  const pairs = fields.flatMap(field => [`'${field}'`, field]).join(',');
  const sql = `SELECT hex(json_group_array(json_object(${pairs}))) FROM ${table} ${where};`;
  const { stdout } = await run(tp, ['query', trace, sql]);
  const hex = stdout.split('\n').map(x => x.replace(/^"|"$/g, '').trim()).find(x => /^[0-9a-fA-F]+$/.test(x));
  if (!hex) throw new Error(`No JSON result for ${table}`);
  return JSON.parse(Buffer.from(hex, 'hex').toString('utf8'));
};
const [mappings, frames, callsites, allocations, stats, processRows, clocks] = await Promise.all([
  query('stack_profile_mapping', ['id', 'name', 'build_id']),
  query('stack_profile_frame', ['id', 'name', 'mapping', 'rel_pc']),
  query('stack_profile_callsite', ['id', 'parent_id', 'frame_id']),
  query('heap_profile_allocation', ['ts', 'upid', 'callsite_id', 'size', 'count']),
  query('stats', ['name', 'value', 'severity'], 'WHERE value != 0'),
  query('process', ['upid', 'pid', 'name']),
  query('clock_snapshot', ['ts', 'clock_name', 'clock_value'], "WHERE clock_name = 'REALTIME' LIMIT 1"),
]);
const { stdout: notes } = await run(join(llvm, 'llvm-readelf'), ['-n', elf]);
const buildId = /Build ID:\s*([a-f0-9]+)/i.exec(notes)?.[1];
const matched = mappings.filter(m => m.name.endsWith('libflutter.so'));
if (!buildId || !matched.length || matched.some(m => m.build_id !== buildId)) {
  throw new Error('ELF Build ID does not match every Flutter mapping in this trace');
}
const flutterIds = new Set(matched.map(m => m.id));
const flutterFrames = frames.filter(f => flutterIds.has(f.mapping));
const symbols = new Map();
for (let i = 0; i < flutterFrames.length; i += 100) {
  const batch = flutterFrames.slice(i, i + 100);
  const { stdout } = await run(join(llvm, 'llvm-symbolizer'), [
    '--output-style=JSON', `--obj=${elf}`, '--inlines', '--demangle', ...batch.map(f => `0x${f.rel_pc.toString(16)}`),
  ]);
  const parsed = JSON.parse(stdout);
  if (parsed.length !== batch.length) throw new Error('Symbolizer result count mismatch');
  batch.forEach((frame, index) => symbols.set(frame.id, parsed[index].Symbol.map(s => ({
    function: s.FunctionName, file: s.FileName, line: s.Line, column: s.Column,
  }))));
}
const frameById = new Map(frames.map(f => [f.id, f]));
const mappingById = new Map(mappings.map(m => [m.id, m]));
const callsiteById = new Map(callsites.map(c => [c.id, c]));
const chain = id => {
  const result = [], seen = new Set();
  while (id !== null && callsiteById.has(id)) {
    if (seen.has(id)) throw new Error('Callsite cycle');
    seen.add(id);
    const callsite = callsiteById.get(id), frame = frameById.get(callsite.frame_id);
    result.push({ module: mappingById.get(frame.mapping)?.name.split('/').at(-1),
      pc: `0x${frame.rel_pc.toString(16)}`, name: frame.name, symbols: symbols.get(frame.id) });
    id = callsite.parent_id;
  }
  return result;
};
const dumps = [], live = new Map(), inclusive = new Map();
const times = [...new Set(allocations.map(a => a.ts))].sort((a,b) => a-b);
const attribution = id => {
  const names = chain(id).flatMap(f => f.symbols?.map(s => s.function) ?? [f.name]).filter(Boolean);
  // Labels describe stack families, not proof of a leaking resource owner.
  for (const [label, pattern] of [
    ['VM allocation-profile response', /GetAllocationProfile|AllocationProfilePrintJSON/],
    ['VM CPU profiler', /dart::.*(?:Profiler|SampleBuffer|CodeLookup|ProfileBuilder|SampleBlock)/],
    ['VM Timeline', /dart::.*Timeline/],
    ['VM JSON/service', /dart::.*(?:JSON|Service::|TextBuffer)/],
    ['Font/text', /(?:SkFont|SkStrike|sktext::|txt::|FontCollection|TextLayout|Paragraph|Typeface|harfbuzz)/],
    ['Graphics', /(?:Sk[A-Z]|skgpu::|impeller::|ImageDecoder|ImageGenerator|RasterCache)/],
  ]) if(names.some(name=>pattern.test(name))) return label;
  return names.find(name=>/^(dart|flutter)::/.test(name)) ?? 'Other/unresolved';
};
const labels = new Map(callsites.map(c => [c.id, attribution(c.id)]));
for (const ts of times) {
  let delta = 0;
  for (const a of allocations.filter(a => a.ts === ts)) {
    const key = `${a.upid}/${a.callsite_id}`;
    const row = live.get(key) ?? { upid: a.upid, callsiteId: a.callsite_id, bytes: 0, count: 0 };
    row.bytes += a.size; row.count += a.count; delta += a.size; live.set(key, row);
  }
  const families = {};
  for (const row of live.values()) {
    const label = labels.get(row.callsiteId);
    families[label] = (families[label] ?? 0) + row.bytes;
  }
  const clock = clocks[0];
  dumps.push({ ts, time: clock ? new Date(clock.clock_value/1e6 + (ts-clock.ts)/1e6).toISOString() : null,
    seconds: (ts-times[0])/1e9, deltaBytes: delta,
    retainedSinceCaptureBytes: [...live.values()].reduce((sum, row) => sum + row.bytes, 0), families });
}
const top = [...live.values()].filter(a => a.bytes > 0).sort((a,b) => b.bytes-a.bytes).map(a => ({ ...a, stack: chain(a.callsiteId) }));
for (const allocation of top) {
  const unique = new Set(allocation.stack.flatMap(frame => frame.symbols?.map(s => s.function) ?? []).filter(Boolean));
  for (const name of unique) inclusive.set(name, (inclusive.get(name) ?? 0) + allocation.bytes);
}
const health = stats.filter(s => s.severity === 'data_loss' || s.severity === 'error' || /heapprofd.*(error|overran|corrupt|disconnect)/.test(s.name));
const result = { trace: basename(trace), elfBuildId: buildId, process: processRows,
  note: 'Sampled malloc attribution since attachment, not full pre-existing heap or all RSS. Inclusive function totals overlap; do not add them.',
  health, hasReportedDataLossOrError: health.some(s=>s.severity==='data_loss'||s.severity==='error'),
  stats: stats.filter(s => /heapprofd/.test(s.name)), dumps,
  symbolizedFrames: flutterFrames.length,
  unresolvedFrames: flutterFrames.filter(f => !symbols.get(f.id)?.some(s => s.function && s.function !== '??')).length,
  topAllocations: top.slice(0, 100),
  inclusiveFunctions: [...inclusive].map(([functionName, bytes]) => ({ functionName, bytes })).sort((a,b) => b.bytes-a.bytes).slice(0,100),
};
mkdirSync(out, { recursive: true });
writeFileSync(join(out, `${basename(trace)}.symbolized.json`), JSON.stringify(result, null, 2));
console.log(JSON.stringify({ trace: result.trace, buildId, frames: result.symbolizedFrames,
  unresolved: result.unresolvedFrames, health,
  dumps: dumps.map(({families,...dump})=>dump),
  top: result.inclusiveFunctions.filter(f=>!/std::__|decltype\(|fml::/.test(f.functionName)).slice(0,8) }, null, 2));
