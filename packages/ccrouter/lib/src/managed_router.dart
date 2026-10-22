import 'dart:async';

import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:flutter/cupertino.dart'
    show CupertinoApp, CupertinoPageRoute, InheritedCupertinoTheme;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart'
    show MaterialApp, MaterialPageRoute, TargetPlatform, Theme;
import 'package:flutter/widgets.dart';

import 'app.dart';
import 'facade.dart';
import 'flutter_route_factory.dart';
import 'managed_predictive_back.dart';
import 'route_catalog.dart';

/// Builds an application-owned layout around managed Shell Outlet Navigators.
///
/// The callback may place one Outlet for a compact tab layout or multiple
/// Outlets for a split view. It must use [CCManagedShellScope.navigatorFor]
/// instead of creating another Navigator for the same Outlet.
typedef CCManagedShellBuilder =
    Widget Function(BuildContext context, CCManagedShellScope shell);

/// Materializes Shell bindings once and rejects duplicate structural identity.
Map<String, CCManagedShellBinding> _indexManagedShellBindings(
  Iterable<CCManagedShellBinding> bindings,
) {
  final indexed = <String, CCManagedShellBinding>{};
  for (final binding in bindings) {
    if (indexed.containsKey(binding.shellId)) {
      throw ArgumentError.value(
        bindings,
        'shellBindings',
        'Managed Shell bindings must have unique Shell IDs.',
      );
    }
    indexed[binding.shellId] = binding;
  }
  return Map.unmodifiable(indexed);
}

/// Host binding that supplies the visual container for one Shell contract.
///
/// Components continue to own only the adapter-neutral `CCShellDefinition`.
/// The application Host owns this Flutter builder and may change its layout
/// without exposing widgets or Navigator keys to feature packages.
final class CCManagedShellBinding {
  /// Creates a Flutter binding for [shellId].
  const CCManagedShellBinding({required this.shellId, required this.builder});

  /// Stable Shell identity matching one registered `CCShellDefinition`.
  final String shellId;

  /// Application-owned layout builder for this Shell.
  final CCManagedShellBuilder builder;
}

/// Immutable build-time view of one managed Shell.
///
/// This object is recreated after Store changes and retains no BuildContext.
/// Host UI can activate a stateful branch explicitly; ordinary navigation from
/// a mounted page should pass its `BuildContext` to `CCRouter.navigator` so the
/// exact Host and Outlet are resolved without consulting focus.
final class CCManagedShellScope {
  /// Creates one Host-only Shell rendering snapshot.
  const CCManagedShellScope._({
    required this.shellId,
    required this.type,
    required this.outlets,
    required this.activeOutlet,
    required Map<String, Widget> navigators,
    required void Function(String outlet) activateOutlet,
  }) : _navigators = navigators,
       _activateOutlet = activateOutlet;

  /// Stable Shell identity.
  final String shellId;

  /// Contracted Shell navigation structure.
  final CCShellType type;

  /// Ordered Outlet identities declared by the Shell contract.
  final List<String> outlets;

  /// Foreground branch used by compact stateful layouts.
  final String activeOutlet;

  /// Prebuilt managed Navigators indexed by Outlet identity.
  final Map<String, Widget> _navigators;

  /// Adapter callback used to change a stateful foreground branch.
  final void Function(String outlet) _activateOutlet;

  /// Returns the managed Navigator for [outlet].
  ///
  /// Unknown or foreign Outlet identities fail closed with
  /// [CCNavigationAdapterError]. A builder must mount each returned Widget at
  /// most once in its output tree.
  Widget navigatorFor(String outlet) {
    final navigator = _navigators[outlet];
    if (navigator == null) {
      throw CCNavigationAdapterError(
        'Managed Shell "$shellId" does not declare Outlet "$outlet".',
      );
    }
    return navigator;
  }

  /// Makes [outlet] the foreground branch of a stateful Shell.
  ///
  /// The operation preserves every branch stack. Calling this for a
  /// single-Navigator Shell or an unknown Outlet throws.
  void activateOutlet(String outlet) => _activateOutlet(outlet);
}

/// Renders one independently managed named Outlet of a backend.
///
/// Use this for adaptive panes that are not owned by a Shell. The Host must
/// register the same Outlet key on [CCNavigationHost]. Pointer and focus events
/// only select the fallback Back target; context-scoped navigation resolves the
/// Outlet directly and does not depend on those events.
final class CCManagedOutlet extends StatefulWidget {
  /// Creates a renderer for [outlet] in [backend].
  const CCManagedOutlet({
    required this.backend,
    required this.outlet,
    super.key,
  });

  /// Backend whose Store owns the Outlet stack.
  final CCManagedRouterBackend backend;

  /// Stable named Outlet registered by the backend Host.
  final String outlet;

  @override
  /// Creates the listener that projects Store revisions into a Navigator.
  State<CCManagedOutlet> createState() => _CCManagedOutletState();
}

/// Flutter Router backend whose managed page stacks are owned by CCRouter.
///
/// Unlike compatibility adapters, this backend does not mirror another
/// router's match tree. Runtime-validated requests mutate one immutable stack
/// partition and [routerConfig] projects that state through `Navigator.pages`.
/// Application composition roots own this object and pass it to
/// `CCRouterApp.managed`; Runtime owns [navigationAdapter] after successful
/// attachment.
final class CCManagedRouterBackend implements CCRouterAppBackend {
  /// Creates a single-Host managed Router backend.
  ///
  /// When [initialLocation] is non-null it is treated as trusted Host
  /// configuration. A null value consumes Flutter's platform default route and
  /// applies external Deep Link policy. This first implementation accepts root
  /// Outlet routes; Shell bindings and additional Outlet renderers are added by
  /// the same backend without changing its state ownership model.
  CCManagedRouterBackend({
    required this.routeCatalog,
    CCNavigationHost? host,
    Iterable<CCManagedShellBinding> shellBindings = const [],
    String? initialLocation = '/',
    Iterable<NavigatorObserver> additionalObservers = const [],
    bool enablePredictiveBack = false,
    bool initializeFromRouteInformation = true,
  }) : host = host ?? CCNavigationHost(),
       _initialLocationIsExternal = initialLocation == null,
       _routeInformationProvider = PlatformRouteInformationProvider(
         initialRouteInformation: RouteInformation(
           uri: Uri.parse(
             initialLocation ??
                 WidgetsBinding.instance.platformDispatcher.defaultRouteName,
           ),
         ),
       ) {
    navigationAdapter = CCManagedNavigationAdapter(
      catalog: routeCatalog,
      host: this.host,
      shellBindings: shellBindings,
      additionalObservers: additionalObservers,
      enablePredictiveBack: enablePredictiveBack,
    );
    _delegate = _CCManagedRouterDelegate(
      navigationAdapter,
      initialLocationIsExternal: _initialLocationIsExternal,
      initializeFromRouteInformation: initializeFromRouteInformation,
    );
    routerConfig = RouterConfig<CCManagedRouteConfiguration>(
      routeInformationProvider: _routeInformationProvider,
      routeInformationParser: _CCManagedRouteInformationParser(
        sessionId: navigationAdapter.routeInformationSessionId,
      ),
      routerDelegate: _delegate,
      backButtonDispatcher: RootBackButtonDispatcher(),
    );
  }

  @override
  /// Generated destination factories used to render managed Pages.
  final CCFlutterRouteCatalog routeCatalog;

  @override
  /// Stable Host whose root Navigator is rendered by [routerConfig].
  final CCNavigationHost host;

  /// Runtime-facing Adapter and managed navigation Store.
  @override
  late final CCManagedNavigationAdapter navigationAdapter;

  /// Managed Store exposed to Host composition and diagnostics code.
  ///
  /// Runtime lifecycle ownership still follows [navigationAdapter]; callers must
  /// not initialize or dispose this value directly after backend attachment.
  CCManagedNavigationAdapter get adapter => navigationAdapter;

  /// Router configuration passed to `MaterialApp.router` or `Router.withConfig`.
  late final RouterConfig<CCManagedRouteConfiguration> routerConfig;

  /// Provider owned by this backend for platform and browser route information.
  final PlatformRouteInformationProvider _routeInformationProvider;

  /// Delegate owned by this backend and detached after Runtime disposal.
  late final _CCManagedRouterDelegate _delegate;

  /// Whether the initial URI came from the platform rather than Host config.
  final bool _initialLocationIsExternal;

  /// Whether backend-owned Flutter resources were already released.
  bool _disposed = false;

  @override
  /// Releases Router listeners and the platform route-information provider.
  ///
  /// Runtime disposes [adapter] first. Repeated calls are harmless, and no
  /// application-owned Navigator or observer is disposed by this method.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _delegate.dispose();
    _routeInformationProvider.dispose();
  }
}

