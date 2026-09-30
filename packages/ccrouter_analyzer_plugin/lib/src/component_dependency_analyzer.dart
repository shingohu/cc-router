import 'package:analyzer/dart/ast/ast.dart';
import 'package:ccrouter_analyzer_plugin/src/contract_owner_index.dart';

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

  /// Offset of the Service or Command dependency that requires the owner.
  final int offset;

  /// Source length of the dependency expression highlighted by the IDE.
  final int length;

  /// Exact owner recovered from generated Package metadata.
  final CCRouterContractOwner owner;

  /// Whether the consumer is a Service or Command dependency.
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
  }) {
    final importPrefixes = _importPrefixes(unit);
    final missing = <CCRouterMissingComponentDependency>[];
    for (final declaration
        in unit.declarations.whereType<TopLevelVariableDeclaration>()) {
      for (final variable in declaration.variables.variables) {
        final arguments = _constructorArguments(
          variable.initializer,
          'CCComponent',
        );
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
        ]) {
          final value = _namedArgument(arguments, field.$1);
          if (value is! ListLiteral) continue;
          for (final element in value.elements.whereType<Expression>()) {
            final type = _dependencyContract(element, field.$2);
            if (type == null) continue;
            final owner = owners.resolve(
              kind: field.$2,
              contractSymbol: type.$1,
              prefix: type.$2,
              importPrefixes: importPrefixes,
              sourcePackage: sourcePackage,
            );
            if (owner == null ||
                _containsOwner(unit, required, owner) ||
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
  static bool _containsOwner(
    CompilationUnit unit,
    List<Expression> dependencies,
    CCRouterContractOwner owner,
  ) {
    final symbols = <String>{};
    if (owner.componentIdSymbol case final symbol?) symbols.add(symbol);
    var changed = true;
    while (changed) {
      changed = false;
      for (final declaration
          in unit.declarations.whereType<TopLevelVariableDeclaration>()) {
        if (!declaration.variables.isConst) continue;
        for (final variable in declaration.variables.variables) {
          final initializer = variable.initializer;
          if (initializer != null &&
              symbols.contains(_terminalIdentifier(initializer)) &&
              symbols.add(variable.name.lexeme)) {
            changed = true;
          }
        }
      }
    }
    for (final dependency in dependencies) {
      if (_componentIdLiteral(dependency) == owner.componentId) return true;
      if (symbols.contains(_terminalIdentifier(dependency))) {
        return true;
      }
    }
    return false;
  }

  /// Reads one Contract type and its optional source import prefix.
  static (String, String?)? _dependencyContract(
    Expression expression,
    CCRouterContractKind kind,
  ) {
    final expected = kind == CCRouterContractKind.service
        ? 'CCServiceDependency'
        : 'CCCommandDependency';
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
    return (contract.name.lexeme, contract.importPrefix?.name.lexeme);
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

  /// Returns the last identifier of a direct dependency expression.
  static String? _terminalIdentifier(Expression expression) =>
      switch (expression) {
        SimpleIdentifier value => value.name,
        PrefixedIdentifier value => value.identifier.name,
        PropertyAccess value => value.propertyName.name,
        _ => null,
      };
}
