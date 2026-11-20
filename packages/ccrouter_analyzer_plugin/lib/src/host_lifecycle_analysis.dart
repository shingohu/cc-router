import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:path/path.dart' as path;

import 'project_context.dart';

/// Finds proven Host lifecycle references in component production sources.
///
/// Package roles follow the same authored evidence as Generator selection.
/// Tests/tools are outside this rule, and unavailable role or symbol evidence
/// is deferred rather than guessing from a class or Package name.
abstract final class CCRouterHostLifecycleAnalysis {
  /// Returns source locations that expose or use application Runtime control.
  ///
  /// Direct import/re-export directives can be checked before resolution. Other
  /// references require the canonical framework declaration, so prefixed and
  /// transitive public barrels work without flagging foreign same-name APIs.
  /// [matchesLibrary] proves URI aliases against the configured SDK libraries.
  static List<AstNode> violations({
    required CompilationUnit unit,
    required String filePath,
    required String packageRoot,
    required bool Function(Uri actual, String canonical) matchesLibrary,
    CCRouterAnalyzerProjectRole? projectRole,
  }) {
    if (!path.isWithin(path.join(packageRoot, 'lib'), filePath))
      return const [];
    final role =
        projectRole ??
        CCRouterAnalyzerProjectContext.resolve(packageRoot)?.role;
    if (role != CCRouterAnalyzerProjectRole.package) return const [];
    final locations = <AstNode>[];
    for (final directive in unit.directives.whereType<NamespaceDirective>()) {
      final exposesHost = directive.combinators.every(
        (combinator) => switch (combinator) {
          ShowCombinator c => c.shownNames.any((n) => n.name == 'CCRouterHost'),
          HideCombinator c => !c.hiddenNames.any(
            (n) => n.name == 'CCRouterHost',
          ),
        },
      );
      if (!exposesHost) continue;
      for (final uri in [
        directive.uri,
        ...directive.configurations.map((c) => c.uri),
      ]) {
        final value = uri.stringValue;
        final parsed = value == null ? null : Uri.tryParse(value);
        if (parsed != null &&
            matchesLibrary(
              Uri.file(filePath).resolveUri(parsed),
              'package:ccrouter/ccrouter_host.dart',
            ))
          locations.add(uri);
      }
    }
    unit.accept(_HostLifecycleReferences(locations, matchesLibrary));
    return locations;
  }
}

/// Visits resolved class references without retaining an AST after analysis.
final class _HostLifecycleReferences extends RecursiveAstVisitor<void> {
  /// Appends canonical Host class uses to the current source's result.
  _HostLifecycleReferences(this.locations, this.matchesLibrary);

  /// Locations retained only for the duration of one source analysis.
  final List<AstNode> locations;

  /// Current-call SDK identity proof; never retained after traversal.
  final bool Function(Uri actual, String canonical) matchesLibrary;

  /// Only the configured framework declaration owns lifecycle control.
  bool _isHost(InterfaceElement element) =>
      element.name == 'CCRouterHost' &&
      matchesLibrary(element.library.uri, 'package:ccrouter/src/facade.dart');

  @override
  /// Declaration identity also recognizes prefixed/transitive barrel imports.
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final combinator = node.thisOrAncestorOfType<Combinator>();
    if (combinator != null) {
      final directive = combinator.parent;
      if (combinator is! ShowCombinator ||
          directive is! NamespaceDirective ||
          !directive.combinators.every(
            (c) => switch (c) {
              ShowCombinator c => c.shownNames.any((n) => n.name == node.name),
              HideCombinator c => !c.hiddenNames.any(
                (n) => n.name == node.name,
              ),
            },
          ))
        return;
    }
    final element = node.element;
    final alias = element is TypeAliasElement ? element.aliasedType : null;
    if (element is InterfaceElement && _isHost(element) ||
        alias is InterfaceType && _isHost(alias.element)) {
      locations.add(node);
    }
    super.visitSimpleIdentifier(node);
  }

  /// Type annotation names are tokens in current Analyzer ASTs.
  @override
  void visitNamedType(NamedType node) {
    final type = node.type;
    if (type is InterfaceType && _isHost(type.element)) locations.add(node);
    super.visitNamedType(node);
  }
}
