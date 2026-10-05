part of '../ccrouter_generator.dart';

const _aggregationReuseKillSwitch = 'CCROUTER_DISABLE_AGGREGATION_REUSE';

/// Local proof that post-Builder aggregation inputs and outputs are unchanged.
///
/// This state can skip only aggregation rendering and writes. Builder,
/// dependency verification, Workspace validation, and input barriers remain
/// outside its authority. Missing or invalid state always falls back.
abstract final class _GenerationAggregationReuseState {
  static const int _schemaVersion = 1;

  /// Verifies the previous aggregation identity and every owned output byte.
  static Future<_GenerationAggregationReuseInspection> inspect({
    required CCPackageWorkspace workspace,
    required String aggregationInputFingerprint,
    required String? toolFingerprint,
    required String? currentOutputFingerprint,
    required String? disabledReason,
  }) async {
    if (disabledReason != null) {
      return _GenerationAggregationReuseInspection.miss(disabledReason);
    }
    if (toolFingerprint == null) {
      return const _GenerationAggregationReuseInspection.miss(
        'tool-fingerprint-unavailable',
      );
    }
    if (currentOutputFingerprint == null) {
      return const _GenerationAggregationReuseInspection.miss(
        'output-fingerprint-unavailable',
      );
    }
    final file = _stateFile(workspace);
    if (!file.existsSync()) {
      return const _GenerationAggregationReuseInspection.miss('state-missing');
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) throw const FormatException('Expected an object.');
      final document = decoded.cast<String, Object?>();
      final payload = <String, Object?>{
        'schemaVersion': document['schemaVersion'],
        'generatorVersion': document['generatorVersion'],
        'hostPackage': document['hostPackage'],
        'toolFingerprint': document['toolFingerprint'],
        'aggregationInputFingerprint': document['aggregationInputFingerprint'],
        'aggregationOutputFingerprint':
            document['aggregationOutputFingerprint'],
      };
      if (payload['schemaVersion'] != _schemaVersion ||
          payload['generatorVersion'] != ccrouterPackageIndexGeneratorVersion ||
          payload['hostPackage'] != workspace.host.name ||
          payload['toolFingerprint'] is! String ||
          payload['aggregationInputFingerprint'] is! String ||
          payload['aggregationOutputFingerprint'] is! String ||
          document['contentFingerprint'] is! String ||
          computeCCCanonicalJsonFingerprint(payload) !=
              document['contentFingerprint']) {
        throw const FormatException('Invalid aggregation reuse state.');
      }
      if (payload['toolFingerprint'] != toolFingerprint) {
        return const _GenerationAggregationReuseInspection.miss('tool-changed');
      }
      if (payload['aggregationInputFingerprint'] !=
          aggregationInputFingerprint) {
        return const _GenerationAggregationReuseInspection.miss(
          'input-changed',
        );
      }
      if (payload['aggregationOutputFingerprint'] != currentOutputFingerprint) {
        return const _GenerationAggregationReuseInspection.miss(
          'output-changed',
        );
      }
      return const _GenerationAggregationReuseInspection.hit();
    } on Object {
      return const _GenerationAggregationReuseInspection.miss('state-invalid');
    }
  }

  /// Atomically publishes a proof after successful full aggregation.
  static Future<void> write({
    required CCPackageWorkspace workspace,
    required String aggregationInputFingerprint,
    required String toolFingerprint,
    required String aggregationOutputFingerprint,
  }) async {
    final payload = <String, Object?>{
      'schemaVersion': _schemaVersion,
      'generatorVersion': ccrouterPackageIndexGeneratorVersion,
      'hostPackage': workspace.host.name,
      'toolFingerprint': toolFingerprint,
      'aggregationInputFingerprint': aggregationInputFingerprint,
      'aggregationOutputFingerprint': aggregationOutputFingerprint,
    };
    final contents =
        '${const JsonEncoder.withIndent('  ').convert({...payload, 'contentFingerprint': computeCCCanonicalJsonFingerprint(payload)})}\n';
    await _writeIfChanged(_stateFile(workspace), contents);
  }

  /// Digests only aggregation-owned files from an existing managed snapshot.
  static String captureOutputFingerprint(Map<String, List<int>> managedFiles) {
    final outputs = <String, List<int>>{};
    for (final entry in managedFiles.entries) {
      if (!_isAggregationOutput(entry.key)) continue;
      outputs[entry.key] = entry.value;
    }
    return _GenerationStateFingerprint.digestEntries(outputs);
  }

  /// Separates Builder source outputs from post-Builder aggregation outputs.
  static bool _isAggregationOutput(String relative) {
    final segments = relative.split('/');
    final generated = segments.indexOf('ccrouter_generated');
    if (generated < 0 || generated + 1 >= segments.length) return false;
    final tail = segments.sublist(generated + 1);
    final name = tail.last;
    if (name == _CCPortableGenerationState.fileName) return false;
    if (tail.length < 2) return true;
    return switch (tail.first) {
      'binding' => !name.endsWith('.route_binding.g.dart'),
      'command' => !name.endsWith('.command.g.dart'),
      'event' => !name.endsWith('.event.g.dart'),
      'init_task' => !name.endsWith('.init_task.g.dart'),
      'route' => !name.endsWith('.route.g.dart'),
      'service' => !name.endsWith('.service.g.dart'),
      'contract' =>
        !name.endsWith('.route.contract.g.dart') &&
            !name.endsWith('.service.contract.g.dart'),
      'component' => !name.endsWith('.service_api.g.dart'),
      _ => true,
    };
  }

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
        'aggregation_reuse',
        '$identity.json',
      ),
    );
  }
}

/// Result of one fail-closed aggregation reuse inspection.
final class _GenerationAggregationReuseInspection {
  const _GenerationAggregationReuseInspection.hit()
    : matches = true,
      reason = 'verified';

  const _GenerationAggregationReuseInspection.miss(this.reason)
    : matches = false;

  final bool matches;
  final String reason;
}

/// Successful aggregation facts published only after the outer transaction.
final class _GenerationAggregationOutcome {
  const _GenerationAggregationOutcome({
    required this.inputFingerprint,
    required this.reused,
    required this.publishState,
  });

  /// Exact post-Builder semantic input used by aggregation.
  final String inputFingerprint;

  /// Whether rendering and aggregation-owned writes were skipped.
  final bool reused;

  /// Whether a cycle-end output proof should replace the local reuse state.
  final bool publishState;
}
