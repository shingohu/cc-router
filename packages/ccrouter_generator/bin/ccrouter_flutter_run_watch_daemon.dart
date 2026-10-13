import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import 'src/flutter_run_watch_lease.dart';

/// Owns redirected watch output independently from any one Flutter run.
Future<void> main(List<String> arguments) async {
  final parsed = _Arguments.parse(arguments);
  if (parsed.error != null) {
    exitCode = 2;
    return;
  }
  IOSink? log;
  try {
    final logFile = File(parsed.logPath!);
    await logFile.parent.create(recursive: true);
    log = logFile.openWrite(mode: FileMode.append);
    final lease = File(parsed.leasePath!).absolute;
    while (lease.existsSync()) {
      final process = await Process.start(
        Platform.resolvedExecutable,
        <String>[
          '--packages=${path.join(parsed.buildRoot!, '.dart_tool', 'package_config.json')}',
          'run',
          '--verbosity=error',
          'ccrouter_generator:ccrouter',
          'generate',
          parsed.hostRoot!,
          '--watch=auto',
          '--machine',
          '--watch-lease',
          lease.path,
        ],
        workingDirectory: parsed.buildRoot!,
        environment: Platform.environment,
        runInShell: Platform.isWindows,
      );
      var registrationConflict = false;
      final stdoutDone = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            log?.writeln(line);
            try {
              final event = jsonDecode(line);
              if (event is Map &&
                  event['type'] == 'failed' &&
                  event['stage'] == 'watch-registration') {
                registrationConflict = true;
              }
            } on FormatException {
              // Non-event generator output remains available in the log.
            }
          })
          .asFuture<void>();
      final stderrDone = process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(log.writeln)
          .asFuture<void>();
      final processExitCode = await process.exitCode;
      await Future.wait<void>(<Future<void>>[stdoutDone, stderrDone]);
      if (!registrationConflict) {
        exitCode = processExitCode;
        return;
      }
      final attachmentWait = Stopwatch()..start();
      while (lease.existsSync() &&
          attachmentWait.elapsed < const Duration(milliseconds: 2500)) {
        if (ccrouterFlutterRunLeaseAttachmentWatchPid(lease) != null) {
          exitCode = 0;
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
    exitCode = 0;
  } on Object catch (error, stackTrace) {
    log?.writeln('error: CCRouter watch daemon failed: $error');
    log?.writeln(stackTrace);
    exitCode = 1;
  } finally {
    await log?.flush();
    await log?.close();
  }
}

final class _Arguments {
  const _Arguments({
    this.hostRoot,
    this.buildRoot,
    this.leasePath,
    this.logPath,
    this.error,
  });

  final String? hostRoot;
  final String? buildRoot;
  final String? leasePath;
  final String? logPath;
  final String? error;

  static _Arguments parse(List<String> arguments) {
    String? hostRoot;
    String? buildRoot;
    String? leasePath;
    String? logPath;
    for (var index = 0; index < arguments.length; index++) {
      final option = arguments[index];
      if (!const <String>{
        '--host-root',
        '--build-root',
        '--watch-lease',
        '--log',
      }.contains(option)) {
        return _Arguments(error: 'Unknown option: $option');
      }
      if (index + 1 >= arguments.length) {
        return _Arguments(error: 'Missing value for $option.');
      }
      final value = arguments[++index];
      switch (option) {
        case '--host-root':
          hostRoot = value;
        case '--build-root':
          buildRoot = value;
        case '--watch-lease':
          leasePath = value;
        case '--log':
          logPath = value;
      }
    }
    if (hostRoot == null ||
        buildRoot == null ||
        leasePath == null ||
        logPath == null) {
      return const _Arguments(
        error:
            '--host-root, --build-root, --watch-lease, and --log are required.',
      );
    }
    return _Arguments(
      hostRoot: hostRoot,
      buildRoot: buildRoot,
      leasePath: leasePath,
      logPath: logPath,
    );
  }
}