/// Managed Flutter Adapter backed by immutable Host/Outlet page state.
///
/// This is Host SPI exposed for diagnostics and composition tests. Feature code
/// must navigate through `CCRouter.navigator`. The Adapter owns result channels,
/// stack listeners, and temporary Navigator observations. Guarded Routes remain
/// strongly referenced only while their Route-scoped PopEntry is registered;
/// unmount, unbind, and disposal release both together. The Adapter never
/// retains a `BuildContext` or Widget.
final class CCManagedNavigationAdapter
    implements
        CCNavigationAdapter,
        CCNavigationTargetedCloseAdapter,
        CCNavigationAdapterHostBinding,
        CCNavigationAdapterCapabilitySource,
        CCNavigationBackendEventSource,
        CCNavigationBackendSnapshotSource,
        CCNavigationPopCoordinator,
        CCNavigationScopedPopCoordinator,
        CCNavigationPopTargetSource,
        CCNavigationPopGuardBinding,
        CCNavigationPredictiveBackSourceProvider {
  /// Creates an unattached Store for one [host] and generated [catalog].
  CCManagedNavigationAdapter({
    required CCFlutterRouteCatalog catalog,
    required CCNavigationHost host,
    Iterable<CCManagedShellBinding> shellBindings = const [],
    Iterable<NavigatorObserver> additionalObservers = const [],
    bool enablePredictiveBack = false,
  }) : _catalog = catalog,
       _host = host,
       _shellBindings = _indexManagedShellBindings(shellBindings),
       _additionalObservers = List.unmodifiable(additionalObservers),
       routeInformationSessionId = Object().hashCode.toRadixString(16) {
    _observers['root'] = _CCManagedNavigatorObserver(this, 'root');
    if (enablePredictiveBack) {
      _predictiveBackBridge = CCManagedPredictiveBackBridge(
        hostId: host.id,
        activeOutlet: () => _state.focusedOutlet,
        navigatorForOutlet: _navigatorForOutlet,
        backendEntryIdForRoute: _backendEntryIdForRoute,
        hasLiveEntry: (backendEntryId) => _state.entries.any(
          (entry) => entry.backendEntryId == backendEntryId,
        ),
        recordFallback: _recordPredictiveBackFallback,
      );
      _predictiveBackBridge!.attach();
    } else {
      _predictiveBackBridge = null;
    }
  }

  /// Opaque process-local identity written to browser history state.
  final String routeInformationSessionId;

  /// Generated page factories indexed during Runtime initialization.
  final CCFlutterRouteCatalog _catalog;

  /// Host owning every stack partition rendered by this Adapter.
  final CCNavigationHost _host;

  /// Application observers appended after the internal ownership observer.
  final List<NavigatorObserver> _additionalObservers;

  /// Application-owned Shell renderers indexed by contract identity.
  final Map<String, CCManagedShellBinding> _shellBindings;

  /// Optional platform predictive-back bridge, allocated only when enabled.
  late final CCManagedPredictiveBackBridge? _predictiveBackBridge;

  /// Bounded Host diagnostics for declined predictive-back starts.
  final List<CCManagedPredictiveBackFallbackEvent> _predictiveBackFallbacks =
      [];

  /// Runtime Shell metadata indexed by stable Shell identity.
  final Map<String, CCNavigationShell> _shells = {};

  /// Observer topology indexed by Navigator Outlet.
  final Map<String, _CCManagedNavigatorObserver> _observers = {};

  /// Runtime route metadata indexed by stable route ID.
  final Map<String, CCNavigationRoute> _routes = {};

  /// Current immutable navigation state.
  _CCManagedNavigationState _state = const _CCManagedNavigationState.empty();

  /// Pending typed results keyed by Runtime navigation identity.
  final Map<String, Completer<Object?>> _results = {};

  /// Weak rendered Route references keyed by backend Entry identity.
  final Map<String, WeakReference<Route<dynamic>>> _renderedRoutes = {};

  /// Runtime-owned synchronous guard evaluator while the Adapter is attached.
  CCPopGuardEvaluator? _popGuardEvaluator;

  /// Conservative Flutter gates installed on guarded managed Routes.
  final Map<ModalRoute<Object?>, _CCManagedPopEntry> _managedPopGuardEntries =
      {};

  /// Routes awaiting a mounted ModalScope before PopEntry registration.
  final Set<Route<dynamic>> _pendingManagedPopGuardRoutes = {};

  /// Whether a Runtime-approved Pop temporarily opened managed gates.
  bool _runtimeGuardedPopInProgress = false;

  /// Store listeners owned by Router delegates and Outlet renderers.
  final Set<VoidCallback> _stateListeners = {};

  /// Runtime backend-event subscribers.
  final Set<CCNavigationBackendEventListener> _backendListeners = {};

  /// Adapter-supplied results awaiting exact Route removal confirmation.
  final Map<String, Object?> _pendingRemovalResults = {};

  /// Monotonic backend event sequence scoped to this Host.
  int _eventSequence = 0;

  /// Monotonic structural order shared by root Entries and Shell anchors.
  int _entrySequence = 0;

  /// Whether Runtime initialization completed.
  bool _initialized = false;

  /// Whether Runtime permanently disposed this Adapter.
  bool _disposed = false;

  @override
  /// Concrete Host identity used for default route placement.
  String get hostId => _host.id;

  @override
  /// Capabilities guaranteed by the state-owned Flutter renderer.
  CCNavigationAdapterCapabilities get capabilities =>
      CCNavigationAdapterCapabilities(
        supportsBackendVisibilityObservation: true,
        supportsNestedNavigators: _host.navigatorKeys.length > 1,
        supportsStatefulShell: _shellBindings.isNotEmpty,
        supportsModalRoutes: true,
        supportsManagedPopObservation: true,
        supportsPredictiveBack: _predictiveBackBridge != null,
      );

  /// Optional Managed predictive-back bridge for Host integration.
  CCManagedPredictiveBackBridge? get predictiveBackBridge =>
      _predictiveBackBridge;

  /// Runtime predictive-back event source, when enabled.
  @override
  CCNavigationPredictiveBackSource? get predictiveBackSource =>
      _predictiveBackBridge;

  /// Bounded reasons why Flutter fallback was selected.
  List<CCManagedPredictiveBackFallbackEvent> get predictiveBackFallbacks =>
      List.unmodifiable(_predictiveBackFallbacks);

  /// Binds Runtime PopGuard evaluation to platform and Route-level gates.
  @override
  void bindPopGuardEvaluator(CCPopGuardEvaluator? evaluator) {
    _popGuardEvaluator = evaluator;
    _predictiveBackBridge?.bindPopGuardEvaluator(evaluator);
    if (evaluator == null) {
      _removeAllManagedPopGuards();
      return;
    }
    for (final routeReference in _renderedRoutes.values) {
      final route = routeReference.target;
      final entry = _entryForRoute(route);
      if (route != null &&
          entry != null &&
          _routeRequiresPopGuard(entry.request.routeId)) {
        _installManagedPopGuard(route);
      }
    }
  }

  /// Current state revision used by Router and focused tests.
  int get revision => _state.revision;

  /// Current managed request order without exposing mutable Store entries.
  List<CCNavigationRequest> get requests =>
      List.unmodifiable(_state.entries.map((entry) => entry.request));

  /// Internal observers installed on the root Navigator.
  List<NavigatorObserver> get _rootObservers => [
    _observerFor('root'),
    ..._additionalObservers,
  ];

  /// Current URI projected to Flutter Router, or null before first navigation.
  Uri? get _currentUri =>
      _state.entries.isEmpty ? null : _state.entries.last.request.uri;

  /// Outlet currently used for context-free Back and Pop operations.
  String get focusedOutlet => _state.focusedOutlet;

  /// Outlets currently visible in the Host layout.
  Set<String> get visibleOutlets => _state.visibleOutlets;

  /// Publishes the Outlets simultaneously visible in the current Host layout.
  ///
  /// Adaptive split-pane infrastructure calls this after layout selection. It
  /// does not push, remove, or focus a Page, and hidden branch stacks remain
  /// retained. The set must be non-empty and contain only registered Outlets.
  void updateVisibleOutlets(Iterable<String> outlets) {
    _ensureAvailable();
    final next = outlets.toSet();
    if (next.isEmpty || next.any((outlet) => !_host.containsOutlet(outlet))) {
      throw const CCNavigationAdapterError(
        'Visible Outlets must be a non-empty subset of the managed Host.',
      );
    }
    if (setEquals(next, _state.visibleOutlets)) return;
    _state = _copyState(entries: _state.entries, visibleOutlets: next);
    _notifyStateListeners();
    _emit(
      CCNavigationBackendEvent(
        kind: CCNavigationBackendEventKind.outletsChanged,
        timestamp: DateTime.now(),
        backendOperationId: 'managed-${_host.id}-${++_eventSequence}',
        hostId: _host.id,
        navigatorOutlet: _state.focusedOutlet,
        sequence: _eventSequence,
        placement: CCRoutePlacement(
          hostId: _host.id,
          navigatorOutlet: _state.focusedOutlet,
        ),
        activeNavigatorOutlets: next.toList(growable: false),
      ),
    );
  }

  @override
  /// Returns no pre-Runtime entries; initial URI admission runs through Runtime.
  List<CCInitialBackendEntrySnapshot> readInitialBackendEntries() => const [];

  @override
  /// Validates the Runtime route table against generated Flutter destinations.
  void initialize(
    List<CCNavigationRoute> routes, {
    List<CCNavigationShell> shells = const [],
  }) {
    _ensureNotDisposed();
    if (_initialized) {
      throw const CCNavigationAdapterError(
        'The managed navigation adapter is already initialized.',
      );
    }
    final runtimeShellIds = shells.map((shell) => shell.shellId).toSet();
    final bindingShellIds = _shellBindings.keys.toSet();
    if (runtimeShellIds.length != shells.length ||
        !setEquals(runtimeShellIds, bindingShellIds)) {
      throw const CCNavigationAdapterError(
        'Managed Shell bindings must match Runtime Shell contracts exactly.',
      );
    }
    for (final shell in shells) {
      final outlets = shell.outlets.toSet();
      if (outlets.length != shell.outlets.length ||
          !outlets.contains(shell.initialOutlet)) {
        throw CCNavigationAdapterError(
          'Managed Shell "${shell.shellId}" has an invalid Outlet contract.',
        );
      }
      for (final outlet in shell.outlets) {
        if (!_host.containsOutlet(outlet)) {
          throw CCNavigationAdapterError(
            'Managed Shell "${shell.shellId}" requires unregistered Outlet '
            '"$outlet" on Host "${_host.id}".',
          );
        }
        _observerFor(outlet);
      }
      _shells[shell.shellId] = shell;
    }
    final catalogIds = _catalog.destinations
        .map((destination) => destination.routeId)
        .toSet();
    for (final route in routes) {
      if (_routes.containsKey(route.routeId)) {
        throw CCNavigationAdapterError(
          'Duplicate managed route ID "${route.routeId}".',
        );
      }
      if (!catalogIds.contains(route.routeId)) {
        throw CCNavigationAdapterError(
          'Managed route "${route.routeId}" has no Flutter destination.',
        );
      }
      if (route.placement.hostId != 'default' &&
          route.placement.hostId != _host.id) {
        throw CCNavigationAdapterError(
          'Managed route "${route.routeId}" targets Host '
          '"${route.placement.hostId}", but this Backend serves "${_host.id}".',
        );
      }
      final shellId = route.placement.shellId;
      if (!_host.containsOutlet(route.placement.navigatorOutlet) ||
          (shellId != null &&
              (!_shells.containsKey(shellId) ||
                  !_shells[shellId]!.outlets.contains(
                    route.placement.navigatorOutlet,
                  )))) {
        throw CCNavigationAdapterError(
          'Managed route "${route.routeId}" targets an unconfigured Shell or '
          'Navigator Outlet.',
        );
      }
      _routes[route.routeId] = route;
    }
    _initialized = true;
  }

  @override
  /// Applies one validated request as an atomic immutable state transaction.
  Future<Object?> navigate(CCNavigationRequest request) {
    _ensureAvailable();
    _ensureRequest(request);
    switch (request.operation) {
      case CCNavigationOperation.push:
        return _push(request);
      case CCNavigationOperation.replace:
        return _replace(request);
      case CCNavigationOperation.go:
        _replaceAll(request, resetHost: false);
        return Future<Object?>.value();
      case CCNavigationOperation.reset:
        _replaceAll(request, resetHost: true);
        return Future<Object?>.value();
      case CCNavigationOperation.open:
        if (request.openMode == CCDeepLinkOpenMode.go) {
          _replaceAll(request, resetHost: false);
        } else {
          _append(request);
        }
        return Future<Object?>.value();
    }
  }

  @override
  /// Removes one exact managed Entry without selecting the active stack.
  Future<CCRouteCloseOutcome> closeNavigation({
    required String navigationId,
    required String hostId,
    required String navigatorOutlet,
    Object? result,
  }) async {
    _ensureAvailable();
    final entry = _entryForNavigation(navigationId);
    if (entry == null ||
        hostId != _host.id ||
        navigatorOutlet != entry.request.placement.navigatorOutlet) {
      return const CCRouteCloseOutcome(CCRouteCloseStatus.notFound);
    }
    final route = _renderedRoutes[entry.backendEntryId]?.target;
    final navigator = route?.navigator;
    if (route != null && route.isActive && navigator != null) {
      _pendingRemovalResults[entry.backendEntryId] = result;
      navigator.removeRoute<Object?>(route, result);
    }
    if (_entryForNavigation(navigationId) != null) {
      _removeEntry(
        entry,
        result: result,
        eventKind: CCNavigationBackendEventKind.remove,
      );
    }
    return const CCRouteCloseOutcome(CCRouteCloseStatus.closed);
  }

  @override
  /// Asks the root Navigator to respect LocalHistory and Route pop disposition.
  Future<bool> maybePop({Object? result}) async =>
      (await maybePopOutcome(result: result)).handled;

  @override
  /// Coordinates one conditional Pop with exact managed or foreign ownership.
  Future<CCPopOutcome> maybePopOutcome({Object? result}) async {
    _ensureAvailable();
    return maybePopOutcomeAt(
      hostId: _host.id,
      navigatorOutlet: _popOutlet,
      result: result,
    );
  }

  @override
  /// Coordinates a conditional Pop in one exact Outlet partition.
  Future<CCPopOutcome> maybePopOutcomeAt({
    required String hostId,
    required String navigatorOutlet,
    Object? result,
  }) async {
    _ensureAvailable();
    if (hostId != _host.id || !_host.containsOutlet(navigatorOutlet)) {
      return const CCPopOutcome(handled: false);
    }
    final outlet = navigatorOutlet;
    final navigator = _host.navigatorKeyFor(outlet).currentState;
    if (navigator == null) return _unhandledPop;
    final top = _observerFor(outlet).topRoute;
    final managed = _entryForRoute(top);
    if (managed != null) {
      _pendingRemovalResults[managed.backendEntryId] = result;
    }
    _runtimeGuardedPopInProgress = true;
    _setManagedPopEntriesCanPop(true);
    late final bool handled;
    try {
      handled = await navigator.maybePop<Object?>(result);
    } finally {
      _setManagedPopEntriesCanPop(false);
      _runtimeGuardedPopInProgress = false;
    }
    if (!handled || (top?.isCurrent ?? false)) {
      if (managed != null) {
        _pendingRemovalResults.remove(managed.backendEntryId);
      }
    }
    if (!handled) return _unhandledPop;
    if (managed != null &&
        _entryForNavigation(managed.request.navigationId) == null) {
      return CCPopOutcome(
        handled: true,
        removedBackendEntryId: managed.backendEntryId,
        removedEntryOwner: CCPopRemovedEntryOwner.managed,
        hostId: _host.id,
        navigatorOutlet: outlet,
      );
    }
    return CCPopOutcome(
      handled: true,
      removedEntryOwner: top == null
          ? CCPopRemovedEntryOwner.none
          : CCPopRemovedEntryOwner.foreign,
      hostId: _host.id,
      navigatorOutlet: outlet,
    );
  }

  @override
  /// Pops the root Navigator synchronously and reports its previous top owner.
  void pop({Object? result}) {
    final outcome = popOutcome(result: result);
    if (!outcome.handled) {
      throw const CCNavigationAdapterError(
        'The managed root Navigator has no removable route.',
      );
    }
  }

  @override
  /// Executes an approved business Pop without re-evaluating Runtime guards.
  CCPopOutcome popOutcome({Object? result}) {
    _ensureAvailable();
    return popOutcomeAt(
      hostId: _host.id,
      navigatorOutlet: _popOutlet,
      result: result,
    );
  }

  @override
  /// Executes an approved business Pop in one exact Outlet partition.
  CCPopOutcome popOutcomeAt({
    required String hostId,
    required String navigatorOutlet,
    Object? result,
  }) {
    _ensureAvailable();
    if (hostId != _host.id || !_host.containsOutlet(navigatorOutlet)) {
      return const CCPopOutcome(handled: false);
    }
    final outlet = navigatorOutlet;
    final navigator = _host.navigatorKeyFor(outlet).currentState;
    if (navigator == null || !navigator.canPop()) return _unhandledPop;
    final top = _observerFor(outlet).topRoute;
    final managed = _entryForRoute(top);
    if (managed != null) {
      _pendingRemovalResults[managed.backendEntryId] = result;
    }
    _runtimeGuardedPopInProgress = true;
    _setManagedPopEntriesCanPop(true);
    try {
      navigator.pop<Object?>(result);
    } finally {
      _setManagedPopEntriesCanPop(false);
      _runtimeGuardedPopInProgress = false;
    }
    final removedManagedRoute = managed != null && !(top?.isCurrent ?? true);
    if (managed != null && !removedManagedRoute) {
      _pendingRemovalResults.remove(managed.backendEntryId);
    }
    return CCPopOutcome(
      handled: true,
      removedBackendEntryId: removedManagedRoute
          ? managed.backendEntryId
          : null,
      removedEntryOwner: managed == null
          ? CCPopRemovedEntryOwner.foreign
          : removedManagedRoute
          ? CCPopRemovedEntryOwner.managed
          : CCPopRemovedEntryOwner.none,
      hostId: _host.id,
      navigatorOutlet: outlet,
    );
  }

  /// Standard unhandled Pop result for this Host root partition.
  CCPopOutcome get _unhandledPop => CCPopOutcome(
    handled: false,
    hostId: _host.id,
    navigatorOutlet: _popOutlet,
  );

  @override
  /// Whether the rendered root Navigator currently accepts a Pop.
  bool canPop() {
    _ensureAvailable();
    return canPopAt(hostId: _host.id, navigatorOutlet: _popOutlet);
  }

  @override
  /// Reports Pop capability for one exact Outlet partition.
  bool canPopAt({required String hostId, required String navigatorOutlet}) {
    _ensureAvailable();
    if (hostId != _host.id || !_host.containsOutlet(navigatorOutlet)) {
      return false;
    }
    return _host.navigatorKeyFor(navigatorOutlet).currentState?.canPop() ??
        false;
  }

  @override
  /// Exact managed Entry targeted by the next root Pop, when rendered.
  CCNavigationPopTarget? get activePopTarget {
    final outlet = _popOutlet;
    final entries = _entriesForOutlet(outlet);
    final entry =
        _entryForRoute(_observerFor(outlet).topRoute) ??
        (entries.isEmpty ? null : entries.last);
    if (entry == null) return null;
    return CCNavigationPopTarget(
      hostId: _host.id,
      navigatorOutlet: outlet,
      backendEntryId: entry.backendEntryId,
    );
  }

  /// Outlet selected for a navigation command without call-site Context.
  String get _popOutlet {
    final focused = _state.focusedOutlet;
    if (_host.navigatorKeyFor(focused).currentState != null) return focused;
    return 'root';
  }

  @override
  /// Adds a Runtime observer and returns an idempotent removal callback.
  void Function() addBackendEventListener(
    CCNavigationBackendEventListener listener,
  ) {
    _backendListeners.add(listener);
    return () => _backendListeners.remove(listener);
  }

  /// Subscribes a Renderer to immutable navigation state changes.
  void _addStateListener(VoidCallback listener) =>
      _stateListeners.add(listener);

  /// Removes a Renderer listener; safe after Adapter disposal.
  void _removeStateListener(VoidCallback listener) =>
      _stateListeners.remove(listener);

  /// Creates declarative Pages for the root Stack and active Shell anchor.
  List<Page<Object?>> _buildRootPages() {
    final layers = <({int order, Page<Object?> page})>[
      for (final entry in _entriesForOutlet('root'))
        (order: entry.order, page: _buildPage(entry)),
    ];
    final shellId = _state.activeShellId;
    final shellOrder = _state.shellAnchorOrder;
    if (shellId != null && shellOrder != null) {
      layers.add((
        order: shellOrder,
        page: _CCManagedShellPage(
          key: ValueKey<String>('ccrouter.managed.shell.$shellId'),
          shellId: shellId,
          adapter: this,
        ),
      ));
    }
    layers.sort((left, right) => left.order.compareTo(right.order));
    if (layers.isEmpty) {
      return const [
        _CCManagedPlaceholderPage(
          key: ValueKey<String>('ccrouter.managed.placeholder'),
        ),
      ];
    }
    return List.unmodifiable(layers.map((layer) => layer.page));
  }

  /// Creates Pages for one named Outlet partition.
  List<Page<Object?>> _buildOutletPages(String outlet) {
    final entries = _entriesForOutlet(outlet);
    if (entries.isEmpty) {
      return [
        _CCManagedPlaceholderPage(
          key: ValueKey<String>('ccrouter.managed.placeholder.$outlet'),
        ),
      ];
    }
    return List.unmodifiable(entries.map(_buildPage));
  }

  /// Returns the immutable bottom-to-top Entries of [outlet].
  List<_CCManagedEntry> _entriesForOutlet(String outlet) => List.unmodifiable(
    _state.entries.where(
      (entry) => entry.request.placement.navigatorOutlet == outlet,
    ),
  );

  /// Builds one generated destination and binds its exact Runtime RouteEntry.
  Page<Object?> _buildPage(_CCManagedEntry entry) {
    final request = entry.request;
    final destination = _catalog.destinationFor(request.routeId)!;
    final payload = CCRouterHostBinding.encodeNavigationPayload(request);
    final child = destination.build(
      CCRouteCodecValues(
        path: _pathParameters(destination.route, request.uri),
        query: request.uri.queryParametersAll,
        extra: CCRouterHostBinding.decodeRouteExtra(payload),
      ),
    );
    final boundChild = CCRouterHostBinding.bindRouteEntry(
      payload: payload,
      child: child,
    );
    final presentation = request.presentation;
    if (_routeRequiresPopGuard(request.routeId) &&
        presentation is CCPagePresentation) {
      return _CCManagedGuardedPage(
        child: boundChild,
        presentation: presentation,
        adapter: this,
        key: entry.pageKey,
        name: request.routeId,
        arguments: request.extra,
        restorationId: entry.backendEntryId,
        predictiveBackHandler: _predictiveBackBridge,
      );
    }
    return CCFlutterRouteFactory.createPage<Object?>(
      child: boundChild,
      presentation: presentation,
      key: entry.pageKey,
      name: request.routeId,
      arguments: request.extra,
      restorationId: entry.backendEntryId,
      predictiveBackHandler: _predictiveBackBridge,
    );
  }

  /// Resolves the Navigator used by one managed Outlet.
  NavigatorState? _navigatorForOutlet(String outlet) =>
      _host.navigatorKeyFor(outlet).currentState;

  /// Resolves a live backend identity from a concrete Flutter Route.
  String? _backendEntryIdForRoute(Route<dynamic> route) {
    for (final entry in _renderedRoutes.entries) {
      if (identical(entry.value.target, route)) return entry.key;
    }
    return null;
  }

  /// Records one sanitized predictive-back fallback without retaining Routes.
  void _recordPredictiveBackFallback(
    CCManagedPredictiveBackFallbackReason reason,
  ) {
    if (_predictiveBackBridge == null) return;
    if (_predictiveBackFallbacks.length >= 100) {
      _predictiveBackFallbacks.removeAt(0);
    }
    _predictiveBackFallbacks.add(
      CCManagedPredictiveBackFallbackEvent(
        reason: reason,
        hostId: _host.id,
        navigatorOutlet: _state.focusedOutlet,
        timestamp: DateTime.now(),
      ),
    );
  }

  /// Extracts named canonical path values already validated by Runtime.
  Map<String, String> _pathParameters(CCNavigationRoute route, Uri uri) {
    final primary = route.patterns.singleWhere((pattern) => pattern.primary);
    final template = switch (primary) {
      CCPathPattern(:final template) => template,
      CCUriPattern(:final template) => Uri.parse(template).path,
      CCRegexPattern() => throw CCNavigationAdapterError(
        'Managed route "${route.routeId}" has no reversible primary pattern.',
      ),
    };
    final templateSegments = Uri.parse(template).pathSegments;
    final actualSegments = uri.pathSegments;
    final values = <String, String>{};
    for (var index = 0; index < templateSegments.length; index++) {
      final segment = templateSegments[index];
      if (segment.startsWith(':') && index < actualSegments.length) {
        values[segment.substring(1)] = actualSegments[index];
      } else if (segment.startsWith('*')) {
        values[segment.substring(1)] = actualSegments.skip(index).join('/');
        break;
      }
    }
    return values;
  }

  /// Adds a result-bearing Entry above the current root Stack.
  Future<Object?> _push(CCNavigationRequest request) {
    final result = Completer<Object?>();
    _results[request.navigationId] = result;
    _append(request);
    return result.future;
  }

  /// Replaces the target Outlet top while preserving the new result channel.
  Future<Object?> _replace(CCNavigationRequest request) {
    final result = Completer<Object?>();
    _results[request.navigationId] = result;
    final partition = _entriesForOutlet(request.placement.navigatorOutlet);
    final previous = partition.isEmpty ? null : partition.last;
    if (previous != null) {
      _removeEntry(
        previous,
        eventKind: CCNavigationBackendEventKind.remove,
        notify: false,
      );
    }
    _append(
      request,
      eventKind: CCNavigationBackendEventKind.replace,
      previousBackendEntryId: previous?.backendEntryId,
    );
    return result.future;
  }

  /// Appends a managed Entry to its exact Outlet partition.
  void _append(
    CCNavigationRequest request, {
    CCNavigationBackendEventKind eventKind = CCNavigationBackendEventKind.push,
    String? previousBackendEntryId,
  }) {
    final entry = _CCManagedEntry(request, order: ++_entrySequence);
    final outlet = request.placement.navigatorOutlet;
    final partition = _entriesForOutlet(outlet);
    final previous = partition.isEmpty ? null : partition.last;
    _commitForNavigation([..._state.entries, entry], entry);
    _emitEntryEvent(
      eventKind,
      entry,
      previousBackendEntryId:
          previousBackendEntryId ?? previous?.backendEntryId,
    );
    _emitTop(entry, previous: previous);
  }

  /// Applies Go to one partition or Reset to every partition of this Host.
  void _replaceAll(CCNavigationRequest request, {required bool resetHost}) {
    final outlet = request.placement.navigatorOutlet;
    final activeShellId = _state.activeShellId;
    final removed = resetHost
        ? _state.entries
        : _state.entries
              .where(
                (entry) =>
                    entry.request.placement.navigatorOutlet == outlet ||
                    (outlet == 'root' &&
                        activeShellId != null &&
                        entry.request.placement.shellId == activeShellId),
              )
              .toList(growable: false);
    final retained = _state.entries
        .where((entry) => !removed.contains(entry))
        .toList(growable: true);
    final entry = _CCManagedEntry(request, order: ++_entrySequence);
    retained.add(entry);
    _commitForNavigation(
      retained,
      entry,
      clearActiveShell: resetHost || outlet == 'root',
    );
    for (final old in removed.reversed) {
      _completeResult(old.request.navigationId, null);
      _renderedRoutes.remove(old.backendEntryId);
      _emitEntryEvent(CCNavigationBackendEventKind.remove, old);
    }
    _emitEntryEvent(
      removed.isEmpty
          ? CCNavigationBackendEventKind.push
          : CCNavigationBackendEventKind.replace,
      entry,
      previousBackendEntryId: removed.isEmpty
          ? null
          : removed.last.backendEntryId,
    );
    _emitTop(entry, previous: removed.isEmpty ? null : removed.last);
  }

  /// Removes [entry], completes its channel once, and reveals its partition top.
  void _removeEntry(
    _CCManagedEntry entry, {
    Object? result,
    required CCNavigationBackendEventKind eventKind,
    bool notify = true,
  }) {
    if (!_state.entries.contains(entry)) return;
    final partition = _entriesForOutlet(
      entry.request.placement.navigatorOutlet,
    );
    final wasTop = partition.isNotEmpty && identical(partition.last, entry);
    final next = [..._state.entries]..remove(entry);
    final shellId = entry.request.placement.shellId;
    final shellStillHasEntries =
        shellId != null &&
        next.any((candidate) => candidate.request.placement.shellId == shellId);
    _state = _copyState(
      entries: next,
      clearActiveShell:
          shellId != null &&
          _state.activeShellId == shellId &&
          !shellStillHasEntries,
    );
    _renderedRoutes.remove(entry.backendEntryId);
    _pendingRemovalResults.remove(entry.backendEntryId);
    _completeResult(entry.request.navigationId, result);
    _emitEntryEvent(eventKind, entry);
    final nextPartition = _entriesForOutlet(
      entry.request.placement.navigatorOutlet,
    );
    if (wasTop && nextPartition.isNotEmpty) {
      _emitTop(nextPartition.last, previous: entry);
    }
    if (notify) _notifyStateListeners();
  }

  /// Commits one navigation transaction and updates structural Shell state.
  void _commitForNavigation(
    List<_CCManagedEntry> entries,
    _CCManagedEntry entry, {
    bool clearActiveShell = false,
  }) {
    final placement = entry.request.placement;
    final shellId = placement.shellId;
    var activeShellId = clearActiveShell ? null : _state.activeShellId;
    var shellAnchorOrder = clearActiveShell ? null : _state.shellAnchorOrder;
    final activeOutlets = {..._state.activeOutletsByShell};
    var visibleOutlets = {..._state.visibleOutlets};
    if (shellId != null) {
      if (activeShellId != shellId) shellAnchorOrder = entry.order;
      activeShellId = shellId;
      activeOutlets[shellId] = placement.navigatorOutlet;
      visibleOutlets = {placement.navigatorOutlet};
    } else if (placement.navigatorOutlet == 'root') {
      visibleOutlets = {'root'};
    } else {
      visibleOutlets.add(placement.navigatorOutlet);
    }
    _state = _CCManagedNavigationState(
      revision: _state.revision + 1,
      entries: entries,
      activeShellId: activeShellId,
      shellAnchorOrder: shellAnchorOrder,
      focusedOutlet: placement.navigatorOutlet,
      visibleOutlets: visibleOutlets,
      activeOutletsByShell: activeOutlets,
    );
    _notifyStateListeners();
  }

  /// Copies Store state while optionally clearing its active Shell anchor.
  _CCManagedNavigationState _copyState({
    required List<_CCManagedEntry> entries,
    bool clearActiveShell = false,
    String? focusedOutlet,
    Set<String>? visibleOutlets,
    Map<String, String>? activeOutletsByShell,
  }) => _CCManagedNavigationState(
    revision: _state.revision + 1,
    entries: entries,
    activeShellId: clearActiveShell ? null : _state.activeShellId,
    shellAnchorOrder: clearActiveShell ? null : _state.shellAnchorOrder,
    focusedOutlet: focusedOutlet ?? _state.focusedOutlet,
    visibleOutlets: visibleOutlets ?? _state.visibleOutlets,
    activeOutletsByShell: activeOutletsByShell ?? _state.activeOutletsByShell,
  );

  /// Notifies a stable copy so listeners may detach during callbacks.
  void _notifyStateListeners() {
    for (final listener in _stateListeners.toList()) {
      listener();
    }
  }

  /// Returns the stable observer owned by one registered Outlet.
  _CCManagedNavigatorObserver _observerFor(String outlet) => _observers
      .putIfAbsent(outlet, () => _CCManagedNavigatorObserver(this, outlet));

  /// Selects [outlet] for context-free Back without changing Shell activation.
  void _focusOutlet(String outlet) {
    if (_disposed || _state.focusedOutlet == outlet) return;
    if (!_host.containsOutlet(outlet)) return;
    _state = _copyState(entries: _state.entries, focusedOutlet: outlet);
    _predictiveBackBridge?.invalidateInactiveOutlets();
    _notifyStateListeners();
  }

  /// Activates one stateful Shell branch while preserving every branch Stack.
  void _activateOutlet(String shellId, String outlet) {
    _ensureAvailable();
    final shell = _shells[shellId];
    if (shell == null ||
        shell.type != CCShellType.statefulBranches ||
        !shell.outlets.contains(outlet)) {
      throw CCNavigationAdapterError(
        'Managed Shell "$shellId" cannot activate Outlet "$outlet".',
      );
    }
    final activeOutlets = {..._state.activeOutletsByShell, shellId: outlet};
    _state = _copyState(
      entries: _state.entries,
      focusedOutlet: outlet,
      visibleOutlets: {outlet},
      activeOutletsByShell: activeOutlets,
    );
    _predictiveBackBridge?.invalidateInactiveOutlets();
    _notifyStateListeners();
    final entries = _entriesForOutlet(outlet);
    final top = entries.isEmpty ? null : entries.last;
    _emit(
      CCNavigationBackendEvent(
        kind: CCNavigationBackendEventKind.outletActivated,
        timestamp: DateTime.now(),
        backendEntryId: top?.backendEntryId,
        backendOperationId: 'managed-${_host.id}-${++_eventSequence}',
        hostId: _host.id,
        navigatorOutlet: outlet,
        sequence: _eventSequence,
        owner: top == null ? null : CCBackendEntryOwner.managed,
        navigationId: top?.request.navigationId,
        routeId: top?.request.routeId,
        placement:
            top?.request.placement ??
            CCRoutePlacement(
              hostId: _host.id,
              shellId: shellId,
              navigatorOutlet: outlet,
            ),
        activeNavigatorOutlets: [outlet],
      ),
    );
  }

  /// Handles a Page-driven Pop or gesture after Flutter accepted it.
  void _didRemovePage(Page<Object?> page) {
    final entry = _entryForPageKey(page.key);
    if (entry == null) return;
    _removeEntry(
      entry,
      result: _pendingRemovalResults.remove(entry.backendEntryId),
      eventKind: CCNavigationBackendEventKind.pop,
    );
  }

  /// Applies one Navigator-confirmed Pop before its Route correlation is lost.
  void _didPopRoute(Route<dynamic> route) {
    final entry = _entryForRoute(route);
    if (entry == null) return;
    _removeEntry(
      entry,
      result: _pendingRemovalResults.remove(entry.backendEntryId),
      eventKind: CCNavigationBackendEventKind.pop,
    );
  }

  /// Retains a weak correlation while [route] belongs to a managed Page.
  void _didMountRoute(Route<dynamic> route) {
    final entry = _entryForPageKey(
      route.settings is Page ? (route.settings as Page<dynamic>).key : null,
    );
    if (entry != null) {
      _renderedRoutes[entry.backendEntryId] = WeakReference(route);
      if (_routeRequiresPopGuard(entry.request.routeId)) {
        _installManagedPopGuard(route);
      }
    }
  }

  /// Drops a rendered correlation without mutating Store ownership.
  void _didUnmountRoute(Route<dynamic> route) {
    _removeManagedPopGuard(route);
    final entry = _entryForRoute(route);
    if (entry != null) _renderedRoutes.remove(entry.backendEntryId);
  }

  /// Whether Runtime metadata marks [routeId] as requiring Pop policy.
  bool _routeRequiresPopGuard(String routeId) =>
      _routes[routeId]?.hasPopGuard ?? false;

  /// Temporarily opens or closes every guarded Route for an approved Pop.
  void _setManagedPopEntriesCanPop(bool value) {
    for (final entry in _managedPopGuardEntries.values) {
      entry.canPopNotifier.value = value;
    }
  }

  /// Opens one guarded Route only when gesture-time Runtime policy allows it.
  bool _prepareManagedPopGesture(Route<dynamic> route) {
    final evaluator = _popGuardEvaluator;
    final modalRoute = route is ModalRoute<Object?> ? route : null;
    final entry = modalRoute == null
        ? null
        : _managedPopGuardEntries[modalRoute];
    if (_disposed ||
        evaluator == null ||
        modalRoute == null ||
        entry == null ||
        !modalRoute.isCurrent) {
      return false;
    }
    if (entry.canPopNotifier.value) return true;
    final decision = evaluator(CCPopTrigger.gesture);
    if (decision is! CCPopAllow ||
        _disposed ||
        !modalRoute.isCurrent ||
        !identical(_managedPopGuardEntries[modalRoute], entry)) {
      return false;
    }
    entry.canPopNotifier.value = true;
    _scheduleManagedPopGestureGateClose(modalRoute, entry);
    return true;
  }

  /// Closes a prepared gate when no interactive gesture retained ownership.
  void _scheduleManagedPopGestureGateClose(
    ModalRoute<Object?> route,
    _CCManagedPopEntry entry,
  ) {
    final binding = WidgetsBinding.instance;
    binding.addPostFrameCallback((_) {
      if (_disposed || route.navigator?.userGestureInProgress == true) return;
      if (identical(_managedPopGuardEntries[route], entry)) {
        entry.canPopNotifier.value = false;
      }
    });
    // Eligibility can be queried between frames. Schedule the cleanup frame so
    // a declined recognizer start cannot leave this temporary gate open.
    binding.scheduleFrame();
  }

  /// Restores the conservative gate after an iOS gesture cancels or finishes.
  void _didStopUserGesture(Route<dynamic>? route) {
    final modalRoute = route is ModalRoute<Object?> ? route : null;
    final entry = modalRoute == null
        ? null
        : _managedPopGuardEntries[modalRoute];
    if (entry != null) entry.canPopNotifier.value = false;
  }

  /// Installs a conservative system-back gate after Route correlation.
  ///
  /// Generated default iOS Routes evaluate Runtime policy synchronously from
  /// their gesture eligibility hook. Other presentation families keep this
  /// gate closed; a rejected system back reaches the PopEntry callback, which
  /// evaluates policy and retries only the same current Route when allowed.
  void _installManagedPopGuard(Route<dynamic> route) {
    if (_popGuardEvaluator == null || route is! ModalRoute<Object?>) return;
    if (_managedPopGuardEntries.containsKey(route) ||
        _pendingManagedPopGuardRoutes.contains(route)) {
      return;
    }
    _pendingManagedPopGuardRoutes.add(route);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pendingManagedPopGuardRoutes.remove(route);
      if (_disposed || _popGuardEvaluator == null || !route.isActive) return;
      _attachManagedPopGuard(route);
    });
  }

  /// Registers one closed PopEntry after the Route's ModalScope is mounted.
  void _attachManagedPopGuard(ModalRoute<Object?> route) {
    if (_popGuardEvaluator == null ||
        _managedPopGuardEntries.containsKey(route)) {
      return;
    }
    late final _CCManagedPopEntry entry;
    entry = _CCManagedPopEntry(
      onInvoked: (didPop, result) {
        if (didPop || _runtimeGuardedPopInProgress || entry.retrying) return;
        _retryManagedSystemPop(route, entry, result);
      },
    );
    route.registerPopEntry(entry);
    _managedPopGuardEntries[route] = entry;
  }

  /// Retries the same guarded Route after synchronous Runtime approval.
  void _retryManagedSystemPop(
    ModalRoute<Object?> route,
    _CCManagedPopEntry entry,
    Object? result,
  ) {
    final evaluator = _popGuardEvaluator;
    final navigator = route.navigator;
    if (_disposed ||
        evaluator == null ||
        navigator == null ||
        !route.isCurrent) {
      return;
    }
    entry.retrying = true;
    try {
      final decision = evaluator(CCPopTrigger.system);
      if (decision is! CCPopAllow ||
          _disposed ||
          !route.isCurrent ||
          !identical(route.navigator, navigator) ||
          !identical(_managedPopGuardEntries[route], entry)) {
        return;
      }
      entry.canPopNotifier.value = true;
      if (route.popDisposition != RoutePopDisposition.pop) return;
      navigator.pop<Object?>(result);
    } finally {
      entry.retrying = false;
      if (identical(_managedPopGuardEntries[route], entry)) {
        entry.canPopNotifier.value = false;
      }
    }
  }

  /// Removes one Route-scoped gate after Flutter releases the Route.
  void _removeManagedPopGuard(Route<dynamic> route) {
    _pendingManagedPopGuardRoutes.remove(route);
    final modalRoute = route is ModalRoute<Object?> ? route : null;
    if (modalRoute == null) return;
    final entry = _managedPopGuardEntries.remove(modalRoute);
    if (entry == null) return;
    if (modalRoute.isActive) modalRoute.unregisterPopEntry(entry);
    entry.dispose();
  }

  /// Releases every pending and registered Route gate during unbinding.
  void _removeAllManagedPopGuards() {
    _pendingManagedPopGuardRoutes.clear();
    final entries = _managedPopGuardEntries.entries.toList();
    _managedPopGuardEntries.clear();
    for (final entry in entries) {
      if (entry.key.isActive) entry.key.unregisterPopEntry(entry.value);
      entry.value.dispose();
    }
  }

  /// Returns the managed Entry rendered by [route], if any.
  _CCManagedEntry? _entryForRoute(Route<dynamic>? route) {
    if (route == null || route.settings is! Page) return null;
    return _entryForPageKey((route.settings as Page<dynamic>).key);
  }

  /// Returns the Entry with an exact stable Page key.
  _CCManagedEntry? _entryForPageKey(LocalKey? key) {
    if (key == null) return null;
    for (final entry in _state.entries) {
      if (entry.pageKey == key) return entry;
    }
    return null;
  }

  /// Returns the Entry with one Runtime navigation identity.
  _CCManagedEntry? _entryForNavigation(String navigationId) {
    for (final entry in _state.entries) {
      if (entry.request.navigationId == navigationId) return entry;
    }
    return null;
  }

  /// Completes and releases one optional typed result channel exactly once.
  void _completeResult(String navigationId, Object? result) {
    final completer = _results.remove(navigationId);
    if (completer != null && !completer.isCompleted) completer.complete(result);
  }

  /// Emits one raw event while isolating observational listener failures.
  void _emitEntryEvent(
    CCNavigationBackendEventKind kind,
    _CCManagedEntry entry, {
    String? previousBackendEntryId,
  }) {
    final request = entry.request;
    _emit(
      CCNavigationBackendEvent(
        kind: kind,
        timestamp: DateTime.now(),
        backendEntryId: entry.backendEntryId,
        backendOperationId: 'managed-${_host.id}-${++_eventSequence}',
        previousBackendEntryId: previousBackendEntryId,
        hostId: _host.id,
        navigatorOutlet: request.placement.navigatorOutlet,
        sequence: _eventSequence,
        owner: CCBackendEntryOwner.managed,
        navigationId: request.navigationId,
        routeId: request.routeId,
        uri: request.uri,
        placement: request.placement,
        location: request.uri.toString(),
        origin: request.origin,
        source: request.source,
      ),
    );
  }

  /// Emits a confirmed current Entry after a Store transaction.
  void _emitTop(_CCManagedEntry entry, {_CCManagedEntry? previous}) {
    final request = entry.request;
    _emit(
      CCNavigationBackendEvent(
        kind: CCNavigationBackendEventKind.topChanged,
        timestamp: DateTime.now(),
        backendEntryId: entry.backendEntryId,
        backendOperationId: 'managed-${_host.id}-${++_eventSequence}',
        previousBackendEntryId: previous?.backendEntryId,
        hostId: _host.id,
        navigatorOutlet: request.placement.navigatorOutlet,
        sequence: _eventSequence,
        owner: CCBackendEntryOwner.managed,
        navigationId: request.navigationId,
        routeId: request.routeId,
        uri: request.uri,
        placement: request.placement,
        location: request.uri.toString(),
        origin: request.origin,
        source: request.source,
      ),
    );
  }

  /// Delivers [event] after Runtime commits the request identity.
  ///
  /// `CCNavigationAdapter.navigate` mutates the Store synchronously, while
  /// Runtime records its RouteEntry immediately after that method returns. A
  /// microtask keeps backend observation ordered behind that commit so the
  /// ledger never misclassifies a managed Page as foreign.
  void _emit(CCNavigationBackendEvent event) {
    scheduleMicrotask(() {
      if (_disposed) return;
      _predictiveBackBridge?.observeBackendEvent(event);
      for (final listener in _backendListeners.toList()) {
        try {
          listener(event);
        } catch (_) {
          // Observers cannot change navigation transaction success.
        }
      }
    });
  }

  /// Rejects unknown route, Host, or Outlet requests before mutation.
  void _ensureRequest(CCNavigationRequest request) {
    if (!_routes.containsKey(request.routeId)) {
      throw CCNavigationAdapterError(
        'Route "${request.routeId}" was not supplied to the managed Adapter.',
      );
    }
    final placement = request.placement;
    final shellId = placement.shellId;
    if (request.hostId != _host.id ||
        !_host.containsOutlet(placement.navigatorOutlet) ||
        (shellId != null &&
            (!_shells.containsKey(shellId) ||
                !_shells[shellId]!.outlets.contains(
                  placement.navigatorOutlet,
                )))) {
      throw CCNavigationAdapterError(
        'Navigation "${request.navigationId}" does not target the managed '
        'Host or a configured Outlet partition.',
      );
    }
  }

  /// Rejects work before initialization or after permanent disposal.
  void _ensureAvailable() {
    if (!_initialized || _disposed) {
      throw const CCNavigationAdapterError(
        'The managed navigation Adapter is not active.',
      );
    }
  }

  /// Rejects initialization work after disposal.
  void _ensureNotDisposed() {
    if (_disposed) {
      throw const CCNavigationAdapterError(
        'The managed navigation Adapter has been disposed.',
      );
    }
  }

  @override
  /// Fails pending results, releases listeners, and clears all retained state.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _initialized = false;
    final error = const CCNavigationAdapterError(
      'Managed navigation ended before the route result completed.',
    );
    final stackTrace = StackTrace.current;
    for (final completer in _results.values) {
      if (!completer.isCompleted) completer.completeError(error, stackTrace);
    }
    _results.clear();
    _routes.clear();
    _popGuardEvaluator = null;
    _removeAllManagedPopGuards();
    _renderedRoutes.clear();
    _pendingRemovalResults.clear();
    for (final observer in _observers.values) {
      observer.clear();
    }
    _observers.clear();
    _shells.clear();
    _state = const _CCManagedNavigationState.empty();
    _notifyStateListeners();
    _stateListeners.clear();
    _backendListeners.clear();
    _predictiveBackBridge?.dispose();
    _predictiveBackFallbacks.clear();
  }
}

