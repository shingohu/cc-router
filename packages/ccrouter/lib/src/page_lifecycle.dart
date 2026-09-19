part of 'app.dart';

/// Optional page lifecycle callbacks for a `StatefulWidget` destination.
///
/// Use this mixin when a [PageRoute] inside an observed [CCRouterApp] Host needs
/// to react when it becomes or stops being the current page in its Navigator
/// Outlet, or when the foreground application containing that current page
/// moves between the foreground and background. This includes managed and
/// foreign PageRoutes observed by the Host. The mixin is inert outside a
/// [CCRouterApp] lifecycle scope, which keeps component widget tests and
/// standalone previews usable without constructing a navigation host.
///
/// Widget construction and disposal remain Flutter concerns: override
/// [State.initState] and [State.dispose] instead of treating these callbacks as
/// page creation or destruction notifications.
mixin CCPageLifecycleMixin<T extends StatefulWidget> on State<T> {
  /// Shared subscriber that binds this State to its current managed PageRoute.
  late final _CCPageLifecycleConsumer _ccPageLifecycleConsumer =
      _CCPageLifecycleConsumer(
        onPageShow: onPageShow,
        onPageHide: onPageHide,
        onForeground: onForeground,
        onBackground: onBackground,
      );

  /// Called when this PageRoute becomes the current page in an active Outlet.
  ///
  /// The callback is repeated when a covering page or PopupRoute is removed.
  /// It describes primary route position, not physical pixel visibility; a
  /// transparent route or bottom sheet above this page still causes a hide.
  @protected
  void onPageShow() {}

  /// Called when this PageRoute stops being current in its active Outlet.
  ///
  /// Covering the page, switching away from its Shell Outlet, or permanently
  /// removing it can all cause this callback. Use Runtime navigation
  /// observation rather than this callback when analytics must distinguish a
  /// temporary cover from final RouteEntry removal.
  @protected
  void onPageHide() {}

  /// Called when the application returns to the foreground while this page is
  /// current.
  ///
  /// Initial page display is represented only by [onPageShow]; this callback is
  /// emitted for a later application lifecycle transition to `resumed`.
  @protected
  void onForeground() {}

  /// Called when the foreground application moves to the background while this
  /// page is current.
  ///
  /// The PageRoute remains current, so this transition does not also emit
  /// [onPageHide]. Transient Flutter `inactive` states are not treated as
  /// background transitions.
  @protected
  void onBackground() {}

  @override
  /// Rebinds this State when its Host or enclosing ModalRoute changes.
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ccPageLifecycleConsumer.bind(context);
  }

  @override
  /// Releases the page subscription before Flutter disposes this State.
  void dispose() {
    _ccPageLifecycleConsumer.dispose();
    super.dispose();
  }
}

/// Composition-based lifecycle listener for Flutter PageRoutes in a Host.
///
/// Use this widget for `StatelessWidget`, `HookWidget`, Functional Widget, or a
/// subtree that prefers callbacks over [CCPageLifecycleMixin]. Both APIs consume
/// the same Host lifecycle ledger and therefore have identical ordering and
/// semantics. Multiple listeners are supported; avoid registering the same
/// business side effect through both APIs on one page. A listener placed inside
/// a PopupRoute such as a Dialog or modal bottom sheet is deliberately inert;
/// observe its managed RouteEntry when final popup disposal matters.
final class CCPageLifecycleListener extends StatefulWidget {
  /// Creates a lifecycle listener around [child].
  const CCPageLifecycleListener({
    required this.child,
    this.onPageShow,
    this.onPageHide,
    this.onForeground,
    this.onBackground,
    super.key,
  });

  /// Page content or subtree that owns the callbacks.
  final Widget child;

  /// Called when the enclosing PageRoute becomes current in an active Outlet.
  final VoidCallback? onPageShow;

  /// Called when the enclosing PageRoute stops being current.
  final VoidCallback? onPageHide;

  /// Called when the application resumes while the page is current.
  final VoidCallback? onForeground;

  /// Called when the application backgrounds while the page is current.
  final VoidCallback? onBackground;

  @override
  /// Creates State that automatically owns the lifecycle subscription.
  State<CCPageLifecycleListener> createState() =>
      _CCPageLifecycleListenerState();
}

