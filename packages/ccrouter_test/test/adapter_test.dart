import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

CCNavigationRoute route(
  String id, {
  String path = '/detail/:value',
  CCRoutePlacement placement = const CCRoutePlacement.root(),
  bool hasPopGuard = false,
}) => CCNavigationRoute(
  routeId: id,
  patterns: [CCPathPattern(path, primary: true)],
  presentation: const CCPagePresentation(),
  deepLink: CCDeepLinkPolicy.disabled,
  hasPopGuard: hasPopGuard,
  placement: placement,
);

CCNavigationRequest request({
  required String id,
  required CCNavigationOperation operation,
  required Uri uri,
  CCRoutePlacement placement = const CCRoutePlacement.root(),
  CCNavigationOrigin origin = CCNavigationOrigin.internal,
  CCDeepLinkOpenMode openMode = CCDeepLinkOpenMode.push,
}) => CCNavigationRequest(
  navigationId: 'test-$id-${operation.name}',
  operation: operation,
  routeId: id,
  uri: uri,
  arguments: const Object(),
  presentation: const CCPagePresentation(),
  placement: placement,
  origin: origin,
  openMode: operation == CCNavigationOperation.open ? openMode : null,
);

final class _Codec implements CCRouteCodec<Object> {
  const _Codec();
  @override
  Object decode(CCRouteCodecValues values) => Object();
  @override
  CCRouteCodecValues encode(Object value) => CCRouteCodecValues();
}