/// Immutable root stack snapshot committed by one Adapter transaction.
final class _CCManagedNavigationState {
  /// Creates one snapshot with a monotonic [revision].
  _CCManagedNavigationState({
    required this.revision,
    required List<_CCManagedEntry> entries,
    required this.activeShellId,
    required this.shellAnchorOrder,
    required this.focusedOutlet,
    required Set<String> visibleOutlets,
    required Map<String, String> activeOutletsByShell,
  }) : entries = List.unmodifiable(entries),
       visibleOutlets = Set.unmodifiable(visibleOutlets),
       activeOutletsByShell = Map.unmodifiable(activeOutletsByShell);

  /// Creates the unattached empty state.
  const _CCManagedNavigationState.empty()
    : revision = 0,
      entries = const [],
      activeShellId = null,
      shellAnchorOrder = null,
      focusedOutlet = 'root',
      visibleOutlets = const {'root'},
      activeOutletsByShell = const {};

  /// Monotonic version incremented for every committed mutation.
  final int revision;

  /// Managed root Entries in bottom-to-top order.
  final List<_CCManagedEntry> entries;

  /// Shell currently mounted as one structural root Page.
  final String? activeShellId;

  /// Global order used to place the active Shell among root overlays.
  final int? shellAnchorOrder;

  /// Outlet selected for operations that have no call-site Context.
  final String focusedOutlet;

