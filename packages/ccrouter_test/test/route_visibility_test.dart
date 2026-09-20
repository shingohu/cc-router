import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:ccrouter_test/ccrouter_test.dart';
import 'package:test/test.dart';

final class _VisibilityArguments {
  const _VisibilityArguments(this.value);

  final String value;
}

final class _VisibilityCodec implements CCRouteCodec<_VisibilityArguments> {
  const _VisibilityCodec();

  @override
  _VisibilityArguments decode(CCEncodedRouteArguments input) =>
      _VisibilityArguments(input.path['value']!);

  @override
  CCEncodedRouteArguments encode(_VisibilityArguments arguments) =>
      CCEncodedRouteArguments(path: {'value': arguments.value});
}

final class _VisibilityIntent<R> implements CCRouteIntent<R> {
  const _VisibilityIntent(this.value);

  final String value;

  @override
  String get routeId => 'visibility.page';

  @override
  Object get arguments => _VisibilityArguments(value);
}

final class _VisibilityRegistrar implements CCComponentRegistrar {
  const _VisibilityRegistrar();

  @override
  void register(CCRegistry registry) {
    registry.registerRoute<_VisibilityArguments, void>(
      CCRouteDefinition<_VisibilityArguments, void>(
        routeId: 'visibility.page',
        patterns: [CCPathPattern('/visibility/:value', primary: true)],
        codec: const _VisibilityCodec(),
      ),
    );
  }
}

void main() {
  test(
    'visibility events distinguish covering, revealing, and disposal',
    () async {
      final host = CCRouterTestHost(
        navigationAdapter: CCMemoryNavigationAdapter(),
        components: const [
          CCComponentManifest(
            id: 'visibility',
            version: '1.0.0',
            registrar: _VisibilityRegistrar(),
          ),
        ],
      );
      addTearDown(host.dispose);
      host.initialize();

      final events = <CCRouteVisibilityEvent>[];
      final removeListener = host.runtime.addRouteVisibilityListener(
        events.add,
      );
      final first = host.runtime.pushRoute<void>(
        const _VisibilityIntent<void>('first'),
      );
      await Future<void>.delayed(Duration.zero);
      final firstEntryId = host.runtime.activeRouteEntries.single.routeEntryId;
      final second = host.runtime.pushRoute<void>(
        const _VisibilityIntent<void>('second'),
      );
      await Future<void>.delayed(Duration.zero);
      final secondEntryId = host.runtime.activeRouteEntries.last.routeEntryId;

      host.runtime.popRoute();
      await second;
      host.runtime.popRoute();
      await first;
      await Future<void>.delayed(Duration.zero);

      expect(
        events
            .where((event) => event.entry.routeEntryId == firstEntryId)
            .map((event) => event.phase),
        [
          CCRouteVisibilityPhase.willShow,
          CCRouteVisibilityPhase.didShow,
          CCRouteVisibilityPhase.willHide,
          CCRouteVisibilityPhase.didHide,
          CCRouteVisibilityPhase.willShow,
          CCRouteVisibilityPhase.didShow,
          CCRouteVisibilityPhase.willHide,
          CCRouteVisibilityPhase.didHide,
        ],
      );
      expect(
        events
            .where((event) => event.entry.routeEntryId == secondEntryId)
            .map((event) => event.phase),
        [
          CCRouteVisibilityPhase.willShow,
          CCRouteVisibilityPhase.didShow,
          CCRouteVisibilityPhase.willHide,
          CCRouteVisibilityPhase.didHide,
        ],
      );
      expect(
        host.runtime.recentRouteEntryEvents
            .where(
              (event) =>
                  event.entry.lifecycleState ==
                  CCRouteEntryLifecycleState.disposed,
            )
            .map((event) => event.entry.routeEntryId),
        containsAll([firstEntryId, secondEntryId]),
      );

      removeListener();
      expect(host.runtime.recentRouteVisibilityEvents, hasLength(12));
    },
  );
}
