part of 'runtime.dart';

/// Creates a service instance inside the active invocation and Scope context.
///
/// Component registrars use factories when service construction requires the
/// Runtime-provided deadline, cancellation, or trace context.
typedef CCServiceFactory<T> = T Function(CCInvocationContext context);

/// Handles a typed message [M] and returns a synchronous or asynchronous [R].
///
/// Use handlers in component registration for Command, Query, Action, and Event
/// processing; business callers dispatch messages through `CCRouter` instead.
typedef CCHandler<M, R> =
    FutureOr<R> Function(M message, CCInvocationContext context);

/// Type-erased handler stored by the internal dispatcher.
typedef _Handler =
    FutureOr<Object?> Function(Object message, CCInvocationContext context);

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

  /// Registers the single handler for command type [C].
  ///
  /// Use when exactly one component owns a side-effecting operation.
  void registerCommand<C extends CCCommand<R>, R>(CCHandler<C, R> handler);

  /// Registers the single handler for query type [Q].
  ///
  /// Use when exactly one component owns a side-effect-free read operation.
  void registerQuery<Q extends CCQuery<R>, R>(CCHandler<Q, R> handler);

  /// Registers an action handler under the globally stable [id].
  ///
  /// Use when multiple components may handle an explicitly requested action.
  void registerAction<A extends CCAction>(
    String id,
    CCHandler<A, void> handler,
  );

  /// Registers an event subscriber under the globally stable [id].
  ///
  /// Use for independent listeners reacting to an already completed fact.
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
  void registerRouteInterceptor(String id, CCNavigationInterceptor interceptor);

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

  /// Registers a command on behalf of the owning component.
  @override
  void registerCommand<C extends CCCommand<R>, R>(CCHandler<C, R> handler) {
    runtime._registerCommandForComponent(ownerComponentId, handler);
  }

  /// Registers a query on behalf of the owning component.
  @override
  void registerQuery<Q extends CCQuery<R>, R>(CCHandler<Q, R> handler) {
    runtime._registerQueryForComponent(ownerComponentId, handler);
  }

  /// Registers an action on behalf of the owning component.
  @override
  void registerAction<A extends CCAction>(
    String id,
    CCHandler<A, void> handler,
  ) {
    runtime._registerActionForComponent(ownerComponentId, id, handler);
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
    CCNavigationInterceptor interceptor,
  ) {
    runtime._registerRouteInterceptorForComponent(
      ownerComponentId,
      id,
      interceptor,
    );
  }

  /// Registers a Shell definition on behalf of the owning component.
  @override
  void registerShell(CCShellDefinition definition) {
    runtime._registerShellForComponent(ownerComponentId, definition);
  }
}

/// Describes how a service implementation is created and owned.
///
/// Component registrars use providers to select factory, key, default choice,
/// and lifecycle Scope for one implementation of a service contract.
final class CCServiceProvider<T extends Object> {
  /// Creates a provider for service contract [T].
  const CCServiceProvider({
    required this.factory,
    this.contract,
    this.key,
    this.scope = CCServiceScope.app,
    this.isDefault = false,
  });

  /// Factory invoked lazily when the service is first resolved.
  final CCServiceFactory<T> factory;

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
    this.scope,
    this.isDefault,
    this.factory,
  );

  /// Service contract type.
  final Type type;

  /// Stable promoted contract identity, or null for internal type-only lookup.
  final String? contractId;

  /// Named implementation key, or null for an unkeyed provider.
  final String? name;

  /// Lifecycle Scope assigned to created instances.
  final CCServiceScope scope;

  /// Whether unkeyed resolution selects this provider.
  final bool isDefault;

  /// Type-erased instance factory.
  final CCServiceFactory<Object> factory;
}
