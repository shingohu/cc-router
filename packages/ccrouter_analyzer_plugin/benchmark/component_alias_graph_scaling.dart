import 'dart:convert';
import 'dart:io';

import 'package:ccrouter_analyzer_plugin/src/contract_owner_index.dart';
import 'package:ccrouter_analyzer_plugin/src/source_analyzer.dart';
import 'package:path/path.dart' as path;

/// Measures parser-only component-ID alias reachability at editor scale.
void main() {
  _verifyAliasGraphEquivalence();
  _benchmarkProductionAnalyzer();
  const queriesPerEdit = 20;
  for (final aliasCount in const [100, 500, 1000, 3000]) {
    final declarations = _reverseOrderedChain(aliasCount);
    final referenceSamples = <int>[];
    final candidateSamples = <int>[];
    for (var sample = 0; sample < (aliasCount < 3000 ? 20 : 10); sample++) {
      final referenceWatch = Stopwatch()..start();
      late Set<String> reference;
      for (var query = 0; query < queriesPerEdit; query++) {
        reference = _fixedPointAliases(
          declarations,
          ownerId: 'owner.component',
          visibleReference: 'ownerComponentId',
        );
        if (!reference.contains('alias_$aliasCount')) {
          throw StateError('Reference lost the terminal alias.');
        }
      }
      referenceWatch.stop();

      final candidateWatch = Stopwatch()..start();
      final graph = _AliasGraph(declarations);
      late Set<String> candidate;
      for (var query = 0; query < queriesPerEdit; query++) {
        candidate = graph.resolve(
          ownerId: 'owner.component',
          visibleReference: 'ownerComponentId',
        );
        if (!candidate.contains('alias_$aliasCount')) {
          throw StateError('Candidate lost the terminal alias.');
        }
      }
      candidateWatch.stop();
      if (!_sameSet(reference, candidate)) {
        throw StateError('Alias closure differs at $aliasCount aliases.');
      }
      referenceSamples.add(referenceWatch.elapsedMicroseconds);
      candidateSamples.add(candidateWatch.elapsedMicroseconds);
    }
    referenceSamples.sort();
    candidateSamples.sort();
    print(
      jsonEncode({
        'scenario': 'analyzer-component-alias-reverse-chain',
        'aliases': aliasCount,
        'queriesPerEdit': queriesPerEdit,
        'referenceP50Us': _percentile(referenceSamples, 0.50),
        'referenceP95Us': _percentile(referenceSamples, 0.95),
        'candidateP50Us': _percentile(candidateSamples, 0.50),
        'candidateP95Us': _percentile(candidateSamples, 0.95),
      }),
    );
  }
}

/// Measures the complete parser-only Analyzer path, including index creation.
void _benchmarkProductionAnalyzer() {
  final root = Directory.systemTemp.createTempSync(
    'ccrouter-analyzer-alias-bench-',
  );
  try {
    final sourcePath = path.join(root.path, 'lib', 'src', 'component.dart');
    final owners = CCRouterContractOwnerIndex(
      owners: const [
        CCRouterContractOwner(
          kind: CCRouterContractKind.service,
          contractSymbol: 'SharedService',
          contractPackage: 'alias_benchmark',
          componentId: 'owner.component',
          componentIdSymbol: 'ownerComponentId',
        ),
      ],
      packageRoots: const {},
    );
    for (final aliasCount in const [100, 500, 1000]) {
      final source = _productionSource(aliasCount);
      final samples = <int>[];
      for (var sample = 0; sample < 10; sample++) {
        final watch = Stopwatch()..start();
        final diagnostics = CCRouterSourceAnalyzer.analyze(
          source: source,
          filePath: sourcePath,
          packageRoot: root.path,
          packageName: 'alias_benchmark',
          contractOwners: owners,
        );
        watch.stop();
        if (diagnostics.any(
          (item) => item.code == 'ccrouter_component_owner_dependency_missing',
        )) {
          throw StateError('Production Analyzer lost the owner alias.');
        }
        samples.add(watch.elapsedMicroseconds);
      }
      samples.sort();
      print(
        jsonEncode({
          'scenario': 'analyzer-component-alias-production',
          'aliases': aliasCount,
          'queriesPerEdit': 20,
          'optimizationDisabled':
              Platform
                  .environment['CCROUTER_DISABLE_ANALYZER_COMPONENT_ALIAS_GRAPH'] ==
              '1',
          'p50Us': _percentile(samples, 0.50),
          'p95Us': _percentile(samples, 0.95),
        }),
      );
    }
  } finally {
    root.deleteSync(recursive: true);
  }
}

/// Creates a parsed component with an adversarial but valid alias chain.
String _productionSource(int aliasCount) {
  final source = StringBuffer()
    ..writeln("const ownerComponentId = CCComponentId('owner.component');");
  for (var index = aliasCount; index >= 1; index--) {
    source.writeln('const alias_$index = alias_${index - 1};');
  }
  source
    ..writeln('const alias_0 = ownerComponentId;')
    ..writeln('const consumerComponent = CCComponent(')
    ..writeln("  id: CCComponentId('consumer.component'),")
    ..writeln("  version: '1.0.0',")
    ..writeln('  dependencies: [alias_$aliasCount],')
    ..writeln('  serviceDependencies: [');
  for (var query = 0; query < 20; query++) {
    source.writeln('    CCServiceDependency<SharedService>(),');
  }
  source
    ..writeln('  ],')
    ..writeln(');');
  return source.toString();
}

