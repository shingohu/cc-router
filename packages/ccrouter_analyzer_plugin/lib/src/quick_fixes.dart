import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:ccrouter_analyzer_plugin/src/component_dependency_analyzer.dart';
import 'package:ccrouter_analyzer_plugin/src/contract_owner_index.dart';
import 'package:ccrouter_analyzer_plugin/src/service_lifecycle_analysis.dart';
import 'resolved_symbols.dart';

/// One conservative source edit offered as an IDE Quick Fix.
final class CCRouterSourceFix {
  /// Creates a fix that replaces one exact source range.
  const CCRouterSourceFix({
    required this.id,
    required this.message,
    required this.offset,
    required this.length,
    required this.replacement,
  });

  /// Stable IDE action identity.
  final String id;

  /// Human-readable action shown by the editor.
  final String message;

  /// Source offset replaced by this action.
  final int offset;

  /// Number of source code units replaced by this action.
  final int length;

  /// Replacement text, empty when deleting one argument.
  final String replacement;
}

/// Computes only CCRouter source fixes with provably bounded edits.
///
/// Conflict fixes remove one explicit argument. Component dependency fixes use
/// generated Metadata to identify the exact owner and require an already
/// visible, value-checked `CCComponentId` constant. This helper never invents
/// IDs, aliases, Contracts, Gate semantics, timeout values, or imports. It also
/// declines an edit when doing so would consume a nearby comment.
abstract final class CCRouterQuickFixes {
  /// Returns safe alternatives for [diagnosticCode] at [offset].
  ///
  /// [contractOwners] and [sourcePackage] are required only for a missing
  /// component-owner dependency. Without both, that diagnostic remains
  /// visible but does not offer a potentially incorrect edit.
  /// [resolvedUnit] is a current analysis snapshot with per-symbol proofs. It is required
  /// for Service disposal fixes; no import or cleanup body is invented.
  static List<CCRouterSourceFix> compute({
    required String source,
    required String filePath,
    required int offset,
    String diagnosticCode = 'ccrouter_annotation_arguments_conflict',
    CCRouterContractOwnerIndex? contractOwners,
    String? sourcePackage,
    CompilationUnit? resolvedUnit,
  }) {
    final unit =
        resolvedUnit ??
        parseString(
          content: source,
          path: filePath,
          throwIfDiagnostics: false,
        ).unit;
    if (diagnosticCode == 'ccrouter_service_disposable_missing') {
      final reference = CCRouterServiceLifecycleAnalysis.disposableReference(
        unit,
      );
      if (reference == null) return const [];
      for (final (declaration, fixable)
          in CCRouterServiceLifecycleAnalysis.issues(unit)) {
        if (!fixable ||
            declaration.name.offset != offset ||
            declaration.leftBracket.isSynthetic)
          continue;
        final clause = declaration.implementsClause;
        return [
          CCRouterSourceFix(
            id: 'ccrouter.implement_disposable',
            message: 'Connect the existing dispose() to CCDisposable',
            offset: clause?.end ?? declaration.leftBracket.offset,
            length: 0,
            replacement: clause == null
                ? 'implements $reference '
                : ', $reference',
          ),
        ];
      }
      return const [];
    }
    if (diagnosticCode == 'ccrouter_component_owner_dependency_missing') {
      if (contractOwners == null || sourcePackage == null) return const [];
      return _componentDependencyFixes(
        source: source,
        filePath: filePath,
        unit: unit,
        offset: offset,
        owners: contractOwners,
        sourcePackage: sourcePackage,
      );
    }
    if (diagnosticCode != 'ccrouter_annotation_arguments_conflict') {
      return const [];
    }
    for (final annotation in _annotations(unit)) {
      if (offset < annotation.offset || offset > annotation.end) continue;
      final name = _annotationName(annotation);
      final conflicts = switch (name) {
        'CCRoute' || 'CCRouteContract' => const ['pattern', 'patterns'],
        'CCInitTask' => const ['contract', 'id'],
        _ => const <String>[],
      };
      if (conflicts.isEmpty) return const [];
      final arguments = annotation.arguments;
      if (arguments == null || arguments.rightParenthesis.isSynthetic) {
        return const [];
      }
      final named = <String, NamedExpression>{
        for (final argument in arguments.arguments.whereType<NamedExpression>())
          argument.name.label.name: argument,
      };
      if (!conflicts.every(named.containsKey)) return const [];
      return <CCRouterSourceFix>[
        for (final field in conflicts)
          if (_removalRange(source, arguments, named[field]!) case final range?)
            CCRouterSourceFix(
              id: 'ccrouter.remove_conflicting_$field',
              message: 'Remove the conflicting `$field` argument',
              offset: range.$1,
              length: range.$2,
              replacement: '',
            ),
      ];
    }
    return const [];
  }

