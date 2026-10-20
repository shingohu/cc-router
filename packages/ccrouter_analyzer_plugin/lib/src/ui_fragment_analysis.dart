import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:path/path.dart' as p;

import 'project_context.dart';
import 'resolved_symbols.dart';

/// A deterministic UI issue anchored in the current editor buffer.
typedef _Issue = ({
  AstNode node,
  String code,
  String message,
  String correction,
});

/// Read-only UI v1 checks; schema and Host closure remain Generator-owned.
abstract final class CCRouterUIFragmentAnalysis {
  /// Examines authored declarations without starting sessions or generation.
  static List<_Issue> issues({
    required CompilationUnit unit,
    required String filePath,
    required String packageRoot,
    required String packageName,
    required CCRouterAnalyzerProjectRole? projectRole,
  }) {
    final issues = <_Issue>[];
    final role =
        projectRole ??
        CCRouterAnalyzerProjectContext.resolve(packageRoot)?.role;
    void add(AstNode node, String code, String message, String correction) =>
        issues.add((
          node: node,
          code: 'ccrouter_ui_$code',
          message: message,
          correction: correction,
        ));
    if (packageName != 'ccrouter_ui' &&
        p.isWithin(p.join(packageRoot, 'lib'), filePath)) {
      for (final directive in unit.directives.whereType<UriBasedDirective>()) {
        final uris = <String?>[
          directive.uri.stringValue,
          if (directive is ImportDirective)
            ...directive.configurations.map((c) => c.uri.stringValue),
          if (directive is ExportDirective)
            ...directive.configurations.map((c) => c.uri.stringValue),
        ];
        if (uris.any(
          (uri) =>
              uri == 'package:ccrouter_ui/ccrouter_ui_generated.dart' ||
              (role == CCRouterAnalyzerProjectRole.package &&
                  uri == 'package:ccrouter_ui/ccrouter_ui_host.dart'),
        )) {
          add(
            directive,
            'spi_access',
            'UI Host/Generated SPI is outside the component business API.',
            'Use ccrouter_ui.dart and the consumer-owned generated UI Client; keep Host assembly in the Composition Root.',
          );
        }
      }
    }
    if (packageName != 'ccrouter_ui' &&
        p.isWithin(p.join(packageRoot, 'lib'), filePath)) {
      final references = _SPIReferences(role);
      unit.accept(references);
      for (final node in references.locations) {
        add(
          node,
          'spi_access',
          'UI Host/Generated types are outside the component business API.',
          'Use ccrouter_ui.dart and the consumer-owned UI Client; keep assembly in the Host.',
        );
      }
    }
    final visitor = _AnnotationVisitor();
    unit.accept(visitor);
    for (final annotation in visitor.annotations) {
      final name = CCRouterResolvedSymbols.annotationName(annotation);
      if (name == 'CCUIFragmentContract') {
        final type = annotation.elementAnnotation?.computeConstantValue()?.type;
        if (type is! InterfaceType || type.typeArguments.length != 2) continue;
        final action = type.typeArguments[1];
        if (_unknown(action)) continue;
        final element = action is InterfaceType ? action.element : null;
        if (element is! EnumElement ||
            element.isPrivate ||
            !element.library.uri.toString().startsWith('package:') ||
            element.library.uri.toString().startsWith('package:flutter/') ||
            element.mixins.isNotEmpty ||
            element.interfaces.isNotEmpty ||
            element.fields.any(
              (f) => !f.isSynthetic && !f.isEnumConstant && f.name != 'values',
            ) ||
            element.getters.any((f) => !f.isSynthetic) ||
            element.setters.any((f) => !f.isSynthetic) ||
            element.methods.any((f) => !f.isSynthetic) ||
            element.constructors.any((f) => !f.isSynthetic)) {
          add(
            annotation,
            'action_invalid',
            'UI v1 requires a public plain enum Action without payload or authored members.',
            'Use a plain enum; keep dynamic payload handling within the Owner component.',
          );
        }
      } else if (name == 'CCUIFragmentRenderer') {
        final parent = annotation.parent;
        if (parent is! FunctionDeclaration ||
            parent.parent is! CompilationUnit) {
          add(
            annotation,
            'renderer_invalid',
            'UI Renderer must be a public synchronous top-level function.',
            'Declare a non-generic Widget function with one required CCUIFragmentRenderInput<Props, Action> parameter.',
          );
          continue;
        }
        final function = parent.declaredFragment?.element;
        final marker = annotation.elementAnnotation
            ?.computeConstantValue()
            ?.getField('contract')
            ?.toTypeValue();
        if (function == null || marker is! InterfaceType) continue;
        final contracts = marker.element.metadata.annotations.where((a) {
          final type = a.computeConstantValue()?.type;
          return type is InterfaceType &&
              CCRouterResolvedSymbols.isFrameworkType(
                type,
                'CCUIFragmentContract',
                'ui_fragment',
              );
        });
        if (contracts.length != 1) continue;
        final contract = contracts.single.computeConstantValue()?.type;
        if (contract is! InterfaceType || contract.typeArguments.length != 2)
          continue;
        final parameters = function.formalParameters;
        final input = parameters.length == 1 ? parameters.single.type : null;
        final result = function.returnType;
        if (_unknown(result) || input != null && _unknown(input)) continue;
        if (function.isPrivate ||
            function.typeParameters.isNotEmpty ||
            parent.functionExpression.body.isAsynchronous ||
            parent.functionExpression.body.isGenerator ||
            result is! InterfaceType ||
            result.element.name != 'Widget' ||
            !result.element.library.uri.toString().startsWith(
              'package:flutter/',
            ) ||
            _nullable(result) ||
            input is! InterfaceType ||
            input.element.name != 'CCUIFragmentRenderInput' ||
            input.element.library.uri.toString() !=
                'package:ccrouter_ui/src/ui_fragment.dart' ||
            _nullable(input) ||
            input.typeArguments.length != 2 ||
            input.typeArguments[0] != contract.typeArguments[0] ||
            input.typeArguments[1] != contract.typeArguments[1] ||
            !parameters.single.isRequiredPositional) {
          add(
            annotation,
            'renderer_invalid',
            'UI Renderer signature does not match its Contract.',
            'Use a public synchronous Widget function with one required CCUIFragmentRenderInput<Props, Action> parameter matching the Contract exactly.',
          );
        }
      }
    }
    for (final declaration
        in unit.declarations.whereType<TopLevelVariableDeclaration>()) {
      for (final variable in declaration.variables.variables) {
        final init = variable.initializer;
        if (init == null ||
            !CCRouterResolvedSymbols.isFrameworkConstructor(
              init,
              'CCComponent',
              'component',
            ))
          continue;
        final arguments = _arguments(init);
        final dependencies = _named(arguments, 'uiDependencies');
        if (dependencies is! ListLiteral ||
            dependencies.elements.any((e) => e is! Expression))
          continue;
        final aliases = <String>{};
        final contracts = <DartType>{};
        for (final dependency
            in dependencies.elements.whereType<Expression>()) {
          if (!CCRouterResolvedSymbols.isFrameworkConstructor(
            dependency,
            'CCUIFragmentDependency',
            'ui_fragment',
          ))
            continue;
          final args = _arguments(dependency);
          final aliasNode = _named(args, 'alias');
          final alias = aliasNode is StringLiteral
              ? aliasNode.stringValue
              : null;
          if (alias != null) {
            if (!_validAlias(alias)) {
              add(
                aliasNode!,
                'alias_invalid',
                'UI alias "$alias" cannot be a generated Client member.',
                'Use a unique lowerCamelCase Dart member name without reserved Object members.',
              );
            }
            if (!aliases.add(alias)) {
              add(
                aliasNode!,
                'alias_duplicate',
                'UI alias "$alias" is repeated in this consumer.',
                'Give each UI dependency a unique alias.',
              );
            }
          }
          final type = dependency.staticType;
          if (type is InterfaceType &&
              type.typeArguments.length == 1 &&
              !_unknown(type.typeArguments.single) &&
              !contracts.add(type.typeArguments.single)) {
            add(
              dependency,
              'dependency_duplicate',
              'This UI Contract is required more than once.',
              'Keep one dependency; render multiple instances through that method with distinct Keys.',
            );
          }
          final rangeNode = _named(args, 'versionRange');
          final range = rangeNode is StringLiteral
              ? rangeNode.stringValue
              : null;
          // Only reject definitely unsupported tokens; the Generator owns the range grammar.
          if (range != null &&
              RegExp(
                r'[a-zA-Z]',
              ).hasMatch(range.split('-').first.split('+').first)) {
            add(
              rangeNode!,
              'version_range_invalid',
              'UI versionRange "$range" is not a supported SemVer range.',
              'Use a supported Contract version range such as ^1.0.0.',
            );
          }
        }
      }
    }
    return issues;
  }

