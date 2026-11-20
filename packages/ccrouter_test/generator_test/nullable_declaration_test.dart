@TestOn('vm')
@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:ccrouter_generator/builder.dart';
import 'package:test/test.dart';

void main() {
  for (final (builder, output) in [
    (
      ccComponentMetadataBuilder(BuilderOptions.empty),
      'metadata/src/probe.component.json',
    ),
    (
      ccServiceProxyBuilder(BuilderOptions.empty),
      'component/probe.service_api.g.dart',
    ),
  ]) {
    test('$output ignores absent nullable component constants', () async {
      final reader = TestReaderWriter(
        rootPackage: 'ccrouter_test',
        flattenOutput: true,
      );
      await reader.testing.loadIsolateSources();
      final logs = <String>[];
      await testBuilder(
        builder,
        {
          'ccrouter_test|lib/src/probe.dart': '''
import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter_test/reader.dart';
const CCComponent? absent = null;
const component = CCComponent(id: CCComponentId('consumer'), version: '1.0.0',
  dependencies: [CCComponentId('other')], serviceDependencies: [CCServiceDependency<Reader>()]);
''',
          'ccrouter_test|lib/reader.dart': '''
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
@CCServiceContract(componentId: CCComponentId('other'), id: 'other.reader')
abstract interface class Reader { String read(); }
''',
        },
        rootPackage: 'ccrouter_test',
        generateFor: {'ccrouter_test|lib/src/probe.dart'},
        isInput: (id) => id == AssetId('ccrouter_test', 'lib/src/probe.dart'),
        readerWriter: reader,
        flattenOutput: true,
        onLog: (entry) => logs.add(entry.message),
      );
      final id = AssetId('ccrouter_test', 'lib/src/ccrouter_generated/$output');
      expect(await reader.canRead(id), isTrue, reason: logs.join('\n'));
      final text = await reader.readAsString(id);
      if (output.endsWith('.json')) {
        expect((jsonDecode(text) as Map)['components'], hasLength(1));
      } else {
        expect(text, contains('ConsumerServices'));
      }
    });
  }
}
