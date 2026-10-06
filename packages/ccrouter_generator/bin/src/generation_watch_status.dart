part of '../ccrouter_generator.dart';

const _generationWatchStatusSchemaVersion = 1;
const _generationWatchDiagnosticsSchemaVersion = 1;
const _generationWatchStatusPollInterval = Duration(milliseconds: 200);
const _generationWatchMirrorRepairInterval = Duration(seconds: 1);

/// Publishes a bounded local view of one watch without affecting generation.
final class _GenerationWatchStatusTracker {
  _GenerationWatchStatusTracker({
    required this.hostRoot,
    required this.buildRoot,
    required String? leasePath,
  }) : _leasePath = leasePath == null ? null : File(leasePath).absolute.path,
       _startedAt = DateTime.now().toUtc().toIso8601String(),
       _sessionId = '$pid-${DateTime.now().microsecondsSinceEpoch}';

  final Directory hostRoot;
  final Directory buildRoot;
  final String? _leasePath;
  final String _startedAt;
  String _sessionId;

  bool _watchStarted = false;
  bool _sessionReady = false;
  bool _disabled = false;
  bool _warned = false;
  bool _stableSessionDisabled = false;
  bool _stableSessionWarned = false;
  bool _diagnosticsDisabled = false;
  bool _diagnosticsWarned = false;
  String? _latestStatusContents;
  String? _latestDiagnosticsContents;
  Timer? _mirrorRepairTimer;
  Future<void> _mirrorRepairTail = Future<void>.value();
  int _sessionSequence = 0;
  int _cycle = 0;
  int _eventRevision = 0;
  int _inputRevision = 0;
  int _cycleInputRevision = 0;
  int? _completedInputRevision;
  int? _failedInputRevision;
  bool _hotRestartRequired = false;
  int? _lastBuildElapsedMs;
  int? _lastBuildRunnerMs;
  int? _lastAggregationElapsedMs;
  String? _lastCycleMode;
  String? _lastSucceededAt;
  String? _lastFailureAt;
  String? _failureStage;
  String? _failureDiagnostics;
  String? _cycleResolutionFingerprint;
  String? _completedResolutionFingerprint;
  String? _cycleResolutionState;
  int? _builderOwnerPid;

  /// Associates this Host status with the process owning build_runner.
  void setBuilderOwnerPid(int value) => _builderOwnerPid = value;

  /// Starts a distinct build_runner child session under the same watch lease.
  void beginNewSession() {
    _sessionSequence++;
    _sessionId =
        '$pid-${DateTime.now().microsecondsSinceEpoch}-$_sessionSequence';
    _sessionReady = false;
    _eventRevision = 0;
    _cycle = 0;
    _lastBuildElapsedMs = null;
    _lastBuildRunnerMs = null;
    _lastAggregationElapsedMs = null;
    _lastCycleMode = null;
    _lastSucceededAt = null;
    _lastFailureAt = null;
    _failureStage = null;
    _failureDiagnostics = null;
    _cycleResolutionFingerprint = null;
    _completedResolutionFingerprint = null;
    _cycleResolutionState = null;
    _cycleInputRevision = _inputRevision;
    _failedInputRevision = null;
  }

  /// Identity of the currently supervised build_runner child session.
  String get sessionId => _sessionId;

  /// Monotonic persisted event revision within the current child session.
  int get eventRevision => _eventRevision;

