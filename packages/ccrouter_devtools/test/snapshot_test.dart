import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter_devtools/ccrouter_devtools.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'snapshot copies collection boundaries and preserves read-only data',
    () {
      final components = <CCComponentManifest>[
        CCComponentManifest(
          id: 'orders',
          version: '1.0.0',
          registrar: _Registrar(),
          dependencies: ['account'],
        ),
      ];
      final snapshot = CCDevToolsSnapshot(
        capturedAt: DateTime.utc(2026, 1, 1),
        runtimeState: CCDevToolsRuntimeState.initialized,
        components: components,
      );

      components.clear();

      expect(snapshot.components, hasLength(1));
      expect(snapshot.components.single.id, 'orders');
      expect(
        () => snapshot.components.add(snapshot.components.single),
        throwsUnsupportedError,
      );
    },
  );

  test('static provider is deterministic and has no mutation surface', () {
    final snapshot = CCDevToolsSnapshot.empty(
      runtimeState: CCDevToolsRuntimeState.initialized,
    );
    final provider = CCStaticDevToolsSnapshotProvider(snapshot);
    var called = false;
    final remove = provider.addListener(() => called = true);

    expect(provider.snapshot(), same(snapshot));
    remove();
    expect(called, isFalse);
  });
}

final class _Registrar implements CCComponentRegistrar {
  @override
  void register(CCRegistry registry) {}
}
