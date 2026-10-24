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

part 'foreign_route_bridge.dart';

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
    required bool Function(String outlet) hasEntries,
    required void Function(String outlet) activateOutlet,
  }) : _navigators = navigators,
       _hasEntries = hasEntries,
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

  /// Adapter callback used to inspect lazy branch initialization.
  final bool Function(String outlet) _hasEntries;

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

  /// Whether [outlet] already owns at least one managed page Entry.
  ///
  /// Host Shell UI can use this to distinguish first branch selection from a
  /// return to an existing branch. On first selection, activate the branch and
  /// navigate to its initial Route. Returning to an initialized branch should
  /// only call [activateOutlet] so its stack and Widget State remain intact.
  /// Feature pages must not use this Host-only stack query. Unknown Outlet
  /// identities fail closed with [CCNavigationAdapterError].
  bool hasEntries(String outlet) => _hasEntries(outlet);

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
/// Unmount releases rendering-only Routes, guards and foreign observations.
/// Remount rebuilds the logical Stack with the same managed identities, pending
/// results and Route Services; ordinary Widget State follows Flutter lifetime.
final class CCManagedOutlet extends StatefulWidget {
  /// Creates a renderer for [outlet] in [backend].
  const CCManagedOutlet({
    required this.backend,
    required this.outlet,
    this.baseBuilder,
    super.key,
  });

  /// Backend whose Store owns the Outlet stack.
  final CCManagedRouterBackend backend;

  /// Stable named Outlet registered by the backend Host.
  final String outlet;