  /// Records one public watch event and persists only developer-useful states.
  Future<void> observe(
    String type, {
    required String timestamp,
    required Map<String, Object?> data,
  }) async {
    if (type == 'watchStarted') _watchStarted = true;
    if (type == 'ready') _sessionReady = true;
    if (type == 'inputChanged') {
      _inputRevision++;
      _failureStage = null;
      _failureDiagnostics = null;
    }
    if (type == 'sessionRestarting' && data['reason'] == 'topology-changed') {
      _hotRestartRequired = true;
    }
    if (type == 'buildStarted' || type == 'resolutionStarted') {
      _cycle++;
      _cycleInputRevision = _inputRevision;
      _failureStage = null;
      _failureDiagnostics = null;
      _failedInputRevision = null;
      _completedResolutionFingerprint = null;
      _cycleResolutionState = 'pending';
      _cycleResolutionFingerprint = await _captureResolutionFingerprint();
    }
    if (type == 'buildSucceeded') {
      _lastBuildElapsedMs = data['elapsedMs'] as int?;
      final report = data['buildRunner'];
      if (report is Map) {
        _lastBuildRunnerMs = report['durationMs'] as int?;
      }
    }
    if (type == 'aggregationSucceeded') {
      _lastAggregationElapsedMs = data['elapsedMs'] as int?;
      _lastCycleMode = data['cycleMode'] as String?;
      _lastSucceededAt = timestamp;
      _failureStage = null;
      _completedInputRevision = _cycleInputRevision;
      _failedInputRevision = null;
      await _completeResolutionFingerprint();
    }
    if (type == 'failed') {
      _lastFailureAt = timestamp;
      _failureStage = data['stage'] as String?;
      _failureDiagnostics = _boundedWatchFailureDiagnostics(
        switch (data['diagnostics']) {
          final String value when value.trim().isNotEmpty => value,
          _ => switch (data['error']) {
            final String value when value.trim().isNotEmpty => value,
            _ => null,
          },
        },
      );
      _failedInputRevision = _cycleInputRevision;
      await _completeResolutionFingerprint();
      if (_failureStage == 'build') {
        _lastBuildElapsedMs = data['elapsedMs'] as int?;
        final report = data['buildRunner'];
        if (report is Map) {
          _lastBuildRunnerMs = report['durationMs'] as int?;
        }
      }
    }
    if (type == 'invalidatedByClean') {
      _lastFailureAt = timestamp;
      _failureStage = data['stage'] as String?;
      _failureDiagnostics = data['reason'] as String?;
      _failedInputRevision = _inputRevision;
    }
    if (!_shouldPersist(type)) return;
    _eventRevision++;

    final state = _stateFor(type);
    final active = switch (type) {
      'starting' ||
      'sessionRestarting' ||
      'watchStarted' ||
      'inputChanged' ||
      'buildStarted' ||
      'resolutionStarted' ||
      'buildSucceeded' ||
      'aggregationStarted' ||
      'aggregationSucceeded' ||
      'ready' => true,
      'invalidatedByClean' => false,
      'failed' => _watchStarted && data['stage'] != 'watch-exit',
      _ => false,
    };
    final document = <String, Object?>{
      'schemaVersion': _generationWatchStatusSchemaVersion,
      'state': state,
      'active': active,
      'lastEvent': type,
      'pid': pid,
      'sessionId': _sessionId,
      'eventRevision': _eventRevision,
      'sessionReady': _sessionReady,
      'cycle': _cycle,
      'inputRevision': _inputRevision,
      'cycleInputRevision': _cycleInputRevision,
      if (_completedInputRevision != null)
        'completedInputRevision': _completedInputRevision,
      if (_failedInputRevision != null)
        'failedInputRevision': _failedInputRevision,
      'hotRestartRequired': _hotRestartRequired,
      'startedAt': _startedAt,
      'updatedAt': timestamp,
      'hostRoot': hostRoot.path,
      'buildRoot': buildRoot.path,
      'managedByLease': _leasePath != null,
      if (_builderOwnerPid != null) 'builderOwnerPid': _builderOwnerPid,
      if (_leasePath != null) 'leasePath': _leasePath,
      if (_lastBuildElapsedMs != null)
        'lastBuildElapsedMs': _lastBuildElapsedMs,
      if (_lastBuildRunnerMs != null) 'lastBuildRunnerMs': _lastBuildRunnerMs,
      if (_lastAggregationElapsedMs != null)
        'lastAggregationElapsedMs': _lastAggregationElapsedMs,
      if (_lastCycleMode != null) 'lastCycleMode': _lastCycleMode,
      if (_lastSucceededAt != null) 'lastSucceededAt': _lastSucceededAt,
      if (_lastFailureAt != null) 'lastFailureAt': _lastFailureAt,
      if (_failureStage != null) 'failureStage': _failureStage,
      if (_failureDiagnostics != null)
        'failureDiagnostics': _failureDiagnostics,
      if (_completedResolutionFingerprint != null)
        'resolutionFingerprint': _completedResolutionFingerprint,
      if (_cycleResolutionState != null)
        'cycleResolutionState': _cycleResolutionState,
    };
    final statusContents =
        '${const JsonEncoder.withIndent('  ').convert(document)}\n';
    _latestStatusContents = statusContents;
    if (!usesLegacyCCRouterCoordination() && !_stableSessionDisabled) {
      try {
        await publishCCRouterHostSession(
          hostRoot: hostRoot,
          buildRoot: buildRoot,
          status: document,
        );
      } on Object catch (error) {
        _stableSessionDisabled = true;
        if (!_stableSessionWarned) {
          _stableSessionWarned = true;
          _commandStderr.writeln(
            'warning: CCRouter stable Host session updates are disabled: '
            '$error',
          );
        }
      }
    }
    if (!_disabled) {
      try {
        await _writeIfChanged(
          _generationWatchStatusFile(hostRoot),
          statusContents,
        );
      } on Object catch (error) {
        _disabled = true;
        if (!_warned) {
          _warned = true;
          _commandStderr.writeln(
            'warning: CCRouter watch status updates are disabled: $error',
          );
        }
      }
    }
    await _publishStructuredDiagnostics(
      type: type,
      timestamp: timestamp,
      data: data,
    );
    _updateMirrorRepair(active);
  }