  /// Unknown semantic evidence is deferred while an editor buffer is incomplete.
  static bool _unknown(DartType type) =>
      type is InvalidType || type is DynamicType;

  /// Nullable Renderer boundaries do not satisfy the generated call signature.
  static bool _nullable(DartType type) => type.getDisplayString().endsWith('?');

  /// Mirrors generated member spelling and reserved Object names.
  static bool _validAlias(String value) =>
      RegExp(r'^[a-z][a-zA-Z0-9]*$').hasMatch(value) &&
      !Keyword.keywords.containsKey(value) &&
      !const {
        'hashCode',
        'runtimeType',
        'toString',
        'noSuchMethod',
      }.contains(value);

  /// Reads only direct constructor calls, never computed dependency collections.
  static ArgumentList? _arguments(Expression expression) =>
      switch (expression) {
        InstanceCreationExpression e => e.argumentList,
        MethodInvocation e => e.argumentList,
        _ => null,
      };

  /// Finds an authored named argument without evaluating user code.
  static Expression? _named(ArgumentList? list, String name) {
    if (list == null) return null;
    for (final argument in list.arguments.whereType<NamedExpression>()) {
      if (argument.name.label.name == name) return argument.expression;
    }
    return null;
  }
}

/// Collects annotations including invalid member Renderers for precise feedback.
final class _AnnotationVisitor extends RecursiveAstVisitor<void> {
  /// Source annotations owned by this synchronous file scan.
  final annotations = <Annotation>[];

