@TestOn('vm')
@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:ccrouter_generator/builder.dart';
import 'package:ccrouter_generator/src/package_workspace.dart';
import 'package:test/test.dart';

void main() {
  for (final kind in ['Service', 'Command']) {
    test(
      '$kind part metadata retains source location and defining Library',
      () async {
        final reader = TestReaderWriter(
          rootPackage: 'ccrouter_test',
          flattenOutput: true,
        );
        await reader.testing.loadIsolateSources();
        await testBuilder(
          kind == 'Service'
              ? ccServiceMetadataBuilder(BuilderOptions.empty)
              : ccCommandMetadataBuilder(BuilderOptions.empty),
          {
            'ccrouter_test|lib/src/root.dart':
                "import 'package:ccrouter_contracts/ccrouter_contracts.dart';\npart 'contract_part.dart';",
            'ccrouter_test|lib/src/contract_part.dart':
                '''
part of 'root.dart';
@CC${kind}Contract(componentId: CCComponentId('owner'), id: 'owner.shared')
${kind == 'Service' ? 'abstract interface class Shared {}' : 'final class Shared implements CCCommand<void> { const Shared(); }'}
''',
          },
          rootPackage: 'ccrouter_test',
          generateFor: {'ccrouter_test|lib/src/root.dart'},
          isInput: (id) => id == AssetId('ccrouter_test', 'lib/src/root.dart'),
          readerWriter: reader,
          flattenOutput: true,
        );
        final document =
            jsonDecode(
                  await reader.readAsString(
                    AssetId(
                      'ccrouter_test',
                      'lib/src/ccrouter_generated/metadata/src/root.${kind.toLowerCase()}.json',
                    ),
                  ),
                )
                as Map;
        final declaration =
            (document['${kind.toLowerCase()}Contracts'] as List)
                    .single['declaration']
                as Map;
        expect(
          declaration['packageUri'],
          'package:ccrouter_test/src/contract_part.dart',
        );
        expect(
          declaration['libraryUri'],
          'package:ccrouter_test/src/root.dart',
        );
        expect(declaration['line'], 3);
        final catalog = CCCapabilitySourceCatalog.fromMetadata([
          document.cast<String, Object?>(),
        ]);
        final decoded = CCCapabilitySourceCatalog.fromJson(catalog.toJson());
        expect(
          decoded.records.single.contract!.toJson()['libraryUri'],
          'package:ccrouter_test/src/root.dart',
        );
      },
    );
  }
}
