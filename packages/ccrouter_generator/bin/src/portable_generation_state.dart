part of '../ccrouter_generator.dart';

/// Stable Dart SDK version without operating-system or architecture suffixes.
String _portableDartVersion() => Platform.version.split(RegExp(r'\s+')).first;

/// Cross-clone proof that one Package's generated artifacts match its inputs.
///
/// The state is source-controlled beside the Package index. It contains only
/// content identities and never stores an absolute path, timestamp, user name,
/// or local cache location. Consumers always recompute every identity before
/// trusting prebuilt metadata.
abstract final class _CCPortableGenerationState {
  /// Current portable-state schema.
  static const int schemaVersion = 1;

  /// Managed file published beside `ccrouter_package.json`.
  static const String fileName = 'ccrouter_generation_state.json';

  /// Verifies selected Packages against their current source and output bytes.
  static Future<Map<String, _CCPortableGenerationStateVerification>> verify(
    CCPackageWorkspace workspace, {
    required Set<String> packageNames,
  }) async {
    if (packageNames.isEmpty) return const {};
    final context = await _CCPortableGenerationContext.capture(workspace);
    final result = <String, _CCPortableGenerationStateVerification>{};
    final names = packageNames.toList()..sort();
    for (final name in names) {
      final package = workspace.packages[name];
      if (package == null) continue;
      result[name] = await _verifyPackage(package, context);
    }
    return Map.unmodifiable(result);
  }

  /// Writes deterministic state only for Packages that publish an index.
  static Future<void> write(
    CCPackageWorkspace workspace, {
    required Map<String, CCPackageIndex> indexes,
  }) async {
    final writableNames = indexes.keys
        .where((name) => workspace.packages[name]?.writable ?? false)
        .toSet();
    if (writableNames.isEmpty) return;
    final context = await _CCPortableGenerationContext.capture(workspace);
    final names = writableNames.toList()..sort();
    for (final name in names) {
      final package = workspace.packages[name]!;
      final index = indexes[name]!;
      final state = _CCPortablePackageGenerationState(
        packageName: package.name,
        packageVersion: package.version,
        toolFingerprint: context.toolFingerprint,
        authoredInputFingerprint: context.authoredFingerprints[name]!,
        resolutionFingerprint: context.resolutionFingerprints[name]!,
        metadataFingerprint: computeCCCanonicalJsonFingerprint(index.metadata),
        managedOutputFingerprint: await _managedOutputFingerprint(package),
      );
      await _writeIfChanged(_file(package), state.toJson());
    }
  }

  /// Reads, authenticates, and compares one Package state.
  static Future<_CCPortableGenerationStateVerification> _verifyPackage(
    CCResolvedPackage package,
    _CCPortableGenerationContext context,
  ) async {
    final file = _file(package);
    if (!file.existsSync()) {
      return const _CCPortableGenerationStateVerification.invalid(
        _CCPortableGenerationStateReason.missing,
      );
    }
    late final _CCPortablePackageGenerationState state;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) throw const FormatException('Expected an object.');
      state = _CCPortablePackageGenerationState.fromJson(
        decoded.cast<String, Object?>(),
      );
    } on Object {
      return const _CCPortableGenerationStateVerification.invalid(
        _CCPortableGenerationStateReason.invalid,
      );
    }
    if (state.packageName != package.name ||
        state.packageVersion != package.version) {
      return const _CCPortableGenerationStateVerification.invalid(
        _CCPortableGenerationStateReason.packageIdentityMismatch,
      );
    }
    if (state.toolFingerprint != context.toolFingerprint) {
      return const _CCPortableGenerationStateVerification.invalid(
        _CCPortableGenerationStateReason.toolMismatch,
      );
    }
    if (state.authoredInputFingerprint !=
        context.authoredFingerprints[package.name]) {
      return const _CCPortableGenerationStateVerification.invalid(
        _CCPortableGenerationStateReason.authoredInputMismatch,
      );
    }
    if (state.resolutionFingerprint !=
        context.resolutionFingerprints[package.name]) {
      return const _CCPortableGenerationStateVerification.invalid(
        _CCPortableGenerationStateReason.resolutionMismatch,
      );
    }
    late final CCPackageIndex index;
    try {
      index = await CCPackageIndex.read(package);
    } on Object {
      return const _CCPortableGenerationStateVerification.invalid(
        _CCPortableGenerationStateReason.packageIndexMismatch,
      );
    }
    if (state.metadataFingerprint !=
        computeCCCanonicalJsonFingerprint(index.metadata)) {
      return const _CCPortableGenerationStateVerification.invalid(
        _CCPortableGenerationStateReason.metadataMismatch,
      );
    }
    final managedOutputFingerprint = await _managedOutputFingerprint(package);
    if (state.managedOutputFingerprint != managedOutputFingerprint) {
      return const _CCPortableGenerationStateVerification.invalid(
        _CCPortableGenerationStateReason.managedOutputMismatch,
      );
    }
    return _CCPortableGenerationStateVerification.valid(state);
  }

  /// Computes output identity without the self-describing state file.
  static Future<String> _managedOutputFingerprint(
    CCResolvedPackage package,
  ) async {
    final outputs = await _GenerationStateFingerprint.capturePackageOutput(
      package,
    );
    outputs.removeWhere((relative, _) => path.basename(relative) == fileName);
    return _GenerationStateFingerprint.digestEntries(outputs);
  }

  /// Resolves the generated state location for [package].
  static File _file(CCResolvedPackage package) =>
      File(path.join(package.catalogDirectory.path, fileName));
}

