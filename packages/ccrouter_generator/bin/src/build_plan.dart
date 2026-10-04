part of '../ccrouter_generator.dart';

/// Computes a fail-closed Build Plan for Builder and aggregation execution.
///
/// P2 permits a proven Host dependency-closure deletion to skip build_runner.
/// P3 additionally permits a pure Package addition when every added Package
/// carries a verified Portable Generation State. Every unproven fast-path miss
/// remains on the full Builder path. The local baseline contains no absolute
/// paths and is written only after a complete successful generation.
abstract final class _GenerationBuildPlanner {
  /// Current disposable planning-state schema.
  static const int _schemaVersion = 1;

  /// Compares current layered inputs with the last successful full generation.
  static Future<_GenerationBuildPlanInspection> inspect({
    required CCPackageWorkspace workspace,
    required _GenerationFastPathMissReason? fastPathMissReason,
    bool profile = false,
  }) async {
    try {
      return await _inspect(
        workspace: workspace,
        fastPathMissReason: fastPathMissReason,
        profile: profile,
      );
    } on Object {
      return const _GenerationBuildPlanInspection.runBuilder(
        reasons: ['planning-inspection-failed'],
      );
    }
  }

  /// Performs the strict comparison behind the failure-isolated entrypoint.
  static Future<_GenerationBuildPlanInspection> _inspect({
    required CCPackageWorkspace workspace,
    required _GenerationFastPathMissReason? fastPathMissReason,
    required bool profile,
  }) async {
    final forcedReason = switch (fastPathMissReason) {
      _GenerationFastPathMissReason.manifestMissing =>
        'fast-path-manifest-missing',
      _GenerationFastPathMissReason.manifestInvalid =>
        'fast-path-manifest-invalid',
      _GenerationFastPathMissReason.cacheInvalid => 'metadata-cache-invalid',
      _GenerationFastPathMissReason.outputChanged => 'managed-output-changed',
      _GenerationFastPathMissReason.inputChanged || null => null,
    };
    if (forcedReason != null) {
      return _GenerationBuildPlanInspection.runBuilder(reasons: [forcedReason]);
    }

    final previous = await _read(workspace);
    if (previous.status != _GenerationPlanningStateStatus.valid) {
      return _GenerationBuildPlanInspection.runBuilder(
        reasons: [
          previous.status == _GenerationPlanningStateStatus.missing
              ? 'planning-state-missing'
              : 'planning-state-invalid',
        ],
      );
    }

    final current = await _GenerationPlanningState.capture(workspace);
    final baseline = previous.state!;
    final inputDelta = profile
        ? _GenerationProfile.inputs(baseline, current)
        : null;
    final addedPackages = current.packages.keys
        .where((name) => !baseline.packages.containsKey(name))
        .toList(growable: false);
    final portableCandidates = <String>{
      for (final name in addedPackages)
        if (workspace.packages[name] case final package?
            when package.declaresGenerationIntent ||
                package.requiresPackageIndex ||
                package.indexFile.existsSync())
          name,
    };
    final portableVerifications = await _CCPortableGenerationState.verify(
      workspace,
      packageNames: portableCandidates,
    );
    final validPortableAdditions = <String>{};
    final reasons = <String>[];
    if (baseline.toolFingerprint != current.toolFingerprint) {
      reasons.add('tool-input-changed');
    }
    if (!baseline.toolResolutionPortable || !current.toolResolutionPortable) {
      reasons.add('tool-resolution-unproven');
    }

    for (final entry in current.packages.entries) {
      final package = entry.value;
      final old = baseline.packages[entry.key];
      if (package.builder) {
        if (old == null || !old.builder) {
          final portable = portableVerifications[entry.key];
          if (old == null && (portable?.valid ?? false)) {
            validPortableAdditions.add(entry.key);
          } else {
            reasons.add(
              old == null && portable != null
                  ? 'portable-state-${portable.reason.name}:${entry.key}'
                  : 'builder-package-added:${entry.key}',
            );
          }
          continue;
        }
        if (package.authoredInputFingerprint != old.authoredInputFingerprint) {
          reasons.add('authored-input-changed:${entry.key}');
        }
        if (!old.resolutionPortable || !package.resolutionPortable) {
          reasons.add('resolution-unproven:${entry.key}');
        } else if (package.resolutionFingerprint != old.resolutionFingerprint) {
          reasons.add('resolution-changed:${entry.key}');
        }
        if (package.metadataFingerprint != old.metadataFingerprint) {
          reasons.add('builder-metadata-changed:${entry.key}');
        }
        if (package.managedOutputFingerprint != old.managedOutputFingerprint) {
          reasons.add('package-output-changed:${entry.key}');
        }
        continue;
      }

      if (!package.writable && package.indexFingerprint != null) {
        if (old == null) {
          final portable = portableVerifications[entry.key];
          if (portable?.valid ?? false) {
            validPortableAdditions.add(entry.key);
          } else {
            reasons.add(
              portable == null
                  ? 'external-package-added-unproven:${entry.key}'
                  : 'portable-state-${portable.reason.name}:${entry.key}',
            );
          }
        } else if (package.indexFingerprint != old.indexFingerprint) {
          reasons.add('external-index-changed:${entry.key}');
        }
      }
    }
    for (final entry in baseline.packages.entries) {
      final currentPackage = current.packages[entry.key];
      if (entry.value.builder &&
          currentPackage != null &&
          !currentPackage.builder) {
        reasons.add('builder-package-disabled:${entry.key}');
      }
    }

    if (reasons.isNotEmpty) {
      reasons.sort();
      return _GenerationBuildPlanInspection.runBuilder(
        reasons: reasons,
        inputDelta: inputDelta,
      );
    }
    final hostGraphChanged =
        baseline.hostGraphFingerprint != current.hostGraphFingerprint;
    final removedPackages = baseline.packages.keys
        .where((name) => !current.packages.containsKey(name))
        .toList(growable: false);
    final pureRemoval =
        hostGraphChanged && removedPackages.isNotEmpty && addedPackages.isEmpty;
    final purePortableAddition =
        hostGraphChanged &&
        addedPackages.isNotEmpty &&
        removedPackages.isEmpty &&
        portableCandidates.isNotEmpty &&
        portableCandidates.length == validPortableAdditions.length;
    return _GenerationBuildPlanInspection.aggregateOnly(
      inputDelta: inputDelta,
      reasons: [
        !hostGraphChanged ? 'non-builder-input-only' : 'host-graph-changed',
        if (purePortableAddition)
          'portable-packages-added:${(validPortableAdditions.toList()..sort()).join('+')}',
      ],
      aggregateOnlyEligible: pureRemoval || purePortableAddition,
      prebuiltPackages: {
        for (final name in validPortableAdditions)
          if (workspace.packages[name]?.writable ?? false) name,
      },
    );
  }

