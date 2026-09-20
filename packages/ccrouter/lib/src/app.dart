import 'dart:async';

import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:flutter/widgets.dart';

import 'facade.dart';
import 'route_catalog.dart';

part 'page_lifecycle.dart';

/// Maximum length accepted for Host and Navigator Outlet identifiers.
const int _maxNavigationIdentifierLength = 128;

/// Stable identifier syntax used by Flutter Host integration.
final RegExp _navigationIdentifierPattern = RegExp(
  r'^[a-z][A-Za-z0-9]*(?:[._-][A-Za-z0-9]+)*$',
);

/// Whether [value] can safely identify one Host or Navigator Outlet.
bool _isNavigationIdentifier(String value) =>
    value.length <= _maxNavigationIdentifierLength &&
    _navigationIdentifierPattern.hasMatch(value);

/// Backend resources coordinated by a managed [CCRouterApp].
///
/// Adapter packages implement this at the application composition boundary.
/// After successful attachment the Runtime owns [navigationAdapter]; when
/// attachment is rejected before ownership transfers,
/// [CCRouterApp.managed] closes the Adapter itself. [dispose] releases only
/// other resources, such as a Router created by a managed backend. An attached
/// backend must leave application-owned Router objects untouched.
abstract interface class CCRouterAppBackend {
  /// Backend-neutral generated destinations assembled for this Host.
  ///
  /// The application passes generated component manifests to
  /// `CCRouter.initialize` before mounting [CCRouterApp.managed]. The managed
  /// binding compares their identities and versions with
  /// [CCFlutterRouteCatalog.componentVersions] so a Backend generated for
  /// another component set cannot attach.
  CCFlutterRouteCatalog get routeCatalog;

  /// Stable Flutter navigation Host shared by Router and Adapter objects.
  CCNavigationHost get host;

  /// Adapter initialized and disposed by the Runtime.
  CCNavigationAdapter get navigationAdapter;

  /// Releases backend-owned resources after Runtime shutdown.
  Future<void> dispose();
}

/// Internal coordinator that transfers one Backend into an initialized Runtime.
///
/// [CCRouterApp.managed] is the only public managed-binding entry. Keeping this
/// coordinator private prevents Hosts from attaching a Backend without mounting
/// its lifecycle scope, while preserving catalog validation and ordered cleanup.
abstract final class _CCRouterBackendBinding {
  /// Backend whose Adapter is currently owned by the active Runtime.
  static CCRouterAppBackend? _activeBackend;

  /// Attaches [backend] to the explicitly initialized default Runtime.
  ///
  /// The application must call `CCRouter.initialize` with its component
  /// manifests first. On success the Runtime owns the Adapter, and
  /// `CCRouter.shutdown` later disposes the Adapter before invoking
  /// [CCRouterAppBackend.dispose]. A rejected Adapter is disposed synchronously
  /// before the error is rethrown; asynchronous Backend resource cleanup is
  /// scheduled separately and reports failures through Flutter diagnostics.
  static void attach({required CCRouterAppBackend backend}) {
    if (_activeBackend != null) {
      _disposeRejectedBackend(backend);
      throw const CCNavigationAdapterError(
        'A navigation Backend is already attached to CCRouter.',
      );
    }
    _attachAndOwn(backend);
  }

  /// Transfers Adapter ownership and registers Backend cleanup with shutdown.
  static void _attachAndOwn(CCRouterAppBackend backend) {
    Future<void> disposeBackend() async {
      if (identical(_activeBackend, backend)) _activeBackend = null;
      await backend.dispose();
    }

    _activeBackend = backend;
    try {
      _validateRouteCatalog(backend.routeCatalog);
      CCRouterHostBinding.attachNavigationAdapter(
        backend.navigationAdapter,
        disposeBackend: disposeBackend,
      );
    } catch (error, stackTrace) {
      if (identical(_activeBackend, backend)) _activeBackend = null;
      _disposeRejectedBackend(backend);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// Rejects a Backend assembled from a different component catalog.
  static void _validateRouteCatalog(CCFlutterRouteCatalog routeCatalog) {
    final registered = <String, String>{
      for (final component in CCRouter.registeredComponents)
        component.id: component.version,
    };
    final generated = routeCatalog.componentVersions;
    if (registered.length != generated.length ||
        registered.entries.any(
          (entry) => generated[entry.key] != entry.value,
        )) {
      throw const CCRegistrationError(
        'The navigation Backend component catalog does not match the '
        'registered Runtime components.',
      );
    }
  }

  /// Releases a Backend whose Adapter ownership transfer did not complete.
  static void _disposeRejectedBackend(CCRouterAppBackend backend) {
    try {
      backend.navigationAdapter.dispose();
    } catch (error, stackTrace) {
      _reportDisposalError(
        error,
        stackTrace,
        'while disposing a rejected CCRouter navigation Adapter',
      );
    }
    unawaited(_disposeRejectedBackendResources(backend));
  }

  /// Releases asynchronous Backend resources after synchronous rejection.
  static Future<void> _disposeRejectedBackendResources(
    CCRouterAppBackend backend,
  ) async {
    try {
      await backend.dispose();
    } catch (error, stackTrace) {
      _reportDisposalError(
        error,
        stackTrace,
        'while disposing a rejected CCRouter application backend',
      );
    }
  }

  /// Reports a cleanup failure without replacing the attachment failure.
  static void _reportDisposalError(
    Object error,
    StackTrace stackTrace,
    String context,
  ) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'ccrouter',
        context: ErrorDescription(context),
      ),
    );
  }
}

