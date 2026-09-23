part of 'runtime.dart';

/// Creates a service instance inside the active invocation and Scope context.
///
/// Component registrars use factories when service construction requires the
/// Runtime-provided deadline, cancellation, or trace context.
typedef CCServiceFactory<T> = T Function(CCInvocationContext context);

/// Lazily prepares a Scope-owned Service for asynchronous use.
///
/// The synchronous [CCServiceFactory] creates and transfers ownership first;
/// this initializer then performs optional I/O or asynchronous setup exactly
/// once per singleton instance. It must observe context cancellation because
/// its Session, Route, or Runtime Scope may close while setup is pending.
typedef CCServiceInitializer<T> =
    FutureOr<void> Function(T service, CCInvocationContext context);

/// Handles a typed message [M] and returns a synchronous or asynchronous [R].
///
/// Use handlers in component registration for Command and Event processing;
/// business callers dispatch messages through `CCRouter` instead.
typedef CCHandler<M, R> =
    FutureOr<R> Function(M message, CCInvocationContext context);

/// Type-erased handler stored by the internal dispatcher.
typedef _Handler =
    FutureOr<Object?> Function(Object message, CCInvocationContext context);

/// Stores a type-erased Command handler with its trusted component owner.
///
/// The Runtime creates this record only from component-bound registration. An
/// empty owner identifies low-level test registration and is omitted from Trace.
final class _RegisteredCommandHandler {
  /// Creates an internally owned Command registration.
  const _RegisteredCommandHandler({
    required this.ownerComponentId,
    required this.callback,
  });

  /// Component that registered the handler, or empty for low-level tests.
  final String ownerComponentId;

  /// Type-erased callback invoked by the Command dispatcher.
  final _Handler callback;
}

/// Stores one Event subscriber with its stable identity and component owner.
///
/// Subscriber identity determines deterministic start order and safe Trace
/// targets. Ownership comes from the component-bound registry, never business
/// input.
final class _RegisteredEventSubscriber {
  /// Creates an internally owned Event subscription.
  const _RegisteredEventSubscriber({
    required this.id,
    required this.ownerComponentId,
    required this.callback,
  });

  /// Globally stable subscriber identity.
  final String id;

  /// Component that registered the subscriber, or empty for low-level tests.
  final String ownerComponentId;

  /// Type-erased callback invoked for a matching Event.
  final _Handler callback;
}

/// Registration-only surface supplied to component registrars.
///
/// It intentionally exposes no resolution, dispatch, Session, or shutdown API.
/// Generated or handwritten registrars use it only during Runtime assembly and
/// must not retain it for later business operations.
abstract interface class CCRegistry {
  /// Registers one implementation of service contract [T].
  ///
  /// Use for capabilities resolved later through `CCRouter.service<T>()`.
  void registerService<T extends Object>(CCServiceProvider<T> provider);

  /// Registers one Runtime-wide initialization task for the current component.
  ///
  /// Use for one-time startup work that needs an explicit dependency DAG or
  /// Gate. Service instance readiness belongs in [CCServiceInitializer].
  void registerInitializationTask(CCInitializationTask task);

  /// Registers the single handler for command type [C].
  ///
  /// Use when exactly one component owns a side-effecting operation.
  void registerCommand<C extends CCCommand<R>, R>(CCHandler<C, R> handler);

  /// Registers an event subscriber under the globally stable [id].
  ///
  /// Use for independent listeners reacting to an already completed fact. The
  /// ID must be unique across the Runtime and should remain stable for Trace and
  /// diagnostics. Subscribers are installed for the Runtime lifetime.
  void registerEvent<E extends CCEvent>(String id, CCHandler<E, void> handler);

  /// Registers a route definition owned by the current component.
  ///
  /// Generated route registrars use this during component assembly; ownership
  /// is injected by the Runtime and cannot be supplied by component code.
  void registerRoute<A, R>(CCRouteDefinition<A, R> definition);

