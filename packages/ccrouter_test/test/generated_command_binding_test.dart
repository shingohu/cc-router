import 'package:ccrouter/ccrouter_host.dart';
import 'package:ccrouter/ccrouter_generated.dart';
import 'package:test/test.dart';

final class _GeneratedGreeting implements CCCommand<String> {
  const _GeneratedGreeting(this.name);

  final String name;
}

final class _GeneratedCommandRegistrar implements CCComponentRegistrar {
  const _GeneratedCommandRegistrar();

  @override
  void register(CCRegistry registry) {
    registry.registerCommand<_GeneratedGreeting, String>((command, context) {
      expect(context.callerComponentId, 'consumer');
      expect(context.targetComponentId, 'owner');
      return 'hello ${command.name}';
    }, commandId: 'owner.greeting');
  }
}

void main() {
  tearDown(CCRouterHost.shutdown);

  test(
    'generated binding preserves stable ID and component identities',
    () async {
      CCRouterHost.initialize(
        hostAssembly: CCHostAssembly.fromComponents(
          components: const [
            CCComponentManifest(
              id: 'owner',
              version: '1.0.0',
              registrar: _GeneratedCommandRegistrar(),
            ),
            CCComponentManifest(
              id: 'consumer',
              version: '1.0.0',
              dependencies: ['owner'],
              registrar: _EmptyCommandRegistrar(),
            ),
          ],
        ),
      );

      final result =
          await CCRouterGeneratedCommandBinding.invoke<
            _GeneratedGreeting,
            String
          >(
            const _GeneratedGreeting('Ada'),
            commandId: 'owner.greeting',
            callerComponentId: 'consumer',
          );

      expect(result, 'hello Ada');
      final trace = CCRouter.recentTraces.single;
      expect(trace.target, 'owner.greeting');
      expect(trace.context.callerComponentId, 'consumer');
      expect(trace.context.targetComponentId, 'owner');
    },
  );

  test('generated binding rejects a mismatched stable ID', () async {
    CCRouterHost.initialize(
      hostAssembly: CCHostAssembly.fromComponents(
        components: const [
          CCComponentManifest(
            id: 'owner',
            version: '1.0.0',
            registrar: _GeneratedCommandRegistrar(),
          ),
        ],
      ),
    );

    expect(
      () => CCRouterGeneratedCommandBinding.invoke<_GeneratedGreeting, String>(
        const _GeneratedGreeting('Ada'),
        commandId: 'owner.other',
        callerComponentId: 'consumer',
      ),
      throwsA(isA<CCResolutionError>()),
    );
  });

  test('generated binding rejects forged component attribution', () async {
    CCRouterHost.initialize(
      hostAssembly: CCHostAssembly.fromComponents(
        components: const [
          CCComponentManifest(
            id: 'owner',
            version: '1.0.0',
            registrar: _GeneratedCommandRegistrar(),
          ),
          CCComponentManifest(
            id: 'unrelated',
            version: '1.0.0',
            registrar: _EmptyCommandRegistrar(),
          ),
        ],
      ),
    );

    expect(
      () => CCRouterGeneratedCommandBinding.invoke<_GeneratedGreeting, String>(
        const _GeneratedGreeting('Ada'),
        commandId: 'owner.greeting',
        callerComponentId: 'missing',
      ),
      throwsA(isA<CCResolutionError>()),
    );
    expect(
      () => CCRouterGeneratedCommandBinding.invoke<_GeneratedGreeting, String>(
        const _GeneratedGreeting('Ada'),
        commandId: 'owner.greeting',
        callerComponentId: 'unrelated',
      ),
      throwsA(isA<CCResolutionError>()),
    );
  });
}

final class _EmptyCommandRegistrar implements CCComponentRegistrar {
  const _EmptyCommandRegistrar();

  @override
  void register(CCRegistry registry) {}
}
