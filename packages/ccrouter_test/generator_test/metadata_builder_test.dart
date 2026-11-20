@TestOn('vm')
library;

import 'dart:convert';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:ccrouter_generator/builder.dart';
import 'package:test/test.dart';

void main() {
  for (final kind in ['Service', 'Command']) {
    test('component metadata rejects duplicate $kind Contracts', () async {
      final reader = TestReaderWriter(
        rootPackage: 'ccrouter_test',
        flattenOutput: true,
      );
      await reader.testing.loadIsolateSources();
      const input = 'lib/src/consumer.dart';
      final logs = <String>[];
      await testBuilder(
        ccComponentMetadataBuilder(BuilderOptions.empty),
        {
          'ccrouter_test|$input':
              '''
import 'package:ccrouter/ccrouter.dart';
import 'shared.dart';
const consumer = CCComponent(
  id: CCComponentId('consumer'), version: '1.0.0',
  dependencies: [CCComponentId('owner')],
  ${kind.toLowerCase()}Dependencies: [CC${kind}Dependency<Shared>()],
);
''',
          'ccrouter_test|lib/src/shared.dart':
              '''
import 'package:ccrouter/ccrouter.dart';
@CC${kind}Contract(componentId: CCComponentId('owner'), id: 'owner.first', alias: 'first')
@CC${kind}Contract(componentId: CCComponentId('owner'), id: 'owner.second', alias: 'second')
${kind == 'Service' ? 'abstract interface class Shared {}' : 'final class Shared implements CCCommand<void> { const Shared(); }'}
''',
        },
        rootPackage: 'ccrouter_test',
        generateFor: {'ccrouter_test|$input'},
        isInput: (id) => id == AssetId('ccrouter_test', input),
        readerWriter: reader,
        flattenOutput: true,
        onLog: (record) => logs.add(record.message),
      );
      expect(
        await reader.canRead(
          AssetId(
            'ccrouter_test',
            'lib/src/ccrouter_generated/metadata/src/consumer.component.json',
          ),
        ),
        isFalse,
      );
      expect(logs.join('\n'), contains('exactly one CC${kind}Contract'));
    });
  }

  test('metadata builders preserve all mixed capability documents', () async {
    final reader = TestReaderWriter(
      rootPackage: 'ccrouter_test',
      flattenOutput: true,
    );
    await reader.testing.loadIsolateSources();
    const input = 'lib/src/mixed_capabilities.dart';
    const sources = {
      'ccrouter_test|$input': '''
import 'package:ccrouter/ccrouter.dart';

const mixedComponentId = CCComponentId('mixed_component');
const mixedComponent = CCComponent(
  id: mixedComponentId,
  version: '1.0.0',
);

@CCRoute<void>(
  id: 'mixed.route',
  pattern: CCPathPattern('/mixed/:id'),
  description: 'Mixed metadata Route.',
)
final class MixedPage {
  const MixedPage({required this.id});
  final int id;
}

@CCService(id: 'mixed.service')
final class MixedService {
  MixedService();
}

@CCCommandContract(id: 'mixed.command', description: 'Mixed Command.')
final class MixedCommand implements CCCommand<int> {
  const MixedCommand();
}

@CCCommandHandler()
int handleMixedCommand(MixedCommand command) => 1;

@CCEventContract(id: 'mixed.event', description: 'Mixed Event.')
final class MixedEvent implements CCEvent {
  const MixedEvent();
}

@CCEventSubscription()
void observeMixedEvent(MixedEvent event) {}

const mixedInitTask = CCInitTaskContract(
  id: 'mixed.init',
  description: 'Mixed InitTask.',
);

@CCInitTask(
  contract: mixedInitTask,
  gate: CCInitTaskGate.appStarted,
  failurePolicy: CCInitTaskFailurePolicy.optional,
)
void initializeMixed() {}
''',
    };
    for (final builder in <Builder>[
      ccComponentMetadataBuilder(BuilderOptions.empty),
      ccRouteMetadataBuilder(BuilderOptions.empty),
      ccServiceMetadataBuilder(BuilderOptions.empty),
      ccCommandMetadataBuilder(BuilderOptions.empty),
      ccEventMetadataBuilder(BuilderOptions.empty),
      ccInitTaskMetadataBuilder(BuilderOptions.empty),
    ]) {
      await testBuilder(
        builder,
        sources,
        rootPackage: 'ccrouter_test',
        generateFor: {'ccrouter_test|$input'},
        isInput: (id) => id == AssetId('ccrouter_test', input),
        readerWriter: reader,
        flattenOutput: true,
      );
    }

    final expectations = <String, String>{
      'component': 'components',
      'route': 'routes',
      'service': 'serviceImplementations',
      'command': 'commandContracts',
      'event': 'eventContracts',
      'init_task': 'initTasks',
    };
    for (final entry in expectations.entries) {
      final output = AssetId(
        'ccrouter_test',
        'lib/src/ccrouter_generated/metadata/src/'
            'mixed_capabilities.${entry.key}.json',
      );
      expect(await reader.canRead(output), isTrue, reason: entry.key);
      final document =
          jsonDecode(await reader.readAsString(output)) as Map<String, Object?>;
      expect(document[entry.value], isNotEmpty, reason: entry.key);
      if (entry.key == 'route') {
        final route = (document['routes'] as List).single as Map;
        expect(route['version'], '0.1.0');
        expect(route['shapeFingerprint'], matches(RegExp(r'^[0-9a-f]{64}$')));
      }
    }
  });
}
