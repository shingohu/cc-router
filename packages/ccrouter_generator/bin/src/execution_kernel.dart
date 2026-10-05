part of '../ccrouter_generator.dart';

final _commandStdoutZoneKey = Object();
final _commandStderrZoneKey = Object();
final _generationCycleModeZoneKey = Object();
const _sharedPlanningSnapshotKillSwitch =
    'CCROUTER_DISABLE_SHARED_PLANNING_SNAPSHOT';

/// Output channel scoped to one command or in-process generation cycle.
final class _CommandOutputSink {
  const _CommandOutputSink.system(this._system) : _buffer = null;

  const _CommandOutputSink.buffer(this._buffer) : _system = null;

  final IOSink? _system;
  final StringBuffer? _buffer;

  void write(Object? value) {
    _system?.write(value);
    _buffer?.write(value);
  }

  void writeln([Object? value = '']) {
    _system?.writeln(value);
    _buffer?.writeln(value);
  }

  Future<void> addStream(Stream<List<int>> stream) async {
    final system = _system;
    if (system != null) {
      await system.addStream(stream);
      return;
    }
    _buffer!.write(await utf8.decodeStream(stream));
  }
}

_CommandOutputSink get _commandStdout =>
    Zone.current[_commandStdoutZoneKey] as _CommandOutputSink? ??
    _CommandOutputSink.system(stdout);

_CommandOutputSink get _commandStderr =>
    Zone.current[_commandStderrZoneKey] as _CommandOutputSink? ??
    _CommandOutputSink.system(stderr);

/// Explicit execution context shared by one-shot and watch cycles.
final class _GenerationCycleMode {
  const _GenerationCycleMode({
    required this.watchCycle,
    required this.lockHeld,
    required this.optimized,
  });

  final bool watchCycle;
  final bool lockHeld;
  final bool optimized;
}

_GenerationCycleMode? get _generationCycleMode =>
    Zone.current[_generationCycleModeZoneKey] as _GenerationCycleMode?;

