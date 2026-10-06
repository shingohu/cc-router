part of '../ccrouter_generator.dart';

const _watchCycleEnvironment = 'CCROUTER_WATCH_CYCLE';
const _watchLockEnvironment = 'CCROUTER_WATCH_LOCK_HELD';
const _watchKillSwitch = 'CCROUTER_DISABLE_BUILD_WATCH';
const _watchCycleOptimizationKillSwitch =
    'CCROUTER_DISABLE_WATCH_CYCLE_OPTIMIZATION';
const _watchInProcessCycleKillSwitch =
    'CCROUTER_DISABLE_WATCH_IN_PROCESS_CYCLE';
const _watchSessionRestartKillSwitch = 'CCROUTER_DISABLE_WATCH_SESSION_RESTART';
const _multiHostWatchKillSwitch = 'CCROUTER_DISABLE_MULTI_HOST_WATCH';
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

bool get _usesMultiHostWatch =>
    Platform.environment[_multiHostWatchKillSwitch] != '1';

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
  _GenerationWatchRegistration? registration;
  if (_usesMultiHostWatch) {
    try {
      registration = await _GenerationWatchRegistration.acquire(
        hostRoot: hostRoot,
        buildRoot: buildContext.resolutionRoot,
        leasePath: parsed.watchLeasePath,
      );
    } on _GenerationWatchRegistrationConflictException catch (error) {
      await events.emit(
        'failed',
        data: {'stage': 'watch-registration', 'error': error.message},
      );
      exitCode = 1;
      return;
    }
  }
  try {
    while (true) {
      try {
        final ownership = await _GenerationWatchOwnership.acquire(
          buildContext.resolutionRoot,
        );
        events.becomeBuilderOwner();
        await _runGenerationWatchOwner(
          hostRoot: hostRoot,
          buildContext: buildContext,
          parsed: parsed,
          events: events,
          watchOwnership: ownership,
          runInProcessCycle: runInProcessCycle,
        );
        return;
      } on _GenerationWatchOwnershipConflictException catch (error) {
        if (!_usesMultiHostWatch) {
          await events.emit(
            'failed',
            data: {'stage': 'watch-lock', 'error': error.message},
          );
          exitCode = 1;
          return;
        }
        final activeHosts = await _GenerationWatchRegistration.activeHostRoots(
          buildContext.resolutionRoot,
        );
        final hasBuilderOwnerRegistration = activeHosts.any(
          (candidate) =>
              !path.equals(candidate.absolute.path, hostRoot.absolute.path),
        );
        if (!hasBuilderOwnerRegistration) {
          await events.emit(
            'failed',
            data: {'stage': 'watch-lock', 'error': error.message},
          );
          exitCode = 1;
          return;
        }
        final promote = await _runGenerationWatchSubscriber(
          hostRoot: hostRoot,
          buildContext: buildContext,
          parsed: parsed,
          events: events,
          runInProcessCycle: runInProcessCycle,
        );
        if (!promote) return;
        events.beginNewSession();
      }
    }
  } finally {
    await registration?.release();
  }
}

/// Owns the single build_runner process for all active Hosts in one build root.
Future<void> _runGenerationWatchOwner({
  required Directory hostRoot,
  required CCProjectContext buildContext,
  required _Arguments parsed,
  required _GenerationWatchEvents events,
  required _GenerationWatchOwnership watchOwnership,
  required Future<_GenerationCycleResult> Function() runInProcessCycle,
}) async {
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
          includeRegisteredHosts: _usesMultiHostWatch,
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
        includeRegisteredHosts: _usesMultiHostWatch,
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
      if (exitCode == 0) await events.emit('stopped');
    } finally {
      try {
        await generationLock.release();
      } finally {
        await watchOwnership.release();
      }
    }
  }
}

