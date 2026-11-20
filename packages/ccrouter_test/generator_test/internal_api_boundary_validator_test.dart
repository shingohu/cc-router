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
  test('file URI imports and exports obey the same Package boundary', () {
    final root = Directory.systemTemp.createTempSync('ccrouter_api_file_');
    addTearDown(() => root.deleteSync(recursive: true));
    final owner = Directory(path.join(root.path, 'owner'));
    final target = Directory(path.join(root.path, 'target'));
    final source = File(path.join(owner.path, 'lib/feature.dart'))
      ..createSync(recursive: true);
    final packages = [_package('owner', owner), _package('target', target)];
    final foreign = File(
      path.join(target.path, 'lib/src/ccrouter_generated/hidden.dart'),
    ).uri;
    final own = File(
      path.join(owner.path, 'lib/src/ccrouter_generated/own.dart'),
    ).uri;
    final public = File(path.join(target.path, 'lib/target.dart')).uri;
    for (final (uri, forbidden) in [
      (foreign.toString(), true),
      if (!Platform.isWindows)
        (foreign.replace(host: 'localhost').toString(), true),
      (own.toString(), false),
      (public.toString(), false),
      (foreign.replace(query: 'query').toString(), true),
      (foreign.replace(fragment: 'fragment').toString(), false),
      (foreign.resolve('%FF.dart').toString(), false),
      (foreign.resolve('%00.dart').toString(), false),
    ]) {
      for (final directive in [
        "import '$uri';",
        "export '$uri';",
        "import 'public.dart' if (dart.library.io) '$uri';",
      ]) {
        source.writeAsStringSync(directive);
        expect(
          CCGeneratedInternalApiBoundaryValidator.validate(packages),
          hasLength(forbidden ? 1 : 0),
          reason: directive,
        );
      }
    }
  });

  test('native aliases cannot hide a foreign generated library', () {
    final root = Directory.systemTemp.createTempSync('ccrouter_api_alias_');
    addTearDown(() => root.deleteSync(recursive: true));
    final owner = Directory(path.join(root.path, 'owner'));
    final target = Directory(path.join(root.path, 'target'));
    final source = File(path.join(owner.path, 'lib/feature.dart'))
      ..createSync(recursive: true);
    final hidden = File(
      path.join(target.path, 'lib/src/ccrouter_generated/hidden.dart'),
    )..createSync(recursive: true);
    hidden.writeAsStringSync('const hidden = 1;');
    final alias = Link(path.join(owner.path, 'lib/public_alias.dart'))
      ..createSync(hidden.path);
    final targetAlias = Link(path.join(root.path, 'target_alias'))
      ..createSync(target.path);
    final packages = [_package('owner', owner), _package('target', target)];
    for (final uri in [
      'public_alias.dart',
      'package:owner/public_alias.dart',
      alias.uri.toString(),
      File(
        path.join(targetAlias.path, 'lib/src/ccrouter_generated/hidden.dart'),
      ).uri.toString(),
    ]) {
      source.writeAsStringSync("import '$uri';");
      expect(
        CCGeneratedInternalApiBoundaryValidator.validate(packages),
        hasLength(1),
        reason: uri,
      );
    }
  }, skip: Platform.isWindows ? 'POSIX symlink fixture' : false);

  test('escaped generated directory names cannot bypass the AST check', () {
    final root = Directory.systemTemp.createTempSync('ccrouter_api_escape_');
    addTearDown(() => root.deleteSync(recursive: true));
    final owner = Directory(path.join(root.path, 'owner'));
    final source = File(path.join(owner.path, 'lib/feature.dart'))
      ..createSync(recursive: true);
    final packages = [
      _package('owner', owner),
      _package('target', Directory(path.join(root.path, 'target'))),
    ];
    for (final name in [
      r'\u0063\u0063router_generated',
      r'\x63\x63router_generated',
      r'\u{63}\u{63}router_generated',
    ]) {
      for (final directive in [
        "import 'package:target/src/$name/hidden.dart';",
        "export 'package:target/src/$name/hidden.dart';",
        "import 'public.dart' if (dart.library.io) 'package:target/src/$name/hidden.dart';",
      ]) {
        source.writeAsStringSync(directive);
        expect(
          CCGeneratedInternalApiBoundaryValidator.validate(packages),
          hasLength(1),
          reason: directive,
        );
      }
      source.writeAsStringSync(
        "const sample = r'package:target/src/$name/hidden.dart';\n// import 'package:target/src/$name/hidden.dart';",
      );
      expect(
        CCGeneratedInternalApiBoundaryValidator.validate(packages),
        isEmpty,
      );
    }
  });

  test('malformed namespace URIs defer to Builder without crashing', () {
    final root = Directory.systemTemp.createTempSync('ccrouter_api_uri_');
    addTearDown(() => root.deleteSync(recursive: true));
    final source = File(path.join(root.path, 'owner/lib/feature.dart'))
      ..createSync(recursive: true);
    final packages = [
      _package('owner', Directory(path.join(root.path, 'owner'))),
      _package('target', Directory(path.join(root.path, 'target'))),
    ];
    for (final uri in [
      'package:target/src/ccrouter_generated/%FF.dart',
      'package:target/src/ccrouter_generated/%00.dart',
      'package:target/src/ccrouter_generated/source.dart#fragment',
      '../target/lib/src/ccrouter_generated/%FF.dart',
      '../target/lib/src/ccrouter_generated/source.dart#fragment',
    ]) {
      source.writeAsStringSync("import '$uri';");
      expect(
        CCGeneratedInternalApiBoundaryValidator.validate(packages),
        isEmpty,
        reason: uri,
      );
    }
  });

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

    source.writeAsStringSync(
      "import '${targetUri.replaceFirst('ccrouter_generated', '%63%63router_generated')}';",
    );
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
    for (final uri in [
      '$relative?query',
      '$targetUri?query',
      targetUri.replaceFirst('package:', 'package:/'),
      targetUri.replaceFirst('package:', 'package://ignored/'),
      targetUri.replaceFirst('/src/', '/src%2F'),
    ]) {
      source.writeAsStringSync("import '$uri';");
      expect(
        CCGeneratedInternalApiBoundaryValidator.validate(packages),
        hasLength(1),
        reason: uri,
      );
    }
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
