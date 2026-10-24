part of 'runtime.dart';

/// Runtime-qualified trace context and admission signals for one active Zone.
/// Identity has no Runtime back-reference; ended owners leave only their tokens.
typedef _InvocationFrame = ({
  Object runtimeIdentity,
  CCInvocationContext context,
  _InvocationOwnership ownership,
});

/// Immutable admission signals inherited by work started in an invocation Zone.
///
/// Completed invocations release cancellation listeners, but their detached
/// continuations must still reject fresh calls after an original Scope ends.
/// This record keeps only tokens, never a Scope, Service, or parent context.
final class _InvocationOwnership {
  /// Snapshots and deduplicates concrete lifetime and invocation signals.
  _InvocationOwnership(Iterable<CCCancellationToken> tokens)
    : _tokens = Set<CCCancellationToken>.unmodifiable(tokens);

  /// Signals from this invocation and every inherited concrete owner.
  final Set<CCCancellationToken> _tokens;

  /// Whether any original owner or already-cancelled invocation has ended.
  bool get isCancelled => _tokens.any((token) => token.isCancelled);
}

/// Carries admission ownership separately from public tracing context.
extension _CCRouterRuntimeInvocationOwnership on CCRouterRuntime {
  /// Returns this Runtime's frame without adopting a different Runtime's Zone.
  _InvocationFrame? get _currentInvocationFrame {
    final current = Zone.current[CCRouterRuntime._invocationZoneKey];
    return current is _InvocationFrame &&
            identical(current.runtimeIdentity, _zoneIdentity)
        ? current
        : null;
  }

  /// Parent trace context when entering a child invocation in this Runtime.
  CCInvocationContext? get _parentContext => _currentInvocationFrame?.context;

  /// Original lifetime signals, including those of successfully returned parents.
  _InvocationOwnership? get _currentInvocationOwnership =>
      _currentInvocationFrame?.ownership;

  /// Builds a Zone frame whose signals survive listener cleanup.
  ///
  /// Scope-owned factories and singleton initializers deliberately reset
  /// inherited ownership: one waiter's cancellation must not end shared work.
  /// New-instance initialization and ordinary calls preserve the caller chain.
  Map<Object, Object> _invocationZoneValues(
    CCInvocationContext context, {
    CCScope? ownerScope,
    bool inheritOwnership = true,
  }) => {
    CCRouterRuntime._invocationZoneKey: (
      runtimeIdentity: _zoneIdentity,
      context: context,
      ownership: _InvocationOwnership({
        appScope.cancellation,
        context.cancellation,
        if (ownerScope != null) ownerScope.cancellation,
        if (inheritOwnership) ...?_currentInvocationOwnership?._tokens,
      }),
    ),
  };
}
