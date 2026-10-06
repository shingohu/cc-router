import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import 'canonical_directory_identity.dart';
import 'flutter_run_watch_lease.dart';

/// Environment switch that bypasses only Flutter machine reload coordination.
const String ccrouterHotReloadGateKillSwitch =
    'CCROUTER_DISABLE_HOT_RELOAD_GATE';

/// Terminal result of waiting for watch to cover one Flutter reload request.
enum CCFlutterReloadGateOutcome {
  /// The current generated graph is safe for Flutter to consume.
  ready,

  /// Generation failed for the input revision requested by Flutter.
  failed,

  /// The Host topology changed and requires an explicit Hot Restart.
  hotRestartRequired,

  /// The active watch or its versioned status cannot prove completion.
  unavailable,

  /// The watch did not reach a matching terminal state within the bound.
  timedOut,
}

/// Immutable completion evidence returned by [CCFlutterReloadGate].
final class CCFlutterReloadGateResult {
  /// Creates one reload-gate result.
  const CCFlutterReloadGateResult({
    required this.outcome,
    required this.message,
    this.sessionId,
    this.diagnostics,
  });

  /// Final coordination outcome.
  final CCFlutterReloadGateOutcome outcome;

  /// Actionable text suitable for daemon error propagation.
  final String message;

  /// Watch session that supplied the accepted or rejected evidence.
  final String? sessionId;

  /// Bounded Generator diagnostics published by watch.
  final String? diagnostics;

  /// Whether Flutter may receive the original restart request.
  bool get mayProceed => outcome == CCFlutterReloadGateOutcome.ready;
}

/// Waits for versioned watch evidence without parsing build_runner output.
final class CCFlutterReloadGate {
  /// Creates a gate for one Host.
  const CCFlutterReloadGate({
    required this.hostRoot,
    this.observationWindow = const Duration(milliseconds: 150),
    this.pollInterval = const Duration(milliseconds: 50),
    this.timeout = const Duration(seconds: 30),
  });

  /// Host whose generated graph the Flutter process consumes.
  final Directory hostRoot;

  /// Brief window allowing the file watcher to publish the save preceding an
  /// IDE reload request.
  final Duration observationWindow;

  /// Bounded local status polling cadence.
  final Duration pollInterval;

  /// Maximum time one reload request may wait for generation.
  final Duration timeout;

