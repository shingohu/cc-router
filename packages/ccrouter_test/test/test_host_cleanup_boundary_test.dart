import 'dart:async';

import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:ccrouter_test/ccrouter_test.dart';
import 'package:flutter_test/flutter_test.dart';

import 'review_repros/init_task_reentrancy/error_zone_repro.dart'
    show guardedZone;
import 'review_repros/runtime_round_trip/test_host_disposal.dart' as fixture;

typedef _Outcome = ({Object? error, StackTrace? stack});

Future<_Outcome> _observe(Zone zone, Future<void> Function() call) {
  final completion = Completer<_Outcome>();
  zone.run(() {
    unawaited(
      Future<void>.sync(call).then<void>(
        (_) => completion.complete((error: null, stack: null)),
        onError: (Object error, StackTrace stack) =>
            completion.complete((error: error, stack: stack)),
      ),
    );
  });
  return completion.future.timeout(const Duration(seconds: 2));
}

void main() {
  for (final sameErrorZone in [true, false]) {
    for (final lateJoin in [true, false]) {
      for (final fails in [true, false]) {
        test('cleanup sameErrorZone=$sameErrorZone late=$lateJoin '
            'fails=$fails', () async {
          final uncaught = <Object>[];
          final firstZone = guardedZone(uncaught);
          final otherZone = sameErrorZone
              ? firstZone.fork()
              : guardedZone(uncaught);
          final failure = StateError('adapter cleanup');
          final adapter = fails ? fixture.ThrowingAdapter(failure) : null;
          final host = CCRouterTestHost(navigationAdapter: adapter);
          final started = Completer<void>();
          final release = Completer<void>();
          final resource = fixture.Resource(started, release);
          host.runtime.registerService(
            CCServiceProvider<fixture.Resource>(factory: (_) => resource),
          );
          host.initialize();
          host.runtime.service<fixture.Resource>();
          final first = _observe(firstZone, host.dispose);
          await started.future;
          expect(host.initialize, throwsStateError);
          expect(() => host.run(() {}), throwsStateError);
          _Outcome? secondResult;
          Future<_Outcome>? second;
          if (!lateJoin) {
            second = _observe(
              otherZone,
              host.dispose,
            ).then((value) => secondResult = value);
            await Future<void>.delayed(Duration.zero);
          }
          final finishedEarly = secondResult != null;
          release.complete();
          final firstResult = await first;
          second ??= _observe(otherZone, host.dispose);
          final joinedResult = await second;
          final later = await _observe(otherZone, host.dispose);
          expect(finishedEarly, isFalse);
          expect(resource.disposals, 1);
          if (fails) {
            expect(adapter!.disposals, 1);
            expect(firstResult.error, same(failure));
            expect(joinedResult.error, same(failure));
            expect(later.error, same(failure));
            expect(joinedResult.stack.toString(), firstResult.stack.toString());
            expect(later.stack.toString(), firstResult.stack.toString());
          } else {
            expect(firstResult.error, isNull);
            expect(joinedResult.error, isNull);
            expect(later.error, isNull);
          }
          expect(uncaught, isEmpty);
        });
      }
    }
  }

  for (final fails in [true, false]) {
    test(
      'synchronous shutdown reentry joins published barrier fails=$fails',
      () async {
        final host = CCRouterTestHost()..initialize();
        final failure = StateError('cancellation callback');
        final uncaught = <Object>[];
        final other = guardedZone(uncaught);
        Future<_Outcome>? reentrant;
        host.runtime.appScope.cancellation.addListener(() {
          reentrant = _observe(other, host.dispose);
          if (fails) throw failure;
        });
        final first = await _observe(Zone.current, host.dispose);
        final joined = await reentrant!;
        expect(first.error, fails ? same(failure) : isNull);
        expect(joined.error, fails ? same(failure) : isNull);
        if (fails) expect(joined.stack.toString(), first.stack.toString());
        expect(uncaught, isEmpty);
      },
    );
  }
}