  /// Writes a new baseline only when generation inputs stayed stable.
  static Future<void> write({
    required CCPackageWorkspace workspace,
    required String expectedInputFingerprint,
  }) async {
    final input = await _GenerationStateFingerprint.captureInput(workspace);
    if (input != expectedInputFingerprint) return;
    final state = await _GenerationPlanningState.capture(workspace);
    final payload = state.toJson();
    final document = <String, Object?>{
      ...payload,
      'contentFingerprint': computeCCCanonicalJsonFingerprint(payload),
    };
    final contents =
        '${const JsonEncoder.withIndent('  ').convert(document)}\n';
    await _writeIfChanged(_stateFile(workspace), contents);
  }

  /// Loads and verifies the previous Host-specific planning state.
  static Future<_GenerationPlanningStateRead> _read(
    CCPackageWorkspace workspace,
  ) async {
    final file = _stateFile(workspace);
    if (!file.existsSync()) {
      return const _GenerationPlanningStateRead.missing();
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) throw const FormatException('Expected an object.');
      final document = decoded.cast<String, Object?>();
      final fingerprint = document.remove('contentFingerprint');
      if (fingerprint is! String ||
          computeCCCanonicalJsonFingerprint(document) != fingerprint) {
        throw const FormatException('Planning fingerprint mismatch.');
      }
      final state = _GenerationPlanningState.fromJson(document);
      if (state.hostPackage != workspace.host.name) {
        throw const FormatException('Planning Host mismatch.');
      }
      return _GenerationPlanningStateRead.valid(state);
    } on Object {
      return const _GenerationPlanningStateRead.invalid();
    }
  }

  /// Resolves a Host-specific local state file without embedding that path.
  static File _stateFile(CCPackageWorkspace workspace) {
    final identity = computeCCCanonicalJsonFingerprint(<String, Object?>{
      'host': workspace.host.name,
      'root': path.relative(
        workspace.host.root.path,
        from: workspace.buildRoot.path,
      ),
    });
    return File(
      path.join(
        workspace.buildRoot.path,
        '.dart_tool',
        'ccrouter',
        'v1',
        'build_plans',
        '$identity.json',
      ),
    );
  }
}

