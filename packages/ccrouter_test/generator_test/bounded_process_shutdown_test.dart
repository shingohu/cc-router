@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import '../../ccrouter_generator/bin/src/bounded_process_shutdown.dart';

void main() {
  test(
    'stops after SIGINT without escalating',
    () async {
      final fixture = await _startSignalFixture('interrupt');
      addTearDown(fixture.close);

      final result = await stopProcessWithEscalation(
        fixture.process,
        interruptTimeout: const Duration(seconds: 1),
        terminateTimeout: const Duration(milliseconds: 100),
        killTimeout: const Duration(milliseconds: 100),
      );

      expect(result, 17);
      expect(fixture.trace.readAsLinesSync(), <String>['ready', 'SIGINT']);
    },
    skip: Platform.isWindows ? 'POSIX signal ordering' : false,
  );

  test(
    'escalates from ignored SIGINT to SIGTERM',
    () async {
      final fixture = await _startSignalFixture('terminate');
      addTearDown(fixture.close);

      final result = await stopProcessWithEscalation(
        fixture.process,
        interruptTimeout: const Duration(milliseconds: 100),
        terminateTimeout: const Duration(seconds: 1),
        killTimeout: const Duration(milliseconds: 100),
      );

      expect(result, 18);
      expect(fixture.trace.readAsLinesSync(), <String>[
        'ready',
        'SIGINT',
        'SIGTERM',
      ]);
    },
    skip: Platform.isWindows ? 'POSIX signal ordering' : false,
  );

  test(
    'escalates to SIGKILL when graceful signals are ignored',
    () async {
      final fixture = await _startSignalFixture('kill');
      addTearDown(fixture.close);
      final watch = Stopwatch()..start();

      final result = await stopProcessWithEscalation(
        fixture.process,
        interruptTimeout: const Duration(milliseconds: 100),
        terminateTimeout: const Duration(milliseconds: 100),
        killTimeout: const Duration(seconds: 1),
      );

      expect(result, isNot(0));
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
      expect(fixture.trace.readAsLinesSync(), <String>[
        'ready',
        'SIGINT',
        'SIGTERM',
      ]);
    },
    skip: Platform.isWindows ? 'POSIX signal ordering' : false,
  );
}

final class _SignalFixture {
  const _SignalFixture({
    required this.directory,
    required this.process,
    required this.trace,
  });

  final Directory directory;
  final Process process;
  final File trace;

  Future<void> close() async {
    process.kill(ProcessSignal.sigkill);
    try {
      await process.exitCode.timeout(const Duration(seconds: 1));
    } on TimeoutException {
      // The test result already reports a child that could not be reaped.
    }
    if (directory.existsSync()) await directory.delete(recursive: true);
  }
}

Future<_SignalFixture> _startSignalFixture(String mode) async {
  final directory = await Directory.systemTemp.createTemp(
    'ccrouter_process_shutdown_',
  );
  final trace = File(path.join(directory.path, 'trace.txt'));
  final script = File(path.join(directory.path, 'signal_child.dart'))
    ..writeAsStringSync(r'''
import 'dart:async';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  final mode = arguments[0];
  final trace = File(arguments[1]);
  ProcessSignal.sigint.watch().listen((_) {
    trace.writeAsStringSync('SIGINT\n', mode: FileMode.append);
    if (mode == 'interrupt') exit(17);
  });
  ProcessSignal.sigterm.watch().listen((_) {
    trace.writeAsStringSync('SIGTERM\n', mode: FileMode.append);
    if (mode == 'terminate') exit(18);
  });
  trace.writeAsStringSync('ready\n');
  await Completer<void>().future;
}
''');
  final process = await Process.start(Platform.resolvedExecutable, <String>[
    script.path,
    mode,
    trace.path,
  ]);
  final stderrOutput = process.stderr
      .transform(SystemEncoding().decoder)
      .join();
  try {
    await _waitFor(() => trace.existsSync());
  } on Object {
    process.kill(ProcessSignal.sigkill);
    final errors = await stderrOutput;
    await directory.delete(recursive: true);
    throw StateError('Signal fixture failed to start: $errors');
  }
  return _SignalFixture(directory: directory, process: process, trace: trace);
}

Future<void> _waitFor(bool Function() predicate) async {
  final watch = Stopwatch()..start();
  while (!predicate()) {
    if (watch.elapsed > const Duration(seconds: 5)) {
      throw TimeoutException('Timed out waiting for signal fixture.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
