import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

/// Internal shared symbol proof for diagnostics and source-preserving fixes.
/// Uses the current resolved unit only; it owns no analysis sessions or caches.
abstract final class CCRouterResolvedSymbols {
  /// Canonical declaration libraries for supported framework annotations.
  static const _annotationLibraries = <String, String>{
    'CCRoute': 'route_annotation',
    'CCRouteContract': 'route_annotation',
    'CCRouteImplementation': 'route_annotation',
    'CCService': 'service',
    'CCServiceContract': 'service',
    'CCCommandContract': 'messaging',
    'CCCommandHandler': 'messaging',
    'CCEventContract': 'messaging',
    'CCEventSubscription': 'messaging',
    'CCInitTask': 'initialization',
    'CCComponentContribution': 'component',
    'CCUIFragmentContract': 'ui_fragment',
    'CCUIFragmentRenderer': 'ui_fragment',
  };

  /// Returns only a proven framework annotation identity, shared with fixes.
  /// Resolved foreign declarations always win over spelling. An unresolved
  /// buffer needs an exact public import and no visible competing namespace.
  static String? annotationName(Annotation annotation) {
    final element = annotation.element;
    final type = annotation.elementAnnotation?.computeConstantValue()?.type;
    final owner = element is ConstructorElement
        ? element.enclosingElement
        : type is InterfaceType
        ? type.element
        : null;
    if (owner != null) {
      final name = owner.name;
      final file = _annotationLibraries[name];
      return file != null &&
              owner.library.uri.toString() ==
                  'package:ccrouter_contracts/src/$file.dart'
          ? name
          : null;
    }
    if (element != null) return null;
    final unit = annotation.thisOrAncestorOfType<CompilationUnit>();
    if (unit == null) return null;
    final name = annotation.name;
    final (prefix, symbol) = switch (name) {
      SimpleIdentifier n => (null, n.name),
      PrefixedIdentifier n => (n.prefix.name, n.identifier.name),
      _ => (null, ''),
    };
    final file = _annotationLibraries[symbol];
    if (file == null) return null;
    if (unit.declaredFragment != null) {
      final resolved = references(unit, symbol)[name.toSource()];
      return resolved is InterfaceElement &&
              isFrameworkType(resolved.thisType, symbol, file)
          ? symbol
          : null;
    }
    if (unit.directives.any((d) => d is PartDirective || d is PartOfDirective))
      return null;
    for (final declaration in unit.declarations) {
      final names = switch (declaration) {
        TopLevelVariableDeclaration d => d.variables.variables.map(
          (v) => v.name.lexeme,
        ),
        NamedCompilationUnitMember d => [d.name.lexeme],
        ExtensionDeclaration d => [if (d.name != null) d.name!.lexeme],
        _ => const <String>[],
      };
      if (names.contains(prefix ?? symbol)) return null;
    }
    var found = false;
    for (final directive in unit.directives.whereType<ImportDirective>()) {
      if (directive.prefix?.name != prefix) continue;
      if (!directive.combinators.every(
        (c) => switch (c) {
          ShowCombinator c => c.shownNames.any((n) => n.name == symbol),
          HideCombinator c => !c.hiddenNames.any((n) => n.name == symbol),
        },
      ))
        continue;
      if (directive.configurations.isNotEmpty ||
          directive.deferredKeyword != null)
        return null;
      final uri = directive.uri.stringValue;
      if (_publicFrameworkLibraries.contains(uri)) {
        if (file == 'ui_fragment'
            ? _publicUILibraries.contains(uri)
            : !_publicUILibraries.contains(uri))
          found = true;
      } else if (uri == null || !uri.startsWith('dart:')) {
        return null;
      }
    }
    return found ? symbol : null;
  }

  /// Public libraries whose export boundaries are known without a new session.
  static const _publicFrameworkLibraries = {
    'package:ccrouter/ccrouter.dart',
    'package:ccrouter_contracts/ccrouter_contracts.dart',
    ..._publicUILibraries,
  };

  /// Explicit UI declaration barrels; ordinary CCRouter barrels omit UI types.
  static const _publicUILibraries = {
    'package:ccrouter_ui/ccrouter_ui.dart',
    'package:ccrouter_contracts/ccrouter_ui_contracts.dart',
  };

  /// Proves the invoked constructor identity, never a function's return type.
  /// Parser-only checks require an exact public import and no shadowing.
  static bool isFrameworkConstructor(
    Expression expression,
    String name,
    String file,
  ) {
    final element = switch (expression) {
      InstanceCreationExpression e => e.constructorName.element,
      MethodInvocation e => e.methodName.element,
      _ => null,
    };
    if (element != null) {
      return element is ConstructorElement &&
          isFrameworkType(element.enclosingElement.thisType, name, file);
    }
    final unit = expression.thisOrAncestorOfType<CompilationUnit>();
    if (unit == null || unit.declaredFragment != null) return false;
    final (prefix, symbol) = switch (expression) {
      InstanceCreationExpression e => (
        e.constructorName.type.importPrefix?.name.lexeme,
        e.constructorName.type.name.lexeme,
      ),
      MethodInvocation e when e.target == null => (null, e.methodName.name),
      MethodInvocation e when e.target is SimpleIdentifier => (
        (e.target as SimpleIdentifier).name,
        e.methodName.name,
      ),
      _ => (null, ''),
    };
    if (symbol != name ||
        unit.directives.any((d) => d is PartDirective || d is PartOfDirective))
      return false;
    if (unit.declarations.any(
      (d) => switch (d) {
        NamedCompilationUnitMember d => d.name.lexeme == (prefix ?? name),
        TopLevelVariableDeclaration d => d.variables.variables.any(
          (v) => v.name.lexeme == (prefix ?? name),
        ),
        _ => false,
      },
    ))
      return false;
    var found = false;
    for (final directive in unit.directives.whereType<ImportDirective>()) {
      if (directive.prefix?.name != prefix) continue;
      if (!directive.combinators.every(
        (c) => switch (c) {
          ShowCombinator c => c.shownNames.any((n) => n.name == name),
          HideCombinator c => !c.hiddenNames.any((n) => n.name == name),
        },
      ))
        continue;
      if (directive.configurations.isNotEmpty ||
          directive.deferredKeyword != null)
        return false;
      final uri = directive.uri.stringValue;
      if (_publicFrameworkLibraries.contains(uri)) {
        if (file == 'ui_fragment'
            ? _publicUILibraries.contains(uri)
            : !_publicUILibraries.contains(uri))
          found = true;
      } else if (uri == null || !uri.startsWith('dart:')) {
        return false;
      }
    }
    return found;
  }

  /// Reads arguments only after proving the canonical framework constructor.
  /// Resolved typedef aliases share the constructor identity of their target.
  static ArgumentList? constructorArguments(
    Expression expression,
    String name,
    String file,
  ) {
    if (!isFrameworkConstructor(expression, name, file)) return null;
    return switch (expression) {
      InstanceCreationExpression value => value.argumentList,
      MethodInvocation value => value.argumentList,
      _ => null,
    };
  }

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
