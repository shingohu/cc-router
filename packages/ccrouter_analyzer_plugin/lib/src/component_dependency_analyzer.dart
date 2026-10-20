import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:ccrouter_analyzer_plugin/src/contract_owner_index.dart';
import 'resolved_symbols.dart';

/// Restores repeated parser-only alias scans for differential diagnosis.
const String _componentAliasGraphKillSwitch =
    'CCROUTER_DISABLE_ANALYZER_COMPONENT_ALIAS_GRAPH';

/// One metadata-proven required owner missing from a component descriptor.
final class CCRouterMissingComponentDependency {
  /// Creates a source-anchored missing-owner result.
  const CCRouterMissingComponentDependency({
    required this.offset,
    required this.length,
    required this.owner,
    required this.contractKind,
    required this.contractSymbol,
  });

  /// Offset of the Service, Command or UI dependency that requires the owner.
  final int offset;

  /// Source length of the dependency expression highlighted by the IDE.
  final int length;

  /// Exact owner recovered from generated Package metadata.
  final CCRouterContractOwner owner;

  /// Whether the consumer is a Service, Command or UI dependency.
  final CCRouterContractKind contractKind;

  /// Authored Contract type that caused the missing edge.
  final String contractSymbol;
}

/// Performs conservative component dependency checks over one parsed file.
///
/// Only direct top-level `CCComponent(...)` descriptors are considered. A
/// missing or direct list-literal `dependencies` argument is verifiable;
/// variables, spreads, conditionals, and computed collections are left to the
/// authoritative Generator so incomplete editor buffers cannot cause false
/// positives.
abstract final class CCRouterComponentDependencyAnalyzer {
  /// Finds required owner IDs omitted from direct component dependency lists.
  static List<CCRouterMissingComponentDependency> findMissing({
    required CompilationUnit unit,
    required String sourcePackage,
    required CCRouterContractOwnerIndex owners,
    String? sourcePath,
  }) {
    final importPrefixes = _importPrefixes(unit);
    final aliasIndex =
        unit.declaredFragment == null &&
            Platform.environment[_componentAliasGraphKillSwitch] != '1'
        ? _LocalComponentAliasIndex(unit)
        : null;
    final missing = <CCRouterMissingComponentDependency>[];
    for (final declaration
        in unit.declarations.whereType<TopLevelVariableDeclaration>()) {
      for (final variable in declaration.variables.variables) {
        final initializer = variable.initializer;
        final arguments = unit.declaredFragment != null && initializer != null
            ? CCRouterResolvedSymbols.constructorArguments(
                initializer,
                'CCComponent',
                'component',
              )?.arguments
            : _constructorArguments(initializer, 'CCComponent');
        if (arguments == null) continue;
        final dependencies = _namedArgument(arguments, 'dependencies');
        if (dependencies != null && dependencies is! ListLiteral) {
          continue;
        }
        if (dependencies is ListLiteral &&
            dependencies.elements.any((element) => element is! Expression)) {
          continue;
        }
        final required = dependencies is ListLiteral
            ? dependencies.elements.whereType<Expression>().toList(
                growable: false,
              )
            : const <Expression>[];
        final ownerIds = <String>{};
        for (final field in const <(String, CCRouterContractKind)>[
          ('serviceDependencies', CCRouterContractKind.service),
          ('commandDependencies', CCRouterContractKind.command),
          ('uiDependencies', CCRouterContractKind.uiFragment),
        ]) {
          if (field.$2 == CCRouterContractKind.uiFragment &&
              !CCRouterResolvedSymbols.isFrameworkConstructor(
                variable.initializer!,
                'CCComponent',
                'component',
              ))
            continue;
          final value = _namedArgument(arguments, field.$1);
          if (value is! ListLiteral) continue;
          for (final element in value.elements.whereType<Expression>()) {
            final type = _dependencyContract(element, field.$2);
            if (type == null) continue;
            final owner = unit.declaredFragment != null
                ? owners.resolveType(field.$2, type.$3)
                : owners.resolve(
                    kind: field.$2,
                    contractSymbol: type.$1,
                    prefix: type.$2,
                    importPrefixes: importPrefixes,
                    sourcePackage: sourcePackage,
                  );
            // UI self-consumption is invalid in the Generator. Never suggest
            // repairing it with a self dependency, which would introduce a cycle.
            final consumerId = _namedArgument(arguments, 'id');
            if (field.$2 == CCRouterContractKind.uiFragment &&
                owner != null &&
                consumerId != null &&
                (unit.declaredFragment != null
                        ? _resolvedComponentId(consumerId)
                        : _localLiteral(unit, consumerId, {})) ==
                    owner.componentId)
              continue;
            if (owner == null ||
                _containsOwner(
                      unit,
                      required,
                      owner,
                      owners,
                      sourcePath,
                      aliasIndex,
                    ) !=
                    false ||
                !ownerIds.add(owner.componentId)) {
              continue;
            }
            missing.add(
              CCRouterMissingComponentDependency(
                offset: element.offset,
                length: element.length,
                owner: owner,
                contractKind: field.$2,
                contractSymbol: type.$1,
              ),
            );
          }
        }
      }
    }
    return List.unmodifiable(missing);
  }

