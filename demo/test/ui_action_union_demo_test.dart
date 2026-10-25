import 'package:ccrouter_demo/ccrouter_demo.dart';
import 'package:ccrouter_test/ccrouter_ui_test.dart';
import 'package:demo_order_contracts/demo_order_contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../modules/navigation_lab/test/support/order_panel_fixture.dart';

String _label(OrderPanelAction action) => switch (action) {
  OrderPanelSettingsRequested() => 'settings',
  OrderPanelTargetSelected(:final target) => switch (target) {
    OrderPanelUser(:final id) => 'user:$id',
    OrderPanelScore(:final id) => 'score:$id',
    OrderPanelVideo(:final id) => 'video:$id',
    OrderPanelArtist(:final id) => 'artist:$id',
  },
};

void main() {
  testWidgets(
    'generated cross-Package union Actions keep exact nested payloads',
    (tester) async {
      final host = CCUIFragmentTestHost(
        hostAssembly: ccrouterGeneratedHostAssembly,
      );
      addTearDown(host.dispose);
      final first = <OrderPanelAction>[];
      final latest = <OrderPanelAction>[];
      await host.run(() async {
        await tester.pumpWidget(createOrderPanelFixture(onAction: first.add));
        for (final label in ['打开设置', '选择用户', '选择曲谱', '选择作品', '选择艺术家']) {
          await tester.tap(find.text(label));
        }
        expect(first.map(_label), [
          'settings',
          'user:demo-user',
          'score:demo-score',
          'video:demo-video',
          'artist:demo-artist',
        ]);
        final retained = tester
            .widget<TextButton>(find.widgetWithText(TextButton, '打开设置'))
            .onPressed!;
        await tester.pumpWidget(createOrderPanelFixture(onAction: latest.add));
        retained();
        expect(latest.map(_label), ['settings']);
        await tester.pumpWidget(
          createOrderPanelFixture(onAction: latest.add, active: false),
        );
        retained();
        expect(latest, hasLength(1));
        await tester.pumpWidget(const SizedBox());
        retained();
        expect(latest, hasLength(1));
        expect(tester.takeException(), isNull);
      }, unmount: () => tester.pumpWidget(const SizedBox()));
    },
  );
}