/// Structured result returned by both in-process and subprocess cycles.
final class _GenerationCycleResult {
  const _GenerationCycleResult({
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

/// Executes one complete generation transaction for CLI or watch.
Future<_GenerationCycleResult> _runGenerationCycle({
  required Directory root,
  required _BuildContext? buildContext,
  required _Arguments parsed,
  required Stopwatch invocationWatch,
  required _GenerationProfileTrace? invocationTrace,
  required bool watchCycle,
  required bool captureOutput,
}) async {
  final inheritedWatchCycle =
      Platform.environment[_watchCycleEnvironment] == '1';
  final effectiveWatchCycle = watchCycle || inheritedWatchCycle;
  final cycleParsed = watchCycle
      ? _Arguments(
          command: _GeneratorCommand.generate,
          rootPath: root.path,
          outputDirectoryPath: null,
          generateComponentRegistrars: true,
          profile: true,
        )
      : parsed;
  final cycleWatch = watchCycle ? (Stopwatch()..start()) : invocationWatch;
  final cycleTrace = watchCycle
      ? _GenerationProfileTrace(cycleWatch)
      : invocationTrace;
  final outputBuffer = captureOutput ? StringBuffer() : null;
  final errorBuffer = captureOutput ? StringBuffer() : null;
  var cycleExitCode = 0;
  Map<String, Object>? profileReport;
  Map<String, Object>? outputDelta;
  List<String>? outputChanges;

  Future<void> executeCycle(
    _Arguments parsed,
    Stopwatch totalWatch,
    _GenerationProfileTrace? profileTrace,
  ) async {
    _GenerationLock? generationLock;
    _GeneratedArtifactsSnapshot? snapshot;
    CCPackageWorkspace? fastPathWorkspace;
    String? verifiedInputFingerprint;
    _GenerationBuildPlanInspection? buildPlan;
    var profileOutcome = 'failed';
    try {
      if (buildContext != null && !_watchOwnsGenerationLock) {
        generationLock = await profileTrace.measure(
          'generation-lock-wait',
          () => _GenerationLock.acquire(buildContext.root),
        );
      }
      if (buildContext != null &&
          parsed.command == _GeneratorCommand.generate &&
          parsed.outputDirectoryPath == null) {
        fastPathWorkspace = await profileTrace.measure<CCPackageWorkspace>(
          'workspace-load',
          () => CCPackageWorkspace.load(
            buildRoot: buildContext.root,
            hostRoot: root,
            workspace: buildContext.workspace,
          ),
          counts: (workspace) => {'packages': workspace.packages.length},
        );
        // Explicit prepare must refresh Portable State even when the ordinary
        // generation manifest proves all managed inputs and outputs unchanged.
        if (parsed.noCache ||
            parsed.portablePrepare ||
            _usesOptimizedWatchCycle) {
          verifiedInputFingerprint = await profileTrace.measure(
            'input-fingerprint-capture',
            () => _GenerationStateFingerprint.captureInput(fastPathWorkspace!),
          );
          buildPlan = _usesOptimizedWatchCycle
              ? const _GenerationBuildPlanInspection.aggregateOnly(
                  reasons: ['build-runner-watch-completed'],
                  aggregateOnlyEligible: true,
                )
              : _GenerationBuildPlanInspection.runBuilder(
                  reasons: [
                    parsed.portablePrepare
                        ? 'portable-state-prepare'
                        : 'no-cache-reference',
                  ],
                );
          profileTrace?.skip('fast-path-inspection');
          profileTrace?.skip('build-plan-inspection');
        } else {
          final fastPath = await profileTrace.measure(
            'fast-path-inspection',
            () => _GenerationFastPath.inspect(workspace: fastPathWorkspace!),
          );
          verifiedInputFingerprint = fastPath.inputFingerprint;
          if (fastPath.matches) {
            _commandStdout.writeln(
              'CCRouter generation fast path hit; inputs and outputs are unchanged.',
            );
            if (parsed.check) {
              _commandStdout.writeln(
                'CCRouter generated artifacts are up to date.',
              );
            }
            if (parsed.profile) {
              _commandStdout.writeln('CCRouter profile fast-path=hit');
              _commandStdout.writeln(
                'CCRouter profile build-plan suggested=unchanged '
                'actual=unchanged reasons=verified-fast-path',
              );
              _commandStdout.writeln('CCRouter profile input-delta=unchanged');
              outputChanges = const [];
              outputDelta = _GenerationProfile.writeOutputs(outputChanges!);
            }
            profileTrace?.skip('build-plan-inspection');
            profileTrace?.skip('build-runner-process');
            profileTrace?.skip('workspace-aggregation');
            profileOutcome = 'success';
            return;
          }
          if (parsed.profile)
            _commandStdout.writeln('CCRouter profile fast-path=miss');
          buildPlan = await profileTrace.measure(
            'build-plan-inspection',
            () => _GenerationBuildPlanner.inspect(
              workspace: fastPathWorkspace!,
              fastPathMissReason: fastPath.missReason,
              profile: parsed.profile,
            ),
          );
        }
        verifiedInputFingerprint ??= await profileTrace.measure(
          'input-fingerprint-capture',
          () => _GenerationStateFingerprint.captureInput(fastPathWorkspace!),
        );
        if (parsed.profile) {
          _commandStdout.writeln(buildPlan!.profileDescription);
          _commandStdout.writeln(
            'CCRouter profile input-delta=${jsonEncode(buildPlan.inputDelta ?? const {'status': 'unavailable'})}',
          );
        }
      }
      if (parsed.command == _GeneratorCommand.generate) {
        fastPathWorkspace ??= await profileTrace.measure<CCPackageWorkspace>(
          'workspace-load',
          () => CCPackageWorkspace.load(
            buildRoot: buildContext!.root,
            hostRoot: root,
            workspace: buildContext.workspace,
          ),
          counts: (workspace) => {'packages': workspace.packages.length},
        );
        // build_runner cannot repair read-only dependency artifacts. Reject
        // stale external files before it sees missing generated libraries and
        // attempts incremental cleanup outside its writable build Packages.
        if (!await profileTrace.measure(
          'portable-state-readonly-verification',
          () => _CCPortableGenerationState.verifyReadOnly(fastPathWorkspace!),
          succeeded: (verified) => verified,
        )) {
          cycleExitCode = 1;
          return;
        }
        final preflightWatch = Stopwatch()..start();
        final issues = await profileTrace.measure(
          'component-dependency-preflight',
          () => _componentDependencyPreflight(fastPathWorkspace!),
          succeeded: (issues) => issues.isEmpty,
          counts: (issues) => {'issues': issues.length},
        );
        preflightWatch.stop();
        if (parsed.profile) {
          _commandStdout.writeln(
            'CCRouter profile dependency-preflight='
            '${preflightWatch.elapsedMilliseconds}ms',
          );
        }
        if (issues.isNotEmpty) {
          _writeComponentDependencyPreflightIssues(issues);
          cycleExitCode = 1;
          return;
        }
      }
      if (parsed.command == _GeneratorCommand.generate &&
          fastPathWorkspace != null) {
        // The plan was computed before preflight and may no longer describe the
        // files that are about to be handed to build_runner. Revalidate at the
        // execution boundary; a Host-graph-only plan must never skip Builder
        // work after an authored input changed in the meantime.
        final executionInput = await profileTrace.measure(
          'execution-boundary-fingerprint',
          () => _GenerationStateFingerprint.captureInput(fastPathWorkspace!),
        );
        if (verifiedInputFingerprint != null &&
            verifiedInputFingerprint != executionInput) {
          buildPlan = const _GenerationBuildPlanInspection.runBuilder(
            reasons: ['input-changed-before-execution'],
          );
          if (parsed.profile) {
            _commandStdout.writeln(
              'CCRouter profile build-plan-revalidated=runBuilder '
              'reason=input-changed-before-execution',
            );
          }
        }
        verifiedInputFingerprint = executionInput;
        if (_isWatchAggregationCycle && !_usesOptimizedWatchCycle) {
          buildPlan = const _GenerationBuildPlanInspection.aggregateOnly(
            reasons: ['build-runner-watch-succeeded'],
            aggregateOnlyEligible: true,
          );
          if (parsed.profile) {
            _commandStdout.writeln(buildPlan.profileDescription);
          }
        }
      }
      final needsBootstrap = await profileTrace.measure(
        'missing-generated-import-scan',
        () async =>
            parsed.command == _GeneratorCommand.generate &&
            fastPathWorkspace != null &&
            await _hasMissingGeneratedComponentImport(fastPathWorkspace),
      );
      snapshot = parsed.command == _GeneratorCommand.generate
          ? await profileTrace.measure(
              'artifact-snapshot-capture',
              () => _GeneratedArtifactsSnapshot.capture(
                buildContext!.root,
                explicitFiles: [
                  if (parsed.outputDirectoryPath case final output?)
                    for (final name in const [
                      'cc_routes.json',
                      'cc_catalog.md',
                      'cc_routes.md',
                      'cc_sources.md',
                    ])
                      File(path.join(output, name)).absolute,
                ],
              ),
            )
          : null;
      if (needsBootstrap) {
        try {
          if (await profileTrace.measure(
            'bootstrap-restore',
            () => _bootstrapGeneratedComponentApis(fastPathWorkspace!),
          )) {
            _commandStdout.writeln(
              'Bootstrapped generated component APIs from validated build metadata.',
            );
          }
        } on Object {
          await profileTrace.measure(
            'artifact-snapshot-restore',
            snapshot!.restore,
          );
        }
      } else {
        profileTrace?.skip('bootstrap-restore');
      }
      var buildDuration = Duration.zero;
      if (buildPlan?.runsBuilder ?? true) {
        final buildWatch = Stopwatch()..start();
        if (buildContext == null) {
          profileTrace?.skip('build-runner-process');
        } else if (!await profileTrace.measure(
          'build-runner-process',
          () => _runBuildRunner(
            buildContext,
            root,
            profile: parsed.profile,
            trace: profileTrace,
          ),
          succeeded: (succeeded) => succeeded,
        )) {
          if (snapshot != null) {
            await profileTrace.measure(
              'artifact-snapshot-restore',
              snapshot.restore,
            );
          }
          cycleExitCode = 1;
          return;
        }
        buildWatch.stop();
        buildDuration = buildWatch.elapsed;
      } else {
        profileTrace?.skip('build-runner-process');
        _commandStdout.writeln(
          'CCRouter generation aggregate-only path; verified Builder inputs '
          'are unchanged.',
        );
      }
      final succeeded = await profileTrace.measure(
        'workspace-aggregation',
        () => parsed.command == _GeneratorCommand.generate
            ? _generateResolvedWorkspace(
                root,
                parsed,
                buildContext!,
                buildDuration: buildDuration,
                expectedInputFingerprint: verifiedInputFingerprint,
                prebuiltPackages:
                    buildPlan?.actualPrebuiltPackages ?? const <String>{},
                trace: profileTrace,
              )
            : _aggregate(root, parsed),
        succeeded: (succeeded) => succeeded,
      );
      if (!succeeded) {
        if (snapshot != null) {
          await profileTrace.measure(
            'artifact-snapshot-restore',
            snapshot.restore,
          );
        }
        cycleExitCode = 1;
        return;
      }
      if (parsed.profile && snapshot != null) {
        try {
          final watch = Stopwatch()..start();
          outputChanges = await profileTrace.measure<List<String>>(
            'output-delta-scan',
            snapshot.changes,
            counts: (changes) => {'files': changes.length},
          );
          outputDelta = _GenerationProfile.writeOutputs(outputChanges!);
          _commandStdout.writeln(
            'CCRouter profile output-delta-scan=${watch.elapsedMilliseconds}ms',
          );
        } on Object {
          _commandStdout.writeln('CCRouter profile output-delta=unavailable');
        }
      }
      if (parsed.check && snapshot != null) {
        final changes = outputChanges ?? await snapshot.changes();
        await profileTrace.measure('check-restore', snapshot.restore);
        if (changes.isNotEmpty) {
          _commandStderr.writeln(
            'error: CCRouter generated artifacts are stale:',
          );
          for (final change in changes) {
            _commandStderr.writeln('  $change');
          }
          cycleExitCode = 1;
          return;
        }
        _commandStdout.writeln('CCRouter generated artifacts are up to date.');
      }
      if (buildContext != null &&
          parsed.command == _GeneratorCommand.generate &&
          parsed.outputDirectoryPath == null) {
        fastPathWorkspace ??= await profileTrace.measure(
          'workspace-reload-for-state',
          () => CCPackageWorkspace.load(
            buildRoot: buildContext.root,
            hostRoot: root,
            workspace: buildContext.workspace,
          ),
        );
        if (Platform.environment[_sharedPlanningSnapshotKillSwitch] == '1') {
          profileTrace?.skip('planning-snapshot-capture');
          await profileTrace.measure(
            'fast-path-manifest-write',
            () => _GenerationFastPath.write(
              workspace: fastPathWorkspace!,
              expectedInputFingerprint: verifiedInputFingerprint!,
            ),
          );
          try {
            await profileTrace.measure(
              'build-plan-state-write',
              () => _GenerationBuildPlanner.write(
                workspace: fastPathWorkspace!,
                expectedInputFingerprint: verifiedInputFingerprint!,
              ),
            );
          } on Object {
            if (parsed.profile) {
              _commandStdout.writeln(
                'CCRouter profile build-plan-state=write-failed; '
                'future runs will conservatively use runBuilder.',
              );
            }
          }
        } else {
          final planningSnapshot = await profileTrace.measure(
            'planning-snapshot-capture',
            () => _GenerationPlanningSnapshot.capture(fastPathWorkspace!),
          );
          if (planningSnapshot.inputFingerprint != verifiedInputFingerprint) {
            profileTrace?.skip('fast-path-manifest-write');
            profileTrace?.skip('build-plan-state-write');
          } else {
            await profileTrace.measure(
              'fast-path-manifest-write',
              () => _GenerationFastPath.writeSnapshot(
                workspace: fastPathWorkspace!,
                inputFingerprint: planningSnapshot.inputFingerprint,
                outputFingerprint: planningSnapshot.outputFingerprint,
              ),
            );
            try {
              await profileTrace.measure('build-plan-state-write', () async {
                final workspace = fastPathWorkspace!;
                final state = await planningSnapshot.capturePlanningState(
                  workspace,
                );
                await _GenerationBuildPlanner.writeSnapshot(
                  workspace: workspace,
                  state: state,
                );
              });
            } on Object {
              if (parsed.profile) {
                _commandStdout.writeln(
                  'CCRouter profile build-plan-state=write-failed; '
                  'future runs will conservatively use runBuilder.',
                );
              }
            }
          }
        }
      }
      profileOutcome = 'success';
    } on _GenerationWatchActiveException catch (error) {
      if (snapshot != null) {
        await profileTrace.measure(
          'artifact-snapshot-restore',
          snapshot.restore,
        );
      }
      _commandStderr.writeln('error: ${error.message}');
      cycleExitCode = 1;
    } on CCPackageWorkspaceException catch (error) {
      if (snapshot != null) {
        await profileTrace.measure(
          'artifact-snapshot-restore',
          snapshot.restore,
        );
      }
      _commandStderr.writeln('error: ${error.message}');
      cycleExitCode = 1;
    } catch (_) {
      if (snapshot != null) {
        await profileTrace.measure(
          'artifact-snapshot-restore',
          snapshot.restore,
        );
      }
      rethrow;
    } finally {
      try {
        if (generationLock != null) {
          await profileTrace.measure(
            'generation-lock-release',
            generationLock.release,
          );
        }
      } finally {
        totalWatch.stop();
        if (parsed.profile) {
          _commandStdout.writeln(
            'CCRouter profile total=${totalWatch.elapsedMilliseconds}ms',
          );
          profileReport = await profileTrace!.write(
            buildRoot: buildContext?.root ?? root,
            hostRoot: root,
            command: parsed.command.name,
            outcome: profileOutcome,
          );
        }
      }
    }
  }

  final zoneValues = <Object, Object?>{
    _generationCycleModeZoneKey: _GenerationCycleMode(
      watchCycle: effectiveWatchCycle,
      lockHeld:
          watchCycle ||
          (inheritedWatchCycle &&
              Platform.environment[_watchLockEnvironment] == '1'),
      optimized:
          effectiveWatchCycle &&
          Platform.environment[_watchCycleOptimizationKillSwitch] != '1',
    ),
    if (outputBuffer != null)
      _commandStdoutZoneKey: _CommandOutputSink.buffer(outputBuffer),
    if (errorBuffer != null)
      _commandStderrZoneKey: _CommandOutputSink.buffer(errorBuffer),
  };
  try {
    await runZoned(
      () => executeCycle(cycleParsed, cycleWatch, cycleTrace),
      zoneValues: zoneValues,
    );
  } on Object catch (error, stackTrace) {
    if (!captureOutput) rethrow;
    cycleExitCode = 1;
    errorBuffer!
      ..writeln('error: $error')
      ..writeln(stackTrace);
  }
  return _GenerationCycleResult(
    exitCode: cycleExitCode,
    elapsedMs: cycleWatch.elapsedMilliseconds,
    trace: profileReport,
    outputDelta: outputDelta,
    diagnostics: cycleExitCode == 0 ? null : errorBuffer?.toString().trim(),
  );
}

/// Owns the source boundary that can change generated artifacts.
///
/// Analyzer installation, scaffold templates, and the Pub hook are CLI
/// integrations. They are deliberately outside this boundary: changing one
/// must not invalidate a Host's generation planning state. The kernel list is
/// explicit and reviewable so a new generation dependency cannot silently
/// expand the tool fingerprint by scanning every file under `bin/`.
abstract final class CCGeneratorExecutionKernel {
  /// Returns the generator files whose bytes affect generation semantics.
  static Future<List<File>> files(Directory packageRoot) async {
    final result = <File>[];
    final lib = Directory(path.join(packageRoot.path, 'lib'));
    if (lib.existsSync()) {
      await for (final entity in lib.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File && entity.path.endsWith('.dart')) result.add(entity);
      }
    }
    for (final relative in const [
      'bin/ccrouter_generator.dart',
      'bin/src/build_plan.dart',
      'bin/src/execution_kernel.dart',
      // Owns the in-process cycle mode that decides whether Builder reruns.
      'bin/src/generation_watch.dart',
      'bin/src/portable_generation_state.dart',
    ]) {
      final file = File(
        path.joinAll([packageRoot.path, ...relative.split('/')]),
      );
      if (file.existsSync()) result.add(file);
    }
    result.sort((left, right) => left.path.compareTo(right.path));
    return result;
  }
}
