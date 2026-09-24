part of 'facade.dart';

/// Selects the Runtime visible to the static [CCRouter] facade.
///
/// Production code uses the isolate-owned default Runtime. Test hosts install
/// a Zone-local overlay so multiple tests can run with independent Runtime
/// instances without changing production state. This resolver only selects and
/// stores the Runtime reference; [CCRouter] remains responsible for
/// initialization, Adapter ownership, shutdown, and disposal.
final class _CCRuntimeResolver {
  /// Zone key used only by the dedicated test-support Runtime overlay.
  final Object _overlayZoneKey = Object();

  /// Runtime installed by the production application host.
  CCRouterRuntime? _defaultRuntime;

  /// Returns the production Runtime, if one has been installed.
  CCRouterRuntime? get defaultRuntime => _defaultRuntime;

  /// Returns the Zone-local test Runtime, if one is active.
  CCRouterRuntime? get overlayRuntime {
    final candidate = Zone.current[_overlayZoneKey];
    return candidate is CCRouterRuntime ? candidate : null;
  }

  /// Whether the current Zone resolves to a test Runtime overlay.
  bool get hasOverlayRuntime => overlayRuntime != null;

  /// Returns the Runtime selected for the current call or throws when absent.
  CCRouterRuntime get active {
    final runtime = activeOrNull;
    if (runtime == null) throw const CCRouterNotInitializedError();
    return runtime;
  }

  /// Returns the Runtime selected for the current call, if any.
  CCRouterRuntime? get activeOrNull => overlayRuntime ?? _defaultRuntime;

  /// Installs the production Runtime after it has completed initialization.
  void installDefault(CCRouterRuntime runtime) {
    if (_defaultRuntime != null) {
      throw const CCRouterAlreadyInitializedError();
    }
    _defaultRuntime = runtime;
  }

  /// Removes and returns the production Runtime for the shutdown owner.
  CCRouterRuntime? takeDefault() {
    final runtime = _defaultRuntime;
    _defaultRuntime = null;
    return runtime;
  }

  /// Runs [body] with [runtime] visible through the static facade.
  R runWithRuntime<R>(CCRouterRuntime runtime, R Function() body) =>
      runZoned(body, zoneValues: {_overlayZoneKey: runtime});
}

/// Single private resolver shared by the production facade and test bridge.
final _runtimeResolver = _CCRuntimeResolver();