CCManagedNavigationAdapter _adapter({
  bool enablePredictiveBack = false,
  CCNavigationHost? host,
}) => CCManagedNavigationAdapter(
  host: host ?? CCNavigationHost(),
  catalog: CCFlutterRouteCatalog([
    CCFlutterRouteDestination.fromDefinition(
      definition: CCRouteDefinition<Object, Object?>(
        routeId: 'detail',
        patterns: [const CCPathPattern('/detail/:value', primary: true)],
        codec: const _Codec(),
      ),
      builder: (_) => const Text('detail'),
    ),
  ]),
  enablePredictiveBack: enablePredictiveBack,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Managed Adapter exposes concrete Host and native capabilities', () {
    final adapter = _adapter(host: CCNavigationHost(id: 'window.main'));
    addTearDown(adapter.dispose);
    adapter.initialize([route('detail')]);
    expect(adapter.hostId, 'window.main');
    expect(adapter.readInitialBackendEntries(), isEmpty);
    expect(adapter.capabilities.supportsNestedNavigators, isTrue);
    expect(adapter.capabilities.supportsModalRoutes, isTrue);
    expect(adapter.capabilities.supportsManagedPopObservation, isTrue);
    expect(adapter.capabilities.supportsPredictiveBack, isFalse);
  });

  test('rejects foreign Host placement before accepting navigation', () {
    final adapter = _adapter(host: CCNavigationHost(id: 'window.main'));
    addTearDown(adapter.dispose);
    expect(
      () => adapter.initialize([
        route(
          'detail',
          placement: const CCRoutePlacement(hostId: 'window.other'),
        ),
      ]),
      throwsA(isA<CCNavigationAdapterError>()),
    );
    expect(adapter.requests, isEmpty);
  });

  test('enables predictive-back bridge only when explicitly requested', () {
    final adapter = _adapter(enablePredictiveBack: true);

    final bridge = adapter.predictiveBackBridge;
    expect(bridge, isNotNull);
    expect(bridge, isA<CCPredictiveBackCoordinator>());
    expect(adapter.capabilities.supportsPredictiveBack, isTrue);
    adapter.bindPopGuardEvaluator((trigger) {
      expect(trigger, CCPopTrigger.predictiveBack);
      return const CCPopDeny(code: 'predictive_blocked');
    });
    final guarded = bridge!.evaluateStart();
    expect(guarded, isA<CCPopDeny>());
    expect((guarded as CCPopDeny).code, 'predictive_blocked');
    final events = <CCPredictiveBackEvent>[];
    final remove = bridge.addPredictiveBackListener(events.add);

    bridge.started();
    bridge.updated(.5);
    bridge.cancelled(.5);
    expect(() => bridge.updated(1.1), throwsArgumentError);
    expect(() => bridge.cancelled(-.1), throwsArgumentError);
    bridge.committed(
      const CCPopOutcome(
        handled: true,
        removedEntryOwner: CCPopRemovedEntryOwner.managed,
        removedBackendEntryId: 'managed-1',
      ),
    );
    expect(events.map((event) => event.phase), [
      CCPredictiveBackPhase.started,
      CCPredictiveBackPhase.updated,
      CCPredictiveBackPhase.cancelled,
      CCPredictiveBackPhase.committed,
    ]);
    expect(events[1].progress, .5);
    expect(events.last.outcome?.removedBackendEntryId, 'managed-1');

    remove();
    bridge.started();
    expect(events, hasLength(4));
    adapter.dispose();
    expect(adapter.predictiveBackBridge, isNotNull);
    expect(bridge.evaluateStart(), isA<CCPopAllow>());
    bridge.started();
    expect(events, hasLength(4));
  });

  test('foreign bridge preserves exact identity without navigating', () async {
    final adapter = _adapter();
    adapter.initialize([route('detail')]);
    final events = <CCNavigationBackendEvent>[];
    adapter.addBackendEventListener(events.add);
    final bridge = adapter.foreignRouteBridge;
    final first = bridge.push(
      navigatorOutlet: 'third-party',
      hostId: 'window.main',
      location: '/one',
    );
    final next = bridge.replace(first, location: '/two');
    bridge.pop(next);
    await Future<void>.delayed(Duration.zero);
    expect(events.map((event) => event.kind), [
      CCNavigationBackendEventKind.push,
      CCNavigationBackendEventKind.replace,
      CCNavigationBackendEventKind.pop,
    ]);
    expect(
      events.every((event) => event.owner == CCBackendEntryOwner.foreign),
      isTrue,
    );
    expect(events[1].previousBackendEntryId, first.backendEntryId);
    expect(events.last.backendEntryId, next.backendEntryId);
    expect(
      events.every(
        (event) =>
            event.hostId == 'window.main' &&
            event.navigatorOutlet == 'third-party' &&
            event.navigationId == null,
      ),
      isTrue,
    );
    expect(adapter.requests, isEmpty);
    expect(() => bridge.pop(next), throwsA(isA<CCNavigationAdapterError>()));
    adapter.dispose();
    expect(() => bridge.push(), throwsA(isA<CCNavigationAdapterError>()));
  });

  test(
    'opaque bridge is diagnostic only and rejects foreign or ended handles',
    () async {
      final adapter = _adapter()..initialize([route('detail')]);
      final other = _adapter()..initialize([route('detail')]);
      addTearDown(other.dispose);
      final events = <CCNavigationBackendEvent>[];
      adapter.addBackendEventListener(events.add);
      final bridge = adapter.foreignRouteBridge;
      final opaque = bridge.pushOpaque(location: 'menu:account');
      expect(
        () => other.foreignRouteBridge.removeOpaque(opaque),
        throwsA(isA<CCNavigationAdapterError>()),
      );
      bridge.removeOpaque(opaque);
      await Future<void>.delayed(Duration.zero);
      expect(events.map((event) => event.kind), [
        CCNavigationBackendEventKind.push,
        CCNavigationBackendEventKind.remove,
      ]);
      expect(
        events.every(
          (event) =>
              event.owner == CCBackendEntryOwner.opaque &&
              event.routeId == null &&
              event.navigationId == null &&
              event.backendEntryId == opaque.backendEntryId,
        ),
        isTrue,
      );
      expect(adapter.requests, isEmpty);
      expect(
        () => bridge.removeOpaque(opaque),
        throwsA(isA<CCNavigationAdapterError>()),
      );
      adapter.dispose();
      expect(
        () => bridge.pushOpaque(),
        throwsA(isA<CCNavigationAdapterError>()),
      );
    },
  );

  test(
    'Adapter lifecycle rejects work before initialization and after disposal',
    () {
      final adapter = _adapter();
      final navigation = request(
        id: 'detail',
        operation: CCNavigationOperation.go,
        uri: Uri.parse('/detail/1'),
      );
      expect(
        () => adapter.navigate(navigation),
        throwsA(isA<CCNavigationAdapterError>()),
      );
      adapter.initialize([route('detail')]);
      expect(
        () => adapter.initialize([route('detail')]),
        throwsA(isA<CCNavigationAdapterError>()),
      );
      adapter.dispose();
      expect(
        () => adapter.navigate(navigation),
        throwsA(isA<CCNavigationAdapterError>()),
      );
      expect(() => adapter.canPop(), throwsA(isA<CCNavigationAdapterError>()));
      expect(
        () => adapter.initialize([route('detail')]),
        throwsA(isA<CCNavigationAdapterError>()),
      );
      adapter.dispose();
    },
  );

  test(
    'Session close preserves the Adapter while Runtime disposal owns it',
    () async {
      final adapter = _adapter();
      final runtime = CCRouterRuntime.forTesting(
        navigationAdapter: adapter,
        components: const [],
      );
      runtime.initialize();
      runtime.openSession(accountId: 'account');
      await runtime.closeSession();
      expect(adapter.canPop(), isFalse);
      await runtime.dispose();
      expect(() => adapter.canPop(), throwsA(isA<CCNavigationAdapterError>()));
    },
  );
}
