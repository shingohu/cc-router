import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';

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

/// Injectable process boundary used only for Flutter's official app template.
typedef CCScaffoldProcessRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
      Map<String, String>? environment,
    });

/// Creates a component or page template after checking every target file.
Future<List<File>> createScaffold({
  required CCScaffoldKind kind,
  required String name,
  required Directory root,
  bool withSubscriber = false,
  bool withContract = false,
  bool withExample = false,
  CCScaffoldProcessRunner processRunner = _runScaffoldProcess,
}) async {
  if (kind == CCScaffoldKind.component) {
    return _createComponentScaffold(
      name,
      root,
      withExample: withExample,
      processRunner: processRunner,
    );
  }
  final files = switch (kind) {
    CCScaffoldKind.component => throw StateError('Handled above.'),
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

/// Builds one complete component beside its final path and publishes it with a
/// single same-filesystem rename only after every optional tool step succeeds.
Future<List<File>> _createComponentScaffold(
  String rawName,
  Directory parent, {
  required bool withExample,
  required CCScaffoldProcessRunner processRunner,
}) async {
  final packageName = _packageName(rawName);
  final packageRoot = Directory(path.join(parent.path, packageName));
  final finalFiles = _componentFiles(
    packageName,
    parent,
    withExample: withExample,
  );
  final stagingRoot = await parent.createTemp('.ccrouter-$packageName-');
  final stagingFiles = <File, String>{
    for (final entry in finalFiles.entries)
      File(
        path.join(
          stagingRoot.path,
          path.relative(entry.key.path, from: packageRoot.path),
        ),
      ): entry.value,
  };
  try {
    for (final entry in stagingFiles.entries) {
      await entry.key.parent.create(recursive: true);
      await entry.key.writeAsString(entry.value, flush: true);
    }
    if (withExample) {
      await _createExampleHost(
        packageName: packageName,
        stagingRoot: stagingRoot,
        finalRoot: packageRoot,
        processRunner: processRunner,
      );
    }
    if (packageRoot.existsSync()) {
      throw CCScaffoldException(
        'Component target appeared during creation; refusing to overwrite: '
        '${packageRoot.path}',
      );
    }
    await stagingRoot.rename(packageRoot.path);
    return <File>[
      ...finalFiles.keys,
      if (withExample) ...[
        File(path.join(packageRoot.path, 'example', 'pubspec.yaml')),
        File(path.join(packageRoot.path, 'example', 'lib', 'main.dart')),
        File(
          path.join(
            packageRoot.path,
            'example',
            'lib',
            'src',
            'example_component.dart',
          ),
        ),
        File(
          path.join(
            packageRoot.path,
            'example',
            'lib',
            'src',
            'example_home_page.dart',
          ),
        ),
      ],
    ];
  } on CCScaffoldException {
    if (stagingRoot.existsSync()) await stagingRoot.delete(recursive: true);
    rethrow;
  } on Object catch (error) {
    if (stagingRoot.existsSync()) await stagingRoot.delete(recursive: true);
    throw CCScaffoldException(
      'Scaffold creation failed before publication: ${error.runtimeType}.',
    );
  }
}

/// Creates and configures an application Host through Flutter's own template.
Future<void> _createExampleHost({
  required String packageName,
  required Directory stagingRoot,
  required Directory finalRoot,
  required CCScaffoldProcessRunner processRunner,
}) async {
  final exampleRoot = Directory(path.join(stagingRoot.path, 'example'));
  final result = await processRunner(
    _flutterExecutable(),
    [
      'create',
      '--template=app',
      '--empty',
      '--no-pub',
      '--project-name',
      '${packageName}_example',
      exampleRoot.path,
    ],
    workingDirectory: stagingRoot.path,
    environment: {...Platform.environment, 'CCROUTER_PUB_HOOK_DISABLE': '1'},
  );
  if (result.exitCode != 0) {
    final details = '${result.stderr}'.trim().isNotEmpty
        ? '${result.stderr}'.trim()
        : '${result.stdout}'.trim();
    final bounded = details.length > 2000
        ? details.substring(details.length - 2000)
        : details;
    throw CCScaffoldException(
      'Flutter example creation failed (exit ${result.exitCode}).'
      '${bounded.isEmpty ? '' : '\n$bounded'}',
    );
  }
  final exampleManifest = File(path.join(exampleRoot.path, 'pubspec.yaml'));
  final generated = _readYamlMap(exampleManifest);
  final component = _readYamlMap(
    File(path.join(stagingRoot.path, 'pubspec.yaml')),
  );
  if (generated == null || component == null) {
    throw const CCScaffoldException(
      'Flutter example creation did not produce a readable pubspec.yaml.',
    );
  }
  final document = (_normalizeYaml(generated) as Map).cast<String, Object>();
  final dependencies = switch (document['dependencies']) {
    final Map value => value.cast<String, Object>(),
    _ => <String, Object>{},
  };
  final devDependencies = switch (document['dev_dependencies']) {
    final Map value => value.cast<String, Object>(),
    _ => <String, Object>{},
  };
  final componentDependencies = component['dependencies'];
  final componentDevDependencies = component['dev_dependencies'];
  if (componentDependencies is! YamlMap ||
      componentDevDependencies is! YamlMap ||
      !componentDependencies.containsKey('ccrouter') ||
      !componentDevDependencies.containsKey('ccrouter_generator') ||
      !componentDevDependencies.containsKey('build_runner')) {
    throw const CCScaffoldException(
      'Generated component manifest is missing generation dependencies.',
    );
  }
  final finalExampleRoot = Directory(path.join(finalRoot.path, 'example'));
  dependencies['ccrouter'] = _rebasePathDependency(
    _normalizeYaml(componentDependencies['ccrouter']),
    finalRoot,
    finalExampleRoot,
  );
  dependencies[packageName] = _hasWorkspaceRoot(finalRoot)
      ? '^0.1.0'
      : <String, Object>{'path': '..'};
  devDependencies['ccrouter_generator'] = _rebasePathDependency(
    _normalizeYaml(componentDevDependencies['ccrouter_generator']),
    finalRoot,
    finalExampleRoot,
  );
  devDependencies['build_runner'] = _rebasePathDependency(
    _normalizeYaml(componentDevDependencies['build_runner']),
    finalRoot,
    finalExampleRoot,
  );
  document['dependencies'] = dependencies;
  document['dev_dependencies'] = devDependencies;
  if (_hasWorkspaceRoot(finalRoot)) document['resolution'] = 'workspace';
  await exampleManifest.writeAsString(
    '${_renderYamlDocument(document)}\n',
    flush: true,
  );
  final sources = <String, String>{
    'lib/main.dart':
        '''import 'package:ccrouter/ccrouter_host.dart';
import 'package:flutter/material.dart';

import 'src/ccrouter_generated/ccrouter_host.api.g.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  CCRouterHost.initialize(hostAssembly: ccrouterGeneratedHostAssembly);
  runApp(const CCManagedRouterApp(title: '$packageName Example'));
}
''',
    'lib/src/example_component.dart':
        '''import 'package:ccrouter/ccrouter.dart';

/// Composition owned by this standalone example, separate from the component.
const exampleComponent = CCComponent(
  id: CCComponentId('${packageName}_example'),
  version: '0.1.0',
  dependencies: [CCComponentId('$packageName')],
);
''',
    'lib/src/example_home_page.dart':
        '''import 'package:ccrouter/ccrouter.dart';
import 'package:flutter/material.dart';

/// The example owns a real startup Route; Managed never invents a home page.
@CCRoute<void>(
  id: '${packageName}_example.home',
  pattern: CCPathPattern('/'),
)
final class ExampleHomePage extends StatelessWidget {
  const ExampleHomePage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('$packageName Example')),
    body: const Center(child: Text('Add component pages and open their typed Intents here.')),
  );
}
''',
  };
  for (final source in sources.entries) {
    final file = File(path.join(exampleRoot.path, source.key));
    await file.parent.create(recursive: true);
    await file.writeAsString(source.value, flush: true);
  }
}

/// Executes one external scaffold process without shell interpolation.
Future<ProcessResult> _runScaffoldProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
}) => Process.run(
  executable,
  arguments,
  workingDirectory: workingDirectory,
  environment: environment,
);