  /// Publishes diagnostics independently so observability stays fail-open.
  Future<void> _publishStructuredDiagnostics({
    required String type,
    required String timestamp,
    required Map<String, Object?> data,
  }) async {
    if (_diagnosticsDisabled ||
        !const <String>{
          'sessionRestarting',
          'buildStarted',
          'resolutionStarted',
          'aggregationSucceeded',
          'ready',
          'invalidatedByClean',
          'failed',
          'stopped',
        }.contains(type)) {
      return;
    }
    final raw = type == 'failed' ? data['structuredDiagnostics'] : null;
    final diagnostics = raw is List
        ? raw
              .whereType<Map>()
              .take(100)
              .map((item) {
                return item.cast<String, Object?>();
              })
              .toList(growable: false)
        : const <Map<String, Object?>>[];
    final document = <String, Object?>{
      'schemaVersion': _generationWatchDiagnosticsSchemaVersion,
      'hostRoot': hostRoot.path,
      'buildRoot': buildRoot.path,
      'sessionId': _sessionId,
      'eventRevision': _eventRevision,
      'cycle': _cycle,
      'lastEvent': type,
      'updatedAt': timestamp,
      if (_completedResolutionFingerprint != null)
        'resolutionFingerprint': _completedResolutionFingerprint,
      if (_cycleResolutionState != null)
        'cycleResolutionState': _cycleResolutionState,
      'diagnostics': diagnostics,
    };
    final diagnosticsContents =
        '${const JsonEncoder.withIndent('  ').convert(document)}\n';
    _latestDiagnosticsContents = diagnosticsContents;
    try {
      await _writeIfChanged(
        _generationWatchDiagnosticsFile(hostRoot),
        diagnosticsContents,
      );
    } on Object catch (error) {
      _diagnosticsDisabled = true;
      if (_diagnosticsWarned) return;
      _diagnosticsWarned = true;
      _commandStderr.writeln(
        'warning: CCRouter structured watch diagnostics are disabled: $error',
      );
    }
  }

  void _updateMirrorRepair(bool active) {
    if (!active) {
      _mirrorRepairTimer?.cancel();
      _mirrorRepairTimer = null;
      return;
    }
    _mirrorRepairTimer ??= Timer.periodic(
      _generationWatchMirrorRepairInterval,
      (_) {
        _mirrorRepairTail = _mirrorRepairTail.then(
          (_) => _restoreMissingMirrors(),
          onError: (Object _, StackTrace __) => _restoreMissingMirrors(),
        );
      },
    );
  }

