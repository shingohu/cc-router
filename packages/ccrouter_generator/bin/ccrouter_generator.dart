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
  final documents = <Map<String, Object?>>[];
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is! File || !entity.path.endsWith('.ccroute.json')) continue;
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
      documents.add(document);
    }
  }
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
    '''Usage: ccrouter_generator [scan-root] [--output-dir <directory>]

Scans .ccroute.json files below scan-root and writes the aggregate route catalog
to scan-root/docs/generated unless --output-dir is provided.''';

final class _Arguments {
  const _Arguments({
    required this.rootPath,
    required this.outputDirectoryPath,
    this.help = false,
    this.error,
  });

  final String rootPath;
  final String? outputDirectoryPath;
  final bool help;
  final String? error;
}

_Arguments _parseArguments(List<String> arguments) {
  var rootPath = Directory.current.path;
  String? outputDirectoryPath;
  var rootProvided = false;

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
  );
}
