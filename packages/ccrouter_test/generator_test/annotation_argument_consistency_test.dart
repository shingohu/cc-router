@TestOn('vm')
@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:ccrouter_generator/builder.dart';
import 'package:test/test.dart';

void main() {
  final cases =
      (jsonDecode(
                File(
                  'packages/ccrouter_test/fixtures/annotation_argument_cases.json',
                ).readAsStringSync(),
              )
              as List)
          .cast<Map<String, dynamic>>();
  for (final entry in cases) {
    for (final metadata in [true, false]) {
      test(
        'Generator ${metadata ? 'metadata' : 'source'} argument semantics: ${entry['name']}',
        () async {
          final reader = TestReaderWriter(
            rootPackage: 'ccrouter_test',
            flattenOutput: true,
          );
          await reader.testing.loadIsolateSources();
          final route = entry['kind'] != 'task';
          final declaration = switch (entry['kind']) {
            'routeContract' =>
              "@CCRouteContract<void>(componentId: CCComponentId('owner'), id: 'probe.route', ${entry['arguments']})\nabstract class ProbeRouteContract { const ProbeRouteContract(); }",
            'route' =>
              "@CCRoute<void>(id: 'probe.route', ${entry['arguments']})\nfinal class Probe { const Probe(); }",
            _ =>
              "@CCInitTask(${entry['arguments']}, gate: CCInitTaskGate.appStarted, failurePolicy: CCInitTaskFailurePolicy.optional)\nvoid initialize() {}",
          };
          final builder = metadata
              ? route
                    ? ccRouteMetadataBuilder(BuilderOptions.empty)
                    : ccInitTaskMetadataBuilder(BuilderOptions.empty)
              : entry['kind'] == 'routeContract'
              ? ccRouteContractBuilder(BuilderOptions.empty)
              : route
              ? ccRouteBuilder(BuilderOptions.empty)
              : ccInitTaskBuilder(BuilderOptions.empty);
          final output = metadata
              ? 'metadata/src/probe.${route ? 'route' : 'init_task'}.json'
              : entry['kind'] == 'routeContract'
              ? 'contract/probe.route.contract.g.dart'
              : route
              ? 'route/probe.route.g.dart'
              : 'init_task/probe.init_task.g.dart';
          final source =
              '''
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
const CCRoutePattern? absentPattern = null;
const CCInitTaskContract? absentTask = null;
const String? absentId = null;
const sharedTask = CCInitTaskContract(id: 'probe.shared');
$declaration
''';
          final logs = <String>[];
          await testBuilder(
            builder,
            {'ccrouter_test|lib/src/probe.dart': source},
            rootPackage: 'ccrouter_test',
            generateFor: {'ccrouter_test|lib/src/probe.dart'},
            isInput: (id) =>
                id == AssetId('ccrouter_test', 'lib/src/probe.dart'),
            readerWriter: reader,
            flattenOutput: true,
            onLog: (entry) => logs.add(entry.message),
          );
          expect(
            await reader.canRead(
              AssetId('ccrouter_test', 'lib/src/ccrouter_generated/$output'),
            ),
            !entry['conflict'],
            reason: logs.join('\n'),
          );
        },
      );
    }
  }
}
