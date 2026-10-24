import 'package:flutter_test/flutter_test.dart';

import 'review_repros/session_and_resume/repro.dart' as review;

// Discover the original review contracts in the normal framework suite.
void main() {
  group('Session ownership and resumed navigation', review.main);
}