  /// Simultaneously visible Outlets reported by the current Host layout.
  final Set<String> visibleOutlets;

  /// Foreground branch retained independently for every stateful Shell.
  final Map<String, String> activeOutletsByShell;
}

/// Immutable managed Stack entry with stable Flutter and backend identities.
final class _CCManagedEntry {
  /// Creates one Entry from a Runtime-validated [request].
  _CCManagedEntry(this.request, {required this.order})
    : backendEntryId = 'managed-${request.navigationId}',
      pageKey = ValueKey<String>('ccrouter.managed.${request.navigationId}');

  /// Monotonic Host-local structural order.
  final int order;

  /// Runtime request and typed arguments owned for this Entry lifetime.
  final CCNavigationRequest request;

  /// Stable identity exposed through backend events and Pop outcomes.
  final String backendEntryId;

  /// Stable declarative Page identity used by Navigator reconciliation.
  final ValueKey<String> pageKey;
}

/// Route configuration exchanged between Flutter Router and CCRouter Runtime.
final class CCManagedRouteConfiguration {
  /// Creates one parsed location with its trust classification.
  const CCManagedRouteConfiguration({
    required this.uri,
    required this.trustedHistory,
  });

  /// Location entering Runtime matching and Codec validation.
  final Uri uri;

  /// Whether this location was emitted by the current backend session.
  final bool trustedHistory;
}

