import 'package:flutter/widgets.dart';

/// Application-owned actions requested by the initialization lab page.
///
/// The component reports product intents through these callbacks. The Host
/// selects the corresponding Gate and owns CCRouter Runtime lifecycle control.
final class DemoInitializationActions extends InheritedWidget {
  const DemoInitializationActions({
    required this.onPrivacyGranted,
    required this.onTimeoutLabRequested,
    required super.child,
    super.key,
  });

  final Future<void> Function() onPrivacyGranted;
  final Future<void> Function() onTimeoutLabRequested;

  static DemoInitializationActions of(BuildContext context) {
    final actions = context
        .dependOnInheritedWidgetOfExactType<DemoInitializationActions>();
    if (actions == null) {
      throw StateError('The Demo Host must install initialization actions.');
    }
    return actions;
  }

  @override
  bool updateShouldNotify(DemoInitializationActions oldWidget) =>
      onPrivacyGranted != oldWidget.onPrivacyGranted ||
      onTimeoutLabRequested != oldWidget.onTimeoutLabRequested;
}
