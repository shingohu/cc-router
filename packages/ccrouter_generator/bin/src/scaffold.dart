import 'dart:io';

import 'package:path/path.dart' as path;

/// The kind of source template requested from the CLI.
enum CCScaffoldKind {
  /// Creates a new Flutter component Package.
  component,

  /// Creates one internal typed Route page in an existing component Package.
  page,

  /// Creates an internal Service Contract and lazy implementation template.
  service,

  /// Creates an internal typed Command and Handler template.
  command,

  /// Creates an internal typed Event and Subscriber template.
  event,

  /// Creates an internal InitTask Contract and Handler template.
  initTask,
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
  bool withSubscriber = false,
  bool withContract = false,
}) async {
  final files = switch (kind) {
    CCScaffoldKind.component => _componentFiles(name, root),
    CCScaffoldKind.page => _pageFiles(name, root),
    CCScaffoldKind.service => _serviceFiles(name, root),
    CCScaffoldKind.command => _commandFiles(name, root),
    CCScaffoldKind.event => _eventFiles(
      name,
      root,
      withSubscriber: withSubscriber,
    ),
    CCScaffoldKind.initTask => _initTaskFiles(
      name,
      root,
      withContract: withContract,
    ),
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

/// Returns deterministic follow-up guidance for one successful scaffold.
///
/// The guidance never mutates Workspace or Host dependencies because the CLI
/// cannot prove which Host or consumer should own the new source.
List<String> scaffoldCompletionSteps({
  required CCScaffoldKind kind,
  required Directory root,
  required List<File> createdFiles,
}) {
  if (kind != CCScaffoldKind.component) {
    return const <String>[
      'Complete the generated TODOs and public API for the real use case.',
      'Run `ccrouter generate <host-root>` for the Host that consumes this component.',
      'Use the stable generated Component API only after generation succeeds.',
    ];
  }

  final packageRoot = createdFiles
      .map((file) => file.parent)
      .firstWhere(
        (directory) =>
            File(path.join(directory.path, 'pubspec.yaml')).existsSync(),
        orElse: () => Directory(
          path.join(
            root.path,
            path.basenameWithoutExtension(createdFiles.first.path),
          ),
        ),
      );
  final workspaceRoot = _findWorkspaceRoot(root);
  final steps = <String>[];
  if (workspaceRoot != null) {
    final relativePackage = path.relative(
      packageRoot.path,
      from: workspaceRoot.path,
    );
    steps.add(
      'Add `$relativePackage` to `${path.join(workspaceRoot.path, 'pubspec.yaml')}` workspace entries.',
    );
  }
  steps.addAll(const <String>[
    'Add the new Package to the intended Host or consuming component dependencies.',
    'Run `flutter pub get` from the actual Host, then `ccrouter generate <host-root>`.',
  ]);
  return List<String>.unmodifiable(steps);
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

Map<File, String> _serviceFiles(String rawName, Directory packageRoot) {
  final serviceClass = _capabilityClassName(rawName, 'Service');
  final stem = _snakeCase(serviceClass);
  final packageName = _readPackageNameOrFail(packageRoot);
  final id = '$packageName.${_idStem(serviceClass, 'Service')}';
  final source =
      '''import 'package:ccrouter/ccrouter.dart';

/// Internal lazy app-scoped Service generated for `$id`.
@CCService(id: '$id')
final class $serviceClass {
  /// Creates the component-owned Service.
  const $serviceClass();

  /// Returns the current value owned by this component.
  String read() => 'replace-me';
}
''';
  return <File, String>{
    File(path.join(packageRoot.path, 'lib', 'src', '$stem.dart')): source,
  };
}

Map<File, String> _commandFiles(String rawName, Directory packageRoot) {
  final commandClass = _capabilityClassName(rawName, 'Command');
  final stem = _snakeCase(commandClass);
  final packageName = _readPackageNameOrFail(packageRoot);
  final id = '$packageName.${_idStem(commandClass, 'Command')}';
  final source =
      '''import 'package:ccrouter/ccrouter.dart';

/// One requested operation owned by `$packageName`.
@CCCommandContract(
  id: '$id',
  description: 'Replace with the Command usage scenario.',
)
final class $commandClass implements CCCommand<void> {
  /// Creates the request. Add only immutable, serializable fields.
  const $commandClass();
}

/// Handles [$commandClass] inside its owning component.
@CCCommandHandler()
Future<void> handle${commandClass}(
  $commandClass command,
  CCInvocationContext context,
) async {
  // TODO: implement the requested operation.
}
''';
  return <File, String>{
    File(path.join(packageRoot.path, 'lib', 'src', '$stem.dart')): source,
  };
}

Map<File, String> _eventFiles(
  String rawName,
  Directory packageRoot, {
  required bool withSubscriber,
}) {
  final eventClass = _capabilityClassName(rawName, 'Event');
  final stem = _snakeCase(eventClass);
  final packageName = _readPackageNameOrFail(packageRoot);
  final id = '$packageName.${_idStem(eventClass, 'Event')}';
  final subscriber = withSubscriber
      ? '''

/// Handles [$eventClass] without returning a business result.
@CCEventSubscription()
void observe${eventClass}($eventClass event) {
  // TODO: react to the completed fact.
}
'''
      : '';
  final source =
      '''import 'package:ccrouter/ccrouter.dart';

/// A completed fact published by `$packageName`.
@CCEventContract(
  id: '$id',
  description: 'Replace with the Event usage scenario.',
)
final class $eventClass implements CCEvent {
  /// Creates the immutable payload. Add only final fields.
  const $eventClass();
}
$subscriber
''';
  return <File, String>{
    File(path.join(packageRoot.path, 'lib', 'src', '$stem.dart')): source,
  };
}

Map<File, String> _initTaskFiles(
  String rawName,
  Directory packageRoot, {
  required bool withContract,
}) {
  final taskName = _capabilityClassName(rawName, 'InitTask');
  final stem = _snakeCase(taskName);
  final packageName = _readPackageNameOrFail(packageRoot);
  final id = '$packageName.${_idStem(taskName, 'InitTask')}';
  final contract = '${_lowerCamel(_snakeCase(taskName))}Contract';
  final handler = 'initialize$taskName';
  final contractDeclaration = withContract
      ? '''
/// Stable startup dependency for `$packageName`.
const $contract = CCInitTaskContract(
  id: '$id',
  description: 'Replace with the initialization usage scenario.',
);
'''
      : '';
  final taskIdentity = withContract ? 'contract: $contract,' : "id: '$id',";
  final source =
      '''import 'package:ccrouter/ccrouter.dart';

$contractDeclaration

/// Initializes the component after the Host opens the selected Gate.
@CCInitTask(
  $taskIdentity
  gate: CCInitTaskGate.appStarted,
  failurePolicy: CCInitTaskFailurePolicy.optional,
)
Future<void> $handler(CCInvocationContext context) async {
  // TODO: perform bounded startup work or delegate to a Service.
}
''';
  return <File, String>{
    File(path.join(packageRoot.path, 'lib', 'src', '$stem.dart')): source,
  };
}

String _readPackageNameOrFail(Directory packageRoot) {
  final pubspec = File(path.join(packageRoot.path, 'pubspec.yaml'));
  if (!pubspec.existsSync()) {
    throw CCScaffoldException(
      'Capability target is not a Dart Package: ${packageRoot.path}',
    );
  }
  return _readPackageName(pubspec);
}

String _capabilityClassName(String value, String suffix) {
  final words = value
      .trim()
      .replaceAll(RegExp(r'[^A-Za-z0-9_]+'), '_')
      .split(RegExp(r'[_\s]+'))
      .where((word) => word.isNotEmpty)
      .map((word) => word[0].toUpperCase() + word.substring(1))
      .join();
  if (words.isEmpty || !RegExp(r'^[A-Z][A-Za-z0-9]*$').hasMatch(words)) {
    throw CCScaffoldException(
      'Capability name must produce a Dart class identifier, for example OrderSummary.',
    );
  }
  return words.endsWith(suffix) ? words : '$words$suffix';
}

String _idStem(String value, String suffix) {
  final stem = value.endsWith(suffix)
      ? value.substring(0, value.length - suffix.length)
      : value;
  return _snakeCase(stem).replaceAll('_', '-');
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
  return _findWorkspaceRoot(start) != null;
}

Directory? _findWorkspaceRoot(Directory start) {
  var current = start.absolute;
  while (true) {
    final pubspec = File(path.join(current.path, 'pubspec.yaml'));
    if (pubspec.existsSync() &&
        RegExp(
          r'^workspace:\s*$',
          multiLine: true,
        ).hasMatch(pubspec.readAsStringSync())) {
      return current;
    }
    final parent = current.parent;
    if (path.equals(parent.path, current.path)) return null;
    current = parent;
  }
}