/// Resolves the Flutter executable paired with the running Dart SDK.
String _flutterExecutable() {
  final executableName = Platform.isWindows ? 'flutter.bat' : 'flutter';
  final explicitRoot = Platform.environment['FLUTTER_ROOT'];
  if (explicitRoot != null) {
    final explicit = File(path.join(explicitRoot, 'bin', executableName));
    if (explicit.existsSync()) return explicit.path;
  }
  var sdkBin = File(Platform.resolvedExecutable).absolute.parent;
  for (var index = 0; index < 3; index++) {
    sdkBin = sdkBin.parent;
  }
  final paired = File(path.join(sdkBin.path, executableName));
  return paired.existsSync() ? paired.path : executableName;
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
  final packageName = path.basename(packageRoot.path);
  final exampleRoot = Directory(path.join(packageRoot.path, 'example'));
  final steps = <String>[];
  if (workspaceRoot != null) {
    final relativePackage = path.relative(
      packageRoot.path,
      from: workspaceRoot.path,
    );
    steps.add(
      'Add `$relativePackage` to `${path.join(workspaceRoot.path, 'pubspec.yaml')}` workspace entries.',
    );
    if (exampleRoot.existsSync()) {
      final relativeExample = path.relative(
        exampleRoot.path,
        from: workspaceRoot.path,
      );
      steps.add(
        'Add `$relativeExample` to `${path.join(workspaceRoot.path, 'pubspec.yaml')}` workspace entries.',
      );
    }
  }
  if (exampleRoot.existsSync()) {
    steps.addAll(<String>[
      'The generated example is a CCRouter Host with a direct `$packageName` dependency, a Managed app, and a registered / home.',
      if (workspaceRoot == null)
        'Outside a Workspace, first run `flutter pub get` from `${packageRoot.path}`, then `ccrouter portable prepare ${packageRoot.path}`. The component opts into Portable Generation State because the example consumes its parent as a read-only Path dependency.',
      'Run `flutter pub get` from `${exampleRoot.path}`, then `ccrouter generate ${exampleRoot.path}`.',
    ]);
  } else {
    steps.addAll(const <String>[
      'Add the new Package to the intended Host or consuming component dependencies.',
      'Run `flutter pub get` from the actual Host, then `ccrouter generate <host-root>`.',
    ]);
  }
  return List<String>.unmodifiable(steps);
}

