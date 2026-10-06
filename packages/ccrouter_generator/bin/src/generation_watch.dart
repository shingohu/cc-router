part of '../ccrouter_generator.dart';

const _watchCycleEnvironment = 'CCROUTER_WATCH_CYCLE';
const _watchLockEnvironment = 'CCROUTER_WATCH_LOCK_HELD';
const _watchKillSwitch = 'CCROUTER_DISABLE_BUILD_WATCH';
const _watchCycleOptimizationKillSwitch =
    'CCROUTER_DISABLE_WATCH_CYCLE_OPTIMIZATION';
const _watchInProcessCycleKillSwitch =
    'CCROUTER_DISABLE_WATCH_IN_PROCESS_CYCLE';
const _watchSessionRestartKillSwitch = 'CCROUTER_DISABLE_WATCH_SESSION_RESTART';
const _watchResolutionExactPollInterval = Duration(seconds: 5);
const _buildRunnerSuccessPattern = 'Built with build_runner';
const _buildRunnerFailurePattern = 'Failed to build with build_runner';

bool get _isWatchAggregationCycle =>
    _generationCycleMode?.watchCycle ??
    Platform.environment[_watchCycleEnvironment] == '1';

bool get _watchOwnsGenerationLock =>
    _generationCycleMode?.lockHeld ??
    (_isWatchAggregationCycle &&
        Platform.environment[_watchLockEnvironment] == '1');

bool get _usesOptimizedWatchCycle =>
    _generationCycleMode?.optimized ??
    (_isWatchAggregationCycle &&
        Platform.environment[_watchCycleOptimizationKillSwitch] != '1');

