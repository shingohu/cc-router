import 'package:ccrouter/ccrouter_generated.dart';
import 'package:test/test.dart';

final class _GeneratedChanged implements CCEvent {
  const _GeneratedChanged();
}

final class _OtherGeneratedChanged implements CCEvent {
  const _OtherGeneratedChanged();
}

final class _EmptyRegistrar implements CCComponentRegistrar {
  const _EmptyRegistrar();

  @override
  void register(CCRegistry registry) {}
}

final class _GeneratedEventRegistrar implements CCComponentRegistrar {
  const _GeneratedEventRegistrar();

  @override
  void register(CCRegistry registry) {
    registry.registerEventSubscriber<_GeneratedChanged>(
      CCEventSubscriber<_GeneratedChanged>(
        id: const CCEventSubscriberId<_GeneratedChanged>('consumer.changed'),
        eventId: 'owner.changed',
        handler: (_, context) {
          expect(context.callerComponentId, 'owner');
          expect(context.targetComponentId, 'consumer');
        },
      ),
    );
  }
}

void main() {
  tearDown(CCRouter.shutdown);

  test(
    'generated binding preserves stable Event and component identities',
    () async {
      CCRouter.initialize(
        hostAssembly: CCHostAssembly.fromComponents(
          components: const [
            CCComponentManifest(
              id: 'owner',
              version: '1.0.0',
              registrar: _EmptyRegistrar(),
            ),
            CCComponentManifest(
              id: 'consumer',
              version: '1.0.0',
              dependencies: ['owner'],
              registrar: _GeneratedEventRegistrar(),
            ),
          ],
        ),
      );

      await CCRouterGeneratedEventBinding.publish(
        const _GeneratedChanged(),
        eventId: 'owner.changed',
        publisherComponentId: 'owner',
      );

      final publish = CCRouter.recentTraces.firstWhere(
        (trace) => trace.operation == 'event',
      );
      final subscriber = CCRouter.recentTraces.firstWhere(
        (trace) => trace.operation == 'eventSubscriber',
      );
      expect(publish.target, 'owner.changed');
      expect(publish.context.callerComponentId, 'owner');
      expect(subscriber.context.callerComponentId, 'owner');
      expect(subscriber.context.targetComponentId, 'consumer');
      expect(subscriber.target, 'owner.changed.consumer.changed');
    },
  );

  test('generated Event with zero subscribers is a traced no-op', () async {
    CCRouter.initialize(
      hostAssembly: CCHostAssembly.fromComponents(
        components: const [
          CCComponentManifest(
            id: 'owner',
            version: '1.0.0',
            registrar: _EmptyRegistrar(),
          ),
        ],
      ),
    );

    await CCRouterGeneratedEventBinding.publish(
      const _OtherGeneratedChanged(),
      eventId: 'owner.unobserved',
      publisherComponentId: 'owner',
    );

    expect(CCRouter.recentTraces.single.target, 'owner.unobserved');
  });

  test(
    'generated binding rejects an Event ID mismatched with subscribers',
    () async {
      CCRouter.initialize(
        hostAssembly: CCHostAssembly.fromComponents(
          components: const [
            CCComponentManifest(
              id: 'consumer',
              version: '1.0.0',
              registrar: _GeneratedEventRegistrar(),
            ),
          ],
        ),
      );

      expect(
        () => CCRouterGeneratedEventBinding.publish(
          const _GeneratedChanged(),
          eventId: 'owner.other',
          publisherComponentId: 'owner',
        ),
        throwsA(isA<CCResolutionError>()),
      );
    },
  );

  test('generated binding rejects missing or unauthorized publisher', () async {
    CCRouter.initialize(
      hostAssembly: CCHostAssembly.fromComponents(
        components: const [
          CCComponentManifest(
            id: 'owner',
            version: '1.0.0',
            registrar: _EmptyRegistrar(),
          ),
          CCComponentManifest(
            id: 'consumer',
            version: '1.0.0',
            registrar: _GeneratedEventRegistrar(),
          ),
        ],
      ),
    );

    expect(
      () => CCRouterGeneratedEventBinding.publish(
        const _GeneratedChanged(),
        eventId: 'owner.changed',
        publisherComponentId: 'missing',
      ),
      throwsA(isA<CCResolutionError>()),
    );
    expect(
      () => CCRouterGeneratedEventBinding.publish(
        const _GeneratedChanged(),
        eventId: 'owner.changed',
        publisherComponentId: 'owner',
      ),
      throwsA(isA<CCResolutionError>()),
    );
  });
}
