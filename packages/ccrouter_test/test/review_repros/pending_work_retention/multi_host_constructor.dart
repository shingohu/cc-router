import 'package:ccrouter/ccrouter_host.dart';
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

class CountingAdapter implements CCNavigationAdapter {
  int initializations = 0;
  int disposals = 0;

  @override
  void initialize(
    List<CCNavigationRoute> routes, {
    List<CCNavigationShell> shells = const [],
  }) {
    initializations++;
  }

  @override
  Future<Object?> navigate(CCNavigationRequest request) async => null;
  @override
  Future<bool> maybePop({Object? result}) async => false;
  @override
  void pop({Object? result}) {}
  @override
  bool canPop() => false;
  @override
  void dispose() => disposals++;
}

void main() {
  test('constructor rejects shared Adapter before claiming Host ownership', () {
    final child = CountingAdapter();
    CCMultiHostNavigationAdapter? accepted;
    Object? error;
    try {
      accepted = CCMultiHostNavigationAdapter(
        defaultHostId: 'left',
        adapters: {'left': child, 'right': child},
      );
    } catch (caught) {
      error = caught;
    }
    // Do not leave unexpectedly accepted production resources alive.
    accepted?.dispose();
    expect(
      (rejected: error != null, disposals: child.disposals),
      (rejected: true, disposals: 0),
      reason: 'dynamic registration already rejects the same Adapter',
    );
    expect(child.initializations, 0);
    expect(child.disposals, 0);
  });

  test('independent constructor children each clean up once', () {
    final left = CountingAdapter();
    final right = CountingAdapter();
    final aggregate = CCMultiHostNavigationAdapter(
      defaultHostId: 'left',
      adapters: {'left': left, 'right': right},
    );
    aggregate.initialize(const []);
    aggregate.unregisterHost('right');
    expect(left.disposals, 0);
    expect(right.disposals, 1);
    aggregate.dispose();
    expect(left.disposals, 1);
    expect(right.disposals, 1);
  });

  test(
    'dynamic registration rejects already-owned Adapter without disposing it',
    () {
      final child = CountingAdapter();
      final aggregate = CCMultiHostNavigationAdapter(
        defaultHostId: 'left',
        adapters: {'left': child},
      );
      aggregate.initialize(const []);
      expect(
        () => aggregate.registerHost('right', child),
        throwsA(isA<CCNavigationAdapterError>()),
      );
      expect(child.disposals, 0);
      aggregate.dispose();
      expect(child.disposals, 1);
    },
  );
}
