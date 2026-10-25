import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:ccrouter_test/ccrouter_test.dart';
import 'package:ccrouter_test/ccrouter_ui_test.dart';
import 'package:ccrouter_ui/ccrouter_ui.dart';
import 'package:ccrouter_ui/ccrouter_ui_generated.dart';
import 'package:ccrouter_ui/ccrouter_ui_host.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _descriptor = CCUIFragmentDescriptor(
  owner: 'owner',
  id: 'owner.card',
  version: '1.0.0',
  fingerprint:
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
);
const _requirement = CCUIFragmentRequirement(
  consumer: 'consumer',
  contract: _descriptor,
  versionRange: '^1.0.0',
);

final class _Props {
  const _Props(this.value);
  final int value;
}

enum _Action { select }

ValueChanged<_Action>? _emit;
Widget _renderer(CCUIFragmentRenderInput<_Props, _Action> input) {
  _emit = input.onAction;
  return Text('${input.props.value}', textDirection: TextDirection.ltr);
}

final class _Registrar implements CCComponentRegistrar {
  const _Registrar({this.fail = false});
  final bool fail;
  @override
  void register(CCRegistry registry) {
    if (fail) throw StateError('registration');
  }
}

CCHostAssembly _assembly({bool fail = false}) => CCUIHostAssembly.attach(
  CCHostAssembly.fromComponents(
    components: [
      const CCComponentManifest(
        id: 'owner',
        version: '1.0.0',
        registrar: _Registrar(),
      ),
      CCComponentManifest(
        id: 'consumer',
        version: '1.0.0',
        dependencies: const ['owner'],
        registrar: _Registrar(fail: fail),
      ),
    ],
  ),
  contributions: const [
    CCUIRenderer<_Props, _Action>(contract: _descriptor, renderer: _renderer),
  ],
  requirements: const [_requirement],
);

Widget _fragment({
  int value = 1,
  bool active = true,
  ValueChanged<_Action>? onAction,
}) => CCUIGeneratedFragment<_Props, _Action>(
  requirement: _requirement,
  props: _Props(value),
  active: active,
  onAction: onAction ?? (_) {},
);

final class _FailingDetach implements CCHostLifecycleBinding {
  _FailingDetach(this.error);
  final Object error;
  @override
  String get id => 'test.failingDetach';
  @override
  void attach() {}
  @override
  void detach() => throw error;
}

final class _AttachCallback implements CCHostLifecycleBinding {
  _AttachCallback(this.callback);
  final void Function() callback;
  @override
  String get id => 'test.startup';
  @override
  void attach() => callback();
  @override
  void detach() {}
}