/// Planned execution mode for one fast-path miss.
enum _GenerationBuildPlan {
  /// Only Host/Catalog aggregation appears necessary from proven inputs.
  aggregateOnly,

  /// At least one Builder input or trusted state boundary changed.
  runBuilder,
}

/// One planning decision with a separately gated actual execution path.
final class _GenerationBuildPlanInspection {
  /// Creates an aggregation-only suggestion for diagnostic comparison.
  const _GenerationBuildPlanInspection.aggregateOnly({
    required this.reasons,
    required this.aggregateOnlyEligible,
    this.prebuiltPackages = const <String>{},
    this.inputDelta,
  }) : suggested = _GenerationBuildPlan.aggregateOnly;

  /// Creates a conservative full-Builder decision.
  const _GenerationBuildPlanInspection.runBuilder({
    required this.reasons,
    this.inputDelta,
  }) : suggested = _GenerationBuildPlan.runBuilder,
       aggregateOnlyEligible = false,
       prebuiltPackages = const <String>{};

  /// Suggested path derived from verified layered state.
  final _GenerationBuildPlan suggested;

  /// Stable, sanitized causes used for profile diagnostics.
  final List<String> reasons;

  /// Optional observations, never consulted by execution or content proofs.
  final Map<String, Object?>? inputDelta;

  /// Whether this change has a complete deletion or portable-addition proof.
  final bool aggregateOnlyEligible;

  /// Writable added Packages whose published metadata replaces Builder cache.
  final Set<String> prebuiltPackages;

  /// Actual path after applying the proven scope and emergency kill switch.
  _GenerationBuildPlan get actual {
    if (suggested != _GenerationBuildPlan.aggregateOnly ||
        !aggregateOnlyEligible) {
      return _GenerationBuildPlan.runBuilder;
    }
    return Platform.environment['CCROUTER_DISABLE_AGGREGATE_ONLY'] == '1'
        ? _GenerationBuildPlan.runBuilder
        : _GenerationBuildPlan.aggregateOnly;
  }

  /// Whether this invocation must execute build_runner.
  bool get runsBuilder => actual == _GenerationBuildPlan.runBuilder;

  /// Prebuilt local Packages trusted only on the actual aggregation-only path.
  Set<String> get actualPrebuiltPackages =>
      actual == _GenerationBuildPlan.aggregateOnly
      ? prebuiltPackages
      : const <String>{};

  /// Bounded profile line that distinguishes suggestion from actual execution.
  String get profileDescription {
    const limit = 12;
    final actualReasons = <String>[
      ...reasons,
      if (suggested == _GenerationBuildPlan.aggregateOnly &&
          !aggregateOnlyEligible)
        'p2-scope-excluded',
      if (suggested == _GenerationBuildPlan.aggregateOnly &&
          aggregateOnlyEligible &&
          actual == _GenerationBuildPlan.runBuilder)
        'aggregate-only-disabled',
    ];
    final visible = actualReasons.take(limit).toList();
    if (actualReasons.length > limit) {
      visible.add('and-${actualReasons.length - limit}-more');
    }
    return 'CCRouter profile build-plan '
        'suggested=${suggested.name} actual=${actual.name} '
        'reasons=${visible.join(',')}';
  }
}

