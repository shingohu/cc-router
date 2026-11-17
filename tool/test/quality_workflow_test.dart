import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('all Quality Flutter jobs match the repository FVM pin', () {
    final pin = jsonDecode(File('.fvmrc').readAsStringSync())['flutter'];
    final workflow = File('.github/workflows/quality.yml').readAsStringSync();
    final versions = RegExp(
      r'^\s+flutter-version: (\S+)',
      multiLine: true,
    ).allMatches(workflow).map((match) => match.group(1));

    expect(versions, isNotEmpty);
    expect(
      versions,
      everyElement(pin),
      reason: 'CI installs Flutter directly and does not run through FVM.',
    );
  });

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
