import 'dart:async';

import 'package:ccrouter/ccrouter_generated.dart';
import 'package:ccrouter/ccrouter_test.dart' show CCRouterTestBinding;
import 'package:ccrouter_core/ccrouter_core.dart' show CCRouterRuntime;
import 'package:ccrouter_test/ccrouter_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leak_tracker/leak_tracker.dart' show forceGC;

final class _StreamService implements CCDisposable {
  _StreamService(this.source);
  final Stream<int> source;
  int calls = 0;
  int disposals = 0;
  CCInvocationContext? context;

  Stream<int> watch(CCInvocationContext invocation) {
    calls++;
    context = invocation;
    return source;
  }

  @override
  void dispose() {
    disposals++;
  }
}

final class _Parent {}

final class _Registrar implements CCComponentRegistrar {
  _Registrar(this.service, this.scope, this.initialize);
  final _StreamService service;
  final CCServiceScope scope;
  final Future<void> Function()? initialize;

  @override
  void register(CCRegistry registry) {
    registry.registerService<_StreamService>(
      CCServiceProvider(
        contractToken: const CCServiceToken<_StreamService>('owner.stream'),
        scope: scope,
        factory: (_) => service,
        initializer: initialize == null ? null : (_, _) => initialize!(),
      ),
    );
    registry.registerService<_Parent>(
      CCServiceProvider(
        contractToken: const CCServiceToken<_Parent>('owner.parent'),
        scope: CCServiceScope.session,
        factory: (_) => _Parent(),
      ),
    );
  }
}

CCRouterTestHost _host(
  _StreamService service, {
  CCServiceScope scope = CCServiceScope.app,
  Future<void> Function()? initialize,
}) {
  final host = CCRouterTestHost(
    components: [
      CCComponentManifest(
        id: 'owner',
        version: '1.0.0',
        registrar: _Registrar(service, scope, initialize),
      ),
    ],
  );
  addTearDown(host.dispose);
  host.initialize();
  return host;
}

Stream<int> _watch(
  CCRouterTestHost host, {
  CCCancellationToken? cancellation,
  Duration? timeout,
}) => host.runtime.invokeServiceStream<_StreamService, int>(
  methodId: 'watch',
  cancellation: cancellation,
  timeout: timeout,
  call: (service, context) => service.watch(context),
);

Future<void> _turn() => Future<void>.delayed(Duration.zero);

