import 'package:ccrouter/ccrouter_host.dart';
import 'package:ccrouter_ui/ccrouter_ui_generated.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'review_repros/fragment_lifecycle/repro.dart' as fixture;

void main() {
  fixture.main();
  testWidgets(
    'changing capability identity revokes retained actions on reused State',
    (tester) async {
      CCRouterHost.initialize(
        hostAssembly: fixture.assembly(includeSecond: true),
      );
      var calls = 0;
      await tester.pumpWidget(
        CCUIGeneratedFragment<fixture.Props, fixture.Action>(
          key: const ValueKey('retained-state'),
          requirement: fixture.requirement,
          props: fixture.Props(1),
          onAction: (_) => calls++,
        ),
      );
      final state = tester.state(
        find.byType(CCUIGeneratedFragment<fixture.Props, fixture.Action>),
      );
      final oldEmit = fixture.captured!;
      oldEmit(fixture.Action.select);
      expect(calls, 1);
      await tester.pumpWidget(
        CCUIGeneratedFragment<fixture.Props, fixture.Action>(
          key: const ValueKey('retained-state'),
          requirement: fixture.otherRequirement,
          props: fixture.Props(2),
          onAction: (_) => calls += 10,
        ),
      );
      expect(
        tester.state(
          find.byType(CCUIGeneratedFragment<fixture.Props, fixture.Action>),
        ),
        same(state),
      );
      oldEmit(fixture.Action.select);
      expect(calls, 1);
      fixture.captured!(fixture.Action.select);
      expect(calls, 11);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