/// Keeps build_runner's AOT entrypoint and Analyzer graph alive for one root.
Future<void> _runGenerationWatch({
  required Directory hostRoot,
  required CCProjectContext buildContext,
  required _Arguments parsed,
  required Future<_GenerationCycleResult> Function() runInProcessCycle,
}) async {
  final events = _GenerationWatchEvents(
    machine: parsed.machine,
    buildRoot: buildContext.resolutionRoot,
    hostRoot: hostRoot,
    leasePath: parsed.watchLeasePath,
  );
  await events.emit('starting', data: {'mode': 'auto'});

  if (Platform.environment[_watchKillSwitch] == '1') {
    await events.emit('fallback', data: {'reason': 'kill-switch'});
    final fallback = await _runWatchGenerationSubprocess(
      hostRoot: hostRoot,
      buildRoot: buildContext.resolutionRoot,
      watchCycle: false,
      lockHeld: false,
      profile: parsed.profile,
    );
    await events.emit(
      fallback.succeeded ? 'succeeded' : 'failed',
      data: fallback.toEventData(),
    );
    exitCode = fallback.exitCode;
    return;
  }
  late final _GenerationWatchOwnership watchOwnership;
  try {
    watchOwnership = await _GenerationWatchOwnership.acquire(
      buildContext.resolutionRoot,
    );
  } on _GenerationWatchOwnershipConflictException catch (error) {
    await events.emit(
      'failed',
      data: {'stage': 'watch-lock', 'error': error.message},
    );
    exitCode = 1;
    return;
  }
  late final _GenerationLock generationLock;
  try {
    generationLock = await _GenerationLock.acquireForWatch(
      buildContext.resolutionRoot,
    );
  } on Object catch (error) {
    await watchOwnership.release();
    await events.emit(
      'failed',
      data: {'stage': 'generation-lock', 'error': '$error'},
    );
    exitCode = 1;
    return;
  }

  final stop = Completer<void>();
  final signalSubscriptions = <StreamSubscription<ProcessSignal>>[];
  Process? activeProcess;
  void requestStop() {
    if (stop.isCompleted) return;
    stop.complete();
    activeProcess?.kill(ProcessSignal.sigint);
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

  try {
    var sessionIndex = 0;
    _GenerationWatchTopology? topology;
    while (!stop.isCompleted) {
      final workspaceWatch = Stopwatch()..start();
      try {
        topology ??= await _resolveGenerationWatchTopology(
          hostRoot: hostRoot,
          buildContext: buildContext,
        );
      } on Object catch (error) {
        await events.emit(
          'failed',
          data: {'stage': 'workspace', 'error': '$error'},
        );
        exitCode = 1;
        break;
      }
      workspaceWatch.stop();
      if (sessionIndex > 0) events.beginNewSession();
      await events.emit(
        'targetsResolved',
        data: {
          'elapsedMs': workspaceWatch.elapsedMilliseconds,
          'packages': topology.targets,
          'topologyFingerprint': topology.fingerprint,
        },
      );
      final nextTopology = await _runGenerationWatchSession(
        hostRoot: hostRoot,
        buildContext: buildContext,
        parsed: parsed,
        events: events,
        topology: topology,
        stop: stop,
        setActiveProcess: (process) => activeProcess = process,
        runInProcessCycle: runInProcessCycle,
      );
      if (nextTopology == null) break;
      topology = nextTopology;
      sessionIndex++;
    }
  } finally {
    leaseTimer?.cancel();
    for (final subscription in signalSubscriptions) {
      await subscription.cancel();
    }
    try {
      await generationLock.release();
    } finally {
      await watchOwnership.release();
    }
    if (exitCode == 0) await events.emit('stopped');
  }
}

/// One resolved Host topology that determines a build_runner child session.
final class _GenerationWatchTopology {
  const _GenerationWatchTopology({
    required this.workspace,
    required this.targets,
    required this.fingerprint,
  });

  final CCPackageWorkspace workspace;
  final List<String> targets;
  final String fingerprint;

  /// Whether [next] contains work that the current child cannot observe.
  ///
  /// A version change or a dependency-edge change inside the already loaded
  /// Package universe remains covered by the current child. Package additions
  /// require a fresh Analyzer graph, while any target-set change requires new
  /// build filters. Removing a non-target Package is therefore the only
  /// Package-set change that can safely retain this session.
  bool requiresRestartFor(_GenerationWatchTopology next) {
    final currentPackages = workspace.packages.keys.toSet();
    final addedPackages = next.workspace.packages.keys.where(
      (name) => !currentPackages.contains(name),
    );
    final nextTargets = next.targets.toSet();
    return addedPackages.isNotEmpty ||
        targets.length != nextTargets.length ||
        targets.any((target) => !nextTargets.contains(target));
  }
}

/// Resolves only topology facts that require a new build_runner Analyzer graph.
Future<_GenerationWatchTopology> _resolveGenerationWatchTopology({
  required Directory hostRoot,
  required CCProjectContext buildContext,
}) async {
  final workspace = await CCPackageWorkspace.load(
    buildRoot: buildContext.resolutionRoot,
    hostRoot: hostRoot,
    workspace: buildContext.isWorkspace,
  );
  final targets =
      workspace.packages.values
          .where(
            (package) => package.writable && package.declaresGenerationIntent,
          )
          .map((package) => package.name)
          .toList()
        ..sort();
  if (targets.isEmpty) {
    throw const CCPackageWorkspaceException(
      'No writable CCRouter Builder Packages were found.',
    );
  }
  final packageNames = workspace.packages.keys.toList()..sort();
  final fingerprint = computeCCCanonicalJsonFingerprint(<String, Object?>{
    'host': workspace.host.name,
    'packages': packageNames,
    'dependencies': <String, Object?>{
      for (final name in packageNames)
        name: workspace.packages[name]!.dependencies,
    },
    'targets': targets,
  });
  return _GenerationWatchTopology(
    workspace: workspace,
    targets: List.unmodifiable(targets),
    fingerprint: fingerprint,
  );
}

/// Runs one child session and returns the topology requiring a restart.
Future<_GenerationWatchTopology?> _runGenerationWatchSession({
  required Directory hostRoot,
  required CCProjectContext buildContext,
  required _Arguments parsed,
  required _GenerationWatchEvents events,
  required _GenerationWatchTopology topology,
  required Completer<void> stop,
  required void Function(Process? process) setActiveProcess,
  required Future<_GenerationCycleResult> Function() runInProcessCycle,
}) async {
  final protectionWatch = Stopwatch()..start();
  final targetRoots = <Directory>[
    for (final name in topology.targets)
      topology.workspace.packages[name]!.root,
  ];
  final protectedOutputs = <_GeneratedArtifactsSnapshot>[
    await _GeneratedArtifactsSnapshot.captureOutside(
      buildContext.resolutionRoot,
      targetRoots,
    ),
    for (final package in topology.workspace.packages.values)
      if (!package.writable &&
          !_isWithin(buildContext.resolutionRoot, package.root))
        await _GeneratedArtifactsSnapshot.capture(package.root),
  ];
  protectionWatch.stop();

  var command = await _buildRunnerCommand(buildContext.resolutionRoot, 'watch');
  final processWatch = Stopwatch()..start();
  late final Process process;
  try {
    command = await _recoverWrongBuildRunnerSnapshotBeforeWatch(
      command,
      buildContext.resolutionRoot,
    );
    process = await Process.start(command.executable, <String>[
      ...command.arguments,
      if (parsed.profile) '--verbose-durations',
      if (buildContext.isWorkspace) '--workspace',
      for (final package in topology.targets) ...[
        '--build-filter',
        'asset:$package/lib/**',
        '--build-filter',
        'asset:$package/ccrouter_generated/**',
      ],
    ], workingDirectory: buildContext.resolutionRoot.path);
  } on Object catch (error) {
    await events.emit(
      'failed',
      data: {'stage': 'watch-start', 'error': '$error'},
    );
    exitCode = 1;
    return null;
  }
  setActiveProcess(process);
  await events.emit(
    'watchStarted',
    data: {
      'elapsedMs': processWatch.elapsedMilliseconds,
      'protectionSnapshotMs': protectionWatch.elapsedMilliseconds,
      'topologyFingerprint': topology.fingerprint,
    },
  );
  final inputObserver = _GenerationWatchInputObserver.start(
    topology.workspace,
    () => events.emit('inputChanged'),
  );
  await events.emit('buildStarted', data: {'initial': true});

  final signals = StreamController<_GenerationWatchSignal>();
  final outputSubscriptions = <StreamSubscription<String>>[
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => signals.add(_GenerationWatchSignal.line(line))),
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => signals.add(_GenerationWatchSignal.line(line))),
  ];
  String? resolutionBaseline;
  String? resolutionStamp;
  try {
    resolutionBaseline = await CCPubResolutionFingerprint.capture(
      hostRoot: hostRoot,
      buildRoot: buildContext.resolutionRoot,
    );
    resolutionStamp = await _captureWatchResolutionStamp(
      hostRoot: hostRoot,
      buildRoot: buildContext.resolutionRoot,
    );
  } on Object {
    // The first complete resolution observed by the timer becomes the baseline.
  }
  final sessionResolutionFingerprint = resolutionBaseline;
  final exactResolutionPoll = Stopwatch()..start();
  Future<void>? activeResolutionCheck;
  late final Timer resolutionTimer;
  resolutionTimer = Timer.periodic(_generationWatchStatusPollInterval, (_) {
    if (activeResolutionCheck != null || stop.isCompleted) return;
    final check = () async {
      try {
        var currentStamp = await _captureWatchResolutionStamp(
          hostRoot: hostRoot,
          buildRoot: buildContext.resolutionRoot,
        );
        if (currentStamp == resolutionStamp &&
            exactResolutionPoll.elapsed < _watchResolutionExactPollInterval) {
          return;
        }
        var current = await CCPubResolutionFingerprint.capture(
          hostRoot: hostRoot,
          buildRoot: buildContext.resolutionRoot,
        );
        exactResolutionPoll.reset();
        if (resolutionBaseline == null) {
          resolutionBaseline = current;
          resolutionStamp = currentStamp;
          return;
        }
        if (current == resolutionBaseline) {
          resolutionStamp = currentStamp;
          return;
        }
        await Future<void>.delayed(_generationWatchStatusPollInterval);
        if (stop.isCompleted) return;
        currentStamp = await _captureWatchResolutionStamp(
          hostRoot: hostRoot,
          buildRoot: buildContext.resolutionRoot,
        );
        current = await CCPubResolutionFingerprint.capture(
          hostRoot: hostRoot,
          buildRoot: buildContext.resolutionRoot,
        );
        exactResolutionPoll.reset();
        if (current == resolutionBaseline) return;
        resolutionBaseline = current;
        resolutionStamp = currentStamp;
        signals.add(_GenerationWatchSignal.resolutionChanged(current));
      } on Object {
        // Pub may atomically replace several files; retry on the next tick.
      }
    }();
    activeResolutionCheck = check;
    check.whenComplete(() {
      if (identical(activeResolutionCheck, check)) activeResolutionCheck = null;
    });
  });
  final iterator = StreamIterator(signals.stream);
  var cycleSnapshot = await _GeneratedArtifactsSnapshot.capture(
    buildContext.resolutionRoot,
  );
  var buildWatch = Stopwatch()..start();
  final buildRunnerPhases = CCBuildRunnerPhaseCollector();
  var initialBuild = true;
  var readyEmitted = false;
  var buildActive = true;
  String? pendingResolutionFingerprint;
  final failureTail = <String>[];
  _GenerationWatchTopology? nextTopology;

  Future<_GenerationWatchTopology?> topologyRequiringRestart() async {
    final current = await _resolveGenerationWatchTopology(
      hostRoot: hostRoot,
      buildContext: buildContext,
    );
    if (!topology.requiresRestartFor(current)) return null;
    if (Platform.environment[_watchSessionRestartKillSwitch] == '1') {
      throw const CCPackageWorkspaceException(
        'The resolved Host topology requires a new build_runner session, but '
        'automatic restart is disabled by '
        'CCROUTER_DISABLE_WATCH_SESSION_RESTART=1. Stop the watch and run '
        'one-shot generation.',
      );
    }
    return current;
  }

  Future<bool> restartIfChanged() async {
    try {
      final changed = await topologyRequiringRestart();
      if (changed == null) return false;
      await cycleSnapshot.restore();
      nextTopology = changed;
      await events.emit(
        'sessionRestarting',
        data: {
          'reason': 'topology-changed',
          'previousTopologyFingerprint': topology.fingerprint,
          'nextTopologyFingerprint': changed.fingerprint,
          'packages': changed.targets,
        },
      );
      process.kill(ProcessSignal.sigint);
      return true;
    } on Object catch (error) {
      await cycleSnapshot.restore();
      await events.emit(
        'failed',
        data: {'stage': 'topology-resolution', 'error': '$error'},
      );
      cycleSnapshot = await _GeneratedArtifactsSnapshot.capture(
        buildContext.resolutionRoot,
      );
      return true;
    }
  }

  Future<bool> runResolutionAggregation(String fingerprint) async {
    await events.emit(
      'resolutionStarted',
      data: {'resolutionFingerprint': fingerprint},
    );
    await events.emit(
      'aggregationStarted',
      data: {'initial': false, 'trigger': 'resolution'},
    );
    final usesSubprocessReference =
        Platform.environment[_watchInProcessCycleKillSwitch] == '1';
    final aggregation = usesSubprocessReference
        ? await _runWatchGenerationSubprocess(
            hostRoot: hostRoot,
            buildRoot: buildContext.resolutionRoot,
            watchCycle: true,
            lockHeld: true,
            profile: parsed.profile,
          )
        : await runInProcessCycle();
    if (await restartIfChanged()) return true;
    await events.emit(
      aggregation.succeeded ? 'aggregationSucceeded' : 'failed',
      data: {
        'stage': 'aggregation',
        'initial': false,
        'trigger': 'resolution',
        'cycleMode': usesSubprocessReference
            ? 'subprocessReference'
            : 'inProcess',
        ...aggregation.toEventData(),
      },
    );
    cycleSnapshot = await _GeneratedArtifactsSnapshot.capture(
      buildContext.resolutionRoot,
    );
    failureTail.clear();
    return false;
  }

  try {
    while (!stop.isCompleted && nextTopology == null) {
      final hasLine = await Future.any<bool>([
        iterator.moveNext(),
        stop.future.then((_) => false),
        process.exitCode.then((_) => false),
      ]);
      if (!hasLine || stop.isCompleted) break;
      final signal = iterator.current;
      final resolutionFingerprint = signal.resolutionFingerprint;
      if (resolutionFingerprint != null) {
        if (buildActive) {
          pendingResolutionFingerprint = resolutionFingerprint;
          continue;
        }
        if (await runResolutionAggregation(resolutionFingerprint)) continue;
        continue;
      }
      final line = _stripAnsi(signal.line!);
      buildRunnerPhases.addLine(line);
      if (line.trim().isNotEmpty) {
        _commandStderr.writeln('build_runner: $line');
        failureTail.add(line);
        if (failureTail.length > 30) failureTail.removeAt(0);
      }
      if (line.contains('Starting build #')) {
        buildRunnerPhases.reset();
        buildWatch = Stopwatch()..start();
        buildActive = true;
        await events.emit('buildStarted', data: {'initial': false});
        continue;
      }
      final succeeded = line.contains(_buildRunnerSuccessPattern);
      final failed = line.contains(_buildRunnerFailurePattern);
      if (!succeeded && !failed) continue;

      final restoreWatch = Stopwatch()..start();
      buildActive = false;
      final buildRunnerReport = buildRunnerPhases.finish(line);
      for (final snapshot in protectedOutputs) {
        await snapshot.restore();
      }
      restoreWatch.stop();
      final buildElapsed = buildWatch.elapsedMilliseconds;
      if (failed) {
        await cycleSnapshot.restore();
        if (await restartIfChanged()) continue;
        await events.emit(
          'failed',
          data: {
            'stage': 'build',
            'initial': initialBuild,
            'elapsedMs': buildElapsed,
            'reportedDuration': _reportedBuildDuration(line),
            'buildRunner': buildRunnerReport.toJson(),
            'protectionRestoreMs': restoreWatch.elapsedMilliseconds,
            'diagnostics': failureTail.join('\n'),
          },
        );
        cycleSnapshot = await _GeneratedArtifactsSnapshot.capture(
          buildContext.resolutionRoot,
        );
        failureTail.clear();
        initialBuild = false;
        final pending = pendingResolutionFingerprint;
        pendingResolutionFingerprint = null;
        if (pending != null) await runResolutionAggregation(pending);
        continue;
      }

      await events.emit(
        'buildSucceeded',
        data: {
          'initial': initialBuild,
          'elapsedMs': buildElapsed,
          'reportedDuration': _reportedBuildDuration(line),
          'buildRunner': buildRunnerReport.toJson(),
          'protectionRestoreMs': restoreWatch.elapsedMilliseconds,
        },
      );
      await events.emit('aggregationStarted', data: {'initial': initialBuild});
      final usesSubprocessReference =
          Platform.environment[_watchInProcessCycleKillSwitch] == '1';
      final aggregation = usesSubprocessReference
          ? await _runWatchGenerationSubprocess(
              hostRoot: hostRoot,
              buildRoot: buildContext.resolutionRoot,
              watchCycle: true,
              lockHeld: true,
              profile: parsed.profile,
            )
          : await runInProcessCycle();
      if (await restartIfChanged()) continue;
      await events.emit(
        aggregation.succeeded ? 'aggregationSucceeded' : 'failed',
        data: {
          'stage': 'aggregation',
          'initial': initialBuild,
          'cycleMode': usesSubprocessReference
              ? 'subprocessReference'
              : 'inProcess',
          ...aggregation.toEventData(),
        },
      );
      cycleSnapshot = await _GeneratedArtifactsSnapshot.capture(
        buildContext.resolutionRoot,
      );
      if (!readyEmitted && aggregation.succeeded) {
        await events.emit('ready');
        readyEmitted = true;
      }
      initialBuild = false;
      failureTail.clear();
      final pending = pendingResolutionFingerprint;
      pendingResolutionFingerprint = null;
      if (pending != null) await runResolutionAggregation(pending);
    }
  } finally {
    await inputObserver.close();
    resolutionTimer.cancel();
    await activeResolutionCheck;
    final processCode = await _stopBuildRunnerWatchProcess(process);
    for (final subscription in outputSubscriptions) {
      await subscription.cancel();
    }
    await iterator.cancel();
    await signals.close();
    setActiveProcess(null);
    if (nextTopology == null && !stop.isCompleted) {
      try {
        final currentResolution = await CCPubResolutionFingerprint.capture(
          hostRoot: hostRoot,
          buildRoot: buildContext.resolutionRoot,
        );
        if (sessionResolutionFingerprint != null &&
            currentResolution != sessionResolutionFingerprint) {
          if (Platform.environment[_watchSessionRestartKillSwitch] == '1') {
            throw const CCPackageWorkspaceException(
              'build_runner exited after Pub resolution changed, but automatic '
              'session restart is disabled by '
              'CCROUTER_DISABLE_WATCH_SESSION_RESTART=1. Stop the watch and '
              'run one-shot generation.',
            );
          }
          final currentTopology = await _resolveGenerationWatchTopology(
            hostRoot: hostRoot,
            buildContext: buildContext,
          );
          await cycleSnapshot.restore();
          nextTopology = currentTopology;
          await events.emit(
            'sessionRestarting',
            data: {
              'reason': 'build-runner-exited-after-resolution-change',
              'previousTopologyFingerprint': topology.fingerprint,
              'nextTopologyFingerprint': currentTopology.fingerprint,
              'packages': currentTopology.targets,
              'exitCode': processCode,
            },
          );
        }
      } on Object catch (error) {
        exitCode = 1;
        await events.emit(
          'failed',
          data: {'stage': 'topology-resolution', 'error': '$error'},
        );
      }
    }
    if (nextTopology == null && !stop.isCompleted) {
      exitCode = 1;
      await events.emit(
        'failed',
        data: {
          'stage': 'watch-exit',
          'exitCode': processCode,
          'diagnostics': failureTail.join('\n'),
        },
      );
    }
  }
  return nextTopology;
}

