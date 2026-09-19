import 'dart:convert';
import 'dart:io';

import 'package:ccrouter_generator/ccrouter_generator.dart';

Future<void> main(List<String> arguments) async {
  final parsed = _parseArguments(arguments);
  if (parsed.help) {
    stdout.writeln(_usage);
    return;
  }
  if (parsed.error != null) {
    stderr.writeln('error: ${parsed.error}');
    stderr.writeln(_usage);
    exitCode = 2;
    return;
  }

  final root = Directory(parsed.rootPath).absolute;
  final outputDirectory = Directory(
    parsed.outputDirectoryPath ??
        '${root.path}${Platform.pathSeparator}docs${Platform.pathSeparator}generated',
  ).absolute;
  final metadataFiles = <_MetadataFile>[];
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is! File ||
        (!entity.path.endsWith('.route.json') &&
            !entity.path.endsWith('.component.json'))) {
      continue;
    }
    if (entity.path.contains(
          '${Platform.pathSeparator}.dart_tool${Platform.pathSeparator}',
        ) ||
        entity.path.contains(
          '${Platform.pathSeparator}build${Platform.pathSeparator}',
        )) {
      continue;
    }
    final decoded = jsonDecode(await entity.readAsString());
    if (decoded is Map) {
      final document = decoded.cast<String, Object?>();
      final source = '${document['source'] ?? ''}';
      if (source.startsWith('test/') ||
          source.startsWith('generator_test/') ||
          source.startsWith('integration_test/')) {
        continue;
      }
      metadataFiles.add(_MetadataFile(entity, document));
    }
  }
  final documents = metadataFiles.map((entry) => entry.document).toList();
  final result = CCRouteWorkspaceValidator.validate(documents);
  final errors = [
    ...result.errors,
    ...CCRouteBarrelExportValidator.validate(root, documents),
  ]..sort();
  if (errors.isNotEmpty) {
    for (final error in errors) {
      stderr.writeln('error: $error');
    }
    exitCode = 1;
    return;
  }
  if (parsed.generateComponentRegistrars) {
    await _generateComponentRouteIndexes(metadataFiles);
  }
  await outputDirectory.create(recursive: true);
  await File(
    '${outputDirectory.path}${Platform.pathSeparator}cc_routes.json',
  ).writeAsString(result.machineDocumentJson);
  await File(
    '${outputDirectory.path}${Platform.pathSeparator}cc_routes.md',
  ).writeAsString(result.markdownDocument);
  stdout.writeln(
    'Validated ${result.machineDocument['components'] is List ? (result.machineDocument['components']! as List).length : 0} components and ${result.machineDocument['routes'] is List ? (result.machineDocument['routes']! as List).length : 0} routes.',
  );
}

const _usage =
    '''Usage: ccrouter_generator [scan-root] [--output-dir <directory>] [--generate-component-registrars]

Scans .component.json and .route.json files below scan-root and writes the aggregate route catalog
to scan-root/docs/generated unless --output-dir is provided. When
--generate-component-registrars is supplied, it also writes deterministic
component route indexes below each package's lib/src/ccrouter_generated.''';

final class _Arguments {
  const _Arguments({
    required this.rootPath,
    required this.outputDirectoryPath,
    this.generateComponentRegistrars = false,
    this.help = false,
    this.error,
  });

  final String rootPath;
  final String? outputDirectoryPath;
  final bool generateComponentRegistrars;
  final bool help;
  final String? error;
}

