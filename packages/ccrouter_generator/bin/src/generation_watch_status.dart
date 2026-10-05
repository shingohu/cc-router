part of '../ccrouter_generator.dart';

const _generationWatchStatusSchemaVersion = 1;
const _generationWatchStatusPollInterval = Duration(milliseconds: 200);

/// Publishes a bounded local view of one watch without affecting generation.
final class _GenerationWatchStatusTracker {
  _GenerationWatchStatusTracker({
    required this.hostRoot,
    required this.buildRoot,
    required String? leasePath,
  }) : _leasePath = leasePath == null ? null : File(leasePath).absolute.path,
       _startedAt = DateTime.now().toUtc().toIso8601String();

  final Directory hostRoot;
  final Directory buildRoot;
  final String? _leasePath;
  final String _startedAt;

  bool _watchStarted = false;
  bool _disabled = false;
  bool _warned = false;
  int _cycle = 0;
  int? _lastBuildElapsedMs;
  int? _lastBuildRunnerMs;
  int? _lastAggregationElapsedMs;
  String? _lastCycleMode;
  String? _lastSucceededAt;
  String? _lastFailureAt;
  String? _failureStage;

  /// Records one public watch event and persists only developer-useful states.
  Future<void> observe(
    String type, {
    required String timestamp,
    required Map<String, Object?> data,
  }) async {
    if (type == 'watchStarted') _watchStarted = true;
    if (type == 'buildStarted') {
      _cycle++;
      _failureStage = null;
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
    }
    if (type == 'failed') {
      _lastFailureAt = timestamp;
      _failureStage = data['stage'] as String?;
      if (_failureStage == 'build') {
        _lastBuildElapsedMs = data['elapsedMs'] as int?;
        final report = data['buildRunner'];
        if (report is Map) {
          _lastBuildRunnerMs = report['durationMs'] as int?;
        }
      }
    }
    if (!_shouldPersist(type) || _disabled) return;

    final state = _stateFor(type);
    final active = switch (type) {
      'starting' ||
      'watchStarted' ||
      'buildStarted' ||
      'buildSucceeded' ||
      'aggregationStarted' ||
      'aggregationSucceeded' ||
      'ready' => true,
      'failed' => _watchStarted && data['stage'] != 'watch-exit',
      _ => false,
    };
    final document = <String, Object?>{
      'schemaVersion': _generationWatchStatusSchemaVersion,
      'state': state,
      'active': active,
      'lastEvent': type,
      'pid': pid,
      'cycle': _cycle,
      'startedAt': _startedAt,
      'updatedAt': timestamp,
      'hostRoot': hostRoot.path,
      'buildRoot': buildRoot.path,
      'managedByLease': _leasePath != null,
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
    };
    try {
      await _writeIfChanged(
        _generationWatchStatusFile(hostRoot),
        '${const JsonEncoder.withIndent('  ').convert(document)}\n',
      );
    } on Object catch (error) {
      _disabled = true;
      if (_warned) return;
      _warned = true;
      _commandStderr.writeln(
        'warning: CCRouter watch status updates are disabled: $error',
      );
    }
  }

  bool _shouldPersist(String type) => switch (type) {
    'starting' ||
    'fallback' ||
    'succeeded' ||
    'watchStarted' ||
    'buildStarted' ||
    'aggregationStarted' ||
    'aggregationSucceeded' ||
    'ready' ||
    'failed' ||
    'stopped' => true,
    _ => false,
  };

  String _stateFor(String type) => switch (type) {
    'buildStarted' || 'buildSucceeded' => 'building',
    'aggregationStarted' => 'aggregating',
    'aggregationSucceeded' => 'succeeded',
    'watchStarted' => 'starting',
    'fallback' => 'fallback',
    'succeeded' || 'stopped' => 'stopped',
    _ => type,
  };
}

/// Runs the read-only human status or follow command for [hostRoot].
Future<void> _runGenerationWatchObservation(
  Directory hostRoot, {
  required bool follow,
}) async {
  final file = _generationWatchStatusFile(hostRoot);
  final initial = await _readGenerationWatchStatus(file);
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
              const {
                'stopped',
                'fallback',
                'failed',
                'stale',
              }.contains(observed['state'])) {
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
  final lockFile = File(
    path.join(
      buildRoot.path,
      '.dart_tool',
      'ccrouter',
      'v1',
      'watch',
      'owner.lock',
    ),
  );
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
    if (decoded is! Map ||
        decoded['schemaVersion'] != _generationWatchStatusSchemaVersion ||
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
    return decoded.cast<String, Object?>();
  } on Object {
    return null;
  }
}

void _writeGenerationWatchStatus(
  Map<String, Object?> status, {
  required File file,
  required Directory hostRoot,
}) {
  _commandStdout.writeln(
    'CCRouter watch status: ${status['active'] == true ? 'active' : 'inactive'}',
  );
  for (final entry in <String, Object?>{
    'state': status['state'],
    'recorded state': status['recordedState'],
    'last event': status['lastEvent'],
    'pid': status['pid'],
    'cycle': status['cycle'],
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
