part of '../ccrouter_generator.dart';

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
  static void writeOutputs(List<String> changes) {
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
    stdout.writeln(
      'CCRouter profile output-delta=${jsonEncode({'files': changes.length, 'artifacts': groups})}',
    );
  }
}
