part of 'runtime.dart';

/// Immutable snapshot of the active authenticated Session.
///
/// Business code reads this through `CCRouter.session` for non-sensitive
/// Session diagnostics. Authentication state remains owned by the application,
/// and a Session should span page changes and App background transitions.
final class CCSession {
  /// Creates Runtime-owned Session state from validated host input.
  CCSession._({
    required this.sessionId,
    required this.accountId,
    required this.openedAt,
    Map<String, Object?> metadata = const {},
  }) : metadata = Map.unmodifiable(metadata);

  /// Runtime-generated identity unique to this Session instance.
  final String sessionId;

  /// Stable account identity supplied when the Session opened.
  final String accountId;

  /// Time at which the Runtime opened this Session.
  final DateTime openedAt;

  /// Immutable non-sensitive metadata captured when the Session opened.
  final Map<String, Object?> metadata;
}