  /// Adds one or all exact owner constants to an editable component list.
  static List<CCRouterSourceFix> _componentDependencyFixes({
    required String source,
    required String filePath,
    required CompilationUnit unit,
    required int offset,
    required CCRouterContractOwnerIndex owners,
    required String sourcePackage,
  }) {
    final allMissing = CCRouterComponentDependencyAnalyzer.findMissing(
      unit: unit,
      sourcePackage: sourcePackage,
      owners: owners,
      sourcePath: filePath,
    );
    final selected = allMissing
        .where((item) => item.offset == offset)
        .toList(growable: false);
    if (selected.length != 1) return const [];
    final selectedItem = selected.single;
    for (final declaration
        in unit.declarations.whereType<TopLevelVariableDeclaration>()) {
      for (final variable in declaration.variables.variables) {
        final initializer = variable.initializer;
        if (initializer == null ||
            offset < initializer.offset ||
            offset > initializer.end) {
          continue;
        }
        final arguments = _constructorArguments(initializer, 'CCComponent');
        if (arguments == null || arguments.rightParenthesis.isSynthetic) {
          return const [];
        }
        final componentMissing = allMissing
            .where(
              (item) =>
                  item.offset >= initializer.offset &&
                  item.offset <= initializer.end,
            )
            .toList(growable: false);
        final ownerReferences = <String, String>{};
        for (final item in componentMissing) {
          final reference = owners.visibleComponentIdReference(
            unit: unit,
            sourcePath: filePath,
            owner: item.owner,
          );
          if (reference == null) continue;
          ownerReferences[item.owner.componentId] = reference;
        }
        final selectedReference =
            ownerReferences[selectedItem.owner.componentId];
        if (selectedReference == null) return const [];
        final dependencies = _namedExpression(arguments, 'dependencies');
        if (dependencies == null) {
          final anchor = arguments.arguments
              .whereType<NamedExpression>()
              .where(
                (argument) =>
                    argument.name.label.name == 'serviceDependencies' ||
                    argument.name.label.name == 'commandDependencies' ||
                    argument.name.label.name == 'uiDependencies',
              )
              .where(
                (argument) =>
                    offset >= argument.offset && offset <= argument.end,
              )
              .firstOrNull;
          if (anchor == null) return const [];
          final fixes = <CCRouterSourceFix>[
            CCRouterSourceFix(
              id: 'ccrouter.add_required_component_dependency',
              message:
                  'Add `$selectedReference` to required component dependencies',
              offset: anchor.offset,
              length: 0,
              replacement: _newDependencyArgument(source, arguments, anchor, [
                selectedReference,
              ]),
            ),
          ];
          final allReferences = _allOwnerReferences(
            componentMissing,
            ownerReferences,
          );
          if (allReferences.length > 1) {
            fixes.add(
              CCRouterSourceFix(
                id: 'ccrouter.add_all_required_component_dependencies',
                message:
                    'Add all ${allReferences.length} proven component dependencies',
                offset: anchor.offset,
                length: 0,
                replacement: _newDependencyArgument(
                  source,
                  arguments,
                  anchor,
                  allReferences,
                ),
              ),
            );
          }
          return fixes;
        }
        final value = dependencies.expression;
        if (value is! ListLiteral ||
            value.elements.any((element) => element is! Expression)) {
          return const [];
        }
        final edit = _appendListElements(source, value, [selectedReference]);
        if (edit == null) return const [];
        final fixes = <CCRouterSourceFix>[
          CCRouterSourceFix(
            id: 'ccrouter.add_required_component_dependency',
            message:
                'Add `$selectedReference` to required component dependencies',
            offset: edit.$1,
            length: edit.$2,
            replacement: edit.$3,
          ),
        ];
        final allReferences = _allOwnerReferences(
          componentMissing,
          ownerReferences,
        );
        if (allReferences.length > 1) {
          final allEdit = _appendListElements(source, value, allReferences);
          if (allEdit != null) {
            fixes.add(
              CCRouterSourceFix(
                id: 'ccrouter.add_all_required_component_dependencies',
                message:
                    'Add all ${allReferences.length} proven component dependencies',
                offset: allEdit.$1,
                length: allEdit.$2,
                replacement: allEdit.$3,
              ),
            );
          }
        }
        return fixes;
      }
    }
    return const [];
  }

  /// Enumerates annotations supported by conflict diagnostics.
  static Iterable<Annotation> _annotations(CompilationUnit unit) sync* {
    for (final declaration in unit.declarations) {
      if (declaration is ClassDeclaration) {
        yield* declaration.metadata;
      } else if (declaration is FunctionDeclaration) {
        yield* declaration.metadata;
      }
    }
  }

  /// Never offers an edit for a foreign same-named annotation.
  static String? _annotationName(Annotation annotation) =>
      CCRouterResolvedSymbols.annotationName(annotation);

