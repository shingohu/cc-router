import 'package:flutter_test/flutter_test.dart';

import 'review_repros/pop_wait_lifecycle/initial_stack.dart' as initial;
import 'review_repros/pop_wait_lifecycle/repro.dart' as wait;

void main() {
  group('External navigation wait ownership', wait.main);
  group('Initial-stack Host registration', initial.main);
}