  /// Records metadata while preserving normal child traversal.
  @override
  void visitAnnotation(Annotation node) {
    annotations.add(node);
    super.visitAnnotation(node);
  }
}

/// Checks canonical class references through prefixed and transitive barrels.
final class _SPIReferences extends RecursiveAstVisitor<void> {
  /// The Package role controls whether Host assembly references are permitted.
  _SPIReferences(this.role);

  /// Unknown roles defer Host-only checks.
  final CCRouterAnalyzerProjectRole? role;

  /// Source nodes owned only by this synchronous scan.
  final locations = <AstNode>[];

  /// Compares defining-library identity instead of a public barrel's spelling.
  bool _forbidden(InterfaceElement element) =>
      element.library.uri.toString() ==
          'package:ccrouter_ui/src/ui_fragment.dart' &&
      (const {
            'CCUIFragmentDescriptor',
            'CCUIFragmentRequirement',
            'CCUIRenderer',
            'CCUIFragmentContribution',
            'CCUIGeneratedFragment',
          }.contains(element.name) ||
          role == CCRouterAnalyzerProjectRole.package &&
              const {
                'CCUIHostAssembly',
                'CCUIDiagnostic',
              }.contains(element.name));

  /// Generated types remain forbidden in handwritten code even in a Host.
  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final element = node.element;
    if (element is InterfaceElement && _forbidden(element)) locations.add(node);
    super.visitSimpleIdentifier(node);
  }

  /// Analyzer represents type annotation names as tokens rather than identifiers.
  @override
  void visitNamedType(NamedType node) {
    final type = node.type;
    if (type is InterfaceType && _forbidden(type.element)) locations.add(node);
    super.visitNamedType(node);
  }
}
