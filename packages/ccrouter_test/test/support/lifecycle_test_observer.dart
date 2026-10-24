import 'package:ccrouter/ccrouter_host.dart';
import 'package:flutter/widgets.dart';

/// Exercises the backend-neutral lifecycle bridge with an ordinary Navigator.
final class LifecycleTestObserver extends NavigatorObserver {
  LifecycleTestObserver({required this.hostId, required this.outlet});
  final String hostId;
  final String outlet;
  @override
  void didChangeTop(Route<dynamic> topRoute, Route<dynamic>? previousTopRoute) {
    CCPageLifecycleHostBridge.didChangeTop(
      hostId: hostId,
      outlet: outlet,
      topRoute: topRoute,
      previousTopRoute: previousTopRoute,
    );
  }
}
