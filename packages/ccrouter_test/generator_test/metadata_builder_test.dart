@TestOn('vm')
library;

import 'dart:convert';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:ccrouter_generator/builder.dart';
import 'package:test/test.dart';

void main() {
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

@CCInitTask(contract: mixedInitTask)
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
    }
  });
}
