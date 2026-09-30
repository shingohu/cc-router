import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';

/// One authored Dart source considered by dependency preflight.
final class CCComponentDependencyPreflightSource {
  /// Creates one Package-owned source snapshot.
  const CCComponentDependencyPreflightSource({
    required this.packageName,
    required this.path,
    required this.contents,
    required this.writable,
  });

  /// Resolved Pub Package owning the source.
  final String packageName;

  /// Absolute source path used only for actionable diagnostics.
  final String path;

  /// Exact authored source contents inspected by the preflight.
  final String contents;

  /// Whether generation may update this Package.
  final bool writable;
}

/// One capability requiring an omitted component owner.
final class CCComponentDependencyPreflightCapability {
  /// Creates one exact Service or Command requirement.
  const CCComponentDependencyPreflightCapability({
    required this.kind,
    required this.id,
  });

  /// Capability category written in diagnostics.
  final String kind;

  /// Stable Service or Command contract identifier.
  final String id;
}

/// Aggregated missing-owner problem found before Builder execution.
final class CCComponentDependencyPreflightIssue {
  /// Creates one source-anchored owner requirement.
  const CCComponentDependencyPreflightIssue({
    required this.sourcePath,
    required this.componentId,
    required this.ownerComponentId,
    required this.capabilities,
  });

  /// Authored component definition containing the invalid dependency list.
  final String sourcePath;

  /// Consumer component whose required edge is missing.
  final String componentId;

  /// Exact component owning all [capabilities] in this issue.
  final String ownerComponentId;

  /// Capabilities proving that the owner is required.
  final List<CCComponentDependencyPreflightCapability> capabilities;
}

/// Performs a conservative AST-only check before Builder execution.
///
/// Only direct list literals and uniquely resolved top-level constants are
/// considered. The check declines aliases, computed collections, ambiguous
/// imports, and incomplete buffers; those inputs continue to the authoritative
/// Builder instead of producing a speculative early failure.
abstract final class CCComponentDependencyPreflight {
  /// Finds exact required owners omitted by writable component definitions.
  static List<CCComponentDependencyPreflightIssue> inspect(
    Iterable<CCComponentDependencyPreflightSource> sources,
  ) {
    final parsed = <_ParsedSource>[];
    for (final source in sources) {
      final unit = parseString(
        content: source.contents,
        path: source.path,
        featureSet: FeatureSet.latestLanguageVersion(),
        throwIfDiagnostics: false,
      ).unit;
      parsed.add(_ParsedSource(source: source, unit: unit));
    }
    final componentIds = _componentIds(parsed);
    final contracts = _contracts(parsed, componentIds);
    final issues = <CCComponentDependencyPreflightIssue>[];
    for (final file in parsed.where((item) => item.source.writable)) {
      for (final declaration
          in file.unit.declarations.whereType<TopLevelVariableDeclaration>()) {
        for (final variable in declaration.variables.variables) {
          final arguments = _constructorArguments(
            variable.initializer,
            'CCComponent',
          );
          if (arguments == null) continue;
          final componentId = _resolveComponentId(
            _namedArgument(arguments, 'id'),
            source: file,
            componentIds: componentIds,
          );
          final dependencyExpression = _namedArgument(
            arguments,
            'dependencies',
          );
          if (componentId == null || dependencyExpression is! ListLiteral) {
            continue;
          }
          if (dependencyExpression.elements.any(
            (element) => element is! Expression,
          )) {
            continue;
          }
          final requiredOwners = <String>{};
          var dependenciesAreExact = true;
          for (final dependency
              in dependencyExpression.elements.whereType<Expression>()) {
            final owner = _resolveComponentId(
              dependency,
              source: file,
              componentIds: componentIds,
            );
            if (owner == null) {
              dependenciesAreExact = false;
              break;
            }
            requiredOwners.add(owner);
          }
          if (!dependenciesAreExact) continue;
          final missing =
              <String, List<CCComponentDependencyPreflightCapability>>{};
          _collectMissing(
            _namedArgument(arguments, 'serviceDependencies'),
            constructorName: 'CCServiceDependency',
            kind: 'Service',
            source: file,
            contracts: contracts,
            requiredOwners: requiredOwners,
            target: missing,
          );
          _collectMissing(
            _namedArgument(arguments, 'commandDependencies'),
            constructorName: 'CCCommandDependency',
            kind: 'Command',
            source: file,
            contracts: contracts,
            requiredOwners: requiredOwners,
            target: missing,
          );
          for (final entry
              in missing.entries.toList()
                ..sort((left, right) => left.key.compareTo(right.key))) {
            entry.value.sort((left, right) {
              final kind = left.kind.compareTo(right.kind);
              return kind != 0 ? kind : left.id.compareTo(right.id);
            });
            issues.add(
              CCComponentDependencyPreflightIssue(
                sourcePath: file.source.path,
                componentId: componentId,
                ownerComponentId: entry.key,
                capabilities: List.unmodifiable(entry.value),
              ),
            );
          }
        }
      }
    }
    issues.sort((left, right) {
      final source = left.sourcePath.compareTo(right.sourcePath);
      if (source != 0) return source;
      final component = left.componentId.compareTo(right.componentId);
      if (component != 0) return component;
      return left.ownerComponentId.compareTo(right.ownerComponentId);
    });
    return List.unmodifiable(issues);
  }