  Future<void> _restoreMissingMirrors() async {
    final statusContents = _latestStatusContents;
    if (!_disabled &&
        statusContents != null &&
        !_generationWatchStatusFile(hostRoot).existsSync()) {
      try {
        await _writeIfChanged(
          _generationWatchStatusFile(hostRoot),
          statusContents,
        );
      } on Object catch (error) {
        _disabled = true;
        if (!_warned) {
          _warned = true;
          _commandStderr.writeln(
            'warning: CCRouter watch status updates are disabled: $error',
          );
        }
      }
    }
    final diagnosticsContents = _latestDiagnosticsContents;
    if (!_diagnosticsDisabled &&
        diagnosticsContents != null &&
        !_generationWatchDiagnosticsFile(hostRoot).existsSync()) {
      try {
        await _writeIfChanged(
          _generationWatchDiagnosticsFile(hostRoot),
          diagnosticsContents,
        );
      } on Object catch (error) {
        _diagnosticsDisabled = true;
        if (!_diagnosticsWarned) {
          _diagnosticsWarned = true;
          _commandStderr.writeln(
            'warning: CCRouter structured watch diagnostics are disabled: '
            '$error',
          );
        }
      }
    }
  }

  bool _shouldPersist(String type) => switch (type) {
    'starting' ||
    'sessionRestarting' ||
    'fallback' ||
    'succeeded' ||
    'watchStarted' ||
    'inputChanged' ||
    'buildStarted' ||
    'resolutionStarted' ||
    'aggregationStarted' ||
    'aggregationSucceeded' ||
    'ready' ||
    'invalidatedByClean' ||
    'failed' ||
    'stopped' => true,
    _ => false,
  };

  String _stateFor(String type) => switch (type) {
    'buildStarted' || 'buildSucceeded' => 'building',
    'inputChanged' => 'pending',
    'resolutionStarted' => 'resolving',
    'aggregationStarted' => 'aggregating',
    'aggregationSucceeded' => 'succeeded',
    'sessionRestarting' => 'restarting',
    'invalidatedByClean' => 'invalidatedByClean',
    'watchStarted' => 'starting',
    'fallback' => 'fallback',
    'succeeded' || 'stopped' => 'stopped',
    _ => type,
  };

  Future<void> _completeResolutionFingerprint() async {
    final started = _cycleResolutionFingerprint;
    if (started == null) {
      _completedResolutionFingerprint = null;
      _cycleResolutionState = 'unavailable';
      return;
    }
    final current = await _captureResolutionFingerprint();
    if (current == null) {
      _completedResolutionFingerprint = null;
      _cycleResolutionState = 'unavailable';
      return;
    }
    final matches = current == started;
    _completedResolutionFingerprint = matches ? current : null;
    _cycleResolutionState = matches ? 'matched' : 'changed';
  }

  Future<String?> _captureResolutionFingerprint() async {
    try {
      return await CCPubResolutionFingerprint.capture(
        hostRoot: hostRoot,
        buildRoot: buildRoot,
      );
    } on FileSystemException {
      return null;
    }
  }
}

String? _boundedWatchFailureDiagnostics(String? value) {
  if (value == null) return null;
  const maximumLines = 200;
  const maximumCharacters = 64 * 1024;
  final lines = const LineSplitter().convert(value.trim());
  final retained = <String>[];
  var characters = 0;
  for (final line in lines.reversed) {
    final cost = line.length + 1;
    if (retained.length >= maximumLines ||
        (retained.isNotEmpty && characters + cost > maximumCharacters)) {
      break;
    }
    if (retained.isEmpty && cost > maximumCharacters) {
      retained.add(line.substring(line.length - maximumCharacters));
      break;
    }
    retained.add(line);
    characters += cost;
  }
  return retained.reversed.join('\n');
}

