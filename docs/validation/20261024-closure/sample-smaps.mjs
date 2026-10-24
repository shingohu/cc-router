import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { readFileSync, writeFileSync, appendFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const exec = promisify(execFile), out = join(dirname(fileURLToPath(import.meta.url)), 'random5m');
const config = JSON.parse(readFileSync(join(out, 'controlled-config.json'), 'utf8'));
const adb = args => exec('adb', ['-s', config.serial, ...args], { timeout: 20000, maxBuffer: 16 * 1024 * 1024 });
for (let index = 0; index < 8; index++) {
  const pid = (await adb(['shell', 'pidof', config.pkg])).stdout.trim();
  if (pid !== config.pid) throw new Error('Refuse smaps from a replacement process');
  const source = (await adb(['shell', 'run-as', config.pkg, 'cat', `/proc/${pid}/smaps`])).stdout;
  writeFileSync(join(out, 'samples', `smaps-${index}.txt`), source);
  const groups = new Map();
  let current;
  for (const line of source.split('\n')) {
    const header = /^\S+-\S+\s+\S+\s+\S+\s+\S+\s+\d+\s*(.*)$/.exec(line);
    if (header) {
      const name = header[1] || '<anonymous>';
      if (!groups.has(name)) groups.set(name, { name, rssKb: 0, pssKb: 0, privateDirtyKb: 0, sizeKb: 0 });
      current = groups.get(name); continue;
    }
    const metric = /^(Rss|Pss|Private_Dirty|Size):\s+(\d+) kB$/.exec(line);
    if (current && metric) current[{ Rss: 'rssKb', Pss: 'pssKb', Private_Dirty: 'privateDirtyKb', Size: 'sizeKb' }[metric[1]]] += Number(metric[2]);
  }
  const sample = { time: new Date().toISOString(), index, pid, mappings: [...groups.values()].sort((a, b) => b.pssKb - a.pssKb) };
  appendFileSync(join(out, 'smaps.ndjson'), JSON.stringify(sample) + '\n');
  console.log(JSON.stringify({ time: sample.time, index, top: sample.mappings.slice(0, 8) }));
  if (readFileSync(join(out, 'controlled-events.ndjson'), 'utf8').includes('"event":"completed"')) break;
  await new Promise(resolve => setTimeout(resolve, 30000));
}