_Arguments _parseArguments(List<String> arguments) {
  var rootPath = Directory.current.path;
  String? outputDirectoryPath;
  var rootProvided = false;
  var generateComponentRegistrars = false;

  for (var index = 0; index < arguments.length; index++) {
    final argument = arguments[index];
    if (argument == '--help' || argument == '-h') {
      return const _Arguments(
        rootPath: '',
        outputDirectoryPath: null,
        help: true,
      );
    }
    if (argument == '--output-dir' || argument == '--output') {
      if (index + 1 >= arguments.length ||
          arguments[index + 1].startsWith('-')) {
        return const _Arguments(
          rootPath: '',
          outputDirectoryPath: null,
          error: 'Missing value for --output-dir.',
        );
      }
      outputDirectoryPath = arguments[++index];
      continue;
    }
    if (argument == '--generate-component-registrars') {
      generateComponentRegistrars = true;
      continue;
    }
    if (argument.startsWith('--output-dir=')) {
      outputDirectoryPath = argument.substring('--output-dir='.length);
      if (outputDirectoryPath.isEmpty) {
        return const _Arguments(
          rootPath: '',
          outputDirectoryPath: null,
          error: 'Missing value for --output-dir.',
        );
      }
      continue;
    }
    if (argument.startsWith('-')) {
      return _Arguments(
        rootPath: '',
        outputDirectoryPath: null,
        error: 'Unknown option: $argument',
      );
    }
    if (rootProvided) {
      return const _Arguments(
        rootPath: '',
        outputDirectoryPath: null,
        error: 'Only one scan root may be provided.',
      );
    }
    rootPath = argument;
    rootProvided = true;
  }

  return _Arguments(
    rootPath: rootPath,
    outputDirectoryPath: outputDirectoryPath,
    generateComponentRegistrars: generateComponentRegistrars,
  );
}

/// Associates one generated metadata document with its source file on disk.
final class _MetadataFile {
  /// Creates a metadata record used by workspace validation and codegen.
  const _MetadataFile(this.file, this.document);

  /// Generated JSON file containing [document].
  final File file;

  /// Decoded component or route metadata payload.
  final Map<String, Object?> document;
}

/// Writes one deterministic route index per component.
Future<void> _generateComponentRouteIndexes(
  Iterable<_MetadataFile> metadataFiles,
) async {
  final componentSources = <String, _ComponentSource>{};
  final routes = <String, List<_RouteRegistration>>{};
  for (final metadata in metadataFiles) {
    final document = metadata.document;
    final package = '${document['package'] ?? ''}';
    final source = '${document['source'] ?? ''}';
    for (final component in _objects(document['components'])) {
      final id = '${component['id']}';
      if (_strings(document['componentDeclarations']).contains(id)) {
        componentSources[id] = _ComponentSource(
          package: package,
          source: source,
          metadataFile: metadata.file,
        );
      }
    }
    for (final route in _objects(document['routes'])) {
      final componentId = '${route['componentId'] ?? ''}';
      final contracts = route['contracts'];
      final routeContract = contracts is Map
          ? '${contracts['route'] ?? ''}'
          : '';
      final registration = '${route['registration'] ?? ''}'.trim().isEmpty
          ? _registrationFromContract(routeContract)
          : '${route['registration']}';
      routes
          .putIfAbsent(componentId, () => [])
          .add(
            _RouteRegistration(
              package: package,
              source: source,
              routeId: '${route['id'] ?? ''}',
              registration: registration,
            ),
          );
    }
  }

  final componentIds = routes.keys.toList()..sort();
  for (final componentId in componentIds) {
    final component = componentSources[componentId];
    if (component == null) continue;
    final componentRoutes = routes[componentId]!..sort(_compareRoutes);
    final packageRoot = _findPackageRoot(component.metadataFile);
    if (packageRoot == null) continue;
    final outputDirectory = Directory(
      '${packageRoot.path}${Platform.pathSeparator}lib${Platform.pathSeparator}src${Platform.pathSeparator}ccrouter_generated',
    )..createSync(recursive: true);
    final output = File(
      '${outputDirectory.path}${Platform.pathSeparator}${_fileStem(componentId)}.routes.g.dart',
    );
    await output.writeAsString(
      _emitComponentRouteIndex(componentId, componentRoutes),
    );
  }
}

