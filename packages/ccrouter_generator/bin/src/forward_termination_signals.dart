import 'dart:async';
import 'dart:io';

/// Forwards supervisor termination signals to a child process.
///
/// [onSignal] runs before the child is signalled so wrapper-owned resources
/// can be released while the child is still shutting down.
List<StreamSubscription<ProcessSignal>> forwardTerminationSignals(
  Process process, {
  Future<void> Function()? onSignal,
}) {
  final subscriptions = <StreamSubscription<ProcessSignal>>[];
  for (final signal in <ProcessSignal>[
    ProcessSignal.sigint,
    if (!Platform.isWindows) ProcessSignal.sigterm,
  ]) {
    try {
      subscriptions.add(
        signal.watch().listen((_) async {
          try {
            await onSignal?.call();
          } finally {
            if (Platform.isWindows) {
              process.kill();
            } else {
              process.kill(signal);
            }
          }
        }),
      );
    } on Object {
      // A platform may not expose every signal.
    }
  }
  return subscriptions;
}