/// Identifies one independently owned Flutter navigation surface.
///
/// The Host owns a stable set of Navigator Outlet keys shared by
/// [CCRouterApp], the application Router, and its navigation Adapter. It does
/// not retain a global [BuildContext]. A Host may fill one Flutter View or
/// represent an embedded independent Router. Future native multi-window
/// integrations map each platform Window or Flutter View to one root Host; the
/// Host itself is not a platform Window identity. A single Host cannot be
/// mounted by two [CCRouterApp] instances at once.
final class CCNavigationHost {
  /// Creates a Host with a stable [id] and immutable Navigator Outlet keys.
  ///
  /// [navigatorKey] identifies the required `root` Outlet. Additional keys are
  /// supplied by [navigatorKeys]. Supplying `root` in both inputs is valid only
  /// when both values are the same object. Outlet names and key identities must
  /// be unique so backend events cannot be attributed to two stacks. Host and
  /// Outlet IDs start with lowercase and use case-sensitive alphanumeric
  /// segments separated by `.`, `_`, or `-`, with at most 128 characters.
  CCNavigationHost({
    this.id = 'default',
    GlobalKey<NavigatorState>? navigatorKey,
    Map<String, GlobalKey<NavigatorState>> navigatorKeys = const {},
  }) : _navigatorKeys = _buildNavigatorKeys(navigatorKey, navigatorKeys) {
    if (!_isNavigationIdentifier(id)) {
      throw ArgumentError.value(
        id,
        'id',
        'Host ID must start with lowercase and use alphanumeric segments separated by '
            '".", "_", or "-".',
      );
    }
  }

  /// Stable host identity used to associate Adapter and Outlet state.
  final String id;

  /// Immutable Navigator keys indexed by stable Outlet name.
  final Map<String, GlobalKey<NavigatorState>> _navigatorKeys;

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

  /// Attaches this Host to one widget tree and rejects duplicate ownership.
  void _mount(Object owner) {
    if (_mountOwner != null && !identical(_mountOwner, owner)) {
      throw FlutterError(
        'CCNavigationHost "$id" is already mounted by another CCRouterApp.',
      );
    }
    if (identical(_mountOwner, owner)) return;
    _mountOwner = owner;
  }

