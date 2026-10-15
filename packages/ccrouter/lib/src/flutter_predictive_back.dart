part of 'flutter_route_factory.dart';

/// Host/Adapter SPI observing default Android Material route gestures.
///
/// The Navigator owns animation and the actual Pop. Implementations correlate
/// concrete Route identities with backend observations; [onCommit] is a request,
/// not proof of removal. Feature code must not retain this interface or Routes.
abstract interface class CCFlutterPredictiveBackHandler {
  /// Whether this observer still owns new gestures. Once false, surviving
  /// application-owned Routes detach it at their next start; an already
  /// accepted gesture still checks [canCommit] against its original owner.
  bool get isActive;

  /// Registers a Navigator-installed Route until its matching [onDispose].
  void onAttach(Route<dynamic> route);

  /// Binds a newly accepted gesture to this exact Route.
  void onStart(Route<dynamic> route);

  /// Observes normalized platform progress without performing navigation.
  void onUpdate(Route<dynamic> route, double progress);

  /// Ends an uncommitted gesture without completing its result or Scope.
  void onCancel(Route<dynamic> route);

  /// Whether the original backend gesture identity is still eligible to Pop.
  ///
  /// Flutter Route gates are checked separately immediately before commit.
  bool canCommit(Route<dynamic> route);

  /// Marks a commit request before Flutter performs its sole Navigator Pop.
  void onCommit(Route<dynamic> route);

  /// Releases any gesture reference when this Route or handler lifetime ends.
  void onDispose(Route<dynamic> route);
}

/// Opt-in Route preserving Flutter's predictive transitions and Pop ownership.
///
/// A policy change during a gesture cancels its preview rather than allowing
/// Flutter's direct commit Pop to bypass a newly closed PopScope/Form gate.
/// Replacing a predictive Theme during a preview also cancels through Flutter's
/// Route hook, even if rebuilding the transition removes its gesture detector.
final class _CCPredictiveMaterialPageRoute<T> extends MaterialPageRoute<T> {
  /// Creates a Navigator-owned route with one Adapter-owned observation sink.
  _CCPredictiveMaterialPageRoute({
    required super.builder,
    required CCFlutterPredictiveBackHandler handler,
    super.settings,
    super.fullscreenDialog,
  }) : _handler = handler;

  /// Sink released at Route disposal so late platform events retain no owner.
  CCFlutterPredictiveBackHandler? _handler;

  /// Whether this Route has accepted a gesture without a terminal callback.
  bool _tracking = false;

  /// Identifies the preview so deferred Theme cleanup cannot cancel a new one.
  int _gestureSequence = 0;

  /// Whether Navigator teardown has permanently ended this Route.
  bool _disposed = false;

  /// Whether every enclosing Navigator surface is still its current Route.
  /// A nested Route's own isCurrent does not detect a root Dialog above it.
  bool get _ancestorsAreCurrent {
    var enclosingNavigator = navigator;
    while (enclosingNavigator != null) {
      final ancestor = ModalRoute.of(enclosingNavigator.context);
      if (ancestor == null) break;
      if (!ancestor.isCurrent) return false;
      enclosingNavigator = ancestor.navigator;
    }
    return true;
  }

  /// Returns the live observer or detaches a broken Host integration.
  ///
  /// Lifetime probing is observational. A custom Host implementation that
  /// throws here must relinquish this Route so Flutter can retain its normal
  /// gesture and Pop behavior.
  CCFlutterPredictiveBackHandler? get _activeHandler {
    final handler = _handler;
    if (handler == null) return null;
    try {
      if (handler.isActive) return handler;
    } catch (_) {
      // A broken Host lifetime probe degrades to Flutter-owned behavior.
    }
    _handler = null;
    try {
      handler.onDispose(this);
    } catch (_) {
      // Detaching a broken Host observer must remain best effort.
    }
    return null;
  }

  @override
  /// Leaves system fallback to the covering ancestor surface before a start.
  bool get popGestureEnabled =>
      super.popGestureEnabled &&
      (_activeHandler == null || _ancestorsAreCurrent);

  @override
  /// Registers only the opt-in Route after Flutter installs its controller.
  void install() {
    super.install();
    _observe((handler) => handler.onAttach(this));
  }

  @override
  /// Cancels an incompatible Theme preview after Flutter rebuilds its detector.
  ///
  /// Theme changes can remove the detector before its platform terminal event.
  /// Cleanup runs after the frame to avoid mutating Navigator during build; the
  /// Adapter retains its platform claim so late commits cannot pop another page.
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final theme = Theme.of(context);
    final transition = theme.pageTransitionsTheme.builders[theme.platform];
    final supported =
        theme.platform == TargetPlatform.android &&
        (transition.runtimeType == PredictiveBackPageTransitionsBuilder ||
            transition.runtimeType ==
                PredictiveBackFullscreenPageTransitionsBuilder);
    if (_tracking && _handler != null && !supported) {
      final sequence = _gestureSequence;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_disposed && _tracking && _gestureSequence == sequence) {
          handleCancelBackGesture();
        }
      });
    }
    return super.buildTransitions(
      context,
      animation,
      secondaryAnimation,
      child,
    );
  }

  /// Delivers observations without allowing instrumentation to break navigation.
  void _observe(void Function(CCFlutterPredictiveBackHandler) callback) {
    final handler = _handler;
    if (handler == null) return;
    try {
      callback(handler);
    } catch (_) {
      // A Host observer failure must not interrupt Flutter animation cleanup.
    }
  }

  @override
  /// Starts Flutter animation and then records the concrete Route identity.
  void handleStartBackGesture({double progress = 0}) {
    if (_disposed) return;
    _activeHandler;
    super.handleStartBackGesture(progress: progress);
    _gestureSequence++;
    _tracking = true;
    _observe((handler) => handler.onStart(this));
  }

  @override
  /// Converts Flutter animation remaining value back to platform progress.
  void handleUpdateBackGestureProgress({required double progress}) {
    if (_disposed || !_tracking) return;
    super.handleUpdateBackGestureProgress(progress: progress);
    _observe((handler) => handler.onUpdate(this, 1 - progress));
  }

  @override
  /// Restores animation once and ends observation without a backend mutation.
  void handleCancelBackGesture() {
    if (_disposed || !_tracking) return;
    _tracking = false;
    super.handleCancelBackGesture();
    _observe((handler) => handler.onCancel(this));
  }

  @override
  /// Rechecks current identity and local gates before delegating the sole Pop.
  void handleCommitBackGesture() {
    if (_disposed || !_tracking) return;
    var allowed = false;
    try {
      allowed =
          isCurrent &&
          !willHandlePopInternally &&
          popDisposition == RoutePopDisposition.pop &&
          (_handler == null ||
              (_ancestorsAreCurrent && _handler!.canCommit(this)));
    } catch (_) {
      // An unavailable identity or broken policy must fail closed.
    }
    if (!allowed) {
      handleCancelBackGesture();
      return;
    }
    _tracking = false;
    _observe((handler) => handler.onCommit(this));
    super.handleCommitBackGesture();
  }

  @override
  /// Detaches the observation sink before Flutter releases animation resources.
  void dispose() {
    _disposed = true;
    _tracking = false;
    _observe((handler) => handler.onDispose(this));
    _handler = null;
    super.dispose();
  }
}
