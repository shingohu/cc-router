import 'dart:io';

import 'package:path/path.dart' as path;

import 'src/watch_startup_handshake.dart';

/// Waits for the Flutter wrapper's exact generation watch lease to become ready.
Future<void> main(List<String> arguments) async {
  final parsed = _parseArguments(arguments);
  if (parsed.error case final error?) {
    stderr.writeln('error: $error');
    exitCode = 2;
    return;
  }
  final result = await waitForCCWatchStartup(
    hostRoot: Directory(parsed.hostRoot!),
    leaseFile: File(parsed.leasePath!),
    startupTimeout: Duration(milliseconds: parsed.startupTimeoutMs),
    readyTimeout: Duration(milliseconds: parsed.readyTimeoutMs),
  );
  if (result.succeeded) {
    stdout.writeln(
      'CCRouter watch ready (pid=${result.pid}, '
      'elapsed=${result.elapsed.inMilliseconds}ms). '
      'Status: ${path.join(parsed.hostRoot!, '.dart_tool', 'ccrouter', 'v1', 'watch', 'status.json')}; '
      'log: ${result.logFile.path}',
    );
    return;
  }
  stderr.writeln(
    'CCRouter watch startup failed: ${result.message}, '
    'elapsed=${result.elapsed.inMilliseconds}ms.',
  );
  if (result.diagnostics case final diagnostics?) {
    stderr.writeln('Generator output:');
    stderr.writeln(diagnostics);
  }
  stderr.writeln('Watch log: ${result.logFile.path}');
  exitCode = 1;
}

/// Parsed internal wrapper arguments with test-only timeout overrides.
final class _WatchStartupArguments {
  /// Creates one immutable parse result.
  const _WatchStartupArguments({
    this.hostRoot,
    this.leasePath,
    this.startupTimeoutMs = 30000,
    this.readyTimeoutMs = 300000,
    this.error,
  });

  /// Host whose local watch status is authoritative.
  final String? hostRoot;

  /// Unique lease passed to the just-launched watch process.
  final String? leasePath;

  /// Maximum milliseconds before the watch publishes matching status.
  final int startupTimeoutMs;

  /// Maximum milliseconds before the matching session becomes ready.
  final int readyTimeoutMs;

  /// Parse failure shown without starting Flutter.
  final String? error;
}

/// Parses the narrow private protocol used by installed SDK wrappers.
_WatchStartupArguments _parseArguments(List<String> arguments) {
  String? hostRoot;
  String? leasePath;
  var startupTimeoutMs = 30000;
  var readyTimeoutMs = 300000;
  for (var index = 0; index < arguments.length; index++) {
    final option = arguments[index];
    if (!const <String>{
      '--host-root',
      '--watch-lease',
      '--startup-timeout-ms',
      '--ready-timeout-ms',
    }.contains(option)) {
      return _WatchStartupArguments(error: 'Unknown option: $option');
    }
    if (index + 1 >= arguments.length) {
      return _WatchStartupArguments(error: 'Missing value for $option.');
    }
    final value = arguments[++index];
    switch (option) {
      case '--host-root':
        hostRoot = value;
      case '--watch-lease':
        leasePath = value;
      case '--startup-timeout-ms':
        final parsed = int.tryParse(value);
        if (parsed == null || parsed <= 0) {
          return const _WatchStartupArguments(
            error: '--startup-timeout-ms must be a positive integer.',
          );
        }
        startupTimeoutMs = parsed;
      case '--ready-timeout-ms':
        final parsed = int.tryParse(value);
        if (parsed == null || parsed <= 0) {
          return const _WatchStartupArguments(
            error: '--ready-timeout-ms must be a positive integer.',
          );
        }
        readyTimeoutMs = parsed;
    }
  }
  if (hostRoot == null || leasePath == null) {
    return const _WatchStartupArguments(
      error: '--host-root and --watch-lease are required.',
    );
  }
  return _WatchStartupArguments(
    hostRoot: hostRoot,
    leasePath: leasePath,
    startupTimeoutMs: startupTimeoutMs,
    readyTimeoutMs: readyTimeoutMs,
  );
}
