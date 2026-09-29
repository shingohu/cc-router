@TestOn('vm')
library;

import 'dart:convert';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:ccrouter_generator/builder.dart';
import 'package:test/test.dart';

void main() {
  late TestReaderWriter reader;

  setUp(() async {
    reader = TestReaderWriter(
      rootPackage: 'ccrouter_test',
      flattenOutput: true,
    );
    await reader.testing.loadIsolateSources();
  });

  test('task builder emits complete typed registration', () async {
    final output = await _generate(
      reader,
      ccInitTaskBuilder(BuilderOptions.empty),
      r'''
const foundationTask = CCInitTaskContract(id: 'startup.foundation');
const analyticsTask = CCInitTaskContract(id: 'startup.analytics');

@CCInitTask(
  contract: analyticsTask,
  dependsOn: [foundationTask],
  gate: CCInitTaskGate.privacyGranted,
  failurePolicy: CCInitTaskFailurePolicy.optional,
  timeout: Duration(seconds: 3),
)
Future<void> initializeAnalytics(CCInvocationContext context) async {}
''',
      'lib/src/ccrouter_generated/init_task/probe.init_task.g.dart',
    );

    expect(output, contains('id: "startup.analytics"'));
    expect(output, contains('"startup.foundation"'));
    expect(output, contains('CCInitTaskGate("privacyGranted")'));
    expect(output, contains('CCInitTaskFailurePolicy.optional'));
    expect(output, contains('Duration(microseconds: 3000000)'));
    expect(output, contains('init_source.initializeAnalytics'));
  });

  test('zero-argument internal task is adapted to Runtime signature', () async {
    final output = await _generate(
      reader,
      ccInitTaskBuilder(BuilderOptions.empty),
      r'''
@CCInitTask(id: 'startup.cache')
void warmCache() {}
''',
      'lib/src/ccrouter_generated/init_task/probe.init_task.g.dart',
    );

    expect(output, contains('(_) => init_source.warmCache()'));
  });

  test('FutureOr Handler may receive invocation context', () async {
    final output = await _generate(
      reader,
      ccInitTaskBuilder(BuilderOptions.empty),
      r'''
import 'dart:async';

@CCInitTask(id: 'startup.context')
FutureOr<void> initializeWithContext(CCInvocationContext context) {}
''',
      'lib/src/ccrouter_generated/init_task/probe.init_task.g.dart',
    );

    expect(output, contains('run: init_source.initializeWithContext'));
  });

  test('metadata records Contract DAG and source locations', () async {
    final output = await _generate(
      reader,
      ccInitTaskMetadataBuilder(BuilderOptions.empty),
      r'''
const foundationTask = CCInitTaskContract(
  id: 'startup.foundation',
  description: 'Prepare shared startup state.',
);

@CCInitTask(contract: foundationTask)
Future<void> initializeFoundation() async {}
''',
      'lib/src/ccrouter_generated/metadata/src/probe.init_task.json',
    );
    final metadata = jsonDecode(output) as Map<String, dynamic>;
    expect(metadata['initTaskContracts'], hasLength(1));
    expect(metadata['initTasks'], hasLength(1));
    expect(metadata['initTaskContracts'][0]['version'], '0.1.0');
    expect(
      metadata['initTaskContracts'][0]['shapeFingerprint'],
      matches(RegExp(r'^[0-9a-f]{64}$')),
    );
    expect(
      metadata['initTaskContracts'][0]['declaration']['symbol'],
      'foundationTask',
    );
    expect(metadata['initTasks'][0]['gateId'], 'appStarted');
  });

  test('contract and id cannot be configured together', () async {
    final logs = await _generate(
      reader,
      ccInitTaskMetadataBuilder(BuilderOptions.empty),
      r'''
const foundationTask = CCInitTaskContract(id: 'startup.foundation');
@CCInitTask(contract: foundationTask, id: 'startup.other')
void initializeFoundation() {}
''',
      'lib/src/ccrouter_generated/metadata/src/probe.init_task.json',
      fails: true,
    );
    expect(logs, contains('exactly one of contract and id'));
  });

  test('invalid Handler signature fails generation', () async {
    final logs = await _generate(
      reader,
      ccInitTaskBuilder(BuilderOptions.empty),
      r'''
@CCInitTask(id: 'startup.invalid')
int initializeInvalid() => 1;
''',
      'lib/src/ccrouter_generated/init_task/probe.init_task.g.dart',
      fails: true,
    );
    expect(logs, contains('must return void'));
  });

  test('private Handler fails generation', () async {
    final logs = await _generate(
      reader,
      ccInitTaskBuilder(BuilderOptions.empty),
      r'''
@CCInitTask(id: 'startup.private')
void _initializePrivate() {}
''',
      'lib/src/ccrouter_generated/init_task/probe.init_task.g.dart',
      fails: true,
    );
    expect(logs, contains('public, top-level, non-generic'));
  });

  test('incorrectly parameterized Handler fails generation', () async {
    final logs = await _generate(
      reader,
      ccInitTaskBuilder(BuilderOptions.empty),
      r'''
@CCInitTask(id: 'startup.parameter')
void initializeWithWrongParameter(String value) {}
''',
      'lib/src/ccrouter_generated/init_task/probe.init_task.g.dart',
      fails: true,
    );
    expect(logs, contains('parameter must be CCInvocationContext'));
  });

  test('invalid Gate fails generation', () async {
    final logs = await _generate(
      reader,
      ccInitTaskBuilder(BuilderOptions.empty),
      r'''
@CCInitTask(
  id: 'startup.invalid_gate',
  gate: CCInitTaskGate('Invalid gate'),
)
void initializeInvalidGate() {}
''',
      'lib/src/ccrouter_generated/init_task/probe.init_task.g.dart',
      fails: true,
    );
    expect(logs, contains('Initialization Gate ID'));
  });

  test('non-positive timeout fails generation', () async {
    final logs = await _generate(
      reader,
      ccInitTaskBuilder(BuilderOptions.empty),
      r'''
@CCInitTask(id: 'startup.timeout', timeout: Duration.zero)
void initializeInvalidTimeout() {}
''',
      'lib/src/ccrouter_generated/init_task/probe.init_task.g.dart',
      fails: true,
    );
    expect(logs, contains('timeout must be positive'));
  });

  test('duplicate and self dependencies fail generation', () async {
    final logs = await _generate(
      reader,
      ccInitTaskMetadataBuilder(BuilderOptions.empty),
      r'''
const foundationTask = CCInitTaskContract(id: 'startup.foundation');
@CCInitTask(contract: foundationTask, dependsOn: [foundationTask])
void initializeFoundation() {}
''',
      'lib/src/ccrouter_generated/metadata/src/probe.init_task.json',
      fails: true,
    );
    expect(logs, contains('duplicate or self dependency'));
  });

  test('dependency list rejects inline Contract construction', () async {
    final logs = await _generate(
      reader,
      ccInitTaskMetadataBuilder(BuilderOptions.empty),
      r'''
@CCInitTask(
  id: 'startup.analytics',
  dependsOn: [CCInitTaskContract(id: 'startup.foundation')],
)
void initializeAnalytics() {}
''',
      'lib/src/ccrouter_generated/metadata/src/probe.init_task.json',
      fails: true,
    );
    expect(logs, contains('constant references'));
  });
}

Future<String> _generate(
  TestReaderWriter reader,
  Builder builder,
  String declarations,
  String outputPath, {
  bool fails = false,
}) async {
  final logs = <String>[];
  const sourcePath = 'lib/src/probe.dart';
  await testBuilder(
    builder,
    {
      'ccrouter_test|$sourcePath':
          "import 'package:ccrouter/ccrouter.dart';\n$declarations",
    },
    rootPackage: 'ccrouter_test',
    generateFor: {'ccrouter_test|$sourcePath'},
    isInput: (id) => id == 'ccrouter_test|$sourcePath',
    readerWriter: reader,
    flattenOutput: true,
    onLog: (record) => logs.add(record.message),
  );
  final output = AssetId('ccrouter_test', outputPath);
  if (fails) {
    expect(await reader.canRead(output), isFalse);
    return logs.join('\n');
  }
  return reader.readAsString(output);
}
