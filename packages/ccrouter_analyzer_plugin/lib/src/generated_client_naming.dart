import 'package:analyzer/dart/ast/token.dart';

/// Mirrors Generator member validation while keeping Analyzer dependencies isolated.
/// Static Clients cannot reuse inherited Object instance member names.
bool isGeneratedClientMemberName(String value) =>
    RegExp(r'^[a-z][A-Za-z0-9]*$').hasMatch(value) &&
    !Keyword.keywords.containsKey(value) &&
    !const {
      'hashCode',
      'runtimeType',
      'toString',
      'noSuchMethod',
    }.contains(value);

/// Mirrors the Generator's Owner Command fallback, without acronym heuristics.
String defaultCommandClientMember(String type) {
  final stem = type.endsWith('Command')
      ? type.substring(0, type.length - 'Command'.length)
      : type;
  return stem.isEmpty
      ? 'command'
      : '${stem[0].toLowerCase()}${stem.substring(1)}';
}

/// Preserves the Generator's established Event publication fallback.
String defaultEventClientMember(String type) {
  final stem = type.endsWith('Event')
      ? type.substring(0, type.length - 'Event'.length)
      : type;
  final name = stem.isEmpty
      ? 'event'
      : '${stem[0].toUpperCase()}${stem.substring(1)}';
  return 'publish$name';
}
