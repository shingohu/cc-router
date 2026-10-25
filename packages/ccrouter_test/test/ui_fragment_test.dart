import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:ccrouter_ui/ccrouter_ui.dart';
import 'package:ccrouter_ui/ccrouter_ui_generated.dart';
import 'package:ccrouter_ui/ccrouter_ui_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Registrar implements CCComponentRegistrar {
  const _Registrar({this.fail = false});
  final bool fail;
  @override
  void register(CCRegistry registry) {
    if (fail) throw StateError('registration failed');
  }
}

final class _LifecycleBinding implements CCHostLifecycleBinding {
  _LifecycleBinding(this.id, {required this.onAttach, required this.onDetach});
  @override
  final String id;
  final void Function() onAttach;
  final void Function() onDetach;
  @override
  void attach() => onAttach();
  @override
  void detach() => onDetach();
}

final class _OwnedService implements CCDisposable {
  bool disposed = false;
  @override
  void dispose() {
    disposed = true;
  }
}

final class _ServiceRegistrar implements CCComponentRegistrar {
  const _ServiceRegistrar();
  @override
  void register(CCRegistry registry) {
    registry.registerService<_OwnedService>(
      CCServiceProvider(factory: (_) => _OwnedService()),
    );
  }
}

const _fingerprint =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _contract = CCUIFragmentDescriptor(
  owner: 'orders',
  id: 'orders.summary',
  version: '1.0.0',
  fingerprint: _fingerprint,
);
const _requirement = CCUIFragmentRequirement(
  consumer: 'account',
  contract: _contract,
  versionRange: '^1.0.0',
);

final class _Props {
  const _Props(this.id);
  final int id;
}

enum _Action { select }

final class _Selection {
  const _Selection(this.id);
  final String id;
}

final _payloadCallbacks = <ValueChanged<_Selection>>[];
Widget _payloadRenderer(CCUIFragmentRenderInput<_Props, _Selection> input) {
  _payloadCallbacks.add(input.onAction);
  return const SizedBox();
}

sealed class _UnionTarget {
  const _UnionTarget(this.id);
  final String id;
}

final class _UserTarget extends _UnionTarget {
  const _UserTarget(super.id);
}

final class _ScoreTarget extends _UnionTarget {
  const _ScoreTarget(super.id);
}

final class _VideoTarget extends _UnionTarget {
  const _VideoTarget(super.id);
}

final class _ArtistTarget extends _UnionTarget {
  const _ArtistTarget(super.id);
}

sealed class _UnionAction {
  const _UnionAction();
}

final class _SettingsRequested extends _UnionAction {
  const _SettingsRequested();
}

final class _TargetSelected extends _UnionAction {
  const _TargetSelected(this.target);
  final _UnionTarget target;
}

final _unionCallbacks = <ValueChanged<_UnionAction>>[];
Widget _unionRenderer(CCUIFragmentRenderInput<_Props, _UnionAction> input) {
  _unionCallbacks.add(input.onAction);
  return const SizedBox();
}

String _unionLabel(_UnionAction action) => switch (action) {
  _SettingsRequested() => 'settings',
  _TargetSelected(:final target) => switch (target) {
    _UserTarget(:final id) => 'user:$id',
    _ScoreTarget(:final id) => 'score:$id',
    _VideoTarget(:final id) => 'video:$id',
    _ArtistTarget(:final id) => 'artist:$id',
  },
};

int _created = 0;
int _disposed = 0;
final _actions = <void Function()>[];

Widget _renderer(CCUIFragmentRenderInput<_Props, _Action> input) =>
    _Card(input);

final class _Card extends StatefulWidget {
  const _Card(this.input);
  final CCUIFragmentRenderInput<_Props, _Action> input;
  @override
  State<_Card> createState() => _CardState();
}

