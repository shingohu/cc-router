part of '../ccrouter_generator.dart';

const _watchCycleEnvironment = 'CCROUTER_WATCH_CYCLE';
const _watchLockEnvironment = 'CCROUTER_WATCH_LOCK_HELD';
const _watchKillSwitch = 'CCROUTER_DISABLE_BUILD_WATCH';
const _watchCycleOptimizationKillSwitch =
    'CCROUTER_DISABLE_WATCH_CYCLE_OPTIMIZATION';
const _buildRunnerSuccessPattern = 'Built with build_runner';
const _buildRunnerFailurePattern = 'Failed to build with build_runner';

bool get _isWatchAggregationCycle =>
    Platform.environment[_watchCycleEnvironment] == '1';

bool get _watchOwnsGenerationLock =>
    _isWatchAggregationCycle &&
    Platform.environment[_watchLockEnvironment] == '1';

bool get _usesOptimizedWatchCycle =>
    _isWatchAggregationCycle &&
    Platform.environment[_watchCycleOptimizationKillSwitch] != '1';

/// Keeps build_runner's AOT entrypoint and Analyzer graph alive for one root.
Future<void> _runGenerationWatch({
  required Directory hostRoot,
  required _BuildContext buildContext,
  required _Arguments parsed,
}) async {
  final events = _GenerationWatchEvents(
    machine: parsed.machine,
    buildRoot: buildContext.root,
    hostRoot: hostRoot,
  );
  events.emit('starting', data: {'mode': 'auto'});

  if (Platform.environment[_watchKillSwitch] == '1') {
    events.emit('fallback', data: {'reason': 'kill-switch'});
    final fallback = await _runWatchGenerationSubprocess(
      hostRoot: hostRoot,
      buildRoot: buildContext.root,
      watchCycle: false,
      lockHeld: false,
    );
    events.emit(
      fallback.succeeded ? 'succeeded' : 'failed',
      data: fallback.toEventData(),
    );
    exitCode = fallback.exitCode;
    return;
  }

  final workspaceWatch = Stopwatch()..start();
  late final CCPackageWorkspace workspace;
  try {
    workspace = await CCPackageWorkspace.load(
      buildRoot: buildContext.root,
      hostRoot: hostRoot,
      workspace: buildContext.workspace,
    );
  } on Object catch (error) {
    events.emit('failed', data: {'stage': 'workspace', 'error': '$error'});
    exitCode = 1;
    return;
  }
  final targets =
      workspace.packages.values
          .where(
            (package) => package.writable && package.declaresGenerationIntent,
          )
          .map((package) => package.name)
          .toList()
        ..sort();
  if (targets.isEmpty) {
    events.emit(
      'failed',
      data: {
        'stage': 'target-resolution',
        'error': 'No writable CCRouter Builder Packages were found.',
      },
    );
    exitCode = 1;
    return;
  }
  workspaceWatch.stop();
  events.emit(
    'targetsResolved',
    data: {
      'elapsedMs': workspaceWatch.elapsedMilliseconds,
      'packages': targets,
    },
  );

  final protectionWatch = Stopwatch()..start();
  final targetRoots = <Directory>[
    for (final name in targets) workspace.packages[name]!.root,
  ];
  final protectedOutputs = <_GeneratedArtifactsSnapshot>[
    await _GeneratedArtifactsSnapshot.captureOutside(
      buildContext.root,
      targetRoots,
    ),
    for (final package in workspace.packages.values)
      if (!package.writable && !_isWithin(buildContext.root, package.root))
        await _GeneratedArtifactsSnapshot.capture(package.root),
  ];
  protectionWatch.stop();

  final command = await _buildRunnerCommand(buildContext.root, 'watch');
  final arguments = <String>[
    ...command.skip(1),
    '--verbose-durations',
    if (buildContext.workspace) '--workspace',
    for (final package in targets) ...[
      '--build-filter',
      'asset:$package/lib/**',
      '--build-filter',
      'asset:$package/ccrouter_generated/**',
    ],
  ];
  final generationLock = await _GenerationLock.acquire(buildContext.root);
  var cycleSnapshot = await _GeneratedArtifactsSnapshot.capture(
    buildContext.root,
  );
  final processWatch = Stopwatch()..start();
  late final Process process;
  try {
    process = await Process.start(
      command.first,
      arguments,
      workingDirectory: buildContext.root.path,
    );
  } on Object catch (error) {
    await generationLock.release();
    events.emit('failed', data: {'stage': 'watch-start', 'error': '$error'});
    exitCode = 1;
    return;
  }
  events.emit(
    'watchStarted',
    data: {
      'elapsedMs': processWatch.elapsedMilliseconds,
      'protectionSnapshotMs': protectionWatch.elapsedMilliseconds,
    },
  );
  events.emit('buildStarted', data: {'initial': true});

  final stop = Completer<void>();
  final signalSubscriptions = <StreamSubscription<ProcessSignal>>[];
  void requestStop() {
    if (stop.isCompleted) return;
    stop.complete();
    process.kill(ProcessSignal.sigterm);
  }

  for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm]) {
    try {
      signalSubscriptions.add(signal.watch().listen((_) => requestStop()));
    } on Object {
      // A platform may not expose every POSIX signal.
    }
  }
  Timer? leaseTimer;
  if (parsed.watchLeasePath case final leasePath?) {
    final lease = File(leasePath).absolute;
    leaseTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!lease.existsSync()) requestStop();
    });
  }

  final lines = StreamController<_BuildRunnerWatchLine>();
  final outputSubscriptions = <StreamSubscription<String>>[
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => lines.add(_BuildRunnerWatchLine(line))),
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => lines.add(_BuildRunnerWatchLine(line))),
  ];
  final iterator = StreamIterator(lines.stream);
  var buildWatch = Stopwatch()..start();
  var initialBuild = true;
  var readyEmitted = false;
  final failureTail = <String>[];
  try {
    while (!stop.isCompleted) {
      final hasLine = await Future.any<bool>([
        iterator.moveNext(),
        stop.future.then((_) => false),
        process.exitCode.then((_) => false),
      ]);
      if (!hasLine || stop.isCompleted) break;
      final line = _stripAnsi(iterator.current.text);
      if (line.trim().isNotEmpty) {
        stderr.writeln('build_runner: $line');
        failureTail.add(line);
        if (failureTail.length > 30) failureTail.removeAt(0);
      }
      if (line.contains('Starting build #')) {
        buildWatch = Stopwatch()..start();
        events.emit('buildStarted', data: {'initial': false});
        continue;
      }
      final succeeded = line.contains(_buildRunnerSuccessPattern);
      final failed = line.contains(_buildRunnerFailurePattern);
      if (!succeeded && !failed) continue;

      final restoreWatch = Stopwatch()..start();
      for (final snapshot in protectedOutputs) {
        await snapshot.restore();
      }
      restoreWatch.stop();
      final buildElapsed = buildWatch.elapsedMilliseconds;
      if (failed) {
        await cycleSnapshot.restore();
        events.emit(
          'failed',
          data: {
            'stage': 'build',
            'initial': initialBuild,
            'elapsedMs': buildElapsed,
            'reportedDuration': _reportedBuildDuration(line),
            'protectionRestoreMs': restoreWatch.elapsedMilliseconds,
            'diagnostics': failureTail.join('\n'),
          },
        );
        cycleSnapshot = await _GeneratedArtifactsSnapshot.capture(
          buildContext.root,
        );
        failureTail.clear();
        initialBuild = false;
        continue;
      }

      events.emit(
        'buildSucceeded',
        data: {
          'initial': initialBuild,
          'elapsedMs': buildElapsed,
          'reportedDuration': _reportedBuildDuration(line),
          'protectionRestoreMs': restoreWatch.elapsedMilliseconds,
        },
      );
      events.emit('aggregationStarted', data: {'initial': initialBuild});
      final aggregation = await _runWatchGenerationSubprocess(
        hostRoot: hostRoot,
        buildRoot: buildContext.root,
        watchCycle: true,
        lockHeld: true,
      );
      events.emit(
        aggregation.succeeded ? 'aggregationSucceeded' : 'failed',
        data: {
          'stage': 'aggregation',
          'initial': initialBuild,
          ...aggregation.toEventData(),
        },
      );
      cycleSnapshot = await _GeneratedArtifactsSnapshot.capture(
        buildContext.root,
      );
      if (!readyEmitted && aggregation.succeeded) {
        events.emit('ready');
        readyEmitted = true;
      }
      initialBuild = false;
      failureTail.clear();
    }
  } finally {
    leaseTimer?.cancel();
    for (final subscription in signalSubscriptions) {
      await subscription.cancel();
    }
    for (final subscription in outputSubscriptions) {
      await subscription.cancel();
    }
    await iterator.cancel();
    await lines.close();
    final processCode = await process.exitCode;
    await generationLock.release();
    if (processCode != 0 && !stop.isCompleted) {
      exitCode = 1;
      events.emit(
        'failed',
        data: {
          'stage': 'watch-exit',
          'exitCode': processCode,
          'diagnostics': failureTail.join('\n'),
        },
      );
    }
    events.emit('stopped');
  }
}

