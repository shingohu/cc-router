import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const base=dirname(fileURLToPath(import.meta.url));
const read=path=>readFileSync(path,'utf8');
const smaps=source=>{
  const maps=new Map();let current;
  for(const line of source.split('\n')) {
    const header=/^[0-9a-f]+-[0-9a-f]+\s+\S+\s+\S+\s+\S+\s+\d+\s*(.*)$/.exec(line);
    if(header){const name=header[1]||'<anonymous>';if(!maps.has(name))maps.set(name,{name,pssKb:0,rssKb:0,privateDirtyKb:0});current=maps.get(name);continue;}
    const metric=/^(Pss|Rss|Private_Dirty):\s+(\d+) kB$/.exec(line);
    if(current&&metric)current[{Pss:'pssKb',Rss:'rssKb',Private_Dirty:'privateDirtyKb'}[metric[1]]]+=Number(metric[2]);
  }
  return maps;
};
const result={note:'Independent same-APK arms, not a causal percentage comparison. Native malloc sampling excludes direct mmap/GPU and other processes.',arms:[]};
for(const runName of ['baseline','diagnostic-retry']) {
  const dir=join(base,runName);
  if(!existsSync(join(dir,'summary.json')))continue;
  const events=read(join(dir,'events.ndjson')).trim().split('\n').map(JSON.parse);
  const config=JSON.parse(read(join(dir,'config.json')));
  const mode=config.mode;
  const points=events.filter(e=>e.event==='sample').map(e=>{
    const stem=`${e.phase}-${e.seconds}`,mem=read(join(dir,`${stem}-mem.txt`));
    const native=/^\s+Native Heap\s+([\d ]+)$/m.exec(mem)?.[1].trim().split(/\s+/).map(Number);
    return{time:e.time,phase:e.phase,seconds:e.seconds,pid:e.pid,activity:e.activity,totalPssKb:e.totalPssKb,thermalStatus:e.thermalStatus,
      deviceBoottimeMs:Number(/Realtime:\s+(\d+)/.exec(mem)?.[1]),
      nativePssKb:native?.[0],nativeHeapSizeKb:native?.[5],nativeAllocatedKb:native?.[6],nativeFreeKb:native?.[7],
      routes:e.routes?.map(r=>({id:r.id,routeId:r.routeId})),vmMemory:e.vmMemory};
  });
  const start=smaps(read(join(dir,'baseline-20-smaps.txt'))),end=smaps(read(join(dir,'idle-60-smaps.txt')));
  const delta=[...new Set([...start.keys(),...end.keys()])].map(name=>({name,
    beforePssKb:start.get(name)?.pssKb??0,afterPssKb:end.get(name)?.pssKb??0,
    deltaPssKb:(end.get(name)?.pssKb??0)-(start.get(name)?.pssKb??0)})).sort((a,b)=>b.deltaPssKb-a.deltaPssKb);
  const nativeFile=join(dir,'native.perfetto-trace.symbolized.json');
  const native=existsSync(nativeFile)?JSON.parse(read(nativeFile)):null;
  const coverage=native?{
    firstDumpTs:native.dumps[0]?.ts,lastDumpTs:native.dumps.at(-1)?.ts,
    firstWorkloadSampleTs:points.find(p=>p.phase==='random')?.deviceBoottimeMs*1e6,
    lastIdleSampleTs:points.at(-1)?.deviceBoottimeMs*1e6,
    hasReportedDataLossOrError:native.hasReportedDataLossOrError,
  }:null;
  const monkey=read(join(dir,'monkey.log'));
  const eventNumbers=[...monkey.matchAll(/Sending event #(\d+)/g)].map(m=>Number(m[1]));
  const logcat=read(join(dir,'logcat.log'));
  result.arms.push({mode,config,summary:JSON.parse(read(join(dir,'summary.json'))),points,
    monkey:{lastPeriodicEvent:Math.max(...eventNumbers),injectedSummary:/Events injected:\s*(\d+)/.exec(monkey)?.[1]??null,
      failureLines:monkey.split('\n').filter(l=>/\/\/ (?:CRASH|ANR|NOT RESPONDING)|MONKEY ABORTED/.test(l))},
    exceptionLines:logcat.split('\n').filter(l=>/FATAL EXCEPTION|Unhandled Exception|ANR in |Fatal signal/.test(l)),
    webviewFirstLoad:logcat.split('\n').find(l=>/WebViewFactory.*Loading/.test(l)),
    nativeCoverage:coverage,topMappingGrowth:delta.slice(0,20)});
}
const fontDir=join(base,'font-probe');
if(existsSync(join(fontDir,'summary.json'))){
  const events=read(join(fontDir,'events.ndjson')).trim().split('\n').map(JSON.parse);
  const native=JSON.parse(read(join(fontDir,'native.perfetto-trace.symbolized.json')));
  const points=events.filter(e=>e.event==='sample').map(e=>{
    const mem=read(join(fontDir,`${e.phase}-mem.txt`));
    const n=/^\s+Native Heap\s+([\d ]+)$/m.exec(mem)?.[1].trim().split(/\s+/).map(Number);
    return{...e,deviceBoottimeMs:Number(/Realtime:\s+(\d+)/.exec(mem)?.[1]),
      nativePssKb:n?.[0],nativeAllocatedKb:n?.[6],nativeFreeKb:n?.[7]};
  });
  result.fontProbe={config:JSON.parse(read(join(fontDir,'config.json'))),points,
    health:native.health,hasReportedDataLossOrError:native.hasReportedDataLossOrError,
    dumps:native.dumps.map(d=>({ts:d.ts,time:d.time,seconds:d.seconds,bytes:d.retainedSinceCaptureBytes,fontBytes:d.families['Font/text']})),
    phaseLog:read(join(fontDir,'logcat.log')).split('\n').filter(l=>l.includes('FONT_PROBE')),
    firstDumpTs:native.dumps[0]?.ts,lastDumpTs:native.dumps.at(-1)?.ts,
    exceptionLines:read(join(fontDir,'logcat.log')).split('\n').filter(l=>/FATAL EXCEPTION|Unhandled Exception|ANR in |Fatal signal/.test(l)),
    restored:events.some(e=>e.event==='original_demo_restored')};
}
writeFileSync(join(base,'analysis.json'),JSON.stringify(result,null,2));
for(const arm of result.arms)console.log(JSON.stringify({mode:arm.mode,points:arm.points.map(({vmMemory,routes,...p})=>p),
  coverage:arm.nativeCoverage,monkey:arm.monkey,errors:arm.exceptionLines,topMappings:arm.topMappingGrowth.slice(0,6)},null,2));