/// Runs the read-only human status or follow command for [hostRoot].
Future<void> _runGenerationWatchObservation(
  Directory hostRoot, {
  required bool follow,
}) async {
  final file = _generationWatchStatusFile(hostRoot);
  var initial = await _readGenerationWatchStatus(file);
  var usedStableSession = false;
  if (initial == null && !usesLegacyCCRouterCoordination()) {
    initial = await _readStableGenerationWatchStatus(hostRoot);
    usedStableSession = initial != null;
  }
  if (initial == null) {
    _commandStderr.writeln(
      'CCRouter watch status is unavailable for ${hostRoot.path}.',
    );
    _commandStderr.writeln('Expected status file: ${file.path}');
    exitCode = 1;
    return;
  }
  if (!follow) {
    _writeGenerationWatchStatus(
      await _observeGenerationWatchLiveness(initial),
      file: file,
      hostRoot: hostRoot,
    );
    return;
  }

  _commandStdout.writeln(
    'Following CCRouter watch status for ${hostRoot.path}. Press Ctrl+C to stop.',
  );
  var previous = '';
  if (usedStableSession) {
    final observed = await _observeGenerationWatchLiveness(initial);
    _writeGenerationWatchFollowEvent(observed);
    if (observed['active'] != true &&
        _isTerminalGenerationWatchState(observed['state'])) {
      return;
    }
    previous =
        '${jsonEncode(initial)}\u0000${observed['active']}\u0000'
        '${observed['state']}';
  }
  final stop = Completer<void>();
  final subscriptions = <StreamSubscription<ProcessSignal>>[];
  for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm]) {
    try {
      subscriptions.add(
        signal.watch().listen((_) {
          if (!stop.isCompleted) stop.complete();
        }),
      );
    } on Object {
      // A platform may not expose every POSIX signal.
    }
  }
  try {
    while (!stop.isCompleted) {
      final contents = file.existsSync() ? await file.readAsString() : '';
      if (contents.isNotEmpty) {
        final status = _decodeGenerationWatchStatus(contents);
        if (status != null) {
          final observed = await _observeGenerationWatchLiveness(status);
          final observationKey =
              '$contents\u0000${observed['active']}\u0000'
              '${observed['state']}';
          if (observationKey != previous) {
            previous = observationKey;
            _writeGenerationWatchFollowEvent(observed);
          }
          if (observed['active'] != true &&
              _isTerminalGenerationWatchState(observed['state'])) {
            return;
          }
        }
      }
      await Future.any<void>([
        Future<void>.delayed(_generationWatchStatusPollInterval),
        stop.future,
      ]);
    }
  } finally {
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
  }
}

bool _isTerminalGenerationWatchState(Object? state) => const {
  'stopped',
  'fallback',
  'failed',
  'invalidatedByClean',
  'stale',
}.contains(state);

Future<Map<String, Object?>?> _readStableGenerationWatchStatus(
  Directory hostRoot,
) async {
  try {
    final context = CCProjectContext.resolve(hostRoot);
    final status = await readCCRouterHostSession(
      hostRoot: context.requestedRoot,
      buildRoot: context.resolutionRoot,
    );
    return status == null ? null : _validateGenerationWatchStatus(status);
  } on Object {
    return null;
  }
}

/// Verifies an active record against the OS-released watch ownership lock.
///
/// Abrupt termination can prevent the watch from publishing `stopped`. The
/// read-only observation commands never rewrite that historical record, but
/// they must not present it as a live process after its exclusive lock is gone.
Future<Map<String, Object?>> _observeGenerationWatchLiveness(
  Map<String, Object?> status,
) async {
  if (status['active'] != true || status['lastEvent'] == 'starting') {
    return status;
  }
  final buildRoot = Directory(status['buildRoot'] as String);
  if (await _generationWatchOwnershipIsHeld(buildRoot)) return status;
  return <String, Object?>{
    ...status,
    'active': false,
    'recordedState': status['state'],
    'state': 'stale',
  };
}

/// Returns false only when the existing owner lock can be acquired shared.
Future<bool> _generationWatchOwnershipIsHeld(Directory buildRoot) async {
  final lockFile = ccrouterWatchOwnerLockFile(buildRoot);
  if (!lockFile.existsSync()) return false;
  RandomAccessFile? opened;
  try {
    opened = await lockFile.open(mode: FileMode.append);
    await opened.lock(FileLock.shared);
    await opened.unlock();
    return false;
  } on FileSystemException {
    return true;
  } finally {
    await opened?.close();
  }
}

File _generationWatchStatusFile(Directory hostRoot) => File(
  path.join(
    hostRoot.path,
    '.dart_tool',
    'ccrouter',
    'v1',
    'watch',
    'status.json',
  ),
);

File _generationWatchDiagnosticsFile(Directory hostRoot) => File(
  path.join(
    hostRoot.path,
    '.dart_tool',
    'ccrouter',
    'v1',
    'watch',
    'diagnostics.json',
  ),
);

