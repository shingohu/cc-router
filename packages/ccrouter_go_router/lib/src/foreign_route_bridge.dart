part of 'adapter.dart';

/// Immutable identity returned for one explicitly bridged foreign route.
///
/// Application hosts retain this handle only while integrating a third-party
/// Navigator. It is not a business route handle and cannot perform navigation
/// through `CCRouter.navigator`.
final class CCGoRouterForeignRouteHandle {
  /// Creates a bridge-owned handle for one foreign backend entry.
  const CCGoRouterForeignRouteHandle._({
    required this.backendEntryId,
    required this.navigatorOutlet,
    required this.hostId,
    required this.location,
  });

  /// Stable backend identity allocated by the owning bridge.
  final String backendEntryId;

  /// Navigator Outlet containing the foreign route.
  final String navigatorOutlet;

  /// Optional Window or display host identity.
  final String? hostId;

  /// Optional backend location retained for diagnostics.
  final String? location;
}

/// Host-only bridge for explicitly reporting third-party Navigator routes.
///
/// Use this when an independent or third-party Navigator cannot install a
/// [CCGoRouterNavigationObserver] but can notify the application host about
/// stack changes. Reported routes remain foreign: they never create a
/// CCRouter RouteEntry, Route Scope, typed result, or business navigation API.
/// Do not use this bridge for `OverlayEntry`, menus, or page-local UI unless
/// the host only needs diagnostic lifecycle records.
final class CCGoRouterForeignRouteBridge {
  /// Creates an adapter-owned bridge with private event publishing callbacks.
  CCGoRouterForeignRouteBridge._({
    required String Function() allocateBackendEntryId,
    required void Function(
      CCNavigationBackendEventKind kind,
      CCGoRouterForeignRouteHandle handle,
      CCGoRouterForeignRouteHandle? previous,
    )
    publish,
  }) : _allocateBackendEntryId = allocateBackendEntryId,
       _publish = publish;

  /// Allocates backend identities in the owning Adapter namespace.
  final String Function() _allocateBackendEntryId;

  /// Publishes bridge events through the owning Adapter event source.
  final void Function(
    CCNavigationBackendEventKind kind,
    CCGoRouterForeignRouteHandle handle,
    CCGoRouterForeignRouteHandle? previous,
  )
  _publish;

  /// Active handles owned by this bridge, indexed by backend identity.
  final Map<String, CCGoRouterForeignRouteHandle> _activeHandles = {};

  /// Reports a foreign route entering one Navigator stack.
  CCGoRouterForeignRouteHandle push({
    String navigatorOutlet = 'root',
    String? hostId,
    String? location,
  }) {
    _validateOutlet(navigatorOutlet);
    final handle = CCGoRouterForeignRouteHandle._(
      backendEntryId: _allocateBackendEntryId(),
      navigatorOutlet: navigatorOutlet,
      hostId: hostId,
      location: location,
    );
    _publish(CCNavigationBackendEventKind.push, handle, null);
    _activeHandles[handle.backendEntryId] = handle;
    return handle;
  }

  /// Reports an atomic replacement and returns the new foreign handle.
  CCGoRouterForeignRouteHandle replace(
    CCGoRouterForeignRouteHandle previous, {
    String? navigatorOutlet,
    String? hostId,
    String? location,
  }) {
    _requireActive(previous);
    final outlet = navigatorOutlet ?? previous.navigatorOutlet;
    _validateOutlet(outlet);
    final next = CCGoRouterForeignRouteHandle._(
      backendEntryId: _allocateBackendEntryId(),
      navigatorOutlet: outlet,
      hostId: hostId ?? previous.hostId,
      location: location,
    );
    _publish(CCNavigationBackendEventKind.replace, next, previous);
    _activeHandles.remove(previous.backendEntryId);
    _activeHandles[next.backendEntryId] = next;
    return next;
  }

  /// Reports a foreign route being popped from its Navigator stack.
  void pop(CCGoRouterForeignRouteHandle handle) {
    _reportRemoval(CCNavigationBackendEventKind.pop, handle);
  }

  /// Reports a foreign route being removed without becoming active.
  void remove(CCGoRouterForeignRouteHandle handle) {
    _reportRemoval(CCNavigationBackendEventKind.remove, handle);
  }

  /// Reports and forgets one active bridge-owned handle.
  void _reportRemoval(
    CCNavigationBackendEventKind kind,
    CCGoRouterForeignRouteHandle handle,
  ) {
    _requireActive(handle);
    _publish(kind, handle, null);
    _activeHandles.remove(handle.backendEntryId);
  }

  /// Rejects empty Outlet identities at the host integration boundary.
  void _validateOutlet(String outlet) {
    if (outlet.isEmpty) {
      throw ArgumentError.value(outlet, 'navigatorOutlet');
    }
  }

  /// Ensures a handle belongs to this bridge and is still active.
  void _requireActive(CCGoRouterForeignRouteHandle handle) {
    if (!identical(_activeHandles[handle.backendEntryId], handle)) {
      throw const CCNavigationAdapterError(
        'Foreign route handle is inactive or belongs to another bridge.',
      );
    }
  }

  /// Forgets active host handles when the owning Adapter is disposed.
  void _dispose() {
    _activeHandles.clear();
  }
}
