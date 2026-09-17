part of 'runtime.dart';

/// Creates a service instance inside the active invocation and Scope context.
typedef CCServiceFactory<T> = T Function(CCInvocationContext context);

/// Handles a typed message [M] and returns a synchronous or asynchronous [R].
typedef CCHandler<M, R> =
    FutureOr<R> Function(M message, CCInvocationContext context);

/// Type-erased handler stored by the internal dispatcher.
typedef _Handler =
    FutureOr<Object?> Function(Object message, CCInvocationContext context);

/// Registration-only surface supplied to component registrars.
///
/// It intentionally exposes no resolution, dispatch, Session, or shutdown API.
abstract interface class CCRegistry {
  /// Registers one implementation of service contract [T].
  void registerService<T extends Object>(CCServiceProvider<T> provider);

  /// Registers the single handler for command type [C].
  void registerCommand<C extends CCCommand<R>, R>(CCHandler<C, R> handler);

  /// Registers the single handler for query type [Q].
  void registerQuery<Q extends CCQuery<R>, R>(CCHandler<Q, R> handler);

  /// Registers an action handler under the globally stable [id].
  void registerAction<A extends CCAction>(
    String id,
    CCHandler<A, void> handler,
  );

  /// Registers an event subscriber under the globally stable [id].
  void registerEvent<E extends CCEvent>(String id, CCHandler<E, void> handler);
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
}

/// Describes how a service implementation is created and owned.
final class CCServiceProvider<T extends Object> {
  /// Creates a provider for service contract [T].
  const CCServiceProvider({
    required this.factory,
    this.key,
    this.scope = CCServiceScope.app,
    this.isDefault = false,
  });

  /// Factory invoked lazily when the service is first resolved.
  final CCServiceFactory<T> factory;

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
  _Provider(this.type, this.name, this.scope, this.isDefault, this.factory);

  /// Service contract type.
  final Type type;

  /// Named implementation key, or null for an unkeyed provider.
  final String? name;

  /// Lifecycle Scope assigned to created instances.
  final CCServiceScope scope;

  /// Whether unkeyed resolution selects this provider.
  final bool isDefault;

  /// Type-erased instance factory.
  final CCServiceFactory<Object> factory;
}
