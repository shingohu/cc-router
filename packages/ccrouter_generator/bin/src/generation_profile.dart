part of '../ccrouter_generator.dart';

/// One stable, bounded timing trace for a generator invocation.
///
/// The trace is diagnostic only. It never participates in build planning,
/// cache validation, or generated output decisions.
final class _GenerationProfileTrace {
  /// Starts a trace on the command's existing monotonic clock.
  _GenerationProfileTrace(this._clock);

  static const int _schemaVersion = 1;

  final Stopwatch _clock;
  final List<_GenerationProfileSpan> _spans = [];

  /// Records work completed before the trace object could be constructed.
  void recordElapsed(
    String name, {
    required int startUs,
    required int durationUs,
    String status = 'ok',
    Map<String, int> counts = const {},
  }) {
    _spans.add(
      _GenerationProfileSpan(
        name: name,
        startUs: startUs,
        durationUs: durationUs,
        status: status,
        counts: counts,
      ),
    );
  }

  /// Opens a manually completed phase for a larger inline operation.
  _GenerationProfileOpenSpan start(String name) =>
      _GenerationProfileOpenSpan(this, name, _clock.elapsedMicroseconds);

  /// Records a phase that was intentionally not executed.
  void skip(String name, {Map<String, int> counts = const {}}) {
    _spans.add(
      _GenerationProfileSpan(
        name: name,
        startUs: _clock.elapsedMicroseconds,
        durationUs: 0,
        status: 'skipped',
        counts: counts,
      ),
    );
  }

  /// Emits stable JSON and atomically persists the latest local trace.
  Future<Map<String, Object>> write({
    required Directory buildRoot,
    required Directory hostRoot,
    required String command,
    required String outcome,
  }) async {
    final orderedSpans = _spans.indexed.toList()
      ..sort((left, right) {
        final byStart = left.$2.startUs.compareTo(right.$2.startUs);
        return byStart != 0 ? byStart : left.$1.compareTo(right.$1);
      });
    final report = <String, Object>{
      'schemaVersion': _schemaVersion,
      'command': command,
      'outcome': outcome,
      'totalUs': _clock.elapsedMicroseconds,
      'spans': [for (final entry in orderedSpans) entry.$2.toJson()],
    };
    final encoded = jsonEncode(report);
    _commandStdout.writeln('CCRouter profile trace=$encoded');
    try {
      final relativeHost = path.normalize(
        path.relative(hostRoot.path, from: buildRoot.path),
      );
      final hostIdentity = sha256
          .convert(utf8.encode(relativeHost))
          .toString()
          .substring(0, 16);
      final reportFile = File(
        path.join(
          buildRoot.path,
          '.dart_tool',
          'ccrouter',
          'v1',
          'profiles',
          hostIdentity,
          'latest.json',
        ),
      );
      await _writeIfChanged(reportFile, '$encoded\n');
      _commandStdout.writeln(
        'CCRouter profile report='
        '.dart_tool/ccrouter/v1/profiles/$hostIdentity/latest.json',
      );
    } on Object {
      _commandStdout.writeln('CCRouter profile report=write-failed');
    }
    return report;
  }

  void _complete(
    String name,
    int startUs, {
    required String status,
    Map<String, int> counts = const {},
  }) {
    _spans.add(
      _GenerationProfileSpan(
        name: name,
        startUs: startUs,
        durationUs: _clock.elapsedMicroseconds - startUs,
        status: status,
        counts: counts,
      ),
    );
  }
}

/// Nullable helpers keep non-profile generation free of recorder allocation.
extension _NullableGenerationProfileTrace on _GenerationProfileTrace? {
  Future<T> measure<T>(
    String name,
    Future<T> Function() action, {
    bool Function(T value)? succeeded,
    Map<String, int> Function(T value)? counts,
  }) async {
    final trace = this;
    if (trace == null) return action();
    final span = trace.start(name);
    try {
      final value = await action();
      span.finish(
        status: succeeded == null || succeeded(value) ? 'ok' : 'failed',
        counts: counts?.call(value) ?? const {},
      );
      return value;
    } on Object {
      span.finish(status: 'failed');
      rethrow;
    }
  }

  T measureSync<T>(
    String name,
    T Function() action, {
    bool Function(T value)? succeeded,
    Map<String, int> Function(T value)? counts,
  }) {
    final trace = this;
    if (trace == null) return action();
    final span = trace.start(name);
    try {
      final value = action();
      span.finish(
        status: succeeded == null || succeeded(value) ? 'ok' : 'failed',
        counts: counts?.call(value) ?? const {},
      );
      return value;
    } on Object {
      span.finish(status: 'failed');
      rethrow;
    }
  }
}