/// Fully content-addressed Tool, Package, and Host planning baseline.
final class _GenerationPlanningState {
  /// Creates one immutable planning baseline.
  const _GenerationPlanningState({
    required this.hostPackage,
    required this.toolFingerprint,
    required this.toolResolutionPortable,
    required this.hostGraphFingerprint,
    required this.packages,
  });

  /// Host Package owning this state file.
  final String hostPackage;

  /// Portable generator, SDK, and build-tool digest.
  final String toolFingerprint;

  /// Whether build tool resolution avoids unverified external Path sources.
  final bool toolResolutionPortable;

  /// Host closure and dependency-edge digest.
  final String hostGraphFingerprint;

  /// Per-Package source, resolution, metadata, and output facts.
  final Map<String, _GenerationPackagePlanningState> packages;

  /// Captures the current workspace without retaining filesystem paths.
  static Future<_GenerationPlanningState> capture(
    CCPackageWorkspace workspace,
  ) async {
    final resolution = await _GenerationResolutionPlanningContext.load(
      workspace,
    );
    final authored = <String, String>{};
    final indexes = <String, String?>{};
    for (final package in workspace.packages.values) {
      if (package.writable) {
        authored[package.name] =
            await _GenerationStateFingerprint.capturePackageAuthoredInput(
              package,
            );
      }
      indexes[package.name] = await _fileFingerprint(package.indexFile);
    }
    await resolution.addPathAuthoredFingerprints(authored);

    final packageStates = <String, _GenerationPackagePlanningState>{};
    final names = workspace.packages.keys.toList()..sort();
    for (final name in names) {
      final package = workspace.packages[name]!;
      final builder = package.writable && package.declaresGenerationIntent;
      final resolutionState = resolution.packageIdentity(
        package,
        authoredFingerprints: authored,
        indexFingerprints: indexes,
      );
      String? metadataFingerprint;
      String? outputFingerprint;
      if (package.writable) {
        metadataFingerprint = (await readCCPackageMetadata(
          workspace.intermediateMetadataDirectory(package),
        )).fingerprint;
        outputFingerprint = _GenerationStateFingerprint.digestEntries(
          await _GenerationStateFingerprint.capturePackageOutput(package),
        );
      }
      packageStates[name] = _GenerationPackagePlanningState(
        writable: package.writable,
        builder: builder,
        authoredInputFingerprint: authored[name],
        resolutionFingerprint: computeCCCanonicalJsonFingerprint(
          resolutionState.identity,
        ),
        resolutionPortable: resolutionState.portable,
        metadataFingerprint: metadataFingerprint,
        managedOutputFingerprint: outputFingerprint,
        indexFingerprint: indexes[name],
      );
    }

    final toolIdentity = resolution.toolIdentity(
      authoredFingerprints: authored,
      indexFingerprints: indexes,
    );
    final toolFingerprint =
        await _GenerationStateFingerprint.capturePortableToolInput(
          toolIdentity.identity,
        );
    final hostGraph = <String, Object?>{
      'host': workspace.host.name,
      'packages': [
        for (final name in names)
          <String, Object?>{
            'name': name,
            'version': workspace.packages[name]!.version,
            'writable': workspace.packages[name]!.writable,
            'dependencies': workspace.packages[name]!.dependencies,
            'indexFingerprint': indexes[name],
          },
      ],
    };
    return _GenerationPlanningState(
      hostPackage: workspace.host.name,
      toolFingerprint: toolFingerprint,
      toolResolutionPortable: toolIdentity.portable,
      hostGraphFingerprint: computeCCCanonicalJsonFingerprint(hostGraph),
      packages: Map.unmodifiable(packageStates),
    );
  }

