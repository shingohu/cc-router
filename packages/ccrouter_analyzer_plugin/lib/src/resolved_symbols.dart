import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

/// Internal shared symbol proof for diagnostics and source-preserving fixes.
/// Uses the current resolved unit only; it owns no analysis sessions or caches.
abstract final class CCRouterResolvedSymbols {
  /// Finds unambiguous references already visible in this library.
  /// Local declarations shadow unprefixed imports; reused prefixes are checked
  /// across all imports, including show/hide and transitive export namespaces.
  static Map<String, Element> references(CompilationUnit unit, String symbol) {
    final fragment = unit.declaredFragment;
    if (fragment == null) return const {};
    final library = fragment.element;
    final locals = <Element>[
      ...library.classes,
      ...library.enums,
      ...library.mixins,
      ...library.typeAliases,
      ...library.topLevelVariables,
      ...library.topLevelFunctions,
      ...library.extensions,
      ...library.extensionTypes,
    ];
    final declared = {
      for (final e in locals)
        if (e.name != null) e.name!: e,
    };
    final candidates = <String, Set<Element>>{};
    if (declared[symbol] case final local?) candidates[symbol] = {local};
    final deferredPrefixes = unit.directives
        .whereType<ImportDirective>()
        .where((directive) => directive.deferredKeyword != null)
        .map((directive) => directive.prefix?.name)
        .toSet();
    for (final import in fragment.libraryImports) {
      final prefix = import.prefix?.name;
      if (deferredPrefixes.contains(prefix)) continue;
      if (declared.containsKey(prefix ?? symbol)) continue;
      final reference = prefix == null ? symbol : '$prefix.$symbol';
      final element = import.namespace.get2(reference);
      if (element != null)
        candidates.putIfAbsent(reference, () => {}).add(element);
    }
    return {
      for (final e in candidates.entries)
        if (e.value.length == 1) e.key: e.value.single,
    };
  }

  /// Reads a resolved CCRouter owner constant, never a same-named foreign type.
  static String? componentId(Element? element) {
    final variable = switch (element) {
      PropertyAccessorElement e => e.variable,
      VariableElement e => e,
      _ => null,
    };
    final type = variable?.type;
    if (type is! InterfaceType ||
        !isFrameworkType(type, 'CCComponentId', 'component'))
      return null;
    return variable?.computeConstantValue()?.getField('value')?.toStringValue();
  }

  /// Proves framework identity from the declaring library rather than spelling.
  static bool isFrameworkType(InterfaceType type, String name, String file) =>
      type.element.name == name &&
      type.element.library.uri.toString() ==
          'package:ccrouter_contracts/src/$file.dart';
}
