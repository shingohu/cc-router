import 'package:flutter/widgets.dart';

part 'page_lifecycle.dart';

/// Identifies one Flutter navigation Host lifecycle transition.
///
/// Host lifecycle is intentionally separate from managed route visibility.
/// Use it for application-window foreground/background state and Host resource
/// ownership; do not interpret it as a page exposure event.
enum CCNavigationHostLifecycleState {
  /// The Host was attached to a [CCRouterApp] widget tree.
  mounted,

  /// Flutter reports that the Host is active and receiving user input.
  resumed,

  /// Flutter reports that the Host is temporarily inactive.
  inactive,

  /// Flutter reports that every view belonging to the Host is hidden.
  hidden,

  /// Flutter reports that the Host is not currently visible to the user.
  paused,

  /// Flutter reports that the Host is detached from its engine view.
  detached,

  /// The Host was removed from its [CCRouterApp] widget tree.
  unmounted,
}

/// Immutable observation emitted when a Flutter navigation Host changes state.
///
/// Host integrations use this event for window-level telemetry and resource
/// suspension. Route exposure must instead use `CCRouteVisibilityEvent`.
final class CCNavigationHostLifecycleEvent {
  /// Creates one lifecycle observation for [hostId].
  const CCNavigationHostLifecycleEvent({
    required this.hostId,
    required this.state,
    required this.timestamp,
  });

  /// Stable identity of the Host that changed state.
  final String hostId;

  /// New lifecycle state of the Host.
  final CCNavigationHostLifecycleState state;

  /// Time at which the Flutter Host observed the transition.
  final DateTime timestamp;
}

/// Receives one immutable Flutter navigation Host lifecycle observation.
typedef CCNavigationHostLifecycleListener =
    void Function(CCNavigationHostLifecycleEvent event);

/// Identifies the Flutter navigation host associated with one application
/// window.
///
/// The Host owns a stable set of Navigator Outlet keys shared by
/// [CCRouterApp], the application Router, and its navigation Adapter. It does
/// not retain a global [BuildContext]. Create one Host per application Window;
/// a single Host cannot be mounted by two [CCRouterApp] instances at once.
final class CCNavigationHost {
  /// Creates a Host with a stable [id] and immutable Navigator Outlet keys.
  ///
  /// [navigatorKey] identifies the required `root` Outlet. Additional keys are
  /// supplied by [navigatorKeys]. Supplying `root` in both inputs is valid only
  /// when both values are the same object. Outlet names and key identities must
  /// be unique so backend events cannot be attributed to two stacks.
  CCNavigationHost({
    this.id = 'default',
    GlobalKey<NavigatorState>? navigatorKey,
    Map<String, GlobalKey<NavigatorState>> navigatorKeys = const {},
  }) : _navigatorKeys = _buildNavigatorKeys(navigatorKey, navigatorKeys) {
    if (id.isEmpty) {
      throw ArgumentError.value(id, 'id', 'Host ID cannot be empty.');
    }
  }

  /// Stable host identity used to associate Adapter and Outlet state.
  final String id;

  /// Immutable Navigator keys indexed by stable Outlet name.
  final Map<String, GlobalKey<NavigatorState>> _navigatorKeys;

  /// Host lifecycle observers owned by composition-root integrations.
  final Set<CCNavigationHostLifecycleListener> _lifecycleListeners = {};

  /// Current Host lifecycle state.
  CCNavigationHostLifecycleState _lifecycleState =
      CCNavigationHostLifecycleState.unmounted;

  /// Exact Widget State currently owning this Host attachment.
  Object? _mountOwner;

  /// Root Navigator key consumed by the application Router and Adapter.
  GlobalKey<NavigatorState> get navigatorKey => _navigatorKeys['root']!;

  /// Immutable Navigator keys indexed by stable Outlet name.
  ///
  /// Pass this exact map to a legacy Adapter integration only when that Adapter
  /// cannot consume [CCNavigationHost] directly. Callers must not copy keys from
  /// another Host or mutate the returned map.
  Map<String, GlobalKey<NavigatorState>> get navigatorKeys => _navigatorKeys;

  /// Current lifecycle state reported by [CCRouterApp].
  CCNavigationHostLifecycleState get lifecycleState => _lifecycleState;

  /// Returns whether this Host declares [outlet].
  bool containsOutlet(String outlet) => _navigatorKeys.containsKey(outlet);