  /// Optional Host-owned local surface retained below this Outlet's Entries.
  ///
  /// It creates no managed Entry, result channel or Route Scope. Use it for an
  /// adaptive pane's local list/detail UI; navigation from its Context still
  /// resolves this exact Host/Outlet. Managed pages pop back to this surface.
  /// Keep the builder stable to preserve its Widget State across stack changes.
  final WidgetBuilder? baseBuilder;

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
  /// [initialLocation] is a trusted fallback. A non-root platform startup URI
  /// takes precedence and passes external ingress policy unless
  /// [overridePlatformDefaultLocation] explicitly forces the Host value.
  /// Null consumes the platform URI, including `/`, as external input.
  CCManagedRouterBackend({
    required this.routeCatalog,
    CCNavigationHost? host,
    Iterable<CCManagedShellBinding> shellBindings = const [],
    String? initialLocation = '/',
    bool overridePlatformDefaultLocation = false,
    Iterable<NavigatorObserver> additionalObservers = const [],
    bool enablePredictiveBack = false,
    bool initializeFromRouteInformation = true,
  }) : host = host ?? CCNavigationHost(),
       _initialLocationIsExternal =
           initialLocation == null ||
           (!overridePlatformDefaultLocation &&
               WidgetsBinding.instance.platformDispatcher.defaultRouteName !=
                   '/'),
       _routeInformationProvider = PlatformRouteInformationProvider(
         initialRouteInformation: RouteInformation(
           uri: Uri.parse(
             initialLocation == null ||
                     (!overridePlatformDefaultLocation &&
                         WidgetsBinding
                                 .instance
                                 .platformDispatcher
                                 .defaultRouteName !=
                             '/')
                 ? WidgetsBinding.instance.platformDispatcher.defaultRouteName
                 : initialLocation,
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
/// referenced only by live renderer topology and Route-scoped PopEntry gates;
/// renderer retirement releases both without closing the logical Stack. The
/// Adapter never retains a `BuildContext` or Widget.
final class CCManagedNavigationAdapter
    implements
        CCNavigationAdapter,
        CCNavigationDispatchAdapter,
        CCNavigationParentStackAdapter,
        CCNavigationTargetedCloseAdapter,
        CCNavigationAdapterHostBinding,
        CCNavigationOutletVisibilityBinding,
        CCNavigationRouteExitBinding,
        CCNavigationAdapterCapabilitySource,
        CCNavigationBackendEventSource,
        CCNavigationBackendSnapshotSource,
        CCNavigationPopCoordinator,
        CCNavigationScopedPopCoordinator,
        CCNavigationPopTargetSource,
        CCNavigationScopedPopTargetSource,
        CCNavigationPopGuardBinding,
        CCNavigationScopedPopGuardBinding,
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
    foreignRouteBridge = CCForeignRouteBridge._(
      allocateBackendEntryId: () {
        _ensureAvailable();
        return 'managed-bridge-${host.id}-${++_foreignSequence}';
      },
      publish: (kind, handle, previous) => _recordBridgedSurface(
        kind: kind,
        backendEntryId: handle.backendEntryId,
        outlet: handle.navigatorOutlet,
        hostId: handle.hostId,
        location: handle.location,
        previousBackendEntryId: previous?.backendEntryId,
        owner: CCBackendEntryOwner.foreign,
      ),
      publishOpaque: (kind, handle) => _recordBridgedSurface(
        kind: kind,
        backendEntryId: handle.backendEntryId,
        outlet: handle.navigatorOutlet,
        hostId: handle.hostId,
        location: handle.location,
        owner: CCBackendEntryOwner.opaque,
      ),
    );
    if (enablePredictiveBack) {
      _predictiveBackBridge = CCManagedPredictiveBackBridge(
        hostId: host.id,
        activeOutlet: () => _popOutlet,
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

  /// Diagnostic-only reporting for third-party Navigators and non-Route UI.
  ///
  /// This bridge neither navigates nor creates a managed Entry, result or Scope.
  /// The Adapter owns it and invalidates all handles and callbacks on disposal.
  late final CCForeignRouteBridge foreignRouteBridge;

  /// Publishes an explicit foreign/opaque lifecycle without rendering a Page.
  void _recordBridgedSurface({
    required CCNavigationBackendEventKind kind,
    required String backendEntryId,
    required String outlet,
    required CCBackendEntryOwner owner,
    String? hostId,
    String? location,
    String? previousBackendEntryId,
  }) {
    _ensureAvailable();
    final sequence = ++_eventSequence;
    _emit(
      CCNavigationBackendEvent(
        kind: kind,
        timestamp: DateTime.now(),
        backendEntryId: backendEntryId,
        backendOperationId: '$_eventNamespace-$sequence',
        sequence: sequence,
        hostId: hostId ?? _host.id,
        navigatorOutlet: outlet,
        owner: owner,
        location: location,
        previousBackendEntryId: previousBackendEntryId,
        placement: CCRoutePlacement(
          hostId: hostId ?? _host.id,
          navigatorOutlet: outlet,
        ),
      ),
    );
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

  /// Empty structural Pages retained only while foreign Routes need their base.
  final Map<String, ({int order, Page<Object?> page})> _foreignAnchors = {};

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

  /// Whether Host layout, rather than navigation defaults, owns visibility.
  bool _hasExplicitVisibleOutlets = false;

  /// Payload-free exit signals owned only until Flutter finishes rendering.
  final Map<String, _CCManagedRouteExit> _routeExits = {};

  /// Frozen child projections owned only by an actually outgoing Shell Route.
  final Map<Route<dynamic>, _CCManagedShellRenderExit> _shellRenderExits = {};

  /// Exact removals whose synchronous Page callbacks must not defer disposal.
  final Set<String> _immediateRemovals = {};

  /// Pending typed results keyed by Runtime navigation identity.
  final Map<String, Completer<Object?>> _results = {};

  /// Weak rendered Route references keyed by backend Entry identity.
  final Map<String, WeakReference<Route<dynamic>>> _renderedRoutes = {};

  /// External Pops awaiting Flutter's actual result in the next microtask.
  final Set<String> _externalPops = {};

  /// Runtime-owned synchronous guard evaluator while the Adapter is attached.
  CCPopGuardEvaluator? _popGuardEvaluator;

  /// Exact native policy, preferred over the legacy focus-based binding.
  CCScopedPopGuardEvaluator? _scopedPopGuardEvaluator;

  /// Conservative Flutter gates installed on guarded managed Routes.
  final Map<ModalRoute<Object?>, _CCManagedPopEntry> _managedPopGuardEntries =
      {};

  /// Routes awaiting a mounted ModalScope before PopEntry registration.
  final Set<Route<dynamic>> _pendingManagedPopGuardRoutes = {};

  /// Routes whose exact Runtime-approved Pop temporarily opened their gate.
  final Set<Route<dynamic>> _runtimeGuardedPopRoutes = {};

  /// Short-lived ownership prevents overlapping requests from claiming one Pop.
  final Map<Route<dynamic>, _CCManagedPopOperation> _pendingPops = {};

  /// Store listeners owned by Router delegates and Outlet renderers.
  final Set<VoidCallback> _stateListeners = {};

  /// Runtime backend-event subscribers.
  final Set<CCNavigationBackendEventListener> _backendListeners = {};

  /// Adapter-supplied results awaiting exact Route removal confirmation.
  final Map<String, Object?> _pendingRemovalResults = {};

  /// Allocates process-local Adapter identities without retaining retired Hosts.
  static int _nextEventNamespace = 0;

  /// Disjoint event namespace even when a logical Host ID is reused.
  final String _eventNamespace = 'managed-${++_nextEventNamespace}';

  /// Monotonic backend event sequence scoped to this Adapter instance.
  int _eventSequence = 0;

  /// Monotonic structural order shared by root Entries and Shell anchors.
  int _entrySequence = 0;

  /// Monotonic identity source for live foreign Routes; never retains payloads.
  int _foreignSequence = 0;

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
        supportsNestedNavigators: true,
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
    _refreshPopGuardBinding();
  }

  @override
  /// Binds native Route policy without changing global Host or Outlet focus.
  void bindScopedPopGuardEvaluator(CCScopedPopGuardEvaluator? evaluator) {
    _scopedPopGuardEvaluator = evaluator;
    _refreshPopGuardBinding();
  }

  /// Reconciles native gates after either optional policy binding changes.
  void _refreshPopGuardBinding() {
    _predictiveBackBridge?.bindPopGuardEvaluator(
      _hasPopGuardEvaluator
          ? (trigger) => _evaluateNativePopGuard(trigger, activePopTarget)
          : null,
    );
    if (!_hasPopGuardEvaluator) {
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

  /// Whether either supported Runtime policy binding remains attached.
  bool get _hasPopGuardEvaluator =>
      _scopedPopGuardEvaluator != null || _popGuardEvaluator != null;

  /// Uses the exact rendered identity; an unavailable guarded target fails closed.
  CCPopGuardDecision _evaluateNativePopGuard(
    CCPopTrigger trigger,
    CCNavigationPopTarget? target,
  ) {
    if (target?.handlesPopInternally == true) return const CCPopAllow();
    final scoped = _scopedPopGuardEvaluator;
    if (scoped != null) {
      return target == null
          ? const CCPopDeny(code: 'pop_target_unavailable')
          : scoped(trigger, target: target);
    }
    return _popGuardEvaluator?.call(trigger) ?? const CCPopAllow();
  }

  /// Captures the actual native Route, rather than a last-focused partition.
  CCNavigationPopTarget? _nativePopTarget(Route<dynamic> route) {
    final entry = _entryForRoute(route);
    if (entry == null) return null;
    return CCNavigationPopTarget(
      hostId: _host.id,
      navigatorOutlet: entry.request.placement.navigatorOutlet,
      backendEntryId: entry.backendEntryId,
      handlesPopInternally: route.willHandlePopInternally,
    );
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
  Uri? get _currentUri {
    if (_state.entries.isEmpty) return null;
    final shellId = _state.activeShellId;
    final roots = _entriesForOutlet('root');
    if (shellId == null) return _state.entries.last.request.uri;
    if (roots.isNotEmpty && roots.last.order > _state.shellAnchorOrder!) {
      return roots.last.request.uri;
    }
    final outlet =
        _state.activeOutletsByShell[shellId] ?? _shells[shellId]!.initialOutlet;
    final branch = _entriesForOutlet(outlet);
    return branch.isEmpty ? null : branch.last.request.uri;
  }

  /// Visible stack partitions after root overlays mask the retained layout.
  Set<String> get _effectiveVisibleOutlets {
    final roots = _entriesForOutlet('root');
    if (_foreignRootTop != null ||
        (_state.activeShellId != null &&
            roots.isNotEmpty &&
            roots.last.order > _state.shellAnchorOrder!)) {
      return const {'root'};
    }
    return _state.visibleOutlets;
  }

  /// Outlet currently used for context-free Back and Pop operations.
  String get focusedOutlet => _state.focusedOutlet;

  /// Outlets currently visible in the Host layout.
  Set<String> get visibleOutlets => Set.unmodifiable(_effectiveVisibleOutlets);

  /// Publishes the Outlets simultaneously visible in the current Host layout.
  ///
  /// Adaptive split-pane infrastructure calls this after layout selection. It
  /// does not push, remove, or focus a Page, and hidden branch stacks remain
  /// retained. The set must be non-empty and contain only registered Outlets.
  /// Once supplied, layout selection survives navigation, focus and Shell
  /// activation until the Host supplies another set. Covering root surfaces
  /// temporarily mask this retained selection. Invalid input leaves it intact.
  @override
  void updateVisibleOutlets(Iterable<String> outlets) {
    _ensureAvailable();
    final values = List<String>.of(outlets);
    final next = values.toSet();
    if (next.isEmpty ||
        next.length != values.length ||
        next.any((outlet) => !_host.containsOutlet(outlet))) {
      throw const CCNavigationAdapterError(
        'Visible Outlets must be a non-empty unique subset of the managed Host.',
      );
    }
    _hasExplicitVisibleOutlets = true;
    if (setEquals(next, _state.visibleOutlets)) return;
    _state = _copyState(entries: _state.entries, visibleOutlets: next);
    _predictiveBackBridge?.invalidateInactiveOutlets();
    _notifyStateListeners();
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
    final claimedOutlets = <String>{'root'};
    for (final shell in shells) {
      final outlets = shell.outlets.toSet();
      if (outlets.length != shell.outlets.length ||
          !outlets.contains(shell.initialOutlet)) {
        throw CCNavigationAdapterError(
          'Managed Shell "${shell.shellId}" has an invalid Outlet contract.',
        );
      }
      for (final outlet in shell.outlets) {
        if (!claimedOutlets.add(outlet)) {
          throw CCNavigationAdapterError(
            'Managed Shell "${shell.shellId}" cannot own root or share '
            'Outlet "$outlet" with another Shell on Host "${_host.id}".',
          );
        }
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
    for (final parent in request.parentStack) {
      _ensureRequest(parent);
      if (parent.hostId != request.hostId ||
          parent.placement.navigatorOutlet !=
              request.placement.navigatorOutlet ||
          parent.placement.shellId != request.placement.shellId ||
          parent.parentStack.isNotEmpty) {
        throw const CCNavigationAdapterError('Invalid managed parent plan.');
      }
    }
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
  /// Runtime constructs ancestors for this Backend's declarative transactions.
  bool supportsParentStack(CCNavigationRequest request) => true;

  @override
  /// Proves synchronous Store acceptance independently of the later Pop result.
  CCNavigationDispatch dispatchNavigation(CCNavigationRequest request) =>
      CCNavigationDispatch(result: navigate(request));

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
    final keepForeignRoot =
        route != null &&
        _entriesForOutlet(navigatorOutlet).length == 1 &&
        (_observerFor(navigatorOutlet).foreignEntries.isNotEmpty ||
            _coveringForeignRootRoute(navigatorOutlet) != null);
    if (keepForeignRoot) {
      final settings = route.settings;
      Page<Object?>? anchor;
      if (settings is _CCManagedGuardedPage) {
        anchor = _CCManagedGuardedPage(
          child: const SizedBox.shrink(),
          presentation: settings.presentation,
          adapter: this,
          key: settings.key,
        );
      } else if (settings is _CCManagedPage) {
        anchor = _CCManagedPage(
          adapter: this,
          child: const SizedBox.shrink(),
          presentation: settings.presentation,
          key: settings.key,
        );
      }
      if (anchor != null) {
        _foreignAnchors[navigatorOutlet] = (order: entry.order, page: anchor);
      }
      _removeManagedPopGuard(route);
    }
    if (!keepForeignRoot &&
        route != null &&
        route.isActive &&
        navigator != null) {
      _pendingRemovalResults[entry.backendEntryId] = result;
      _immediateRemovals.add(entry.backendEntryId);
      try {
        navigator.removeRoute<Object?>(route, result);
      } finally {
        _immediateRemovals.remove(entry.backendEntryId);
      }
    }
    if (_entryForNavigation(navigationId) != null) {
      _removeEntry(
        entry,
        result: result,
        eventKind: CCNavigationBackendEventKind.remove,
        preserveRenderLifetime: false,
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
    final outlet = _coveringForeignRootRoute(navigatorOutlet) == null
        ? navigatorOutlet
        : 'root';
    final navigator = _host.navigatorKeyFor(outlet).currentState;
    if (navigator == null) return _unhandledPop;
    final top = _observerFor(outlet).topRoute;
    if (top == null) return _unhandledPop;
    if (_pendingPops.containsKey(top)) {
      return CCPopOutcome(
        handled: true,
        hostId: _host.id,
        navigatorOutlet: outlet,
      );
    }
    final operation = _CCManagedPopOperation();
    _pendingPops[top] = operation;
    final managed = _entryForRoute(top) ?? _topEntryForShellRoute(top);
    // Normal Page results come from Route.popped. Only a structural Shell
    // needs to associate the container result with its selected child.
    if (managed != null && top.settings is _CCManagedShellPage) {
      _pendingRemovalResults[managed.backendEntryId] = result;
    }
    // Internal history may disappear while willPop awaits. Keep the native
    // gate closed so the actual exit still checks its exact Managed Guard.
    final approveExit = !top.willHandlePopInternally;
    if (approveExit) _setManagedPopEntryCanPop(top, true);
    late final bool handled;
    try {
      handled = await Future.any([
        runZoned(
          () => navigator.maybePop<Object?>(result),
          zoneValues: {_CCManagedPopOperation.zoneKey: operation},
        ),
        operation.retired.future,
      ]);
    } finally {
      _pendingPops.remove(top);
      if (approveExit) _setManagedPopEntryCanPop(top, false);
      if (managed != null) {
        _pendingRemovalResults.remove(managed.backendEntryId);
      }
    }
    if (!handled && _canPopShell(outlet)) {
      return maybePopOutcomeAt(
        hostId: hostId,
        navigatorOutlet: 'root',
        result: result,
      );
    }
    if (!handled) return _unhandledPop;
    if (operation.didPop && operation.removedBackendEntryId != null) {
      return CCPopOutcome(
        handled: true,
        removedBackendEntryId: operation.removedBackendEntryId,
        removedEntryOwner: CCPopRemovedEntryOwner.managed,
        hostId: _host.id,
        navigatorOutlet: outlet,
      );
    }
    return CCPopOutcome(
      handled: true,
      removedEntryOwner: operation.didPop
          ? CCPopRemovedEntryOwner.foreign
          : CCPopRemovedEntryOwner.none,
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
    final outlet = _coveringForeignRootRoute(navigatorOutlet) == null
        ? navigatorOutlet
        : 'root';
    final navigator = _host.navigatorKeyFor(outlet).currentState;
    if (navigator == null) return _unhandledPop;
    if (!navigator.canPop()) {
      return _canPopShell(outlet)
          ? popOutcomeAt(
              hostId: hostId,
              navigatorOutlet: 'root',
              result: result,
            )
          : _unhandledPop;
    }
    final top = _observerFor(outlet).topRoute;
    final managed = _entryForRoute(top) ?? _topEntryForShellRoute(top);
    if (managed != null) {
      _pendingRemovalResults[managed.backendEntryId] = result;
    }
    if (top != null) _setManagedPopEntryCanPop(top, true);
    try {
      navigator.pop<Object?>(result);
    } finally {
      if (top != null) _setManagedPopEntryCanPop(top, false);
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
    if (_coveringForeignRootRoute(navigatorOutlet) != null) {
      return _host.navigatorKey.currentState?.canPop() ?? false;
    }
    return (_host.navigatorKeyFor(navigatorOutlet).currentState?.canPop() ??
            false) ||
        _canPopShell(navigatorOutlet);
  }

  /// Whether an exhausted child can bubble Back to its current Shell anchor.
  bool _canPopShell(String outlet) {
    final shell = _shellForOutlet(outlet);
    final top = _observerFor('root').topRoute;
    return shell != null &&
        top?.settings is _CCManagedShellPage &&
        (top!.settings as _CCManagedShellPage).shellId == shell.shellId &&
        (_host.navigatorKey.currentState?.canPop() ?? false);
  }

  /// Managed result/guard owner of a structural Shell Route's selected branch.
  _CCManagedEntry? _topEntryForShellRoute(Route<dynamic>? route) {
    final settings = route?.settings;
    if (settings is! _CCManagedShellPage) return null;
    final shell = _shells[settings.shellId];
    if (shell == null) return null;
    final outlet =
        _state.activeOutletsByShell[shell.shellId] ?? shell.initialOutlet;
    final entries = _entriesForOutlet(outlet);
    return entries.isEmpty ? null : entries.last;
  }

  @override
  /// Live managed or foreign target selected for context-free Back.
  CCNavigationPopTarget? get activePopTarget {
    return popTargetAt(hostId: _host.id, navigatorOutlet: _popOutlet);
  }

  @override
  /// Resolves actual ownership without changing Host focus or branch selection.
  CCNavigationPopTarget? popTargetAt({
    required String hostId,
    required String navigatorOutlet,
  }) {
    if (_disposed ||
        hostId != _host.id ||
        !_host.containsOutlet(navigatorOutlet))
      return null;
    final outlet = _coveringForeignRootRoute(navigatorOutlet) == null
        ? navigatorOutlet
        : 'root';
    final observer = _observerFor(outlet);
    final settings = observer.topRoute?.settings;
    if (settings is _CCManagedShellPage) {
      final shell = _shells[settings.shellId];
      if (shell != null) {
        return popTargetAt(
          hostId: hostId,
          navigatorOutlet:
              _state.activeOutletsByShell[shell.shellId] ?? shell.initialOutlet,
        );
      }
    }
    final foreignId = observer.foreignEntries[observer.topRoute];
    if (foreignId != null) {
      return CCNavigationPopTarget(
        hostId: _host.id,
        navigatorOutlet: outlet,
        backendEntryId: foreignId,
        owner: CCBackendEntryOwner.foreign,
      );
    }
    final entries = _entriesForOutlet(outlet);
    final entry =
        _entryForRoute(_observerFor(outlet).topRoute) ??
        (entries.isEmpty ? null : entries.last);
    if (entry == null) return null;
    return CCNavigationPopTarget(
      hostId: _host.id,
      navigatorOutlet: outlet,
      backendEntryId: entry.backendEntryId,
      handlesPopInternally: observer.topRoute?.willHandlePopInternally ?? false,
    );
  }

  /// Outlet selected for a navigation command without call-site Context.
  String get _popOutlet {
    final visible = _effectiveVisibleOutlets;
    final focused = _state.focusedOutlet;
    if (visible.contains(focused) &&
        _host.navigatorKeyFor(focused).currentState != null)
      return focused;
    final shellId = _state.activeShellId;
    final selected = _state.activeOutletsByShell[shellId];
    if (selected != null &&
        visible.contains(selected) &&
        _host.navigatorKeyFor(selected).currentState != null)
      return selected;
    final mounted = visible.where(
      (outlet) => _host.navigatorKeyFor(outlet).currentState != null,
    );
    if (mounted.length == 1) return mounted.single;
    return 'root';
  }

  /// Returns a foreign root Route visually covering one nested Outlet.
  ///
  /// RouterDelegate Back reaches the managed Adapter before Flutter can select
  /// a Navigator. A root Dialog or Popup must therefore be offered Pop before
  /// the focused child Navigator; structural Shell and placeholder Routes are
  /// not foreign surfaces.
  Route<dynamic>? _coveringForeignRootRoute(String outlet) {
    if (outlet == 'root') return null;
    return _foreignRootTop;
  }

  /// Real foreign root top, excluding implementation-owned structural Pages.
  Route<dynamic>? get _foreignRootTop {
    final route = _observerFor('root').topRoute;
    if (route == null ||
        !route.isCurrent ||
        _entryForRoute(route) != null ||
        route.settings is _CCManagedShellPage ||
        route.settings is _CCManagedPlaceholderPage) {
      return null;
    }
    return route;
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

  /// Creates root Pages and retained Shell anchors in their shared Stack order.
  List<Page<Object?>> _buildRootPages() {
    final layers = <({int order, Page<Object?> page})>[
      if (_foreignAnchors['root'] case final anchor?) anchor,
      for (final entry in _entriesForOutlet('root'))
        (order: entry.order, page: _buildPage(entry)),
    ];
    for (final anchor in _state.shellAnchors.entries) {
      final shellId = anchor.key;
      layers.add((
        order: anchor.value,
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
  List<Page<Object?>> _buildOutletPages(
    String outlet, {
    WidgetBuilder? baseBuilder,
  }) {
    final entries = _entriesForOutlet(outlet);
    final anchor = _foreignAnchors[outlet]?.page;
    if (baseBuilder != null) {
      return [
        _CCManagedPlaceholderPage(
          key: ValueKey<String>('ccrouter.managed.base.$outlet'),
          builder: baseBuilder,
        ),
        if (anchor != null) anchor,
        ...entries.map(_buildPage),
      ];
    }
    if (entries.isEmpty) {
      if (anchor != null) return [anchor];
      return [
        _CCManagedPlaceholderPage(
          key: ValueKey<String>('ccrouter.managed.placeholder.$outlet'),
        ),
      ];
    }
    return List.unmodifiable([
      if (anchor != null) anchor,
      ...entries.map(_buildPage),
    ]);
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
        path: request.pathParameters,
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
    return _CCManagedPage(
      adapter: this,
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
  }

  /// Applies Go to one partition or Reset to every partition of this Host.
  void _replaceAll(CCNavigationRequest request, {required bool resetHost}) {
    final outlet = request.placement.navigatorOutlet;
    final removed = resetHost
        ? _state.entries
        : _state.entries
              .where(
                (entry) =>
                    entry.request.placement.navigatorOutlet == outlet ||
                    (outlet == 'root' &&
                        _shellForOutlet(
                              entry.request.placement.navigatorOutlet,
                            ) !=
                            null),
              )
              .toList(growable: false);
    final retained = _state.entries
        .where((entry) => !removed.contains(entry))
        .toList(growable: true);
    final parents = [
      for (final parent in request.parentStack)
        _CCManagedEntry(parent, order: ++_entrySequence),
    ];
    final entry = _CCManagedEntry(request, order: ++_entrySequence);
    retained.addAll([...parents, entry]);
    _commitForNavigation(
      retained,
      entry,
      clearActiveShell: resetHost || outlet == 'root',
    );
    for (final old in removed.reversed) {
      _retainRouteExit(old);
      _completeResult(old.request.navigationId, null);
      _renderedRoutes.remove(old.backendEntryId);
      _emitEntryEvent(CCNavigationBackendEventKind.remove, old);
    }
    for (final parent in parents) {
      _emitEntryEvent(CCNavigationBackendEventKind.push, parent);
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
  }

  /// Removes [entry], completes its channel once, and reveals its partition top.
  void _removeEntry(
    _CCManagedEntry entry, {
    Object? result,
    required CCNavigationBackendEventKind eventKind,
    bool notify = true,
    bool preserveRenderLifetime = true,
  }) {
    if (!_state.entries.contains(entry)) return;
    if (preserveRenderLifetime) _retainRouteExit(entry);
    final next = [..._state.entries]..remove(entry);
    _state = _copyState(entries: next);
    _renderedRoutes.remove(entry.backendEntryId);
    _pendingRemovalResults.remove(entry.backendEntryId);
    _completeResult(entry.request.navigationId, result);
    _emitEntryEvent(eventKind, entry);
    if (notify) _notifyStateListeners();
  }

  /// Tracks only a live outgoing transition, never a retained empty anchor.
  void _retainRouteExit(
    _CCManagedEntry entry, {
    TransitionRoute<Object?>? outerRoute,
  }) {
    final navigationId = entry.request.navigationId;
    if (_routeExits.containsKey(navigationId)) return;
    final route = outerRoute ?? _renderedRoutes[entry.backendEntryId]?.target;
    if (_immediateRemovals.contains(entry.backendEntryId) ||
        route is! TransitionRoute<Object?> ||
        _foreignAnchors.values.any(
          (anchor) => anchor.page.key == entry.pageKey,
        )) {
      return;
    }
    final exit = _CCManagedRouteExit(
      outlet: outerRoute == null
          ? entry.request.placement.navigatorOutlet
          : 'root',
      onComplete: () => _routeExits.remove(navigationId),
    );
    _routeExits[navigationId] = exit;
    // The Future retains only this detachable signal, not Adapter or payload.
    unawaited(
      route.completed.then<void>(
        (_) => exit.complete(),
        onError: (Object _, StackTrace __) => exit.complete(),
      ),
    );
  }

  @override
  /// Keeps a removed page's Scope usable only through its pending render exit.
  void Function()? addRouteExitListener({
    required String navigationId,
    required String hostId,
    required void Function() onExited,
  }) {
    if (_disposed || hostId != _host.id) return null;
    return _routeExits[navigationId]?.addListener(onExited);
  }

  /// Commits one navigation transaction and updates structural Shell state.
  void _commitForNavigation(
    List<_CCManagedEntry> entries,
    _CCManagedEntry entry, {
    bool clearActiveShell = false,
  }) {
    final placement = entry.request.placement;
    final shellId = _shellForOutlet(placement.navigatorOutlet)?.shellId;
    if (shellId != null) {
      for (final exit in _shellRenderExits.values) {
        if (exit.shellId == shellId) exit.retireProjection();
      }
    }
    final anchors = clearActiveShell
        ? <String, int>{}
        : {..._state.shellAnchors};
    final activeOutlets = {..._state.activeOutletsByShell};
    var visibleOutlets = {..._state.visibleOutlets};
    if (shellId != null) {
      if (_state.activeShellId != shellId || !anchors.containsKey(shellId)) {
        anchors[shellId] = entry.order;
      }
      activeOutlets[shellId] = placement.navigatorOutlet;
      visibleOutlets = {placement.navigatorOutlet};
    } else if (placement.navigatorOutlet == 'root') {
      if (anchors.isEmpty) visibleOutlets = {'root'};
    } else {
      visibleOutlets.add(placement.navigatorOutlet);
    }
    _state = _CCManagedNavigationState(
      revision: _state.revision + 1,
      entries: entries,
      shellAnchors: anchors,
      focusedOutlet: placement.navigatorOutlet,
      visibleOutlets: _hasExplicitVisibleOutlets
          ? _state.visibleOutlets
          : visibleOutlets,
      activeOutletsByShell: activeOutlets,
    );
    _notifyStateListeners();
  }

  /// Copies state, retiring empty Shell anchors and restoring the revealed one.
  _CCManagedNavigationState _copyState({
    required List<_CCManagedEntry> entries,
    bool clearActiveShell = false,
    String? focusedOutlet,
    Set<String>? visibleOutlets,
    Map<String, String>? activeOutletsByShell,
  }) {
    final anchors = <String, int>{
      if (!clearActiveShell)
        for (final anchor in _state.shellAnchors.entries)
          if (entries.any(
                (entry) => _shells[anchor.key]!.outlets.contains(
                  entry.request.placement.navigatorOutlet,
                ),
              ) ||
              _shells[anchor.key]!.outlets.any(_foreignAnchors.containsKey))
            anchor.key: anchor.value,
    };
    final activeShell = _CCManagedNavigationState.topShell(anchors);
    final shellChanged = activeShell != _state.activeShellId;
    final revealedOutlet = activeShell == null
        ? 'root'
        : (_state.activeOutletsByShell[activeShell] ??
              _shells[activeShell]!.initialOutlet);
    return _CCManagedNavigationState(
      revision: _state.revision + 1,
      entries: entries,
      shellAnchors: anchors,
      focusedOutlet:
          focusedOutlet ??
          (shellChanged ? revealedOutlet : _state.focusedOutlet),
      visibleOutlets:
          visibleOutlets ??
          (shellChanged && !_hasExplicitVisibleOutlets
              ? {revealedOutlet}
              : _state.visibleOutlets),
      activeOutletsByShell: activeOutletsByShell ?? _state.activeOutletsByShell,
    );
  }

  /// Notifies a stable copy so listeners may detach during callbacks.
  void _notifyStateListeners() {
    _emitVisibleOutlets();
    for (final listener in _stateListeners.toList()) {
      listener();
    }
  }

  /// Resolves structural ownership independently of a page's declared metadata.
  CCNavigationShell? _shellForOutlet(String outlet) {
    for (final shell in _shells.values) {
      if (shell.outlets.contains(outlet)) return shell;
    }
    return null;
  }

  /// Publishes the same layout projection consumed by Flutter lifecycle hooks.
  void _emitVisibleOutlets() {
    CCPageLifecycleHostBridge.setActiveOutlets(
      hostId: _host.id,
      outlets: _disposed ? const <String>[] : _effectiveVisibleOutlets,
    );
    if (_disposed) return;
    _emit(
      CCNavigationBackendEvent(
        kind: CCNavigationBackendEventKind.outletsChanged,
        timestamp: DateTime.now(),
        backendOperationId: '$_eventNamespace-${++_eventSequence}',
        hostId: _host.id,
        sequence: _eventSequence,
        activeNavigatorOutlets: _effectiveVisibleOutlets,
      ),
    );
  }

  /// Returns the stable observer owned by one registered Outlet.
  _CCManagedNavigatorObserver _observerFor(String outlet) => _observers
      .putIfAbsent(outlet, () => _CCManagedNavigatorObserver(this, outlet));

  /// Starts a fresh renderer generation without altering the logical Stack.
  _CCManagedNavigatorObserver _attachRenderer(String outlet) {
    _observers[outlet]?.retire();
    final observer = _CCManagedNavigatorObserver(this, outlet);
    _observers[outlet] = observer;
    return observer;
  }

  /// Retires only this generation; an older disposal cannot clear a new mount.
  void _detachRenderer(_CCManagedNavigatorObserver observer) {
    observer.retire();
    if (identical(_observers[observer.outlet], observer)) {
      if (observer.outlet == 'root') {
        for (final exit in _shellRenderExits.values.toList()) {
          exit.complete();
        }
      }
      _observers.remove(observer.outlet);
    }
  }

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
      visibleOutlets: _hasExplicitVisibleOutlets
          ? _state.visibleOutlets
          : {outlet},
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
        backendOperationId: '$_eventNamespace-${++_eventSequence}',
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
        activeNavigatorOutlets: _effectiveVisibleOutlets,
      ),
    );
    _emitVisibleOutlets();
  }

  /// Reports whether one declared Shell Outlet already owns managed Entries.
  bool _shellHasEntries(String shellId, String outlet) {
    _ensureAvailable();
    final shell = _shells[shellId];
    if (shell == null || !shell.outlets.contains(outlet)) {
      throw CCNavigationAdapterError(
        'Managed Shell "$shellId" does not declare Outlet "$outlet".',
      );
    }
    return _state.entries.any(
      (entry) => entry.request.placement.navigatorOutlet == outlet,
    );
  }

  /// Handles a Page-driven Pop or gesture after Flutter accepted it.
  void _didRemovePage(Page<Object?> page) {
    if (page is! _CCManagedPage && page is! _CCManagedGuardedPage) return;
    final entry = _entryForPageKey(page.key);
    if (entry == null || _externalPops.contains(entry.backendEntryId)) return;
    _removeEntry(
      entry,
      result: _pendingRemovalResults.remove(entry.backendEntryId),
      eventKind: CCNavigationBackendEventKind.pop,
    );
  }

  /// Applies one Navigator-confirmed Pop before its Route correlation is lost.
  void _didPopRoute(Route<dynamic> route) {
    final settings = route.settings;
    if (settings is _CCManagedShellPage) {
      final outlets = _shells[settings.shellId]?.outlets;
      if (outlets == null) return;
      final removed = _state.entries
          .where(
            (entry) =>
                outlets.contains(entry.request.placement.navigatorOutlet),
          )
          .toList();
      // A declarative removal only confirms an already committed transaction;
      // do not notify Router from Navigator.didUpdateWidget/build again.
      if (removed.isEmpty) return;
      final selected = _topEntryForShellRoute(route);
      if (route is TransitionRoute<Object?>) {
        final shell = _shells[settings.shellId]!;
        final exit = _CCManagedShellRenderExit(
          shellId: shell.shellId,
          activeOutlet:
              _state.activeOutletsByShell[shell.shellId] ?? shell.initialOutlet,
          pages: {
            for (final outlet in outlets)
              outlet: List<Page<Object?>>.of(
                _host.navigatorKeyFor(outlet).currentState?.widget.pages ??
                    [
                      _CCManagedPlaceholderPage(
                        key: ValueKey('ccrouter.managed.placeholder.$outlet'),
                      ),
                    ],
              ),
          },
          onComplete: () => _shellRenderExits.remove(route),
        );
        _shellRenderExits[route] = exit;
        unawaited(
          route.completed.then<void>(
            (_) => exit.complete(),
            onError: (Object _, StackTrace __) => exit.complete(),
          ),
        );
        for (final entry in removed) {
          if (_renderedRoutes[entry.backendEntryId]?.target != null) {
            _retainRouteExit(entry, outerRoute: route);
          }
        }
      }
      void removeEntries(Object? result) {
        if (_disposed) return;
        for (final entry in removed.reversed) {
          _removeEntry(
            entry,
            result: identical(entry, selected) ? result : null,
            eventKind: CCNavigationBackendEventKind.pop,
            notify: false,
          );
        }
        _notifyStateListeners();
      }

      if (selected != null &&
          _pendingRemovalResults.containsKey(selected.backendEntryId)) {
        removeEntries(_pendingRemovalResults.remove(selected.backendEntryId));
      } else {
        unawaited(route.popped.then(removeEntries));
      }
      return;
    }
    final entry = _entryForRoute(route);
    if (entry == null) return;
    // Native Pop results arrive in a microtask, after observer unmount. Capture
    // the exit signal now so outgoing rebuilds retain their exact Scope.
    _retainRouteExit(entry);
    if (!_pendingRemovalResults.containsKey(entry.backendEntryId)) {
      _externalPops.add(entry.backendEntryId);
      unawaited(
        route.popped.then((result) {
          _externalPops.remove(entry.backendEntryId);
          if (!_disposed) {
            _removeEntry(
              entry,
              result: result,
              eventKind: CCNavigationBackendEventKind.pop,
            );
          }
        }),
      );
      return;
    }
    _removeEntry(
      entry,
      result: _pendingRemovalResults.remove(entry.backendEntryId),
      eventKind: CCNavigationBackendEventKind.pop,
    );
  }

  /// Retains a weak correlation while [route] belongs to a managed Page.
  void _didMountRoute(Route<dynamic> route) {
    final entry = _entryForRoute(route);
    if (entry != null) {
      _renderedRoutes[entry.backendEntryId] = WeakReference(route);
      if (_routeRequiresPopGuard(entry.request.routeId)) {
        _installManagedPopGuard(route);
      }
    }
  }

  /// Drops a rendered correlation without mutating Store ownership.
  void _didUnmountRoute(Route<dynamic> route) {
    _pendingPops[route]?.retire();
    _removeManagedPopGuard(route);
    final entry = _entryForRoute(route);
    if (entry != null) _renderedRoutes.remove(entry.backendEntryId);
  }

  /// Whether Runtime metadata marks [routeId] as requiring Pop policy.
  bool _routeRequiresPopGuard(String routeId) =>
      _routes[routeId]?.hasPopGuard ?? false;

  /// Opens only the exact approved Route; another Outlet keeps its own gate.
  void _setManagedPopEntryCanPop(Route<dynamic> route, bool value) {
    if (value) {
      _runtimeGuardedPopRoutes.add(route);
    } else {
      _runtimeGuardedPopRoutes.remove(route);
    }
    _managedPopGuardEntries[route]?.canPopNotifier.value = value;
  }

  /// Opens one guarded Route only when gesture-time Runtime policy allows it.
  bool _prepareManagedPopGesture(Route<dynamic> route) {
    final modalRoute = route is ModalRoute<Object?> ? route : null;
    final entry = modalRoute == null
        ? null
        : _managedPopGuardEntries[modalRoute];
    if (_disposed ||
        !_hasPopGuardEvaluator ||
        modalRoute == null ||
        entry == null ||
        !modalRoute.isCurrent) {
      return false;
    }
    if (entry.canPopNotifier.value) return true;
    final decision = _evaluateNativePopGuard(
      CCPopTrigger.gesture,
      _nativePopTarget(route),
    );
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
    if (!_hasPopGuardEvaluator || route is! ModalRoute<Object?>) return;
    if (_managedPopGuardEntries.containsKey(route) ||
        _pendingManagedPopGuardRoutes.contains(route)) {
      return;
    }
    _pendingManagedPopGuardRoutes.add(route);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_pendingManagedPopGuardRoutes.remove(route)) return;
      if (_disposed || !_hasPopGuardEvaluator || !route.isActive) return;
      _attachManagedPopGuard(route);
    });
  }

  /// Registers one closed PopEntry after the Route's ModalScope is mounted.
  void _attachManagedPopGuard(ModalRoute<Object?> route) {
    if (!_hasPopGuardEvaluator || _managedPopGuardEntries.containsKey(route)) {
      return;
    }
    late final _CCManagedPopEntry entry;
    entry = _CCManagedPopEntry(
      onInvoked: (didPop, result) {
        if (didPop ||
            _runtimeGuardedPopRoutes.contains(route) ||
            entry.retrying)
          return;
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
    final navigator = route.navigator;
    if (_disposed ||
        !_hasPopGuardEvaluator ||
        navigator == null ||
        !route.isCurrent) {
      return;
    }
    entry.retrying = true;
    try {
      final decision = _evaluateNativePopGuard(
        CCPopTrigger.system,
        _nativePopTarget(route),
      );
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

  /// Retires empty boundaries only after both local and covering popups leave.
  void _releaseForeignAnchors() {
    if (_disposed || _foreignAnchors.isEmpty) return;
    final rootHasForeign = _observerFor('root').foreignEntries.isNotEmpty;
    final removed = _foreignAnchors.keys
        .where(
          (outlet) =>
              !rootHasForeign && _observerFor(outlet).foreignEntries.isEmpty,
        )
        .toList();
    if (removed.isEmpty) return;
    for (final outlet in removed) {
      _foreignAnchors.remove(outlet);
    }
    _state = _copyState(entries: _state.entries);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed) _notifyStateListeners();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  /// Returns only framework-created Pages; a copied key never conveys ownership.
  _CCManagedEntry? _entryForRoute(Route<dynamic>? route) {
    if (route == null ||
        (route.settings is! _CCManagedPage &&
            route.settings is! _CCManagedGuardedPage))
      return null;
    final settings = route.settings;
    final owner = settings is _CCManagedPage
        ? settings.adapter
        : (settings as _CCManagedGuardedPage).adapter;
    if (!identical(owner, this)) return null;
    final entry = _entryForPageKey((settings as Page<dynamic>).key);
    if (entry == null) return null;
    final rendered = _renderedRoutes[entry.backendEntryId]?.target;
    return rendered == null || identical(rendered, route) ? entry : null;
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
        backendOperationId: '$_eventNamespace-${++_eventSequence}',
        previousBackendEntryId: previousBackendEntryId,
        hostId: _host.id,
        navigatorOutlet: request.placement.navigatorOutlet,
        sequence: _eventSequence,
        owner: CCBackendEntryOwner.managed,
        navigationId: request.navigationId,
        routeId: request.routeId,
        uri: request.uri,
        placement: _concretePlacement(request.placement),
        location: request.uri.toString(),
        origin: request.origin,
        source: request.source,
      ),
    );
  }

  /// Resolves the Host alias for diagnostics without losing structural placement.
  CCRoutePlacement _concretePlacement(CCRoutePlacement placement) =>
      CCRoutePlacement(
        hostId: _host.id,
        shellId: placement.shellId,
        parentRouteId: placement.parentRouteId,
        navigatorOutlet: placement.navigatorOutlet,
      );

  /// Publishes a managed top only after the Navigator confirms that Route.
  void _emitTop(_CCManagedEntry entry, {_CCManagedEntry? previous}) {
    final request = entry.request;
    _emit(
      CCNavigationBackendEvent(
        kind: CCNavigationBackendEventKind.topChanged,
        timestamp: DateTime.now(),
        backendEntryId: entry.backendEntryId,
        backendOperationId: '$_eventNamespace-${++_eventSequence}',
        previousBackendEntryId: previous?.backendEntryId,
        hostId: _host.id,
        navigatorOutlet: request.placement.navigatorOutlet,
        sequence: _eventSequence,
        owner: CCBackendEntryOwner.managed,
        navigationId: request.navigationId,
        routeId: request.routeId,
        uri: request.uri,
        placement: _concretePlacement(request.placement),
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
    foreignRouteBridge._dispose();
    _routes.clear();
    _popGuardEvaluator = null;
    _scopedPopGuardEvaluator = null;
    _removeAllManagedPopGuards();
    _renderedRoutes.clear();
    _externalPops.clear();
    for (final exit in _routeExits.values.toList()) {
      exit.complete();
    }
    _routeExits.clear();
    for (final exit in _shellRenderExits.values.toList()) {
      exit.complete();
    }
    _shellRenderExits.clear();
    _immediateRemovals.clear();
    _foreignAnchors.clear();
    _pendingRemovalResults.clear();
    for (final operation in _pendingPops.values) {
      operation.retire();
    }
    _pendingPops.clear();
    _runtimeGuardedPopRoutes.clear();
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
    required Map<String, int> shellAnchors,
    required this.focusedOutlet,
    required Set<String> visibleOutlets,
    required Map<String, String> activeOutletsByShell,
  }) : shellAnchors = Map.unmodifiable(shellAnchors),
       entries = List.unmodifiable(entries),
       visibleOutlets = Set.unmodifiable(visibleOutlets),
       activeOutletsByShell = Map.unmodifiable(activeOutletsByShell);

  /// Creates the unattached empty state.
  const _CCManagedNavigationState.empty()
    : revision = 0,
      entries = const [],
      shellAnchors = const {},
      focusedOutlet = 'root',
      visibleOutlets = const {'root'},
      activeOutletsByShell = const {};

  /// Monotonic version incremented for every committed mutation.
  final int revision;

  /// Managed root Entries in bottom-to-top order.
  final List<_CCManagedEntry> entries;

  /// Retained structural root layers, each owned by its Shell's live Entries.
  final Map<String, int> shellAnchors;

  /// Uppermost retained Shell, independently of root overlay coverage.
  String? get activeShellId => topShell(shellAnchors);

  /// Selects the latest structural layer without relying on insertion order.
  static String? topShell(Map<String, int> anchors) {
    String? selected;
    var order = -1;
    for (final anchor in anchors.entries) {
      if (anchor.value > order) {
        selected = anchor.key;
        order = anchor.value;
      }
    }
    return selected;
  }

  /// Global order used to place the active Shell among root overlays.
  int? get shellAnchorOrder => shellAnchors[activeShellId];

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
  _CCManagedEntry(CCNavigationRequest request, {required this.order})
    : request = request.parentStack.isEmpty
          ? request
          : request.withParentStack(const []),
      backendEntryId = 'managed-${request.navigationId}',
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

  /// Prevents a retained RouterConfig remount from replaying startup as a Go.
  bool _initialRoutePathApplied = false;

  /// Owns only the pending location; a newer location cancels it before dispatch.
  CCCancellationToken? _routeInformationCancellation;

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
    if (_initialRoutePathApplied) return setNewRoutePath(configuration);
    await _applyRouteInformation(
      configuration,
      external: initialLocationIsExternal,
    );
    _initialRoutePathApplied = true;
  }

  @override
  /// Applies browser and platform locations through one Runtime Go transaction.
  Future<void> setNewRoutePath(CCManagedRouteConfiguration configuration) =>
      _applyRouteInformation(
        configuration,
        external: !configuration.trustedHistory,
      );

  /// Supersedes policy/defer waits even when the new URI is already current.
  Future<void> _applyRouteInformation(
    CCManagedRouteConfiguration configuration, {
    required bool external,
  }) async {
    _routeInformationCancellation?.cancel();
    _routeInformationCancellation = null;
    if (_disposed || adapter._disposed) return;
    if (adapter._currentUri == configuration.uri &&
        adapter.requests.isNotEmpty) {
      return;
    }
    final cancellation = CCCancellationToken();
    _routeInformationCancellation = cancellation;
    try {
      await CCRouterHostBinding.openRouteInformation(
        configuration.uri,
        external: external,
        placementOverride: CCRoutePlacement(hostId: adapter.hostId),
        cancellation: cancellation,
      );
    } on CCRouteCancelledError {
      if (!cancellation.isCancelled && !_disposed && CCRouter.isInitialized)
        rethrow;
    } finally {
      if (identical(_routeInformationCancellation, cancellation)) {
        _routeInformationCancellation = null;
      }
    }
  }

  @override
  /// Routes system Back through Runtime PopGuard and ownership coordination.
  Future<bool> popRoute() async => (await CCRouter.navigator.maybePopOutcome(
    trigger: CCPopTrigger.system,
  )).handled;

  @override
  /// Builds one declarative root Navigator from the latest immutable state.
  Widget build(BuildContext context) =>
      _CCManagedNavigatorRenderer(adapter: adapter, outlet: 'root');

  /// Rebuilds Router and reports a possible URL projection change.
  void _onStateChanged() {
    if (!_disposed) notifyListeners();
  }

  @override
  /// Detaches from Adapter state before releasing ChangeNotifier listeners.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _routeInformationCancellation?.cancel();
    _routeInformationCancellation = null;
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
    // The structural Route may rebuild during its exit after Runtime shutdown.
    // Its Store has retired; never call a Host binding with cleared metadata.
    if (widget.adapter._disposed) return const SizedBox.shrink();
    final exit = widget.adapter._shellRenderExits[ModalRoute.of(context)];
    // Re-entry transfers these Outlet keys to the new structural Route. Keep
    // this tombstone until the old outer Route completes so it cannot rebuild
    // the live Store and become a second Navigator owner.
    if (exit?.projectionRetired ?? false) return const SizedBox.shrink();
    final shell = widget.adapter._shells[widget.shellId]!;
    final binding = widget.adapter._shellBindings[widget.shellId]!;
    final activeOutlet =
        exit?.activeOutlet ??
        widget.adapter._state.activeOutletsByShell[widget.shellId] ??
        shell.initialOutlet;
    final navigators = <String, Widget>{
      for (final outlet in shell.outlets)
        outlet: _CCManagedOutletNavigator(
          adapter: widget.adapter,
          outlet: outlet,
          frozenPages: exit?.pages?[outlet],
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
        hasEntries: (outlet) =>
            widget.adapter._shellHasEntries(shell.shellId, outlet),
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
    baseBuilder: widget.baseBuilder,
  );
}

/// Builds one Navigator while keeping focus separate from route placement.
final class _CCManagedOutletNavigator extends StatelessWidget {
  /// Creates a renderer for one exact [outlet].
  const _CCManagedOutletNavigator({
    required this.adapter,
    required this.outlet,
    this.baseBuilder,
    this.frozenPages,
  });

  /// Store projected by the child Navigator.
  final CCManagedNavigationAdapter adapter;

  /// Host-registered Outlet identity.
  final String outlet;

  /// Host-local bottom surface, without managed identity or Scope ownership.
  final WidgetBuilder? baseBuilder;

  /// Projection retained only while its outer Shell is visibly exiting.
  final List<Page<Object?>>? frozenPages;

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
        child: _CCManagedNavigatorRenderer(
          adapter: adapter,
          outlet: outlet,
          baseBuilder: baseBuilder,
          frozenPages: frozenPages,
        ),
      ),
    ),
  );
}

/// Moves renderer ownership with its Navigator during same-frame reparenting.
///
/// A private key type prevents collisions with Host-created GlobalObjectKeys.
final class _CCManagedRendererKey
    extends GlobalObjectKey<_CCManagedNavigatorRendererState> {
  /// Uses the exact Host Navigator key as a stable, payload-free identity.
  const _CCManagedRendererKey(super.value);
}

/// Owns one actual Navigator generation, independently of retained Entries.
final class _CCManagedNavigatorRenderer extends StatefulWidget {
  /// Projects one Outlet; root additionally supplies Host observers and Shells.
  _CCManagedNavigatorRenderer({
    required this.adapter,
    required this.outlet,
    this.baseBuilder,
    this.frozenPages,
  }) : super(key: _CCManagedRendererKey(adapter._host.navigatorKeyFor(outlet)));

  /// Logical Stack owner, which can outlive this mounted renderer.
  final CCManagedNavigationAdapter adapter;

  /// Exact partition rendered by this Navigator.
  final String outlet;

  /// Optional non-business base for a named Outlet.
  final WidgetBuilder? baseBuilder;

  /// Outgoing Shell projection, independent of the already committed Store.
  final List<Page<Object?>>? frozenPages;

  @override
  /// Creates deterministic attach/detach ownership for this renderer.
  State<_CCManagedNavigatorRenderer> createState() =>
      _CCManagedNavigatorRendererState();
}

/// Fences observer callbacks across unmount, replacement and same-frame remount.
final class _CCManagedNavigatorRendererState
    extends State<_CCManagedNavigatorRenderer> {
  /// Observer identity doubles as the generation token.
  late _CCManagedNavigatorObserver _observer;

  @override
  /// Attaches before Flutter can mount any child Route.
  void initState() {
    super.initState();
    _observer = widget.adapter._attachRenderer(widget.outlet);
  }

  @override
  /// Moves ownership if a Host reuses this Widget position for another Outlet.
  void didUpdateWidget(covariant _CCManagedNavigatorRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.adapter, widget.adapter) ||
        oldWidget.outlet != widget.outlet) {
      oldWidget.adapter._detachRenderer(_observer);
      _observer = widget.adapter._attachRenderer(widget.outlet);
    }
  }

  @override
  /// Drops all rendering-only ownership, preserving business Entries/results.
  void dispose() {
    widget.adapter._detachRenderer(_observer);
    super.dispose();
  }

  @override
  /// Builds Pages from the current logical revision with this generation.
  Widget build(BuildContext context) => Navigator(
    key: widget.adapter._host.navigatorKeyFor(widget.outlet),
    pages:
        widget.frozenPages ??
        (widget.outlet == 'root'
            ? widget.adapter._buildRootPages()
            : widget.adapter._buildOutletPages(
                widget.outlet,
                baseBuilder: widget.baseBuilder,
              )),
    observers: widget.outlet == 'root'
        ? widget.adapter._rootObservers
        : [_observer],
    onDidRemovePage: widget.adapter._didRemovePage,
  );
}

/// Internal page displayed only while the first Runtime location is unresolved.
final class _CCManagedPlaceholderPage extends Page<Object?> {
  /// Creates the stable non-business placeholder Page.
  const _CCManagedPlaceholderPage({super.key, this.builder});

  /// Optional local Host surface; null produces the startup placeholder.
  final WidgetBuilder? builder;

  @override
  /// Creates a zero-duration Route with no managed Entry or payload.
  Route<Object?> createRoute(BuildContext context) => PageRouteBuilder<Object?>(
    settings: this,
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    pageBuilder: (context, _, _) =>
        (ModalRoute.of(context)!.settings as _CCManagedPlaceholderPage).builder
            ?.call(context) ??
        const SizedBox.shrink(),
  );
}

/// Correlates one maybePop continuation with the actual Navigator callback.
final class _CCManagedPopOperation {
  /// Creates an uncommitted claim for a single live Navigator Route.
  _CCManagedPopOperation();

  /// Correlates Flutter's async maybePop continuation with its actual observer.
  static final Object zoneKey = Object();

  /// True only when this operation's Zone produced the exact didPop callback.
  bool didPop = false;

  /// Managed identity observed at commit, including a Shell's selected child.
  String? removedBackendEntryId;

  /// Ends only the framework wait if Flutter's willPop outlives its renderer.
  final Completer<bool> retired = Completer<bool>();

  /// Consumes teardown as handled without claiming an unconfirmed removal.
  void retire() {
    if (!retired.isCompleted) retired.complete(true);
  }
}

/// Holds an outgoing Shell's Pages until its outer Route finishes rendering.
final class _CCManagedShellRenderExit {
  /// Captures existing Pages without allocating new Managed Entries or Scopes.
  _CCManagedShellRenderExit({
    required this.shellId,
    required this.activeOutlet,
    required this.pages,
    required VoidCallback onComplete,
  }) : _onComplete = onComplete;

  /// Identifies the Outlet owner whose keys must transfer on Shell re-entry.
  final String shellId;

  /// Suppresses an outgoing surface after a new instance claims its Outlets.
  bool projectionRetired = false;

  /// Keeps the selected branch stable while the active Store reveals its parent.
  final String activeOutlet;

  /// Exact existing child Pages; cleared on Route completion or renderer detach.
  Map<String, List<Page<Object?>>>? pages;

  /// Detachable bookkeeping callback, never retained after teardown.
  VoidCallback? _onComplete;

  /// Drops old Pages while retaining the tombstone through outer completion.
  void retireProjection() {
    projectionRetired = true;
    pages = null;
  }

  /// Releases all payload-bearing Pages before dropping Adapter bookkeeping.
  void complete() {
    pages = null;
    final onComplete = _onComplete;
    _onComplete = null;
    onComplete?.call();
  }
}

/// Detachable render-exit signal that never retains a Flutter Route or payload.
final class _CCManagedRouteExit {
  /// Registers Adapter bookkeeping cleanup without retaining it after exit.
  _CCManagedRouteExit({required this.outlet, required VoidCallback onComplete})
    : _onComplete = onComplete;

  /// Renderer partition whose teardown must also finish this wait.
  final String outlet;

  /// Callback removed before any subscriber runs, including Adapter disposal.
  VoidCallback? _onComplete;

  /// Runtime callbacks explicitly detachable before a delayed Flutter exit.
  final Set<VoidCallback> _listeners = {};

  /// Adds one subscriber while rendering remains pending.
  VoidCallback? addListener(VoidCallback listener) {
    if (_onComplete == null) return null;
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  /// Releases all ownership once and then signals waiting Scope closures.
  void complete() {
    final onComplete = _onComplete;
    if (onComplete == null) return;
    _onComplete = null;
    onComplete();
    final listeners = _listeners.toList();
    _listeners.clear();
    for (final listener in listeners) {
      listener();
    }
  }
}

/// Keeps Route content synchronized even when Flutter caches a covered Page.
final class _CCManagedRouteContent extends StatefulWidget {
  /// Observes only Store revision; business content remains in current settings.
  const _CCManagedRouteContent({required this.adapter});

  /// Store that retires anchor content while Flutter owns ordinary exit timing.
  final CCManagedNavigationAdapter adapter;

  @override
  /// Creates a listener with the same lifetime as the rendered Route subtree.
  State<_CCManagedRouteContent> createState() => _CCManagedRouteContentState();
}

/// Releases its Store subscription when Flutter removes the Route subtree.
final class _CCManagedRouteContentState extends State<_CCManagedRouteContent> {
  @override
  /// Subscribes once; the owning Adapter is immutable for this Route.
  void initState() {
    super.initState();
    widget.adapter._addStateListener(_changed);
  }

  /// Rebuilds the dynamic Page content after its managed ownership changes.
  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  /// Preserves Flutter's outgoing subtree while dropping retired anchor content.
  Widget build(BuildContext context) => _managedPageChild(context);

  @override
  /// Removes the exact callback before releasing the content State.
  void dispose() {
    widget.adapter._removeStateListener(_changed);
    super.dispose();
  }
}

/// Keeps outgoing animation content until Flutter disposes its Route subtree.
///
/// Store removal ends the result immediately; the render-exit binding keeps
/// its Scope available until the reverse transition ends. Retained foreign
/// anchors and disposed backends clear content early because they can outlive
/// every business Entry.
Widget _managedPageChild(BuildContext context) {
  final settings = ModalRoute.of(context)!.settings;
  final adapter = switch (settings) {
    final _CCManagedPage page => page.adapter,
    final _CCManagedGuardedPage page => page.adapter,
    _ => null,
  };
  if (adapter == null ||
      adapter._disposed ||
      adapter._foreignAnchors.values.any(
        (anchor) => anchor.page.key == (settings as Page).key,
      )) {
    return const SizedBox.shrink();
  }
  return switch (settings) {
    final _CCManagedPage page => page.child,
    final _CCManagedGuardedPage page => page.child,
    _ => const SizedBox.shrink(),
  };
}

/// Private Page identity distinguishes owned entries from arbitrary copied keys.
final class _CCManagedPage extends Page<Object?> {
  /// Creates one immutable destination projection or empty foreign-route anchor.
  const _CCManagedPage({
    required this.adapter,
    required this.child,
    required this.presentation,
    this.predictiveBackHandler,
    super.key,
    super.name,
    super.arguments,
    super.restorationId,
  });

  /// Current content; empty anchors retain neither payload nor Route Scope.
  final Widget child;

  /// Owning Store distinguishing live/outgoing content from empty anchors.
  final CCManagedNavigationAdapter adapter;

  /// Backend-neutral rendering contract for this entry.
  final CCRoutePresentation presentation;

  /// Optional Host coordinator for default Android Material routes.
  final CCFlutterPredictiveBackHandler? predictiveBackHandler;

  @override
  /// Builds through shared presentation logic while reading updated Page content.
  Route<Object?> createRoute(BuildContext context) =>
      CCFlutterRouteFactory.createRoute<Object?>(
        context: context,
        child: _CCManagedRouteContent(adapter: adapter),
        presentation: presentation,
        settings: this,
        predictiveBackHandler: predictiveBackHandler,
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
      return CCFlutterRouteFactory.createRoute<Object?>(
        context: context,
        child: _CCManagedRouteContent(adapter: adapter),
        presentation: presentation,
        settings: this,
        predictiveBackHandler: predictiveBackHandler,
      );
    }
    if (useCupertino) {
      return _CCManagedGuardedCupertinoPageRoute<Object?>(
        settings: this,
        fullscreenDialog: value.fullscreenDialog,
        builder: (_) => _CCManagedRouteContent(adapter: adapter),
        preparePopGesture: adapter._prepareManagedPopGesture,
      );
    }
    return _CCManagedGuardedMaterialPageRoute<Object?>(
      settings: this,
      fullscreenDialog: value.fullscreenDialog,
      builder: (_) => _CCManagedRouteContent(adapter: adapter),
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

  /// Live foreign identities, released on exact Pop/Remove/Replace or disposal.
  final Map<Route<dynamic>, String> foreignEntries = {};

  /// Routes owned by this renderer, released even without didPop/didRemove.
  final Set<Route<dynamic>> _liveRoutes = {};

  /// Prevents delayed Flutter callbacks from republishing a retired generation.
  bool _retired = false;

  /// Whether a Route is an implementation-owned anchor rather than a popup.
  bool _isStructural(Route<dynamic> route) =>
      route.settings is _CCManagedShellPage ||
      route.settings is _CCManagedPlaceholderPage;

  /// Reports a foreign lifecycle transition without settings or payload data.
  void _emitForeign(CCNavigationBackendEventKind kind, Route<dynamic> route) {
    final id = foreignEntries[route];
    if (id == null || adapter._disposed) return;
    adapter._emit(
      CCNavigationBackendEvent(
        kind: kind,
        timestamp: DateTime.now(),
        backendEntryId: id,
        backendOperationId:
            '${adapter._eventNamespace}-${++adapter._eventSequence}',
        sequence: adapter._eventSequence,
        hostId: adapter.hostId,
        navigatorOutlet: outlet,
        owner: CCBackendEntryOwner.foreign,
        placement: CCRoutePlacement(
          hostId: adapter.hostId,
          navigatorOutlet: outlet,
        ),
      ),
    );
  }

  /// Mounts only real application Routes in the foreign ledger.
  void _mount(Route<dynamic> route) {
    adapter._didMountRoute(route);
    if (adapter._disposed ||
        adapter._entryForRoute(route) != null ||
        _isStructural(route))
      return;
    foreignEntries[route] =
        'managed-foreign-${adapter.hostId}-${++adapter._foreignSequence}';
    _emitForeign(CCNavigationBackendEventKind.push, route);
  }

  @override
  /// Associates newly rendered managed Page Routes with their Entry identity.
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_retired) return;
    _liveRoutes.add(route);
    _mount(route);
    topRoute = route;
  }

  @override
  /// Re-closes a gesture-time PopEntry after commit or cancellation.
  void didStopUserGesture() {
    if (_retired) return;
    adapter._didStopUserGesture(topRoute);
  }

  @override
  /// Releases a popped Route correlation and remembers the revealed top.
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_retired) return;
    final operation = adapter._pendingPops[route];
    if (operation != null &&
        identical(Zone.current[_CCManagedPopOperation.zoneKey], operation)) {
      operation.didPop = true;
      operation.removedBackendEntryId =
          (adapter._entryForRoute(route) ??
                  adapter._topEntryForShellRoute(route))
              ?.backendEntryId;
    }
    adapter._didPopRoute(route);
    _emitForeign(CCNavigationBackendEventKind.pop, route);
    foreignEntries.remove(route);
    adapter._releaseForeignAnchors();
    adapter._didUnmountRoute(route);
    _liveRoutes.remove(route);
    topRoute = previousRoute;
  }

  @override
  /// Releases an exactly removed Route correlation.
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_retired) return;
    _emitForeign(CCNavigationBackendEventKind.remove, route);
    foreignEntries.remove(route);
    adapter._releaseForeignAnchors();
    adapter._didUnmountRoute(route);
    _liveRoutes.remove(route);
    if (identical(topRoute, route)) topRoute = previousRoute;
  }

  @override
  /// Rebinds a replacement Route while releasing its predecessor.
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (_retired) return;
    if (oldRoute != null) {
      _emitForeign(CCNavigationBackendEventKind.remove, oldRoute);
      foreignEntries.remove(oldRoute);
      adapter._didUnmountRoute(oldRoute);
      _liveRoutes.remove(oldRoute);
    }
    if (newRoute != null) {
      _liveRoutes.add(newRoute);
      _mount(newRoute);
    }
    adapter._releaseForeignAnchors();
    if (identical(topRoute, oldRoute)) topRoute = newRoute;
  }

  @override
  /// Tracks Flutter's confirmed current Route, including foreign Popups.
  void didChangeTop(Route<dynamic> topRoute, Route<dynamic>? previousTopRoute) {
    super.didChangeTop(topRoute, previousTopRoute);
    if (_retired) return;
    this.topRoute = topRoute;
    if (adapter._disposed) return;
    final entry = adapter._entryForRoute(topRoute);
    if (entry != null) {
      adapter._emitTop(
        entry,
        previous: adapter._entryForRoute(previousTopRoute),
      );
    }
    _emitForeign(CCNavigationBackendEventKind.topChanged, topRoute);
    adapter._emitVisibleOutlets();
    CCPageLifecycleHostBridge.didChangeTop(
      hostId: adapter.hostId,
      outlet: outlet,
      topRoute: topRoute,
      previousTopRoute: previousTopRoute,
    );
    if (outlet == 'root') {
      adapter._predictiveBackBridge?.observeNavigatorTopChange();
    }
  }

  /// Ends rendering ownership without completing any still-managed result.
  void retire() {
    if (_retired) return;
    _retired = true;
    final top = topRoute;
    if (top != null) {
      CCPageLifecycleHostBridge.didDetachOutlet(
        hostId: adapter.hostId,
        outlet: outlet,
        previousTopRoute: top,
      );
    }
    for (final route in _liveRoutes) {
      _emitForeign(CCNavigationBackendEventKind.remove, route);
      adapter._didUnmountRoute(route);
    }
    clear();
    for (final exit
        in adapter._routeExits.values
            .where((exit) => exit.outlet == outlet)
            .toList()) {
      exit.complete();
    }
    adapter._releaseForeignAnchors();
  }

  /// Clears any Route retained while the owning Navigator is tearing down.
  void clear() {
    topRoute = null;
    foreignEntries.clear();
    _liveRoutes.clear();
  }
}