void main() {
  tearDown(() async {
    _emit = null;
    await CCRouterHost.shutdown();
  });

  test(
    'disposal before run cannot take ownership of an existing Host',
    () async {
      CCRouterHost.initialize(hostAssembly: _assembly());
      final host = CCUIFragmentTestHost(hostAssembly: _assembly());
      await host.dispose();
      await expectLater(
        host.run(() async {}, unmount: () async {}),
        throwsStateError,
      );
      expect(CCRouter.isInitialized, isTrue);
    },
  );

  test(
    'reentrant disposal during startup skips the body and closes acquired Host',
    () async {
      late CCUIFragmentTestHost host;
      late Future<({Object error, StackTrace stack})?> disposal;
      var bodyCalled = false;
      var unmounts = 0;
      host = CCUIFragmentTestHost(
        hostAssembly: CCHostAssembly.withLifecycleBindings(_assembly(), [
          _AttachCallback(() => disposal = _observe(host.dispose)),
        ]),
      );
      await expectLater(
        host.run(
          () async => bodyCalled = true,
          unmount: () async => unmounts++,
        ),
        throwsStateError,
      );
      expect(await disposal, isNull);
      expect(bodyCalled, isFalse);
      expect(unmounts, 1);
      expect(CCRouter.isInitialized, isFalse);
      await host.dispose();
    },
  );

  for (final fails in [false, true]) {
    test(
      'concurrent, reentrant and late disposal joins across error Zones: failure=$fails',
      () async {
        final bodyEntered = Completer<void>();
        final releaseBody = Completer<void>();
        final cleanupEntered = Completer<void>();
        final releaseCleanup = Completer<void>();
        final error = StateError('unmount');
        final stack = StackTrace.fromString('original UI test cleanup stack');
        var unmounts = 0;
        late CCUIFragmentTestHost host;
        late Future<({Object error, StackTrace stack})?> reentrant;
        host = CCUIFragmentTestHost(hostAssembly: _assembly());
        final running = _observe(
          () => host.run(
            () async {
              bodyEntered.complete();
              await releaseBody.future;
            },
            unmount: () async {
              unmounts++;
              reentrant = _observe(host.dispose);
              cleanupEntered.complete();
              await releaseCleanup.future;
              if (fails) Error.throwWithStackTrace(error, stack);
            },
          ),
        );
        await bodyEntered.future;
        final first = _inErrorZone(host.dispose);
        await cleanupEntered.future;
        final second = _inErrorZone(host.dispose);
        expect(CCRouter.isInitialized, isTrue);
        releaseCleanup.complete();
        final outcomes = [await first, await second, await reentrant];
        expect(CCRouter.isInitialized, isFalse);
        outcomes.add(await _inErrorZone(host.dispose));
        releaseBody.complete();
        outcomes.add(await running);
        for (final outcome in outcomes) {
          if (fails) {
            expect(outcome?.error, same(error));
            expect(outcome?.stack.toString(), stack.toString());
          } else {
            expect(outcome, isNull);
          }
        }
        expect(unmounts, 1);
      },
    );
  }

  testWidgets(
    'dispose releases a Host without waiting for its body',
    (tester) async {
      final host = CCUIFragmentTestHost(hostAssembly: _assembly());
      addTearDown(host.dispose);
      final entered = Completer<void>();
      final release = Completer<void>();
      var unmounts = 0;
      final running = host.run(
        () async {
          await tester.pumpWidget(_fragment());
          entered.complete();
          await release.future;
        },
        unmount: () async {
          unmounts++;
          await tester.pumpWidget(const SizedBox());
        },
      );
      await entered.future;
      try {
        await host.dispose();
        expect(CCRouter.isInitialized, isFalse);
        expect(unmounts, 1);
        final replacement = CCHostAssembly.fromComponents(components: const []);
        CCRouterHost.initialize(hostAssembly: replacement);
        release.complete();
        await running;
        await host.dispose();
        expect(unmounts, 1);
        expect(CCRouter.isInitialized, isTrue);
        expect(CCRouter.registeredComponents, isEmpty);
      } finally {
        if (!release.isCompleted) release.complete();
        await running;
      }
    },
    timeout: const Timeout(Duration(seconds: 10)),
  );

  test(
    'registered teardown isolates the test after a real Widget timeout',
    () async {
      final root = _workspaceRoot();
      final configFile = File('${root.path}/.dart_tool/package_config.json');
      final config =
          jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>;
      final flutter = (config['packages'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere((p) => p['name'] == 'flutter');
      final sdk = Directory.fromUri(
        configFile.uri.resolve(flutter['rootUri'] as String),
      ).parent.parent;
      final child = await Process.start(
        '${sdk.path}/bin/${Platform.isWindows ? 'flutter.bat' : 'flutter'}',
        [
          'test',
          '--no-pub',
          '--reporter=json',
          'packages/ccrouter_test/test/fixtures/ui_fragment_timeout.dart',
        ],
        workingDirectory: root.path,
        runInShell: Platform.isWindows,
      );
      final output = child.stdout.transform(utf8.decoder).join();
      final errors = child.stderr.transform(utf8.decoder).join();
      var exited = false;
      try {
        final code = await child.exitCode.timeout(const Duration(seconds: 45));
        exited = true;
        final stdout = await output;
        final stderr = await errors;
        final events = stdout
            .split('\n')
            .where((line) => line.startsWith('{'))
            .map((line) => jsonDecode(line) as Map<String, dynamic>)
            .toList();
        int testId(String name) =>
            (events.singleWhere(
                      (event) =>
                          event['type'] == 'testStart' &&
                          (event['test'] as Map)['name'] == name,
                    )['test']
                    as Map)['id']
                as int;
        String result(int id) =>
            events.singleWhere(
                  (event) =>
                      event['type'] == 'testDone' && event['testID'] == id,
                )['result']
                as String;
        expect(code, 1, reason: '$stdout\n$stderr');
        expect(result(testId('body times out')), 'error');
        expect(result(testId('next Widget test gets a clean Host')), 'success');
        final failures = events
            .where((event) => event['type'] == 'error')
            .toList();
        expect(failures, hasLength(1), reason: '$stdout\n$stderr');
        expect(failures.single['error'], contains('TimeoutException'));
      } finally {
        if (!exited) child.kill();
      }
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  testWidgets('real UI actions update, revoke and stay isolated between runs', (
    tester,
  ) async {
    final assembly = _assembly();
    var first = 0;
    var latest = 0;
    late ValueChanged<_Action> oldAction;
    final host = CCUIFragmentTestHost(hostAssembly: assembly);
    await host.run(() async {
      await tester.pumpWidget(_fragment(onAction: (_) => first++));
      oldAction = _emit!;
      oldAction(_Action.select);
      await tester.pumpWidget(_fragment(value: 2, onAction: (_) => latest++));
      expect(find.text('2'), findsOneWidget);
      oldAction(_Action.select);
      await tester.pumpWidget(_fragment(active: false));
      oldAction(_Action.select);
      expect(first, 1);
      expect(latest, 1);
    }, unmount: () => tester.pumpWidget(const SizedBox()));
    oldAction(_Action.select);
    expect(latest, 1);
    expect(CCRouter.isInitialized, isFalse);
    await expectLater(
      host.run(() async {}, unmount: () async {}),
      throwsStateError,
    );
    await CCUIFragmentTestHost(hostAssembly: assembly).run(() async {
      await tester.pumpWidget(_fragment(onAction: (_) => latest++));
      oldAction(_Action.select);
      expect(latest, 1);
      _emit!(_Action.select);
      expect(latest, 2);
    }, unmount: () => tester.pumpWidget(const SizedBox()));
  });

  test(
    'failure retains original error and still unmounts and shuts down',
    () async {
      final bodyError = StateError('body');
      final stack = StackTrace.current;
      var unmounted = false;
      final result = CCUIFragmentTestHost(hostAssembly: _assembly()).run(
        () async => Error.throwWithStackTrace(bodyError, stack),
        unmount: () async {
          unmounted = true;
          throw StateError('unmount');
        },
      );
      try {
        await result;
        fail('Expected original body failure');
      } catch (error, actualStack) {
        expect(error, same(bodyError));
        expect(actualStack.toString(), stack.toString());
      }
      expect(unmounted, isTrue);
      expect(CCRouter.isInitialized, isFalse);
      await CCUIFragmentTestHost(
        hostAssembly: _assembly(),
      ).run(() async {}, unmount: () async {});
    },
  );

  test('unmount failure still shuts down and is reported', () async {
    final error = StateError('unmount');
    await expectLater(
      CCUIFragmentTestHost(
        hostAssembly: _assembly(),
      ).run(() async {}, unmount: () async => throw error),
      throwsA(same(error)),
    );
    expect(CCRouter.isInitialized, isFalse);
  });

  test(
    'shutdown failures surface after unmount and release other UI bindings',
    () async {
      final error = StateError('detach');
      final assembly = CCHostAssembly.withLifecycleBindings(_assembly(), [
        _FailingDetach(error),
      ]);
      var unmounted = false;
      await expectLater(
        CCUIFragmentTestHost(hostAssembly: assembly).run(
          () async {},
          unmount: () async {
            expect(CCRouter.isInitialized, isTrue);
            unmounted = true;
          },
        ),
        throwsA(same(error)),
      );
      expect(unmounted, isTrue);
      expect(CCRouter.isInitialized, isFalse);
      await CCUIFragmentTestHost(
        hostAssembly: _assembly(),
      ).run(() async {}, unmount: () async {});
    },
  );

  test('shutdown failure does not replace a body failure', () async {
    final primary = StateError('body');
    final assembly = CCHostAssembly.withLifecycleBindings(_assembly(), [
      _FailingDetach(StateError('detach')),
    ]);
    await expectLater(
      CCUIFragmentTestHost(
        hostAssembly: assembly,
      ).run(() async => throw primary, unmount: () async {}),
      throwsA(same(primary)),
    );
    expect(CCRouter.isInitialized, isFalse);
  });

  test(
    'initialization failure joins rollback without running caller cleanup',
    () async {
      var touched = false;
      await expectLater(
        CCUIFragmentTestHost(
          hostAssembly: _assembly(fail: true),
        ).run(() async => touched = true, unmount: () async => touched = true),
        throwsA(anything),
      );
      expect(touched, isFalse);
      expect(CCRouter.isInitialized, isFalse);
      await CCUIFragmentTestHost(
        hostAssembly: _assembly(),
      ).run(() async {}, unmount: () async {});
    },
  );

  test('rejects an occupied default Host without disposing it', () async {
    CCRouterHost.initialize(hostAssembly: _assembly());
    var touched = false;
    await expectLater(
      CCUIFragmentTestHost(
        hostAssembly: _assembly(),
      ).run(() async => touched = true, unmount: () async => touched = true),
      throwsA(isA<CCRouterAlreadyInitializedError>()),
    );
    expect(touched, isFalse);
    expect(CCRouter.isInitialized, isTrue);
  });

  test('overlapping helpers fail without disrupting the owning run', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    final first = CCUIFragmentTestHost(hostAssembly: _assembly()).run(() async {
      entered.complete();
      await release.future;
    }, unmount: () async {});
    await entered.future;
    try {
      await expectLater(
        CCUIFragmentTestHost(
          hostAssembly: _assembly(),
        ).run(() async {}, unmount: () async => fail('Not owned')),
        throwsA(isA<CCRouterAlreadyInitializedError>()),
      );
      expect(CCRouter.isInitialized, isTrue);
    } finally {
      release.complete();
      await first;
    }
    expect(CCRouter.isInitialized, isFalse);
  });

  test('cleanup never shuts down a replacement default Host', () async {
    final replacement = CCHostAssembly.fromComponents(components: const []);
    await CCUIFragmentTestHost(hostAssembly: _assembly()).run(() async {
      await CCRouterHost.shutdown();
      CCRouterHost.initialize(hostAssembly: replacement);
    }, unmount: () async {});
    expect(CCRouter.isInitialized, isTrue);
    expect(CCRouter.registeredComponents, isEmpty);
  });

  test('rejects Zone overlays and preserves their Runtime', () async {
    final overlay = CCRouterTestHost();
    overlay.initialize();
    addTearDown(overlay.dispose);
    await overlay.run(() async {
      await expectLater(
        CCUIFragmentTestHost(
          hostAssembly: _assembly(),
        ).run(() async {}, unmount: () async => fail('Not owned')),
        throwsA(isA<CCRouterAlreadyInitializedError>()),
      );
      expect(CCRouter.isInitialized, isTrue);
    });
    expect(CCRouter.isInitialized, isFalse);
  });
}

Future<({Object error, StackTrace stack})?> _observe(
  Future<void> Function() invoke,
) async {
  try {
    await invoke();
    return null;
  } catch (error, stack) {
    return (error: error, stack: stack);
  }
}

Future<({Object error, StackTrace stack})?> _inErrorZone(
  Future<void> Function() invoke,
) {
  final completion = Completer<({Object error, StackTrace stack})?>();
  runZonedGuarded(() async {
    completion.complete(await _observe(invoke));
  }, completion.completeError);
  return completion.future;
}

Directory _workspaceRoot() {
  var current = Directory.current.absolute;
  while (!File(
    '${current.path}/packages/ccrouter_test/pubspec.yaml',
  ).existsSync()) {
    final parent = current.parent;
    if (parent.path == current.path)
      throw StateError('Workspace root not found.');
    current = parent;
  }
  return current;
}
