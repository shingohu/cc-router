import 'package:ccrouter/ccrouter.dart';
import 'package:demo_order_contracts/demo_order_contracts.dart';

/// Prepares the Order component before dependent component tasks execute.
@CCInitTask(contract: demoOrderFoundationInitTask)
Future<void> initializeDemoOrderFoundation() async {
  await Future<void>.delayed(const Duration(milliseconds: 8));
}
