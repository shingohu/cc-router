import 'dart:convert';

/// Measures parser-only component-ID alias reachability at editor scale.
void main() {
  _verifyAliasGraphEquivalence();
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
