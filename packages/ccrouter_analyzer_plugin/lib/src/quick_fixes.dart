import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';

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

/// Computes only explicit conflict-removal fixes with provably bounded edits.
///
/// This helper never invents IDs, aliases, Contracts, Gate semantics, timeout
/// values, imports, or Package dependencies. It also declines to delete an
/// argument when doing so would consume a nearby comment.
abstract final class CCRouterQuickFixes {
  /// Returns conflict-removal alternatives for the annotation at [offset].
  static List<CCRouterSourceFix> compute({
    required String source,
    required String filePath,
    required int offset,
  }) {
    final unit = parseString(
      content: source,
      path: filePath,
      throwIfDiagnostics: false,
    ).unit;
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

  /// Returns an annotation's unqualified name.
  static String _annotationName(Annotation annotation) {
    final source = annotation.name.toSource();
    return source.substring(source.lastIndexOf('.') + 1);
  }

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
}