  /// Builds a symbol index only when one Package gives it one stable value.
  static Map<_SymbolKey, String> _componentIds(List<_ParsedSource> sources) {
    final values = <_SymbolKey, Set<String>>{};
    for (final source in sources) {
      for (final declaration
          in source.unit.declarations
              .whereType<TopLevelVariableDeclaration>()) {
        if (!declaration.variables.isConst) continue;
        for (final variable in declaration.variables.variables) {
          final id = _componentIdLiteral(variable.initializer);
          if (id == null) continue;
          values
              .putIfAbsent(
                _SymbolKey(source.source.packageName, variable.name.lexeme),
                () => <String>{},
              )
              .add(id);
        }
      }
    }
    return {
      for (final entry in values.entries)
        if (entry.value.length == 1) entry.key: entry.value.single,
    };
  }

  /// Reads uniquely provable Service and Command annotations.
  static Map<_ContractKey, _Contract> _contracts(
    List<_ParsedSource> sources,
    Map<_SymbolKey, String> componentIds,
  ) {
    final candidates = <_ContractKey, List<_Contract>>{};
    for (final source in sources) {
      for (final declaration
          in source.unit.declarations.whereType<ClassDeclaration>()) {
        for (final annotation in declaration.metadata) {
          final name = _terminalName(annotation.name);
          final kind = switch (name) {
            'CCServiceContract' => 'Service',
            'CCCommandContract' => 'Command',
            _ => null,
          };
          final arguments = annotation.arguments;
          if (kind == null || arguments == null) continue;
          final componentId = _resolveComponentId(
            _namedArgument(arguments.arguments, 'componentId'),
            source: source,
            componentIds: componentIds,
          );
          final id = _stringLiteral(_namedArgument(arguments.arguments, 'id'));
          if (componentId == null || id == null) continue;
          final key = _ContractKey(
            kind,
            source.source.packageName,
            declaration.namePart.typeName.lexeme,
          );
          candidates
              .putIfAbsent(key, () => [])
              .add(_Contract(ownerComponentId: componentId, id: id));
        }
      }
    }
    return {
      for (final entry in candidates.entries)
        if (entry.value.length == 1) entry.key: entry.value.single,
    };
  }

  /// Adds missing owners for direct, uniquely resolved Contract types.
  static void _collectMissing(
    Expression? expression, {
    required String constructorName,
    required String kind,
    required _ParsedSource source,
    required Map<_ContractKey, _Contract> contracts,
    required Set<String> requiredOwners,
    required Map<String, List<CCComponentDependencyPreflightCapability>> target,
  }) {
    if (expression is! ListLiteral ||
        expression.elements.any((element) => element is! Expression)) {
      return;
    }
    for (final dependency in expression.elements.whereType<Expression>()) {
      final contractType = _dependencyType(dependency, constructorName);
      if (contractType == null) continue;
      final packages = source.importedPackages(
        prefix: contractType.$1,
        symbol: contractType.$2,
      );
      final candidates = packages
          .map(
            (package) =>
                contracts[_ContractKey(kind, package, contractType.$2)],
          )
          .whereType<_Contract>()
          .toList(growable: false);
      if (candidates.length != 1) continue;
      final contract = candidates.single;
      if (requiredOwners.contains(contract.ownerComponentId)) {
        continue;
      }
      final capabilities = target.putIfAbsent(
        contract.ownerComponentId,
        () => [],
      );
      if (capabilities.any(
        (capability) => capability.kind == kind && capability.id == contract.id,
      )) {
        continue;
      }
      capabilities.add(
        CCComponentDependencyPreflightCapability(kind: kind, id: contract.id),
      );
    }
  }

  /// Resolves a direct ID literal or one uniquely imported constant.
  static String? _resolveComponentId(
    Expression? expression, {
    required _ParsedSource source,
    required Map<_SymbolKey, String> componentIds,
  }) {
    final literal = _componentIdLiteral(expression);
    if (literal != null) return literal;
    final symbol = switch (expression) {
      SimpleIdentifier value => (null, value.name),
      PrefixedIdentifier value => (value.prefix.name, value.identifier.name),
      PropertyAccess value when value.target is SimpleIdentifier => (
        (value.target! as SimpleIdentifier).name,
        value.propertyName.name,
      ),
      _ => null,
    };
    if (symbol == null) return null;
    final local =
        componentIds[_SymbolKey(source.source.packageName, symbol.$2)];
    if (symbol.$1 == null && local != null) return local;
    final candidatePackages = source
        .importedPackages(prefix: symbol.$1, symbol: symbol.$2)
        .where(
          (package) => componentIds.containsKey(_SymbolKey(package, symbol.$2)),
        )
        .toList(growable: false);
    return candidatePackages.length == 1
        ? componentIds[_SymbolKey(candidatePackages.single, symbol.$2)]
        : null;
  }