/// State that binds [CCPageLifecycleListener] to the current Host and Route.
final class _CCPageLifecycleListenerState
    extends State<CCPageLifecycleListener> {
  /// Shared subscriber whose closures always resolve the latest Widget values.
  late final _CCPageLifecycleConsumer _consumer = _CCPageLifecycleConsumer(
    onPageShow: () => widget.onPageShow?.call(),
    onPageHide: () => widget.onPageHide?.call(),
    onForeground: () => widget.onForeground?.call(),
    onBackground: () => widget.onBackground?.call(),
  );

  @override
  /// Rebinds when the Host scope or enclosing ModalRoute changes.
  void didChangeDependencies() {
    super.didChangeDependencies();
    _consumer.bind(context);
  }

  @override
  /// Cancels the lifecycle subscription owned by this listener.
  void dispose() {
    _consumer.dispose();
    super.dispose();
  }

  @override
  /// Returns the child without adding layout, paint, or semantics behavior.
  Widget build(BuildContext context) => widget.child;
}

/// Host-only bridge between Flutter navigation backends and page subscribers.
///
/// Adapter packages report top-Route changes through [didChangeTop] and active
/// Outlet changes through [setActiveOutlets]. Business and component code must
/// not call this SPI; use [CCPageLifecycleMixin] or [CCPageLifecycleListener].
abstract final class CCPageLifecycleHostBridge {
  /// Host ledgers indexed by stable Host identity.
  static final Map<String, _CCPageLifecycleHostRecord> _hosts = {};

  /// Attaches one Host owner and records its current application lifecycle.
  ///
  /// A Host ID cannot be mounted by two widget trees at once because backend
  /// Route identities would otherwise be ambiguous.
  static void _attachHost({
    required String hostId,
    required Object owner,
    AppLifecycleState? applicationState,
  }) {
    final record = _hosts.putIfAbsent(
      hostId,
      () => _CCPageLifecycleHostRecord(hostId),
    );
    final existingOwner = record.owner;
    if (existingOwner != null && !identical(existingOwner, owner)) {
      throw FlutterError(
        'CCRouter page lifecycle Host "$hostId" is already attached.',
      );
    }
    record
      ..owner = owner
      ..attached = true
      ..updateApplicationState(applicationState, notify: false);
    record.reconcileAllRoutes();
  }

  /// Detaches [owner], hides current pages, and clears backend Route positions.
  static void _detachHost({required String hostId, required Object owner}) {
    final record = _hosts[hostId];
    if (record == null || !identical(record.owner, owner)) return;
    record
      ..attached = false
      ..owner = null
      ..topRoutes.clear();
    record.activeOutlets
      ..clear()
      ..add('root');
    record.reconcileAllRoutes();
    _removeHostIfUnused(record);
  }

  /// Forwards one Flutter application lifecycle state to current pages.
  ///
  /// `resumed` produces foreground callbacks after a background transition;
  /// `hidden`, `paused`, and `detached` produce one background callback.
  /// Flutter's transient `inactive` state does not change page foreground state.
  static void _updateApplicationState({
    required String hostId,
    required AppLifecycleState state,
  }) {
    final record = _hosts[hostId];
    if (record == null || !record.attached) return;
    record.updateApplicationState(state);
  }

  /// Reports the current top Route for one Host Navigator Outlet.
  ///
  /// Backends should invoke this only after Flutter confirms a top-Route change,
  /// normally from `NavigatorObserver.didChangeTop`. Foreign PageRoutes and
  /// PopupRoutes are valid top Routes: they hide a subscribed managed page but
  /// never remove or dispose its Runtime RouteEntry. Events for a Host that is
  /// not currently attached by `CCRouterApp` are ignored so an external Router
  /// cannot keep Flutter Route objects alive after Host teardown.
  static void didChangeTop({
    required String hostId,
    required String outlet,
    required Route<dynamic> topRoute,
    Route<dynamic>? previousTopRoute,
  }) {
    final record = _hosts[hostId];
    if (record == null || !record.attached) return;
    record.topRoutes[outlet] = topRoute;
    if (previousTopRoute != null) record.reconcileRoute(previousTopRoute);
    record.reconcileRoute(topRoute);
  }

  /// Declares which Navigator Outlets currently participate in page display.
  ///
  /// Root-only Hosts are active by default. Stateful Shell integrations call
  /// this when branches switch; adaptive multi-pane Hosts may declare multiple
  /// simultaneous Outlets. Entries in inactive Outlets stay mounted but receive
  /// `onPageHide` until their Outlet becomes active again.
  static void setActiveOutlets({
    required String hostId,
    required Iterable<String> outlets,
  }) {
    final record = _hosts[hostId];
    if (record == null || !record.attached) return;
    record.activeOutlets
      ..clear()
      ..addAll(outlets);
    record.reconcileAllRoutes();
  }

  /// Wraps [child] with the inherited Host identity used by page subscribers.
  ///
  /// This is called by `CCRouterApp`; adapters do not need to wrap page widgets.
  static Widget _scope({required String hostId, required Widget child}) =>
      _CCPageLifecycleHostScope(hostId: hostId, child: child);