  /// Maps each source import prefix to the Package names it can expose.
  static Map<String, Set<String>> _importPrefixes(CompilationUnit unit) {
    final result = <String, Set<String>>{};
    for (final directive in unit.directives.whereType<ImportDirective>()) {
      final uri = directive.uri.stringValue;
      final parsed = uri == null ? null : Uri.tryParse(uri);
      if (parsed == null || parsed.scheme != 'package') continue;
      final segments = parsed.pathSegments;
      if (segments.isEmpty) continue;
      final prefix = directive.prefix?.name ?? '';
      result.putIfAbsent(prefix, () => <String>{}).add(segments.first);
    }
    return result;
  }

  /// Checks a direct dependency list for the exact owner value or symbol.
  static bool? _containsOwner(
    CompilationUnit unit,
    List<Expression> dependencies,
    CCRouterContractOwner owner,
    CCRouterContractOwnerIndex owners,
    String? sourcePath,
    _LocalComponentAliasIndex? aliasIndex,
  ) {
    if (unit.declaredFragment != null) {
      final values = dependencies.map(_resolvedComponentId).toList();
      if (values.contains(owner.componentId)) return true;
      return values.contains(null) ? null : false;
    }
    final symbols = <String>{};
    if (sourcePath != null) {
      final reference = owners.visibleComponentIdReference(
        unit: unit,
        sourcePath: sourcePath,
        owner: owner,
      );
      if (reference != null) symbols.add(reference);
    }
    if (aliasIndex != null) {
      return aliasIndex.containsOwner(
        dependencies,
        ownerId: owner.componentId,
        visibleReference: symbols.singleOrNull,
      );
    }
    var changed = true;
    while (changed) {
      changed = false;
      for (final declaration
          in unit.declarations.whereType<TopLevelVariableDeclaration>()) {
        if (!declaration.variables.isConst) continue;
        for (final variable in declaration.variables.variables) {
          final initializer = variable.initializer;
          if (initializer != null &&
              (symbols.contains(initializer.toSource()) ||
                  _componentIdLiteral(initializer) == owner.componentId) &&
              symbols.add(variable.name.lexeme)) {
            changed = true;
          }
        }
      }
    }
    for (final dependency in dependencies) {
      if (_componentIdLiteral(dependency) == owner.componentId) return true;
      if (symbols.contains(dependency.toSource())) {
        return true;
      }
    }
    // An unresolved imported/computed value is not proof of a missing owner.
    return dependencies.any((entry) => _localLiteral(unit, entry, {}) == null)
        ? null
        : false;
  }

  /// Follows same-file const aliases without treating unknown imports as values.
  static String? _localLiteral(
    CompilationUnit unit,
    Expression expression,
    Set<String> visiting,
  ) {
    final direct = _componentIdLiteral(expression);
    if (direct != null) return direct;
    if (expression is! SimpleIdentifier || !visiting.add(expression.name))
      return null;
    for (final declaration
        in unit.declarations.whereType<TopLevelVariableDeclaration>()) {
      if (!declaration.variables.isConst) continue;
      for (final variable in declaration.variables.variables) {
        if (variable.name.lexeme == expression.name &&
            variable.initializer != null) {
          return _localLiteral(unit, variable.initializer!, visiting);
        }
      }
    }
    return null;
  }

  /// Reads only typed constant owner identities, including imported const aliases.
  static String? _resolvedComponentId(Expression expression) {
    final type = expression.staticType;
    if (type is! InterfaceType ||
        type.element.name != 'CCComponentId' ||
        type.element.library.uri.toString() !=
            'package:ccrouter_contracts/src/component.dart')
      return null;
    final element = switch (expression) {
      SimpleIdentifier e => e.element,
      PrefixedIdentifier e => e.identifier.element,
      PropertyAccess e => e.propertyName.element,
      _ => null,
    };
    final variable = switch (element) {
      PropertyAccessorElement e => e.variable,
      VariableElement e => e,
      _ => null,
    };
    if (variable != null)
      return variable
          .computeConstantValue()
          ?.getField('value')
          ?.toStringValue();
    return _componentIdLiteral(expression);
  }

  /// Reads one Contract type and its optional source import prefix.
  static (String, String?, DartType?)? _dependencyContract(
    Expression expression,
    CCRouterContractKind kind,
  ) {
    final expected = switch (kind) {
      CCRouterContractKind.service => 'CCServiceDependency',
      CCRouterContractKind.command => 'CCCommandDependency',
      CCRouterContractKind.uiFragment => 'CCUIFragmentDependency',
    };
    if (kind == CCRouterContractKind.uiFragment &&
        !CCRouterResolvedSymbols.isFrameworkConstructor(
          expression,
          expected,
          'ui_fragment',
        ))
      return null;
    // Resolved constructor aliases may rename or bind the type parameters.
    // Read the instantiated dependency type after canonical constructor proof.
    if (kind == CCRouterContractKind.uiFragment &&
        expression.thisOrAncestorOfType<CompilationUnit>()?.declaredFragment !=
            null) {
      final dependency = expression.staticType;
      if (dependency is! InterfaceType || dependency.typeArguments.length != 1)
        return null;
      final contract = dependency.typeArguments.single;
      if (contract is! InterfaceType) return null;
      return (contract.element.name ?? '', null, contract);
    }
    final typeArguments = switch (expression) {
      InstanceCreationExpression value
          when value.constructorName.type.name.lexeme == expected =>
        value.constructorName.type.typeArguments?.arguments,
      MethodInvocation value
          when value.target == null && value.methodName.name == expected =>
        value.typeArguments?.arguments,
      _ => null,
    };
    if (typeArguments == null || typeArguments.length != 1) return null;
    final contract = typeArguments.single;
    if (contract is! NamedType) return null;
    return (
      contract.name.lexeme,
      contract.importPrefix?.name.lexeme,
      contract.type,
    );
  }

