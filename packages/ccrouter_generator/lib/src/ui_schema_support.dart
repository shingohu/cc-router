part of 'ui_fragment_generator.dart';

/// Invocation-local subtype facts; never retains an Analyzer graph globally.
final class _DataSubtypeIndex {
  /// Starts an empty cache scoped to one Contract schema read.
  _DataSubtypeIndex();

  /// Each defining library is scanned once, including its part declarations.
  final _libraries =
      <LibraryElement, Map<InterfaceElement, List<InterfaceElement>>>{};

  /// Returns real class/interface edges, excluding erased extension-type views.
  List<InterfaceElement> subtypes(ClassElement root) =>
      (_libraries.putIfAbsent(root.library, () {
        final result = <InterfaceElement, List<InterfaceElement>>{};
        for (final candidate in <InterfaceElement>[
          ...root.library.classes,
          ...root.library.enums,
          ...root.library.mixins,
        ]) {
          final parents = <InterfaceElement>{
            if (candidate.supertype case final type?) type.element,
            ...candidate.interfaces.map((type) => type.element),
            ...candidate.mixins.map((type) => type.element),
          };
          for (final parent in parents) {
            if (parent.library == root.library) {
              result.putIfAbsent(parent, () => []).add(candidate);
            }
          }
        }
        for (final values in result.values) {
          values.sort((a, b) => a.displayName.compareTo(b.displayName));
        }
        return result;
      }))[root] ??
      const [];
}

/// Bounds legacy expansion and constant traversal without changing valid hashes.
final class _LegacySchemaBudget {
  /// Keeps schema and constant failures attributable to their input boundary.
  _LegacySchemaBudget({this.label = 'UI DTO schema'});

  /// Diagnostic prefix; the limits are validation bounds, not a wire format.
  final String label;

  /// Expanded nodes across both type schemas and effective constant values.
  int _nodes = 0;

  /// Fails before a repeated DAG can exhaust the Builder stack or heap.
  void visit(int depth, Element origin) {
    if (++_nodes > 16384 || depth >= 256) {
      _fail('$label exceeds 16384 expanded nodes or 256 data levels.', origin);
    }
  }
}
