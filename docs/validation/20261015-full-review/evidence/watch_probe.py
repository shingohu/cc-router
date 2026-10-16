import subprocess, pathlib, os, signal, time, json
root=pathlib.Path(__file__).parent
cwd=root/'watch-probe'
target=cwd/'demo/lib/src/ccrouter_generated/host/ccrouter_demo_ccrouter.g.dart'
original=target.stat().st_mode
log=root/'logs/watch-snapshot-probe.log'
env=os.environ.copy();env['CCROUTER_HOME']=str(root/'coordination/watch-probe');env['CCROUTER_PUB_HOOK_DISABLE']='1';env['FLUTTER_ROOT']='<USER_HOME>/fvm/versions/3.41.9'
command=['<USER_HOME>/fvm/versions/3.41.9/bin/dart','packages/ccrouter_generator/bin/ccrouter_generator.dart','generate','demo','--watch=auto','--machine']
process=None
try:
 with log.open('w') as output:
  process=subprocess.Popen(command,cwd=cwd,env=env,stdout=output,stderr=subprocess.STDOUT,start_new_session=True)
  deadline=time.time()+50
  while time.time()<deadline and process.poll() is None:
   if '\"type\":\"watchStarted\"' in log.read_text(errors='replace'):
    target.chmod(0)
    break
   time.sleep(0.001)
  try:
   code=process.wait(timeout=15)
   result={'exited':True,'exit_code':code,'pid':process.pid}
  except subprocess.TimeoutExpired:
   result={'exited':False,'after_seconds':15,'pid':process.pid}
  snapshot=subprocess.run(['ps','-ax','-o','pid,ppid,pgid,command'],capture_output=True,text=True).stdout
  result['processes']=[line for line in snapshot.splitlines() if str(cwd) in line or ('build_runner' in line and str(process.pid) in line)]
  (root/'logs/watch-snapshot-probe.json').write_text(json.dumps(result,indent=2))
  print(json.dumps(result))
finally:
 target.chmod(original)
 if process is not None:
  try:os.killpg(process.pid,signal.SIGTERM)
  except ProcessLookupError:pass
  try:process.wait(timeout=5)
  except subprocess.TimeoutExpired:
   os.killpg(process.pid,signal.SIGKILL);process.wait()
print(log.read_text(errors='replace')[-5000:])