  /// Decodes an integrity-checked state document.
  factory _GenerationPlanningState.fromJson(Map<String, Object?> json) {
    if (json['schemaVersion'] != _GenerationBuildPlanner._schemaVersion ||
        json['generatorVersion'] != ccrouterPackageIndexGeneratorVersion ||
        json['hostPackage'] is! String ||
        json['toolFingerprint'] is! String ||
        json['toolResolutionPortable'] is! bool ||
        json['hostGraphFingerprint'] is! String ||
        json['packages'] is! Map) {
      throw const FormatException('Unsupported planning state.');
    }
    final packages = <String, _GenerationPackagePlanningState>{};
    for (final entry in (json['packages']! as Map).entries) {
      if (entry.key is! String || entry.value is! Map) {
        throw const FormatException('Invalid planning Package state.');
      }
      packages[entry.key as String] = _GenerationPackagePlanningState.fromJson(
        (entry.value as Map).cast<String, Object?>(),
      );
    }
    return _GenerationPlanningState(
      hostPackage: json['hostPackage']! as String,
      toolFingerprint: json['toolFingerprint']! as String,
      toolResolutionPortable: json['toolResolutionPortable']! as bool,
      hostGraphFingerprint: json['hostGraphFingerprint']! as String,
      packages: Map.unmodifiable(packages),
    );
  }

  /// Encodes deterministic portable state before the outer integrity digest.
  Map<String, Object?> toJson() {
    final names = packages.keys.toList()..sort();
    return <String, Object?>{
      'schemaVersion': _GenerationBuildPlanner._schemaVersion,
      'generatorVersion': ccrouterPackageIndexGeneratorVersion,
      'hostPackage': hostPackage,
      'toolFingerprint': toolFingerprint,
      'toolResolutionPortable': toolResolutionPortable,
      'hostGraphFingerprint': hostGraphFingerprint,
      'packages': <String, Object?>{
        for (final name in names) name: packages[name]!.toJson(),
      },
    };
  }
}

/// One Package slice of the portable planning baseline.
final class _GenerationPackagePlanningState {
  /// Creates one immutable Package planning slice.
  const _GenerationPackagePlanningState({
    required this.writable,
    required this.builder,
    required this.authoredInputFingerprint,
    required this.resolutionFingerprint,
    required this.resolutionPortable,
    required this.metadataFingerprint,
    required this.managedOutputFingerprint,
    required this.indexFingerprint,
  });

  /// Whether this invocation owns the Package files.
  final bool writable;

  /// Whether build_runner targets this Package for CCRouter generation.
  final bool builder;

  /// Exact authored source and Package configuration digest.
  final String? authoredInputFingerprint;

  /// Normalized transitive resolution identity digest.
  final String resolutionFingerprint;

  /// Whether the resolution avoids an unverified external Path dependency.
  final bool resolutionPortable;

  /// Exact Builder metadata digest for writable Packages.
  final String? metadataFingerprint;

  /// Exact managed source-output digest for writable Packages.
  final String? managedOutputFingerprint;

  /// Exact published Package Index bytes, when present.
  final String? indexFingerprint;

  /// Decodes one Package state with strict field types.
  factory _GenerationPackagePlanningState.fromJson(Map<String, Object?> json) {
    bool optionalString(String key) => json[key] == null || json[key] is String;
    if (json['writable'] is! bool ||
        json['builder'] is! bool ||
        !optionalString('authoredInputFingerprint') ||
        json['resolutionFingerprint'] is! String ||
        json['resolutionPortable'] is! bool ||
        !optionalString('metadataFingerprint') ||
        !optionalString('managedOutputFingerprint') ||
        !optionalString('indexFingerprint')) {
      throw const FormatException('Invalid planning Package fields.');
    }
    return _GenerationPackagePlanningState(
      writable: json['writable']! as bool,
      builder: json['builder']! as bool,
      authoredInputFingerprint: json['authoredInputFingerprint'] as String?,
      resolutionFingerprint: json['resolutionFingerprint']! as String,
      resolutionPortable: json['resolutionPortable']! as bool,
      metadataFingerprint: json['metadataFingerprint'] as String?,
      managedOutputFingerprint: json['managedOutputFingerprint'] as String?,
      indexFingerprint: json['indexFingerprint'] as String?,
    );
  }