/// Reusable portable identities computed once for one verification pass.
final class _CCPortableGenerationContext {
  /// Creates one immutable content-identity view.
  const _CCPortableGenerationContext({
    required this.toolFingerprint,
    required this.authoredFingerprints,
    required this.resolutionFingerprints,
  });

  /// Exact generator implementation, SDK version, and tool resolution digest.
  final String toolFingerprint;

  /// Authored source and Package configuration digest by Package name.
  final Map<String, String> authoredFingerprints;

  /// Transitive portable resolution digest by Package name.
  final Map<String, String> resolutionFingerprints;

  /// Captures all current Package sources instead of trusting source type.
  static Future<_CCPortableGenerationContext> capture(
    CCPackageWorkspace workspace,
  ) async {
    final resolution = await _GenerationResolutionPlanningContext.load(
      workspace,
    );
    final authored = <String, String>{};
    for (final package in workspace.packages.values) {
      final source = '${resolution.lock[package.name]?['source'] ?? ''}';
      if (!package.writable &&
          !package.requiresPackageIndex &&
          source != 'path') {
        continue;
      }
      authored[package.name] =
          await _GenerationStateFingerprint.capturePackageAuthoredInput(
            package,
          );
    }
    await resolution.addPathAuthoredFingerprints(authored);
    final toolIdentity = resolution.toolIdentity(
      authoredFingerprints: authored,
      indexFingerprints: const <String, String?>{},
    );
    if (!toolIdentity.portable) {
      throw const FormatException(
        'Generator tool resolution cannot form a portable identity.',
      );
    }
    final resolutionFingerprints = <String, String>{};
    for (final package in workspace.packages.values) {
      final identity = resolution.packageIdentity(
        package,
        authoredFingerprints: authored,
        indexFingerprints: const <String, String?>{},
      );
      if (!identity.portable) {
        throw FormatException(
          'Package ${package.name} cannot form a portable identity.',
        );
      }
      resolutionFingerprints[package.name] = computeCCCanonicalJsonFingerprint(
        identity.identity,
      );
    }
    return _CCPortableGenerationContext(
      toolFingerprint:
          await _GenerationStateFingerprint.capturePortableToolInput(
            toolIdentity.identity,
          ),
      authoredFingerprints: Map.unmodifiable(authored),
      resolutionFingerprints: Map.unmodifiable(resolutionFingerprints),
    );
  }
}

/// Parsed deterministic state for one generated Package.
final class _CCPortablePackageGenerationState {
  /// Creates one fully content-addressed state document.
  const _CCPortablePackageGenerationState({
    required this.packageName,
    required this.packageVersion,
    required this.toolFingerprint,
    required this.authoredInputFingerprint,
    required this.resolutionFingerprint,
    required this.metadataFingerprint,
    required this.managedOutputFingerprint,
  });

  /// Resolved Pub Package name.
  final String packageName;

  /// Resolved Pub Package version.
  final String packageVersion;

  /// Portable generator and SDK identity.
  final String toolFingerprint;

  /// Exact authored Dart and Package configuration identity.
  final String authoredInputFingerprint;

  /// Exact normalized transitive resolution identity.
  final String resolutionFingerprint;

  /// Canonical Package Index metadata identity.
  final String metadataFingerprint;

  /// Exact managed output identity excluding this state file.
  final String managedOutputFingerprint;