final class _CardState extends State<_Card> {
  late final int identity = ++_created;
  final controller = TextEditingController();
  @override
  Widget build(BuildContext context) {
    _actions.add(() => widget.input.onAction(_Action.select));
    return Text(
      'instance:$identity props:${widget.input.props.id} active:${widget.input.active}',
      textDirection: TextDirection.ltr,
    );
  }

  @override
  void dispose() {
    _disposed++;
    controller.dispose();
    super.dispose();
  }
}

CCHostAssembly _base({bool fail = false, bool dependency = true}) =>
    CCHostAssembly.fromComponents(
      components: [
        const CCComponentManifest(
          id: 'orders',
          version: '1.0.0',
          registrar: _Registrar(),
        ),
        CCComponentManifest(
          id: 'account',
          version: '1.0.0',
          registrar: _Registrar(fail: fail),
          dependencies: dependency ? ['orders'] : [],
        ),
      ],
    );

CCHostAssembly _assembly({
  bool fail = false,
  List<CCUIFragmentContribution>? contributions,
  List<CCUIFragmentRequirement> requirements = const [_requirement],
}) => CCUIHostAssembly.attach(
  _base(fail: fail),
  contributions:
      contributions ??
      [
        const CCUIRenderer<_Props, _Action>(
          contract: _contract,
          renderer: _renderer,
        ),
      ],
  requirements: requirements,
);

Widget _fragment({
  int id = 1,
  bool active = true,
  Key? key,
  ValueChanged<_Action>? onAction,
  CCUIFragmentRequirement requirement = _requirement,
}) => CCUIGeneratedFragment<_Props, _Action>(
  key: key,
  props: _Props(id),
  active: active,
  onAction: onAction ?? (_) {},
  requirement: requirement,
);

Matcher _code(String code) =>
    isA<CCUIFragmentError>().having((e) => e.code, 'code', code);