  /// Registers a route interceptor owned by the current component.
  ///
  /// Route definitions refer to [id] in their `interceptorIds` list. The
  /// interceptor is invoked only after global interceptors and cannot access
  /// the Runtime or navigation Adapter directly.
  void registerRouteInterceptor(
    String id,
    CCNavigationInterceptor interceptor, {
    Duration? timeout,
  });

  /// Registers a synchronous Pop guard owned by the current component.
  ///
  /// Route definitions refer to [id] in their `popGuardIds` list. Use this for
  /// managed-route exit rules that can be decided from current in-memory state;
  /// asynchronous confirmation UI should use Flutter `PopScope` instead.
  void registerRoutePopGuard(String id, CCPopGuard guard);

  /// Registers a Shell definition owned by the current component.
  ///
  /// Generated Shell registrars use this for persistent containers and
  /// independent navigation branches. The Runtime injects component ownership;
  /// component code supplies only the adapter-neutral contract.
  void registerShell(CCShellDefinition definition);
}

/// Component-bound implementation of the restricted registration surface.
///
/// The Runtime creates one instance per component and keeps the component
/// owner alongside the registry.  Component code can therefore register
/// capabilities without receiving the Runtime or its resolution APIs.
final class _CCComponentRegistry implements CCRegistry {
  /// Creates a registry bound to [ownerComponentId] in [runtime].
  _CCComponentRegistry({required this.runtime, required this.ownerComponentId});

  /// Runtime that owns the registrations made through this registry.
  final CCRouterRuntime runtime;

  /// Stable component ID trusted by the Runtime for future owned entries.
  final String ownerComponentId;

  /// Registers a service on behalf of the owning component.
  @override
  void registerService<T extends Object>(CCServiceProvider<T> provider) {
    runtime._registerServiceForComponent(ownerComponentId, provider);
  }

  /// Registers an initialization task on behalf of the owning component.
  @override
  void registerInitializationTask(CCInitializationTask task) {
    runtime._registerInitializationTaskForComponent(ownerComponentId, task);
  }

  /// Registers a command on behalf of the owning component.
  @override
  void registerCommand<C extends CCCommand<R>, R>(CCHandler<C, R> handler) {
    runtime._registerCommandForComponent(ownerComponentId, handler);
  }

  /// Registers an event subscriber on behalf of the owning component.
  @override
  void registerEvent<E extends CCEvent>(String id, CCHandler<E, void> handler) {
    runtime._registerEventForComponent(ownerComponentId, id, handler);
  }

  /// Registers a route definition on behalf of the owning component.
  @override
  void registerRoute<A, R>(CCRouteDefinition<A, R> definition) {
    runtime._registerRouteForComponent(ownerComponentId, definition);
  }

  /// Registers a route interceptor on behalf of the owning component.
  @override
  void registerRouteInterceptor(
    String id,
    CCNavigationInterceptor interceptor, {
    Duration? timeout,
  }) {
    runtime._registerRouteInterceptorForComponent(
      ownerComponentId,
      id,
      interceptor,
      timeout: timeout,
    );
  }

  /// Registers a route Pop guard on behalf of the owning component.
  @override
  void registerRoutePopGuard(String id, CCPopGuard guard) {
    runtime._registerRoutePopGuardForComponent(ownerComponentId, id, guard);
  }

  /// Registers a Shell definition on behalf of the owning component.
  @override
  void registerShell(CCShellDefinition definition) {
    runtime._registerShellForComponent(ownerComponentId, definition);
  }
}

/// Describes how a service implementation is created and owned.
///
/// Component registrars use providers to select the factory, contract, key,
/// default choice, ownership Scope, and creation policy for one implementation
/// of a service contract. Scope controls disposal ownership; creation policy
/// controls whether the instance is cached within that Scope.
final class CCServiceProvider<T extends Object> {
  /// Creates a provider for service contract [T].
  const CCServiceProvider({
    required this.factory,
    this.initializer,
    this.contract,
    this.key,
    this.scope = CCServiceScope.app,
    this.creationPolicy = CCServiceCreationPolicy.singleton,
    this.isDefault = false,
  });

