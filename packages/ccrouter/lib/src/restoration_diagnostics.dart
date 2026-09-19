import 'package:ccrouter_contracts/ccrouter_contracts.dart';

/// Host-owned bridge for reporting route-restoration demand signals.
///
/// Create this in application composition code, pass it to
/// `CCRouter.initialize`, and call [report] only when platform or persisted
/// session evidence indicates a genuine recreation opportunity. This controller
/// does not persist or restore navigation state.
final class CCRouteRestorationOpportunityController
    implements CCRouteRestorationOpportunitySource {
  /// Creates a bridge with optional signals detected before Runtime startup.
  ///
  /// [pendingCapacity] bounds evidence retained before a Runtime subscribes;
  /// when full, the oldest signal is discarded. Use a small positive value
  /// because these signals measure demand and are not a restoration journal.
  CCRouteRestorationOpportunityController({
    Iterable<CCRouteRestorationOpportunitySignal> initialSignals = const [],
    this.pendingCapacity = 64,
  }) : _pending = [] {
    if (pendingCapacity <= 0) {
      throw ArgumentError.value(
        pendingCapacity,
        'pendingCapacity',
        'Pending capacity must be greater than zero.',
      );
    }
    for (final signal in initialSignals) {
      _retainPending(signal);
    }
  }

  /// Maximum number of pre-subscription signals retained by this controller.
  final int pendingCapacity;

  /// Signals waiting for the first Runtime subscription.
  final List<CCRouteRestorationOpportunitySignal> _pending;

  /// Active Runtime consumers; normally this set contains at most one listener.
  final Set<void Function(CCRouteRestorationOpportunitySignal signal)>
  _listeners = {};

  /// Reports platform or session-marker evidence to the active Runtime.
  ///
  /// Signals reported before Runtime attaches are retained until
  /// [takeInitialSignals]. Do not use this for ordinary cold starts or
  /// foreground transitions because those would overstate restoration demand.
  void report(CCRouteRestorationOpportunitySignal signal) {
    if (_listeners.isEmpty) {
      _retainPending(signal);
      return;
    }
    for (final listener in _listeners.toList()) {
      listener(signal);
    }
  }

  /// Drains evidence captured before Runtime initialization.
  @override
  List<CCRouteRestorationOpportunitySignal> takeInitialSignals() {
    final result = List<CCRouteRestorationOpportunitySignal>.unmodifiable(
      _pending,
    );
    _pending.clear();
    return result;
  }

  /// Attaches one Runtime consumer and returns its removal callback.
  @override
  void Function() addListener(
    void Function(CCRouteRestorationOpportunitySignal signal) listener,
  ) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  /// Retains one startup signal while dropping the oldest overflow item.
  void _retainPending(CCRouteRestorationOpportunitySignal signal) {
    if (_pending.length == pendingCapacity) {
      _pending.removeAt(0);
    }
    _pending.add(signal);
  }
}
