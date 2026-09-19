import 'dart:convert';
import 'dart:io';

import 'package:ccrouter_generator/ccrouter_generator.dart';

Future<void> main(List<String> arguments) async {
  final root = Directory(
    arguments.isEmpty ? Directory.current.path : arguments.first,
  );
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
  if (!result.isValid) {
    for (final error in result.errors) {
      stderr.writeln('error: $error');
    }
    exitCode = 1;
    return;
  }
  await File(
    '${root.path}${Platform.pathSeparator}CCRouter-routes.json',
  ).writeAsString(result.machineDocumentJson);
  await File(
    '${root.path}${Platform.pathSeparator}CCRouter-routes.md',
  ).writeAsString(result.markdownDocument);
  stdout.writeln(
    'Validated ${result.machineDocument['components'] is List ? (result.machineDocument['components']! as List).length : 0} components and ${result.machineDocument['routes'] is List ? (result.machineDocument['routes']! as List).length : 0} routes.',
  );
}