  /// Returns arguments from one unresolved constructor-shaped invocation.
  static NodeList<Expression>? _constructorArguments(
    Expression? expression,
    String typeName,
  ) => switch (expression) {
    InstanceCreationExpression value
        when value.constructorName.type.name.lexeme == typeName =>
      value.argumentList.arguments,
    MethodInvocation value
        when value.target == null && value.methodName.name == typeName =>
      value.argumentList.arguments,
    _ => null,
  };

  /// Reads one named constructor argument.
  static Expression? _namedArgument(
    NodeList<Expression> arguments,
    String name,
  ) {
    for (final argument in arguments.whereType<NamedExpression>()) {
      if (argument.name.label.name == name) return argument.expression;
    }
    return null;
  }

  /// Reads a direct stable component ID literal.
  static String? _componentIdLiteral(Expression expression) {
    final arguments = _constructorArguments(expression, 'CCComponentId');
    if (arguments == null || arguments.length != 1) return null;
    final value = arguments.single;
    return value is SimpleStringLiteral ? value.value : null;
  }
}

/// Parser-only const-alias index shared by all dependency checks in one unit.
final class _LocalComponentAliasIndex {
  /// Indexes exact initializer spellings and direct component-ID literals.
  _LocalComponentAliasIndex(CompilationUnit unit) {
    for (final declaration
        in unit.declarations.whereType<TopLevelVariableDeclaration>()) {
      if (!declaration.variables.isConst) continue;
      for (final variable in declaration.variables.variables) {
        final initializer = variable.initializer;
        if (initializer == null) continue;
        final name = variable.name.lexeme;
        _firstInitializerByName.putIfAbsent(name, () => initializer);
        (_aliasesByInitializer[initializer.toSource()] ??= <String>[]).add(
          name,
        );
        final ownerId = CCRouterComponentDependencyAnalyzer._componentIdLiteral(
          initializer,
        );
        if (ownerId != null) {
          (_aliasesByOwner[ownerId] ??= <String>[]).add(name);
        }
      }
    }
  }

  /// Exact alias edges keyed by initializer source text.
  final Map<String, List<String>> _aliasesByInitializer = {};

  /// Direct literal aliases keyed by stable component ID.
  final Map<String, List<String>> _aliasesByOwner = {};

  /// First initializer for each name, matching the legacy declaration walk.
  final Map<String, Expression> _firstInitializerByName = {};

  /// Reachable aliases memoized by owner identity and visible source symbol.
  final Map<(String, String?), Set<String>> _closureByOwner = {};

  /// Resolved local literal values, including cached unknown aliases.
  final Map<String, String?> _localLiteralByName = {};

  /// Checks whether [dependencies] prove the exact required [ownerId].
  ///
  /// Returns `null` when any dependency remains imported, computed, or cyclic,
  /// preserving the Generator-authoritative fallback used by the legacy walk.
  bool? containsOwner(
    List<Expression> dependencies, {
    required String ownerId,
    required String? visibleReference,
  }) {
    final symbols = _aliasesFor(
      ownerId: ownerId,
      visibleReference: visibleReference,
    );
    for (final dependency in dependencies) {
      if (CCRouterComponentDependencyAnalyzer._componentIdLiteral(dependency) ==
              ownerId ||
          symbols.contains(dependency.toSource())) {
        return true;
      }
    }
    return dependencies.any((entry) => _localLiteral(entry, <String>{}) == null)
        ? null
        : false;
  }

  /// Returns the complete exact-source alias closure for one owner.
  Set<String> _aliasesFor({
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

  /// Resolves same-file simple aliases without guessing computed expressions.
  String? _localLiteral(Expression expression, Set<String> visiting) {
    final direct = CCRouterComponentDependencyAnalyzer._componentIdLiteral(
      expression,
    );
    if (direct != null) return direct;
    if (expression is! SimpleIdentifier) return null;
    final name = expression.name;
    if (_localLiteralByName.containsKey(name)) {
      return _localLiteralByName[name];
    }
    if (!visiting.add(name)) return null;
    final initializer = _firstInitializerByName[name];
    final result = initializer == null
        ? null
        : _localLiteral(initializer, visiting);
    visiting.remove(name);
    _localLiteralByName[name] = result;
    return result;
  }
}