  /// Detaches this Host from its widget tree without disposing Navigator keys.
  void _unmount(Object owner) {
    if (!identical(_mountOwner, owner)) return;
    _mountOwner = null;
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
      if (!_isNavigationIdentifier(entry.key)) {
        throw ArgumentError.value(
          entry.key,
          'navigatorKeys',
          'Navigator Outlet ID is invalid.',
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

/// Flutter application integration boundary for CCRouter.
///
/// The default constructor is a non-owning Host wrapper for existing
/// integrations. [CCRouterApp.managed] additionally attaches one navigation
/// Backend after the application explicitly initializes CCRouter with its
/// components. Neither mode initializes or shuts down the Runtime, and neither
/// stores a global [BuildContext].
final class CCRouterApp extends StatefulWidget {
  /// Creates a non-owning Host around an existing Flutter application tree.
  ///
  /// Use this compatibility mode when Backend binding remains in an existing
  /// composition root. Removing this widget never shuts down
  /// [CCRouter] or disposes the supplied [host]. New applications should prefer
  /// [CCRouterApp.managed].
  const CCRouterApp({
    required this.child,
    this.host,
    this.onLifecycleChanged,
    super.key,
  }) : _backend = null;

  /// Creates an App that attaches and exposes a managed navigation Backend.
  ///
  /// Call `CCRouter.initialize` with the startup components before mounting this
  /// widget. Backend attachment is synchronous, so the [child] is mounted on
  /// the first build only after the Adapter is fully configured. Removing the
  /// widget does not shut down CCRouter; the
  /// application must call `CCRouter.shutdown`, which disposes the Runtime-owned
  /// Adapter before releasing Backend-owned resources.
  ///
  /// Use this mode once at the application composition root. It intentionally
  /// does not open a Session; authentication flows retain explicit Session
  /// ownership.
  CCRouterApp.managed({
    required CCRouterAppBackend backend,
    required this.child,
    this.onLifecycleChanged,
    super.key,
  }) : host = null,
       _backend = backend;

  /// Application widget, commonly `MaterialApp.router`.
  final Widget child;

  /// Optional externally owned host, useful when an Adapter needs its key.
  /// When omitted, the Host creates and retains one for this widget State.
  final CCNavigationHost? host;

  /// Backend whose Adapter and generated assembly are attached in managed mode.
  ///
  /// A null value selects the non-owning compatibility constructor.
  final CCRouterAppBackend? _backend;

  /// Optional callback for process-level Flutter application lifecycle changes.
  ///
  /// The callback is observational only and must not initialize or shut down the
  /// Runtime. It is not a native Window focus or visibility signal. Session
  /// ownership remains with explicit login and logout flows in both modes.
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

/// State that coordinates Host events and optional Backend attachment.
final class _CCRouterAppState extends State<CCRouterApp>
    with WidgetsBindingObserver {
  /// Stable Host mounted by this State for its complete lifetime.
  late CCNavigationHost _host;

  /// Managed Backend captured at attachment so widget updates cannot drift.
  CCRouterAppBackend? _managedBackend;

  /// Whether synchronous managed attachment failed before the first build.
  bool _backendAttachmentFailed = false;

  @override
  /// Mounts the Host, observes Flutter lifecycle, and attaches the Backend.
  void initState() {
    super.initState();
    final backend = widget._backend;
    _managedBackend = backend;
    _host = backend?.host ?? widget.host ?? CCNavigationHost();
    _host._mount(this);
    CCPageLifecycleHostBridge._attachHost(
      hostId: _host.id,
      owner: this,
      applicationState: WidgetsBinding.instance.lifecycleState,
    );
    WidgetsBinding.instance.addObserver(this);
    if (backend != null) {
      try {
        _CCRouterBackendBinding.attach(backend: backend);
      } catch (error, stackTrace) {
        _backendAttachmentFailed = true;
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'ccrouter',
            context: ErrorDescription('while attaching CCRouterApp.managed'),
          ),
        );
      }
    }
  }

  @override
  /// Rebinds compatibility mode and rejects managed ownership replacement.
  void didUpdateWidget(covariant CCRouterApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    final managedBackend = _managedBackend;
    if (managedBackend != null || widget._backend != null) {
      if (!identical(managedBackend, widget._backend)) {
        throw FlutterError(
          'A mounted CCRouterApp.managed cannot replace its backend or '
          'route catalog. Recreate it with a different Key after the previous '
          'managed App has been removed.',
        );
      }
      return;
    }
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
    CCPageLifecycleHostBridge._updateApplicationState(
      hostId: _host.id,
      state: state,
    );
    widget.onLifecycleChanged?.call(state);
  }

  @override
  /// Stops Host observation without changing the explicit Runtime lifecycle.
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    CCPageLifecycleHostBridge._detachHost(hostId: _host.id, owner: this);
    _host._unmount(this);
    super.dispose();
  }

  @override
  /// Provides Host and page-lifecycle scopes around the active App state.
  Widget build(BuildContext context) => _CCRouterHostScope(
    host: _host,
    child: CCPageLifecycleHostBridge._scope(
      hostId: _host.id,
      child: _managedContent(),
    ),
  );

  /// Selects application or startup-failure content for managed mode.
  ///
  /// Startup failures are already reported through [FlutterError]. This method
  /// deliberately renders no exception details so production Hosts cannot leak
  /// component, route, or Adapter configuration through their startup UI.
  Widget _managedContent() {
    if (!_backendAttachmentFailed) return widget.child;
    return const Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: Text('Application failed to start.')),
    );
  }
}

/// Inherited scope that makes one navigation Host discoverable.
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
