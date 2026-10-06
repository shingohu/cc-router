import 'package:test/test.dart';

import '../../ccrouter_generator/bin/src/build_runner_phase_report.dart';

void main() {
  test('collects only completed required phases', () {
    final collector = CCBuildRunnerPhaseCollector()
      ..addLine(
        '  0.00s ccrouter_generator:routes on 38 inputs; '
        'demo|lib/src/page.dart',
      )
      ..addLine(
        '  0.00s ccrouter_generator:routes on 38 inputs: 1 skipped; '
        'demo|lib/src/other.dart',
      )
      ..addLine(
        '  3.90s ccrouter_generator:routes on 38 inputs: '
        '37 skipped, 1 same; spent 3.18s\u00a0analyzing, '
        '0.67s\u00a0resolving, 0.04s\u00a0reading',
      );

    final report = collector
        .finish('Built with build_runner/aot in 4.26s; wrote 3 outputs.')
        .toJson();

    expect(report['durationMs'], 4260);
    expect(report['writtenOutputs'], 3);
    expect(report['formatVersion'], 2);
    expect(report['available'], isTrue);
    expect(report['unparsedFinalLines'], isNull);
    expect(report['totals'], {
      'phases': 1,
      'inputs': 38,
      'skipped': 37,
      'notTriggered': 0,
      'invalidatedInputs': 1,
      'executedInputs': 1,
      'outputs': 0,
      'sameOutputs': 1,
      'noOp': 0,
    });
    expect((report['phases'] as List).single, {
      'name': 'ccrouter_generator:routes',
      'durationMs': 3900,
      'inputs': 38,
      'skipped': 37,
      'notTriggered': 0,
      'invalidatedInputs': 1,
      'executedInputs': 1,
      'outputs': 0,
      'sameOutputs': 1,
      'noOp': 0,
      'activitiesMs': {'analyzing': 3180, 'resolving': 670, 'reading': 40},
    });
  });

  test('collects lazy phases and every execution outcome', () {
    final collector = CCBuildRunnerPhaseCollector()
      ..addLine(
        '0.12s ccrouter_generator:routes (lazy): 1 not triggered, '
        '2 outputs, 3 same, 4 no-op',
      );

    final phase =
        (collector
                        .finish(
                          'Built with build_runner/jit in 0.20s; wrote 5 outputs.',
                        )
                        .toJson()['phases']
                    as List)
                .single
            as Map<String, Object?>;

    expect(phase['inputs'], isNull);
    expect(phase['invalidatedInputs'], 10);
    expect(phase['executedInputs'], 9);
    expect(phase['outputs'], 2);
    expect(phase['sameOutputs'], 3);
    expect(phase['noOp'], 4);
  });

  test('retains malformed terminal lines without failing collection', () {
    final collector = CCBuildRunnerPhaseCollector()
      ..addLine(
        '0.10s ccrouter_generator:routes on 2 inputs: 1 skipped, '
        '1 upstream-new-counter',
      )
      ..addLine(
        '0.20s ccrouter_generator:services on 2 inputs: 1 skipped, 1 no-op',
      );

    final report = collector
        .finish(
          'Failed to build with build_runner/aot in 0.30s; wrote 0 outputs.',
        )
        .toJson();

    expect((report['phases'] as List), hasLength(1));
    expect(
      report['unparsedFinalLines'],
      contains(contains('upstream-new-counter')),
    );
  });

  test('reset isolates consecutive watch cycles', () {
    final collector = CCBuildRunnerPhaseCollector()
      ..addLine('0.10s ccrouter_generator:routes on 1 input: 1 skipped')
      ..reset()
      ..addLine('0.20s ccrouter_generator:services on 1 input: 1 no-op');

    final phases =
        collector
                .finish(
                  'Built with build_runner/aot in 0.20s; wrote 0 outputs.',
                )
                .toJson()['phases']
            as List;

    expect(phases, hasLength(1));
    expect((phases.single as Map)['name'], 'ccrouter_generator:services');
  });

  test('does not encode unavailable phase details as zero counters', () {
    final collector = CCBuildRunnerPhaseCollector();

    final report = collector
        .finish(
          'Built with build_runner/aot in 0.20s; wrote 0 outputs.',
          phaseDetailsAvailable: false,
        )
        .toJson();

    expect(report['formatVersion'], 2);
    expect(report['available'], isFalse);
    expect(report['reason'], 'profile-disabled');
    expect(report['durationMs'], 200);
    expect(report['writtenOutputs'], 0);
    expect(report.containsKey('totals'), isFalse);
    expect(report.containsKey('phases'), isFalse);
  });
}
