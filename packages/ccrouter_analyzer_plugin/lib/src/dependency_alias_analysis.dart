part of 'source_analyzer.dart';

/// Checks literal Service/Command overrides on proven component constructors.
/// Computed aliases and collections remain authoritative Generator checks.
List<CCRouterAnalyzerDiagnostic> _dependencyAliasDiagnostics(
  CompilationUnit unit,
) {
  final diagnostics = <CCRouterAnalyzerDiagnostic>[];
  for (final declaration
      in unit.declarations.whereType<TopLevelVariableDeclaration>()) {
    for (final variable in declaration.variables.variables) {
      final initializer = variable.initializer;
      if (initializer == null) continue;
      final arguments = CCRouterResolvedSymbols.constructorArguments(
        initializer,
        'CCComponent',
        'component',
      );
      if (arguments == null) continue;
      for (final field in const [
        ('serviceDependencies', 'CCServiceDependency', 'service'),
        ('commandDependencies', 'CCCommandDependency', 'messaging'),
      ]) {
        final dependencies = arguments.arguments
            .whereType<NamedExpression>()
            .where((argument) => argument.name.label.name == field.$1)
            .firstOrNull
            ?.expression;
        if (dependencies is! ListLiteral ||
            dependencies.elements.any((element) => element is! Expression))
          continue;
        for (final dependency
            in dependencies.elements.whereType<Expression>()) {
          final dependencyArguments =
              CCRouterResolvedSymbols.constructorArguments(
                dependency,
                field.$2,
                field.$3,
              );
          if (dependencyArguments == null) continue;
          final aliasNode = dependencyArguments.arguments
              .whereType<NamedExpression>()
              .where((argument) => argument.name.label.name == 'alias')
              .firstOrNull
              ?.expression;
          final alias = aliasNode is StringLiteral
              ? aliasNode.stringValue
              : null;
          if (alias == null || isGeneratedClientMemberName(alias)) continue;
          diagnostics.add(
            CCRouterAnalyzerDiagnostic(
              offset: aliasNode!.offset,
              length: aliasNode.length,
              code: 'ccrouter_alias_invalid',
              message:
                  '${field.$2} alias "$alias" cannot be a generated Client member.',
              correction:
                  'Choose a non-keyword lower-camel Client member name outside Object members.',
              severity: AnalysisErrorSeverity.ERROR,
            ),
          );
        }
      }
    }
  }
  return diagnostics;
}
