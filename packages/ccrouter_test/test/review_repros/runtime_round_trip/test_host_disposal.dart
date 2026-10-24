import 'dart:async';

import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:ccrouter_test/ccrouter_test.dart';
import 'package:flutter_test/flutter_test.dart';

import '../completed_invocation/repro.dart' show observe;

class Resource implements CCDisposable {
  Resource(this.started, this.release);
  final Completer<void> started;
  final Completer<void> release;
  int disposals = 0;
  @override
  Future<void> dispose() {
    disposals++;
    started.complete();
    return release.future;
  }
}

class ThrowingAdapter implements CCNavigationAdapter {
  ThrowingAdapter(this.failure);
  final Object failure;
  final delegate = CCMemoryNavigationAdapter();
  int disposals = 0;
  @override
  void initialize(
    List<CCNavigationRoute> routes, {
    List<CCNavigationShell> shells = const [],
  }) => delegate.initialize(routes, shells: shells);
  @override
  Future<Object?> navigate(CCNavigationRequest request) =>
      delegate.navigate(request);
  @override
  Future<bool> maybePop({Object? result}) => delegate.maybePop(result: result);
  @override
  void pop({Object? result}) => delegate.pop(result: result);
  @override
  bool canPop() => delegate.canPop();
  @override
  void dispose() {
    disposals++;
    delegate.dispose();
    throw failure;
  }
}

void main() {
  test(
    'every concurrent TestHost dispose joins actual resource cleanup',
    () async {
      final host = CCRouterTestHost();
      final started = Completer<void>();
      final release = Completer<void>();
      final resource = Resource(started, release);
      host.runtime.registerService(
        CCServiceProvider<Resource>(factory: (_) => resource),
      );
      host.initialize();
      host.runtime.service<Resource>();
      final first = host.dispose();
      await started.future;
      var joined = false;
      final second = host.dispose().then((_) => joined = true);
      await Future<void>.delayed(Duration.zero);
      final finishedBeforeRelease = joined;
      release.complete();
      await Future.wait([first, second]);
      expect(resource.disposals, 1);
      expect(
        finishedBeforeRelease,
        isFalse,
        reason: 'Awaited teardown must not finish before owned resources',
      );
    },
  );

  test(
    'repeated TestHost dispose preserves the original cleanup failure',
    () async {
      final failure = StateError('adapter cleanup');
      final adapter = ThrowingAdapter(failure);
      final host = CCRouterTestHost(navigationAdapter: adapter)..initialize();
      final first = observe(host.dispose);
      final second = observe(host.dispose);
      expect(await first, same(failure));
      expect(adapter.disposals, 1);
      expect(
        await second,
        same(failure),
        reason: 'Joining cleanup must not turn structural failure into success',
      );
    },
  );
}
