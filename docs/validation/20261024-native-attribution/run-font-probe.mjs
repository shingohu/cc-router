import { execFile, spawn } from 'node:child_process';
import { promisify } from 'node:util';
import { readFileSync, writeFileSync, appendFileSync, mkdirSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';

const base=dirname(fileURLToPath(import.meta.url)),out=join(base,'font-probe');
const original=resolve(process.argv[2]??'');
const hash=file=>createHash('sha256').update(readFileSync(file)).digest('hex');
if(hash(original)!=='a3416242f0d745158b39d7f8e24d5404ebf33e298d04b3d7bd2397748a414851')throw new Error('Original restoration APK identity mismatch');
const probe=resolve(process.argv[3]??join(base,'../../../demo/build/app/outputs/flutter-apk/app-profile.apk'));
if(hash(probe)===hash(original))throw new Error('Font probe APK has not been built');
mkdirSync(out);
const exec=promisify(execFile),serial='UJN0221619023373',pkg='dev.ccrouter.demo';
const adb=async(...args)=>(await exec('adb',['-s',serial,...args],{timeout:30000,maxBuffer:32*1024*1024})).stdout;
const shell=command=>adb('shell',command),sleep=ms=>new Promise(r=>setTimeout(r,ms));
const save=(name,value)=>writeFileSync(join(out,name),typeof value==='string'?value:JSON.stringify(value,null,2));
const record=(event,data={})=>{const value={time:new Date().toISOString(),event,...data};appendFileSync(join(out,'events.ndjson'),JSON.stringify(value)+'\n');console.log(JSON.stringify(value));};
let pid,trace,tracePid,logger,installed=false;
const remote=`/data/misc/perfetto-traces/ccrouter-font-${Date.now()}.perfetto-trace`;
async function sample(phase) {
  if((await shell(`pidof ${pkg}`)).trim()!==pid)throw new Error('Font-probe process changed');
  const mem=await shell(`dumpsys meminfo ${pkg}`);
  save(`${phase}-mem.txt`,mem);save(`${phase}-smaps.txt`,await shell(`run-as ${pkg} cat /proc/${pid}/smaps`));
  save(`${phase}-thermal.txt`,await shell('dumpsys thermalservice'));
  save(`${phase}-activity.txt`,await shell('dumpsys activity activities'));
  record('sample',{phase,pid,totalPssKb:Number(/TOTAL PSS:\s+(\d+)/.exec(mem)?.[1])});
}
async function stopTrace() {
  if(!tracePid||trace.exitCode!==null)return;
  const cmd=await shell(`cat /proc/${tracePid}/cmdline`);
  if(!cmd.includes('perfetto')||!cmd.includes(remote))throw new Error('Trace PID identity mismatch');
  await shell(`kill -INT ${tracePid}`);
  await Promise.race([new Promise(r=>trace.once('exit',r)),sleep(10000)]);
  if(trace.exitCode===null)throw new Error('Trace did not finish');
  tracePid=undefined;
  await adb('pull',remote,join(out,'native.perfetto-trace'));
}
try {
  let processes=await shell('ps -A');
  if(processes.split('\n').some(l=>/\bmonkey\b|\bscreenrecord\b/.test(l)))throw new Error('Another capture still active');
  if(/\bheapprofd\b/.test(processes))record('waiting_for_previous_heapprofd');
  for(let attempt=0;attempt<45&&/\bheapprofd\b/.test(processes);attempt++){
    await sleep(1000);processes=await shell('ps -A');
  }
  if(/\bheapprofd\b/.test(processes))throw new Error('Previous heapprofd did not retire; no process killed');
  save('install.txt',await adb('install','-r',probe));installed=true;
  await shell(`am force-stop ${pkg}`);
  const config=`buffers { size_kb: 65536 fill_policy: DISCARD }\nduration_ms: 240000\ndata_sources { config { name: "android.heapprofd" heapprofd_config { sampling_interval_bytes: 262144 process_cmdline: "${pkg}" shmem_size_bytes: 16777216 block_client: false continuous_dump_config { dump_phase_ms: 0 dump_interval_ms: 10000 } } } }\n`;
  save('heap.pbtxt',config);await adb('push',join(out,'heap.pbtxt'),'/data/local/tmp/ccrouter-font-probe.pbtxt');
  trace=spawn('adb',['-s',serial,'shell',`cat /data/local/tmp/ccrouter-font-probe.pbtxt | exec perfetto --txt -c - -o ${remote}`]);
  trace.stdout.on('data',d=>appendFileSync(join(out,'perfetto.log'),d));trace.stderr.on('data',d=>appendFileSync(join(out,'perfetto.log'),d));
  await sleep(2000);
  tracePid=(await shell('ps -A -o PID,ARGS')).split('\n').find(l=>l.includes(remote)&&/^\s*\d+\s+perfetto\b/.test(l))?.trim().split(/\s+/)[0];
  if(!tracePid)throw new Error('Probe trace not running');
  save('launch.txt',await shell(`am start -W -n ${pkg}/.MainActivity --ez enable-dart-profiling false`));
  const started=performance.now();pid=(await shell(`pidof ${pkg}`)).trim();
  if(!/^\d+$/.test(pid))throw new Error('Probe process missing');
  logger=spawn('adb',['-s',serial,'logcat',`--pid=${pid}`,'-T','1','-v','threadtime']);
  logger.stdout.on('data',d=>appendFileSync(join(out,'logcat.log'),d));
  save('config.json',{serial,pkg,pid,probeApkSha256:hash(probe),restoreApkSha256:hash(original),
    entrypoint:'demo/tool/native_font_probe.dart',ccrouterInitialized:false,vmClientConnected:false,profilerRequested:false,
    stylesPerRound:72,rounds:3,stylePeriodMs:400,samplingIntervalBytes:262144,startedAt:new Date().toISOString()});
  for(const second of [5,12,35,65,100,135,165]){
    await sleep(Math.max(0,started+second*1000-performance.now()));
    if(trace.exitCode!==null)throw new Error('Probe trace exited early');
    await sample(`at-${second}s`);
  }
  await sample('before-trim');
  save('trim.txt',await shell(`am send-trim-memory ${pkg} RUNNING_CRITICAL`));record('trim_sent');
  await sleep(20000);await sample('after-trim-20s');
  await stopTrace();
  save('summary.json',{completed:true,pid,endedAt:new Date().toISOString()});record('completed');
} catch(error){record('failed',{message:error.stack});process.exitCode=1;}
finally {
  await stopTrace().catch(error=>record('cleanup_error',{message:error.message}));logger?.kill('SIGTERM');
  if(installed){save('restore-install.txt',await adb('install','-r',original));save('restore-launch.txt',await shell(`am start -W -n ${pkg}/.MainActivity --ez enable-dart-profiling false`));record('original_demo_restored');}
}