/// Lets build_runner clean up its child before escalating a stuck shutdown.
Future<int> _stopBuildRunnerWatchProcess(Process process) async {
  process.kill(ProcessSignal.sigint);
  try {
    return await process.exitCode.timeout(const Duration(seconds: 10));
  } on TimeoutException {
    process.kill(ProcessSignal.sigterm);
    return process.exitCode;
  }
}

/// Cheap wake-up evidence for the exact resolution fingerprint monitor.
Future<String> _captureWatchResolutionStamp({
  required Directory hostRoot,
  required Directory buildRoot,
}) async {
  final files = <File>[
    File(path.join(hostRoot.path, 'pubspec.yaml')),
    File(path.join(buildRoot.path, 'pubspec.yaml')),
    File(path.join(buildRoot.path, 'pubspec.lock')),
    File(path.join(buildRoot.path, '.dart_tool', 'package_config.json')),
    File(path.join(buildRoot.path, '.dart_tool', 'package_graph.json')),
  ];
  final parts = <String>[];
  for (final file in files) {
    final stat = await file.stat();
    parts.add(
      '${file.path}\u0000${stat.type}\u0000${stat.size}\u0000'
      '${stat.modified.microsecondsSinceEpoch}',
    );
  }
  return parts.join('\u0001');
}