/// Parses platform route information without performing business matching.
final class _CCManagedRouteInformationParser
    extends RouteInformationParser<CCManagedRouteConfiguration> {
  /// Creates a parser recognizing browser history from [sessionId].
  const _CCManagedRouteInformationParser({required this.sessionId});

  /// Process-local marker preventing external locations from gaining trust.
  final String sessionId;

  @override
  /// Preserves the URI and validates only the opaque history marker.
  Future<CCManagedRouteConfiguration> parseRouteInformation(
    RouteInformation routeInformation,
  ) => SynchronousFuture(
    CCManagedRouteConfiguration(
      uri: routeInformation.uri,
      trustedHistory:
          routeInformation.state is Map<String, Object?> &&
          (routeInformation.state as Map<String, Object?>)['ccrouterSession'] ==
              sessionId,
    ),
  );

  @override
  /// Projects the current managed URI with non-sensitive session metadata.
  RouteInformation? restoreRouteInformation(
    CCManagedRouteConfiguration configuration,
  ) => RouteInformation(
    uri: configuration.uri,
    state: <String, Object?>{'ccrouterSession': sessionId},
  );
}

/// RouterDelegate that renders the Adapter Store through `Navigator.pages`.
final class _CCManagedRouterDelegate
    extends RouterDelegate<CCManagedRouteConfiguration>
    with ChangeNotifier {
  /// Binds one delegate to [adapter] for its complete lifecycle.
  _CCManagedRouterDelegate(
    this.adapter, {
    required this.initialLocationIsExternal,
    required this.initializeFromRouteInformation,
  }) {
    adapter._addStateListener(_onStateChanged);
  }

  /// Store and Runtime Adapter whose state this delegate renders.
  final CCManagedNavigationAdapter adapter;

  /// Whether initial Router configuration must pass external ingress policy.
  final bool initialLocationIsExternal;

  /// Whether this child Router admits its platform initial location.
  final bool initializeFromRouteInformation;

  /// Whether this delegate already released its Store listener.
  bool _disposed = false;

  /// Root Navigator identity shared with Host context resolution.
  GlobalKey<NavigatorState> get navigatorKey => adapter._host.navigatorKey;

  @override
  /// Current URL projection, or null while initial navigation is unresolved.
  CCManagedRouteConfiguration? get currentConfiguration {
    final uri = adapter._currentUri;
    if (uri == null) return null;
    return CCManagedRouteConfiguration(uri: uri, trustedHistory: true);
  }

  @override
  /// Admits initial Host or platform location through Runtime policy.
  Future<void> setInitialRoutePath(
    CCManagedRouteConfiguration configuration,
  ) async {
    if (!initializeFromRouteInformation) return;
    await CCRouterHostBinding.openRouteInformation(
      configuration.uri,
      external: initialLocationIsExternal,
      placementOverride: CCRoutePlacement(hostId: adapter.hostId),
    );
  }

  @override
  /// Applies browser and platform locations through one Runtime Go transaction.
  Future<void> setNewRoutePath(
    CCManagedRouteConfiguration configuration,
  ) async {
    if (adapter._currentUri == configuration.uri &&
        adapter.requests.isNotEmpty) {
      return;
    }
    await CCRouterHostBinding.openRouteInformation(
      configuration.uri,
      external: !configuration.trustedHistory,
      placementOverride: CCRoutePlacement(hostId: adapter.hostId),
    );
  }

  @override
  /// Routes system Back through Runtime PopGuard and ownership coordination.
  Future<bool> popRoute() async => (await CCRouter.navigator.maybePopOutcome(
    trigger: CCPopTrigger.system,
  )).handled;

  @override
  /// Builds one declarative root Navigator from the latest immutable state.
  Widget build(BuildContext context) => Navigator(
    key: navigatorKey,
    pages: adapter._buildRootPages(),
    observers: adapter._rootObservers,
    onDidRemovePage: adapter._didRemovePage,
  );

  /// Rebuilds Router and reports a possible URL projection change.
  void _onStateChanged() {
    if (!_disposed) notifyListeners();
  }

  @override
  /// Detaches from Adapter state before releasing ChangeNotifier listeners.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    adapter._removeStateListener(_onStateChanged);
    super.dispose();
  }
}

