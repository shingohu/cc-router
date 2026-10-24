import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:ccrouter_ui/ccrouter_ui.dart';
import 'package:ccrouter_ui/ccrouter_ui_generated.dart';
import 'package:ccrouter_ui/ccrouter_ui_host.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leak_tracker/leak_tracker.dart' show forceGC;

final class Props {
  Props(this.id);
  final int id;
}

enum Action { select }

final class CallbackOwner {
  int calls = 0;
  void onAction(Action _) => calls++;
}

final class Registrar implements CCComponentRegistrar {
  @override
  void register(CCRegistry registry) {}
}

const contract = CCUIFragmentDescriptor(
  owner: 'owner',
  id: 'owner.card',
  version: '1.0.0',
  fingerprint:
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
);
const requirement = CCUIFragmentRequirement(
  consumer: 'consumer',
  contract: contract,
  versionRange: '^1.0.0',
);
const otherContract = CCUIFragmentDescriptor(
  owner: 'owner',
  id: 'owner.other',
  version: '1.0.0',
  fingerprint:
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
);
const otherRequirement = CCUIFragmentRequirement(
  consumer: 'consumer',
  contract: otherContract,
  versionRange: '^1.0.0',
);

ValueChanged<Action>? captured;

Widget renderer(CCUIFragmentRenderInput<Props, Action> input) {
  captured = input.onAction;
  return const SizedBox();
}

CCHostAssembly assembly({
  String versionRange = '^1.0.0',
  bool includeSecond = false,
}) => CCUIHostAssembly.attach(
  CCHostAssembly.fromComponents(
    components: [
      CCComponentManifest(
        id: 'owner',
        version: '1.0.0',
        registrar: Registrar(),
      ),
      CCComponentManifest(
        id: 'consumer',
        version: '1.0.0',
        dependencies: const ['owner'],
        registrar: Registrar(),
      ),
    ],
  ),
  contributions: [
    const CCUIRenderer<Props, Action>(contract: contract, renderer: renderer),
    if (includeSecond)
      const CCUIRenderer<Props, Action>(
        contract: otherContract,
        renderer: renderer,
      ),
  ],
  requirements: [
    CCUIFragmentRequirement(
      consumer: requirement.consumer,
      contract: requirement.contract,
      versionRange: versionRange,
    ),
    if (includeSecond) otherRequirement,
  ],
);

typedef Probe = ({
  WeakReference<Props> props,
  WeakReference<CallbackOwner> callbackOwner,
  WeakReference<State> state,
  ValueChanged<Action>? emit,
});

Future<Probe> mountAndUnmount(WidgetTester tester, bool retainAction) async {
  final props = Props(1);
  final owner = CallbackOwner();
  await tester.pumpWidget(
    CCUIGeneratedFragment<Props, Action>(
      requirement: requirement,
      props: props,
      onAction: owner.onAction,
    ),
  );
  final state = WeakReference<State>(
    tester.state(find.byType(CCUIGeneratedFragment<Props, Action>)),
  );
  final emit = retainAction ? captured : null;
  captured = null;
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
  emit?.call(Action.select);
  expect(owner.calls, 0, reason: 'Unmounted Action must remain inert');
  return (
    props: WeakReference(props),
    callbackOwner: WeakReference(owner),
    state: state,
    emit: emit,
  );
}

void main() {
  tearDown(() async {
    captured = null;
    await CCRouterHost.shutdown();
  });
  for (final retainAction in [false, true]) {
    testWidgets('unmounted Fragment releases inputs: '
        'retain inert framework Action=$retainAction', (tester) async {
      CCRouterHost.initialize(hostAssembly: assembly());
      final probe = await mountAndUnmount(tester, retainAction);
      await tester.runAsync(
        () => forceGC(fullGcCycles: 4, timeout: const Duration(seconds: 20)),
      );
      expect(
        {
          'propsRetained': probe.props.target != null,
          'callbackOwnerRetained': probe.callbackOwner.target != null,
          'stateRetained': probe.state.target != null,
        },
        {
          'propsRetained': false,
          'callbackOwnerRetained': false,
          'stateRetained': false,
        },
      );
      // Keep the inert sink alive through the GC observation itself.
      probe.emit?.call(Action.select);
      expect(tester.takeException(), isNull);
    });
  }
}
