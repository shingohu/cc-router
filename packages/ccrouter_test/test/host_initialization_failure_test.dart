import 'dart:async';

import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:leak_tracker/leak_tracker.dart' show forceGC;
import 'package:test/test.dart';

final _constructionError = StateError('fixture constructor failure');
final _constructionStack = StackTrace.fromString('original constructor stack');

final class _Registrar implements CCComponentRegistrar {
  const _Registrar({this.constructionFailure = false});
  final bool constructionFailure;

  @override
  void register(CCRegistry registry) {
    if (constructionFailure) {
      Error.throwWithStackTrace(_constructionError, _constructionStack);
    }
    registry.registerInitTask(
      CCInitTaskDefinition(
        id: 'fixture.prepare',
        dependsOn: const ['missing.prepare'],
        gate: CCInitTaskGate.appStarted,
        failurePolicy: CCInitTaskFailurePolicy.required,
        run: (_) => fail('Invalid InitTask must never run'),
      ),
    );
  }
}

final class _Binding implements CCHostLifecycleBinding {
  _Binding(this.id, this.onDetach);
  @override
  final String id;
  final void Function() onDetach;
  @override
  void attach() {}
  @override
  void detach() => onDetach();
}

final class _Tool implements CCHostToolIntegration {
  @override
  String get id => 'fixture.tool';
  final calls = <String>[];
  @override
  void onRuntimeReady() => calls.add('ready');
  @override
  void onRuntimeStopping() => calls.add('stopping');
}

