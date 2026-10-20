import 'package:ccrouter_generator/src/ui_fragment_workspace.dart';
import 'package:test/test.dart';

void main() {
  Map<String, Object?> reference(String symbol) => {
    'packageUri': 'package:sample/ui.dart',
    'symbol': symbol,
    'line': 3,
    'column': 7,
  };
  Map<String, Object?> contract() => {
    'componentId': 'orders',
    'id': 'orders.card',
    'version': '1.0.0',
    'shapeFingerprint': 'shape',
    'declaration': reference('Card'),
  };
  List<Map<String, Object?>> documents() => [
    {
      'package': 'contracts',
      'uiSchemaVersion': 1,
      'uiContracts': [contract()],
    },
    {
      'package': 'orders',
      'components': [
        {'id': 'orders', 'dependencies': <String>[]},
      ],
      'uiRenderers': [
        {...contract(), 'implementation': reference('render')},
      ],
    },
    {
      'package': 'consumer',
      'components': [
        {
          'id': 'consumer',
          'dependencies': ['orders'],
        },
      ],
      'uiRequirements': [
        {
          ...contract(),
          'consumer': 'consumer',
          'versionRange': '^1.0.0',
          'consumerDeclaration': reference('component'),
        },
      ],
    },
  ];
  test('valid UI workspace emits no diagnostics', () {
    expect(
      validateUIFragmentWorkspaceDiagnostics(documents(), host: true),
      isEmpty,
    );
  });
  final cases = <String, void Function(List<Map<String, Object?>>)>{
    'contract_duplicate': (docs) =>
        (docs[0]['uiContracts'] as List).add(contract()),
    'owner_mismatch': (docs) =>
        (docs[1]['components'] as List).single['id'] = 'foreign',
    'implementation_duplicate': (docs) => (docs[1]['uiRenderers'] as List).add({
      ...contract(),
      'implementation': reference('other'),
    }),
    'dependency_missing': (docs) =>
        (docs[2]['components'] as List).single['dependencies'] = <String>[],
    'stale_generated_output': (docs) =>
        (docs[2]['uiRequirements'] as List).single['version'] = '1.1.0',
    'missing_implementation': (docs) => docs[1]['uiRenderers'] = <Object?>[],
    'fingerprint_changed': (docs) =>
        (docs[2]['uiRequirements'] as List).single['shapeFingerprint'] =
            'new-shape',
    'version_out_of_range': (docs) =>
        (docs[2]['uiRequirements'] as List).single['versionRange'] = '^2.0.0',
  };
  for (final entry in cases.entries) {
    test(
      'structured UI ${entry.key} has an authored location and correction',
      () {
        final docs = documents();
        entry.value(docs);
        final diagnostics = validateUIFragmentWorkspaceDiagnostics(
          docs,
          host: true,
        );
        final issue = diagnostics.firstWhere(
          (d) => d.code == 'ccrouter_ui_${entry.key}',
        );
        expect(issue.primaryLocation?.uri, 'package:sample/ui.dart');
        expect(issue.primaryLocation?.line, 3);
        expect(issue.correction, isNotEmpty);
        expect(issue.toJson()['code'], issue.code);
        expect(
          validateUIFragmentWorkspace(docs, host: true),
          contains(issue.message),
        );
      },
    );
  }
  test('invalid portable source positions never become IDE diagnostics', () {
    for (final uri in [
      'file:///local/source.dart',
      'package:sample/../outside.dart',
      'invalid',
    ]) {
      final docs = documents();
      docs[1]['uiRenderers'] = <Object?>[];
      (docs[2]['uiRequirements'] as List).single['consumerDeclaration'] = {
        ...reference('component'),
        'packageUri': uri,
      };
      expect(
        validateUIFragmentWorkspaceDiagnostics(
          docs,
          host: true,
        ).single.primaryLocation,
        isNull,
      );
    }
  });
}
