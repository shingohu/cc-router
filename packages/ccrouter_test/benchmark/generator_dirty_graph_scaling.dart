import 'dart:convert';

import 'package:ccrouter_generator/ccrouter_generator.dart';
import 'package:ccrouter_generator/src/reverse_dependency_closure.dart';

/// Compares full Workspace validation with dirty Package graph propagation.
void main() {
  _benchmarkWorkspaceValidation();
  _benchmarkDirtyPropagation();
  _benchmarkRuntimeBundlePropagation();
  _benchmarkInitTaskOptionalReachability();
  _benchmarkRouteVisibilityClosure();
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

/// Measures Runtime Bundle forwarding on a reverse-ordered Package chain.
void _benchmarkRuntimeBundlePropagation() {
  for (final packageCount in const [100, 1000, 5000]) {
    final graph = <String, Set<String>>{
      for (var index = packageCount - 1; index >= 0; index--)
        'package_$index': {if (index > 0) 'package_${index - 1}'},
    };
    final referenceSamples = <int>[];
    final candidateSamples = <int>[];
    final expected = _fixedPointClosure(graph, const {'package_0'});
    for (var sample = 0; sample < (packageCount < 5000 ? 10 : 5); sample++) {
      final referenceWatch = Stopwatch()..start();
      final reference = _fixedPointClosure(graph, const {'package_0'});
      referenceWatch.stop();
      final candidateWatch = Stopwatch()..start();
      final candidate = CCReverseDependencyClosure.compute(
        dependenciesByNode: graph,
        seeds: const {'package_0'},
      );
      candidateWatch.stop();
      if (!_sameSet(reference, candidate)) {
        throw StateError('Runtime Bundle closure differs at $packageCount.');
      }
      referenceSamples.add(referenceWatch.elapsedMicroseconds);
      candidateSamples.add(candidateWatch.elapsedMicroseconds);
    }
    referenceSamples.sort();
    candidateSamples.sort();
    print(
      jsonEncode({
        'scenario': 'runtime-bundle-adversarial-chain',
        'packages': packageCount,
        'runtimePackages': expected.length,
        'referenceP50Us': _percentile(referenceSamples, 0.50),
        'referenceP95Us': _percentile(referenceSamples, 0.95),
        'candidateP50Us': _percentile(candidateSamples, 0.50),
        'candidateP95Us': _percentile(candidateSamples, 0.95),
      }),
    );
  }
}

/// Measures repeated optional-ancestor queries against one memoized DAG walk.
void _benchmarkInitTaskOptionalReachability() {
  _verifyInitTaskOptionalReachability();
  for (final taskCount in const [100, 500, 1000]) {
    final dependencies = <String, List<String>>{
      for (var index = 0; index < taskCount; index++)
        'task_$index': [if (index > 0) 'task_${index - 1}'],
    };
    final optionalTasks = const {'task_0'};
    final referenceSamples = <int>[];
    final candidateSamples = <int>[];
    for (var sample = 0; sample < (taskCount < 1000 ? 10 : 5); sample++) {
      final referenceWatch = Stopwatch()..start();
      final reference = <String, String?>{
        for (final id in dependencies.keys)
          id: _findOptionalReference(
            id,
            dependencies: dependencies,
            optionalTasks: optionalTasks,
            visiting: <String>{},
          ),
      };
      referenceWatch.stop();
      final candidateWatch = Stopwatch()..start();
      final candidate = _memoizedOptionalAncestors(dependencies, optionalTasks);
      candidateWatch.stop();
      if (!_sameNullableStringMap(reference, candidate)) {
        throw StateError(
          'InitTask optional reachability differs at $taskCount.',
        );
      }
      referenceSamples.add(referenceWatch.elapsedMicroseconds);
      candidateSamples.add(candidateWatch.elapsedMicroseconds);
    }
    referenceSamples.sort();
    candidateSamples.sort();
    print(
      jsonEncode({
        'scenario': 'init-task-optional-adversarial-chain',
        'tasks': taskCount,
        'referenceP50Us': _percentile(referenceSamples, 0.50),
        'referenceP95Us': _percentile(referenceSamples, 0.95),
        'candidateP50Us': _percentile(candidateSamples, 0.50),
        'candidateP95Us': _percentile(candidateSamples, 0.95),
      }),
    );
  }
}

/// Measures per-Route component closure walks against per-owner memoization.
void _benchmarkRouteVisibilityClosure() {
  const routesPerComponent = 20;
  for (final componentCount in const [100, 500, 1000]) {
    final dependencies = <String, List<String>>{
      for (var index = 0; index < componentCount; index++)
        'component_$index': [if (index > 0) 'component_${index - 1}'],
    };
    final routeOwners = <String>[
      for (var index = 0; index < componentCount; index++)
        for (var route = 0; route < routesPerComponent; route++)
          'component_$index',
    ];
    final exactCache = <String, Set<String>>{};
    for (final owner in dependencies.keys) {
      final reference = _transitiveDependenciesReference(owner, dependencies);
      final candidate = exactCache.putIfAbsent(
        owner,
        () => _transitiveDependenciesReference(owner, dependencies),
      );
      if (!_sameSet(reference, candidate)) {
        throw StateError(
          'Route visibility closure differs for $owner at '
          '$componentCount components.',
        );
      }
    }
    final referenceSamples = <int>[];
    final candidateSamples = <int>[];
    for (var sample = 0; sample < (componentCount < 1000 ? 10 : 5); sample++) {
      final referenceWatch = Stopwatch()..start();
      var referenceClosureEntries = 0;
      for (final owner in routeOwners) {
        referenceClosureEntries += _transitiveDependenciesReference(
          owner,
          dependencies,
        ).length;
      }
      referenceWatch.stop();
      final candidateWatch = Stopwatch()..start();
      final cache = <String, Set<String>>{};
      var candidateClosureEntries = 0;
      for (final owner in routeOwners) {
        candidateClosureEntries += cache
            .putIfAbsent(
              owner,
              () => _transitiveDependenciesReference(owner, dependencies),
            )
            .length;
      }
      candidateWatch.stop();
      if (referenceClosureEntries != candidateClosureEntries) {
        throw StateError(
          'Route visibility closure differs at $componentCount components.',
        );
      }
      referenceSamples.add(referenceWatch.elapsedMicroseconds);
      candidateSamples.add(candidateWatch.elapsedMicroseconds);
    }
    referenceSamples.sort();
    candidateSamples.sort();
    print(
      jsonEncode({
        'scenario': 'route-visibility-component-cache',
        'components': componentCount,
        'routes': routeOwners.length,
        'referenceP50Us': _percentile(referenceSamples, 0.50),
        'referenceP95Us': _percentile(referenceSamples, 0.95),
        'candidateP50Us': _percentile(candidateSamples, 0.50),
        'candidateP95Us': _percentile(candidateSamples, 0.95),
      }),
    );
  }
}

/// Verifies memoization against ordering, diamond, and missing-node cases.
void _verifyInitTaskOptionalReachability() {
  final fixtures = <Map<String, List<String>>>[
    {
      'required': ['first', 'second'],
      'first': ['shared'],
      'second': ['optional_second'],
      'shared': const [],
      'optional_second': const [],
    },
    {
      'required': ['optional_first', 'optional_second'],
      'optional_first': const [],
      'optional_second': const [],
    },
    {
      'left': ['shared_optional'],
      'right': ['shared_optional'],
      'shared_optional': const [],
      'missing_consumer': ['missing'],
    },
  ];
  final optionalTasks = {
    'optional_first',
    'optional_second',
    'shared_optional',
  };
  for (var fixtureIndex = 0; fixtureIndex < fixtures.length; fixtureIndex++) {
    final dependencies = fixtures[fixtureIndex];
    final reference = <String, String?>{
      for (final id in dependencies.keys)
        id: _findOptionalReference(
          id,
          dependencies: dependencies,
          optionalTasks: optionalTasks,
          visiting: <String>{},
        ),
    };
    final candidate = _memoizedOptionalAncestors(dependencies, optionalTasks);
    if (!_sameNullableStringMap(reference, candidate)) {
      throw StateError(
        'InitTask optional reachability fixture $fixtureIndex differs.',
      );
    }
  }
}

/// Reproduces the current recursive optional-ancestor lookup.
String? _findOptionalReference(
  String id, {
  required Map<String, List<String>> dependencies,
  required Set<String> optionalTasks,
  required Set<String> visiting,
}) {
  if (!visiting.add(id)) return null;
  if (!dependencies.containsKey(id)) return null;
  if (optionalTasks.contains(id)) return id;
  for (final dependency in dependencies[id]!) {
    final optional = _findOptionalReference(
      dependency,
      dependencies: dependencies,
      optionalTasks: optionalTasks,
      visiting: visiting,
    );
    if (optional != null) return optional;
  }
  return null;
}

/// Computes the first optional ancestor once per InitTask.
Map<String, String?> _memoizedOptionalAncestors(
  Map<String, List<String>> dependencies,
  Set<String> optionalTasks,
) {
  final cache = <String, String?>{};
  final visiting = <String>{};
  String? resolve(String id) {
    if (cache.containsKey(id)) return cache[id];
    if (!visiting.add(id)) return null;
    String? result;
    if (dependencies.containsKey(id)) {
      if (optionalTasks.contains(id)) {
        result = id;
      } else {
        for (final dependency in dependencies[id]!) {
          result = resolve(dependency);
          if (result != null) break;
        }
      }
    }
    visiting.remove(id);
    cache[id] = result;
    return result;
  }

  for (final id in dependencies.keys) {
    resolve(id);
  }
  return <String, String?>{for (final id in dependencies.keys) id: cache[id]};
}

/// Reproduces one component dependency closure walk.
Set<String> _transitiveDependenciesReference(
  String component,
  Map<String, List<String>> dependencies,
) {
  final found = <String>{};
  void visit(String id) {
    for (final dependency in dependencies[id] ?? const <String>[]) {
      if (dependencies.containsKey(dependency) && found.add(dependency)) {
        visit(dependency);
      }
    }
  }

  visit(component);
  return found;
}

/// Compares nullable lookup results by task identity.
bool _sameNullableStringMap(
  Map<String, String?> left,
  Map<String, String?> right,
) {
  if (left.length != right.length) return false;
  for (final entry in left.entries) {
    if (!right.containsKey(entry.key) || right[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
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
  final warmCandidate = CCReverseDependencyClosure.compute(
    dependenciesByNode: graph,
    seeds: seeds,
  );
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
    final candidate = CCReverseDependencyClosure.compute(
      dependenciesByNode: graph,
      seeds: seeds,
    );
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