/// Uses Pub's cached executable snapshot and heals a missing cache via Pub.
Future<CCBuildRunnerCommand> _buildRunnerCommand(
  Directory buildRoot,
  String command,
) => resolveCCBuildRunnerCommand(
  buildRoot: buildRoot,
  command: command,
  dartExecutable: _dartVmExecutable(),
);

/// Probes the long-lived watch entrypoint before it acquires Analyzer state.
///
/// A normal cached snapshot is retained. Only the Dart VM's exact full-version
/// diagnostic authorizes deletion and a self-healing `dart run` invocation.
Future<CCBuildRunnerCommand> _recoverWrongBuildRunnerSnapshotBeforeWatch(
  CCBuildRunnerCommand command,
  Directory buildRoot,
) async {
  final snapshot = command.cachedSnapshot;
  if (snapshot == null) return command;
  if (!await snapshot.exists()) {
    return _buildRunnerCommand(buildRoot, 'watch');
  }
  final probe = await Process.run(command.executable, [
    snapshot.path,
    '--help',
  ], workingDirectory: buildRoot.path);
  final diagnostics = '${probe.stdout}\n${probe.stderr}';
  if (!await command.invalidateIfWrongSnapshotVersion(diagnostics)) {
    return command;
  }
  _commandStderr.writeln(
    'warning: cached build_runner snapshot is incompatible with the current '
    'Dart SDK; rebuilding it once through dart run.',
  );
  return _buildRunnerCommand(buildRoot, 'watch');
}

