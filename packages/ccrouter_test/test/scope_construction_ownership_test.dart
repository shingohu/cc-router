import 'dart:async';

import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:test/test.dart';

final class Resource implements CCDisposable {
  Resource(this.onDispose);
  final FutureOr<void> Function() onDispose;
  int disposals = 0;
  @override
  Future<void> dispose() async {
    disposals++;
    await onDispose();
  }
}

void main() {
  for (final cached in [false, true]) {
    test(
      'closing factory joins async cleanup in reverse order (cached=$cached)',
      () async {
        final scope = CCScope('construction');
        final started = Completer<void>();
        final gate = Completer<void>();
        final order = <String>[];
        final dependency = scope.resolve(
          'dependency',
          () => Resource(() => order.add('dependency')),
        );
        final late = Resource(() {
          order.add('late');
          started.complete();
          return gate.future;
        });
        Future<void>? closing;
        var finished = false;
        expect(
          () => scope.resolve('late', () {
            closing = scope.close().then((_) => finished = true);
            return late;
          }, cache: cached),
          throwsA(isA<CCScopeClosedError>()),
        );
        await started.future;
        expect(finished, isFalse);
        expect(dependency.disposals, 0);
        expect(
          () => scope.resolve('rejected', () => Object()),
          throwsA(isA<CCScopeClosedError>()),
        );
        gate.complete();
        await closing;
        await scope.close();
        expect(order, ['late', 'dependency']);
        expect(late.disposals, 1);
        expect(dependency.disposals, 1);
        expect(scope.state, CCScopeState.closed);
      },
    );
  }

  test('late throwing disposer cannot skip existing dependencies', () async {
    final scope = CCScope('throwing');
    final dependency = scope.resolve('dependency', () => Resource(() {}));
    final late = Resource(() => throw StateError('dispose'));
    Future<void>? closing;
    expect(
      () => scope.resolve('late', () {
        closing = scope.close();
        return late;
      }),
      throwsA(isA<CCScopeClosedError>()),
    );
    await closing;
    expect(late.disposals, 1);
    expect(dependency.disposals, 1);
    expect(scope.disposalErrors.single, isA<StateError>());
  });

  test('factory alias of an existing disposable is cleaned once', () async {
    final scope = CCScope('alias');
    final resource = scope.resolve('original', () => Resource(() {}));
    Future<void>? closing;
    expect(
      () => scope.resolve('alias', () {
        closing = scope.close();
        return resource;
      }),
      throwsA(isA<CCScopeClosedError>()),
    );
    await closing;
    expect(resource.disposals, 1);
  });

  test(
    'throwing construction releases close and preserves original failure',
    () async {
      final scope = CCScope('failed-construction');
      final dependency = scope.resolve('dependency', () => Resource(() {}));
      final failure = StateError('factory');
      Future<void>? closing;
      expect(
        () => scope.resolve<Object>('failed', () {
          closing = scope.close();
          throw failure;
        }),
        throwsA(same(failure)),
      );
      await closing;
      expect(dependency.disposals, 1);
      expect(scope.state, CCScopeState.closed);
    },
  );
}
