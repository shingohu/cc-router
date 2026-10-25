// Invoked explicitly by the timeout regression; its first test must fail.
import 'dart:async';

import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:ccrouter_test/ccrouter_ui_test.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('body times out', (tester) async {
    final host = CCUIFragmentTestHost(
      hostAssembly: CCHostAssembly.fromComponents(components: const []),
    );
    addTearDown(host.dispose);
    await host.run(() async {
      await tester.pumpWidget(const SizedBox());
      await Completer<void>().future;
    }, unmount: () => tester.pumpWidget(const SizedBox()));
  }, timeout: const Timeout(Duration(milliseconds: 300)));

  testWidgets('next Widget test gets a clean Host', (tester) async {
    expect(CCRouter.isInitialized, isFalse);
    final host = CCUIFragmentTestHost(
      hostAssembly: CCHostAssembly.fromComponents(components: const []),
    );
    addTearDown(host.dispose);
    await host.run(() async {
      await tester.pumpWidget(const SizedBox());
      expect(CCRouter.isInitialized, isTrue);
    }, unmount: () => tester.pumpWidget(const SizedBox()));
    expect(CCRouter.isInitialized, isFalse);
  });
}
