@TestOn('vm')
library;

// ignore_for_file: implementation_imports
import 'dart:convert';
import 'dart:io';
import 'package:ccrouter_generator/src/package_workspace.dart';
import 'package:test/test.dart';

void main() {
  List<Map<String, Object?>> metadata(
    Object? documentVersion,
    Object? recordVersion,
  ) => [
    {
      'schemaVersion': 5,
      'package': 'review',
      'uiSchemaVersion': documentVersion,
      'uiContracts': [
        {
          'componentId': 'owner',
          'id': 'panel',
          'version': '1.0.0',
          'uiSchemaVersion': recordVersion,
        },
      ],
    },
  ];
  CCPackageIndex index(List<Map<String, Object?>> docs) => CCPackageIndex(
    packageName: 'review',
    packageVersion: '1.0.0',
    dependencies: const [],
    metadata: docs,
    contentFingerprint: computeCCPackageFingerprint(
      packageName: 'review',
      packageVersion: '1.0.0',
      bundleLibrary: null,
      bundleSymbol: null,
      dependencies: const [],
      metadata: docs,
    ),
  );
  test('review source and index version tags must be integers', () async {
    final root = Directory.systemTemp.createTempSync(
      'ccrouter-ui-version-review-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final package = CCResolvedPackage(
      name: 'review',
      version: '1.0.0',
      root: root,
      dependencies: const [],
      devDependencies: const [],
      writable: false,
    );
    final docs = metadata(2, 2);
    final value = index(docs);
    final encoded = jsonDecode(value.toJson()) as Map<String, dynamic>;
    encoded['schemaVersion'] = 4.0;
    package.indexFile
      ..createSync(recursive: true)
      ..writeAsStringSync(jsonEncode(encoded));
    await expectLater(
      CCPackageIndex.read(package),
      throwsA(isA<CCPackageWorkspaceException>()),
    );
    docs.single['schemaVersion'] = 5.0;
    expect(
      () => index(docs).toJson(),
      throwsA(isA<CCPackageWorkspaceException>()),
    );
  });
  for (final versions in [(2, 3), (3, 2), (3, 99), (99, 99)]) {
    test('review index writer rejects inconsistent UI versions $versions', () {
      expect(
        () => index(metadata(versions.$1, versions.$2)).toJson(),
        throwsA(isA<CCPackageWorkspaceException>()),
      );
    });
    test(
      'review index reader rejects inconsistent UI versions $versions',
      () async {
        final root = Directory.systemTemp.createTempSync(
          'ccrouter-ui-index-review-',
        );
        addTearDown(() => root.deleteSync(recursive: true));
        final package = CCResolvedPackage(
          name: 'review',
          version: '1.0.0',
          root: root,
          dependencies: const [],
          devDependencies: const [],
          writable: false,
        );
        final docs = metadata(versions.$1, versions.$2);
        final value = index(docs);
        package.indexFile
          ..createSync(recursive: true)
          ..writeAsStringSync(
            jsonEncode({
              'schemaVersion': versions.$1 == 3 ? 5 : 4,
              'package': {'name': 'review', 'version': '1.0.0'},
              'contentFingerprint': value.contentFingerprint,
              'bundle': null,
              'dependencies': [],
              'metadata': docs,
              'capabilityCatalog': value.capabilityCatalog.toJson(),
            }),
          );
        await expectLater(
          CCPackageIndex.read(package),
          throwsA(isA<CCPackageWorkspaceException>()),
        );
      },
    );
  }
}