void main() {
  setUp(() {
    _created = 0;
    _disposed = 0;
    _actions.clear();
  });
  tearDown(CCRouterHost.shutdown);
  test(
    'review Host rejects a stale Contract version even inside the range',
    () {
      const newer = CCUIFragmentDescriptor(
        owner: 'orders',
        id: 'orders.summary',
        version: '1.0.1',
        fingerprint: _fingerprint,
      );
      expect(
        () => _assembly(
          contributions: [
            const CCUIRenderer<_Props, _Action>(
              contract: newer,
              renderer: _renderer,
            ),
          ],
        ),
        throwsA(_code('staleGeneratedOutput')),
      );
      expect(CCRouter.isInitialized, isFalse);
    },
  );
  for (final (kind, stale) in <(String, CCUIFragmentRequirement)>[
    (
      'shape',
      const CCUIFragmentRequirement(
        consumer: 'account',
        contract: CCUIFragmentDescriptor(
          owner: 'orders',
          id: 'orders.summary',
          version: '1.0.0',
          fingerprint:
              'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        ),
        versionRange: '^1.0.0',
      ),
    ),
    (
      'version',
      const CCUIFragmentRequirement(
        consumer: 'account',
        contract: CCUIFragmentDescriptor(
          owner: 'orders',
          id: 'orders.summary',
          version: '1.0.1',
          fingerprint: _fingerprint,
        ),
        versionRange: '^1.0.0',
      ),
    ),
    (
      'range',
      const CCUIFragmentRequirement(
        consumer: 'account',
        contract: _contract,
        versionRange: '>=1.0.0',
      ),
    ),
  ]) {
    testWidgets(
      'review stale $kind updates permanently revoke retained Actions',
      (tester) async {
        CCRouterHost.initialize(hostAssembly: _assembly());
        var first = 0;
        var latest = 0;
        await tester.pumpWidget(_fragment(onAction: (_) => first++));
        final oldAction = _actions.last;
        await tester.pumpWidget(
          _fragment(requirement: stale, onAction: (_) => latest++),
        );
        expect(tester.takeException(), _code('staleGeneratedOutput'));
        oldAction();
        expect(first, 0);
        expect(latest, 0);
        await tester.pumpWidget(_fragment(onAction: (_) => latest++));
        oldAction();
        expect(
          latest,
          0,
          reason: 'Restoring valid metadata must not revive the revoked sink.',
        );
        _actions.last();
        expect(latest, 1);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'sealed payloads preserve instances, callbacks and all revocation fences',
    (tester) async {
      CCHostAssembly assembly() => _assembly(
        contributions: [
          const CCUIRenderer<_Props, _UnionAction>(
            contract: _contract,
            renderer: _unionRenderer,
          ),
        ],
      );
      final first = <_UnionAction>[];
      final latest = <_UnionAction>[];
      final second = <_UnionAction>[];
      Widget tree({
        bool active = true,
        bool update = false,
        int identity = 0,
      }) => Row(
        textDirection: TextDirection.ltr,
        children: [
          CCUIGeneratedFragment<_Props, _UnionAction>(
            key: ValueKey('first-$identity'),
            requirement: _requirement,
            props: const _Props(1),
            active: active,
            onAction: (update ? latest : first).add,
          ),
          CCUIGeneratedFragment<_Props, _UnionAction>(
            key: ValueKey('second-$identity'),
            requirement: _requirement,
            props: const _Props(2),
            onAction: second.add,
          ),
        ],
      );
      const payloads = <_UnionAction>[
        _SettingsRequested(),
        _TargetSelected(_UserTarget('1')),
        _TargetSelected(_ScoreTarget('2')),
        _TargetSelected(_VideoTarget('3')),
        _TargetSelected(_ArtistTarget('4')),
      ];
      _unionCallbacks.clear();
      CCRouterHost.initialize(hostAssembly: assembly());
      await tester.pumpWidget(tree());
      final oldFirst = _unionCallbacks[0];
      final oldSecond = _unionCallbacks[1];
      for (final payload in payloads) {
        oldFirst(payload);
      }
      expect(first.map(_unionLabel), [
        'settings',
        'user:1',
        'score:2',
        'video:3',
        'artist:4',
      ]);
      for (var i = 0; i < payloads.length; i++) {
        expect(first[i], same(payloads[i]));
      }
      oldSecond(payloads.last);
      expect(second.single, same(payloads.last));
      await tester.pumpWidget(tree(update: true));
      oldFirst(payloads.first);
      expect(latest.single, same(payloads.first));
      await tester.pumpWidget(tree(update: true, active: false));
      oldFirst(payloads.last);
      expect(latest, hasLength(1));
      await tester.pumpWidget(tree(update: true));
      oldFirst(payloads.last);
      expect(latest, hasLength(2));
      await tester.pumpWidget(tree(update: true, identity: 1));
      oldFirst(payloads.first);
      oldSecond(payloads.first);
      expect(latest, hasLength(2));
      expect(second, hasLength(1));
      final current = _unionCallbacks.last;
      await CCRouterHost.shutdown();
      current(payloads.first);
      CCRouterHost.initialize(hostAssembly: assembly());
      current(payloads.first);
      await tester.pumpWidget(tree(identity: 2));
      _unionCallbacks.last(payloads.first);
      expect(second.map(_unionLabel), ['artist:4', 'settings']);
      await tester.pumpWidget(const SizedBox());
      _unionCallbacks.last(payloads.first);
      expect(second, hasLength(2));
      expect(tester.takeException(), isNull);
      _unionCallbacks.clear();
    },
  );

  test(
    'optional binding failure rolls back in reverse order and blocks reentry',
    () {
      final events = <String>[];
      final base = _base();
      final assembly = CCHostAssembly.withLifecycleBindings(base, [
        _LifecycleBinding(
          'first',
          onAttach: () {
            events.add('first.attach');
            expect(
              () => CCRouterHost.initialize(hostAssembly: base),
              throwsA(isA<CCRouterAlreadyInitializedError>()),
            );
          },
          onDetach: () => events.add('first.detach'),
        ),
        _LifecycleBinding(
          'second',
          onAttach: () {
            events.add('second.attach');
            throw StateError('partial attach');
          },
          onDetach: () => events.add('second.detach'),
        ),
      ]);
      expect(
        () => CCRouterHost.initialize(hostAssembly: assembly),
        throwsStateError,
      );
      expect(events, [
        'first.attach',
        'second.attach',
        'second.detach',
        'first.detach',
      ]);
      expect(CCRouter.isInitialized, isFalse);
      CCRouterHost.initialize(hostAssembly: base);
    },
  );

  test(
    'failing detach still releases other bindings and existing App Services',
    () async {
      final events = <String>[];
      final base = CCHostAssembly.fromComponents(
        components: [
          const CCComponentManifest(
            id: 'services',
            version: '1.0.0',
            registrar: _ServiceRegistrar(),
          ),
        ],
      );
      final assembly = CCHostAssembly.withLifecycleBindings(base, [
        _LifecycleBinding(
          'first',
          onAttach: () {},
          onDetach: () => events.add('first'),
        ),
        _LifecycleBinding(
          'second',
          onAttach: () {},
          onDetach: () {
            events.add('second');
            throw StateError('detach');
          },
        ),
      ]);
      CCRouterHost.initialize(hostAssembly: assembly);
      final service = CCRouter.service<_OwnedService>();
      await expectLater(CCRouterHost.shutdown(), throwsStateError);
      expect(events, ['second', 'first']);
      expect(service.disposed, isTrue);
      expect(CCRouter.isInitialized, isFalse);
      CCRouterHost.initialize(hostAssembly: base);
    },
  );

  testWidgets(
    'unbound UI fails explicitly without changing ordinary Host startup',
    (tester) async {
      CCRouterHost.initialize(hostAssembly: _base());
      await tester.pumpWidget(_fragment());
      final error = tester.takeException();
      expect(error, _code('runtimeUnavailable'));
      expect(error.toString(), contains('CCHostAssembly.extend'));
      expect(error.toString(), contains('CCUIFragmentTestHost'));
      expect(CCRouter.isInitialized, isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Action failures propagate and ignored Action diagnostics remain bounded',
    (tester) async {
      CCRouterHost.initialize(hostAssembly: _assembly());
      await tester.pumpWidget(
        _fragment(onAction: (_) => throw StateError('callback')),
      );
      expect(_actions.last, throwsStateError);
      await tester.pumpWidget(_fragment(active: false));
      for (var i = 0; i < 200; i++) {
        _actions.last();
      }
      expect(CCUIHostAssembly.diagnostics.length, 128);
      expect(
        CCUIHostAssembly.diagnostics.every(
          (event) =>
              event.contractId == _contract.id && event.code == 'actionIgnored',
        ),
        isTrue,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'required catalog fails closed for missing, duplicate and undeclared edges',
    () {
      expect(
        () => _assembly(contributions: []),
        throwsA(_code('missingImplementation')),
      );
      const renderer = CCUIRenderer<_Props, _Action>(
        contract: _contract,
        renderer: _renderer,
      );
      expect(
        () => _assembly(contributions: [renderer, renderer]),
        throwsA(_code('duplicateImplementation')),
      );
      expect(
        () => CCUIHostAssembly.attach(
          _base(dependency: false),
          contributions: [renderer],
          requirements: [_requirement],
        ),
        throwsA(_code('dependencyMissing')),
      );
    },
  );

  test('version and public schema are enforced independently of Core kinds', () {
    expect(
      () => _assembly(
        requirements: [
          const CCUIFragmentRequirement(
            consumer: 'account',
            contract: _contract,
            versionRange: '^2.0.0',
          ),
        ],
      ),
      throwsA(_code('versionOutOfRange')),
    );
    expect(
      () => _assembly(
        requirements: [
          const CCUIFragmentRequirement(
            consumer: 'account',
            contract: CCUIFragmentDescriptor(
              owner: 'orders',
              id: 'orders.summary',
              version: '1.0.0',
              fingerprint:
                  'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
            ),
            versionRange: '^1.0.0',
          ),
        ],
      ),
      throwsA(_code('fingerprintChanged')),
    );
    expect(CCContractKind.values.map((e) => e.name), [
      'route',
      'service',
      'command',
      'event',
      'initTask',
    ]);
  });

  test(
    'initialization failure rolls back the optional binding for a later Host',
    () async {
      expect(
        () => CCRouterHost.initialize(hostAssembly: _assembly(fail: true)),
        throwsA(anything),
      );
      CCRouterHost.initialize(hostAssembly: _assembly());
      expect(CCRouter.activeRouteEntries, isEmpty);
      await CCRouterHost.shutdown();
      CCRouterHost.initialize(hostAssembly: _assembly());
    },
  );

  testWidgets('Props/callback update keeps State, Key change disposes it', (
    tester,
  ) async {
    CCRouterHost.initialize(hostAssembly: _assembly());
    var first = 0;
    var latest = 0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: _fragment(key: const ValueKey('a'), onAction: (_) => first++),
      ),
    );
    final oldAction = _actions.last;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: _fragment(
          id: 2,
          key: const ValueKey('a'),
          onAction: (_) => latest++,
        ),
      ),
    );
    expect(find.text('instance:1 props:2 active:true'), findsOneWidget);
    oldAction();
    expect(first, 0);
    expect(latest, 1);
    expect(_created, 1);
    expect(CCRouter.activeRouteEntries, isEmpty);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: _fragment(key: const ValueKey('b')),
      ),
    );
    expect(_created, 2);
    expect(_disposed, 1);
    oldAction();
    expect(latest, 1);
    await tester.pumpWidget(const SizedBox());
    expect(_disposed, 2);
  });

  testWidgets(
    'two instances remain independent and inactive KeepAlive suppresses actions',
    (tester) async {
      CCRouterHost.initialize(hostAssembly: _assembly());
      var count = 0;
      Widget tree(int index) => Directionality(
        textDirection: TextDirection.ltr,
        child: IndexedStack(
          index: index,
          children: [
            _fragment(
              key: const ValueKey(1),
              active: index == 0,
              onAction: (_) => count++,
            ),
            _fragment(id: 2, key: const ValueKey(2), active: index == 1),
          ],
        ),
      );
      await tester.pumpWidget(tree(0));
      final firstAction = _actions.first;
      await tester.pumpWidget(tree(1));
      firstAction();
      expect(count, 0);
      expect(_created, 2);
      expect(_disposed, 0);
      await tester.pumpWidget(tree(0));
      firstAction();
      expect(count, 1);
      await tester.pumpWidget(const SizedBox());
      expect(_disposed, 2);
    },
  );

  testWidgets('GlobalKey reparenting does not terminate State', (tester) async {
    CCRouterHost.initialize(hostAssembly: _assembly());
    final key = GlobalKey();
    Widget tree(bool right) => Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        children: [
          Expanded(child: right ? const SizedBox() : _fragment(key: key)),
          Expanded(child: right ? _fragment(key: key) : const SizedBox()),
        ],
      ),
    );
    await tester.pumpWidget(tree(false));
    await tester.pumpWidget(tree(true));
    expect(_created, 1);
    expect(_disposed, 0);
    await tester.pumpWidget(const SizedBox());
    expect(_disposed, 1);
  });

  testWidgets(
    'shutdown invalidates late Actions; reinitialize requires explicit remount',
    (tester) async {
      CCRouterHost.initialize(hostAssembly: _assembly());
      var count = 0;
      await tester.pumpWidget(_fragment(onAction: (_) => count++));
      final oldAction = _actions.last;
      await CCRouterHost.shutdown();
      oldAction();
      expect(count, 0);
      CCRouterHost.initialize(hostAssembly: _assembly());
      await tester.pumpWidget(_fragment(onAction: (_) => count++));
      expect(tester.takeException(), _code('runtimeGenerationMismatch'));
      await tester.pumpWidget(
        _fragment(key: const ValueKey('new'), onAction: (_) => count++),
      );
      _actions.last();
      oldAction();
      expect(count, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'DTO payload uses latest instance callback and is invalid after unmount or shutdown',
    (tester) async {
      CCHostAssembly assembly() => _assembly(
        contributions: [
          const CCUIRenderer<_Props, _Selection>(
            contract: _contract,
            renderer: _payloadRenderer,
          ),
        ],
      );
      final first = <String>[];
      final latest = <String>[];
      final second = <String>[];
      Widget tree({bool active = true, bool update = false, int session = 0}) =>
          Row(
            textDirection: TextDirection.ltr,
            children: [
              CCUIGeneratedFragment<_Props, _Selection>(
                key: ValueKey('first-$session'),
                props: const _Props(1),
                requirement: _requirement,
                active: active,
                onAction: (value) => (update ? latest : first).add(value.id),
              ),
              CCUIGeneratedFragment<_Props, _Selection>(
                key: ValueKey('second-$session'),
                props: const _Props(2),
                requirement: _requirement,
                onAction: (value) => second.add(value.id),
              ),
            ],
          );
      _payloadCallbacks.clear();
      CCRouterHost.initialize(hostAssembly: assembly());
      await tester.pumpWidget(tree());
      final emitFirst = _payloadCallbacks[0];
      final emitSecond = _payloadCallbacks[1];
      emitFirst(const _Selection('private-first'));
      emitSecond(const _Selection('private-second'));
      expect(first, ['private-first']);
      expect(second, ['private-second']);
      await tester.pumpWidget(tree(update: true));
      emitFirst(const _Selection('latest'));
      expect(latest, ['latest']);
      await tester.pumpWidget(tree(active: false, update: true));
      emitFirst(const _Selection('hidden'));
      expect(latest, ['latest']);
      await tester.pumpWidget(tree(update: true));
      emitFirst(const _Selection('resumed'));
      expect(latest, ['latest', 'resumed']);
      await tester.pumpWidget(tree(update: true, session: 1));
      emitFirst(const _Selection('old-session'));
      expect(latest, hasLength(2));
      final current = _payloadCallbacks.last;
      await CCRouterHost.shutdown();
      current(const _Selection('shutdown'));
      expect(second, ['private-second']);
      CCRouterHost.initialize(hostAssembly: assembly());
      current(const _Selection('old-generation'));
      await tester.pumpWidget(tree(session: 2));
      _payloadCallbacks.last(const _Selection('new-generation'));
      expect(second, ['private-second', 'new-generation']);
      await tester.pumpWidget(const SizedBox());
      current(const _Selection('disposed'));
      expect(second, hasLength(2));
      expect(tester.takeException(), isNull);
      _payloadCallbacks.clear();
    },
  );

  testWidgets(
    'forged Client edge and generic signature fail before rendering',
    (tester) async {
      CCRouterHost.initialize(hostAssembly: _assembly());
      await tester.pumpWidget(
        _fragment(
          requirement: const CCUIFragmentRequirement(
            consumer: 'orders',
            contract: _contract,
            versionRange: '^1.0.0',
          ),
        ),
      );
      expect(tester.takeException(), _code('dependencyMissing'));
      await tester.pumpWidget(
        CCUIGeneratedFragment<String, _Action>(
          key: const ValueKey('mismatch'),
          requirement: _requirement,
          props: 'wrong',
          onAction: (_) {},
        ),
      );
      expect(tester.takeException(), _code('rendererSignatureMismatch'));
      expect(_created, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