File _generationWatchLogFile(Directory hostRoot) => File(
  path.join(
    hostRoot.path,
    '.dart_tool',
    'ccrouter',
    'v1',
    'watch',
    'flutter-run.log',
  ),
);

Future<Map<String, Object?>?> _readGenerationWatchStatus(File file) async {
  if (!file.existsSync()) return null;
  try {
    return _decodeGenerationWatchStatus(await file.readAsString());
  } on FileSystemException {
    return null;
  }
}

Map<String, Object?>? _decodeGenerationWatchStatus(String contents) {
  try {
    final decoded = jsonDecode(contents);
    return decoded is Map
        ? _validateGenerationWatchStatus(decoded.cast<String, Object?>())
        : null;
  } on Object {
    return null;
  }
}

Map<String, Object?>? _validateGenerationWatchStatus(
  Map<String, Object?> decoded,
) {
  try {
    if (decoded['schemaVersion'] != _generationWatchStatusSchemaVersion ||
        decoded['state'] is! String ||
        decoded['active'] is! bool ||
        decoded['lastEvent'] is! String ||
        decoded['pid'] is! int ||
        decoded['cycle'] is! int ||
        decoded['startedAt'] is! String ||
        decoded['hostRoot'] is! String ||
        decoded['buildRoot'] is! String ||
        decoded['managedByLease'] is! bool ||
        decoded['updatedAt'] is! String) {
      return null;
    }
    return decoded;
  } on Object {
    return null;
  }
}

void _writeGenerationWatchStatus(
  Map<String, Object?> status, {
  required File file,
  required Directory hostRoot,
}) {
  final buildRoot = Directory(status['buildRoot'] as String);
  final coordination = usesLegacyCCRouterCoordination()
      ? legacyCCRouterWatchOwnerLockFile(buildRoot).parent
      : CCRouterCoordinationPaths.forBuildRoot(buildRoot).projectDirectory;
  _commandStdout.writeln(
    'CCRouter watch status: ${status['active'] == true ? 'active' : 'inactive'}',
  );
  for (final entry in <String, Object?>{
    'state': status['state'],
    'recorded state': status['recordedState'],
    'last event': status['lastEvent'],
    'pid': status['pid'],
    'cycle': status['cycle'],
    'input revision': status['inputRevision'],
    'completed input revision': status['completedInputRevision'],
    if (status['hotRestartRequired'] == true) 'hot restart required': true,
    'updated': status['updatedAt'],
    'build': status['lastBuildElapsedMs'] == null
        ? null
        : '${status['lastBuildElapsedMs']}ms',
    'build_runner': status['lastBuildRunnerMs'] == null
        ? null
        : '${status['lastBuildRunnerMs']}ms',
    'aggregation': status['lastAggregationElapsedMs'] == null
        ? null
        : '${status['lastAggregationElapsedMs']}ms',
    'cycle mode': status['lastCycleMode'],
    'failure stage': status['failureStage'],
    'coordination schema': usesLegacyCCRouterCoordination() ? 'v1' : 'v2',
    'coordination path': coordination.path,
    'status file': file.path,
    if (status['managedByLease'] == true)
      'log file': _generationWatchLogFile(hostRoot).path,
  }.entries) {
    if (entry.value != null) {
      _commandStdout.writeln('  ${entry.key}: ${entry.value}');
    }
  }
}

void _writeGenerationWatchFollowEvent(Map<String, Object?> status) {
  final fields = <String>[
    '${status['updatedAt']}',
    'state=${status['state']}',
    'event=${status['lastEvent']}',
    'cycle=${status['cycle']}',
    if (status['inputRevision'] case final int value) 'input=$value',
    if (status['completedInputRevision'] case final int value)
      'completed_input=$value',
    if (status['hotRestartRequired'] == true) 'hot_restart_required=true',
    if (status['lastBuildElapsedMs'] case final int value) 'build=${value}ms',
    if (status['lastBuildRunnerMs'] case final int value)
      'build_runner=${value}ms',
    if (status['lastAggregationElapsedMs'] case final int value)
      'aggregation=${value}ms',
    if (status['lastCycleMode'] case final String value) 'mode=$value',
    if (status['failureStage'] case final String value) 'failure=$value',
  ];
  _commandStdout.writeln(fields.join(' '));
}
