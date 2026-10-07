/// Computes dependency invalidation without repeatedly scanning the full graph.
///
/// This internal utility preserves every seed, including identities outside
/// [dependenciesByNode], because a known node may still depend on an external
/// dirty identity. Only nodes declared as map keys can be added transitively.
abstract final class CCReverseDependencyClosure {
  /// Returns all [seeds] and their transitive dependents in O(V + E) time.
  ///
  /// Cycles and duplicate edges are safe. The returned set is immutable and
  /// its iteration order is not a public ordering contract.
  static Set<String> compute({
    required Map<String, Iterable<String>> dependenciesByNode,
    required Iterable<String> seeds,
  }) {
    final dependentsByNode = <String, List<String>>{};
    for (final entry in dependenciesByNode.entries) {
      for (final dependency in entry.value) {
        (dependentsByNode[dependency] ??= <String>[]).add(entry.key);
      }
    }

    final closure = <String>{...seeds};
    final pending = closure.toList(growable: true);
    for (var cursor = 0; cursor < pending.length; cursor++) {
      for (final dependent
          in dependentsByNode[pending[cursor]] ?? const <String>[]) {
        if (closure.add(dependent)) pending.add(dependent);
      }
    }
    return Set.unmodifiable(closure);
  }
}
