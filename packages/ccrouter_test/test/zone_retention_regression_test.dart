import 'package:flutter_test/flutter_test.dart';

import 'review_repros/runtime_round_trip/construction_retention.dart' as memory;
import 'review_repros/runtime_round_trip/test_host_disposal.dart' as cleanup;

void main() {
  group('Zone lifetime', memory.main);
  group('TestHost cleanup barrier', cleanup.main);
}