  /// Returns the Navigator key registered for [outlet].
  ///
  /// Host and Adapter setup code use this to bind Shell or Pane Navigators.
  /// An unknown Outlet is a configuration error and throws [ArgumentError].
  GlobalKey<NavigatorState> navigatorKeyFor(String outlet) {
    final key = _navigatorKeys[outlet];
    if (key == null) {
      throw ArgumentError.value(
        outlet,
        'outlet',
        'Navigator Outlet is not registered by Host "$id".',
      );
    }
    return key;
  }

  /// Subscribes to Host lifecycle changes and returns a removal callback.
  ///
  /// Use this at the application composition root for window-level telemetry
  /// or resource suspension. Listener failures are isolated from Flutter's
  /// lifecycle dispatch and from other listeners.
  void Function() addLifecycleListener(
    CCNavigationHostLifecycleListener listener,
  ) {
    _lifecycleListeners.add(listener);
    return () => _lifecycleListeners.remove(listener);
  }

  /// Attaches this Host to one widget tree and rejects duplicate ownership.
  void _mount(Object owner) {
    if (_mountOwner != null && !identical(_mountOwner, owner)) {
      throw FlutterError(
        'CCNavigationHost "$id" is already mounted by another CCRouterApp.',
      );
    }
    if (identical(_mountOwner, owner)) return;
    _mountOwner = owner;
    _emitLifecycle(CCNavigationHostLifecycleState.mounted);
  }

  /// Converts one Flutter application lifecycle state into a Host event.
  void _updateLifecycle(AppLifecycleState state) {
    if (_mountOwner == null) return;
    _emitLifecycle(switch (state) {
      AppLifecycleState.resumed => CCNavigationHostLifecycleState.resumed,
      AppLifecycleState.inactive => CCNavigationHostLifecycleState.inactive,
      AppLifecycleState.hidden => CCNavigationHostLifecycleState.hidden,
      AppLifecycleState.paused => CCNavigationHostLifecycleState.paused,
      AppLifecycleState.detached => CCNavigationHostLifecycleState.detached,
    });
  }

  /// Detaches this Host from its widget tree without disposing Navigator keys.
  void _unmount(Object owner) {
    if (!identical(_mountOwner, owner)) return;
    _mountOwner = null;
    _emitLifecycle(CCNavigationHostLifecycleState.unmounted);
  }

  /// Publishes one lifecycle transition while isolating listener failures.
  void _emitLifecycle(CCNavigationHostLifecycleState state) {
    _lifecycleState = state;
    final event = CCNavigationHostLifecycleEvent(
      hostId: id,
      state: state,
      timestamp: DateTime.now(),
    );
    for (final listener in _lifecycleListeners.toList()) {
      try {
        listener(event);
      } catch (_) {
        // Host telemetry must never interrupt Flutter lifecycle delivery.
      }
    }
  }

  /// Builds the immutable Outlet registry and validates identity ambiguity.
  static Map<String, GlobalKey<NavigatorState>> _buildNavigatorKeys(
    GlobalKey<NavigatorState>? root,
    Map<String, GlobalKey<NavigatorState>> outlets,
  ) {
    final declaredRoot = outlets['root'];
    if (root != null &&
        declaredRoot != null &&
        !identical(root, declaredRoot)) {
      throw ArgumentError.value(
        outlets,
        'navigatorKeys',
        'The root Outlet is declared with two different Navigator keys.',
      );
    }
    final keys = <String, GlobalKey<NavigatorState>>{
      ...outlets,
      'root':
          root ??
          declaredRoot ??
          GlobalKey<NavigatorState>(debugLabel: 'CCRouter.root'),
    };
    final identities = <GlobalKey<NavigatorState>>{};
    for (final entry in keys.entries) {
      if (entry.key.isEmpty) {
        throw ArgumentError.value(
          entry.key,
          'navigatorKeys',
          'Navigator Outlet name cannot be empty.',
        );
      }
      if (!identities.add(entry.value)) {
        throw ArgumentError.value(
          entry.key,
          'navigatorKeys',
          'One Navigator key cannot represent multiple Outlets.',
        );
      }
    }
    return Map.unmodifiable(keys);
  }
}

