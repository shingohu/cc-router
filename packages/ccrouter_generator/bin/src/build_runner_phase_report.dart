/// Collects build_runner's supported verbose phase lines for one build cycle.
///
/// The collector is diagnostic-only. Unknown upstream formats are retained as
/// bounded raw diagnostics and never affect whether generation succeeds.
final class CCBuildRunnerPhaseCollector {
  /// Creates an empty collector for the initial or next watch build.
  CCBuildRunnerPhaseCollector();

  /// Maximum upstream format mismatches retained in one cycle.
  static const _maximumDiagnostics = 12;

  /// Maximum raw characters retained for one format mismatch.
  static const _maximumDiagnosticLength = 500;

  /// Latest completed report for each phase in upstream display order.
  final Map<String, CCBuildRunnerPhaseReport> _phases = {};

  /// Bounded terminal lines rejected by the strict parser.
  final List<String> _unparsedFinalLines = [];

  /// Discards all phase evidence before the next build cycle starts.
  void reset() {
    _phases.clear();
    _unparsedFinalLines.clear();
  }

  /// Observes one ANSI-free build_runner log line.
  ///
  /// Start and intermediate progress lines are ignored. A completed required
  /// phase is accepted only when all primary inputs are accounted for.
  void addLine(String line) {
    final parse = _parsePhaseLine(line);
    switch (parse) {
      case _IgnoredPhaseLine():
        return;
      case _MalformedFinalPhaseLine(:final line):
        if (_unparsedFinalLines.length >= _maximumDiagnostics) return;
        _unparsedFinalLines.add(
          line.length <= _maximumDiagnosticLength
              ? line
              : line.substring(0, _maximumDiagnosticLength),
        );
      case _ParsedPhaseLine(:final phase):
        _phases[phase.name] = phase;
    }
  }

  /// Completes a diagnostic report from build_runner's terminal status line.
  CCBuildRunnerCycleReport finish(
    String statusLine, {
    bool phaseDetailsAvailable = true,
  }) {
    final status = RegExp(
      r'build_runner/(?:aot|jit) in (\d+\.\d{2}s)(?: with warnings)?; '
      r'wrote (\d+) outputs?\.',
    ).firstMatch(statusLine);
    return CCBuildRunnerCycleReport(
      durationMs: status == null ? null : _durationMs(status.group(1)!),
      writtenOutputs: status == null ? null : int.parse(status.group(2)!),
      phaseDetailsAvailable: phaseDetailsAvailable,
      phases: _phases.values.toList(growable: false),
      unparsedFinalLines: List.unmodifiable(_unparsedFinalLines),
    );
  }
}

/// Structured diagnostic for one completed build_runner Builder phase.
final class CCBuildRunnerPhaseReport {
  /// Creates a phase report from build_runner's public console counters.
  CCBuildRunnerPhaseReport({
    required this.name,
    required this.durationMs,
    required this.inputs,
    required this.skipped,
    required this.notTriggered,
    required this.outputs,
    required this.sameOutputs,
    required this.noOp,
    required Map<String, int> activitiesMs,
  }) : activitiesMs = Map.unmodifiable(activitiesMs);

  /// Builder phase name, including `(lazy)` when build_runner reports it.
  final String name;

  /// Upstream phase duration rounded to build_runner's 10ms precision.
  final int durationMs;

  /// Required primary input count, or `null` for a lazy phase.
  final int? inputs;

  /// Inputs whose previous outputs remained current.
  final int skipped;

  /// Invalidated inputs whose trigger condition did not request execution.
  final int notTriggered;

  /// Executions that produced new or byte-different outputs.
  final int outputs;

  /// Executions that reproduced the previous output bytes.
  final int sameOutputs;

  /// Executions that produced no output.
  final int noOp;

  /// Upstream activity durations, such as analyzing and resolving.
  final Map<String, int> activitiesMs;

  /// Build steps that actually invoked Builder code.
  int get executedInputs => outputs + sameOutputs + noOp;

  /// Primary inputs invalidated or reconsidered by the asset graph.
  ///
  /// This is inferred from the supported phase counters. It is a count, not a
  /// list of AssetIds and not proof of semantic impact on generated output.
  int get invalidatedInputs =>
      inputs == null ? notTriggered + executedInputs : inputs! - skipped;

  /// Encodes this diagnostic without source paths or source values.
  Map<String, Object?> toJson() => {
    'name': name,
    'durationMs': durationMs,
    if (inputs case final inputs?) 'inputs': inputs,
    'skipped': skipped,
    'notTriggered': notTriggered,
    'invalidatedInputs': invalidatedInputs,
    'executedInputs': executedInputs,
    'outputs': outputs,
    'sameOutputs': sameOutputs,
    'noOp': noOp,
    if (activitiesMs.isNotEmpty) 'activitiesMs': activitiesMs,
  };
}

/// Immutable structured summary for one build_runner build.
final class CCBuildRunnerCycleReport {
  /// Creates a cycle report from completed phases and the terminal status.
  CCBuildRunnerCycleReport({
    required this.durationMs,
    required this.writtenOutputs,
    required this.phaseDetailsAvailable,
    required List<CCBuildRunnerPhaseReport> phases,
    required List<String> unparsedFinalLines,
  }) : phases = List.unmodifiable(phases),
       unparsedFinalLines = List.unmodifiable(unparsedFinalLines);

  /// Total duration reported by build_runner, or `null` for an unknown format.
  final int? durationMs;

  /// Overall written-output count, or `null` for an unknown status format.
  final int? writtenOutputs;

  /// Whether verbose Builder phase counters were enabled for this cycle.
  final bool phaseDetailsAvailable;

