import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// A real, isolated Analysis Server using the current local plugin sources.
/// No Pub invocation or IDE cache is needed: the legacy loader intentionally
/// has only an entrypoint and an absolute package configuration.
class AnalysisServerSession {
  AnalysisServerSession._(this.root, this.host, this.process, this.lsp);

  final Directory root;
  final Directory host;
  final Process process;
  final bool lsp;
  List<int> _buffer = [];
  final _pending = <String, Completer<Map<String, dynamic>>>{};
  final diagnostics = <String, List<Map<String, dynamic>>>{};
  final revisions = <String, int>{};
  final _subscriptions = <StreamSubscription<dynamic>>[];
  final _failures = <String>[];
  final _stderr = <String>[];
  int _nextId = 0;
  bool _closing = false;

  static Future<AnalysisServerSession> start(
    Map<String, String> sources, {
    bool lsp = false,
    Map<String, Map<String, String>> dependencyPackages = const {},
  }) async {
    final root = Directory.systemTemp.createTempSync('ccrouter-server-e2e-');
    try {
      final pluginRoot = Directory.current;
      final host = Directory(p.join(root.path, 'host'))..createSync();
      final pluginPackage = Directory(p.join(root.path, 'plugin'))
        ..createSync();
      final loader = Directory(
        p.join(pluginPackage.path, 'tools', 'analyzer_plugin'),
      )..createSync(recursive: true);
      final configFile = File(
        p.join(pluginRoot.path, '.dart_tool', 'package_config.json'),
      );
      final config = jsonDecode(configFile.readAsStringSync()) as Map;
      final packages = [
        for (final entry in config['packages'] as List)
          <String, dynamic>{
            ...entry as Map<String, dynamic>,
            'rootUri': configFile.uri
                .resolve(entry['rootUri'] as String)
                .toString(),
          },
      ];
      for (final dependency in dependencyPackages.entries) {
        final directory = Directory(
          p.join(host.path, 'modules', dependency.key),
        )..createSync(recursive: true);
        packages.add({
          'name': dependency.key,
          'rootUri': directory.uri.toString(),
          'packageUri': 'lib/',
          'languageVersion': '3.10',
        });
        _write(
          p.join(directory.path, 'pubspec.yaml'),
          'name: ${dependency.key}\nresolution: workspace\nenvironment:\n  sdk: ^3.10.0\n',
        );
        for (final file in dependency.value.entries) {
          _write(p.join(directory.path, file.key), file.value);
        }
      }
      packages.removeWhere((entry) => entry['name'] == 'ccrouter_contracts');
      packages.addAll([
        {
          'name': 'ccrouter_contracts',
          'rootUri': Directory(
            p.join(pluginRoot.parent.path, 'ccrouter_contracts'),
          ).uri.toString(),
          'packageUri': 'lib/',
          'languageVersion': '3.10',
        },
        {
          'name': 'e2e_host',
          'rootUri': host.uri.toString(),
          'packageUri': 'lib/',
          'languageVersion': '3.10',
        },
        {
          'name': 'ccrouter_e2e_plugin',
          'rootUri': pluginPackage.uri.toString(),
          'packageUri': 'lib/',
          'languageVersion': '3.10',
        },
      ]);
      for (final directory in [loader, host]) {
        _write(
          p.join(directory.path, '.dart_tool', 'package_config.json'),
          jsonEncode({'configVersion': 2, 'packages': packages}),
        );
      }
      _write(
        p.join(loader.path, 'bin', 'plugin.dart'),
        File(
          p.join(
            pluginRoot.path,
            'tools',
            'analyzer_plugin',
            'bin',
            'plugin.dart',
          ),
        ).readAsStringSync(),
      );
      _write(
        p.join(host.path, 'pubspec.yaml'),
        'name: e2e_host\nenvironment:\n  sdk: ^3.10.0\ndependencies:\n  ccrouter_contracts: any\n'
        '${dependencyPackages.isEmpty ? '' : 'workspace:\n${dependencyPackages.keys.map((name) => '  - modules/$name\n').join()}'}',
      );
      _write(
        p.join(host.path, 'analysis_options.yaml'),
        'analyzer:\n  plugins:\n    - ccrouter_e2e_plugin\n',
      );
      for (final entry in sources.entries) {
        _write(p.join(host.path, entry.key), entry.value);
      }
      // Use the SDK's official JIT Server snapshot. The AOT Server's second
      // context checks a pubspec timestamp even for a manifest-free loader;
      // that packaging/cache path belongs to the separate bootstrap smoke.
      final serverSnapshot = p.join(
        p.dirname(Platform.resolvedExecutable),
        'snapshots',
        'analysis_server.dart.snapshot',
      );
      if (!File(serverSnapshot).existsSync()) {
        throw StateError(
          'SDK Analysis Server snapshot is unavailable: $serverSnapshot',
        );
      }
      final process = await Process.start(Platform.resolvedExecutable, [
        serverSnapshot,
        '--protocol=${lsp ? 'lsp' : 'analyzer'}',
        '--suppress-analytics',
        '--cache=${p.join(root.path, 'cache')}',
      ], workingDirectory: host.path);
      final session = AnalysisServerSession._(root, host, process, lsp);
      session._subscriptions.add(
        lsp
            ? process.stdout.listen(session._receiveBytes)
            : process.stdout
                  .transform(utf8.decoder)
                  .transform(const LineSplitter())
                  .listen(session._receive),
      );
      session._subscriptions.add(
        process.stderr
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) {
              session._stderr.add(line);
              if (session._stderr.length > 80) session._stderr.removeAt(0);
            }),
      );
      unawaited(
        process.exitCode.then((code) {
          if (!session._closing) session._recordFailure('Server exited: $code');
        }),
      );
      try {
        if (lsp) {
          await session.request('initialize', {
            'processId': pid,
            'rootUri': host.uri.toString(),
            'capabilities': {
              'textDocument': {
                'codeAction': {
                  'codeActionLiteralSupport': {
                    'codeActionKind': {
                      'valueSet': ['quickfix'],
                    },
                  },
                },
              },
            },
          });
          session.notify('initialized', {});
        } else {
          await session.request('analysis.setAnalysisRoots', {
            'included': [host.path],
            'excluded': <String>[],
          });
          await session.request('analysis.setPriorityFiles', {
            'files': sources.keys
                .where((key) => key.endsWith('.dart'))
                .map((key) => p.join(host.path, key))
                .toList(),
          });
        }
        return session;
      } catch (_) {
        await session.close();
        rethrow;
      }
    } catch (_) {
      if (root.existsSync()) root.deleteSync(recursive: true);
      rethrow;
    }
  }

  static void _write(String path, String content) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  String path(String relative) => p.normalize(p.join(host.path, relative));

  void write(String relative, String content) =>
      _write(path(relative), content);

  void _receiveBytes(List<int> bytes) {
    _buffer.addAll(bytes);
    while (true) {
      var end = -1;
      for (var i = 0; i + 3 < _buffer.length; i++) {
        if (_buffer[i] == 13 &&
            _buffer[i + 1] == 10 &&
            _buffer[i + 2] == 13 &&
            _buffer[i + 3] == 10) {
          end = i;
          break;
        }
      }
      if (end < 0) return;
      final header = ascii.decode(_buffer.sublist(0, end));
      final length = int.parse(
        RegExp(
          r'Content-Length: (\d+)',
          caseSensitive: false,
        ).firstMatch(header)!.group(1)!,
      );
      if (_buffer.length < end + 4 + length) return;
      final payload = utf8.decode(_buffer.sublist(end + 4, end + 4 + length));
      _buffer = _buffer.sublist(end + 4 + length);
      _receive(payload);
    }
  }

  void _send(Map<String, dynamic> message) {
    if (lsp) {
      final payload = utf8.encode(jsonEncode({'jsonrpc': '2.0', ...message}));
      process.stdin.add(
        ascii.encode('Content-Length: ${payload.length}\r\n\r\n'),
      );
      process.stdin.add(payload);
    } else {
      process.stdin.writeln(jsonEncode(message));
    }
  }

  void notify(String method, Map<String, dynamic> params) =>
      _send({'method': method, 'params': params});

  void _receive(String line) {
    try {
      final message = jsonDecode(line) as Map<String, dynamic>;
      if (lsp && message['method'] != null) {
        final method = message['method'];
        final params = message['params'] as Map? ?? {};
        if (message['id'] != null) {
          _send({
            'id': message['id'],
            'result': method == 'workspace/configuration'
                ? [for (final _ in params['items'] as List) <String, dynamic>{}]
                : null,
          });
        } else if (method == 'textDocument/publishDiagnostics') {
          final file = Uri.parse(params['uri'] as String).toFilePath();
          diagnostics[file] = (params['diagnostics'] as List)
              .cast<Map<String, dynamic>>();
          revisions[file] = (revisions[file] ?? 0) + 1;
        } else if ((method == 'window/logMessage' ||
                method == 'window/showMessage') &&
            params['type'] == 1) {
          _recordFailure('$message');
        }
        return;
      }
      final id = message['id'];
      if (id is String) {
        final completer = _pending.remove(id);
        if (message['error'] != null) {
          completer?.completeError(StateError('$message'));
        } else {
          final result = message['result'];
          completer?.complete(
            result is Map ? result.cast<String, dynamic>() : {'value': result},
          );
        }
      }
      final event = message['event'];
      if (event == 'server.error' || event == 'server.pluginError') {
        _recordFailure(jsonEncode(message));
      } else if (event == 'analysis.errors') {
        final params = message['params'] as Map;
        final file = params['file'] as String;
        diagnostics[file] = (params['errors'] as List)
            .cast<Map<String, dynamic>>();
        revisions[file] = (revisions[file] ?? 0) + 1;
      }
    } catch (error) {
      _recordFailure('Protocol error: $error');
    }
  }

  Future<Map<String, dynamic>> request(
    String method,
    Map<String, dynamic> params, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final id = '${++_nextId}';
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    _send({'id': id, 'method': method, 'params': params});
    try {
      return await completer.future.timeout(timeout);
    } finally {
      _pending.remove(id);
    }
  }

  Future<void> overlay(String relative, String? content) async {
    await request('analysis.updateContent', {
      'files': {
        path(relative): content == null
            ? {'type': 'remove'}
            : {'type': 'add', 'content': content},
      },
    });
  }

  /// Require a new notification and a stable result, not an initial empty
  /// Dart-only diagnostic batch before the plugin starts.
  Future<List<Map<String, dynamic>>> waitFor(
    String relative,
    bool Function(List<Map<String, dynamic>>) predicate, {
    int after = 0,
  }) async {
    final file = path(relative);
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    DateTime? stableSince;
    while (DateTime.now().isBefore(deadline)) {
      checkHealthy();
      final errors = diagnostics[file];
      if ((revisions[file] ?? 0) > after &&
          errors != null &&
          predicate(errors)) {
        stableSince ??= DateTime.now();
        if (DateTime.now().difference(stableSince) >
            const Duration(milliseconds: 600))
          return errors;
      } else {
        stableSince = null;
      }
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    throw StateError(
      'Diagnostics timed out for $relative: ${diagnostics[file]}\n${_stderr.join('\n')}',
    );
  }

  void checkHealthy() {
    if (_failures.isNotEmpty) throw StateError(_failures.join('\n'));
  }

  void _recordFailure(String message) {
    if (_failures.length < 20) {
      _failures.add(
        message.length > 8192 ? message.substring(0, 8192) : message,
      );
    }
    for (final pending in _pending.values) {
      if (!pending.isCompleted) pending.completeError(StateError(message));
    }
    _pending.clear();
  }

  Future<void> close() async {
    if (_closing) return;
    _closing = true;
    try {
      await request(
        lsp ? 'shutdown' : 'server.shutdown',
        {},
        timeout: const Duration(seconds: 5),
      );
      if (lsp) notify('exit', {});
      final code = await process.exitCode.timeout(const Duration(seconds: 5));
      if (code != 0) _recordFailure('Shutdown exit code: $code');
    } on Object catch (error) {
      _recordFailure('Server required forced cleanup: $error');
      process.kill(ProcessSignal.sigkill);
      await process.exitCode;
    } finally {
      try {
        await process.stdin.close();
      } finally {
        for (final subscription in _subscriptions) {
          await subscription.cancel();
        }
        for (final pending in _pending.values) {
          if (!pending.isCompleted)
            pending.completeError(StateError('Server session closed'));
        }
        _pending.clear();
        diagnostics.clear();
        revisions.clear();
        _buffer.clear();
        if (root.existsSync()) root.deleteSync(recursive: true);
      }
    }
    checkHealthy();
  }
}
