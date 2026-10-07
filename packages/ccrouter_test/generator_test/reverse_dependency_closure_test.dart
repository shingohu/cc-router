import 'dart:math';

import 'package:ccrouter_generator/src/reverse_dependency_closure.dart';
import 'package:test/test.dart';

void main() {
  test('finds chain, diamond, cycle, and disconnected dependents', () {
    final closure = CCReverseDependencyClosure.compute(
      dependenciesByNode: {
        'chain-a': <String>{},
        'chain-b': {'chain-a'},
        'diamond-left': {'chain-b'},
        'diamond-right': {'chain-b'},
        'diamond-end': {'diamond-left', 'diamond-right'},
        'cycle-a': {'diamond-end', 'cycle-b'},
        'cycle-b': {'cycle-a'},
        'disconnected': <String>{},
      },
      seeds: const {'chain-a'},
    );

    expect(
      closure,
      equals({
        'chain-a',
        'chain-b',
        'diamond-left',
        'diamond-right',
        'diamond-end',
        'cycle-a',
        'cycle-b',
      }),
    );
    expect(() => closure.add('mutated'), throwsUnsupportedError);
  });

  test('preserves unknown seeds and propagates their known dependents', () {
    final closure = CCReverseDependencyClosure.compute(
      dependenciesByNode: {
        'known': {'external'},
        'downstream': {'known'},
        'unrelated': <String>{},
      },
      seeds: const {'external', 'missing'},
    );

    expect(closure, equals({'external', 'missing', 'known', 'downstream'}));
  });

  test('matches fixed-point reference across deterministic random graphs', () {
    final random = Random(0xCC42);
    for (var iteration = 0; iteration < 240; iteration++) {
      final nodeCount = 1 + random.nextInt(80);
      final nodes = [for (var index = 0; index < nodeCount; index++) 'n$index'];
      final graph = <String, Set<String>>{
        for (final node in nodes) node: <String>{},
      };
      for (final node in nodes) {
        final dependencies = graph[node]!;
        final edgeAttempts = random.nextInt(8);
        for (var edge = 0; edge < edgeAttempts; edge++) {
          dependencies.add(
            random.nextInt(10) == 0
                ? 'external_${random.nextInt(4)}'
                : nodes[random.nextInt(nodes.length)],
          );
        }
      }
      final seeds = <String>{
        for (final node in nodes)
          if (random.nextInt(12) == 0) node,
        if (random.nextBool()) 'external_${random.nextInt(4)}',
      };

      final expected = _fixedPointClosure(graph, seeds);
      final actual = CCReverseDependencyClosure.compute(
        dependenciesByNode: graph,
        seeds: seeds,
      );

      expect(actual, equals(expected), reason: 'iteration $iteration');
    }
  });
}

Set<String> _fixedPointClosure(
  Map<String, Set<String>> dependenciesByNode,
  Set<String> seeds,
) {
  final dirty = <String>{...seeds};
  var changed = true;
  while (changed) {
    changed = false;
    for (final entry in dependenciesByNode.entries) {
      if (dirty.contains(entry.key)) continue;
      if (entry.value.any(dirty.contains)) {
        dirty.add(entry.key);
        changed = true;
      }
    }
  }
  return dirty;
}
