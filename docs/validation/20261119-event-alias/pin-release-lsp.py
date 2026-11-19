import hashlib
import json
import os
from pathlib import Path
import queue
import subprocess
import tempfile
import threading
import time

REPO = Path('<home>/develop/LiberLive/cc-router')
DEMO = REPO / 'demo'
TARGET = DEMO / 'modules/navigation_lab/lib/src/component_capabilities.dart'
DART = '<home>/fvm/versions/ohos/oh-3.41.9-release/bin/cache/dart-sdk/bin/dart'
SNAPSHOT = str(Path(DART).parent / 'snapshots/analysis_server.dart.snapshot')
EXPECTED = 'ec9da8538b27ef17efcf44aeefc9bbad2fbef845'
CODE = 'ccrouter_alias_invalid'
ORIGINAL = TARGET.read_text()
BROKEN = ORIGINAL.replace('@CCEventContract(', "@CCEventContract(alias: 'toString',", 1)
assert BROKEN != ORIGINAL
BOOTSTRAP = DEMO / 'tools/ccrouter_analyzer_plugin_host/tools/analyzer_plugin'
assert EXPECTED in (BOOTSTRAP / 'pubspec.yaml').read_text()
assert EXPECTED in (BOOTSTRAP / 'pubspec.lock').read_text()

class Client:
    def __init__(self):
        self.process = subprocess.Popen([DART, SNAPSHOT, '--protocol=lsp', '--suppress-analytics'], cwd=DEMO, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.messages = queue.Queue()
        self.stderr = []
        self.next_id = 0
        self.revision = 0
        self.diagnostics = []
        self.last_version = None
        threading.Thread(target=self.read, daemon=True).start()
        threading.Thread(target=self.read_errors, daemon=True).start()
    def read_errors(self):
        for line in self.process.stderr:
            self.stderr.append(line.decode(errors='replace'))
            self.stderr = self.stderr[-50:]
    def read(self):
        try:
            while True:
                headers = {}
                while True:
                    line = self.process.stdout.readline()
                    if not line:
                        raise EOFError('Analysis Server closed its output')
                    if line in (b'\r\n', b'\n'):
                        break
                    key, value = line.decode().split(':', 1)
                    headers[key.lower()] = value.strip()
                length = int(headers['content-length'])
                payload = bytearray()
                while len(payload) < length:
                    part = self.process.stdout.read(length - len(payload))
                    if not part:
                        raise EOFError('Incomplete LSP message')
                    payload.extend(part)
                self.messages.put(json.loads(payload))
        except BaseException as error:
            self.messages.put(error)
    def send(self, message):
        payload = json.dumps({'jsonrpc': '2.0', **message}).encode()
        self.process.stdin.write(f'Content-Length: {len(payload)}\r\n\r\n'.encode() + payload)
        self.process.stdin.flush()
    def notify(self, method, params):
        self.send({'method': method, 'params': params})
    def pump(self, timeout):
        try:
            message = self.messages.get(timeout=timeout)
        except queue.Empty:
            return None
        if isinstance(message, BaseException):
            raise RuntimeError(str(message) + '\n' + ''.join(self.stderr))
        method = message.get('method')
        params = message.get('params') or {}
        if method and 'id' in message:
            result = [{} for _ in params.get('items', [])] if method == 'workspace/configuration' else None
            self.send({'id': message['id'], 'result': result})
        elif method == 'textDocument/publishDiagnostics' and params.get('uri') == TARGET.as_uri():
            self.diagnostics = params.get('diagnostics', [])
            self.last_version = params.get('version')
            self.revision += 1
        elif method in ('window/logMessage', 'window/showMessage') and params.get('type') == 1:
            raise RuntimeError(str(message))
        return message
    def request(self, method, params, timeout=60):
        self.next_id += 1
        request_id = self.next_id
        self.send({'id': request_id, 'method': method, 'params': params})
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            message = self.pump(min(1, deadline-time.monotonic()))
            if message and message.get('id') == request_id and 'method' not in message:
                if 'error' in message:
                    raise RuntimeError(str(message['error']))
                return message.get('result')
        raise TimeoutError(method + '\n' + ''.join(self.stderr))
    def wait_diagnostic(self, present, after):
        deadline = time.monotonic() + 90
        stable = None
        while time.monotonic() < deadline:
            self.pump(0.15)
            has = any(str(d.get('code', '')).lower() == CODE for d in self.diagnostics)
            if self.revision > after and has == present:
                stable = stable or time.monotonic()
                if time.monotonic() - stable >= 1:
                    return [d for d in self.diagnostics if str(d.get('code', '')).lower() == CODE]
            else:
                stable = None
        raise TimeoutError(f'{CODE} present={present}, diagnostics={self.diagnostics}\n' + ''.join(self.stderr))
    def start(self):
        self.request('initialize', {'processId': os.getpid(), 'rootUri': DEMO.as_uri(), 'workspaceFolders': [{'uri': DEMO.as_uri(), 'name': 'CCRouter Demo'}], 'capabilities': {'textDocument': {'publishDiagnostics': {'versionSupport': True}}}})
        self.notify('initialized', {})
        self.notify('textDocument/didOpen', {'textDocument': {'uri': TARGET.as_uri(), 'languageId': 'dart', 'version': 1, 'text': ORIGINAL}})
    def change(self, version, content):
        self.notify('textDocument/didChange', {'textDocument': {'uri': TARGET.as_uri(), 'version': version}, 'contentChanges': [{'text': content}]})
    def close(self):
        if self.process.poll() is not None:
            raise RuntimeError('Analysis Server exited unexpectedly')
        self.notify('textDocument/didClose', {'textDocument': {'uri': TARGET.as_uri()}})
        self.request('shutdown', {}, timeout=15)
        self.notify('exit', {})
        self.process.stdin.close()
        assert self.process.wait(timeout=15) == 0

runs = []
for cycle in range(2):
    client = Client()
    try:
        client.start()
        revision = client.revision
        client.change(2, BROKEN)
        diagnostics = client.wait_diagnostic(True, revision)
        print(json.dumps({'cycle': cycle + 1, 'pid': client.process.pid, 'diagnostic': CODE, 'message': diagnostics[0]['message']}, ensure_ascii=False), flush=True)
        revision = client.revision
        client.change(3, ORIGINAL)
        client.wait_diagnostic(False, revision)
        runs.append({'cycle': cycle + 1, 'pid': client.process.pid, 'invalidAliasReported': True, 'repairCleared': True})
    finally:
        client.close()
    assert TARGET.read_text() == ORIGINAL

manager = Path.home() / '.dartServer/.plugin_manager'
cache = manager / hashlib.md5(str(BOOTSTRAP).encode()).hexdigest() / 'analyzer_plugin'
assert (cache / 'pubspec.yaml').read_bytes() == (BOOTSTRAP / 'pubspec.yaml').read_bytes(), 'Manager cache does not match Demo bootstrap'
config_path = cache / '.dart_tool/package_config.json'
config = json.loads(config_path.read_text())
entry = next(p for p in config['packages'] if p['name'] == 'ccrouter_analyzer_plugin')
assert EXPECTED in entry['rootUri'], entry
report = {'host': str(DEMO), 'pluginRef': EXPECTED, 'cache': str(cache), 'resolvedPluginRoot': entry['rootUri'], 'sourceUnchanged': TARGET.read_text() == ORIGINAL, 'runs': runs}
Path('/tmp/ccrouter-event-release-live-lsp.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
print(json.dumps(report, ensure_ascii=False, indent=2), flush=True)
