part of 'facade.dart';

/// Generated-code-only bridge for method-level Service invocation.
///
/// Generated cross-package Service proxies call this bridge after compile-time
/// contract validation. Application and component code should import
/// `package:ccrouter/ccrouter.dart` and use the generated typed proxy instead of
/// importing `ccrouter_generated.dart` or passing an arbitrary callback here.
abstract final class CCRouterGeneratedServiceBinding {
  /// Resolves a promoted Service and invokes one synchronous generated method.
  ///
  /// Generators use this form only when the contract method has a synchronous
  /// return type. It preserves that signature and records a method-level trace,
  /// but it does not start lazy asynchronous initialization. Calling it before
  /// a Provider is ready throws [CCServiceNotReadyError].
  static R invokeSync<T extends Object, R>({
    required CCServiceToken<T> contract,
    CCServiceKey<T>? key,
    required String methodId,
    String? callerComponentId,
    String? navigationId,
    required R Function(T service, CCInvocationContext context) call,
  }) => CCRouter._runtime.invokeServiceSync<T, R>(
    contract: contract,
    key: key,
    methodId: methodId,
    callerComponentId: callerComponentId,
    navigationId: navigationId,
    call: call,
  );

  /// Resolves a promoted Service and invokes one generated method body.
  ///
  /// [contract], [methodId], [callerComponentId], and [navigationId] are emitted
  /// from validated metadata. The Runtime enforces Scope ownership, propagates
  /// timeout and cancellation, and records only sanitized stable identifiers.
  static Future<R> invoke<T extends Object, R>({
    required CCServiceToken<T> contract,
    CCServiceKey<T>? key,
    required String methodId,
    String? callerComponentId,
    String? navigationId,
    Duration? timeout,
    CCCancellationToken? cancellation,
    required FutureOr<R> Function(T service, CCInvocationContext context) call,
  }) => CCRouter._runtime.invokeService<T, R>(
    contract: contract,
    key: key,
    methodId: methodId,
    callerComponentId: callerComponentId,
    navigationId: navigationId,
    timeout: timeout,
    cancellation: cancellation,
    call: call,
  );
}
