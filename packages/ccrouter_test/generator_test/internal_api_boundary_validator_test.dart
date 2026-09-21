@TestOn('vm')
library;

// The validator belongs to Generator tooling, not its public builder API.
// ignore_for_file: implementation_imports

import 'dart:io';

import 'package:ccrouter_generator/src/internal_api_boundary_validator.dart';
import 'package:ccrouter_generator/src/package_workspace.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  test('rejects cross-Package imports, exports, and conditional imports', () {
    final root = Directory.systemTemp.createTempSync('ccrouter_api_boundary_');
    addTearDown(() => root.deleteSync(recursive: true));
    final ownerRoot = Directory(path.join(root.path, 'owner'));
    final targetRoot = Directory(path.join(root.path, 'target'));
    final packages = [
      _package('owner', ownerRoot),
      _package('target', targetRoot),
    ];
    final source = File(path.join(ownerRoot.path, 'lib', 'feature.dart'))
      ..createSync(recursive: true);
    const targetUri =
        'package:target/src/ccrouter_generated/component/target.route_api.g.dart';
    source.writeAsStringSync("import '$targetUri';\n");
    expect(CCGeneratedInternalApiBoundaryValidator.validate(packages), [
      allOf(contains('owner:lib/feature.dart:1'), contains(targetUri)),
    ]);

    source.writeAsStringSync("export '$targetUri';\n");
    expect(
      CCGeneratedInternalApiBoundaryValidator.validate(packages),
      hasLength(1),
    );

    source.writeAsStringSync('''
import 'package:target/target.dart'
    if (dart.library.io) '$targetUri';
''');
    expect(
      CCGeneratedInternalApiBoundaryValidator.validate(packages),
      hasLength(1),
    );

    final targetFile = path.join(
      targetRoot.path,
      'lib',
      'src',
      'ccrouter_generated',
      'component',
      'target.route_api.g.dart',
    );
    final relative = path
        .relative(targetFile, from: source.parent.path)
        .replaceAll('\\', '/');
    source.writeAsStringSync("import '$relative';\n");
    expect(
      CCGeneratedInternalApiBoundaryValidator.validate(packages),
      hasLength(1),
    );
  });

  test('allows owner imports, public contracts, and generated Host glue', () {
    final root = Directory.systemTemp.createTempSync('ccrouter_api_allowed_');
    addTearDown(() => root.deleteSync(recursive: true));
    final ownerRoot = Directory(path.join(root.path, 'owner'));
    final targetRoot = Directory(path.join(root.path, 'target'));
    final packages = [
      _package('owner', ownerRoot),
      _package('target', targetRoot),
    ];
    final source = File(path.join(ownerRoot.path, 'lib', 'feature.dart'))
      ..createSync(recursive: true);
    source.writeAsStringSync('''
// import 'package:target/src/ccrouter_generated/route/hidden.dart';
import 'package:owner/src/ccrouter_generated/component/owner.route_api.g.dart';
import 'package:target/target.dart';
const sample = 'package:target/src/ccrouter_generated/route/hidden.dart';
''');
    final generated = File(
      path.join(
        ownerRoot.path,
        'lib',
        'src',
        'ccrouter_generated',
        'host',
        'owner_ccrouter.g.dart',
      ),
    )..createSync(recursive: true);
    generated.writeAsStringSync('''
import 'package:target/src/ccrouter_generated/host/target_ccrouter.g.dart';
''');
    expect(CCGeneratedInternalApiBoundaryValidator.validate(packages), isEmpty);

    final readOnly = _package(
      'readonly',
      Directory(path.join(root.path, 'readonly')),
      writable: false,
    );
    final external = File(path.join(readOnly.root.path, 'lib', 'feature.dart'))
      ..createSync(recursive: true);
    external.writeAsStringSync('''
import 'package:target/src/ccrouter_generated/component/target.route_api.g.dart';
''');
    expect(
      CCGeneratedInternalApiBoundaryValidator.validate([...packages, readOnly]),
      isEmpty,
    );
  });
}

CCResolvedPackage _package(
  String name,
  Directory root, {
  bool writable = true,
}) => CCResolvedPackage(
  name: name,
  version: '1.0.0',
  root: root,
  dependencies: const [],
  devDependencies: const [],
  writable: writable,
);
