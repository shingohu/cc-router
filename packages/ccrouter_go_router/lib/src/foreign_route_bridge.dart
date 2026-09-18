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

/// Immutable identity for one explicitly bridged opaque UI surface.
///
/// Hosts use this handle for an [OverlayEntry], [MenuAnchor],
/// `LocalHistoryEntry`, or a third-party overlay whose backend stack identity
/// is not a Flutter `Route`. The handle is diagnostic only; it cannot create
/// a CCRouter route, complete a navigation result, or close a Route Scope.
final class CCGoRouterOpaqueUiHandle {
  /// Creates a bridge-owned handle for one opaque UI surface.
  const CCGoRouterOpaqueUiHandle._({
    required this.backendEntryId,
    required this.navigatorOutlet,
    required this.hostId,
    required this.location,
  });

  /// Stable backend identity allocated by the owning bridge.
  final String backendEntryId;

  /// Navigator Outlet whose UI is covered by this surface.
  final String navigatorOutlet;

  /// Optional Window or display host identity.
  final String? hostId;

  /// Optional diagnostic location or surface label.
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
    required void Function(
      CCNavigationBackendEventKind kind,
      CCGoRouterOpaqueUiHandle handle,
    )
    publishOpaque,
  }) : _allocateBackendEntryId = allocateBackendEntryId,
       _publish = publish,
       _publishOpaque = publishOpaque;

  /// Allocates backend identities in the owning Adapter namespace.
  final String Function() _allocateBackendEntryId;

  /// Publishes bridge events through the owning Adapter event source.
  final void Function(
    CCNavigationBackendEventKind kind,
    CCGoRouterForeignRouteHandle handle,
    CCGoRouterForeignRouteHandle? previous,
  )
  _publish;

  /// Publishes opaque UI events through the owning Adapter event source.
  final void Function(
    CCNavigationBackendEventKind kind,
    CCGoRouterOpaqueUiHandle handle,
  )
  _publishOpaque;

  /// Active handles owned by this bridge, indexed by backend identity.
  final Map<String, CCGoRouterForeignRouteHandle> _activeHandles = {};

  /// Active opaque UI handles owned by this bridge.
  final Map<String, CCGoRouterOpaqueUiHandle> _activeOpaqueHandles = {};

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

  /// Reports an opaque UI surface entering an Outlet without creating a Route.
  ///
  /// Use this for UI that is visually or interactively above a CCRouter page
  /// but is not represented by a Navigator `Route`, such as an overlay menu,
  /// a `LocalHistoryEntry`, or a third-party popup system. Removing the
  /// surface later only updates diagnostics and never changes CCRouter's
  /// managed RouteEntry stack.
  CCGoRouterOpaqueUiHandle pushOpaque({
    String navigatorOutlet = 'root',
    String? hostId,
    String? location,
  }) {
    _validateOutlet(navigatorOutlet);
    final handle = CCGoRouterOpaqueUiHandle._(
      backendEntryId: _allocateBackendEntryId(),
      navigatorOutlet: navigatorOutlet,
      hostId: hostId,
      location: location,
    );
    _publishOpaque(CCNavigationBackendEventKind.push, handle);
    _activeOpaqueHandles[handle.backendEntryId] = handle;
    return handle;
  }

  /// Reports an opaque UI surface leaving an Outlet.
  ///
  /// The handle must be active and must have been created by this bridge.
  /// Calling this twice, or passing a handle from another adapter, throws a
  /// [CCNavigationAdapterError] instead of affecting any managed route.
  void removeOpaque(CCGoRouterOpaqueUiHandle handle) {
    _requireActiveOpaque(handle);
    _publishOpaque(CCNavigationBackendEventKind.remove, handle);
    _activeOpaqueHandles.remove(handle.backendEntryId);
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

  /// Ensures an opaque handle belongs to this bridge and is still active.
  void _requireActiveOpaque(CCGoRouterOpaqueUiHandle handle) {
    if (!identical(_activeOpaqueHandles[handle.backendEntryId], handle)) {
      throw const CCNavigationAdapterError(
        'Opaque UI handle is inactive or belongs to another bridge.',
      );
    }
  }

  /// Forgets active host handles when the owning Adapter is disposed.
  void _dispose() {
    _activeHandles.clear();
    _activeOpaqueHandles.clear();
  }
}
