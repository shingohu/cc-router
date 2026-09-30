import 'dart:async';

import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import 'backend.dart';

/// Creates one GoRouter Backend for a declared navigation Host.
///
/// The factory receives the Catalog installed by `CCRouter.initialize` and the
/// Host ID declared by [CCGoRouterMultiHostBackend.managed]. It must return a
/// Backend bound to that exact Host ID and Catalog snapshot.
typedef CCGoRouterHostBackendFactory =
    CCGoRouterBackend Function(
      CCGoRouterHostBackendConfiguration configuration,
    );

/// Immutable inputs supplied to one [CCGoRouterHostBackendFactory].
///
/// Host factories use this value instead of reading generated Host globals or
/// the process binding themselves. Instances are created only by
/// [CCGoRouterMultiHostBackend.managed].
final class CCGoRouterHostBackendConfiguration {
  /// Creates one framework-owned Host factory input.
  const CCGoRouterHostBackendConfiguration._({
    required this.hostId,
    required this.catalog,
  });

  /// Stable Host identity declared by the aggregate Backend.
  final String hostId;

  /// Exact backend-neutral Catalog installed by the initialized Host Assembly.
  final CCFlutterRouteCatalog catalog;
}

/// Aggregates multiple independently owned GoRouter Hosts into one App Backend.
///
/// This is an advanced Host SPI for multiple independent Router surfaces. It
/// does not choose a layout, create a `MaterialApp`, or model a platform Window.
/// Large-screen panes, tabs, and Shell branches normally remain multiple
/// Outlets of one Host instead of using this type.
///
/// The aggregate owns the child Backend resources returned by its factories.
/// After attachment, the Runtime owns [adapter] and disposes every child Adapter
/// before [dispose] releases the managed child Routers.
final class CCGoRouterMultiHostBackend implements CCRouterAppBackend {
  /// Creates child Backends from the Catalog installed by `CCRouter.initialize`.
  ///
  /// [hostFactories] must contain [defaultHostId]. Every returned Backend must
  /// use its map key as `backend.host.id` and retain the exact supplied Catalog.
  /// Factory failure disposes every Backend created earlier in the same attempt.
  factory CCGoRouterMultiHostBackend.managed({
    required String defaultHostId,
    required Map<String, CCGoRouterHostBackendFactory> hostFactories,
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
    final backends = <String, CCGoRouterBackend>{};
    final backendIdentities = Set<CCGoRouterBackend>.identity();
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
          CCGoRouterHostBackendConfiguration._(
            hostId: entry.key,
            catalog: catalog,
          ),
        );
        if (!backendIdentities.add(backend)) {
          throw CCNavigationAdapterError(
            'Host factory "${entry.key}" returned a Backend already owned by '
            'another Host.',
          );
        }
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

      final adapter = CCMultiHostNavigationAdapter(
        defaultHostId: defaultHostId,
        adapters: {
          for (final entry in backends.entries)
            entry.key: entry.value.navigationAdapter,
        },
      );
      return CCGoRouterMultiHostBackend._(
        routeCatalog: catalog,
        defaultHostId: defaultHostId,
        backends: backends,
        adapter: adapter,
      );
    } catch (error, stackTrace) {
      _disposeUnattachedBackends(backends.values);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// Stores successfully assembled child Backends and their aggregate Adapter.
  CCGoRouterMultiHostBackend._({
    required this.routeCatalog,
    required this.defaultHostId,
    required Map<String, CCGoRouterBackend> backends,
    required this.adapter,
  }) : _backends = backends,
       _defaultHost = backends[defaultHostId]!.host;

  /// Exact Catalog shared by every child Backend.
  @override
  final CCFlutterRouteCatalog routeCatalog;

  /// Host used for default-placement navigation and `CCRouterApp` scope lookup.
  @override
  CCNavigationHost get host => _defaultHost;

  /// Stable identity of the initial active Host.
  final String defaultHostId;

  /// Multi-Host Adapter transferred to the Runtime after App attachment.
  final CCMultiHostNavigationAdapter adapter;

  /// Child Backend resources indexed by Host identity until disposal.
  final Map<String, CCGoRouterBackend> _backends;

  /// Default Host retained independently of the disposable Backend map.
  final CCNavigationHost _defaultHost;

  /// Whether child Router resource ownership has ended.
  bool _disposed = false;

  /// Immutable Host identities assembled into this Backend.
  Set<String> get hostIds => Set.unmodifiable(_backends.keys);

  /// Returns the child Backend for [hostId].
  ///
  /// Host layout infrastructure may use this to mount the corresponding
  /// [CCGoRouterBackend.router]. Calls after disposal or for an unknown Host
  /// throw [CCNavigationAdapterError].
  CCGoRouterBackend backendFor(String hostId) {
    if (_disposed) {
      throw const CCNavigationAdapterError(
        'The multi-Host GoRouter Backend has been disposed.',
      );
    }
    final backend = _backends[hostId];
    if (backend == null) {
      throw CCNavigationAdapterError(
        'GoRouter Host "$hostId" is not registered.',
      );
    }
    return backend;
  }

  /// Returns the Router owned by [hostId].
  GoRouter routerFor(String hostId) => backendFor(hostId).router;

  /// Returns the navigation Host represented by [hostId].
  CCNavigationHost hostFor(String hostId) => backendFor(hostId).host;

  @override
  /// Adapter multiplexer initialized and disposed by the Runtime.
  CCNavigationAdapter get navigationAdapter => adapter;

  @override
  /// Releases every child Backend resource after Runtime Adapter disposal.
  ///
  /// Cleanup is idempotent and best-effort. A failing child does not prevent
  /// later Routers from being released; the first failure is rethrown.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final backends = _backends.values.toList(growable: false);
    _backends.clear();
    Object? firstError;
    StackTrace? firstStackTrace;
    for (final backend in backends) {
      try {
        await backend.dispose();
      } catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStackTrace!);
    }
  }

  /// Releases partial construction state without replacing the original error.
  static void _disposeUnattachedBackends(Iterable<CCGoRouterBackend> backends) {
    for (final backend in backends) {
      try {
        backend.navigationAdapter.dispose();
      } catch (error, stackTrace) {
        _reportCleanupError(error, stackTrace, 'while disposing child Adapter');
      }
      unawaited(
        backend.dispose().catchError((Object error, StackTrace stackTrace) {
          _reportCleanupError(
            error,
            stackTrace,
            'while disposing child Backend',
          );
        }),
      );
    }
  }

  /// Reports secondary construction cleanup failures through Flutter tooling.
  static void _reportCleanupError(
    Object error,
    StackTrace stackTrace,
    String context,
  ) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'ccrouter_go_router',
        context: ErrorDescription(context),
      ),
    );
  }
}