  /// Computes a comma-aware deletion that preserves adjacent arguments.
  static (int, int)? _removalRange(
    String source,
    ArgumentList list,
    NamedExpression target,
  ) {
    final arguments = list.arguments;
    final index = arguments.indexOf(target);
    if (index < 0) return null;
    late final int start;
    late final int end;
    if (arguments.length == 1) {
      start = target.offset;
      end = target.end;
    } else if (index < arguments.length - 1) {
      start = target.offset;
      end = arguments[index + 1].offset;
    } else {
      start = arguments[index - 1].end;
      end = target.end;
    }
    final removed = source.substring(start, end);
    if (removed.contains('//') || removed.contains('/*')) return null;
    return (start, end - start);
  }

  /// Returns the arguments of a direct constructor-shaped invocation.
  static ArgumentList? _constructorArguments(
    Expression expression,
    String typeName,
  ) => switch (expression) {
    InstanceCreationExpression value
        when value.constructorName.type.name.lexeme == typeName =>
      value.argumentList,
    MethodInvocation value
        when value.target == null && value.methodName.name == typeName =>
      value.argumentList,
    _ => null,
  };

  /// Reads one named expression from a constructor argument list.
  static NamedExpression? _namedExpression(
    ArgumentList arguments,
    String name,
  ) {
    for (final argument in arguments.arguments.whereType<NamedExpression>()) {
      if (argument.name.label.name == name) return argument;
    }
    return null;
  }

  /// Orders one visible reference per owner when every owner is provable.
  static List<String> _allOwnerReferences(
    List<CCRouterMissingComponentDependency> missing,
    Map<String, String> references,
  ) {
    final ownerIds = missing.map((item) => item.owner.componentId).toSet();
    if (!ownerIds.every(references.containsKey)) return const [];
    final sorted = ownerIds.toList()..sort();
    return [for (final owner in sorted) references[owner]!];
  }

  /// Creates a complete dependency argument before one consuming field.
  static String _newDependencyArgument(
    String source,
    ArgumentList arguments,
    NamedExpression anchor,
    List<String> references,
  ) {
    final multiline = source
        .substring(
          arguments.leftParenthesis.end,
          arguments.rightParenthesis.offset,
        )
        .contains('\n');
    if (references.length == 1) {
      return multiline
          ? 'dependencies: [${references.single}],\n${_lineIndent(source, anchor.offset)}'
          : 'dependencies: [${references.single}], ';
    }
    if (!multiline) return 'dependencies: [${references.join(', ')}], ';
    final indent = _lineIndent(source, anchor.offset);
    final entries = references.map((item) => '$indent  $item,').join('\n');
    return 'dependencies: [\n$entries\n$indent],\n$indent';
  }

  /// Computes a comment-preserving append to a direct list literal.
  static (int, int, String)? _appendListElements(
    String source,
    ListLiteral list,
    List<String> elementsToAdd,
  ) {
    if (elementsToAdd.isEmpty) return null;
    final innerStart = list.leftBracket.end;
    final innerEnd = list.rightBracket.offset;
    final elements = list.elements;
    if (elements.isEmpty) {
      final gap = source.substring(innerStart, innerEnd);
      if (gap.contains('//') || gap.contains('/*')) return null;
      if (!gap.contains('\n')) {
        return (innerStart, gap.length, elementsToAdd.join(', '));
      }
      final closingIndent = _lineIndent(source, innerEnd);
      final entries = elementsToAdd
          .map((item) => '$closingIndent  $item,')
          .join('\n');
      return (innerStart, gap.length, '\n$entries\n$closingIndent');
    }
    final last = elements.last;
    final gap = source.substring(last.end, innerEnd);
    if (gap.contains('//') || gap.contains('/*')) return null;
    if (!gap.contains('\n')) {
      final trailingComma = gap.contains(',');
      return (
        last.end,
        gap.length,
        ', ${elementsToAdd.join(', ')}${trailingComma ? ',' : ''}',
      );
    }
    final closingIndent = _lineIndent(source, innerEnd);
    final firstIndent = _lineIndent(source, elements.first.offset);
    final childIndent = firstIndent.length > closingIndent.length
        ? firstIndent
        : '$closingIndent  ';
    final entries = elementsToAdd
        .map((item) => '$childIndent$item,')
        .join('\n');
    return (last.end, gap.length, ',\n$entries\n$closingIndent');
  }

  /// Returns whitespace preceding [offset] on its source line.
  static String _lineIndent(String source, int offset) {
    final lineStart = source.lastIndexOf('\n', offset - 1) + 1;
    final prefix = source.substring(lineStart, offset);
    final match = RegExp(r'^[ \t]*').firstMatch(prefix);
    return match?.group(0) ?? '';
  }
}