/// Structural Page that mounts one application-owned managed Shell.
final class _CCManagedShellPage extends Page<Object?> {
  /// Creates a stable anchor for [shellId].
  const _CCManagedShellPage({
    required this.shellId,
    required this.adapter,
    super.key,
  });

  /// Shell rendered by this structural layer.
  final String shellId;

  /// Store supplying the Shell's Outlet Navigators.
  final CCManagedNavigationAdapter adapter;

  @override
  /// Creates a normal full-screen structural Route.
  Route<Object?> createRoute(BuildContext context) => PageRouteBuilder<Object?>(
    settings: this,
    pageBuilder: (_, _, _) =>
        _CCManagedShellSurface(adapter: adapter, shellId: shellId),
  );
}

/// Reactive Shell renderer retained by the structural Route.
final class _CCManagedShellSurface extends StatefulWidget {
  /// Creates a surface bound to one Store and Shell.
  const _CCManagedShellSurface({required this.adapter, required this.shellId});

  /// Store whose revision drives child Navigator Pages.
  final CCManagedNavigationAdapter adapter;

  /// Shell contract and Host binding identity.
  final String shellId;

  @override
  /// Creates the Store listener for this structural Route.
  State<_CCManagedShellSurface> createState() => _CCManagedShellSurfaceState();
}

