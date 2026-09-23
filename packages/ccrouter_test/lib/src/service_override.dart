// Test support intentionally consumes Core's visible-for-testing boundary.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:ccrouter_core/ccrouter_core.dart';

/// A test-only replacement for one already registered Service Provider.
///
/// Use [CCServiceOverride.value] for a fixed fake or
/// [CCServiceOverride.factory] when each resolution should create a fresh fake
/// according to the original Provider's Scope and creation policy. The target
/// is selected by [contract] when supplied, otherwise by the Dart type [T];
/// [key] selects a named implementation and no key selects the registered
/// default. Overrides are accepted only by [CCRouterTestHost] and never by
/// production initialization.
final class CCServiceOverride<T extends Object> {
  /// Internal constructor used by the public named replacement factories.
  const CCServiceOverride._({
    required this.create,
    this.initializer,
    this.contract,
    this.key,
  });

  /// Replaces a Provider with the same [instance] on every resolution.
  ///
  /// The owning Scope still disposes a disposable instance when the test host
  /// ends. Do not use one mutable instance for a Provider whose original
  /// creation policy is factory unless sharing that state is intentional. The
  /// production initializer is cleared; pass [initializer] only when this fake
  /// needs an explicit readiness phase.
  factory CCServiceOverride.value(
    T instance, {
    CCServiceInitializer<T>? initializer,
    CCServiceToken<T>? contract,
    CCServiceKey<T>? key,
  }) => CCServiceOverride._(
    create: (_) => instance,
    initializer: initializer,
    contract: contract,
    key: key,
  );

  /// Replaces a Provider with a test [create] factory.
  ///
  /// The factory receives the same invocation context shape as the production
  /// Provider. Scope, cancellation, and disposal remain controlled by Runtime.
  /// The production initializer is cleared; pass [initializer] to install a
  /// test-owned replacement.
  factory CCServiceOverride.factory({
    required CCServiceFactory<T> create,
    CCServiceInitializer<T>? initializer,
    CCServiceToken<T>? contract,
    CCServiceKey<T>? key,
  }) => CCServiceOverride._(
    create: create,
    initializer: initializer,
    contract: contract,
    key: key,
  );

  /// Replacement factory passed to the isolated Runtime.
  final CCServiceFactory<T> create;

  /// Optional readiness hook for the replacement instance.
  ///
  /// Null clears the production initializer. Supply this only when the fake
  /// itself needs readiness behavior exercised by `serviceAsync`.
  final CCServiceInitializer<T>? initializer;

  /// Stable cross-package Service identity to replace, when promoted.
  final CCServiceToken<T>? contract;

  /// Named implementation to replace, or null for the default implementation.
  final CCServiceKey<T>? key;

  /// Converts the test API to the Core-only replacement boundary.
  CCServiceOverrideEntry<T> toEntry() => CCServiceOverrideEntry<T>(
    factory: create,
    initializer: initializer == null
        ? null
        : (service, context) => initializer!(service as T, context),
    contract: contract,
    key: key,
  );
}
