import 'package:analyzer/dart/ast/token.dart';

/// Returns whether [value] can be emitted as a public generated Client member.
///
/// Generated aliases deliberately accept only ASCII lower-camel identifiers.
/// Dart keywords are rejected so authored metadata cannot produce source that
/// fails later during analysis.
bool isGeneratedClientMemberName(String value) =>
    RegExp(r'^[a-z][A-Za-z0-9]*$').hasMatch(value) &&
    !Keyword.keywords.containsKey(value);

/// Derives the stable default member name for a Service contract type.
///
/// Only a trailing `Service` suffix is removed. The first remaining character
/// is lowercased without acronym heuristics, keeping generation deterministic
/// across tool versions. Authors should use a Contract alias for domain names
/// such as `network` instead of relying on acronym tokenization.
String defaultServiceClientMember(String contractType) {
  final stem = contractType.endsWith('Service')
      ? contractType.substring(0, contractType.length - 'Service'.length)
      : contractType;
  return _lowerCamelOr(stem, fallback: 'service');
}

/// Derives the stable default member name for a Command contract type.
///
/// Only a trailing `Command` suffix is removed. Contract and dependency aliases
/// override this fallback when a domain-specific generated API is preferable.
String defaultCommandClientMember(String contractType) {
  final stem = contractType.endsWith('Command')
      ? contractType.substring(0, contractType.length - 'Command'.length)
      : contractType;
  return _lowerCamelOr(stem, fallback: 'command');
}

/// Lowercases one leading character while preserving the remaining authored
/// type spelling, or returns [fallback] when suffix removal leaves no stem.
String _lowerCamelOr(String value, {required String fallback}) =>
    value.isEmpty ? fallback : '${value[0].toLowerCase()}${value.substring(1)}';