  /// Encodes one deterministic Package state.
  Map<String, Object?> toJson() => <String, Object?>{
    'writable': writable,
    'builder': builder,
    'authoredInputFingerprint': authoredInputFingerprint,
    'resolutionFingerprint': resolutionFingerprint,
    'resolutionPortable': resolutionPortable,
    'metadataFingerprint': metadataFingerprint,
    'managedOutputFingerprint': managedOutputFingerprint,
    'indexFingerprint': indexFingerprint,
  };
}

/// Read outcome that distinguishes first use from state corruption.
final class _GenerationPlanningStateRead {
  /// Creates a successful verified state read.
  const _GenerationPlanningStateRead.valid(this.state)
    : status = _GenerationPlanningStateStatus.valid;

  /// Creates a first-use result with no prior file.
  const _GenerationPlanningStateRead.missing()
    : status = _GenerationPlanningStateStatus.missing,
      state = null;

  /// Creates a fail-closed result for malformed or incompatible state.
  const _GenerationPlanningStateRead.invalid()
    : status = _GenerationPlanningStateStatus.invalid,
      state = null;

  /// Integrity classification of this read.
  final _GenerationPlanningStateStatus status;

  /// Verified state, available only for [status] `valid`.
  final _GenerationPlanningState? state;
}

/// Integrity status of one planning-state read.
enum _GenerationPlanningStateStatus {
  /// No state was written yet.
  missing,

  /// The state exists but cannot be trusted.
  invalid,

  /// Schema and content fingerprint both passed.
  valid,
}

/// Normalized Pub graph, lock, and language-version facts.
final class _GenerationResolutionPlanningContext {
  /// Creates one context from already normalized resolution documents.
  const _GenerationResolutionPlanningContext({
    required this.graph,
    required this.lock,
    required this.config,
    required this.roots,
  });

  /// Full Package graph keyed by Package name.
  final Map<String, Map<String, Object?>> graph;

  /// Sanitized lock identities keyed by Package name.
  final Map<String, Map<String, Object?>> lock;

  /// Portable Package config fields keyed by Package name.
  final Map<String, Map<String, Object?>> config;

  /// Resolved Package roots used only to hash local Path sources.
  ///
  /// Paths never enter a persisted identity; only their authored bytes do.
  final Map<String, Directory> roots;

  /// Loads resolution state without retaining root URIs or local paths.
  static Future<_GenerationResolutionPlanningContext> load(
    CCPackageWorkspace workspace,
  ) async {
    final dartTool = Directory(
      path.join(workspace.buildRoot.path, '.dart_tool'),
    );
    final graphDocument = jsonDecode(
      await File(path.join(dartTool.path, 'package_graph.json')).readAsString(),
    );
    final configDocument = jsonDecode(
      await File(
        path.join(dartTool.path, 'package_config.json'),
      ).readAsString(),
    );
    final graph = <String, Map<String, Object?>>{};
    for (final entry in _planningObjects((graphDocument as Map)['packages'])) {
      final name = '${entry['name'] ?? ''}';
      if (name.isNotEmpty) graph[name] = entry;
    }
    final config = <String, Map<String, Object?>>{};
    final roots = <String, Directory>{};
    for (final entry in _planningObjects((configDocument as Map)['packages'])) {
      final name = '${entry['name'] ?? ''}';
      if (name.isEmpty) continue;
      config[name] = <String, Object?>{
        'languageVersion': entry['languageVersion'],
        'packageUri': entry['packageUri'],
      };
      final rootUri = '${entry['rootUri'] ?? ''}';
      if (rootUri.isNotEmpty) {
        final resolved = File(
          path.join(
            workspace.buildRoot.path,
            '.dart_tool',
            'package_config.json',
          ),
        ).uri.resolve(rootUri);
        if (resolved.scheme == 'file') {
          roots[name] = Directory.fromUri(resolved).absolute;
        }
      }
    }
    final lock = <String, Map<String, Object?>>{};
    final lockFile = File(path.join(workspace.buildRoot.path, 'pubspec.lock'));
    if (lockFile.existsSync()) {
      final document = loadYaml(await lockFile.readAsString());
      final packages = document is YamlMap ? document['packages'] : null;
      if (packages is YamlMap) {
        for (final entry in packages.entries) {
          if (entry.key is! String || entry.value is! YamlMap) continue;
          lock[entry.key as String] = _sanitizeLockEntry(
            entry.value as YamlMap,
          );
        }
      }
    }
    return _GenerationResolutionPlanningContext(
      graph: Map.unmodifiable(graph),
      lock: Map.unmodifiable(lock),
      config: Map.unmodifiable(config),
      roots: Map.unmodifiable(roots),
    );
  }

