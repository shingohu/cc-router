import 'dart:convert';

import 'package:ccrouter_generator/ccrouter_generator.dart';

void main() {
  const sizes = [10, 100, 500, 1000];
  for (final size in sizes) {
    final documents = [_document(size)];
    CCRouteWorkspaceValidator.validate(documents);
    final watch = Stopwatch()..start();
    final result = CCRouteWorkspaceValidator.validate(documents);
    watch.stop();
    if (result.errors.isNotEmpty) {
      throw StateError('Benchmark fixture is invalid: ${result.errors}');
    }
    print(
      jsonEncode({
        'routes': size,
        'validateMs': watch.elapsedMicroseconds / 1000,
        'machineDocumentBytes': utf8.encode(result.machineDocumentJson).length,
      }),
    );
  }
}

Map<String, Object?> _document(int routeCount) => <String, Object?>{
  'schemaVersion': 2,
  'package': 'benchmark_routes',
  'source': 'lib/routes.dart',
  'componentDeclarations': ['benchmark'],
  'componentManifests': {'benchmark': 'benchmarkManifest'},
  'components': [
    {
      'id': 'benchmark',
      'version': '1.0.0',
      'dependencies': <String>[],
      'optionalDependencies': <String>[],
    },
  ],
  'routes': [for (var index = 0; index < routeCount; index++) _route(index)],
  'routeImplementations': <Object>[],
};

Map<String, Object?> _route(int index) => <String, Object?>{
  'id': 'benchmark.route.$index',
  'componentId': 'benchmark',
  'exposure': 'internal',
  'deepLink': 'disabled',
  'description': 'Synthetic generator scaling route $index.',
  'declaration': {
    'package': 'benchmark_routes',
    'library': 'lib/routes.dart',
    'kind': 'page',
  },
  'navigationSources': ['typedIntent', 'internalUri'],
  'restoration': {'status': 'unsupported'},
  'placement': {
    'hostId': 'default',
    'parentRouteId': null,
    'shellId': null,
    'navigatorOutlet': 'root',
  },
  'presentation': {'type': 'page'},
  'contracts': {
    'route': 'BenchmarkRoute$index',
    'arguments': 'BenchmarkRoute${index}Arguments',
    'package': 'benchmark_routes',
    'library': 'lib/routes.dart',
  },
  'registration': 'ccrouterRegisterBenchmarkRoute$index',
  'destination': {
    'descriptor': 'ccrouterDescribeBenchmarkRoute$index',
    'builder': 'ccrouterBuildBenchmarkRoute$index',
  },
  'patterns': [
    {
      'type': 'CCPathPattern',
      'value': '/benchmark/$index/:id',
      'primary': true,
      'constraints': <String, String>{},
    },
  ],
  'parameters': [
    {
      'name': 'id',
      'wireName': 'id',
      'source': 'path',
      'type': 'int',
      'cardinality': null,
      'required': true,
      'description': 'Synthetic identity.',
    },
  ],
  'resultType': 'void',
};