  /// Waits until watch has completed every source revision observed while the
  /// request is pending.
  ///
  /// [acknowledgedHotRestartSessionId] is process-local evidence that this
  /// Flutter run already performed the restart required by that watch session.
  Future<CCFlutterReloadGateResult> wait({
    required bool fullRestart,
    String? acknowledgedHotRestartSessionId,
  }) async {
    final normalizedHost = canonicalDirectoryIdentity(hostRoot.path);
    final watch = Stopwatch()..start();
    var requiredInputRevision = 0;
    var stableSince = Duration.zero;
    String? previousIdentity;
    Map<String, Object?>? latest;
    while (watch.elapsed < timeout) {
      final status = await _readStatus();
      if (status == null) {
        await Future<void>.delayed(pollInterval);
        continue;
      }
      latest = status;
      final identity =
          '${status['sessionId']}|${status['eventRevision']}|'
          '${status['inputRevision']}|${status['lastEvent']}';
      if (identity != previousIdentity) {
        previousIdentity = identity;
        stableSince = watch.elapsed;
      }
      final statusHost = canonicalDirectoryIdentity(
        status['hostRoot'] as String,
      );
      if (!path.equals(statusHost, normalizedHost)) {
        return const CCFlutterReloadGateResult(
          outcome: CCFlutterReloadGateOutcome.unavailable,
          message: 'CCRouter watch status belongs to a different Host.',
        );
      }
      final inputRevision = status['inputRevision'] as int;
      if (inputRevision > requiredInputRevision) {
        requiredInputRevision = inputRevision;
      }
      final sessionId = status['sessionId'] as String;
      final hotRestartRequired =
          status['hotRestartRequired'] == true &&
          acknowledgedHotRestartSessionId != sessionId;
      if (hotRestartRequired && !fullRestart) {
        return CCFlutterReloadGateResult(
          outcome: CCFlutterReloadGateOutcome.hotRestartRequired,
          message:
              'CCRouter Host topology changed. Use Hot Restart before '
              'continuing; Hot Reload would retain the old initialized graph.',
          sessionId: sessionId,
        );
      }

      final lastEvent = status['lastEvent'] as String;
      final failedInputRevision = status['failedInputRevision'] as int?;
      if (lastEvent == 'failed' &&
          failedInputRevision != null &&
          failedInputRevision >= requiredInputRevision) {
        return CCFlutterReloadGateResult(
          outcome: CCFlutterReloadGateOutcome.failed,
          message:
              'CCRouter generation failed before Flutter reload '
              '(stage: ${status['failureStage'] ?? 'generation'}).',
          sessionId: sessionId,
          diagnostics: status['failureDiagnostics'] as String?,
        );
      }

      final completedInputRevision = status['completedInputRevision'] as int?;
      final resolutionMatched = status['cycleResolutionState'] == 'matched';
      final completed =
          completedInputRevision != null &&
          completedInputRevision >= requiredInputRevision &&
          resolutionMatched &&
          const <String>{'aggregationSucceeded', 'ready'}.contains(lastEvent);
      if (completed && watch.elapsed - stableSince >= observationWindow) {
        return CCFlutterReloadGateResult(
          outcome: CCFlutterReloadGateOutcome.ready,
          message:
              'CCRouter watch completed input revision '
              '$requiredInputRevision.',
          sessionId: sessionId,
        );
      }
      if (status['active'] != true) {
        return CCFlutterReloadGateResult(
          outcome: CCFlutterReloadGateOutcome.unavailable,
          message:
              'CCRouter watch stopped before the Flutter reload barrier '
              'completed.',
          sessionId: sessionId,
          diagnostics: status['failureDiagnostics'] as String?,
        );
      }
      await Future<void>.delayed(pollInterval);
    }
    return CCFlutterReloadGateResult(
      outcome: CCFlutterReloadGateOutcome.timedOut,
      message:
          'CCRouter watch did not complete input revision '
          '$requiredInputRevision within ${timeout.inSeconds}s.',
      sessionId: latest?['sessionId'] as String?,
      diagnostics: latest?['failureDiagnostics'] as String?,
    );
  }

  Future<Map<String, Object?>?> _readStatus() async {
    final file = File(
      path.join(
        hostRoot.path,
        '.dart_tool',
        'ccrouter',
        'v1',
        'watch',
        'status.json',
      ),
    );
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map ||
          decoded['schemaVersion'] != 1 ||
          decoded['active'] is! bool ||
          decoded['hostRoot'] is! String ||
          decoded['sessionId'] is! String ||
          decoded['lastEvent'] is! String ||
          decoded['inputRevision'] is! int) {
        return null;
      }
      return decoded.cast<String, Object?>();
    } on Object {
      return null;
    }
  }
}

/// Proxies only Flutter machine stdin so reload requests can cross the gate.
final class CCFlutterMachineRunProxy {
  /// Creates a proxy for one original Flutter entrypoint and Host.
  CCFlutterMachineRunProxy({
    required this.originalFlutter,
    required this.flutterArguments,
    required this.hostRoot,
    this.watchLease,
    this.abortSignal,
    Map<String, String>? environment,
  }) : environment = environment ?? Platform.environment;

  /// Original SDK entrypoint preserved by Pub Hook installation.
  final String originalFlutter;

  /// Exact arguments originally passed to the Flutter wrapper.
  final List<String> flutterArguments;

  /// CCRouter Host associated with this Flutter run.
  final Directory hostRoot;

  /// Optional wrapper-created lease owned for the child lifetime.
  final File? watchLease;

  /// Optional supervisor failure that terminates the Flutter child.
  final Future<void>? abortSignal;

  /// Process environment used for the kill switch and child launch.
  final Map<String, String> environment;

  String? _acknowledgedHotRestartSessionId;
  final Map<Object, String> _pendingHotRestartSessions = <Object, String>{};

