import { execFile, spawn } from 'node:child_process';
import { promisify } from 'node:util';
import { readFileSync, writeFileSync, appendFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';

// Same-APK A/B. Neither arm requests getAllocationProfile or forces Dart GC.
const mode = process.argv[2];
if (!['baseline', 'diagnostic'].includes(mode)) throw new Error('Choose baseline or diagnostic');
const base = dirname(fileURLToPath(import.meta.url));
const runName = process.argv[3] ?? mode;
if (!/^[a-z][a-z0-9-]*$/.test(runName)) throw new Error('Invalid evidence directory name');
const out = join(base, runName);
mkdirSync(out); // Never overwrite an earlier run.
const exec = promisify(execFile), serial = 'UJN0221619023373', pkg = 'dev.ccrouter.demo';
const diagnostic = mode === 'diagnostic';
const adb = async (...args) => (await exec('adb', ['-s', serial, ...args], { timeout: 25000, maxBuffer: 32*1024*1024 })).stdout;
const shell = command => adb('shell', command);
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const save = (name, value) => writeFileSync(join(out, name), typeof value === 'string' ? value : JSON.stringify(value, null, 2));
const record = (event, values = {}) => {
  const item = { time: new Date().toISOString(), event, ...values };
  appendFileSync(join(out, 'events.ndjson'), JSON.stringify(item)+'\n');
  console.log(JSON.stringify(item));
};
let pid, traceProcess, tracePid, monkey, monkeyPid, logger, vm, port, isolateId, baselineActivity;
let next=0, frames=0, isolateExited=false;
const pending = new Map(), frameTimes=[];
const rpc = (method, params = {}) => new Promise((resolve, reject) => {
  const id=String(++next), timer=setTimeout(() => { pending.delete(id); reject(new Error(`RPC timeout ${method}`)); },15000);
  pending.set(id,{resolve,reject,timer}); vm.send(JSON.stringify({jsonrpc:'2.0',id,method,params}));
});
const traceName=`ccrouter-native-${mode}-${Date.now()}.perfetto-trace`;
const tracePath=`/data/misc/perfetto-traces/${traceName}`;
async function stopOwned(process, processId, expected) {
  if (!processId || process.exitCode !== null) return;
  const cmdline = await shell(`cat /proc/${processId}/cmdline`).catch(() => '');
  if (!cmdline.includes(expected)) throw new Error(`Refuse signal to changed process ${processId}`);
  await shell(`kill -INT ${processId}`);
  await Promise.race([new Promise(resolve => process.once('exit',resolve)), sleep(10000)]);
  if (process.exitCode === null) throw new Error(`Owned ${expected} did not exit`);
}
async function sample(phase, seconds) {
  if ((await shell(`pidof ${pkg}`)).trim() !== pid || isolateExited) throw new Error('Engine identity changed');
  const memory=await shell(`dumpsys meminfo ${pkg}`), thermal=await shell('dumpsys thermalservice');
  const activity=await shell('dumpsys activity activities');
  const resumed=activity.split('\n').filter(x=> /mResumedActivity|topResumedActivity/.test(x));
  const identity=/ActivityRecord\{([^ ]+)/.exec(resumed.join(' '))?.[1];
  if (baselineActivity && identity !== baselineActivity) throw new Error(`Activity identity changed: ${identity}`);
  baselineActivity ??= identity;
  const name=`${phase}-${seconds}`;
  save(`${name}-mem.txt`,memory); save(`${name}-thermal.txt`,thermal); save(`${name}-activity.txt`,activity);
  save(`${name}-smaps.txt`,await shell(`run-as ${pkg} cat /proc/${pid}/smaps`));
  save(`${name}-cpu.txt`,await shell(`top -b -n 1 -p ${pid}`));
  let vmMemory, routes;
  if(diagnostic) {
    const info=await rpc('getVM');
    if(!info.isolates.some(i=>i.id===isolateId)) throw new Error('Main isolate changed');
    vmMemory=[];
    for(const isolate of [...info.isolates,...info.systemIsolates??[]]) {
      vmMemory.push({id:isolate.id,name:isolate.name,...await rpc('getMemoryUsage',{isolateId:isolate.id})});
    }
    routes=(await rpc('ext.ccrouter.snapshot',{isolateId})).runtime.entries.filter(e=>e.kind==='route');
  }
  record('sample',{phase,seconds,pid,activity:identity,frames,
    totalPssKb:Number(/TOTAL PSS:\s+(\d+)/.exec(memory)?.[1]),
    thermalStatus:Number(/Thermal Status:\s+(\d+)/.exec(thermal)?.[1]),vmMemory,routes});
}
try {
  if ((await shell('ps -A')).split('\n').some(x=>/\bmonkey\b|\bscreenrecord\b|com\.huawei\.screenrecorder|\bheapprofd\b/.test(x))) throw new Error('Conflicting capture/Monkey process');
  save('initial-memory.txt',await shell(`dumpsys meminfo ${pkg}`));
  // Test restart establishes an independent arm, never evidence of memory release.
  await shell(`am force-stop ${pkg}`);
  const config=`buffers { size_kb: 65536 fill_policy: DISCARD }\nduration_ms: 480000\ndata_sources { config { name: "android.heapprofd" heapprofd_config { sampling_interval_bytes: 262144 process_cmdline: "${pkg}" shmem_size_bytes: 16777216 block_client: false continuous_dump_config { dump_phase_ms: 0 dump_interval_ms: 15000 } } } }\n`;
  save('heap.pbtxt',config);
  await adb('push',join(out,'heap.pbtxt'),`/data/local/tmp/${traceName}.pbtxt`);
  traceProcess=spawn('adb',['-s',serial,'shell',`echo CCROUTER_TRACE_PID=$$; exec sh -c 'cat /data/local/tmp/${traceName}.pbtxt | exec perfetto --txt -c - -o ${tracePath}'`]);
  let tracePrefix='';
  traceProcess.stdout.on('data',data=>{appendFileSync(join(out,'perfetto.log'),data);tracePrefix+=data;tracePid??=/CCROUTER_TRACE_PID=(\d+)/.exec(tracePrefix)?.[1];});
  traceProcess.stderr.on('data',data=>appendFileSync(join(out,'perfetto.log'),data));
  await sleep(2000);
  if(traceProcess.exitCode!==null) throw new Error('Perfetto exited before launch');
  save('launch.txt',await shell(`am start -W -n ${pkg}/.MainActivity --ez enable-dart-profiling ${diagnostic}`));
  await sleep(5000);
  pid=(await shell(`pidof ${pkg}`)).trim();
  if(!/^\d+$/.test(pid)) throw new Error('Expected one Demo PID');
  // Locate actual perfetto child independently of the pipeline's shell PID.
  const ps=await shell('ps -A -o PID,ARGS');
  tracePid=ps.split('\n').find(x=>x.includes(tracePath)&& /^\s*\d+\s+perfetto\b/.test(x))?.trim().split(/\s+/)[0];
  if(!tracePid) throw new Error('Owned Perfetto PID missing');
  logger=spawn('adb',['-s',serial,'logcat',`--pid=${pid}`,'-T','1','-v','threadtime']);
  logger.stdout.on('data',data=>appendFileSync(join(out,'logcat.log'),data));
  if(diagnostic) {
    const startup=await adb('logcat','-d',`--pid=${pid}`,'-v','brief');
    const service=/Dart VM service is listening on (http:\/\/127\.0\.0\.1:\d+\/[^\s]*)/.exec(startup)?.[1];
    if(!service) throw new Error('Missing VM URL');
    const url=new URL(service); port=(await adb('forward','tcp:0',`tcp:${url.port}`)).trim();
    vm=new WebSocket(`ws://127.0.0.1:${port}${url.pathname}ws`);
    vm.addEventListener('message',e=>{
      const message=JSON.parse(e.data), entry=pending.get(message.id);
      if(entry){pending.delete(message.id);clearTimeout(entry.timer);message.error?entry.reject(new Error(JSON.stringify(message.error))):entry.resolve(message.result);}
      else if(message.method==='streamNotify') {
        const event=message.params.event;
        if(event.kind==='IsolateExit'&&event.isolate?.id===isolateId) isolateExited=true;
        if(event.extensionKind==='Flutter.Frame') {frames++;frameTimes.push(event.extensionData);appendFileSync(join(out,'frames.ndjson'),JSON.stringify(event.extensionData)+'\n');}
      }
    });
    await new Promise((resolve,reject)=>{vm.addEventListener('open',resolve,{once:true});vm.addEventListener('error',reject,{once:true});});
    isolateId=(await rpc('getVM')).isolates.find(i=>i.name==='main').id;
    save('vm-flags.json',(await rpc('getFlagList')).flags.filter(f=>/profiler|profile_period|timeline_recorder/.test(f.name)));
    await rpc('setVMTimelineFlags',{recordedStreams:['Dart','Embedder','GC']});
    await rpc('streamListen',{streamId:'Extension'});await rpc('streamListen',{streamId:'Isolate'});
  }
  const apk=readFileSync(join(base,'../../../demo/build/app/outputs/flutter-apk/app-profile.apk'));
  save('config.json',{mode,pid,isolateId,serial,pkg,startedAt:new Date().toISOString(),apkSha256:createHash('sha256').update(apk).digest('hex'),
    profiler:diagnostic,timeline:diagnostic?['Dart','Embedder','GC']:[],snapshotPolling:diagnostic,devtoolsRegistered:true,
    allocationProfile:false,explicitGC:false,samplingIntervalBytes:262144,sharedMemoryBytes:16777216,seed:20261024,throttleMs:200,randomDurationMs:300000});
  await sample('baseline',0);await sleep(20000);await sample('baseline',20);
  const args=['-p',pkg,'-s','20261024','--throttle','200','--pct-touch','45','--pct-motion','25','--pct-pinchzoom','5','--pct-majornav','20','--pct-nav','5','--pct-appswitch','0','--pct-syskeys','0','--pct-trackball','0','--pct-flip','0','--pct-anyevent','0','--pct-permission','0','--ignore-crashes','--ignore-timeouts','--ignore-security-exceptions','--monitor-native-crashes','-v','-v','1000000'];
  save('monkey-args.json',args);
  monkey=spawn('adb',['-s',serial,'shell',`echo CCROUTER_MONKEY_PID=$$; exec monkey ${args.join(' ')}`]);
  let prefix='';
  monkey.stdout.on('data',data=>{appendFileSync(join(out,'monkey.log'),data);prefix+=data;monkeyPid??=/CCROUTER_MONKEY_PID=(\d+)/.exec(prefix)?.[1];});
  monkey.stderr.on('data',data=>appendFileSync(join(out,'monkey.log'),data));
  const started=performance.now();record('random_started',{durationMs:300000});
  for(let tick=1;tick<=10;tick++) {
    await sleep(Math.max(0,started+tick*30000-performance.now()));
    if(monkey.exitCode!==null) throw new Error('Monkey exited early');
    if(traceProcess.exitCode!==null) throw new Error('Perfetto exited during workload');
    if(tick===10){await stopOwned(monkey,monkeyPid,'com.android.commands.monkey');monkeyPid=undefined;}
    await sample('random',tick*30);
  }
  record('random_completed',{elapsedMs:performance.now()-started});
  // Recover to the visible home without replacing the Activity or engine.
  for(let attempt=0;attempt<12;attempt++) {
    await shell('uiautomator dump /data/local/tmp/ccrouter-native-ui.xml');
    const xml=await shell('cat /data/local/tmp/ccrouter-native-ui.xml');save(`return-${attempt}.xml`,xml);
    if(xml.includes('CCRouter Lab')&&xml.includes('Route Entries')) {record('home_restored',{attempt});break;}
    if(attempt===11) throw new Error('Could not return to home; keep evidence but reject settled comparison');
    await shell('input keyevent 4');await sleep(700);
  }
  await sample('home',0);
  for(let tick=1;tick<=2;tick++){await sleep(30000);await sample('idle',tick*30);}
  await stopOwned(traceProcess,tracePid,'perfetto');tracePid=undefined;
  await adb('pull',tracePath,join(out,'native.perfetto-trace'));
  const screenshot=await exec('adb',['-s',serial,'exec-out','screencap','-p'],{encoding:'buffer',timeout:20000,maxBuffer:10*1024*1024});
  writeFileSync(join(out,'final.png'),screenshot.stdout);
  save('summary.json',{completed:true,pid,isolateId,frames,frameStats:['build','raster'].map(key=>{const a=frameTimes.map(f=>f[key]/1000).sort((a,b)=>a-b);return{key,count:a.length,p95Ms:a[Math.floor(a.length*.95)],maxMs:a.at(-1)};}),endedAt:new Date().toISOString()});
  record('completed');
} catch(error) { record('failed',{message:error.stack});process.exitCode=1; }
finally {
  if(monkeyPid) await stopOwned(monkey,monkeyPid,'com.android.commands.monkey').catch(error=>record('cleanup_error',{message:error.message}));
  if(tracePid) await stopOwned(traceProcess,tracePid,'perfetto').catch(error=>record('cleanup_error',{message:error.message}));
  if(traceProcess?.exitCode!==null) await adb('pull',tracePath,join(out,'native.perfetto-trace')).catch(()=>{});
  logger?.kill('SIGTERM');vm?.close();for(const p of pending.values())clearTimeout(p.timer);
  if(port)await adb('forward','--remove',`tcp:${port}`);
}
