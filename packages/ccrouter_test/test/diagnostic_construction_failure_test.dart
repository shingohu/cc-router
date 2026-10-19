import 'dart:async';

import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:leak_tracker/leak_tracker.dart' show forceGC;
import 'package:test/test.dart';

enum _FailureStage { manifest, registrar, serviceOverride }

final _hostZoneKey = Object();
final _registrarError = StateError('fixture registrar failure');
final _registrarStack = StackTrace.fromString('original registrar stack');

final class _Registrar implements CCComponentRegistrar {
  const _Registrar(this.fail);
  final bool fail;

  @override
  void register(CCRegistry registry) {
    if (fail) Error.throwWithStackTrace(_registrarError, _registrarStack);
  }
}

final class _Probe {
  final events = <String>[];
  final zones = <Object?>[];

  void record(CCDiagnosticEvent event) {
    events.add('${event.operation}:${event.status}:${event.target}');
    zones.add(Zone.current[_hostZoneKey]);
  }
}

final class _HeldSink implements CCDiagnosticSink {
  _HeldSink(this.pending, this.probe);
  final Future<void> pending;
  final _Probe probe;

  @override
  Future<void> record(CCDiagnosticEvent event) {
    probe.record(event);
    return pending;
  }
}

final class _SyncSink implements CCDiagnosticSink {
  _SyncSink(this.mode, this.probe);
  final String mode;
  final _Probe probe;

  @override
  FutureOr<void> record(CCDiagnosticEvent event) {
    probe.record(event);
    if (mode == 'throw') throw StateError('isolated Sink error');
    if (mode == 'synchronousFuture') return SynchronousFuture<void>(null);
  }
}

void _construct(CCDiagnosticSink? sink, _FailureStage stage) {
  final diagnostics = CCDiagnosticsConfig(
    sink: sink,
    defaultMinimumLevel: CCDiagnosticLevel.debug,
  );
  final components = [
    CCComponentManifest(
      id: stage == _FailureStage.manifest ? 'INVALID' : 'fixture',
      version: '1.0.0',
      registrar: _Registrar(stage == _FailureStage.registrar),
    ),
  ];
  if (stage == _FailureStage.serviceOverride) {
    CCRouterRuntime.forTesting(
      diagnostics: diagnostics,
      components: components,
      serviceOverrides: [
        CCServiceOverrideEntry<Object>(factory: (_) => Object()),
      ],
    );
  } else {
    CCRouterRuntime.forHost(diagnostics: diagnostics, components: components);
  }
}

void _expectConstructionFailure(CCDiagnosticSink? sink, _FailureStage stage) {
  Object? caught;
  StackTrace? caughtStack;
  try {
    runZoned(() => _construct(sink, stage), zoneValues: {_hostZoneKey: 'host'});
  } catch (error, stack) {
    caught = error;
    caughtStack = stack;
  }
  if (stage == _FailureStage.registrar) {
    expect(caught, same(_registrarError));
    expect(caughtStack.toString(), _registrarStack.toString());
  } else {
    expect(caught, isA<CCRegistrationError>());
  }
}

WeakReference<CCDiagnosticSink> _failedSink(
  Future<void> pending,
  _Probe probe,
  _FailureStage stage,
) {
  final sink = _HeldSink(pending, probe);
  final reference = WeakReference<CCDiagnosticSink>(sink);
  _expectConstructionFailure(sink, stage);
  return reference;
}

Future<void> _turn() => Future<void>.delayed(Duration.zero);

void main() {
  test('construction without a Sink does not schedule diagnostic cleanup', () {
    runZoned(
      () => _expectConstructionFailure(null, _FailureStage.registrar),
      zoneSpecification: ZoneSpecification(
        createTimer: (_, _, _, _, _) => throw StateError('unexpected Timer'),
      ),
    );
  });

  for (final stage in _FailureStage.values) {
    test(
      '$stage preserves startup error if terminal scheduling fails',
      () async {
        var timers = 0;
        final pending = Completer<void>();
        final probe = _Probe();
        final reference = runZoned(
          () => _failedSink(pending.future, probe, stage),
          zoneSpecification: ZoneSpecification(
            createTimer: (_, parent, zone, duration, callback) {
              timers++;
              if (timers == 2) throw StateError('terminal scheduling rejected');
              return parent.createTimer(zone, duration, callback);
            },
          ),
        );
        try {
          expect(timers, 2);
          await _turn();
          expect(probe.events, isEmpty);
          await forceGC(fullGcCycles: 3);
          expect(reference.target, isNull);
        } finally {
          pending.complete();
        }
      },
    );

    for (final lateError in [false, true]) {
      test(
        '$stage releases Sink with unfinished Future; lateError=$lateError',
        () async {
          // Future creation and the retained probe do not capture the Sink or a
          // construction Zone. Only the framework's delivery callback can do so.
          final pending = Completer<void>();
          final probe = _Probe();
          final reference = _failedSink(pending.future, probe, stage);
          expect(
            probe.events,
            isEmpty,
          ); // Preserve asynchronous startup logging.
          try {
            await _turn();
            expect(probe.events, hasLength(1));
            expect(probe.zones, ['host']);
            await forceGC(fullGcCycles: 3);
            expect(reference.target, isNull);
            expect(pending.isCompleted, isFalse);
          } finally {
            if (lateError) {
              pending.completeError(StateError('late Sink failure'));
            } else {
              pending.complete();
            }
            await _turn();
            await _turn();
          }
          expect(
            probe.events,
            hasLength(1),
          ); // Never resume the discarded queue.
        },
      );
    }

    for (final mode in ['sync', 'throw', 'synchronousFuture']) {
      test(
        '$stage preserves deferred final diagnostics with $mode Sink',
        () async {
          final probe = _Probe();
          final sink = _SyncSink(mode, probe);
          _expectConstructionFailure(sink, stage);
          expect(probe.events, isEmpty);
          await _turn();
          final expected = switch (stage) {
            _FailureStage.manifest => [
              'componentGraph:started:null',
              'componentGraph:failed:null',
            ],
            _FailureStage.registrar => [
              'componentGraph:started:null',
              'componentRegistration:started:fixture',
              'componentRegistration:failed:fixture',
              'componentGraph:failed:null',
            ],
            _FailureStage.serviceOverride => [
              'componentGraph:started:null',
              'componentRegistration:started:fixture',
              'componentRegistration:succeeded:fixture',
              'componentGraph:succeeded:null',
            ],
          };
          expect(probe.events, expected);
          expect(probe.zones, everyElement('host'));
          await _turn();
          expect(probe.events, expected);
        },
      );
    }
  }
}