  /// Starts Flutter and relays machine traffic until the child exits.
  Future<int> run() async {
    final process = await Process.start(
      originalFlutter,
      flutterArguments,
      workingDirectory: Directory.current.path,
      environment: environment,
      runInShell: Platform.isWindows,
    );
    Object? heartbeatFailure;
    final leaseOwner = watchLease == null
        ? null
        : CCFlutterRunWatchLeaseOwner(watchLease!);
    try {
      await leaseOwner?.start(
        onFailure: (error, _) {
          heartbeatFailure ??= error;
          process.kill();
        },
      );
    } on Object {
      process.kill();
      await process.exitCode;
      await leaseOwner?.close();
      rethrow;
    }
    final stdoutDone = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_forwardFlutterLine)
        .asFuture<void>();
    final stderrDone = process.stderr.listen(stderr.add).asFuture<void>();
    final signalSubscriptions = <StreamSubscription<ProcessSignal>>[];
    for (final signal in <ProcessSignal>[
      ProcessSignal.sigint,
      if (!Platform.isWindows) ProcessSignal.sigterm,
    ]) {
      try {
        signalSubscriptions.add(
          signal.watch().listen((_) {
            if (Platform.isWindows) {
              process.kill();
            } else {
              process.kill(signal);
            }
          }),
        );
      } on Object {
        // A platform may not expose every signal.
      }
    }
    final inputSubscription = stdin
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .asyncMap((line) => _forwardMachineLine(process, line))
        .listen(
          (_) {},
          onError: (_) {
            process.kill();
          },
          onDone: () {
            unawaited(process.stdin.close());
          },
        );
    try {
      final childExitCode = abortSignal == null
          ? await process.exitCode
          : await Future.any<int>(<Future<int>>[
              process.exitCode,
              abortSignal!.then((_) async {
                process.kill();
                return process.exitCode;
              }),
            ]);
      if (heartbeatFailure != null) {
        stderr.writeln(
          'error: CCRouter Flutter-run watch lease heartbeat failed: '
          '$heartbeatFailure',
        );
        return 1;
      }
      return childExitCode;
    } finally {
      await inputSubscription.cancel();
      for (final subscription in signalSubscriptions) {
        await subscription.cancel();
      }
      await Future.wait<void>([stdoutDone, stderrDone]);
      await leaseOwner?.close();
    }
  }

  Future<void> _forwardMachineLine(Process process, String line) async {
    final request = _restartRequest(line);
    if (request == null ||
        environment[ccrouterHotReloadGateKillSwitch] == '1') {
      process.stdin.writeln(line);
      await process.stdin.flush();
      return;
    }
    final result = await CCFlutterReloadGate(hostRoot: hostRoot).wait(
      fullRestart: request.fullRestart,
      acknowledgedHotRestartSessionId: _acknowledgedHotRestartSessionId,
    );
    if (!result.mayProceed) {
      final detail = result.diagnostics == null
          ? result.message
          : '${result.message}\n${result.diagnostics}';
      stderr.writeln(detail);
      stdout.writeln(
        jsonEncode(<Object?>[
          <String, Object?>{'id': request.id, 'error': detail, 'trace': ''},
        ]),
      );
      return;
    }
    process.stdin.writeln(line);
    await process.stdin.flush();
    if (request.fullRestart && result.sessionId != null) {
      _pendingHotRestartSessions[request.id] = result.sessionId!;
    }
  }

  void _forwardFlutterLine(String line) {
    try {
      final decoded = jsonDecode(line);
      if (decoded is List && decoded.length == 1 && decoded.first is Map) {
        final response = (decoded.first as Map).cast<String, Object?>();
        final id = response['id'];
        final pendingSession = _pendingHotRestartSessions.remove(id);
        final result = response['result'];
        if (pendingSession != null &&
            response['error'] == null &&
            result is Map &&
            result['code'] == 0) {
          _acknowledgedHotRestartSessionId = pendingSession;
        }
      }
    } on Object {
      // Non-daemon output remains byte-content-equivalent line output.
    }
    stdout.writeln(line);
  }

  _CCFlutterRestartRequest? _restartRequest(String line) {
    try {
      final decoded = jsonDecode(line);
      if (decoded is! List || decoded.length != 1 || decoded.first is! Map) {
        return null;
      }
      final request = (decoded.first as Map).cast<String, Object?>();
      if (request['method'] != 'app.restart' || request['id'] == null) {
        return null;
      }
      final params = request['params'];
      if (params is! Map) return null;
      return _CCFlutterRestartRequest(
        id: request['id']!,
        fullRestart: params['fullRestart'] == true,
      );
    } on Object {
      return null;
    }
  }
}

final class _CCFlutterRestartRequest {
  const _CCFlutterRestartRequest({required this.id, required this.fullRestart});

  final Object id;
  final bool fullRestart;
}
