part of 'source_analyzer.dart';

/// Checks only authored literal configuration with proven framework identity.
///
/// Cross-file topology, computed constants and missing registrations remain
/// Generator-owned. No analysis session, AST or application state is retained.
abstract final class _RouteConfigurationAnalysis {
  /// Reports precise literal spans without inventing IDs or offering rewrites.
  static List<CCRouterAnalyzerDiagnostic> diagnostics(Annotation annotation) {
    final issues = <CCRouterAnalyzerDiagnostic>[];
    final placement = CCRouterSourceAnalyzer._namedArgument(
      annotation,
      'placement',
    );
    final arguments = placement == null
        ? null
        : CCRouterResolvedSymbols.constructorArguments(
            placement,
            'CCRoutePlacement',
            'route_placement',
          );
    final routeId = CCRouterSourceAnalyzer._literalString(
      CCRouterSourceAnalyzer._namedArgument(annotation, 'id'),
    );
    for (final argument
        in arguments?.arguments.whereType<NamedExpression>() ??
            const <NamedExpression>[]) {
      final field = argument.name.label.name;
      if (!const {
        'hostId',
        'navigatorOutlet',
        'shellId',
        'parentRouteId',
      }.contains(field))
        continue;
      final value = CCRouterSourceAnalyzer._literalString(argument.expression);
      if (value == null) continue;
      if (!_validId(value)) {
        issues.add(
          _issue(
            argument.expression,
            code: 'ccrouter_route_placement_invalid',
            message: 'Route $field must be a bounded stable identifier.',
            correction:
                'Use a lowercase-leading ID of at most 128 characters '
                'with alphanumeric segments separated by ., _, or -.',
          ),
        );
      } else if (field == 'parentRouteId' && value == routeId) {
        issues.add(
          _issue(
            argument.expression,
            code: 'ccrouter_route_parent_self',
            message: 'A Route cannot be its own parent.',
            correction:
                'Choose a different declared parent Route or omit parentRouteId.',
          ),
        );
      }
    }
    for (final field in const ['interceptors', 'popGuards']) {
      final expression = CCRouterSourceAnalyzer._namedArgument(
        annotation,
        field,
      );
      if (expression is! ListLiteral) continue;
      final seen = <String>{};
      for (final item in expression.elements) {
        if (item is! Expression) continue;
        final value = CCRouterSourceAnalyzer._literalString(item);
        if (value == null) continue;
        if (!_validId(value)) {
          issues.add(
            _issue(
              item,
              code: 'ccrouter_route_policy_invalid',
              message: 'Route $field must contain bounded stable identifiers.',
              correction:
                  'Use lowercase-leading IDs of at most 128 characters '
                  'with alphanumeric segments separated by ., _, or -.',
            ),
          );
        } else if (!seen.add(value)) {
          issues.add(
            _issue(
              item,
              code: 'ccrouter_route_policy_duplicate',
              message: 'Route $field cannot repeat the same policy ID.',
              correction: 'Keep each policy ID once in its ordered list.',
            ),
          );
        }
      }
    }
    return issues;
  }

  /// Uses the same bounded identifier syntax as authoritative Route generation.
  static bool _validId(String value) =>
      value.length <= 128 && _stableIdPattern.hasMatch(value);

  /// Keeps the diagnostic on the authored value rather than the whole class.
  static CCRouterAnalyzerDiagnostic _issue(
    AstNode node, {
    required String code,
    required String message,
    required String correction,
  }) => CCRouterAnalyzerDiagnostic(
    offset: node.offset,
    length: node.length,
    code: code,
    message: message,
    correction: correction,
    severity: AnalysisErrorSeverity.ERROR,
  );
}