/// Rebuilds a Shell when any of its retained Outlet stacks changes.
final class _CCManagedShellSurfaceState extends State<_CCManagedShellSurface> {
  @override
  /// Subscribes after the State is ready to rebuild.
  void initState() {
    super.initState();
    widget.adapter._addStateListener(_onStateChanged);
  }

  @override
  /// Moves the listener if a structural Route receives another Store instance.
  void didUpdateWidget(covariant _CCManagedShellSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.adapter, widget.adapter)) {
      oldWidget.adapter._removeStateListener(_onStateChanged);
      widget.adapter._addStateListener(_onStateChanged);
    }
  }

  /// Rebuilds only while this structural surface remains mounted.
  void _onStateChanged() {
    if (mounted) setState(() {});
  }

  @override
  /// Releases the Store callback before this Route leaves the tree.
  void dispose() {
    widget.adapter._removeStateListener(_onStateChanged);
    super.dispose();
  }

  @override
  /// Invokes the application binding with managed Outlet Navigators.
  Widget build(BuildContext context) {
    final shell = widget.adapter._shells[widget.shellId]!;
    final binding = widget.adapter._shellBindings[widget.shellId]!;
    final activeOutlet =
        widget.adapter._state.activeOutletsByShell[widget.shellId] ??
        shell.initialOutlet;
    final navigators = <String, Widget>{
      for (final outlet in shell.outlets)
        outlet: _CCManagedOutletNavigator(
          adapter: widget.adapter,
          outlet: outlet,
        ),
    };
    return binding.builder(
      context,
      CCManagedShellScope._(
        shellId: shell.shellId,
        type: shell.type,
        outlets: shell.outlets,
        activeOutlet: activeOutlet,
        navigators: Map.unmodifiable(navigators),
        activateOutlet: (outlet) =>
            widget.adapter._activateOutlet(shell.shellId, outlet),
      ),
    );
  }
}

/// State listener backing the public adaptive Outlet renderer.
final class _CCManagedOutletState extends State<CCManagedOutlet> {
  @override
  /// Validates and subscribes to the backend Store.
  void initState() {
    super.initState();
    _validateOutlet();
    widget.backend.adapter._addStateListener(_onStateChanged);
  }

