import 'dart:io';

import 'package:path/path.dart' as path;

/// The kind of source template requested from the CLI.
enum CCScaffoldKind {
  /// Creates a new Flutter component Package.
  component,

  /// Creates one internal typed Route page in an existing component Package.
  page,
}

/// A failure raised when a scaffold cannot be created without overwriting code.
final class CCScaffoldException implements Exception {
  /// Creates a user-facing scaffold failure.
  const CCScaffoldException(this.message);

  /// Actionable explanation of the failed precondition.
  final String message;

  @override
  String toString() => message;
}

/// Creates a component or page template after checking every target file.
Future<List<File>> createScaffold({
  required CCScaffoldKind kind,
  required String name,
  required Directory root,
}) async {
  final files = switch (kind) {
    CCScaffoldKind.component => _componentFiles(name, root),
    CCScaffoldKind.page => _pageFiles(name, root),
  };
  final existing = files.keys.where((file) => file.existsSync()).toList();
  if (existing.isNotEmpty) {
    throw CCScaffoldException(
      'Refusing to overwrite existing file(s):\n'
      '${existing.map((file) => '  ${file.path}').join('\n')}',
    );
  }

  final created = <File>[];
  try {
    for (final entry in files.entries) {
      await entry.key.parent.create(recursive: true);
      await entry.key.writeAsString(entry.value, flush: true);
      created.add(entry.key);
    }
  } catch (error) {
    for (final file in created.reversed) {
      if (file.existsSync()) await file.delete();
    }
    throw CCScaffoldException(
      'Scaffold creation failed: ${error.runtimeType}.',
    );
  }
  return created;
}

Map<File, String> _componentFiles(String rawName, Directory parent) {
  final packageName = _packageName(rawName);
  final packageRoot = Directory(path.join(parent.path, packageName));
  if (packageRoot.existsSync()) {
    throw CCScaffoldException(
      'Component target already exists: ${packageRoot.path}',
    );
  }
  final symbol = _lowerCamel(packageName);
  final componentSymbol = '${symbol}Component';
  final idSymbol = '${symbol}ComponentId';
  final workspaceResolution = _hasWorkspaceRoot(parent);
  final pubspec = StringBuffer()
    ..writeln('name: $packageName')
    ..writeln('description: CCRouter component Package.')
    ..writeln('version: 0.1.0')
    ..writeln('publish_to: none');
  if (workspaceResolution) pubspec.writeln('resolution: workspace');
  pubspec
    ..writeln('environment:')
    ..writeln('  sdk: ^3.10.0')
    ..writeln('dependencies:')
    ..writeln('  ccrouter: ^0.1.0')
    ..writeln('  flutter:')
    ..writeln('    sdk: flutter')
    ..writeln('dev_dependencies:')
    ..writeln('  ccrouter_generator: ^0.1.0');

  final componentSource =
      '''import 'package:ccrouter/ccrouter.dart';

/// Stable identity of the `$packageName` component.
const $idSymbol = CCComponentId('$packageName');

/// Build-time descriptor owned by the `$packageName` component.
const $componentSymbol = CCComponent(
  id: $idSymbol,
  version: '0.1.0',
);
''';
  final barrel =
      '''library;

/// Public feature APIs for the `$packageName` component are exported here.
/// The component descriptor remains an internal source declaration.
''';
  return <File, String>{
    File(path.join(packageRoot.path, 'pubspec.yaml')):
        '${pubspec.toString()}\n',
    File(path.join(packageRoot.path, 'lib', '$packageName.dart')): barrel,
    File(
      path.join(
        packageRoot.path,
        'lib',
        'src',
        '${packageName}_component.dart',
      ),
    ): componentSource,
  };
}

Map<File, String> _pageFiles(String rawName, Directory packageRoot) {
  final pageClass = _pageClassName(rawName);
  final pageStem = _snakeCase(pageClass);
  final pubspec = File(path.join(packageRoot.path, 'pubspec.yaml'));
  if (!pubspec.existsSync()) {
    throw CCScaffoldException(
      'Page target is not a Dart Package: ${packageRoot.path}',
    );
  }
  final componentName = _readPackageName(pubspec);
  final routeStem = pageStem.endsWith('_page')
      ? pageStem.substring(0, pageStem.length - '_page'.length)
      : pageStem;
  final routeId = '$componentName.$routeStem';
  final routePath = '/$routeStem';
  final source =
      '''import 'package:ccrouter/ccrouter.dart';
import 'package:flutter/material.dart';

/// A page generated as the starting point for `$routeId`.
@CCRoute<void>(
  id: '$routeId',
  pattern: CCPathPattern('$routePath'),
)
final class $pageClass extends StatelessWidget {
  /// Creates the `$pageClass` destination.
  const $pageClass({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('$pageClass')),
    body: const Center(child: Text('Replace this page with component UI.')),
  );
}
''';
  return <File, String>{
    File(path.join(packageRoot.path, 'lib', 'src', '$pageStem.dart')): source,
  };
}

String _packageName(String value) {
  final normalized = value.trim().toLowerCase();
  if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(normalized)) {
    throw CCScaffoldException(
      'Component name must be a Dart Package name: [a-z][a-z0-9_]*.',
    );
  }
  return normalized;
}

String _readPackageName(File pubspec) {
  final match = RegExp(
    r'^name:\s*([a-z][a-z0-9_]*)\s*$',
    multiLine: true,
  ).firstMatch(pubspec.readAsStringSync());
  if (match == null) {
    throw CCScaffoldException(
      'Package pubspec has no valid name: ${pubspec.path}',
    );
  }
  return match.group(1)!;
}

String _pageClassName(String value) {
  final words = value
      .trim()
      .replaceAll(RegExp(r'[^A-Za-z0-9_]+'), '_')
      .split(RegExp(r'[_\s]+'))
      .where((word) => word.isNotEmpty)
      .map((word) => word[0].toUpperCase() + word.substring(1))
      .join();
  if (words.isEmpty || !RegExp(r'^[A-Z][A-Za-z0-9]*$').hasMatch(words)) {
    throw CCScaffoldException(
      'Page name must produce a Dart class identifier, for example OrderDetailPage.',
    );
  }
  return words.endsWith('Page') ? words : '${words}Page';
}

String _snakeCase(String value) => value
    .replaceAllMapped(
      RegExp(r'([a-z0-9])([A-Z])'),
      (match) => '${match.group(1)}_${match.group(2)}',
    )
    .toLowerCase();

String _lowerCamel(String value) {
  final words = value.split('_').where((word) => word.isNotEmpty).toList();
  if (words.isEmpty) return value;
  return words.first +
      words
          .skip(1)
          .map((word) => word[0].toUpperCase() + word.substring(1))
          .join();
}

bool _hasWorkspaceRoot(Directory start) {
  var current = start.absolute;
  while (true) {
    final pubspec = File(path.join(current.path, 'pubspec.yaml'));
    if (pubspec.existsSync() &&
        RegExp(
          r'^workspace:\s*$',
          multiLine: true,
        ).hasMatch(pubspec.readAsStringSync())) {
      return true;
    }
    final parent = current.parent;
    if (path.equals(parent.path, current.path)) return false;
    current = parent;
  }
}
