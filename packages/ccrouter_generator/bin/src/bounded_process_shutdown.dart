import 'dart:async';
import 'dart:io';

/// Stops a child process with bounded graceful and forceful escalation.
Future<int> stopProcessWithEscalation(
  Process process, {
  Duration interruptTimeout = const Duration(seconds: 10),
  Duration terminateTimeout = const Duration(seconds: 5),
  Duration killTimeout = const Duration(seconds: 5),
}) async {
  process.kill(ProcessSignal.sigint);
  final interrupted = await _waitForExit(process, interruptTimeout);
  if (interrupted != null) return interrupted;

  process.kill(ProcessSignal.sigterm);
  final terminated = await _waitForExit(process, terminateTimeout);
  if (terminated != null) return terminated;

  var killSent = false;
  try {
    killSent = process.kill(ProcessSignal.sigkill);
  } on Object {
    if (!Platform.isWindows) rethrow;
  }
  if (!killSent && Platform.isWindows) {
    killSent = process.kill();
  }
  final killed = await _waitForExit(process, killTimeout);
  if (killed != null) return killed;
  throw TimeoutException(
    'Child process ${process.pid} did not exit after '
    '${interruptTimeout.inMilliseconds}ms SIGINT, '
    '${terminateTimeout.inMilliseconds}ms SIGTERM, and '
    '${killTimeout.inMilliseconds}ms SIGKILL waits '
    '(force signal sent: $killSent).',
  );
}

Future<int?> _waitForExit(Process process, Duration timeout) async {
  try {
    return await process.exitCode.timeout(timeout);
  } on TimeoutException {
    return null;
  }
}