/// Exercises ordering, literal seeds, unknown aliases, and disconnected cycles.
void _verifyAliasGraphEquivalence() {
  final fixtures = <List<_AliasDeclaration>>[
    _reverseOrderedChain(20),
    [
      const _AliasDeclaration(
        name: 'literal',
        literalOwnerId: 'owner.component',
      ),
      const _AliasDeclaration(name: 'forward', initializer: 'literal'),
      const _AliasDeclaration(name: 'unknown', initializer: 'external.value'),
    ],
    const [
      _AliasDeclaration(name: 'cycle_a', initializer: 'cycle_b'),
      _AliasDeclaration(name: 'cycle_b', initializer: 'cycle_a'),
      _AliasDeclaration(name: 'seeded', initializer: 'ownerComponentId'),
    ],
  ];
  for (var index = 0; index < fixtures.length; index++) {
    final reference = _fixedPointAliases(
      fixtures[index],
      ownerId: 'owner.component',
      visibleReference: 'ownerComponentId',
    );
    final candidate = _AliasGraph(
      fixtures[index],
    ).resolve(ownerId: 'owner.component', visibleReference: 'ownerComponentId');
    if (!_sameSet(reference, candidate)) {
      throw StateError('Alias fixture $index differs.');
    }
  }
}

/// Builds a chain whose declaration order advances one alias per full scan.
List<_AliasDeclaration> _reverseOrderedChain(int aliasCount) => [
  for (var index = aliasCount; index >= 1; index--)
    _AliasDeclaration(name: 'alias_$index', initializer: 'alias_${index - 1}'),
  const _AliasDeclaration(name: 'alias_0', initializer: 'ownerComponentId'),
];

/// Reproduces the current repeated declaration-scan fixed point.
Set<String> _fixedPointAliases(
  List<_AliasDeclaration> declarations, {
  required String ownerId,
  required String? visibleReference,
}) {
  final symbols = <String>{if (visibleReference != null) visibleReference};
  var changed = true;
  while (changed) {
    changed = false;
    for (final declaration in declarations) {
      final matchesOwner =
          (declaration.initializer != null &&
              symbols.contains(declaration.initializer)) ||
          declaration.literalOwnerId == ownerId;
      if (matchesOwner && symbols.add(declaration.name)) {
        changed = true;
      }
    }
  }
  return symbols;
}

/// Reverse alias graph built once for all dependency checks in one edit.
final class _AliasGraph {
  /// Indexes aliases by exact initializer spelling and literal owner value.
  _AliasGraph(List<_AliasDeclaration> declarations) {
    for (final declaration in declarations) {
      final initializer = declaration.initializer;
      if (initializer != null) {
        (_aliasesByInitializer[initializer] ??= <String>[]).add(
          declaration.name,
        );
      }
      final literalOwnerId = declaration.literalOwnerId;
      if (literalOwnerId != null) {
        (_aliasesByOwner[literalOwnerId] ??= <String>[]).add(declaration.name);
      }
    }
  }

  final Map<String, List<String>> _aliasesByInitializer = {};
  final Map<String, List<String>> _aliasesByOwner = {};
  final Map<(String, String?), Set<String>> _closureByOwner = {};

  /// Returns every alias proven equal to one owner identity.
  Set<String> resolve({
    required String ownerId,
    required String? visibleReference,
  }) => _closureByOwner.putIfAbsent((ownerId, visibleReference), () {
    final closure = <String>{if (visibleReference != null) visibleReference};
    final pending = <String>[...closure, ...?_aliasesByOwner[ownerId]];
    closure.addAll(pending);
    for (var cursor = 0; cursor < pending.length; cursor++) {
      for (final alias
          in _aliasesByInitializer[pending[cursor]] ?? const <String>[]) {
        if (closure.add(alias)) pending.add(alias);
      }
    }
    return Set.unmodifiable(closure);
  });
}

/// One const declaration relevant to parser-only component-ID aliases.
final class _AliasDeclaration {
  /// Creates an alias edge or a literal owner seed.
  const _AliasDeclaration({
    required this.name,
    this.initializer,
    this.literalOwnerId,
  });

  /// Declared top-level variable name.
  final String name;

  /// Exact initializer source for alias edges.
  final String? initializer;

  /// Stable component ID when the initializer is a direct literal.
  final String? literalOwnerId;
}

/// Selects the nearest-rank percentile from sorted microsecond samples.
int _percentile(List<int> sorted, double percentile) =>
    sorted[((sorted.length - 1) * percentile).ceil()];

/// Compares unordered alias closures exactly.
bool _sameSet(Set<String> left, Set<String> right) =>
    left.length == right.length && left.containsAll(right);
