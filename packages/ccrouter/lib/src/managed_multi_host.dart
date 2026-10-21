import 'dart:async';

import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:flutter/widgets.dart';

import 'app.dart';
import 'facade.dart';
import 'managed_router.dart';
import 'multi_host.dart';
import 'route_catalog.dart';

/// Creates one native Managed Backend for a declared Host.
typedef CCManagedHostBackendFactory =
    CCManagedRouterBackend Function(CCManagedHostBackendConfiguration config);

/// Immutable inputs supplied to one Managed Host factory.
final class CCManagedHostBackendConfiguration {
  /// Creates a framework-owned Host factory input.
  const CCManagedHostBackendConfiguration._({
    required this.hostId,
    required this.catalog,
    required this.isDefaultHost,
  });

  /// Stable Host identity selected by the aggregate Backend.
  final String hostId;

  /// Exact Catalog retained by the initialized Host Assembly.
  final CCFlutterRouteCatalog catalog;

  /// Whether this Host is the aggregate's initial default Host.
  final bool isDefaultHost;
}

/// Aggregates independent native Managed Hosts under one Runtime Adapter.
///
/// Each child owns its own immutable Stack Store, RouterConfig, Navigator keys,
/// and optional predictive-back bridge. The aggregate only resolves default
/// placement, forwards Runtime operations, and exposes child RouterConfigs for
/// the Host-owned layout. It never mirrors or edits a GoRouter match tree.
final class CCManagedMultiHostBackend implements CCRouterAppBackend {
  /// Builds child Managed Backends from the initialized Host Catalog.
  ///
  /// [hostFactories] must contain [defaultHostId]. Factory failures dispose all
  /// children already created in the same attempt and rethrow the original
  /// error, so partial Host ownership cannot escape the constructor.
  factory CCManagedMultiHostBackend.managed({
    required String defaultHostId,
    required Map<String, CCManagedHostBackendFactory> hostFactories,
  }) {
    if (defaultHostId.isEmpty) {
      throw ArgumentError.value(
        defaultHostId,
        'defaultHostId',
        'Default Host ID cannot be empty.',
      );
    }
    if (hostFactories.isEmpty || !hostFactories.containsKey(defaultHostId)) {
      throw ArgumentError.value(
        hostFactories,
        'hostFactories',
        'The default Host must have one Backend factory.',
      );
    }
    final catalog = CCRouterHostBinding.routeCatalog;
    final backends = <String, CCManagedRouterBackend>{};
    final identities = Set<CCManagedRouterBackend>.identity();
    try {
      for (final entry in hostFactories.entries) {
        if (entry.key.isEmpty) {
          throw ArgumentError.value(
            entry.key,
            'hostFactories',
            'Host ID cannot be empty.',
          );
        }
        final backend = entry.value(
          CCManagedHostBackendConfiguration._(
            hostId: entry.key,
            catalog: catalog,
            isDefaultHost: entry.key == defaultHostId,
          ),
        );
        if (!identities.add(backend)) {
          throw CCNavigationAdapterError(
            'Host factory "${entry.key}" returned a Backend already owned by '
            'another Host.',
          );
        }
        // Retain the returned child before validating its identity so every
        // resource returned by a factory is covered by rollback cleanup.
        backends[entry.key] = backend;
        if (backend.host.id != entry.key) {
          throw CCNavigationAdapterError(
            'Host factory "${entry.key}" returned Backend Host '
            '"${backend.host.id}".',
          );
        }
        if (!identical(backend.routeCatalog, catalog)) {
          throw CCRegistrationError(
            'Host factory "${entry.key}" returned a Backend created from a '
            'different route Catalog.',
          );
        }
      }
      return CCManagedMultiHostBackend._(
        routeCatalog: catalog,
        defaultHostId: defaultHostId,
        backends: backends,
        adapter: CCMultiHostNavigationAdapter(
          defaultHostId: defaultHostId,
          adapters: {
            for (final entry in backends.entries)
              entry.key: entry.value.navigationAdapter,
          },
        ),
      );
    } catch (error, stackTrace) {
      _disposeUnattachedBackends(backends.values);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  CCManagedMultiHostBackend._({
    required this.routeCatalog,
    required this.defaultHostId,
    required Map<String, CCManagedRouterBackend> backends,
    required this.adapter,
  }) : _backends = backends,
       _defaultHost = backends[defaultHostId]!.host;

  /// Exact Catalog shared by every child Backend.
  @override
  final CCFlutterRouteCatalog routeCatalog;

  /// Stable Host used for default placement and App scope resolution.
  @override
  CCNavigationHost get host => _defaultHost;

  /// Initial active Host for default-placement requests.
  final String defaultHostId;

  /// Multi-Host Adapter transferred into Runtime ownership.
  final CCMultiHostNavigationAdapter adapter;

  final Map<String, CCManagedRouterBackend> _backends;
  final CCNavigationHost _defaultHost;
  bool _disposed = false;

  /// Host IDs assembled by this Backend.
  Set<String> get hostIds => Set.unmodifiable(_backends.keys);

  /// Returns one child Backend by Host identity.
  CCManagedRouterBackend backendFor(String hostId) {
    if (_disposed) {
      throw const CCNavigationAdapterError(
        'The multi-Host Managed Backend has been disposed.',
      );
    }
    final backend = _backends[hostId];
    if (backend == null) {
      throw CCNavigationAdapterError(
        'Managed Host "$hostId" is not registered.',
      );
    }
    return backend;
  }

  /// Returns the RouterConfig projected by one child Host.
  RouterConfig<CCManagedRouteConfiguration> routerConfigFor(String hostId) =>
      backendFor(hostId).routerConfig;

  /// Returns one child Host's Navigator topology.
  CCNavigationHost hostFor(String hostId) => backendFor(hostId).host;

  @override
  /// Adapter multiplexer initialized and disposed by Runtime.
  CCNavigationAdapter get navigationAdapter => adapter;

  @override
  /// Releases every child Adapter and RouterConfig exactly once.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final children = _backends.values.toList(growable: false);
    _backends.clear();
    Object? firstError;
    StackTrace? firstStack;
    for (final backend in children) {
      try {
        await backend.dispose();
      } catch (error, stackTrace) {
        firstError ??= error;
        firstStack ??= stackTrace;
      }
    }
    if (firstError != null) Error.throwWithStackTrace(firstError, firstStack!);
  }

  static void _disposeUnattachedBackends(
    Iterable<CCManagedRouterBackend> backends,
  ) {
    for (final backend in backends) {
      try {
        backend.navigationAdapter.dispose();
      } catch (error, stackTrace) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'ccrouter',
            context: ErrorDescription('while disposing child Managed Adapter'),
          ),
        );
      }
      unawaited(
        backend.dispose().catchError((Object error, StackTrace stack) {
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stack,
              library: 'ccrouter',
              context: ErrorDescription(
                'while disposing child Managed Backend',
              ),
            ),
          );
        }),
      );
    }
  }
}