  /// Subscribes one mounted consumer to its enclosing PageRoute.
  static _CCPageLifecycleSubscription _subscribe({
    required String hostId,
    required PageRoute<dynamic> route,
    required _CCPageLifecycleCallbacks callbacks,
  }) {
    final record = _hosts.putIfAbsent(
      hostId,
      () => _CCPageLifecycleHostRecord(hostId),
    );
    final subscription = _CCPageLifecycleSubscription(
      host: record,
      route: route,
      callbacks: callbacks,
    );
    record.subscriptions
        .putIfAbsent(route, () => <_CCPageLifecycleSubscription>{})
        .add(subscription);
    subscription.scheduleInitialReconcile();
    return subscription;
  }

  /// Removes a Host ledger after both its widget owner and subscribers are gone.
  static void _removeHostIfUnused(_CCPageLifecycleHostRecord record) {
    if (!record.attached && record.subscriptions.isEmpty) {
      _hosts.remove(record.hostId);
    }
  }
}

/// Inherited Host identity installed above the application Router.
final class _CCPageLifecycleHostScope extends InheritedWidget {
  /// Creates a lifecycle Host scope around [child].
  const _CCPageLifecycleHostScope({required this.hostId, required super.child});

  /// Stable Host identity used to select the lifecycle ledger.
  final String hostId;

  /// Reads the nearest Host identity and establishes an inherited dependency.
  static String? maybeHostIdOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_CCPageLifecycleHostScope>()
      ?.hostId;

  @override
  /// Notifies consumers only when the effective Host identity changes.
  bool updateShouldNotify(_CCPageLifecycleHostScope oldWidget) =>
      oldWidget.hostId != hostId;
}

/// Mutable Host ledger retained only by the Flutter integration layer.
final class _CCPageLifecycleHostRecord {
  /// Creates a detached Host record with the root Outlet active by default.
  _CCPageLifecycleHostRecord(this.hostId);

  /// Stable Host identity shared with backend observers.
  final String hostId;

  /// Exact `CCRouterApp` State currently owning the Host.
  Object? owner;

  /// Whether the Host is mounted above a Flutter application tree.
  bool attached = false;

  /// Whether Flutter currently considers the application foregrounded.
  bool? foreground;

  /// Current top Route for each observed Navigator Outlet.
  final Map<String, Route<dynamic>> topRoutes = {};

  /// Outlets whose current PageRoute is eligible for page-show callbacks.
  final Set<String> activeOutlets = {'root'};

  /// Page subscriptions grouped by exact Flutter Route identity.
  final Map<Route<dynamic>, Set<_CCPageLifecycleSubscription>> subscriptions =
      Map.identity();

  /// Applies one App state and optionally publishes its foreground transition.
  void updateApplicationState(AppLifecycleState? state, {bool notify = true}) {
    final next = switch (state) {
      AppLifecycleState.resumed => true,
      AppLifecycleState.hidden ||
      AppLifecycleState.paused ||
      AppLifecycleState.detached => false,
      AppLifecycleState.inactive || null => foreground,
    };
    if (next == foreground) return;
    final previous = foreground;
    foreground = next;
    if (!notify || previous == null || next == null) return;
    for (final subscription in _allSubscriptions().where(
      (candidate) => candidate.shown,
    )) {
      if (next) {
        subscription.dispatchForeground();
      } else {
        subscription.dispatchBackground();
      }
    }
  }

  /// Reconciles every subscribed Route after Host or Outlet state changes.
  void reconcileAllRoutes() {
    for (final route in subscriptions.keys.toList()) {
      reconcileRoute(route);
    }
  }

  /// Reconciles subscribers for one exact Route identity.
  void reconcileRoute(Route<dynamic> route) {
    final subscribers = subscriptions[route];
    if (subscribers == null) return;
    final shouldShow = attached && _isCurrentInActiveOutlet(route);
    for (final subscription in subscribers.toList()) {
      subscription.reconcile(shouldShow);
    }
  }

  /// Returns whether [route] is top in any currently active Outlet.
  bool _isCurrentInActiveOutlet(Route<dynamic> route) {
    for (final outlet in activeOutlets) {
      if (identical(topRoutes[outlet], route)) return true;
    }
    return false;
  }

  /// Returns a stable snapshot while callbacks may cancel subscriptions.
  List<_CCPageLifecycleSubscription> _allSubscriptions() =>
      subscriptions.values.expand((items) => items).toList(growable: false);
}

/// Callback group shared by Mixin and Listener consumers.
final class _CCPageLifecycleCallbacks {
  /// Creates one callback group.
  const _CCPageLifecycleCallbacks({
    required this.onPageShow,
    required this.onPageHide,
    required this.onForeground,
    required this.onBackground,
  });

