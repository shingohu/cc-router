import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';

import 'resolved_symbols.dart';

/// Internal resolved-only Service lifetime checks shared by diagnostics/fixes.
/// No resource is destroyed or instantiated; ambiguous ownership is ignored.
abstract final class CCRouterServiceLifecycleAnalysis {
  /// Returns annotated Services missing Scope disposal, with a safe-fix flag.
  /// The flag proves an existing compatible instance method, not cleanup quality.
  static Iterable<(ClassDeclaration, bool)> issues(CompilationUnit unit) sync* {
    for (final declaration in unit.declarations.whereType<ClassDeclaration>()) {
      final element = declaration.declaredFragment?.element;
      if (element == null ||
          element.isAbstract ||
          declaration.typeParameters != null)
        continue;
      final service = declaration.metadata.any((annotation) {
        final type = annotation.elementAnnotation?.computeConstantValue()?.type;
        return type is InterfaceType &&
            CCRouterResolvedSymbols.isFrameworkType(
              type,
              'CCService',
              'service',
            );
      });
      if (!service) continue;
      if (_disposable(element.thisType)) continue;
      final method = element.lookUpMethod(
        name: 'dispose',
        library: element.library,
      );
      if (method != null &&
          !method.isAbstract &&
          !method.isStatic &&
          method.formalParameters.isEmpty &&
          method.typeParameters.isEmpty &&
          _voidLike(method.returnType)) {
        yield (declaration, true);
        continue;
      }
      final visitor = _OwnedResourceVisitor(element);
      declaration.accept(visitor);
      if (visitor.found) yield (declaration, false);
    }
  }

  /// Finds the existing unambiguous import reference for the framework interface.
  static String? disposableReference(CompilationUnit unit) {
    final candidates = CCRouterResolvedSymbols.references(unit, 'CCDisposable')
        .entries
        .where(
          (entry) =>
              entry.value is InterfaceElement &&
              CCRouterResolvedSymbols.isFrameworkType(
                (entry.value as InterfaceElement).thisType,
                'CCDisposable',
                'lifecycle',
              ),
        )
        .toList();
    return candidates.length == 1 ? candidates.single.key : null;
  }

  /// Whether a type implements Scope's exact disposal contract, including bases.
  static bool _disposable(InterfaceType type) =>
      [type, ...type.allSupertypes].any(
        (candidate) => CCRouterResolvedSymbols.isFrameworkType(
          candidate,
          'CCDisposable',
          'lifecycle',
        ),
      );

  /// Safe method return shapes accepted by the framework lifecycle contract.
  static bool _voidLike(DartType type) =>
      type is VoidType ||
      type is InterfaceType &&
          type.nullabilitySuffix == NullabilitySuffix.none &&
          (type.isDartAsyncFuture || type.isDartAsyncFutureOr) &&
          type.typeArguments.single is VoidType;
}

/// Finds direct owned allocations into private final instance fields.
/// Constructor injection, shared lookups, factories, and arbitrary flow are not
/// ownership proof. This conservative subset intentionally misses complex leaks.
final class _OwnedResourceVisitor extends RecursiveAstVisitor<void> {
  /// Limits evidence to fields and constructors of this annotated Service.
  _OwnedResourceVisitor(this.owner);

  /// Resolved Service whose own private fields may establish ownership.
  final ClassElement owner;

  /// Whether at least one direct disposable allocation has been proven.
  bool found = false;

  /// Checks direct field declaration initializers.
  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    _check(node.declaredFragment?.element, node.initializer);
    super.visitVariableDeclaration(node);
  }

  /// Checks constructor initializer-list allocations.
  @override
  void visitConstructorFieldInitializer(ConstructorFieldInitializer node) {
    _check(node.fieldName.element, node.expression);
    super.visitConstructorFieldInitializer(node);
  }

  /// Checks direct constructor-body assignments, not arbitrary later mutations.
  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    if (node.thisOrAncestorOfType<ConstructorDeclaration>() != null) {
      final left = node.leftHandSide;
      if (left is! SimpleIdentifier &&
          !(left is PropertyAccess && left.target is ThisExpression))
        return;
      final element = switch (left) {
        SimpleIdentifier e => e.element,
        PropertyAccess e => e.propertyName.element,
        _ => null,
      };
      _check(node.writeElement ?? element, node.rightHandSide);
    }
    super.visitAssignmentExpression(node);
  }

  /// Accepts only fresh generative CCDisposable or known SDK/Flutter resources.
  void _check(Element? element, Expression? expression) {
    final field = element is PropertyAccessorElement
        ? element.variable
        : element;
    if (field is! FieldElement ||
        field.enclosingElement != owner ||
        field.isStatic ||
        !field.isFinal ||
        !field.isPrivate ||
        expression is! InstanceCreationExpression)
      return;
    final type = expression.staticType;
    if (type is! InterfaceType) return;
    final uri = type.element.library.uri.toString();
    final known =
        (uri == 'dart:async' &&
            const {'Timer', 'StreamController'}.contains(type.element.name)) ||
        (uri.startsWith('package:flutter/') &&
            const {
              'ChangeNotifier',
              'ValueNotifier',
              'TextEditingController',
              'ScrollController',
              'FocusNode',
              'AnimationController',
            }.contains(type.element.name));
    if (known ||
        (expression.constructorName.element?.isFactory == false &&
            CCRouterServiceLifecycleAnalysis._disposable(type)))
      found = true;
  }
}
