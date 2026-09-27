part of 'facade.dart';

/// Generated-code-only bridge for typed Command invocation.
///
/// Generated component clients call this bridge with identities validated at
/// build time. Application code imports `ccrouter.dart` and calls the generated
/// client instead of importing `ccrouter_generated.dart` directly.
abstract final class CCRouterGeneratedCommandBinding {
  /// Dispatches [command] to its generated single-owner handler.
  static Future<R> invoke<C extends CCCommand<R>, R>(
    C command, {
    required String commandId,
    required String callerComponentId,
    Duration? timeout,
    CCCancellationToken? cancellation,
  }) => CCRouter._runtime.invokeGeneratedCommand<R>(
    command,
    commandId: commandId,
    callerComponentId: callerComponentId,
    timeout: timeout,
    cancellation: cancellation,
  );
}
