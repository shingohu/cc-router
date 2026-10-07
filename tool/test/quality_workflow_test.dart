import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('workflow-level environment uses only workflow-available values', () {
    final workflow = File('.github/workflows/quality.yml').readAsStringSync();
    final workflowConfiguration = workflow.split('\njobs:').first;

    expect(
      workflowConfiguration,
      isNot(contains(r'${{ runner.')),
      reason: 'The runner context is available only within jobs and steps.',
    );
    expect(
      workflowConfiguration,
      contains('CCROUTER_HOME: /tmp/ccrouter-home'),
      reason: 'All Quality jobs run on isolated Ubuntu runners.',
    );
  });
}