Future<(Stream<int>, WeakReference<Object>)> _completedStreamWithPayload(
  CCRouterTestHost host,
) async {
  final payload = Object();
  final stream = runZoned(
    () => _watch(host),
    zoneValues: {#streamCaller: payload},
  );
  await stream.toList();
  return (stream, WeakReference(payload));
}

Future<(WeakReference<CCRouterRuntime>, Future<void>)> _retirePendingStream(
  Stream<int> source,
) async {
  final runtime = CCRouterRuntime.forTesting(
    components: [
      CCComponentManifest(
        id: 'owner',
        version: '1.0.0',
        registrar: _Registrar(_StreamService(source), CCServiceScope.app, null),
      ),
    ],
  )..initialize();
  final subscription = runtime
      .invokeServiceStream<_StreamService, int>(
        methodId: 'watch',
        call: (service, context) => service.watch(context),
      )
      .listen((_) {});
  await _turn();
  final cancelling = subscription.cancel();
  await CCRouterTestBinding.runWithRuntime(
    runtime,
    () => runtime.appScope.close(timeout: const Duration(milliseconds: 10)),
  );
  await runtime.dispose();
  return (WeakReference(runtime), cancelling);
}

Future<(Stream<int>, WeakReference<CCRouterRuntime>)>
_unusedAfterShutdown() async {
  final runtime = CCRouterRuntime.forTesting(
    components: [
      CCComponentManifest(
        id: 'owner',
        version: '1.0.0',
        registrar: _Registrar(
          _StreamService(const Stream.empty()),
          CCServiceScope.app,
          null,
        ),
      ),
    ],
  )..initialize();
  final stream = runtime.invokeServiceStream<_StreamService, int>(
    methodId: 'watch',
    call: (service, context) => service.watch(context),
  );
  await runtime.dispose();
  return (stream, WeakReference(runtime));
}

WeakReference<Object> _queuePayload(StreamController<Object> source) {
  final payload = Object();
  source.add(payload);
  return WeakReference(payload);
}

WeakReference<Stream<int>> _abandonUnlistened(CCRouterTestHost host) =>
    WeakReference(_watch(host));

Future<(Stream<int>, WeakReference<Object>)> _unlistenedConsumerStream(
  CCRouterTestHost host,
) async {
  final payload = Object();
  final stream = runZoned(
    () => host.runtime.invokeServiceSync<_Parent, Stream<int>>(
      methodId: 'create',
      call: (_, _) => _watch(host),
    ),
    zoneValues: {#pendingConsumer: payload},
  );
  await host.runtime.closeSession();
  return (stream, WeakReference(payload));
}

final class _ReviewSink implements CCDiagnosticSink {
  final events = <CCDiagnosticEvent>[];
  @override
  Future<void> record(CCDiagnosticEvent event) async {
    events.add(event);
  }
}

// A legal single-subscription source that emits synchronously when resumed.
final class _ResumeSource extends Stream<Object> {
  _ResumeSource({this.finishOnResume = false});
  final bool finishOnResume;
  final _carrier = StreamController<Object>();
  WeakReference<Object>? payloadReference;
  @override
  StreamSubscription<Object> listen(
    void Function(Object)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final zone = Zone.current;
    void Function(Object)? handler = onData == null
        ? null
        : zone.bindUnaryCallbackGuarded(onData);
    void Function()? finish = onDone == null
        ? null
        : zone.bindCallbackGuarded(onDone);
    final inner = _carrier.stream.listen(
      null,
      onError: onError,
      onDone: null,
      cancelOnError: cancelOnError,
    );
    _carrier.onResume = () {
      final value = Object();
      payloadReference = WeakReference(value);
      handler?.call(value);
      if (finishOnResume) {
        final done = finish;
        unawaited(inner.cancel());
        done?.call();
      }
    };
    _carrier.onCancel = () {
      handler = null;
      finish = null;
      _carrier.onResume = null;
      unawaited(_carrier.close());
    };
    return _ResumeSubscription(inner, (next) {
      handler = next == null ? null : zone.bindUnaryCallbackGuarded(next);
    });
  }
}

final class _ResumeSubscription implements StreamSubscription<Object> {
  _ResumeSubscription(this.inner, this.replace);
  final StreamSubscription<Object> inner;
  final void Function(void Function(Object)?) replace;
  @override
  Future<void> cancel() => inner.cancel();
  @override
  void onData(void Function(Object)? handler) => replace(handler);
  @override
  void onError(Function? handler) => inner.onError(handler);
  @override
  void onDone(void Function()? handler) => inner.onDone(handler);
  @override
  void pause([Future<void>? signal]) => inner.pause(signal);
  @override
  void resume() => inner.resume();
  @override
  bool get isPaused => inner.isPaused;
  @override
  Future<E> asFuture<E>([E? value]) => inner.asFuture<E>(value);
}

bool _payloadAlive(WeakReference<Object>? reference) =>
    reference?.target != null;

final class _CleanupPayloadError implements Exception {
  _CleanupPayloadError(this.payload);
  final Object payload;
}

Future<(Stream<int>, WeakReference<Object>)> _finishedCleanupFailure() async {
  final payload = Object();
  final failure = _CleanupPayloadError(payload);
  final source = StreamController<int>(
    onCancel: () => Future<void>.error(failure),
  );
  final runtime = CCRouterRuntime.forTesting(
    components: [
      CCComponentManifest(
        id: 'owner',
        version: '1.0.0',
        registrar: _Registrar(
          _StreamService(source.stream),
          CCServiceScope.app,
          null,
        ),
      ),
    ],
  )..initialize();
  final token = CCCancellationToken();
  final stream = runtime.invokeServiceStream<_StreamService, int>(
    methodId: 'watch',
    cancellation: token,
    call: (service, context) => service.watch(context),
  );
  final done = Completer<void>();
  stream.listen((_) {}, onError: (Object _) {}, onDone: done.complete);
  await _turn();
  token.cancel();
  await done.future;
  await runtime.dispose();
  await source.close();
  return (stream, WeakReference(payload));
}

Future<WeakReference<Object>> _cancelWithPendingResumeSignal(
  CCRouterTestHost host,
  Future<void> signal,
) async {
  final payload = Object();
  final sub = runZoned(
    () => _watch(host).listen((_) {}),
    zoneValues: {#resumeConsumer: payload},
  );
  runZoned(() => sub.pause(signal), zoneValues: {#pauseCaller: payload});
  await _turn();
  await sub.cancel();
  return WeakReference(payload);
}

void main() {
  test(
    'resumeSignal preserves the original pause caller Zone while live',
    () async {
      Object? seen;
      final source = StreamController<int>(
        onResume: () {
          seen = Zone.current[#pauseContext];
        },
      );
      final host = _host(_StreamService(source.stream));
      final sub = _watch(host).listen((_) {});
      final signal = Completer<void>();
      await _turn();
      runZoned(
        () => sub.pause(signal.future),
        zoneValues: {#pauseContext: 'original pause'},
      );
      signal.complete();
      await _turn();
      expect(seen, 'original pause');
      await sub.cancel();
      await source.close();
    },
  );

  test(
    'retained completed Stream does not retain a cleanup exception payload',
    () async {
      final retained = await _finishedCleanupFailure();
      await forceGC(fullGcCycles: 3, timeout: const Duration(seconds: 20));
      expect(retained.$2.target, isNull);
      expect(() => retained.$1.listen((_) {}), throwsStateError);
    },
  );

  test(
    'repeated cancel joins errors in each caller Zone and cleans once',
    () async {
      final escaped = <Object>[];
      final producer = runZonedGuarded(
        () => Zone.current,
        (Object e, StackTrace _) => escaped.add(e),
      )!;
      final release = producer.run(Completer<void>.new);
      var cancels = 0;
      final source = StreamController<int>(
        onCancel: () {
          cancels++;
          return release.future;
        },
      );
      final host = _host(_StreamService(source.stream));
      final sub = producer.run(() => _watch(host).listen((_) {}));
      await _turn();
      final original = StateError('joined cleanup');
      final first = producer.run(
        () => expectLater(sub.cancel(), throwsA(same(original))),
      );
      final second = expectLater(sub.cancel(), throwsA(same(original)));
      producer.run(
        () => release.completeError(
          original,
          StackTrace.fromString('joined cancellation'),
        ),
      );
      await first;
      await second;
      expect(cancels, 1);
      expect(escaped, isEmpty);
      await source.close();
    },
  );

  for (final explicit in [false, true]) {
    test(
      'pending cancelOnError ${explicit ? 'is suppressed by explicit cancel' : 'uses updated asFuture handler'}',
      () async {
        final release = Completer<void>();
        final source = StreamController<int>(onCancel: () => release.future);
        final host = _host(_StreamService(source.stream));
        final old = <Object>[];
        final sub = _watch(
          host,
        ).listen((_) {}, onError: old.add, cancelOnError: true);
        await _turn();
        final original = StateError('pending source error');
        source.addError(original);
        await _turn();
        Future<void> observed;
        if (explicit) {
          observed = sub.cancel();
        } else {
          observed = expectLater(sub.asFuture<void>(), throwsA(same(original)));
        }
        release.complete();
        await observed;
        await _turn();
        expect(old, isEmpty);
        await source.close();
      },
    );
  }

  test(
    'handler replacement and typed asFuture preserve native completion',
    () async {
      final source = StreamController<int>();
      final host = _host(_StreamService(source.stream));
      final first = <int>[];
      final replacement = <int>[];
      final sub = _watch(host).listen(first.add);
      sub.onData(replacement.add);
      sub.onError((Object _, StackTrace __) => fail('unexpected error'));
      expect(() => sub.asFuture<int>(), throwsArgumentError);
      final result = sub.asFuture<int>(9);
      await _turn();
      source.add(1);
      await source.close();
      expect(await result, 9);
      expect(first, isEmpty);
      expect(replacement, [1]);
      expect(sub.isPaused, isFalse);
      await sub.cancel();
    },
  );

  for (final cleanupFails in [false, true]) {
    test(
      'asFuture preserves error/stack while cleanup ${cleanupFails ? 'fails' : 'finishes'}',
      () async {
        final release = Completer<void>();
        final cleanupError = StateError('cleanup');
        final source = StreamController<int>(
          onCancel: () async {
            await release.future;
            if (cleanupFails) throw cleanupError;
          },
        );
        final host = _host(_StreamService(source.stream));
        final sub = _watch(host).listen((_) {});
        var completed = false;
        Object? received;
        StackTrace? receivedStack;
        final observed = sub
            .asFuture<int>(1)
            .then<void>(
              (_) {
                completed = true;
              },
              onError: (Object e, StackTrace s) {
                received = e;
                receivedStack = s;
                completed = true;
              },
            );
        await _turn();
        const original = FormatException('source');
        final stack = StackTrace.fromString('asFuture source stack');
        source.addError(original, stack);
        await _turn();
        expect(completed, isFalse);
        release.complete();
        await observed;
        expect(received, same(original));
        expect(receivedStack, same(stack));
        if (cleanupFails) {
          await expectLater(sub.cancel(), throwsA(same(cleanupError)));
        } else {
          await sub.cancel();
        }
        await source.close();
      },
    );
  }

  test(
    'nested pause and resumeSignal preserve pause count and ordering',
    () async {
      final source = StreamController<int>();
      final host = _host(_StreamService(source.stream));
      final values = <int>[];
      final sub = _watch(host).listen(values.add);
      final signal = Completer<void>();
      final done = sub.asFuture<void>();
      await _turn();
      sub.pause(signal.future);
      sub.pause();
      source.add(1);
      signal.complete();
      await _turn();
      expect(sub.isPaused, isTrue);
      expect(values, isEmpty);
      sub.resume();
      await _turn();
      expect(values, [1]);
      await source.close();
      await done;
    },
  );

  test(
    'resumeSignal failure resumes once and reaches the listener error Zone',
    () async {
      final escaped = <Object>[];
      final listener = runZonedGuarded(
        () => Zone.current,
        (Object e, StackTrace _) => escaped.add(e),
      )!;
      final source = StreamController<int>();
      final host = _host(_StreamService(source.stream));
      final values = <int>[];
      final done = Completer<void>();
      final sub = listener.run(
        () => _watch(host).listen(values.add, onDone: done.complete),
      );
      final signal = listener.run(Completer<void>.new);
      await _turn();
      listener.run(() => sub.pause(signal.future));
      source.add(1);
      final error = StateError('resume');
      listener.run(() => signal.completeError(error));
      await _turn();
      expect(escaped, [same(error)]);
      expect(values, [1]);
      expect(sub.isPaused, isFalse);
      await source.close();
      await done.future;
    },
  );

  test(
    'unfinished resumeSignal cannot retain a cancelled consumer payload',
    () async {
      final signal = Completer<void>();
      final source = StreamController<int>();
      final host = _host(_StreamService(source.stream));
      final payload = await _cancelWithPendingResumeSignal(host, signal.future);
      await forceGC(fullGcCycles: 3, timeout: const Duration(seconds: 20));
      expect(payload.target, isNull);
      signal.complete();
      await source.close();
    },
  );

  test(
    'synchronous upstream done commits already delivered values before Scope close',
    () async {
      final source = _ResumeSource(finishOnResume: true);
      final host = _host(
        _StreamService(const Stream.empty()),
        scope: CCServiceScope.session,
      );
      host.runtime.openSession(accountId: 'done');
      final errors = <Object>[];
      final deliveredStates = <Object>[];
      final scope = host.runtime.sessionScope!;
      final done = Completer<void>();
      final sub = host.runtime
          .invokeServiceStream<_StreamService, Object>(
            methodId: 'watch',
            call: (_, _) => source,
          )
          .listen(
            (_) => deliveredStates.add(scope.state),
            onError: errors.add,
            onDone: done.complete,
          );
      await _turn();
      sub.pause();
      sub.resume();
      sub.pause();
      await _turn();
      await host.runtime.closeSession();
      await forceGC(fullGcCycles: 3, timeout: const Duration(seconds: 20));
      expect(_payloadAlive(source.payloadReference), isFalse);
      sub.resume();
      await done.future;
      expect(errors, isEmpty);
      expect(deliveredStates.single.toString(), 'CCScopeState.active');
      expect(host.runtime.recentTraces.single.status, 'succeeded');
    },
  );

  test(
    'cooperative signal and source cancel use the same automatic error Zone',
    () async {
      final escaped = <Object>[];
      final producer = runZonedGuarded(
        () => Zone.current,
        (Object e, StackTrace _) => escaped.add(e),
      )!;
      Completer<void>? cleanup;
      final source = StreamController<int>(onCancel: () => cleanup!.future);
      final service = _StreamService(source.stream);
      final host = _host(service, scope: CCServiceScope.session);
      host.runtime.openSession(accountId: 'automatic');
      final scope = host.runtime.sessionScope!;
      final done = Completer<void>();
      producer.run(
        () => _watch(
          host,
        ).listen((_) {}, onError: (Object _) {}, onDone: done.complete),
      );
      await _turn();
      service.context!.cancellation.addListener(() {
        expect(Zone.current.inSameErrorZone(producer), isTrue);
        cleanup = Completer<void>();
      });
      final closing = host.runtime.closeSession();
      final failure = StateError('cooperative cleanup');
      producer.run(() => cleanup!.completeError(failure));
      await closing;
      await done.future;
      expect(escaped, isEmpty);
      expect(scope.disposalErrors, [same(failure)]);
      await source.close();
    },
  );

  test(
    'Stream<void> can deliver data and completion through the owned subscription',
    () async {
      final source = StreamController<void>();
      final host = _host(_StreamService(const Stream.empty()));
      var count = 0;
      final sub = host.runtime
          .invokeServiceStream<_StreamService, void>(
            methodId: 'watch',
            call: (_, _) => source.stream,
          )
          .listen((_) {
            count++;
          });
      final done = sub.asFuture<void>();
      await _turn();
      source.add(null);
      await source.close();
      await done;
      expect(count, 1);
    },
  );

  for (final proxy in [false, true]) {
    test(
      '${proxy ? 'proxy' : 'native'} resumed source must not retain cancelled payload',
      () async {
        final source = _ResumeSource();
        final host = _host(
          _StreamService(const Stream.empty()),
          scope: CCServiceScope.session,
        );
        host.runtime.openSession(accountId: 'resumed');
        final output = proxy
            ? host.runtime.invokeServiceStream<_StreamService, Object>(
                methodId: 'watch',
                call: (_, _) => source,
              )
            : source;
        final done = Completer<void>();
        var count = 0;
        final sub = output.listen(
          (_) {
            count++;
          },
          onError: (Object _) {},
          onDone: done.complete,
        );
        await _turn();
        sub.pause();
        sub.resume();
        sub.pause();
        if (proxy) {
          await host.runtime.closeSession();
        } else {
          await sub.cancel();
        }
        await forceGC(fullGcCycles: 3, timeout: const Duration(seconds: 20));
        final retained = _payloadAlive(source.payloadReference);
        if (proxy) {
          sub.resume();
          await done.future;
        }
        await forceGC(fullGcCycles: 3, timeout: const Duration(seconds: 20));
        expect(count, 1);
        expect(retained, isFalse);
      },
    );
  }

  for (final proxy in [false, true]) {
    test(
      '${proxy ? 'proxy' : 'native'} cleanup Future owned by Host error Zone',
      () async {
        final ownerEscaped = <Object>[];
        final producerEscaped = <Object>[];
        final owner = runZonedGuarded(() => Zone.current, (
          Object e,
          StackTrace s,
        ) {
          ownerEscaped.add(e);
        })!;
        final producer = owner.run(
          () => runZonedGuarded(() => Zone.current, (Object e, StackTrace s) {
            producerEscaped.add(e);
          })!,
        );
        final cleanup = owner.run(Completer<void>.new);
        final source = owner.run(
          () => StreamController<int>(onCancel: () => cleanup.future),
        );
        final host = owner.run(() => _host(_StreamService(source.stream)));
        final stream = proxy ? producer.run(() => _watch(host)) : source.stream;
        final sub = owner.run(
          () => stream.listen((_) {}, onError: (Object _) {}),
        );
        await _turn();
        var completed = false;
        Object? received;
        owner.run(() {
          unawaited(
            sub.cancel().then<void>(
              (_) {
                completed = true;
              },
              onError: (Object e, StackTrace s) {
                received = e;
                completed = true;
              },
            ),
          );
        });
        await _turn();
        final error = StateError('Host-owned cleanup');
        owner.run(
          () => cleanup.completeError(
            error,
            StackTrace.fromString('Host cleanup stack'),
          ),
        );
        await _turn();
        await _turn();
        await host.runtime.appScope.close(
          timeout: const Duration(milliseconds: 10),
        );
        unawaited(source.close());
        expect(completed, isTrue);
        expect(received, same(error));
        expect(ownerEscaped, isEmpty);
        expect(producerEscaped, isEmpty);
      },
    );
  }
  test('token cancellation must not hide upstream cleanup failure', () async {
    final sink = _ReviewSink();
    final cleanupError = StateError('actual source cleanup failed');
    final source = StreamController<int>(
      onCancel: () => Future<void>.error(cleanupError),
    );
    final runtime = CCRouterRuntime.forTesting(
      diagnostics: CCDiagnosticsConfig(
        sink: sink,
        defaultMinimumLevel: CCDiagnosticLevel.debug,
      ),
      components: [
        CCComponentManifest(
          id: 'owner',
          version: '1.0.0',
          registrar: _Registrar(
            _StreamService(source.stream),
            CCServiceScope.app,
            null,
          ),
        ),
      ],
    )..initialize();
    addTearDown(runtime.dispose);
    final token = CCCancellationToken();
    final observed = <Object>[];
    final done = Completer<void>();
    final sub = runtime
        .invokeServiceStream<_StreamService, int>(
          methodId: 'watch',
          cancellation: token,
          call: (service, context) => service.watch(context),
        )
        .listen((_) {}, onError: observed.add, onDone: done.complete);
    await _turn();
    token.cancel();
    await done.future;
    await sub.cancel();
    await _turn();
    await runtime.appScope.close();
    await _turn();
    final cleanupReported = sink.events.any((e) => e.errorType == 'StateError');
    await source.close();
    expect(
      cleanupReported ||
          observed.contains(cleanupError) ||
          runtime.appScope.disposalErrors.contains(cleanupError),
      isTrue,
    );
  });

  test(
    'synchronous consumer can close its Scope without reentrant delivery',
    () async {
      var cancels = 0;
      final source = StreamController<int>(
        sync: true,
        onCancel: () {
          cancels++;
        },
      );
      final service = _StreamService(source.stream);
      final host = _host(service, scope: CCServiceScope.session);
      host.runtime.openSession(accountId: 'reentry');
      final values = <int>[];
      final errors = <Object>[];
      final done = Completer<void>();
      Future<void>? closing;
      _watch(host).listen(
        (value) {
          values.add(value);
          closing = host.runtime.closeSession();
        },
        onError: errors.add,
        onDone: done.complete,
      );
      await _turn();
      source.add(1);
      source.add(2);
      await closing;
      await done.future;
      expect(values, [1]);
      expect(errors, [isA<CCInvocationCancelledError>()]);
      expect(cancels, 1);
      expect(service.disposals, 1);
      await source.close();
    },
  );

  test('live Scope does not retain abandoned unlistened streams', () async {
    final host = _host(_StreamService(const Stream.empty()));
    final abandoned = _abandonUnlistened(host);
    await forceGC(fullGcCycles: 3, timeout: const Duration(seconds: 20));
    expect(abandoned.target, isNull);
    expect(host.runtime.recentTraces, isEmpty);
  });

  test(
    'consumer close releases unlistened App call Zone without a stream Trace',
    () async {
      final service = _StreamService(const Stream.empty());
      final host = _host(service);
      host.runtime.openSession(accountId: 'consumer');
      final pending = await _unlistenedConsumerStream(host);
      await forceGC(fullGcCycles: 3, timeout: const Duration(seconds: 20));
      expect(pending.$2.target, isNull);
      expect(service.calls, 0);
      await expectLater(
        pending.$1.toList(),
        throwsA(isA<CCInvocationCancelledError>()),
      );
      expect(host.runtime.recentTraces.map((trace) => trace.target), [
        'owner.parent.create',
      ]);
    },
  );

  for (final broadcast in [false, true]) {
    test(
      'Scope close releases paused ${broadcast ? 'broadcast' : 'single'} upstream payloads',
      () async {
        final source = broadcast
            ? StreamController<Object>.broadcast(sync: true)
            : StreamController<Object>(sync: true);
        final host = _host(
          _StreamService(const Stream.empty()),
          scope: CCServiceScope.session,
        );
        host.runtime.openSession(accountId: 'paused');
        final done = Completer<void>();
        final errors = <Object>[];
        final sub = host.runtime
            .invokeServiceStream<_StreamService, Object>(
              methodId: 'watch',
              call: (_, _) => source.stream,
            )
            .listen(
              (_) => fail('paused data escaped'),
              onError: errors.add,
              onDone: done.complete,
            );
        await _turn();
        sub.pause();
        final payload = _queuePayload(source);
        await host.runtime.closeSession();
        await forceGC(fullGcCycles: 3, timeout: const Duration(seconds: 20));
        expect(payload.target, isNull);
        sub.resume();
        await done.future;
        expect(errors, [isA<CCInvocationCancelledError>()]);
        await source.close();
      },
    );
  }

  test(
    'source error and done cannot deliver after Scope close starts',
    () async {
      final source = StreamController<int>(sync: true);
      final host = _host(
        _StreamService(source.stream),
        scope: CCServiceScope.session,
      );
      host.runtime.openSession(accountId: 'error');
      final scope = host.runtime.sessionScope!;
      final original = StateError('source');
      final stack = StackTrace.fromString('source before done');
      final errors = <Object>[];
      final states = <Object>[];
      final done = Completer<void>();
      _watch(host).listen(
        (_) {},
        onError: (Object error, StackTrace trace) {
          errors.add(error);
          states.add(scope.state);
          expect(trace, same(stack));
        },
        onDone: done.complete,
      );
      await _turn();
      source.addError(original, stack);
      final sourceDone = source.close();
      await host.runtime.closeSession();
      await sourceDone;
      await done.future;
      expect(errors, [same(original)]);
      expect(states.single.toString(), 'CCScopeState.active');
    },
  );

  test(
    'cross-error-Zone Scope cleanup reports failure once and disposes Service',
    () async {
      final escaped = <Object>[];
      final producer = runZonedGuarded(
        () => Zone.current,
        (Object e, StackTrace _) => escaped.add(e),
      )!;
      final cleanup = producer.run(Completer<void>.new);
      final source = StreamController<int>(onCancel: () => cleanup.future);
      final service = _StreamService(source.stream);
      final host = _host(service, scope: CCServiceScope.session);
      host.runtime.openSession(accountId: 'producer');
      final scope = host.runtime.sessionScope!;
      final received = Completer<Object>();
      producer.run(
        () => _watch(
          host,
        ).listen((_) {}, onError: received.complete, cancelOnError: true),
      );
      await _turn();
      final closing = host.runtime.closeSession();
      final original = StateError('producer cancel');
      producer.run(
        () => cleanup.completeError(
          original,
          StackTrace.fromString('producer cancel stack'),
        ),
      );
      await closing;
      expect(await received.future, isA<CCInvocationCancelledError>());
      await _turn();
      expect(escaped, isEmpty);
      expect(scope.disposalErrors, [same(original)]);
      expect(service.disposals, 1);
      expect(host.runtime.recentTraces.single.status, 'cancelled');
      await source.close();
    },
  );

  test('native cancel observes the same producer Zone error', () async {
    final uncaught = <Object>[];
    final producer = runZonedGuarded(() => Zone.current, (
      Object e,
      StackTrace s,
    ) {
      uncaught.add(e);
    })!;
    final cleanup = producer.run(Completer<void>.new);
    final source = StreamController<int>(onCancel: () => cleanup.future);
    final sub = producer.run(() => source.stream.listen((_) {}));
    var completed = false;
    Object? received;
    producer.run(() {
      unawaited(
        sub.cancel().then<void>(
          (_) {
            completed = true;
          },
          onError: (Object e, StackTrace s) {
            received = e;
            completed = true;
          },
        ),
      );
    });
    final error = StateError('producer cleanup');
    producer.run(() => cleanup.completeError(error));
    await _turn();
    expect(completed, isTrue);
    expect(received, same(error));
    expect(uncaught, isEmpty);
    await source.close();
  });
  test('unlistened stream must release ended Runtime', () async {
    final retained = await _unusedAfterShutdown();
    await forceGC(fullGcCycles: 3, timeout: const Duration(seconds: 20));
    final wasRetained = retained.$2.target != null;
    await expectLater(
      retained.$1.toList(),
      throwsA(isA<CCInvocationCancelledError>()),
    );
    await forceGC(fullGcCycles: 3, timeout: const Duration(seconds: 20));
    expect(wasRetained, isFalse);
  });
  test('source done must not allow data after Scope close starts', () async {
    final source = StreamController<int>(sync: true);
    final host = _host(
      _StreamService(source.stream),
      scope: CCServiceScope.session,
    );
    host.runtime.openSession(accountId: 'first');
    final scope = host.runtime.sessionScope!;
    final events = <Object>[];
    final done = Completer<void>();
    _watch(host).listen(
      (v) {
        events.add('$v:${scope.state}');
      },
      onError: events.add,
      onDone: done.complete,
    );
    await _turn();
    source.add(41);
    final sourceDone = source.close();
    final closing = host.runtime.closeSession();
    await closing;
    await sourceDone;
    await done.future;
    expect(events, ['41:CCScopeState.active']);
  });
  test('cancellation must release paused queued payload', () async {
    final source = StreamController<Object>(sync: true);
    final host = _host(
      _StreamService(const Stream.empty()),
      scope: CCServiceScope.session,
    );
    host.runtime.openSession(accountId: 'first');
    final done = Completer<void>();
    final sub = host.runtime
        .invokeServiceStream<_StreamService, Object>(
          methodId: 'watch',
          call: (_, _) => source.stream,
        )
        .listen((_) {}, onError: (Object _) {}, onDone: done.complete);
    await _turn();
    final payload = _queuePayload(source);
    sub.pause();
    await host.runtime.closeSession();
    await forceGC(fullGcCycles: 3, timeout: const Duration(seconds: 20));
    final wasRetained = payload.target != null;
    sub.resume();
    await done.future;
    await source.close();
    await forceGC(fullGcCycles: 3, timeout: const Duration(seconds: 20));
    expect(wasRetained, isFalse);
  });
  test('cancellation preserves producer error Zone failure', () async {
    final uncaught = <Object>[];
    final producer = runZonedGuarded(() => Zone.current, (
      Object e,
      StackTrace s,
    ) {
      uncaught.add(e);
    })!;
    final cleanup = producer.run(Completer<void>.new);
    final source = StreamController<int>(onCancel: () => cleanup.future);
    final host = _host(_StreamService(source.stream));
    final sub = producer.run(
      () => _watch(host).listen((_) {}, onError: (Object _) {}),
    );
    await _turn();
    var completed = false;
    Object? received;
    StackTrace? receivedStack;
    producer.run(() {
      unawaited(
        sub.cancel().then<void>(
          (_) {
            completed = true;
          },
          onError: (Object e, StackTrace s) {
            received = e;
            receivedStack = s;
            completed = true;
          },
        ),
      );
    });
    await _turn();
    final error = StateError('producer cleanup');
    final stack = StackTrace.fromString('producer stack');
    producer.run(() => cleanup.completeError(error, stack));
    await _turn();
    await _turn();
    await host.runtime.appScope.close(
      timeout: const Duration(milliseconds: 10),
    );
    unawaited(source.close());
    expect(completed, isTrue);
    expect(received, same(error));
    expect(receivedStack, same(stack));
    expect(uncaught, isEmpty);
  });

  test(
    'uncooperative cancel does not retain Runtime after bounded Scope cleanup',
    () async {
      final release = Completer<void>();
      final source = StreamController<int>(onCancel: () => release.future);
      final retained = await _retirePendingStream(source.stream);
      try {
        await forceGC(fullGcCycles: 3, timeout: const Duration(seconds: 20));
        expect(retained.$1.target, isNull);
      } finally {
        release.complete();
        await retained.$2;
        await source.close();
      }
    },
  );

  test(
    'reentrant source listen cancellation attaches and cancels only once',
    () async {
      final token = CCCancellationToken();
      var cancels = 0;
      final source = StreamController<int>(
        onListen: token.cancel,
        onCancel: () {
          cancels++;
        },
      );
      final host = _host(_StreamService(source.stream));
      await expectLater(
        _watch(host, cancellation: token).toList(),
        throwsA(isA<CCInvocationCancelledError>()),
      );
      expect(cancels, 1);
      expect(host.runtime.recentTraces, hasLength(1));
      await source.close();
    },
  );

  test('startup failure preserves original error and stack', () async {
    final host = _host(_StreamService(const Stream.empty()));
    final error = StateError('startup');
    final stack = StackTrace.fromString('startup stack');
    final stream = host.runtime.invokeServiceStream<_StreamService, int>(
      methodId: 'watch',
      call: (_, _) => Error.throwWithStackTrace(error, stack),
    );
    try {
      await stream.toList();
      fail('startup error was swallowed');
    } catch (e, s) {
      expect(e, same(error));
      expect(s, same(stack));
    }
    expect(host.runtime.recentTraces.single.status, 'failed');
  });

  test(
    'inherited deadline and context survive the parent method returning',
    () async {
      final source = StreamController<int>();
      final service = _StreamService(source.stream);
      final host = _host(service);
      host.runtime.openSession(accountId: 'parent');
      late CCInvocationContext parent;
      final stream = await host.runtime.invokeService<_Parent, Stream<int>>(
        methodId: 'create',
        timeout: const Duration(milliseconds: 100),
        call: (_, context) {
          parent = context;
          return _watch(host);
        },
      );
      await expectLater(
        stream.toList(),
        throwsA(isA<CCInvocationTimeoutError>()),
      );
      expect(service.context!.deadline, parent.deadline);
      expect(service.context!.parentSpanId, parent.spanId);
      expect(service.context!.traceId, parent.traceId);
      await source.close();
    },
  );

  test('Scope records cleanup failure and still disposes Service', () async {
    final error = StateError('cleanup');
    final source = StreamController<int>(
      onCancel: () => Future<void>.error(error),
    );
    final service = _StreamService(source.stream);
    final host = _host(service, scope: CCServiceScope.session);
    host.runtime.openSession(accountId: 'cleanup');
    final scope = host.runtime.sessionScope!;
    final done = Completer<void>();
    final events = <Object>[];
    _watch(host).listen(events.add, onError: events.add, onDone: done.complete);
    await _turn();
    await host.runtime.closeSession();
    await done.future;
    expect(scope.disposalErrors, [same(error)]);
    expect(events, [isA<CCInvocationCancelledError>()]);
    expect(service.disposals, 1);
    await source.close();
  });

  test(
    'Runtime shutdown waits for source cleanup before disposing Service',
    () async {
      final release = Completer<void>();
      final source = StreamController<int>(onCancel: () => release.future);
      final service = _StreamService(source.stream);
      final host = _host(service);
      final done = Completer<void>();
      final errors = <Object>[];
      _watch(host).listen((_) {}, onError: errors.add, onDone: done.complete);
      await _turn();
      var disposed = false;
      final disposing = host.dispose().then((_) {
        disposed = true;
      });
      await _turn();
      expect(disposed, isFalse);
      expect(service.disposals, 0);
      release.complete();
      await disposing;
      await done.future;
      expect(service.disposals, 1);
      expect(errors, [isA<CCInvocationCancelledError>()]);
      await source.close();
    },
  );

  test(
    'retained completed stream releases its call-time Zone payload',
    () async {
      final host = _host(_StreamService(Stream.value(1)));
      final retained = await _completedStreamWithPayload(host);
      await forceGC(fullGcCycles: 3, timeout: const Duration(seconds: 20));
      expect(retained.$2.target, isNull);
      expect(() => retained.$1.listen((_) {}), throwsStateError);
    },
  );

  test(
    'binding is lazy, delivers early ordered data, original errors and done once',
    () async {
      var cancels = 0;
      final source = StreamController<int>(
        onCancel: () {
          cancels++;
        },
      );
      final service = _StreamService(source.stream);
      final host = _host(service);
      await host.run(() async {
        final stream =
            CCRouterGeneratedServiceBinding.invokeStream<_StreamService, int>(
              methodId: 'watch',
              call: (service, context) => service.watch(context),
            );
        expect(service.calls, 0);
        final events = <Object>[];
        final stacks = <StackTrace>[];
        final done = Completer<void>();
        stream.listen(
          events.add,
          onError: (Object e, StackTrace s) {
            events.add(e);
            stacks.add(s);
          },
          onDone: done.complete,
        );
        expect(() => stream.listen((_) {}), throwsStateError);
        await _turn();
        source.add(1);
        await _turn();
        expect(events, [1]);
        expect(CCRouter.recentTraces, isEmpty);
        final error = StateError('original');
        final stack = StackTrace.fromString('original stream stack');
        source.addError(error, stack);
        source.add(2);
        await source.close();
        await done.future;
        expect(events, [1, same(error), 2]);
        expect(stacks.single, same(stack));
        expect(service.calls, 1);
        expect(cancels, 1);
        expect(CCRouter.recentTraces.single.status, 'failed');
      });
    },
  );

  test(
    'explicit cancel joins asynchronous cleanup and cancels context once',
    () async {
      final release = Completer<void>();
      var cancels = 0;
      final source = StreamController<int>(
        onCancel: () {
          cancels++;
          return release.future;
        },
      );
      final service = _StreamService(source.stream);
      final host = _host(service);
      final events = <Object>[];
      final subscription = _watch(host).listen(events.add, onError: events.add);
      await _turn();
      var completed = false;
      final cancelling = subscription.cancel().then((_) {
        completed = true;
      });
      expect(service.context!.cancellation.isCancelled, isTrue);
      source.add(99);
      await _turn();
      expect(completed, isFalse);
      expect(events, isEmpty);
      release.complete();
      await cancelling;
      await subscription.cancel();
      expect(cancels, 1);
      expect(host.runtime.recentTraces.single.status, 'cancelled');
      await source.close();
    },
  );

  test(
    'token cancellation fences paused data/errors and waits for cancel before error/done',
    () async {
      final release = Completer<void>();
      final source = StreamController<int>(onCancel: () => release.future);
      final service = _StreamService(source.stream);
      final host = _host(service);
      final token = CCCancellationToken();
      final events = <Object>[];
      final done = Completer<void>();
      final subscription = _watch(
        host,
        cancellation: token,
      ).listen(events.add, onError: events.add, onDone: done.complete);
      await _turn();
      subscription.pause();
      source.add(1);
      source.addError(StateError('late'));
      token.cancel();
      expect(service.context!.cancellation.isCancelled, isTrue);
      subscription.resume();
      await _turn();
      expect(events, isEmpty);
      release.complete();
      await done.future;
      expect(events, [isA<CCInvocationCancelledError>()]);
      await source.close();
    },
  );

  test(
    'Scope close joins cancellation before Service disposal and fences old generation',
    () async {
      final release = Completer<void>();
      var cancels = 0;
      final source = StreamController<int>(
        onCancel: () {
          cancels++;
          return release.future;
        },
      );
      final service = _StreamService(source.stream);
      final host = _host(service, scope: CCServiceScope.session);
      host.runtime.openSession(accountId: 'first');
      final stream = _watch(host);
      final oldUnlistened = _watch(host);
      final events = <Object>[];
      final done = Completer<void>();
      stream.listen(events.add, onError: events.add, onDone: done.complete);
      await _turn();
      var closed = false;
      final closing = host.runtime.closeSession().then((_) {
        closed = true;
      });
      source.add(99);
      await _turn();
      expect(closed, isFalse);
      expect(service.disposals, 0);
      release.complete();
      await closing;
      await done.future;
      expect(events, [isA<CCInvocationCancelledError>()]);
      expect(service.disposals, 1);
      expect(cancels, 1);
      host.runtime.openSession(accountId: 'second');
      await expectLater(
        oldUnlistened.toList(),
        throwsA(isA<CCInvocationCancelledError>()),
      );
      expect(service.calls, 1);
      await source.close();
    },
  );

  test(
    'consumer Session closure cancels an App stream returned by completed parent',
    () async {
      final release = Completer<void>();
      final source = StreamController<int>(onCancel: () => release.future);
      final host = _host(_StreamService(source.stream));
      host.runtime.openSession(accountId: 'consumer');
      final stream = host.runtime.invokeServiceSync<_Parent, Stream<int>>(
        methodId: 'create',
        call: (_, _) => _watch(host),
      );
      final done = Completer<void>();
      final events = <Object>[];
      stream.listen(events.add, onError: events.add, onDone: done.complete);
      await _turn();
      var closed = false;
      final closing = host.runtime.closeSession().then((_) {
        closed = true;
      });
      await _turn();
      expect(closed, isFalse);
      release.complete();
      await closing;
      await done.future;
      expect(events, [isA<CCInvocationCancelledError>()]);
      await source.close();
    },
  );

  test(
    'pre-cancel and cancellation during readiness do not enter the method',
    () async {
      final initialized = Completer<void>();
      final source = StreamController<int>();
      final service = _StreamService(source.stream);
      final host = _host(service, initialize: () => initialized.future);
      final cancelled = CCCancellationToken()..cancel();
      await expectLater(
        _watch(host, cancellation: cancelled).toList(),
        throwsA(isA<CCInvocationCancelledError>()),
      );
      final token = CCCancellationToken();
      final pending = expectLater(
        _watch(host, cancellation: token).toList(),
        throwsA(isA<CCInvocationCancelledError>()),
      );
      await _turn();
      token.cancel();
      await pending;
      initialized.complete();
      await _turn();
      expect(service.calls, 0);
      unawaited(source.close());
    },
  );

  test(
    'broadcast source stays single-subscription and forwards pause/resume',
    () async {
      final source = StreamController<int>.broadcast();
      final host = _host(_StreamService(source.stream));
      final events = <int>[];
      final stream = _watch(host);
      final subscription = stream.listen(events.add);
      await _turn();
      expect(stream.isBroadcast, isFalse);
      expect(() => stream.listen((_) {}), throwsStateError);
      final resume = Completer<void>();
      subscription.pause(resume.future);
      source.add(1);
      await _turn();
      expect(events, isEmpty);
      resume.complete();
      await _turn();
      expect(events, [1]);
      await subscription.cancel();
      expect(source.hasListener, isFalse);
      await source.close();
    },
  );

  test(
    'deadline covers the entire Stream lifetime and cancels upstream',
    () async {
      var cancels = 0;
      final source = StreamController<int>(
        onCancel: () {
          cancels++;
        },
      );
      final service = _StreamService(source.stream);
      final host = _host(service);
      await expectLater(
        _watch(host, timeout: const Duration(milliseconds: 30)).toList(),
        throwsA(isA<CCInvocationTimeoutError>()),
      );
      expect(cancels, 1);
      expect(service.context!.cancellation.isCancelled, isTrue);
      expect(host.runtime.recentTraces.single.status, 'timedOut');
      await source.close();
    },
  );

  test(
    'cancelOnError preserves source error and cancels exactly once',
    () async {
      var cancels = 0;
      final source = StreamController<int>(
        onCancel: () {
          cancels++;
        },
      );
      final host = _host(_StreamService(source.stream));
      final original = StateError('source');
      final received = Completer<Object>();
      _watch(
        host,
      ).listen((_) {}, onError: received.complete, cancelOnError: true);
      await _turn();
      source.addError(original);
      expect(await received.future, same(original));
      await _turn();
      expect(cancels, 1);
      expect(host.runtime.recentTraces, hasLength(1));
      await source.close();
    },
  );

  test(
    'subscription cancel preserves original asynchronous cleanup failure',
    () async {
      final error = StateError('cleanup');
      final stack = StackTrace.fromString('cancel stack');
      final source = StreamController<int>(
        onCancel: () => Future<void>.error(error, stack),
      );
      final host = _host(_StreamService(source.stream));
      final subscription = _watch(host).listen((_) {});
      await _turn();
      try {
        await subscription.cancel();
        fail('cleanup failure was swallowed');
      } catch (e, s) {
        expect(e, same(error));
        expect(s, same(stack));
      }
      await source.close();
    },
  );
}