/// Plans authored component files without publishing or mutating a Workspace.
///
/// Standalone examples consume a read-only parent, so that parent must prepare
/// portable artifacts using its own build tool before the example is generated.
Map<File, String> _componentFiles(
  String rawName,
  Directory parent, {
  bool withExample = false,
}) {
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
  final manifest = _resolveComponentManifest(parent, packageRoot);
  final pubspec = StringBuffer()
    ..writeln('name: $packageName')
    ..writeln('description: CCRouter component Package.')
    ..writeln('version: 0.1.0')
    ..writeln('publish_to: none');
  if (workspaceResolution) pubspec.writeln('resolution: workspace');
  pubspec
    ..writeln('environment:')
    ..writeln('  sdk: ${_yamlScalar(manifest.sdkConstraint)}')
    ..writeln('dependencies:');
  _writeDependency(pubspec, 'ccrouter', manifest.ccrouter);
  pubspec
    ..writeln('  flutter:')
    ..writeln('    sdk: flutter')
    ..writeln('dev_dependencies:');
  _writeDependency(pubspec, 'ccrouter_generator', manifest.ccrouterGenerator);
  if (withExample) {
    // Match the Flutter app template's SDK-pinned tool dependencies when the
    // component and example resolve independently for Portable verification.
    pubspec
      ..writeln('  flutter_test:')
      ..writeln('    sdk: flutter');
    _writeDependency(
      pubspec,
      'build_runner',
      _buildRunnerDependency(parent, packageRoot),
    );
  }

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
    if (withExample && !workspaceResolution)
      File(path.join(packageRoot.path, 'ccrouter.yaml')):
          'generation:\n  portable: true\n',
    File(path.join(packageRoot.path, 'pubspec.yaml')):
        '${pubspec.toString()}\n',
    File(path.join(packageRoot.path, '.metadata')): 'project_type: package\n',
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

/// Inherits a proven build tool source for independently generated examples.
Object _buildRunnerDependency(Directory parent, Directory target) {
  final manifests = <File>[
    ..._ancestorPubspecs(parent),
    ..._ancestorPubspecs(Directory.current),
  ];
  final dependency =
      _firstDependency(manifests, 'build_runner', target) ??
      _resolvedVersionConstraint(parent, 'build_runner') ??
      _resolvedVersionConstraint(Directory.current, 'build_runner');
  if (dependency != null) return dependency;
  throw const CCScaffoldException(
    'Cannot prove dependency source for build_runner. Declare a compatible '
    'build_runner dev dependency in the invoking Host/Workspace before '
    'creating --with-example. No component was published.',
  );
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

/// Resolved manifest values inherited by a newly scaffolded component.
final class _ComponentManifest {
  /// Creates one dependency-source snapshot.
  const _ComponentManifest({
    required this.sdkConstraint,
    required this.ccrouter,
    required this.ccrouterGenerator,
  });

  /// Dart SDK constraint inherited from the nearest Package or Workspace.
  final String sdkConstraint;

  /// Exact hosted, Git, or path declaration for the Runtime Package.
  final Object ccrouter;

  /// Exact hosted, Git, or path declaration for the Generator Package.
  final Object ccrouterGenerator;
}

/// Resolves scaffold dependencies without guessing from unrelated Packages.
_ComponentManifest _resolveComponentManifest(
  Directory parent,
  Directory packageRoot,
) {
  final manifests = _ancestorPubspecs(parent);
  final fallbackManifests = _ancestorPubspecs(Directory.current);
  final allManifests = <File>[
    ...manifests,
    for (final manifest in fallbackManifests)
      if (!manifests.any(
        (candidate) => path.equals(candidate.path, manifest.path),
      ))
        manifest,
  ];
  final sdk = _firstSdkConstraint(allManifests) ?? '^3.10.0';
  final ccrouter =
      _firstDependency(allManifests, 'ccrouter', packageRoot) ??
      _resolvedVersionConstraint(parent, 'ccrouter') ??
      _resolvedVersionConstraint(Directory.current, 'ccrouter');
  final generator =
      _firstDependency(allManifests, 'ccrouter_generator', packageRoot) ??
      _resolvedVersionConstraint(parent, 'ccrouter_generator') ??
      _resolvedVersionConstraint(Directory.current, 'ccrouter_generator');
  if (ccrouter == null || generator == null) {
    final missing = <String>[
      if (ccrouter == null) 'ccrouter',
      if (generator == null) 'ccrouter_generator',
    ].join(', ');
    throw CCScaffoldException(
      'Cannot prove dependency source for $missing. Run the scaffold from a '
      'resolved CCRouter Host/Workspace or declare the dependency there first. '
      'No component files were written under ${packageRoot.path}.',
    );
  }
  return _ComponentManifest(
    sdkConstraint: sdk,
    ccrouter: ccrouter,
    ccrouterGenerator: generator,
  );
}

/// Returns pubspec files from the nearest Package through its ancestors.
List<File> _ancestorPubspecs(Directory start) {
  final result = <File>[];
  var current = start.absolute;
  while (true) {
    final pubspec = File(path.join(current.path, 'pubspec.yaml'));
    if (pubspec.existsSync()) result.add(pubspec);
    final parent = current.parent;
    if (path.equals(parent.path, current.path)) return result;
    current = parent;
  }
}

/// Reads the first explicit direct dependency from ordered manifests.
Object? _firstDependency(
  List<File> manifests,
  String packageName,
  Directory packageRoot,
) {
  for (final manifest in manifests) {
    final document = _readYamlMap(manifest);
    if (document == null) continue;
    for (final section in const ['dependencies', 'dev_dependencies']) {
      final dependencies = document[section];
      if (dependencies is! YamlMap || !dependencies.containsKey(packageName)) {
        continue;
      }
      final value = _normalizeYaml(dependencies[packageName]);
      return _rebasePathDependency(value, manifest.parent, packageRoot);
    }
  }
  return null;
}

/// Rebases a direct path dependency for the new nested Package location.
Object _rebasePathDependency(
  Object value,
  Directory origin,
  Directory packageRoot,
) {
  if (value is! Map<String, Object> || value['path'] is! String) return value;
  final declared = value['path']! as String;
  final absolute = path.isAbsolute(declared)
      ? path.normalize(declared)
      : path.normalize(path.join(origin.path, declared));
  return <String, Object>{
    ...value,
    'path': path
        .relative(absolute, from: packageRoot.path)
        .replaceAll('\\', '/'),
  };
}

/// Reads the nearest declared Dart SDK constraint.
String? _firstSdkConstraint(List<File> manifests) {
  for (final manifest in manifests) {
    final environment = _readYamlMap(manifest)?['environment'];
    if (environment is YamlMap && environment['sdk'] is String) {
      return environment['sdk'] as String;
    }
  }
  return null;
}

/// Uses an exact resolved version only for proven Workspace or hosted sources.
String? _resolvedVersionConstraint(Directory start, String packageName) {
  final config = _nearestPackageConfig(start);
  if (config == null) return null;
  try {
    final decoded = jsonDecode(config.readAsStringSync());
    if (decoded is! Map || decoded['packages'] is! List) return null;
    for (final rawPackage in decoded['packages'] as List) {
      if (rawPackage is! Map || rawPackage['name'] != packageName) continue;
      final rootUri = rawPackage['rootUri'];
      if (rootUri is! String) return null;
      final packageRoot = Directory.fromUri(config.uri.resolve(rootUri));
      final resolutionRoot = config.parent.parent;
      if (!_isWorkspaceMember(resolutionRoot, packageRoot) &&
          !_isHostedLockDependency(resolutionRoot, packageName)) {
        return null;
      }
      final manifest = _readYamlMap(
        File(path.join(packageRoot.path, 'pubspec.yaml')),
      );
      final rawVersion = manifest?['version'];
      if (rawVersion is! String) return null;
      final version = Version.parse(rawVersion);
      return '^$version';
    }
  } on FormatException {
    return null;
  } on FileSystemException {
    return null;
  }
  return null;
}

/// Whether [packageRoot] is explicitly listed by the enclosing Workspace.
bool _isWorkspaceMember(Directory root, Directory packageRoot) {
  final workspace = _readYamlMap(
    File(path.join(root.path, 'pubspec.yaml')),
  )?['workspace'];
  if (workspace is! YamlList) return false;
  final normalizedPackage = path.normalize(packageRoot.absolute.path);
  for (final member in workspace.whereType<String>()) {
    if (path.equals(path.join(root.path, member), normalizedPackage)) {
      return true;
    }
  }
  return false;
}

/// Whether Pub's lockfile proves that [packageName] came from Hosted Pub.
bool _isHostedLockDependency(Directory root, String packageName) {
  final packages = _readYamlMap(
    File(path.join(root.path, 'pubspec.lock')),
  )?['packages'];
  if (packages is! YamlMap) return false;
  final dependency = packages[packageName];
  return dependency is YamlMap && dependency['source'] == 'hosted';
}

/// Finds resolved Package state without crossing above the filesystem root.
File? _nearestPackageConfig(Directory start) {
  var current = start.absolute;
  while (true) {
    final config = File(
      path.join(current.path, '.dart_tool', 'package_config.json'),
    );
    if (config.existsSync()) return config;
    final parent = current.parent;
    if (path.equals(parent.path, current.path)) return null;
    current = parent;
  }
}

/// Loads a YAML mapping or returns null for an unreadable manifest.
YamlMap? _readYamlMap(File file) {
  if (!file.existsSync()) return null;
  try {
    final document = loadYaml(file.readAsStringSync());
    return document is YamlMap ? document : null;
  } on FileSystemException {
    return null;
  } on YamlException {
    return null;
  }
}

/// Converts YAML collection nodes into immutable plain Dart values.
Object _normalizeYaml(Object? value) {
  if (value is YamlMap) {
    return <String, Object>{
      for (final entry in value.entries)
        if (entry.key is String)
          entry.key as String: _normalizeYaml(entry.value),
    };
  }
  if (value is YamlList) {
    return <Object>[for (final item in value) _normalizeYaml(item)];
  }
  if (value is String || value is num || value is bool) return value!;
  if (value == null) return 'any';
  return '$value';
}

/// Renders one generated YAML document using the supported deterministic subset.
String _renderYamlDocument(Map<String, Object> document) {
  final output = StringBuffer();
  for (final entry in document.entries) {
    if (entry.value is Map || entry.value is List) {
      output.writeln('${entry.key}:');
      _writeYamlValue(output, entry.value, 2);
    } else {
      output.writeln('${entry.key}: ${_yamlScalar(entry.value)}');
    }
  }
  return output.toString().trimRight();
}

/// Writes one dependency using a deterministic YAML subset.
void _writeDependency(StringBuffer output, String name, Object value) {
  if (value is Map || value is List) {
    output.writeln('  $name:');
    _writeYamlValue(output, value, 4);
    return;
  }
  output.writeln('  $name: ${_yamlScalar(value)}');
}

/// Writes nested Maps and Lists supported by Pub dependency declarations.
void _writeYamlValue(StringBuffer output, Object value, int indent) {
  final prefix = ' ' * indent;
  if (value is Map<String, Object>) {
    for (final entry in value.entries) {
      if (entry.value is Map || entry.value is List) {
        output.writeln('$prefix${entry.key}:');
        _writeYamlValue(output, entry.value, indent + 2);
      } else {
        output.writeln('$prefix${entry.key}: ${_yamlScalar(entry.value)}');
      }
    }
    return;
  }
  if (value is List<Object>) {
    for (final item in value) {
      if (item is Map || item is List) {
        output.writeln('$prefix-');
        _writeYamlValue(output, item, indent + 2);
      } else {
        output.writeln('$prefix- ${_yamlScalar(item)}');
      }
    }
  }
}

/// Preserves string identity, quoting YAML indicators and implicitly typed data.
String _yamlScalar(Object value) {
  if (value is! String) return '$value';
  if (RegExp(r'^[A-Za-z0-9_./^<>=+*~ -]+$').hasMatch(value)) {
    try {
      if (loadYaml(value) == value) return value;
    } on YamlException {
      // Version ranges starting with > and aliases such as * need quotes.
    }
  }
  return jsonEncode(value);
}
