import 'package:flutter/widgets.dart';

/// Identifies the Flutter navigation host associated with one application
/// window.
///
/// The host owns a root [navigatorKey] that an Adapter may bind to its Router
/// or Navigator. It does not retain a global [BuildContext], and one host may
/// be created for each Window when an application has multiple windows.
final class CCNavigationHost {
  /// Creates a host with a stable [id] and optional root Navigator key.
  CCNavigationHost({this.id = 'root', GlobalKey<NavigatorState>? navigatorKey})
    : navigatorKey =
          navigatorKey ?? GlobalKey<NavigatorState>(debugLabel: 'CCRouter');

  /// Stable host identity used to associate Adapter and Outlet state.
  final String id;

  /// Root Navigator key consumed by a Flutter navigation Adapter.
  final GlobalKey<NavigatorState> navigatorKey;
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
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  /// Rebinds the State to a newly supplied externally owned Host.
  void didUpdateWidget(covariant CCRouterApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.host != null) {
      _host = widget.host!;
    } else if (oldWidget.host != null) {
      _host = CCNavigationHost();
    }
  }

  @override
  /// Forwards the lifecycle event to the optional observational callback.
  void didChangeAppLifecycleState(AppLifecycleState state) {
    widget.onLifecycleChanged?.call(state);
  }

  @override
  /// Stops lifecycle observation without disposing the application Runtime.
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  /// Provides the Host scope to the existing application widget tree.
  Widget build(BuildContext context) =>
      _CCRouterHostScope(host: _host, child: widget.child);
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
