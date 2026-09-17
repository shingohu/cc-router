import 'dart:async';

/// Contract implemented by instances that release lifecycle-owned resources.
///
/// Implement this for services that own subscriptions, ports, controllers, or
/// other resources that must be released when their Runtime Scope closes.
abstract interface class CCDisposable {
  /// Releases resources when the owning Scope closes.
  FutureOr<void> dispose();
}
