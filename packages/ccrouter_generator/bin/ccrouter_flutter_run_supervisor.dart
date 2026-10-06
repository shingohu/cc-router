import 'dart:io';

import 'src/flutter_run_supervisor.dart';

/// Runs the original Flutter Tool while owning the background watch lease.
Future<void> main(List<String> arguments) async {
  final separator = arguments.indexOf('--');
  if (separator < 0) {
    stderr.writeln(
      'error: expected --host-root <path> --original <path> '
      '(--launch-watch | --watch-lease <path>) [--reload-gate] '
      '-- <flutter args>',
    );
    exitCode = 2;
    return;
  }
  String? hostRoot;
  String? original;
  String? watchLease;
  var launchWatch = false;
  var reloadGate = false;
  for (var index = 0; index < separator; index++) {
    final option = arguments[index];
    if (option == '--reload-gate') {
      reloadGate = true;
      continue;
    }
    if (option == '--launch-watch') {
      launchWatch = true;
      continue;
    }
    if ((option == '--host-root' ||
            option == '--original' ||
            option == '--watch-lease') &&
        index + 1 < separator) {
      final value = arguments[++index];
      switch (option) {
        case '--host-root':
          hostRoot = value;
        case '--original':
          original = value;
        case '--watch-lease':
          watchLease = value;
      }
      continue;
    }
    stderr.writeln('error: invalid Flutter-run supervisor option: $option');
    exitCode = 2;
    return;
  }
  if (hostRoot == null ||
      original == null ||
      (launchWatch == (watchLease != null))) {
    stderr.writeln(
      'error: --host-root, --original, and exactly one of --launch-watch or '
      '--watch-lease are required.',
    );
    exitCode = 2;
    return;
  }
  try {
    exitCode = await CCFlutterRunSupervisor(
      originalFlutter: original,
      flutterArguments: arguments.sublist(separator + 1),
      hostRoot: Directory(hostRoot).absolute,
      watchLease: watchLease == null ? null : File(watchLease).absolute,
      launchWatch: launchWatch,
      coordinateMachineReloads: reloadGate,
      environment: Platform.environment,
    ).run();
  } on Object catch (error) {
    stderr.writeln('error: CCRouter Flutter-run supervisor failed: $error');
    exitCode = 1;
  }
}