  @override
  /// Transfers the listener when Host composition replaces the backend.
  void didUpdateWidget(covariant CCManagedOutlet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.backend, widget.backend)) {
      oldWidget.backend.adapter._removeStateListener(_onStateChanged);
      _validateOutlet();
      widget.backend.adapter._addStateListener(_onStateChanged);
    } else if (oldWidget.outlet != widget.outlet) {
      _validateOutlet();
    }
  }

  /// Rejects unknown and root Outlet composition mistakes.
  void _validateOutlet() {
    if (widget.outlet == 'root' ||
        !widget.backend.host.containsOutlet(widget.outlet)) {
      throw FlutterError(
        'CCManagedOutlet requires a registered non-root Outlet on its Backend.',
      );
    }
  }

  /// Rebuilds declarative Pages after one Store revision.
  void _onStateChanged() {
    if (mounted) setState(() {});
  }

  @override
  /// Detaches the Store listener deterministically.
  void dispose() {
    widget.backend.adapter._removeStateListener(_onStateChanged);
    super.dispose();
  }

  @override
  /// Renders the exact named Outlet Navigator.
  Widget build(BuildContext context) => _CCManagedOutletNavigator(
    adapter: widget.backend.adapter,
    outlet: widget.outlet,
  );
}

/// Builds one Navigator while keeping focus separate from route placement.
final class _CCManagedOutletNavigator extends StatelessWidget {
  /// Creates a renderer for one exact [outlet].
  const _CCManagedOutletNavigator({
    required this.adapter,
    required this.outlet,
  });

  /// Store projected by the child Navigator.
  final CCManagedNavigationAdapter adapter;

  /// Host-registered Outlet identity.
  final String outlet;

  @override
  /// Wraps interaction only to select context-free Back fallback.
  Widget build(BuildContext context) => Focus(
    onFocusChange: (focused) {
      if (focused) adapter._focusOutlet(outlet);
    },
    child: Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => adapter._focusOutlet(outlet),
      child: HeroControllerScope.none(
        child: Navigator(
          key: adapter._host.navigatorKeyFor(outlet),
          pages: adapter._buildOutletPages(outlet),
          observers: [adapter._observerFor(outlet)],
          onDidRemovePage: adapter._didRemovePage,
        ),
      ),
    ),
  );
}

/// Internal page displayed only while the first Runtime location is unresolved.
final class _CCManagedPlaceholderPage extends Page<Object?> {
  /// Creates the stable non-business placeholder Page.
  const _CCManagedPlaceholderPage({super.key});

  @override
  /// Creates a zero-duration Route with no managed Entry or payload.
  Route<Object?> createRoute(BuildContext context) => PageRouteBuilder<Object?>(
    settings: this,
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    pageBuilder: (_, _, _) => const SizedBox.shrink(),
  );
}

/// Managed Page that evaluates PopGuard immediately before an iOS edge swipe.
///
/// Android and non-interactive presentation paths continue through the shared
/// route factory so predictive-back and custom-transition behavior is unchanged.
final class _CCManagedGuardedPage extends CCFlutterPage<Object?> {
  /// Creates one guarded Page with Adapter-owned gesture coordination.
  const _CCManagedGuardedPage({
    required super.child,
    required super.presentation,
    required this.adapter,
    super.key,
    super.name,
    super.arguments,
    super.restorationId,
    super.predictiveBackHandler,
  });

  /// Adapter that owns the corresponding managed Entry and PopEntry gate.
  final CCManagedNavigationAdapter adapter;

  @override
  /// Creates an iOS-aware guarded Route or preserves the shared fallback.
  Route<Object?> createRoute(BuildContext context) {
    final value = presentation;
    final useCupertino = switch (value.routeType) {
      CCPageRouteType.cupertino => true,
      CCPageRouteType.material => false,
      CCPageRouteType.platformDefault => _usesCupertinoRouteFamily(context),
    };
    final usesInteractiveIosTransition =
        useCupertino || Theme.of(context).platform == TargetPlatform.iOS;
    if (value.transition != CCPageTransitionType.platformDefault ||
        !value.opaque ||
        !usesInteractiveIosTransition) {
      return super.createRoute(context);
    }
    if (useCupertino) {
      return _CCManagedGuardedCupertinoPageRoute<Object?>(
        settings: this,
        fullscreenDialog: value.fullscreenDialog,
        builder: (_) => child,
        preparePopGesture: adapter._prepareManagedPopGesture,
      );
    }
    return _CCManagedGuardedMaterialPageRoute<Object?>(
      settings: this,
      fullscreenDialog: value.fullscreenDialog,
      builder: (_) => child,
      preparePopGesture: adapter._prepareManagedPopGesture,
    );
  }

  /// Resolves Material versus Cupertino Host ownership without Theme ambiguity.
  static bool _usesCupertinoRouteFamily(BuildContext context) {
    bool? useCupertino;
    context.visitAncestorElements((element) {
      final widget = element.widget;
      if (widget is MaterialApp) {
        useCupertino = false;
        return false;
      }
      if (widget is CupertinoApp) {
        useCupertino = true;
        return false;
      }
      return true;
    });
    return useCupertino ??
        context.dependOnInheritedWidgetOfExactType<InheritedCupertinoTheme>() !=
            null;
  }
}

/// Material Route that opens its PopEntry only for an allowed edge swipe.
final class _CCManagedGuardedMaterialPageRoute<T> extends MaterialPageRoute<T> {
  /// Creates a Material route coordinated by [preparePopGesture].
  _CCManagedGuardedMaterialPageRoute({
    required super.builder,
    required this.preparePopGesture,
    super.settings,
    super.fullscreenDialog,
  });

  /// Synchronously evaluates and prepares the managed gesture gate.
  final bool Function(Route<dynamic> route) preparePopGesture;

  @override
  /// Allows Flutter to start only after Runtime policy opens the PopEntry.
  bool get popGestureEnabled =>
      preparePopGesture(this) && super.popGestureEnabled;
}

/// Cupertino Route that opens its PopEntry only for an allowed edge swipe.
final class _CCManagedGuardedCupertinoPageRoute<T>
    extends CupertinoPageRoute<T> {
  /// Creates a Cupertino route coordinated by [preparePopGesture].
  _CCManagedGuardedCupertinoPageRoute({
    required super.builder,
    required this.preparePopGesture,
    super.settings,
    super.fullscreenDialog,
  });

  /// Synchronously evaluates and prepares the managed gesture gate.
  final bool Function(Route<dynamic> route) preparePopGesture;

  @override
  /// Allows Flutter to start only after Runtime policy opens the PopEntry.
  bool get popGestureEnabled =>
      preparePopGesture(this) && super.popGestureEnabled;
}

/// Adapter-owned PopEntry bridging synchronous Runtime policy to Flutter.
///
/// The entry remains closed outside an approved Pop so guarded Routes cannot
/// begin an interactive gesture that would bypass Runtime policy.
final class _CCManagedPopEntry extends PopEntry<Object?> {
  /// Creates a closed gate with one result-aware attempt callback.
  _CCManagedPopEntry({required this.onInvoked})
    : canPopNotifier = ValueNotifier<bool>(false);

  /// Callback invoked after Flutter accepts or rejects a Pop attempt.
  final void Function(bool didPop, Object? result) onInvoked;

  /// Prevents an approved retry from recursively evaluating the same guard.
  bool retrying = false;

  /// Mutable gate consumed by [ModalRoute.popDisposition].
  @override
  final ValueNotifier<bool> canPopNotifier;

  @override
  /// Forwards Flutter's result-aware notification to the Adapter.
  void onPopInvokedWithResult(bool didPop, Object? result) {
    onInvoked(didPop, result);
  }

  /// Releases the notifier after unregistering this PopEntry.
  void dispose() => canPopNotifier.dispose();
}

/// Navigator observer retaining only live Route topology and weak correlations.
final class _CCManagedNavigatorObserver extends NavigatorObserver {
  /// Creates an observer owned by [adapter].
  _CCManagedNavigatorObserver(this.adapter, this.outlet);

  /// Adapter receiving live Route mount and unmount callbacks.
  final CCManagedNavigationAdapter adapter;

  /// Stable Outlet rendered by the observed Navigator.
  final String outlet;

  /// Current top Route used to distinguish managed and foreign Pop ownership.
  Route<dynamic>? topRoute;

  @override
  /// Associates newly rendered managed Page Routes with their Entry identity.
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    adapter._didMountRoute(route);
    topRoute = route;
  }

  @override
  /// Re-closes a gesture-time PopEntry after commit or cancellation.
  void didStopUserGesture() {
    adapter._didStopUserGesture(topRoute);
  }

  @override
  /// Releases a popped Route correlation and remembers the revealed top.
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    adapter._didPopRoute(route);
    adapter._didUnmountRoute(route);
    topRoute = previousRoute;
  }

  @override
  /// Releases an exactly removed Route correlation.
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    adapter._didUnmountRoute(route);
    if (identical(topRoute, route)) topRoute = previousRoute;
  }

  @override
  /// Rebinds a replacement Route while releasing its predecessor.
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute != null) adapter._didUnmountRoute(oldRoute);
    if (newRoute != null) adapter._didMountRoute(newRoute);
    if (identical(topRoute, oldRoute)) topRoute = newRoute;
  }

  @override
  /// Tracks Flutter's confirmed current Route, including foreign Popups.
  void didChangeTop(Route<dynamic> topRoute, Route<dynamic>? previousTopRoute) {
    this.topRoute = topRoute;
  }

  /// Clears any Route retained while the owning Navigator is tearing down.
  void clear() => topRoute = null;
}
