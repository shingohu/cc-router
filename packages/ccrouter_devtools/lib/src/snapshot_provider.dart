import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter_devtools_protocol/ccrouter_devtools_protocol.dart';
import 'package:flutter/foundation.dart';

import 'host_state.dart';
import 'snapshot.dart';

/// Supplies immutable CCRouter diagnostics to a read-only visualization.
///
/// Implementations must not expose mutable Runtime objects. The optional
/// listener registration is observational and must return an idempotent
/// remover. A static provider is useful for deterministic widget tests.
abstract interface class CCDevToolsSnapshotProvider {
  /// Captures the current immutable diagnostics view.
  CCRouterDevToolsSnapshot snapshot();

  /// Registers a callback for a best-effort refresh notification.
  ///
  /// Returning a no-op is valid when the source cannot observe changes.
  void Function() addListener(VoidCallback listener);
}

/// Reads the active CCRouter facade without exposing its Runtime internals.
///
/// This provider is intended for a Host-owned debug panel. It keeps no
/// navigation state and all listener removers are released by the panel.
final class CCRouterDevToolsSnapshotProvider
    implements CCDevToolsSnapshotProvider {
  /// Creates a provider backed by the process-default CCRouter facade.
  const CCRouterDevToolsSnapshotProvider({this.catalog});

  /// Optional source index overriding the active generated Host Catalog.
  ///
  /// Ordinary panels omit this value and automatically observe the Catalog
  /// installed by [CCDevToolsHostIntegration]. Tests and standalone diagnostic
  /// surfaces may provide an explicit deterministic Catalog.
  final CCDevToolsStaticCatalogSnapshot? catalog;

  @override
  /// Captures bounded snapshots, or an empty uninitialized view.
  CCRouterDevToolsSnapshot snapshot() {
    if (!CCRouter.isInitialized) return CCRouterDevToolsSnapshot.empty();
    try {
      return CCRouterDevToolsSnapshot(
        capturedAt: DateTime.now(),
        runtimeState: CCDevToolsRuntimeState.initialized,
        catalog: catalog ?? CCDevToolsHostState.catalog,
        components: CCRouter.registeredComponents,
        routeEntries: CCRouter.activeRouteEntries,
        backendEntries: CCRouter.backendEntries,
        traces: CCRouter.recentTraces,
        navigationEvents: CCRouter.recentNavigationEvents,
        navigationFailures: CCRouter.recentNavigationFailures,
        capabilityFallbacks: CCRouter.recentNavigationCapabilityFallbacks,
        visibilityEvents: CCRouter.recentRouteVisibilityEvents,
        backendEvents: CCRouter.recentBackendNavigationEvents,
        initTasks: CCRouter.initTasks,
        pendingNavigations: CCRouter.pendingNavigations,
      );
    } on StateError {
      // Runtime can be shut down between the status check and the read.
      return CCRouterDevToolsSnapshot.empty();
    }
  }

  @override
  /// Observes existing Runtime diagnostic streams and never starts navigation.
  void Function() addListener(VoidCallback listener) {
    if (!CCRouter.isInitialized) return () {};
    final removers = <void Function()>[];
    try {
      removers.add(CCRouter.addNavigationListener((_) => listener()));
      removers.add(CCRouter.addNavigationFailureListener((_) => listener()));
      removers.add(
        CCRouter.addNavigationCapabilityFallbackListener((_) => listener()),
      );
      removers.add(CCRouter.addRouteVisibilityListener((_) => listener()));
      removers.add(CCRouter.addBackendNavigationListener((_) => listener()));
    } on StateError {
      for (final remove in removers) {
        remove();
      }
      return () {};
    }
    var removed = false;
    return () {
      if (removed) return;
      removed = true;
      for (final remove in removers) {
        remove();
      }
    };
  }
}

/// Provides a fixed snapshot and no-op observation for widget tests.
final class CCStaticDevToolsSnapshotProvider
    implements CCDevToolsSnapshotProvider {
  /// Creates a provider that always returns [value].
  CCStaticDevToolsSnapshotProvider(this.value);

  /// Snapshot returned by [snapshot].
  CCRouterDevToolsSnapshot value;

  @override
  /// Returns the current test snapshot without copying source objects.
  CCRouterDevToolsSnapshot snapshot() => value;

  @override
  /// Returns an idempotent no-op remover because the value is static.
  void Function() addListener(VoidCallback listener) => () {};
}