final class _Probe {
  final events = <String>[];
  void record(CCDiagnosticEvent event) =>
      events.add('${event.operation}:${event.status}');
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

final class _ImmediateSink implements CCDiagnosticSink {
  _ImmediateSink(this.mode, this.probe);
  final String mode;
  final _Probe probe;
  @override
  FutureOr<void> record(CCDiagnosticEvent event) {
    probe.record(event);
    if (mode == 'throw') throw StateError('isolated Sink failure');
    if (mode == 'SynchronousFuture') return SynchronousFuture<void>(null);
  }
}

CCHostAssembly _invalidAssembly({
  Iterable<CCHostLifecycleBinding> bindings = const [],
  Iterable<CCHostToolIntegration> tools = const [],
  bool constructionFailure = false,
}) => CCHostAssembly.withLifecycleBindings(
  CCHostAssembly.fromComponents(
    components: [
      CCComponentManifest(
        id: 'fixture',
        version: '1.0.0',
        registrar: _Registrar(constructionFailure: constructionFailure),
      ),
    ],
    hostToolIntegrations: tools,
  ),
  bindings,
);

CCHostAssembly _emptyAssembly() =>
    CCHostAssembly.fromComponents(components: const []);

void _expectStartupFailure({CCHostAssembly? assembly, CCDiagnosticSink? sink}) {
  expect(
    () => CCRouterHost.initialize(
      hostAssembly: assembly ?? _invalidAssembly(),
      diagnostics: CCDiagnosticsConfig(
        sink: sink,
        defaultMinimumLevel: CCDiagnosticLevel.debug,
      ),
    ),
    throwsA(isA<CCRegistrationError>()),
  );
  expect(CCRouter.isInitialized, isFalse);
}

WeakReference<_HeldSink> _failWithHeldSink(Future<void> pending, _Probe probe) {
  final sink = _HeldSink(pending, probe);
  final reference = WeakReference(sink);
  _expectStartupFailure(sink: sink);
  return reference;
}

Future<void> _turn() => Future<void>.delayed(Duration.zero);

Zone _guardedZone(List<Object> uncaught) {
  late Zone zone;
  runZonedGuarded(() => zone = Zone.current, (error, _) => uncaught.add(error));
  return zone;
}

Future<({Object? error, StackTrace? stack, Zone zone})>
_observeShutdown() async {
  try {
    await CCRouterHost.shutdown();
    return (error: null, stack: null, zone: Zone.current);
  } catch (error, stack) {
    return (error: error, stack: stack, zone: Zone.current);
  }
}

void main() {
  tearDown(CCRouterHost.shutdown);

  for (final rollback in [true, false]) {
    for (final cleanupFails in [false, true]) {
      test('cleanup waiters in owner, parent and sibling error Zones: '
          'rollback=$rollback, failure=$cleanupFails', () async {
        final uncaught = <Object>[];
        final owner = _guardedZone(uncaught);
        final sibling = _guardedZone(uncaught);
        final parent = Zone.current;
        final cleanupError = StateError('fixture cleanup failure');
        final cleanupStack = StackTrace.fromString('original cleanup stack');
        var detachCount = 0;
        final binding = _Binding('fixture', () {
          detachCount++;
          if (cleanupFails) {
            Error.throwWithStackTrace(cleanupError, cleanupStack);
          }
        });
        final assembly = rollback
            ? _invalidAssembly(bindings: [binding])
            : CCHostAssembly.withLifecycleBindings(_emptyAssembly(), [binding]);

        final ownerWait = owner.run(() {
          if (rollback) {
            _expectStartupFailure(assembly: assembly);
          } else {
            CCRouterHost.initialize(hostAssembly: assembly);
          }
          return _observeShutdown();
        });
        final parentWait = _observeShutdown();
        final siblingWait = sibling.run(_observeShutdown);
        expect(
          () => CCRouterHost.initialize(hostAssembly: _emptyAssembly()),
          throwsA(isA<CCRouterAlreadyInitializedError>()),
        );
        final results = await Future.wait([
          ownerWait,
          parentWait,
          siblingWait,
        ]).timeout(const Duration(seconds: 1));

        for (final result in results) {
          expect(result.error, cleanupFails ? same(cleanupError) : isNull);
          expect(
            result.stack?.toString(),
            cleanupFails ? cleanupStack.toString() : isNull,
          );
        }
        expect(results.map((result) => result.zone), [owner, parent, sibling]);
        expect(detachCount, 1);
        expect(uncaught, isEmpty);
        expect(CCRouter.isInitialized, isFalse);
        await CCRouterHost.shutdown();
        CCRouterHost.initialize(hostAssembly: _emptyAssembly());
      });
    }

    test(
      'detach callback joins cleanup from another error Zone: rollback=$rollback',
      () async {
        final uncaught = <Object>[];
        final owner = _guardedZone(uncaught);
        final sibling = _guardedZone(uncaught);
        final cleanupError = StateError('reentrant detach failure');
        final cleanupStack = StackTrace.fromString('reentrant detach stack');
        Future<({Object? error, StackTrace? stack, Zone zone})>? joined;
        Object? reentryError;
        var joinedCompleted = false;
        final binding = _Binding('fixture', () {
          try {
            CCRouterHost.initialize(hostAssembly: _emptyAssembly());
          } catch (error) {
            reentryError = error;
          }
          joined = sibling.run(() async {
            final result = await _observeShutdown();
            // This waiter can finish before the initiating shutdown resumes.
            CCRouterHost.initialize(hostAssembly: _emptyAssembly());
            return result;
          });
          unawaited(joined!.then((_) => joinedCompleted = true));
          Error.throwWithStackTrace(cleanupError, cleanupStack);
        });
        final ownerWait = owner.run(() {
          if (rollback) {
            _expectStartupFailure(
              assembly: _invalidAssembly(bindings: [binding]),
            );
          } else {
            CCRouterHost.initialize(
              hostAssembly: CCHostAssembly.withLifecycleBindings(
                _emptyAssembly(),
                [binding],
              ),
            );
          }
          return _observeShutdown();
        });
        expect(reentryError, isA<CCRouterAlreadyInitializedError>());
        expect(joinedCompleted, isFalse);
        final results = await Future.wait([
          ownerWait,
          joined!,
        ]).timeout(const Duration(seconds: 1));
        expect(
          results.map((result) => result.error),
          everyElement(same(cleanupError)),
        );
        expect(
          results.map((result) => result.stack.toString()),
          everyElement(cleanupStack.toString()),
        );
        expect(joinedCompleted, isTrue);
        expect(uncaught, isEmpty);
        expect(CCRouter.isInitialized, isTrue);
      },
    );
  }

  for (final lateError in [false, true]) {
    test(
      'Host rollback releases Sink before write completes; error=$lateError',
      () async {
        // Keep only the Future/probe alive outside the helper; neither owns Sink.
        final pending = Completer<void>();
        final probe = _Probe();
        final reference = _failWithHeldSink(pending.future, probe);
        try {
          await CCRouterHost.shutdown();
          await _turn();
          expect(probe.events, hasLength(1));
          await forceGC(fullGcCycles: 3);
          expect(reference.target, isNull);
        } finally {
          if (lateError) {
            pending.completeError(StateError('late Sink failure'));
          } else {
            pending.complete();
          }
          await _turn();
        }
        expect(probe.events, hasLength(1));
        CCRouterHost.initialize(hostAssembly: _emptyAssembly());
        expect(CCRouter.isInitialized, isTrue);
      },
    );
  }

  test(
    'rollback blocks reentry and reentrant shutdown waits for cleanup',
    () async {
      final detached = <String>[];
      final joined = <Future<void>>[];
      var joinedCount = 0;
      final tool = _Tool();
      final base = _emptyAssembly();
      void detach(String id) {
        detached.add(id);
        expect(CCRouter.isInitialized, isFalse);
        expect(
          () => CCRouterHost.initialize(hostAssembly: base),
          throwsA(isA<CCRouterAlreadyInitializedError>()),
        );
        final future = CCRouterHost.shutdown();
        joined.add(future);
        unawaited(future.then((_) => joinedCount++));
      }

      _expectStartupFailure(
        assembly: _invalidAssembly(
          bindings: [
            _Binding('first', () => detach('first')),
            _Binding('second', () => detach('second')),
          ],
          tools: [tool],
        ),
      );
      expect(detached, ['second', 'first']);
      expect(joinedCount, 0);
      expect(
        () => CCRouterHost.initialize(hostAssembly: base),
        throwsA(isA<CCRouterAlreadyInitializedError>()),
      );
      await CCRouterHost.shutdown();
      await Future.wait(joined);
      expect(joinedCount, 2);
      expect(tool.calls, isEmpty);
      await CCRouterHost.shutdown();
      expect(detached, ['second', 'first']);
      CCRouterHost.initialize(hostAssembly: base);
      expect(CCRouter.isInitialized, isTrue);
    },
  );

  test(
    'detach error preserves startup stack and shutdown reports cleanup error',
    () async {
      final cleanupError = StateError('fixture detach failure');
      final cleanupStack = StackTrace.fromString('original detach stack');
      final detached = <String>[];
      final probe = _Probe();
      Object? startupError;
      StackTrace? startupStack;
      try {
        CCRouterHost.initialize(
          diagnostics: CCDiagnosticsConfig(
            sink: _ImmediateSink('sync', probe),
            defaultMinimumLevel: CCDiagnosticLevel.debug,
          ),
          hostAssembly: _invalidAssembly(
            bindings: [
              _Binding('first', () => detached.add('first')),
              _Binding('second', () {
                detached.add('second');
                Error.throwWithStackTrace(cleanupError, cleanupStack);
              }),
            ],
          ),
        );
      } catch (error, stack) {
        startupError = error;
        startupStack = stack;
      }
      expect(startupError, isA<CCRegistrationError>());
      expect(startupStack.toString(), contains('_validateInitTasks'));
      expect(detached, ['second', 'first']);
      Object? observedError;
      StackTrace? observedStack;
      try {
        await CCRouterHost.shutdown();
      } catch (error, stack) {
        observedError = error;
        observedStack = stack;
      }
      expect(observedError, same(cleanupError));
      expect(observedStack.toString(), cleanupStack.toString());
      expect(probe.events, contains('runtimeInitialize:failed'));
      CCRouterHost.initialize(hostAssembly: _emptyAssembly());
    },
  );

  test(
    'unobserved rollback errors are handled and gate clears automatically',
    () async {
      final uncaught = <Object>[];
      var detached = 0;
      runZonedGuarded(
        () => _expectStartupFailure(
          assembly: _invalidAssembly(
            bindings: [
              _Binding('fixture', () {
                detached++;
                throw StateError('unobserved detach failure');
              }),
            ],
          ),
        ),
        (error, _) => uncaught.add(error),
      );
      await _turn();
      await _turn();
      expect(detached, 1);
      expect(uncaught, isEmpty);
      CCRouterHost.initialize(hostAssembly: _emptyAssembly());
      expect(CCRouter.isInitialized, isTrue);
    },
  );

  for (final mode in ['sync', 'throw', 'SynchronousFuture']) {
    test(
      'rollback retains best-effort startup diagnostics for $mode Sink',
      () async {
        final probe = _Probe();
        _expectStartupFailure(sink: _ImmediateSink(mode, probe));
        await CCRouterHost.shutdown();
        expect(probe.events, contains('runtimeInitialize:failed'));
        expect(probe.events, isNot(contains('runtimeInitialize:succeeded')));
        final delivered = probe.events.length;
        await _turn();
        expect(probe.events, hasLength(delivered));
      },
    );
  }

  test('constructor failure preserves identity, stack and immediate retry', () {
    final detached = <String>[];
    Object? observedError;
    StackTrace? observedStack;
    try {
      CCRouterHost.initialize(
        hostAssembly: _invalidAssembly(
          constructionFailure: true,
          bindings: [
            _Binding('fixture', () {
              detached.add('fixture');
              throw StateError('secondary detach failure');
            }),
          ],
        ),
      );
    } catch (error, stack) {
      observedError = error;
      observedStack = stack;
    }
    expect(observedError, same(_constructionError));
    expect(observedStack.toString(), _constructionStack.toString());
    expect(detached, ['fixture']);
    CCRouterHost.initialize(hostAssembly: _emptyAssembly());
    expect(CCRouter.isInitialized, isTrue);
  });

  test(
    'low-level Runtime initialize failure keeps disposal with its owner',
    () async {
      final runtime = CCRouterRuntime.forHost(
        components: _invalidAssembly().componentManifests,
      );
      expect(runtime.initialize, throwsA(isA<CCRegistrationError>()));
      expect(runtime.appScope.cancellation.isCancelled, isFalse);
      await runtime.dispose();
      expect(runtime.appScope.cancellation.isCancelled, isTrue);
    },
  );
}
