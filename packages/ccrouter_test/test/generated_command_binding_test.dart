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
  tearDown(CCRouter.shutdown);

  test(
    'generated binding preserves stable ID and component identities',
    () async {
      CCRouter.initialize(
        components: const [
          CCComponentManifest(
            id: 'owner',
            version: '1.0.0',
            registrar: _GeneratedCommandRegistrar(),
          ),
        ],
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
    CCRouter.initialize(
      components: const [
        CCComponentManifest(
          id: 'owner',
          version: '1.0.0',
          registrar: _GeneratedCommandRegistrar(),
        ),
      ],
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
}