  /// Adds content identities for resolved Path Packages outside the workspace.
  ///
  /// Resolution identities never persist the resolved roots. Hashing every
  /// Path Package here lets both the local Build Plan and Portable Generation
  /// State prove the same dependency graph without trusting local paths.
  Future<void> addPathAuthoredFingerprints(
    Map<String, String> authoredFingerprints,
  ) async {
    final names =
        lock.entries
            .where(
              (entry) =>
                  entry.value['source'] == 'path' &&
                  !authoredFingerprints.containsKey(entry.key),
            )
            .map((entry) => entry.key)
            .toList()
          ..sort();
    for (final name in names) {
      final root = roots[name];
      final packageGraph = graph[name];
      if (root == null || packageGraph == null) continue;
      final package = CCResolvedPackage(
        name: name,
        version: '${packageGraph['version'] ?? '0.0.0'}',
        root: root,
        dependencies: _planningStrings(packageGraph['dependencies']),
        devDependencies: _planningStrings(packageGraph['devDependencies']),
        writable: false,
      );
      authoredFingerprints[name] =
          await _GenerationStateFingerprint.capturePackageAuthoredInput(
            package,
          );
    }
  }

  /// Builds a Package-specific transitive identity and portability decision.
  ///
  /// Distribution proofs omit producer-only development edges and transport
  /// identities for content-backed Packages. The local Build Plan retains
  /// those inputs to invalidate builds when the author's tool setup changes.
  _GenerationResolutionIdentity packageIdentity(
    CCResolvedPackage package, {
    required Map<String, String> authoredFingerprints,
    required Map<String, String?> indexFingerprints,
    bool forDistribution = false,
  }) => _identityForRoots(
    [package.name],
    authoredFingerprints: authoredFingerprints,
    indexFingerprints: indexFingerprints,
    rootDevDependencies: !forDistribution,
    forDistribution: forDistribution,
  );

  /// Builds the build_runner/generator toolchain identity.
  ///
  /// Development dependencies of tool Packages are not executed by the Host.
  /// Distribution mode uses authored content where available, preserving lock
  /// identities for the remaining resolved tool dependencies.
  _GenerationResolutionIdentity toolIdentity({
    required Map<String, String> authoredFingerprints,
    required Map<String, String?> indexFingerprints,
    bool forDistribution = false,
  }) => _identityForRoots(
    const ['build_runner', 'ccrouter_generator'],
    authoredFingerprints: authoredFingerprints,
    indexFingerprints: indexFingerprints,
    rootDevDependencies: false,
    forDistribution: forDistribution,
  );