/// Resolves the Dart CLI even when Pub launched this command via AOT runtime.
String _dartVmExecutable() {
  final resolved = File(Platform.resolvedExecutable);
  if (path.basenameWithoutExtension(resolved.path) != 'dartaotruntime') {
    return resolved.path;
  }
  final sibling = File(
    path.join(resolved.parent.path, Platform.isWindows ? 'dart.exe' : 'dart'),
  );
  return sibling.existsSync() ? sibling.path : resolved.path;
}

Future<_GenerationCycleResult> _runWatchGenerationSubprocess({
  required Directory hostRoot,
  required Directory buildRoot,
  required bool watchCycle,
  required bool lockHeld,
  required bool profile,
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
    if (profile) '--profile',
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
  if (result.exitCode != 0 && errors.trim().isNotEmpty)
    _commandStderr.write(errors);
  return _GenerationCycleResult(
    exitCode: result.exitCode,
    elapsedMs: stopwatch.elapsedMilliseconds,
    trace: trace,
    outputDelta: outputDelta,
    diagnostics: result.exitCode == 0 ? null : errors.trim(),
    structuredDiagnostics: const [],
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

/// One merged child-process or exact Pub-resolution watch signal.
final class _GenerationWatchSignal {
  const _GenerationWatchSignal._({this.line, this.resolutionFingerprint});

  const _GenerationWatchSignal.line(String line) : this._(line: line);

  const _GenerationWatchSignal.resolutionChanged(String fingerprint)
    : this._(resolutionFingerprint: fingerprint);

  final String? line;
  final String? resolutionFingerprint;
}

/// Observes authored Builder inputs so Flutter reload can wait for their cycle.
///
/// This observer records only a monotonic revision. It does not parse Dart,
/// classify declarations, or authorize skipping Builder work.
final class _GenerationWatchInputObserver {
  _GenerationWatchInputObserver._(this._subscriptions, this._onChanged);

  /// Starts bounded filesystem observation for writable generation Packages.
  static _GenerationWatchInputObserver start(
    CCPackageWorkspace workspace,
    Future<void> Function() onChanged,
  ) {
    final subscriptions = <StreamSubscription<FileSystemEvent>>[];
    final observer = _GenerationWatchInputObserver._(subscriptions, onChanged);
    for (final package in workspace.packages.values) {
      if (!package.writable || !package.declaresGenerationIntent) continue;
      final lib = Directory(path.join(package.root.path, 'lib'));
      if (lib.existsSync()) {
        try {
          subscriptions.add(
            lib
                .watch(recursive: true)
                .listen(
                  observer._observeLibraryEvent,
                  onError: observer._ignoreWatchError,
                ),
          );
        } on FileSystemException {
          // build_runner remains authoritative when platform watch is absent.
        }
      }
      try {
        subscriptions.add(
          package.root.watch().listen(
            observer._observePackageEvent,
            onError: observer._ignoreWatchError,
          ),
        );
      } on FileSystemException {
        // build_runner remains authoritative when platform watch is absent.
      }
    }
    return observer;
  }

  final List<StreamSubscription<FileSystemEvent>> _subscriptions;
  final Future<void> Function() _onChanged;
  Timer? _coalesceWindow;
  bool _closed = false;

  void _observeLibraryEvent(FileSystemEvent event) {
    final normalized = path.normalize(event.path);
    if (!normalized.endsWith('.dart') ||
        normalized.contains(
          '${path.separator}src${path.separator}ccrouter_generated'
          '${path.separator}',
        ) ||
        path.basename(normalized).endsWith('.g.dart')) {
      return;
    }
    _scheduleRevision();
  }

  void _observePackageEvent(FileSystemEvent event) {
    if (!const <String>{
      'pubspec.yaml',
      'build.yaml',
      'ccrouter.yaml',
    }.contains(path.basename(event.path))) {
      return;
    }
    _scheduleRevision();
  }

  void _scheduleRevision() {
    if (_closed || _coalesceWindow != null) return;
    unawaited(_onChanged());
    _coalesceWindow = Timer(const Duration(milliseconds: 40), () {
      _coalesceWindow = null;
    });
  }

  void _ignoreWatchError(Object _, [StackTrace? __]) {
    // Source observation is a reload fence hint; Builder correctness is intact.
  }

  /// Cancels every directory subscription owned by this child session.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _coalesceWindow?.cancel();
    _coalesceWindow = null;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
  }
}

final class _GenerationWatchEvents {
  _GenerationWatchEvents({
    required this.machine,
    required this.buildRoot,
    required this.hostRoot,
    required String? leasePath,
  }) : _status = _GenerationWatchStatusTracker(
         hostRoot: hostRoot,
         buildRoot: buildRoot,
         leasePath: leasePath,
       );

  final bool machine;
  final Directory buildRoot;
  final Directory hostRoot;
  final _GenerationWatchStatusTracker _status;
  Future<void> _emissionTail = Future<void>.value();

  /// Rotates the child-session identity while retaining the outer watch lease.
  void beginNewSession() => _status.beginNewSession();

  Future<void> emit(String type, {Map<String, Object?> data = const {}}) {
    final operation = _emissionTail.then((_) => _emitNow(type, data: data));
    _emissionTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return operation;
  }

  Future<void> _emitNow(
    String type, {
    required Map<String, Object?> data,
  }) async {
    final timestamp = DateTime.now().toUtc().toIso8601String();
    await _status.observe(type, timestamp: timestamp, data: data);
    if (machine) {
      _commandStdout.writeln(
        jsonEncode(<String, Object?>{
          'schemaVersion': 1,
          'type': type,
          'timestamp': timestamp,
          'buildRoot': buildRoot.path,
          'hostRoot': hostRoot.path,
          'sessionId': _status.sessionId,
          'eventRevision': _status.eventRevision,
          ...data,
        }),
      );
      return;
    }
    final elapsed = data['elapsedMs'];
    _commandStdout.writeln(
      'CCRouter watch $type${elapsed is int ? ' (${elapsed}ms)' : ''}.',
    );
  }
}