/// Reuses the build-root owner while retaining Host-specific aggregation.
///
/// The subscriber never starts build_runner. It waits until the owner's target
/// union covers its closure, then serializes its own validation/publication
/// behind the shared aggregation lock. If the owner exits while this Host is
/// still leased, the caller retries ownership and promotes this process.
Future<bool> _runGenerationWatchSubscriber({
  required Directory hostRoot,
  required CCProjectContext buildContext,
  required _Arguments parsed,
  required _GenerationWatchEvents events,
  required Future<_GenerationCycleResult> Function() runInProcessCycle,
}) async {
  var ownTopology = await _resolveGenerationWatchTopology(
    hostRoot: hostRoot,
    buildContext: buildContext,
  );
  var requiredTargets = ownTopology.targets.toSet();
  var inputObserver = _GenerationWatchInputObserver.start(<CCPackageWorkspace>[
    ownTopology.workspace,
  ], () => events.emit('inputChanged'));
  final stop = Completer<void>();
  final signalSubscriptions = <StreamSubscription<ProcessSignal>>[];
  void requestStop() {
    if (!stop.isCompleted) stop.complete();
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

  var ready = false;
  var seenCycleRevision = 0;
  var seenFailureRevision = 0;
  String? builderSessionId;

  Future<void> refreshOwnTopology() async {
    final current = await _resolveGenerationWatchTopology(
      hostRoot: hostRoot,
      buildContext: buildContext,
    );
    if (current.fingerprint == ownTopology.fingerprint) return;
    final previous = ownTopology;
    final requiresNewHostSession = previous.requiresRestartFor(
      current,
      removeMissingTargets: true,
    );
    await inputObserver.close();
    ownTopology = current;
    requiredTargets = current.targets.toSet();
    inputObserver = _GenerationWatchInputObserver.start(<CCPackageWorkspace>[
      current.workspace,
    ], () => events.emit('inputChanged'));
    if (ready && requiresNewHostSession) {
      await events.emit(
        'sessionRestarting',
        data: {
          'reason': 'topology-changed',
          'sharedBuilder': true,
          'previousTopologyFingerprint': previous.fingerprint,
          'nextTopologyFingerprint': current.fingerprint,
          'packages': current.targets,
        },
      );
      events.beginNewSession();
      ready = false;
    }
  }

  try {
    await events.emit('watchStarted', data: {'sharedBuilder': true});
    while (!stop.isCompleted) {
      final ownerHeld = await _generationWatchOwnershipIsHeld(
        buildContext.resolutionRoot,
      );
      final status = await _readGenerationWatchBuildRootStatus(
        buildContext.resolutionRoot,
      );
      if (!ownerHeld) {
        await events.emit(
          'sessionRestarting',
          data: {'reason': 'builder-owner-exited'},
        );
        return true;
      }
      if (status == null || status['active'] != true) {
        await Future.any<void>([
          Future<void>.delayed(_generationWatchStatusPollInterval),
          stop.future,
        ]);
        continue;
      }
      final ownerPid = status['pid'] as int;
      events.followBuilderOwner(ownerPid);
      final sessionId = status['sessionId'] as String?;
      if (sessionId != builderSessionId) {
        await refreshOwnTopology();
        builderSessionId = sessionId;
        seenCycleRevision = 0;
        seenFailureRevision = 0;
      }
      final cycleRevision = status['cycleRevision'] as int;
      if (cycleRevision > seenCycleRevision) await refreshOwnTopology();
      final targets = (status['targets'] as List).whereType<String>().toSet();
      if (!targets.containsAll(requiredTargets)) {
        await Future.any<void>([
          Future<void>.delayed(_generationWatchStatusPollInterval),
          stop.future,
        ]);
        continue;
      }
      final failureRevision = status['failureRevision'] as int;
      if (failureRevision > seenFailureRevision) {
        seenFailureRevision = failureRevision;
        await events.emit('buildStarted', data: {'sharedBuilder': true});
        await events.emit(
          'failed',
          data: {
            'stage': 'build',
            'sharedBuilder': true,
            'builderOwnerPid': ownerPid,
            if (status['failureDiagnostics'] != null)
              'diagnostics': status['failureDiagnostics'],
          },
        );
      }
      if (cycleRevision > seenCycleRevision) {
        seenCycleRevision = cycleRevision;
        await events.emit('buildStarted', data: {'sharedBuilder': true});
        await events.emit(
          'buildSucceeded',
          data: {
            'sharedBuilder': true,
            'builderOwnerPid': ownerPid,
            'builderCycleRevision': cycleRevision,
          },
        );
        await events.emit(
          'aggregationStarted',
          data: {'initial': !ready, 'sharedBuilder': true},
        );
        final aggregation = await _runSerializedWatchAggregation(
          buildContext.resolutionRoot,
          runInProcessCycle,
        );
        await events.emit(
          aggregation.succeeded ? 'aggregationSucceeded' : 'failed',
          data: {
            'stage': 'aggregation',
            'initial': !ready,
            'sharedBuilder': true,
            'builderOwnerPid': ownerPid,
            'builderCycleRevision': cycleRevision,
            'cycleMode': 'sharedBuilderInProcess',
            ...aggregation.toEventData(),
          },
        );
        if (!ready && aggregation.succeeded) {
          ready = true;
          await events.emit('ready', data: {'sharedBuilder': true});
        }
      }
      await Future.any<void>([
        Future<void>.delayed(_generationWatchStatusPollInterval),
        stop.future,
      ]);
    }
    if (exitCode == 0) await events.emit('stopped');
    return false;
  } finally {
    await inputObserver.close();
    leaseTimer?.cancel();
    for (final subscription in signalSubscriptions) {
      await subscription.cancel();
    }
  }
}

/// One resolved Host topology that determines a build_runner child session.
final class _GenerationWatchTopology {
  const _GenerationWatchTopology({
    required this.workspace,
    required this.workspaces,
    required this.targets,
    required this.targetRoots,
    required this.packageNames,
    required this.fingerprint,
  });

  final CCPackageWorkspace workspace;
  final List<CCPackageWorkspace> workspaces;
  final List<String> targets;
  final Map<String, Directory> targetRoots;
  final Set<String> packageNames;
  final String fingerprint;

  /// Whether [next] contains work that the current child cannot observe.
  ///
  /// A version change or a dependency-edge change inside the already loaded
  /// Package universe remains covered by the current child. Package additions
  /// require a fresh Analyzer graph, while adding a target requires a new build
  /// filter. A departed subscriber may leave a harmless target superset loaded
  /// until the owner exits; a Pub-resolution cycle still requests exact target
  /// removal so deleted dependencies cannot remain in the Analyzer graph.
  bool requiresRestartFor(
    _GenerationWatchTopology next, {
    required bool removeMissingTargets,
  }) {
    final nextTargets = next.targets.toSet();
    final addedPackages = next.packageNames.where(
      (name) => !packageNames.contains(name),
    );
    final addedTargets = nextTargets.where(
      (target) => !targets.contains(target),
    );
    final removedTargets = targets.where(
      (target) => !nextTargets.contains(target),
    );
    return addedPackages.isNotEmpty ||
        addedTargets.isNotEmpty ||
        (removeMissingTargets && removedTargets.isNotEmpty);
  }
}

/// Resolves only topology facts that require a new build_runner Analyzer graph.
Future<_GenerationWatchTopology> _resolveGenerationWatchTopology({
  required Directory hostRoot,
  required CCProjectContext buildContext,
  bool includeRegisteredHosts = false,
}) async {
  final registeredHosts = includeRegisteredHosts
      ? await _GenerationWatchRegistration.activeHostRoots(
          buildContext.resolutionRoot,
        )
      : <Directory>[];
  if (!registeredHosts.any(
    (candidate) => path.equals(candidate.absolute.path, hostRoot.absolute.path),
  )) {
    registeredHosts.add(hostRoot.absolute);
  }
  registeredHosts.sort((left, right) => left.path.compareTo(right.path));
  final workspaces = <CCPackageWorkspace>[];
  for (final registeredHost in registeredHosts) {
    workspaces.add(
      await CCPackageWorkspace.load(
        buildRoot: buildContext.resolutionRoot,
        hostRoot: registeredHost,
        workspace: buildContext.isWorkspace,
      ),
    );
  }
  final workspace = workspaces.firstWhere(
    (candidate) =>
        path.equals(candidate.host.root.absolute.path, hostRoot.absolute.path),
  );
  final targetRoots = <String, Directory>{};
  final packageNames = <String>{};
  for (final candidate in workspaces) {
    packageNames.addAll(candidate.packages.keys);
    for (final package in candidate.packages.values) {
      if (package.writable && package.declaresGenerationIntent) {
        targetRoots[package.name] = package.root;
      }
    }
  }
  final targets = targetRoots.keys.toList()..sort();
  if (targets.isEmpty) {
    throw const CCPackageWorkspaceException(
      'No writable CCRouter Builder Packages were found.',
    );
  }
  final sortedPackageNames = packageNames.toList()..sort();
  final fingerprint = computeCCCanonicalJsonFingerprint(<String, Object?>{
    'hosts': [for (final item in workspaces) item.host.name]..sort(),
    'packages': sortedPackageNames,
    'dependencies': <String, Object?>{
      for (final item in workspaces)
        for (final package in item.packages.values)
          package.name: package.dependencies,
    },
    'targets': targets,
  });
  return _GenerationWatchTopology(
    workspace: workspace,
    workspaces: List.unmodifiable(workspaces),
    targets: List.unmodifiable(targets),
    targetRoots: Map.unmodifiable(targetRoots),
    packageNames: Set.unmodifiable(packageNames),
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
  required bool includeRegisteredHosts,
}) async {
  final protectionWatch = Stopwatch()..start();
  final targetRoots = <Directory>[
    for (final name in topology.targets) topology.targetRoots[name]!,
  ];
  final protectedOutputs = <_GeneratedArtifactsSnapshot>[
    await _GeneratedArtifactsSnapshot.captureOutside(
      buildContext.resolutionRoot,
      targetRoots,
    ),
    for (final root in {
      for (final candidate in topology.workspaces)
        for (final package in candidate.packages.values)
          if (!package.writable &&
              !_isWithin(buildContext.resolutionRoot, package.root))
            package.root.absolute.path: package.root,
    }.values)
      await _GeneratedArtifactsSnapshot.capture(
        root,
        stopAtNestedPackages: true,
      ),
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
    <CCPackageWorkspace>[topology.workspace],
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
  String? registrationStamp;
  try {
    resolutionBaseline = await CCPubResolutionFingerprint.capture(
      hostRoot: hostRoot,
      buildRoot: buildContext.resolutionRoot,
    );
    resolutionStamp = await _captureWatchResolutionStamp(
      hostRoot: hostRoot,
      buildRoot: buildContext.resolutionRoot,
    );
    if (includeRegisteredHosts) {
      registrationStamp = await _captureWatchRegistrationStamp(
        buildContext.resolutionRoot,
      );
    }
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
        if (includeRegisteredHosts) {
          final currentRegistrationStamp = await _captureWatchRegistrationStamp(
            buildContext.resolutionRoot,
          );
          if (currentRegistrationStamp != registrationStamp) {
            registrationStamp = currentRegistrationStamp;
            signals.add(const _GenerationWatchSignal.topologyChanged());
          }
        }
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

  Future<_GenerationWatchTopology?> topologyRequiringRestart({
    required bool removeMissingTargets,
  }) async {
    final current = await _resolveGenerationWatchTopology(
      hostRoot: hostRoot,
      buildContext: buildContext,
      includeRegisteredHosts: includeRegisteredHosts,
    );
    if (!topology.requiresRestartFor(
      current,
      removeMissingTargets: removeMissingTargets,
    )) {
      return null;
    }
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

  Future<bool> restartIfChanged({bool removeMissingTargets = false}) async {
    if (stop.isCompleted) return false;
    try {
      final changed = await topologyRequiringRestart(
        removeMissingTargets: removeMissingTargets,
      );
      if (stop.isCompleted) return false;
      if (changed == null) return false;
      await cycleSnapshot.restore();
      if (stop.isCompleted) return false;
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
    if (stop.isCompleted) return false;
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
    final aggregation = await _runSerializedWatchAggregation(
      buildContext.resolutionRoot,
      () => usesSubprocessReference
          ? _runWatchGenerationSubprocess(
              hostRoot: hostRoot,
              buildRoot: buildContext.resolutionRoot,
              watchCycle: true,
              lockHeld: true,
              profile: parsed.profile,
            )
          : runInProcessCycle(),
    );
    if (await restartIfChanged(removeMissingTargets: true)) return true;
    if (stop.isCompleted) return false;
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
      if (signal.topologyChanged) {
        if (!buildActive && !stop.isCompleted) await restartIfChanged();
        continue;
      }
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
        if (stop.isCompleted) break;
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
      final aggregation = await _runSerializedWatchAggregation(
        buildContext.resolutionRoot,
        () => usesSubprocessReference
            ? _runWatchGenerationSubprocess(
                hostRoot: hostRoot,
                buildRoot: buildContext.resolutionRoot,
                watchCycle: true,
                lockHeld: true,
                profile: parsed.profile,
              )
            : runInProcessCycle(),
      );
      if (await restartIfChanged()) continue;
      if (stop.isCompleted) break;
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
            includeRegisteredHosts: includeRegisteredHosts,
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

/// Cheap exact-enough wake-up stamp for active Host registration changes.
Future<String> _captureWatchRegistrationStamp(Directory buildRoot) async {
  final directory = _GenerationWatchRegistration._directory(buildRoot);
  if (!directory.existsSync()) return '';
  final files =
      directory
          .listSync(followLinks: false)
          .whereType<File>()
          .where((file) => file.path.endsWith('.json'))
          .toList()
        ..sort((left, right) => left.path.compareTo(right.path));
  final parts = <String>[];
  for (final file in files) {
    final stat = await file.stat();
    parts.add(
      '${path.basename(file.path)}\u0000${stat.size}\u0000'
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
  const _GenerationWatchSignal._({
    this.line,
    this.resolutionFingerprint,
    this.topologyChanged = false,
  });

  const _GenerationWatchSignal.line(String line) : this._(line: line);

  const _GenerationWatchSignal.resolutionChanged(String fingerprint)
    : this._(resolutionFingerprint: fingerprint);

  const _GenerationWatchSignal.topologyChanged()
    : this._(topologyChanged: true);

  final String? line;
  final String? resolutionFingerprint;
  final bool topologyChanged;
}

/// Observes authored Builder inputs so Flutter reload can wait for their cycle.
///
/// This observer records only a monotonic revision. It does not parse Dart,
/// classify declarations, or authorize skipping Builder work.
final class _GenerationWatchInputObserver {
  _GenerationWatchInputObserver._(this._subscriptions, this._onChanged);

  /// Starts bounded filesystem observation for writable generation Packages.
  static _GenerationWatchInputObserver start(
    Iterable<CCPackageWorkspace> workspaces,
    Future<void> Function() onChanged,
  ) {
    final subscriptions = <StreamSubscription<FileSystemEvent>>[];
    final observer = _GenerationWatchInputObserver._(subscriptions, onChanged);
    final packages = <String, CCResolvedPackage>{
      for (final workspace in workspaces)
        for (final package in workspace.packages.values)
          if (package.writable && package.declaresGenerationIntent)
            package.root.absolute.path: package,
    };
    for (final package in packages.values) {
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

/// Live Host registration consumed by the single build-root Builder owner.
final class _GenerationWatchRegistration {
  const _GenerationWatchRegistration._({
    required this.identity,
    required this.document,
    required this.lockFile,
    required this.lock,
  });

  final String identity;
  final File document;
  final File lockFile;
  final RandomAccessFile lock;
  static final Set<String> _ownedIdentities = <String>{};

  /// Publishes one Host and holds its registration lock until watch shutdown.
  static Future<_GenerationWatchRegistration> acquire({
    required Directory hostRoot,
    required Directory buildRoot,
    required String? leasePath,
  }) async {
    final directory = _directory(buildRoot);
    await directory.create(recursive: true);
    final identity = sha256
        .convert(utf8.encode(path.normalize(hostRoot.absolute.path)))
        .toString()
        .substring(0, 24);
    final document = File(path.join(directory.path, '$identity.json'));
    final lockFile = File(path.join(directory.path, '$identity.lock'));
    final lock = await lockFile.open(mode: FileMode.append);
    try {
      try {
        await lock.lock(FileLock.exclusive);
      } on FileSystemException {
        throw _GenerationWatchRegistrationConflictException(
          'Host ${hostRoot.absolute.path} already has an active CCRouter '
          'generation watch. Reuse or stop that Host watch before starting '
          'another one.',
        );
      }
      await _writeIfChanged(
        document,
        '${jsonEncode(<String, Object?>{'schemaVersion': 1, 'hostRoot': hostRoot.absolute.path, 'buildRoot': buildRoot.absolute.path, 'pid': pid, if (leasePath != null) 'leasePath': File(leasePath).absolute.path})}\n',
      );
      _ownedIdentities.add(identity);
      return _GenerationWatchRegistration._(
        identity: identity,
        document: document,
        lockFile: lockFile,
        lock: lock,
      );
    } on Object {
      await lock.close();
      rethrow;
    }
  }

  /// Returns only registrations whose process still owns the companion lock.
  static Future<List<Directory>> activeHostRoots(Directory buildRoot) async {
    final directory = _directory(buildRoot);
    if (!directory.existsSync()) return <Directory>[];
    final documents =
        directory
            .listSync(followLinks: false)
            .whereType<File>()
            .where((file) => file.path.endsWith('.json'))
            .toList()
          ..sort((left, right) => left.path.compareTo(right.path));
    final hosts = <String, Directory>{};
    for (final document in documents) {
      final stem = path.basenameWithoutExtension(document.path);
      final lockFile = File(path.join(directory.path, '$stem.lock'));
      try {
        final decoded = jsonDecode(await document.readAsString());
        if (decoded is! Map ||
            decoded['schemaVersion'] != 1 ||
            decoded['hostRoot'] is! String ||
            decoded['buildRoot'] is! String ||
            !path.equals(
              path.normalize('${decoded['buildRoot']}'),
              path.normalize(buildRoot.absolute.path),
            )) {
          continue;
        }
        if (!_ownedIdentities.contains(stem) && !await _isHeld(lockFile)) {
          continue;
        }
        final host = Directory(decoded['hostRoot'] as String).absolute;
        if (host.existsSync()) hosts[host.path] = host;
      } on Object {
        // A malformed or concurrently removed registration grants no scope.
      }
    }
    return hosts.values.toList()..sort((a, b) => a.path.compareTo(b.path));
  }

  static Directory _directory(Directory buildRoot) => Directory(
    path.join(
      buildRoot.path,
      '.dart_tool',
      'ccrouter',
      'v1',
      'watch',
      'registrations',
    ),
  );

  static Future<bool> _isHeld(File file) async {
    if (!file.existsSync()) return false;
    RandomAccessFile? opened;
    try {
      opened = await file.open(mode: FileMode.append);
      await opened.lock(FileLock.shared);
      await opened.unlock();
      return false;
    } on FileSystemException {
      return true;
    } finally {
      await opened?.close();
    }
  }

  /// Removes only this process's registration after releasing its OS lock.
  Future<void> release() async {
    _ownedIdentities.remove(identity);
    try {
      await lock.unlock();
    } finally {
      await lock.close();
    }
    if (document.existsSync()) await document.delete();
    if (lockFile.existsSync()) await lockFile.delete();
  }
}

/// Signals that one Host already owns its single status and lease lifecycle.
final class _GenerationWatchRegistrationConflictException implements Exception {
  const _GenerationWatchRegistrationConflictException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Serializes Host-specific aggregation while one Builder owner stays alive.
final class _GenerationWatchAggregationLock {
  const _GenerationWatchAggregationLock._(this.file);

  final RandomAccessFile file;

  static Future<_GenerationWatchAggregationLock> acquire(
    Directory buildRoot,
  ) async {
    final lockFile = File(
      path.join(
        buildRoot.path,
        '.dart_tool',
        'ccrouter',
        'v1',
        'watch',
        'aggregation.lock',
      ),
    );
    await lockFile.parent.create(recursive: true);
    final file = await lockFile.open(mode: FileMode.append);
    try {
      await file.lock(FileLock.blockingExclusive);
      return _GenerationWatchAggregationLock._(file);
    } on Object {
      await file.close();
      rethrow;
    }
  }

  Future<void> release() async {
    try {
      await file.unlock();
    } finally {
      await file.close();
    }
  }
}

Future<_GenerationCycleResult> _runSerializedWatchAggregation(
  Directory buildRoot,
  Future<_GenerationCycleResult> Function() operation,
) async {
  final lock = await _GenerationWatchAggregationLock.acquire(buildRoot);
  try {
    return await operation();
  } finally {
    await lock.release();
  }
}

File _generationWatchBuildRootStatusFile(Directory buildRoot) => File(
  path.join(
    buildRoot.path,
    '.dart_tool',
    'ccrouter',
    'v1',
    'watch',
    'builder-status.json',
  ),
);

Future<Map<String, Object?>?> _readGenerationWatchBuildRootStatus(
  Directory buildRoot,
) async {
  final file = _generationWatchBuildRootStatusFile(buildRoot);
  if (!file.existsSync()) return null;
  try {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map ||
        decoded['schemaVersion'] != 1 ||
        decoded['active'] is! bool ||
        decoded['pid'] is! int ||
        decoded['cycleRevision'] is! int ||
        decoded['failureRevision'] is! int ||
        decoded['targets'] is! List) {
      return null;
    }
    return decoded.cast<String, Object?>();
  } on Object {
    return null;
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
  bool _publishesBuildRootStatus = false;
  int _buildRootCycleRevision = 0;
  int _buildRootFailureRevision = 0;
  List<String> _buildRootTargets = const [];

  /// Marks this process as the single Builder owner for the shared build root.
  void becomeBuilderOwner() {
    _publishesBuildRootStatus = _usesMultiHostWatch;
    _status.setBuilderOwnerPid(pid);
  }

  /// Associates a subscriber Host with the current shared Builder owner.
  void followBuilderOwner(int ownerPid) {
    _status.setBuilderOwnerPid(ownerPid);
  }

  /// Rotates the child-session identity while retaining the outer watch lease.
  void beginNewSession() {
    _status.beginNewSession();
    if (_publishesBuildRootStatus) {
      _buildRootCycleRevision = 0;
      _buildRootFailureRevision = 0;
      _buildRootTargets = const [];
    }
  }

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
    if (_publishesBuildRootStatus) {
      if (type == 'targetsResolved') {
        _buildRootTargets =
            (data['packages'] as List?)?.whereType<String>().toList(
              growable: false,
            ) ??
            const [];
      }
      if (type == 'aggregationSucceeded' ||
          (type == 'failed' && data['stage'] == 'aggregation')) {
        _buildRootCycleRevision++;
      }
      if (type == 'failed' && data['stage'] == 'build') {
        _buildRootFailureRevision++;
      }
      final active =
          type != 'stopped' &&
          !(type == 'failed' &&
              const {
                'watch-start',
                'watch-exit',
                'generation-lock',
              }.contains(data['stage']));
      await _writeIfChanged(
        _generationWatchBuildRootStatusFile(buildRoot),
        '${jsonEncode(<String, Object?>{'schemaVersion': 1, 'active': active, 'pid': pid, 'sessionId': _status.sessionId, 'eventRevision': _status.eventRevision, 'lastEvent': type, 'cycleRevision': _buildRootCycleRevision, 'failureRevision': _buildRootFailureRevision, 'targets': _buildRootTargets, 'hostRoot': hostRoot.path, 'buildRoot': buildRoot.path, 'updatedAt': timestamp, if (type == 'failed') 'failureStage': data['stage'], if (type == 'failed' && data['diagnostics'] != null) 'failureDiagnostics': data['diagnostics']})}\n',
      );
    }
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
