import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:ccrouter_test/ccrouter_test.dart';
import 'package:flutter_test/flutter_test.dart';

class _LegacyAdapter
    implements CCNavigationAdapter, CCNavigationPopGuardBinding {
  CCPopGuardEvaluator? evaluator;
  bool disposed = false;

  @override
  void bindPopGuardEvaluator(CCPopGuardEvaluator? evaluator) {
    this.evaluator = evaluator;
  }

  @override
  void initialize(
    List<CCNavigationRoute> routes, {
    List<CCNavigationShell> shells = const [],
  }) {}

  @override
  bool canPop() => false;

  @override
  Future<bool> maybePop({Object? result}) async => false;

  @override
  Future<Object?> navigate(CCNavigationRequest request) async => null;

  @override
  void pop({Object? result}) {}

  @override
  void dispose() => disposed = true;
}

class _ScopedAdapter extends _LegacyAdapter
    implements CCNavigationScopedPopGuardBinding {
  CCScopedPopGuardEvaluator? scoped;
  bool rejectBinding = false;
  int unbindings = 0;

  @override
  void bindScopedPopGuardEvaluator(CCScopedPopGuardEvaluator? evaluator) {
    scoped = evaluator;
    if (evaluator == null) unbindings++;
    if (evaluator != null && rejectBinding) throw StateError('bind failed');
  }
}

final class _ThrowingUnbindAdapter extends _ScopedAdapter
    implements CCNavigationBackendEventSource {
  bool rejectUnbinding = false;
  bool listenerRemoved = false;
  final guardError = StateError('guard unbind failed');

  @override
  void bindScopedPopGuardEvaluator(CCScopedPopGuardEvaluator? evaluator) {
    super.bindScopedPopGuardEvaluator(evaluator);
    if (evaluator == null && rejectUnbinding) throw guardError;
  }

  @override
  void Function() addBackendEventListener(
    CCNavigationBackendEventListener listener,
  ) => () {
    listenerRemoved = true;
    throw StateError('listener removal failed');
  };
}

void main() {
  test('MultiHost cleanup preserves first error and still releases child', () {
    final child = _ThrowingUnbindAdapter();
    final adapter = CCMultiHostNavigationAdapter(
      defaultHostId: 'primary',
      adapters: {'primary': child},
    );
    adapter.initialize(const []);
    child.rejectUnbinding = true;
    expect(adapter.dispose, throwsA(same(child.guardError)));
    expect(child.listenerRemoved, isTrue);
    expect(child.disposed, isTrue);
    expect(child.scoped, isNull);
  });

  test(
    'Runtime prefers scoped binding and clears it before Adapter disposal',
    () async {
      final adapter = _ScopedAdapter();
      final host = CCRouterTestHost(navigationAdapter: adapter);
      addTearDown(host.dispose);
      host.initialize();
      expect(adapter.scoped, isNotNull);
      expect(adapter.evaluator, isNull);
      await host.dispose();
      expect(adapter.scoped, isNull);
      expect(adapter.unbindings, 1);
      expect(adapter.disposed, isTrue);
    },
  );

  test(
    'rejected scoped attachment clears partially installed Runtime callback',
    () {
      final host = CCRouterTestHost();
      addTearDown(host.dispose);
      host.initialize();
      final adapter = _ScopedAdapter()..rejectBinding = true;
      expect(
        () => host.runtime.attachNavigationAdapter(adapter),
        throwsStateError,
      );
      expect(adapter.scoped, isNull);
      expect(adapter.unbindings, 1);
    },
  );

  test(
    'MultiHost forwards scoped targets to dynamic children and unbinds them',
    () {
      final primary = _ScopedAdapter();
      final secondary = _ScopedAdapter();
      final adapter = CCMultiHostNavigationAdapter(
        defaultHostId: 'primary',
        adapters: {'primary': primary},
      );
      addTearDown(adapter.dispose);
      adapter.initialize(const []);
      CCNavigationPopTarget? seen;
      adapter.bindScopedPopGuardEvaluator((trigger, {required target}) {
        seen = target;
        return const CCPopDeny(code: 'scoped');
      });
      adapter.registerHost('secondary', secondary);
      const target = CCNavigationPopTarget(
        hostId: 'secondary',
        navigatorOutlet: 'detail',
        backendEntryId: 'exact',
      );
      expect(
        secondary.scoped!(CCPopTrigger.gesture, target: target),
        isA<CCPopDeny>(),
      );
      expect(seen!.hostId, target.hostId);
      expect(seen!.navigatorOutlet, target.navigatorOutlet);
      expect(seen!.backendEntryId, endsWith('-entry-exact'));
      expect(adapter.activeHostId, 'primary');
      adapter.unregisterHost('secondary');
      expect(secondary.scoped, isNull);
      expect(secondary.disposed, isTrue);
      adapter.bindScopedPopGuardEvaluator(null);
      expect(primary.scoped, isNull);
    },
  );

  test(
    'legacy children without target SPI keep their own single-Navigator Host',
    () {
      final primary = _LegacyAdapter();
      final secondary = _LegacyAdapter();
      final adapter = CCMultiHostNavigationAdapter(
        defaultHostId: 'primary',
        adapters: {'primary': primary, 'secondary': secondary},
      );
      addTearDown(adapter.dispose);
      adapter.initialize(const []);
      CCNavigationPopTarget? seen;
      adapter.bindScopedPopGuardEvaluator((trigger, {required target}) {
        seen = target;
        return const CCPopAllow();
      });
      expect(secondary.evaluator!(CCPopTrigger.system), isA<CCPopAllow>());
      expect(seen!.hostId, 'secondary');
      expect(seen!.navigatorOutlet, 'root');
      expect(adapter.activeHostId, 'primary');
      adapter.bindScopedPopGuardEvaluator(null);
      expect(primary.evaluator, isNull);
      expect(secondary.evaluator, isNull);
    },
  );
}
