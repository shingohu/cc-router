import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:flutter_test/flutter_test.dart';

/// Drives the initialized Demo Host's startup on the Widget test's fake clock.
///
/// Create the Runtime inside `testWidgets`, before calling this helper. A real
/// `setUp` Zone would give Host-owned work a scheduler that `pump` cannot drive.
Future<void> pumpDemoStartup(WidgetTester tester) async {
  var finished = false;
  final startup = CCRouterHost.runInitTasks(
    gate: CCInitTaskGate.appStarted,
  ).whenComplete(() => finished = true);
  for (var tick = 0; !finished && tick < 100; tick++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(finished, isTrue, reason: 'Demo startup did not settle in fake time');
  await startup;
}