/// Generates a component registrar source with stable imports and ordering.
String _emitComponentRouteIndex(
  String componentId,
  List<_RouteRegistration> routes,
) {
  final className = _pascalIdentifier(componentId) + 'GeneratedRoutes';
  final constantName = '${className[0].toLowerCase()}${className.substring(1)}';
  final imports = <String, String>{};
  for (final route in routes) {
    imports.putIfAbsent(route.source, () => _sourceAlias(route.source));
  }
  final out = StringBuffer()
    ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND')
    ..writeln('// ignore_for_file: type=lint, unused_element')
    ..writeln()
    ..writeln("import 'package:ccrouter/ccrouter.dart';");
  for (final entry
      in imports.entries.toList()
        ..sort((left, right) => left.key.compareTo(right.key))) {
    final source = entry.key;
    final package = routes
        .firstWhere((route) => route.source == source)
        .package;
    out.writeln(
      "import 'package:$package/${source.substring('lib/'.length)}' as ${entry.value};",
    );
  }
  out
    ..writeln()
    ..writeln('/// Generated registration index for component `$componentId`.')
    ..writeln('final class $className {')
    ..writeln('  /// Creates the immutable component route index.')
    ..writeln('  const $className();')
    ..writeln()
    ..writeln(
      '  /// Registers every route owned by `$componentId` in stable order.',
    )
    ..writeln('  void register(CCRegistry registry) {');
  for (final route in routes) {
    final alias = imports[route.source]!;
    out.writeln('    $alias.${route.registration}(registry);');
  }
  out
    ..writeln('  }')
    ..writeln('}')
    ..writeln()
    ..writeln('/// Shared generated index used by the component Registrar.')
    ..writeln('const $constantName = $className();')
    ..writeln();
  return out.toString();
}

/// Finds a package root by walking up from one metadata file.
Directory? _findPackageRoot(File metadataFile) {
  var directory = metadataFile.parent;
  while (true) {
    if (File(
      '${directory.path}${Platform.pathSeparator}pubspec.yaml',
    ).existsSync()) {
      return directory;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) return null;
    directory = parent;
  }
}

/// Returns a stable Dart import alias for one package-relative source path.
String _sourceAlias(String source) =>
    'route_${source.substring('lib/'.length).replaceAll(RegExp(r'[^A-Za-z0-9]'), '_')}';

/// Converts a component ID into a valid generated Dart class stem.
String _pascalIdentifier(String value) => value
    .split(RegExp(r'[^A-Za-z0-9]+'))
    .where((part) => part.isNotEmpty)
    .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
    .join();

/// Converts a component ID into a stable generated file stem.
String _fileStem(String value) =>
    value.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');

/// Derives a bridge name for metadata generated before the registration field.
String _registrationFromContract(String contract) {
  final name = contract
      .replaceFirst(RegExp(r'^_'), '')
      .replaceFirst(RegExp(r'Route$'), '');
  return 'ccrouterRegister${name}Route';
}

/// Sorts route contributions independently of filesystem traversal order.
int _compareRoutes(_RouteRegistration left, _RouteRegistration right) {
  final source = left.source.compareTo(right.source);
  return source == 0 ? left.routeId.compareTo(right.routeId) : source;
}

/// Reads object arrays from loosely typed metadata safely.
Iterable<Map<String, Object?>> _objects(Object? value) sync* {
  if (value is! List) return;
  for (final item in value) {
    if (item is Map) yield item.cast<String, Object?>();
  }
}

/// Reads a string array from loosely typed metadata safely.
List<String> _strings(Object? value) => value is List
    ? value.whereType<Object>().map((item) => '$item').toList()
    : const [];

/// Describes the annotated component declaration that owns generated routes.
final class _ComponentSource {
  /// Creates a component source record.
  const _ComponentSource({
    required this.package,
    required this.source,
    required this.metadataFile,
  });

  /// Package name used by generated package imports.
  final String package;

  /// Component registrar source path relative to `lib/`.
  final String source;

  /// Metadata file used to locate the package root.
  final File metadataFile;
}

/// Describes one route contribution for a generated component index.
final class _RouteRegistration {
  /// Creates a normalized route contribution record.
  const _RouteRegistration({
    required this.package,
    required this.source,
    required this.routeId,
    required this.registration,
  });

  /// Package name used by generated package imports.
  final String package;

  /// Source library containing the generated registration bridge.
  final String source;

  /// Stable route ID used for deterministic sorting.
  final String routeId;

  /// Generated bridge symbol exposed only to package-internal code.
  final String registration;
}