/// Uses Pub's cached executable snapshot without resolving dependencies again.
Future<List<String>> _buildRunnerCommand(
  Directory buildRoot,
  String command,
) async {
  final snapshotDirectory = Directory(
    path.join(buildRoot.path, '.dart_tool', 'pub', 'bin', 'build_runner'),
  );
  if (snapshotDirectory.existsSync()) {
    final sdkVersion = Platform.version.split(' ').first;
    final snapshots = snapshotDirectory
        .listSync(followLinks: false)
        .whereType<File>()
        .where(
          (file) =>
              path.basename(file.path) ==
              'build_runner.dart-$sdkVersion.snapshot',
        )
        .toList();
    snapshots.sort(
      (left, right) =>
          right.lastModifiedSync().compareTo(left.lastModifiedSync()),
    );
    if (snapshots.isNotEmpty) {
      return [Platform.resolvedExecutable, snapshots.first.path, command];
    }
  }

  final packageConfig = File(
    path.join(buildRoot.path, '.dart_tool', 'package_config.json'),
  );
  final decoded = jsonDecode(await packageConfig.readAsString());
  if (decoded is! Map || decoded['packages'] is! List) {
    throw const FormatException('Invalid package_config.json.');
  }
  for (final entry in decoded['packages'] as List) {
    if (entry is! Map || entry['name'] != 'build_runner') continue;
    final rootUri = entry['rootUri'];
    if (rootUri is! String) break;
    final packageRoot = packageConfig.uri.resolve(rootUri).toFilePath();
    final entrypoint = File(path.join(packageRoot, 'bin', 'build_runner.dart'));
    if (entrypoint.existsSync()) {
      return [Platform.resolvedExecutable, entrypoint.path, command];
    }
  }
  throw const FileSystemException(
    'Unable to resolve the build_runner entrypoint.',
  );
}