  /// Decodes and authenticates one state document.
  factory _CCPortablePackageGenerationState.fromJson(
    Map<String, Object?> json,
  ) {
    if (json['schemaVersion'] != _CCPortableGenerationState.schemaVersion ||
        json['generatorVersion'] != ccrouterPackageIndexGeneratorVersion ||
        json['package'] is! Map ||
        json['toolFingerprint'] is! String ||
        json['authoredInputFingerprint'] is! String ||
        json['resolutionFingerprint'] is! String ||
        json['metadataFingerprint'] is! String ||
        json['managedOutputFingerprint'] is! String ||
        json['contentFingerprint'] is! String) {
      throw const FormatException('Unsupported portable generation state.');
    }
    final package = (json['package']! as Map).cast<String, Object?>();
    if (package['name'] is! String || package['version'] is! String) {
      throw const FormatException('Invalid portable Package identity.');
    }
    final payload = <String, Object?>{
      'schemaVersion': json['schemaVersion'],
      'generatorVersion': json['generatorVersion'],
      'package': package,
      'toolFingerprint': json['toolFingerprint'],
      'authoredInputFingerprint': json['authoredInputFingerprint'],
      'resolutionFingerprint': json['resolutionFingerprint'],
      'metadataFingerprint': json['metadataFingerprint'],
      'managedOutputFingerprint': json['managedOutputFingerprint'],
    };
    if (computeCCCanonicalJsonFingerprint(payload) !=
        json['contentFingerprint']) {
      throw const FormatException('Portable state fingerprint mismatch.');
    }
    return _CCPortablePackageGenerationState(
      packageName: package['name']! as String,
      packageVersion: package['version']! as String,
      toolFingerprint: json['toolFingerprint']! as String,
      authoredInputFingerprint: json['authoredInputFingerprint']! as String,
      resolutionFingerprint: json['resolutionFingerprint']! as String,
      metadataFingerprint: json['metadataFingerprint']! as String,
      managedOutputFingerprint: json['managedOutputFingerprint']! as String,
    );
  }

  /// Encodes stable JSON with an outer integrity fingerprint.
  String toJson() {
    final payload = <String, Object?>{
      'schemaVersion': _CCPortableGenerationState.schemaVersion,
      'generatorVersion': ccrouterPackageIndexGeneratorVersion,
      'package': <String, Object?>{
        'name': packageName,
        'version': packageVersion,
      },
      'toolFingerprint': toolFingerprint,
      'authoredInputFingerprint': authoredInputFingerprint,
      'resolutionFingerprint': resolutionFingerprint,
      'metadataFingerprint': metadataFingerprint,
      'managedOutputFingerprint': managedOutputFingerprint,
    };
    return '${const JsonEncoder.withIndent('  ').convert({...payload, 'contentFingerprint': computeCCCanonicalJsonFingerprint(payload)})}\n';
  }
}

/// Result of recomputing one Package's Portable Generation State.
final class _CCPortableGenerationStateVerification {
  /// Creates a successful verified result.
  const _CCPortableGenerationStateVerification.valid(this.state)
    : valid = true,
      reason = _CCPortableGenerationStateReason.valid;

  /// Creates a bounded failure without retaining raw source or paths.
  const _CCPortableGenerationStateVerification.invalid(this.reason)
    : valid = false,
      state = null;

  /// Whether every current identity exactly matches the published state.
  final bool valid;

  /// Stable mismatch category suitable for diagnostics.
  final _CCPortableGenerationStateReason reason;

  /// Authenticated state, available only when [valid] is true.
  final _CCPortablePackageGenerationState? state;
}

/// Sanitized Portable Generation State verification outcomes.
enum _CCPortableGenerationStateReason {
  /// Every identity matched.
  valid,

  /// The generated state file is absent.
  missing,

  /// The schema, field types, or integrity fingerprint is invalid.
  invalid,

  /// Resolved Package name or version changed.
  packageIdentityMismatch,

  /// Generator implementation, SDK version, or tool resolution changed.
  toolMismatch,

  /// Authored Dart or Package configuration changed.
  authoredInputMismatch,

  /// Transitive Package resolution changed.
  resolutionMismatch,

  /// The Package Index is absent, stale, or corrupted.
  packageIndexMismatch,

  /// Canonical Builder metadata differs from the published index.
  metadataMismatch,

  /// At least one managed generated output differs.
  managedOutputMismatch,
}