  /// Factory invoked lazily when the service is first resolved.
  final CCServiceFactory<T> factory;

  /// Optional lazy asynchronous readiness initializer.
  ///
  /// Use only when the Service cannot safely serve methods until asynchronous
  /// setup completes. Runtime starts it through `serviceAsync` or a generated
  /// proxy, never during synchronous registration or application startup.
  final CCServiceInitializer<T>? initializer;

  /// Stable cross-package contract token, when this service is promoted.
  ///
  /// Omit for component-internal services. Supplying a token keeps legacy
  /// type-based lookup available while enabling callers to migrate to a stable
  /// identity without creating a second provider or service instance.
  final CCServiceToken<T>? contract;

  /// Optional typed key identifying a named implementation.
  final CCServiceKey<T>? key;

  /// Lifecycle Scope that owns created instances.
  final CCServiceScope scope;

  /// Whether the owning Scope caches or recreates the service.
  final CCServiceCreationPolicy creationPolicy;

  /// Whether this provider is selected when no key is supplied.
  final bool isDefault;
}

/// Type-erased internal service provider record.
final class _Provider {
  /// Creates the normalized provider stored in the registry.
  _Provider(
    this.type,
    this.contractId,
    this.name,
    this.ownerComponentId,
    this.scope,
    this.creationPolicy,
    this.isDefault,
    this.factory,
    this.initializer,
  );

  /// Service contract type.
  final Type type;

  /// Stable promoted contract identity, or null for internal type-only lookup.
  final String? contractId;

  /// Named implementation key, or null for an unkeyed provider.
  final String? name;

  /// Trusted component that registered this provider.
  final String ownerComponentId;

  /// Lifecycle Scope assigned to created instances.
  final CCServiceScope scope;

  /// Creation policy applied inside [scope].
  final CCServiceCreationPolicy creationPolicy;

  /// Whether unkeyed resolution selects this provider.
  final bool isDefault;

  /// Type-erased instance factory.
  final CCServiceFactory<Object> factory;

  /// Type-erased lazy readiness initializer, when configured.
  final CCServiceInitializer<Object>? initializer;

  /// Creates a provider with unchanged identity and lifecycle policy but
  /// test-owned construction and readiness behavior.
  _Provider replacing({
    required CCServiceFactory<Object> factory,
    CCServiceInitializer<Object>? initializer,
  }) => _Provider(
    type,
    contractId,
    name,
    ownerComponentId,
    scope,
    creationPolicy,
    isDefault,
    factory,
    initializer,
  );
}

/// Internal test-only description of one Service Provider replacement.
///
/// The Core Runtime consumes this value only through
/// [CCRouterRuntime.forTesting]. The public test package wraps it in
/// `CCServiceOverride`, so production applications cannot install replacements
/// through `CCRouter.initialize`. The target Provider must already be
/// registered; its Scope, creation policy, key, and contract identity remain
/// authoritative for the replacement.
@visibleForTesting
final class CCServiceOverrideEntry<T extends Object> {
  /// Creates a replacement for the Provider identified by [contract] or [T]
  /// and optionally narrowed by [key].
  const CCServiceOverrideEntry({
    required this.factory,
    this.initializer,
    this.contract,
    this.key,
  });

  /// Replacement factory invoked with the owning Scope context.
  final CCServiceFactory<T> factory;

  /// Optional test-owned readiness initializer for replacement instances.
  ///
  /// Null deliberately clears the production Provider's initializer so a fake
  /// never triggers production I/O or SDK setup implicitly.
  final CCServiceInitializer<Object>? initializer;

  /// Promoted contract identity to replace, when this service uses one.
  final CCServiceToken<T>? contract;

  /// Named implementation to replace, or null for the default Provider.
  final CCServiceKey<T>? key;

  /// Runtime Dart type used for type-only replacement lookup.
  Type get type => T;
}