  /// Traverses deterministic graph slices from [roots].
  _GenerationResolutionIdentity _identityForRoots(
    Iterable<String> roots, {
    required Map<String, String> authoredFingerprints,
    required Map<String, String?> indexFingerprints,
    required bool rootDevDependencies,
    required bool forDistribution,
  }) {
    final rootSet = roots.where(graph.containsKey).toSet();
    final pending = rootSet.toList()..sort();
    final names = <String>{};
    while (pending.isNotEmpty) {
      final name = pending.removeLast();
      if (!names.add(name)) continue;
      final package = graph[name];
      if (package == null) continue;
      final dependencies = <String>[
        ..._planningStrings(package['dependencies']),
        if (rootDevDependencies && rootSet.contains(name))
          ..._planningStrings(package['devDependencies']),
      ]..sort();
      pending.addAll(dependencies.where(graph.containsKey));
    }
    final sorted = names.toList()..sort();
    var portable = true;
    final packages = <Map<String, Object?>>[];
    for (final name in sorted) {
      final package = graph[name]!;
      final lockIdentity = lock[name];
      final source = '${lockIdentity?['source'] ?? 'workspace'}';
      final authored = authoredFingerprints[name];
      if (source == 'path' && authored == null) portable = false;
      packages.add(<String, Object?>{
        'name': name,
        'version': package['version'],
        'dependencies': _planningStrings(package['dependencies'])..sort(),
        if (rootDevDependencies && rootSet.contains(name))
          'devDependencies': _planningStrings(package['devDependencies'])
            ..sort(),
        'config': config[name],
        // Source-controlled proofs cannot contain their own eventual Git ref
        // or archive hash. Exact authored bytes also prove content-backed
        // dependencies independently of workspace/Path/Git transport. Other
        // dependencies retain their lock identity. The local Build Plan keeps
        // its stricter source identity and root development dependency graph.
        'lock': forDistribution && authored != null ? null : lockIdentity,
        'authoredFingerprint': authored,
        'indexFingerprint': indexFingerprints[name],
      });
    }
    return _GenerationResolutionIdentity(
      identity: <String, Object?>{
        'roots': rootSet.toList()..sort(),
        'packages': packages,
      },
      portable: portable,
    );
  }
}

/// One normalized resolution digest input plus its portability proof.
final class _GenerationResolutionIdentity {
  /// Creates one immutable resolution identity.
  const _GenerationResolutionIdentity({
    required this.identity,
    required this.portable,
  });

  /// Canonical JSON-compatible identity without absolute paths.
  final Map<String, Object?> identity;

  /// Whether every Path dependency is backed by writable authored content.
  final bool portable;
}

/// Returns a SHA-256 digest for one optional file.
Future<String?> _fileFingerprint(File file) async => file.existsSync()
    ? sha256.convert(await file.readAsBytes()).toString()
    : null;

/// Converts a generated JSON array into object-typed maps.
List<Map<String, Object?>> _planningObjects(Object? value) => value is List
    ? value
          .whereType<Map>()
          .map((entry) => entry.cast<String, Object?>())
          .toList(growable: false)
    : const [];

/// Converts a graph field into stable string values.
List<String> _planningStrings(Object? value) => value is List
    ? value.whereType<String>().toList(growable: false)
    : <String>[];

/// Removes local paths and repository URLs from one lockfile identity.
Map<String, Object?> _sanitizeLockEntry(YamlMap entry) {
  final source = '${entry['source'] ?? ''}';
  final description = entry['description'];
  Object? safeDescription;
  if (description is YamlMap) {
    safeDescription = switch (source) {
      'hosted' => <String, Object?>{
        'name': description['name'],
        'sha256': description['sha256'],
      },
      'git' => <String, Object?>{
        'resolvedRef': description['resolved-ref'],
        'path': description['path'],
      },
      'sdk' => <String, Object?>{'sdk': description['sdk']},
      'path' => const <String, Object?>{'kind': 'external-path'},
      _ => <String, Object?>{'kind': source},
    };
  } else if (source == 'sdk') {
    safeDescription = description;
  }
  return <String, Object?>{
    'source': source,
    'version': entry['version']?.toString(),
    'description': safeDescription,
  };
}
