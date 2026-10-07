import 'dart:convert';

import 'package:ccrouter_generator/ccrouter_generator.dart';

/// Compares full Workspace validation with dirty Package graph propagation.
void main() {
  _benchmarkWorkspaceValidation();
  _benchmarkDirtyPropagation();
}

/// Measures the complete authoritative validator at realistic component scales.
void _benchmarkWorkspaceValidation() {
  for (final componentCount in const [6, 18, 30, 60, 120]) {
    final documents = [
      for (var index = 0; index < componentCount; index++)
        _componentDocument(index),
    ];
    final warm = CCRouteWorkspaceValidator.validate(documents);
    if (warm.errors.isNotEmpty) {
      throw StateError('Invalid validator fixture: ${warm.errors}');
    }
    final samples = <int>[];
    for (var sample = 0; sample < 20; sample++) {
      final watch = Stopwatch()..start();
      final result = CCRouteWorkspaceValidator.validate(documents);
      watch.stop();
      if (result.errors.isNotEmpty) {
        throw StateError('Validator fixture changed during measurement.');
      }
      samples.add(watch.elapsedMicroseconds);
    }
    samples.sort();
    print(
      jsonEncode({
        'scenario': 'workspace-validator-component-scale',
        'components': componentCount,
        'routes': componentCount * 5,
        'samples': samples.length,
        'p50Us': _percentile(samples, 0.50),
        'p95Us': _percentile(samples, 0.95),
      }),
    );
  }
}

/// Compares the current fixed-point closure with a reverse-adjacency queue.
void _benchmarkDirtyPropagation() {
  for (final packageCount in const [100, 1000, 5000, 10000]) {
    final workspaceLike = <String, Set<String>>{
      for (var index = 0; index < packageCount; index++)
        'package_$index': {
          if (index > 0) 'package_${index - 1}',
          if (index > 2) 'package_${index ~/ 2}',
        },
    };
    _measureDirtyPropagation(
      graph: <String, Set<String>>{
        for (final entry in workspaceLike.entries.toList().reversed)
          entry.key: entry.value,
      },
      scenario: 'dirty-package-workspace-like',
      packageCount: packageCount,
      samples: packageCount < 5000 ? 20 : 10,
    );
  }
  for (final packageCount in const [100, 1000, 5000]) {
    final chain = <String, Set<String>>{
      for (var index = 0; index < packageCount; index++)
        'package_$index': {if (index > 0) 'package_${index - 1}'},
    };
    _measureDirtyPropagation(
      graph: <String, Set<String>>{
        for (final entry in chain.entries.toList().reversed)
          entry.key: entry.value,
      },
      scenario: 'dirty-package-adversarial-chain',
      packageCount: packageCount,
      samples: packageCount < 5000 ? 10 : 5,
    );
  }
}

/// Measures both closure algorithms after warming their JIT paths.
void _measureDirtyPropagation({
  required Map<String, Set<String>> graph,
  required String scenario,
  required int packageCount,
  required int samples,
}) {
  final seeds = {'package_0'};
  final expected = _fixedPointClosure(graph, seeds);
  final warmCandidate = _reverseClosure(graph, seeds);
  if (!_sameSet(expected, warmCandidate) || expected.length != packageCount) {
    throw StateError('Dirty closure mismatch at $packageCount Packages.');
  }
  final fixedPointSamples = <int>[];
  final reverseClosureSamples = <int>[];
  for (var sample = 0; sample < samples; sample++) {
    final fixedPointWatch = Stopwatch()..start();
    final reference = _fixedPointClosure(graph, seeds);
    fixedPointWatch.stop();
    final reverseClosureWatch = Stopwatch()..start();
    final candidate = _reverseClosure(graph, seeds);
    reverseClosureWatch.stop();
    if (!_sameSet(reference, candidate)) {
      throw StateError(
        'Dirty closure changed during $scenario sample $sample.',
      );
    }
    fixedPointSamples.add(fixedPointWatch.elapsedMicroseconds);
    reverseClosureSamples.add(reverseClosureWatch.elapsedMicroseconds);
  }
  fixedPointSamples.sort();
  reverseClosureSamples.sort();
  print(
    jsonEncode({
      'scenario': scenario,
      'packages': packageCount,
      'edges': graph.values.fold<int>(
        0,
        (total, dependencies) => total + dependencies.length,
      ),
      'dirtyPackages': expected.length,
      'samples': samples,
      'fixedPointP50Us': _percentile(fixedPointSamples, 0.50),
      'fixedPointP95Us': _percentile(fixedPointSamples, 0.95),
      'reverseClosureP50Us': _percentile(reverseClosureSamples, 0.50),
      'reverseClosureP95Us': _percentile(reverseClosureSamples, 0.95),
    }),
  );
}