/// A phase whose completion status is decided by its caller.
final class _GenerationProfileOpenSpan {
  _GenerationProfileOpenSpan(this._trace, this._name, this._startUs);

  final _GenerationProfileTrace _trace;
  final String _name;
  final int _startUs;
  bool _finished = false;

  void finish({String status = 'ok', Map<String, int> counts = const {}}) {
    if (_finished) return;
    _finished = true;
    _trace._complete(_name, _startUs, status: status, counts: counts);
  }
}

/// JSON representation of one phase without paths or source values.
final class _GenerationProfileSpan {
  const _GenerationProfileSpan({
    required this.name,
    required this.startUs,
    required this.durationUs,
    required this.status,
    required this.counts,
  });

  final String name;
  final int startUs;
  final int durationUs;
  final String status;
  final Map<String, int> counts;

  Map<String, Object> toJson() => {
    'name': name,
    'startUs': startUs,
    'durationUs': durationUs,
    'status': status,
    if (counts.isNotEmpty) 'counts': counts,
  };
}

/// Read-only attribution from existing exact content proofs and output diffs.
/// These observations neither classify Dart semantics nor authorize cache reuse.
abstract final class _GenerationProfile {
  /// Compares Package facts to the last successful local planning baseline.
  /// A dependency-resolution-only change is not proof of a specific causal edge.
  static Map<String, Object?> inputs(
    _GenerationPlanningState before,
    _GenerationPlanningState after,
  ) {
    try {
      final authored = <String>[];
      final authoredUnavailable = <String>[];
      final resolution = <String>[];
      final resolutionOnly = <String>[];
      final added = <String>[];
      final removed = <String>[];
      for (final entry in after.packages.entries) {
        final old = before.packages[entry.key];
        if (old == null) {
          added.add(entry.key);
          continue;
        }
        final comparable =
            old.authoredInputFingerprint != null &&
            entry.value.authoredInputFingerprint != null;
        if (!comparable) authoredUnavailable.add(entry.key);
        final ownChanged =
            comparable &&
            old.authoredInputFingerprint !=
                entry.value.authoredInputFingerprint;
        if (ownChanged) authored.add(entry.key);
        if (old.resolutionFingerprint != entry.value.resolutionFingerprint) {
          resolution.add(entry.key);
          if (comparable && !ownChanged) resolutionOnly.add(entry.key);
        }
      }
      removed.addAll(
        before.packages.keys.where((name) => !after.packages.containsKey(name)),
      );
      return {
        'status': 'compared',
        'toolChanged': before.toolFingerprint != after.toolFingerprint,
        'hostGraphChanged':
            before.hostGraphFingerprint != after.hostGraphFingerprint,
        'authored': _names(authored),
        'authoredUnavailable': _names(authoredUnavailable),
        'resolution': _names(resolution),
        'resolutionOnly': _names(resolutionOnly),
        'added': _names(added),
        'removed': _names(removed),
      };
    } on Object {
      return const {'status': 'unavailable'};
    }
  }

  /// Emits bounded names only, without paths, source contents or business values.
  static Map<String, Object> _names(List<String> values) {
    values.sort();
    return {
      'count': values.length,
      'packages': [
        for (final value in values.take(12))
          value.length <= 128 ? value : '${value.substring(0, 128)}…',
      ],
      'omitted': values.length > 12 ? values.length - 12 : 0,
    };
  }

  /// Reports exact added/removed/modified artifact counts before check restores.
  /// Code, JSON metadata, Markdown and portable proof state stay distinct: a
  /// changed proof is not a changed business API, and equal Dart is not equal metadata.
  static Map<String, Object> writeOutputs(List<String> changes) {
    final groups = <String, Map<String, int>>{
      for (final kind in [
        'dart',
        'metadata',
        'documentation',
        'state',
        'other',
      ])
        kind: {'added': 0, 'removed': 0, 'modified': 0},
    };
    for (final change in changes) {
      final separator = change.indexOf(': ');
      final operation = change.substring(0, separator);
      final relative = change.substring(separator + 2);
      final kind =
          path.basename(relative) == _CCPortableGenerationState.fileName
          ? 'state'
          : relative.endsWith('.dart')
          ? 'dart'
          : relative.endsWith('.json')
          ? 'metadata'
          : relative.endsWith('.md')
          ? 'documentation'
          : 'other';
      groups[kind]![operation] = groups[kind]![operation]! + 1;
    }
    final report = <String, Object>{
      'files': changes.length,
      'artifacts': groups,
    };
    _commandStdout.writeln(
      'CCRouter profile output-delta=${jsonEncode(report)}',
    );
    return report;
  }
}