Future<_WatchGenerationResult> _runWatchGenerationSubprocess({
  required Directory hostRoot,
  required Directory buildRoot,
  required bool watchCycle,
  required bool lockHeld,
}) async {
  final stopwatch = Stopwatch()..start();
  final environment = <String, String>{...Platform.environment};
  if (watchCycle) environment[_watchCycleEnvironment] = '1';
  if (lockHeld) environment[_watchLockEnvironment] = '1';
  final script = Platform.script;
  final directEntrypoint = script.scheme == 'file'
      ? File(script.toFilePath()).absolute
      : null;
  final arguments = <String>[
    if (directEntrypoint == null || !directEntrypoint.existsSync()) ...[
      'run',
      '--verbosity=error',
      'ccrouter_generator:ccrouter',
    ] else
      directEntrypoint.path,
    'generate',
    hostRoot.path,
    '--profile',
  ];
  final result = await Process.run(
    Platform.resolvedExecutable,
    arguments,
    workingDirectory: buildRoot.path,
    environment: environment,
  );
  stopwatch.stop();
  final output = '${result.stdout}';
  final errors = '${result.stderr}';
  Map<String, Object?>? trace;
  Map<String, Object?>? outputDelta;
  for (final line in const LineSplitter().convert(output)) {
    if (line.startsWith('CCRouter profile trace=')) {
      trace = _decodeWatchObject(
        line.substring('CCRouter profile trace='.length),
      );
    } else if (line.startsWith('CCRouter profile output-delta=')) {
      outputDelta = _decodeWatchObject(
        line.substring('CCRouter profile output-delta='.length),
      );
    }
  }
  if (result.exitCode != 0 && errors.trim().isNotEmpty) stderr.write(errors);
  return _WatchGenerationResult(
    exitCode: result.exitCode,
    elapsedMs: stopwatch.elapsedMilliseconds,
    trace: trace,
    outputDelta: outputDelta,
    diagnostics: result.exitCode == 0 ? null : errors.trim(),
  );
}

Map<String, Object?>? _decodeWatchObject(String value) {
  try {
    final decoded = jsonDecode(value);
    return decoded is Map ? decoded.cast<String, Object?>() : null;
  } on FormatException {
    return null;
  }
}

String _stripAnsi(String value) =>
    value.replaceAll(RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]'), '');

String? _reportedBuildDuration(String line) {
  final match = RegExp(
    r'build_runner/(?:aot|jit) in ([^;]+);',
  ).firstMatch(line);
  return match?.group(1);
}

final class _BuildRunnerWatchLine {
  const _BuildRunnerWatchLine(this.text);

  final String text;
}

final class _WatchGenerationResult {
  const _WatchGenerationResult({
    required this.exitCode,
    required this.elapsedMs,
    required this.trace,
    required this.outputDelta,
    required this.diagnostics,
  });

  final int exitCode;
  final int elapsedMs;
  final Map<String, Object?>? trace;
  final Map<String, Object?>? outputDelta;
  final String? diagnostics;

  bool get succeeded => exitCode == 0;

  Map<String, Object?> toEventData() => {
    'exitCode': exitCode,
    'elapsedMs': elapsedMs,
    if (trace != null) 'profile': trace!,
    if (outputDelta != null) 'outputDelta': outputDelta!,
    if (diagnostics != null) 'diagnostics': diagnostics!,
  };
}

final class _GenerationWatchEvents {
  const _GenerationWatchEvents({
    required this.machine,
    required this.buildRoot,
    required this.hostRoot,
  });

  final bool machine;
  final Directory buildRoot;
  final Directory hostRoot;

  void emit(String type, {Map<String, Object?> data = const {}}) {
    if (machine) {
      stdout.writeln(
        jsonEncode(<String, Object?>{
          'schemaVersion': 1,
          'type': type,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'buildRoot': buildRoot.path,
          'hostRoot': hostRoot.path,
          ...data,
        }),
      );
      return;
    }
    final elapsed = data['elapsedMs'];
    stdout.writeln(
      'CCRouter watch $type${elapsed is int ? ' (${elapsed}ms)' : ''}.',
    );
  }
}
