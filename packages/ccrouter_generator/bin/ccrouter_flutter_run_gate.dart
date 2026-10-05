import 'dart:io';

import 'src/flutter_run_reload_gate.dart';

/// Starts the original Flutter machine process behind the CCRouter reload gate.
Future<void> main(List<String> arguments) async {
  final separator = arguments.indexOf('--');
  if (separator < 0) {
    stderr.writeln(
      'error: expected --host-root <path> --original <path> -- <flutter args>',
    );
    exitCode = 2;
    return;
  }
  String? hostRoot;
  String? original;
  for (var index = 0; index < separator; index++) {
    final option = arguments[index];
    if ((option == '--host-root' || option == '--original') &&
        index + 1 < separator) {
      final value = arguments[++index];
      if (option == '--host-root') {
        hostRoot = value;
      } else {
        original = value;
      }
      continue;
    }
    stderr.writeln('error: invalid reload-gate option: $option');
    exitCode = 2;
    return;
  }
  if (hostRoot == null || original == null) {
    stderr.writeln('error: --host-root and --original are required.');
    exitCode = 2;
    return;
  }
  final proxy = CCFlutterMachineRunProxy(
    originalFlutter: original,
    flutterArguments: arguments.sublist(separator + 1),
    hostRoot: Directory(hostRoot).absolute,
  );
  exitCode = await proxy.run();
}