/// Optional Flutter integration Host for CCRouter.
///
/// Simple applications may bind an Adapter directly to `MaterialApp.router`.
/// Use this Host when the application needs a root navigation host, lifecycle
/// observation, or a context-bound foundation for future Shell and Outlet
/// resolution. This widget is not a second `MaterialApp`, does not initialize
/// or shut down [CCRouter], and never stores a global [BuildContext].
final class CCRouterApp extends StatefulWidget {
  /// Creates a Host around an existing Flutter application widget tree.
  const CCRouterApp({
    required this.child,
    this.host,
    this.onLifecycleChanged,
    super.key,
  });

  /// Application widget, commonly `MaterialApp.router`.
  final Widget child;

  /// Optional externally owned host, useful when an Adapter needs its key.
  /// When omitted, the Host creates and retains one for this widget State.
  final CCNavigationHost? host;

  /// Optional callback for host-level Flutter lifecycle changes.
  ///
  /// The callback is observational only; Runtime and Session ownership remain
  /// with `CCRouter.initialize`, `CCRouter.closeSession`, and `CCRouter.shutdown`.
  final ValueChanged<AppLifecycleState>? onLifecycleChanged;

  /// Returns the nearest navigation host and establishes an inherited
  /// dependency on it.
  ///
  /// Use this from Adapter or Outlet integration code. Business route calls
  /// should continue using `CCRouter.navigator` instead of reading the host.
  static CCNavigationHost of(BuildContext context) {
    final host = maybeOf(context);
    if (host == null) {
      throw FlutterError.fromParts([
        ErrorSummary('No CCRouterApp host found.'),
        ErrorDescription(
          'Wrap the application with CCRouterApp before resolving a '
          'navigation host.',
        ),
      ]);
    }
    return host;
  }

  /// Returns the nearest navigation host, or null when no Host is mounted.
  static CCNavigationHost? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_CCRouterHostScope>()?.host;

  @override
  /// Creates the lifecycle-aware Host State.
  State<CCRouterApp> createState() => _CCRouterAppState();
}

/// State that bridges Flutter lifecycle notifications to the optional Host
/// callback without taking ownership of the application Runtime.
final class _CCRouterAppState extends State<CCRouterApp>
    with WidgetsBindingObserver {
  late CCNavigationHost _host;

  @override
  /// Creates the internal Host and starts observing Flutter lifecycle events.
  void initState() {
    super.initState();
    _host = widget.host ?? CCNavigationHost();
    _host._mount(this);
    CCPageLifecycleHostBridge._attachHost(
      hostId: _host.id,
      owner: this,
      applicationState: WidgetsBinding.instance.lifecycleState,
    );
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  /// Rebinds the State to a newly supplied externally owned Host.
  void didUpdateWidget(covariant CCRouterApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextHost = widget.host;
    if (nextHost == null && oldWidget.host == null) return;
    if (nextHost != null && identical(_host, nextHost)) return;
    CCPageLifecycleHostBridge._detachHost(hostId: _host.id, owner: this);
    _host._unmount(this);
    _host = nextHost ?? CCNavigationHost();
    _host._mount(this);
    CCPageLifecycleHostBridge._attachHost(
      hostId: _host.id,
      owner: this,
      applicationState: WidgetsBinding.instance.lifecycleState,
    );
  }

  @override
  /// Forwards the lifecycle event to the optional observational callback.
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _host._updateLifecycle(state);
    CCPageLifecycleHostBridge._updateApplicationState(
      hostId: _host.id,
      state: state,
    );
    widget.onLifecycleChanged?.call(state);
  }

  @override
  /// Stops lifecycle observation without disposing the application Runtime.
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    CCPageLifecycleHostBridge._detachHost(hostId: _host.id, owner: this);
    _host._unmount(this);
    super.dispose();
  }

  @override
  /// Provides the Host scope to the existing application widget tree.
  Widget build(BuildContext context) => _CCRouterHostScope(
    host: _host,
    child: CCPageLifecycleHostBridge._scope(
      hostId: _host.id,
      child: widget.child,
    ),
  );
}

/// Inherited scope that makes one Window's navigation Host discoverable.
final class _CCRouterHostScope extends InheritedWidget {
  /// Creates an inherited Host scope around [child].
  const _CCRouterHostScope({required this.host, required super.child});

  /// Host made available to descendant Adapter and Outlet integration code.
  final CCNavigationHost host;

  @override
  /// Notifies descendants only when the Host identity changes.
  bool updateShouldNotify(_CCRouterHostScope oldWidget) =>
      !identical(host, oldWidget.host);
}