  /// Reads the type argument of one direct dependency constructor.
  static (String?, String)? _dependencyType(
    Expression expression,
    String constructorName,
  ) {
    final typeArguments = switch (expression) {
      InstanceCreationExpression value
          when value.constructorName.type.name.lexeme == constructorName =>
        value.constructorName.type.typeArguments?.arguments,
      MethodInvocation value
          when value.target == null &&
              value.methodName.name == constructorName =>
        value.typeArguments?.arguments,
      _ => null,
    };
    if (typeArguments == null || typeArguments.length != 1) return null;
    final type = typeArguments.single;
    if (type is! NamedType) return null;
    return (type.importPrefix?.name.lexeme, type.name.lexeme);
  }

  /// Reads one direct `CCComponentId('value')` expression.
  static String? _componentIdLiteral(Expression? expression) {
    final arguments = _constructorArguments(expression, 'CCComponentId');
    if (arguments == null || arguments.length != 1) return null;
    return _stringLiteral(arguments.single);
  }

  /// Reads arguments from one direct constructor-shaped expression.
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

  /// Reads one named argument from a direct argument list.
  static Expression? _namedArgument(
    NodeList<Expression> arguments,
    String name,
  ) {
    for (final argument in arguments.whereType<NamedExpression>()) {
      if (argument.name.label.name == name) return argument.expression;
    }
    return null;
  }

  /// Reads one source string literal without evaluating code.
  static String? _stringLiteral(Expression? expression) =>
      expression is SimpleStringLiteral ? expression.value : null;

  /// Returns the terminal identifier of an annotation name.
  static String _terminalName(Identifier name) => switch (name) {
    SimpleIdentifier value => value.name,
    PrefixedIdentifier value => value.identifier.name,
    _ => name.toSource().split('.').last,
  };
}

/// Parsed source plus its conservative public import view.
final class _ParsedSource {
  /// Creates one parsed source and its import visibility view.
  const _ParsedSource({required this.source, required this.unit});

  /// Authored source metadata and exact contents.
  final CCComponentDependencyPreflightSource source;

  /// Syntax tree parsed without semantic resolution.
  final CompilationUnit unit;

  /// Returns every Package import through which [symbol] remains visible.
  Set<String> importedPackages({
    required String? prefix,
    required String symbol,
  }) {
    final packages = <String>{};
    for (final directive in unit.directives.whereType<ImportDirective>()) {
      final uri = directive.uri.stringValue;
      final parsed = uri == null ? null : Uri.tryParse(uri);
      if (parsed == null ||
          parsed.scheme != 'package' ||
          parsed.pathSegments.isEmpty ||
          directive.deferredKeyword != null) {
        continue;
      }
      if (directive.prefix?.name != prefix) continue;
      var visible = true;
      for (final combinator in directive.combinators) {
        if (combinator is ShowCombinator) {
          visible = combinator.shownNames.any((name) => name.name == symbol);
        } else if (combinator is HideCombinator &&
            combinator.hiddenNames.any((name) => name.name == symbol)) {
          visible = false;
        }
      }
      if (visible) packages.add(parsed.pathSegments.first);
    }
    return packages;
  }
}

/// Package-qualified source symbol.
final class _SymbolKey {
  /// Creates one Package-qualified symbol key.
  const _SymbolKey(this.packageName, this.symbol);

  /// Pub Package declaring the symbol.
  final String packageName;

  /// Unqualified Dart symbol name.
  final String symbol;

  /// Compares Package and symbol identity.
  @override
  bool operator ==(Object other) =>
      other is _SymbolKey &&
      other.packageName == packageName &&
      other.symbol == symbol;

  /// Hashes Package and symbol identity.
  @override
  int get hashCode => Object.hash(packageName, symbol);
}

/// Package-qualified Service or Command Contract symbol.
final class _ContractKey {
  /// Creates one kind- and Package-qualified Contract key.
  const _ContractKey(this.kind, this.packageName, this.symbol);

  /// Capability category such as Service or Command.
  final String kind;

  /// Pub Package declaring the Contract.
  final String packageName;

  /// Unqualified Contract type name.
  final String symbol;

  /// Compares the complete Contract lookup identity.
  @override
  bool operator ==(Object other) =>
      other is _ContractKey &&
      other.kind == kind &&
      other.packageName == packageName &&
      other.symbol == symbol;

  /// Hashes the complete Contract lookup identity.
  @override
  int get hashCode => Object.hash(kind, packageName, symbol);
}

/// Exact owner information read from one Contract annotation.
final class _Contract {
  /// Creates one exact Contract owner record.
  const _Contract({required this.ownerComponentId, required this.id});

  /// Stable ID of the component that owns the Contract.
  final String ownerComponentId;

  /// Stable capability ID declared by the Contract.
  final String id;
}