  /// Page-show callback.
  final VoidCallback onPageShow;

  /// Page-hide callback.
  final VoidCallback onPageHide;

  /// Application-foreground callback.
  final VoidCallback onForeground;

  /// Application-background callback.
  final VoidCallback onBackground;
}

/// One automatically removed subscription to an exact PageRoute.
final class _CCPageLifecycleSubscription {
  /// Creates an inactive subscription.
  _CCPageLifecycleSubscription({
    required this.host,
    required this.route,
    required this.callbacks,
  });

  /// Host ledger that owns this subscription.
  final _CCPageLifecycleHostRecord host;

  /// Exact Flutter PageRoute observed by this subscription.
  final PageRoute<dynamic> route;

  /// Consumer callbacks invoked for state changes.
  final _CCPageLifecycleCallbacks callbacks;

  /// Whether the page has most recently received a show callback.
  bool shown = false;

  /// Whether the owning Mixin or Listener has cancelled the subscription.
  bool disposed = false;

  /// Schedules initial-state replay after dependency resolution and build.
  void scheduleInitialReconcile() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!disposed) host.reconcileRoute(route);
    });
  }

  /// Publishes a show or hide callback only when effective state changes.
  void reconcile(bool shouldShow) {
    if (disposed || shouldShow == shown) return;
    shown = shouldShow;
    _reportCallback(
      callback: shouldShow ? callbacks.onPageShow : callbacks.onPageHide,
      name: shouldShow ? 'onPageShow' : 'onPageHide',
    );
  }

  /// Publishes an application-foreground callback for a shown page.
  void dispatchForeground() {
    if (!disposed && shown) {
      _reportCallback(callback: callbacks.onForeground, name: 'onForeground');
    }
  }

  /// Publishes an application-background callback for a shown page.
  void dispatchBackground() {
    if (!disposed && shown) {
      _reportCallback(callback: callbacks.onBackground, name: 'onBackground');
    }
  }

  /// Cancels this subscription without synthesizing a navigation transition.
  void dispose() {
    if (disposed) return;
    disposed = true;
    final subscribers = host.subscriptions[route];
    subscribers?.remove(this);
    if (subscribers != null && subscribers.isEmpty) {
      host.subscriptions.remove(route);
    }
    CCPageLifecycleHostBridge._removeHostIfUnused(host);
  }

  /// Reports callback failures without corrupting Host navigation state.
  void _reportCallback({required VoidCallback callback, required String name}) {
    try {
      callback();
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'CCRouter page lifecycle',
          context: ErrorDescription('while dispatching $name'),
        ),
      );
    }
  }
}

/// Shared binding helper used by both public page lifecycle APIs.
final class _CCPageLifecycleConsumer {
  /// Creates a consumer around stable callback closures.
  _CCPageLifecycleConsumer({
    required this.onPageShow,
    required this.onPageHide,
    required this.onForeground,
    required this.onBackground,
  });

  /// Page-show callback supplied by the public API.
  final VoidCallback onPageShow;

  /// Page-hide callback supplied by the public API.
  final VoidCallback onPageHide;

  /// Application-foreground callback supplied by the public API.
  final VoidCallback onForeground;

  /// Application-background callback supplied by the public API.
  final VoidCallback onBackground;

  /// Host identity currently associated with [subscription].
  String? _hostId;

  /// Exact PageRoute currently associated with [subscription].
  PageRoute<dynamic>? _route;

  /// Active Host ledger subscription, when the widget is inside a Host page.
  _CCPageLifecycleSubscription? _subscription;

  /// Binds to the nearest Host scope and enclosing PageRoute.
  void bind(BuildContext context) {
    final hostId = _CCPageLifecycleHostScope.maybeHostIdOf(context);
    final modalRoute = ModalRoute.of(context);
    final route = modalRoute is PageRoute<dynamic> ? modalRoute : null;
    if (_hostId == hostId && identical(_route, route)) return;
    _subscription?.dispose();
    _subscription = null;
    _hostId = hostId;
    _route = route;
    if (hostId == null || route == null) return;
    _subscription = CCPageLifecycleHostBridge._subscribe(
      hostId: hostId,
      route: route,
      callbacks: _CCPageLifecycleCallbacks(
        onPageShow: onPageShow,
        onPageHide: onPageHide,
        onForeground: onForeground,
        onBackground: onBackground,
      ),
    );
  }

  /// Releases the current subscription and retained Route identity.
  void dispose() {
    _subscription?.dispose();
    _subscription = null;
    _hostId = null;
    _route = null;
  }
}