  /// Completed phase diagnostics in upstream display order.
  final List<CCBuildRunnerPhaseReport> phases;

  /// Bounded terminal-looking lines that could not be parsed safely.
  final List<String> unparsedFinalLines;

  /// Encodes the diagnostic report for a machine watch event.
  Map<String, Object?> toJson() {
    final knownInputPhases = phases.where((phase) => phase.inputs != null);
    int sum(int Function(CCBuildRunnerPhaseReport phase) read) =>
        phases.fold(0, (total, phase) => total + read(phase));
    return {
      'formatVersion': 2,
      'available': phaseDetailsAvailable,
      if (!phaseDetailsAvailable) 'reason': 'profile-disabled',
      if (durationMs case final durationMs?) 'durationMs': durationMs,
      if (writtenOutputs case final writtenOutputs?)
        'writtenOutputs': writtenOutputs,
      if (phaseDetailsAvailable)
        'totals': {
          'phases': phases.length,
          'inputs': knownInputPhases.fold<int>(
            0,
            (total, phase) => total + phase.inputs!,
          ),
          'skipped': sum((phase) => phase.skipped),
          'notTriggered': sum((phase) => phase.notTriggered),
          'invalidatedInputs': sum((phase) => phase.invalidatedInputs),
          'executedInputs': sum((phase) => phase.executedInputs),
          'outputs': sum((phase) => phase.outputs),
          'sameOutputs': sum((phase) => phase.sameOutputs),
          'noOp': sum((phase) => phase.noOp),
        },
      if (phaseDetailsAvailable)
        'phases': [for (final phase in phases) phase.toJson()],
      if (phaseDetailsAvailable && unparsedFinalLines.isNotEmpty)
        'unparsedFinalLines': unparsedFinalLines,
    };
  }
}

/// Internal result of classifying one upstream console line.
sealed class _PhaseLineParse {
  /// Creates a closed parse result used by the collector switch.
  const _PhaseLineParse();
}

/// Marks a start, progress, status, or unrelated line that needs no report.
final class _IgnoredPhaseLine extends _PhaseLineParse {
  /// Creates the stateless ignored-line result.
  const _IgnoredPhaseLine();
}

/// Preserves a terminal-looking line whose format is not understood.
final class _MalformedFinalPhaseLine extends _PhaseLineParse {
  /// Creates a mismatch result retaining the bounded diagnostic source.
  const _MalformedFinalPhaseLine(this.line);

  /// Original ANSI-free upstream line.
  final String line;
}

/// Carries a validated completed phase report.
final class _ParsedPhaseLine extends _PhaseLineParse {
  /// Creates a successful parse result.
  const _ParsedPhaseLine(this.phase);

  /// Completed phase extracted from the upstream line.
  final CCBuildRunnerPhaseReport phase;
}

/// Classifies one phase line without depending on build_runner private APIs.
_PhaseLineParse _parsePhaseLine(String line) {
  final normalized = line.replaceAll('\u00a0', ' ');
  final match = RegExp(
    r'^\s*(\d+\.\d{2}s)\s+(.+?)(?: on (\d+) inputs?)?'
    r'(?:: (.*?))?(?:; (.*))?$',
  ).firstMatch(normalized);
  if (match == null) return const _IgnoredPhaseLine();
  final countersSource = match.group(4);
  if (countersSource == null) return const _IgnoredPhaseLine();
  final suffix = match.group(5);
  if (suffix != null && !suffix.startsWith('spent ')) {
    return const _IgnoredPhaseLine();
  }

  final counters = <String, int>{};
  for (final rawCounter in countersSource.split(', ')) {
    final counter = RegExp(
      r'^(\d+) (skipped|not triggered|outputs?|same|no-op)$',
    ).firstMatch(rawCounter);
    if (counter == null) return _MalformedFinalPhaseLine(line);
    counters[counter.group(2)!] = int.parse(counter.group(1)!);
  }
  int count(String singular, [String? plural]) =>
      counters[singular] ?? (plural == null ? 0 : counters[plural]) ?? 0;

  final inputs = int.tryParse(match.group(3) ?? '');
  final skipped = count('skipped');
  final notTriggered = count('not triggered');
  final outputs = count('output', 'outputs');
  final sameOutputs = count('same');
  final noOp = count('no-op');
  final accounted = skipped + notTriggered + outputs + sameOutputs + noOp;
  if (inputs != null && accounted != inputs) {
    return _MalformedFinalPhaseLine(line);
  }

  final activities = <String, int>{};
  if (suffix != null) {
    final source = suffix.substring('spent '.length);
    for (final rawActivity in source.split(', ')) {
      final activity = RegExp(
        r'^(\d+\.\d{2}s)\s+(.+)$',
      ).firstMatch(rawActivity);
      if (activity == null) return _MalformedFinalPhaseLine(line);
      activities[activity.group(2)!] = _durationMs(activity.group(1)!);
    }
  }
  return _ParsedPhaseLine(
    CCBuildRunnerPhaseReport(
      name: match.group(2)!,
      durationMs: _durationMs(match.group(1)!),
      inputs: inputs,
      skipped: skipped,
      notTriggered: notTriggered,
      outputs: outputs,
      sameOutputs: sameOutputs,
      noOp: noOp,
      activitiesMs: activities,
    ),
  );
}

/// Converts build_runner's fixed two-decimal seconds to milliseconds.
int _durationMs(String value) {
  final match = RegExp(r'^(\d+)\.(\d{2})s$').firstMatch(value)!;
  return int.parse(match.group(1)!) * 1000 + int.parse(match.group(2)!) * 10;
}