/// Reproduces the production fixed-point dirty propagation before optimization.
Set<String> _fixedPointClosure(
  Map<String, Set<String>> dependenciesByPackage,
  Set<String> seeds,
) {
  final dirty = <String>{...seeds};
  var changed = true;
  while (changed) {
    changed = false;
    for (final entry in dependenciesByPackage.entries) {
      if (dirty.contains(entry.key)) continue;
      if (entry.value.any(dirty.contains)) {
        dirty.add(entry.key);
        changed = true;
      }
    }
  }
  return dirty;
}

/// Candidate O(V+E) reverse dependency closure used only for comparison.
Set<String> _reverseClosure(
  Map<String, Set<String>> dependenciesByPackage,
  Set<String> seeds,
) {
  final dependents = <String, Set<String>>{
    for (final package in dependenciesByPackage.keys) package: <String>{},
  };
  for (final entry in dependenciesByPackage.entries) {
    for (final dependency in entry.value) {
      dependents[dependency]?.add(entry.key);
    }
  }
  final dirty = <String>{
    for (final seed in seeds)
      if (dependenciesByPackage.containsKey(seed)) seed,
  };
  final pending = dirty.toList(growable: true);
  for (var cursor = 0; cursor < pending.length; cursor++) {
    for (final dependent in dependents[pending[cursor]] ?? const <String>{}) {
      if (dirty.add(dependent)) pending.add(dependent);
    }
  }
  return dirty;
}

/// Creates one valid component Package with five internal Routes.
Map<String, Object?> _componentDocument(int index) {
  final componentId = 'component_$index';
  return <String, Object?>{
    'schemaVersion': 2,
    'package': 'package_$index',
    'source': 'lib/src/component.dart',
    'componentDeclarations': [componentId],
    'componentManifests': {componentId: 'componentManifest$index'},
    'components': [
      {
        'id': componentId,
        'version': '1.0.0',
        'dependencies': [if (index > 0) 'component_${index - 1}'],
        'optionalDependencies': <String>[],
      },
    ],
    'routes': [
      for (var route = 0; route < 5; route++) _route(componentId, index, route),
    ],
    'routeImplementations': <Object>[],
  };
}

/// Creates one unique internal Route metadata record.
Map<String, Object?> _route(String componentId, int component, int route) =>
    <String, Object?>{
      'id': '$componentId.route_$route',
      'componentId': componentId,
      'exposure': 'internal',
      'deepLink': 'disabled',
      'description': 'Synthetic graph benchmark route.',
      'declaration': {
        'package': 'package_$component',
        'library': 'lib/src/routes.dart',
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
        'route': 'Route${component}_$route',
        'arguments': 'Route${component}_${route}Arguments',
        'package': 'package_$component',
        'library': 'lib/src/routes.dart',
      },
      'registration': 'registerRoute${component}_$route',
      'destination': {
        'descriptor': 'describeRoute${component}_$route',
        'builder': 'buildRoute${component}_$route',
      },
      'patterns': [
        {
          'type': 'CCPathPattern',
          'value': '/component/$component/route/$route/:id',
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

/// Selects one nearest-rank percentile from sorted microseconds.
int _percentile(List<int> sorted, double percentile) =>
    sorted[((sorted.length - 1) * percentile).ceil()];

/// Compares unordered closure identities.
bool _sameSet(Set<String> left, Set<String> right) =>
    left.length == right.length && left.containsAll(right);
