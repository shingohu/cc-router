part of 'ui_fragment_generator.dart';

/// Reads opt-in schema 3 Actions without changing legacy Props/DTO fingerprints.
///
/// Each union is one sealed root with final direct leaves in its defining
/// library (including parts). Inheritance is structural only: constructor
/// syntax must prove `this.field` or `super.field` forwarding, with no executable
/// initializers. Field recursion, not the superclass relation, defines cycles.
final class _ActionSchema {
  /// Uses the Builder resolver so inspected part syntax participates in rebuilds.
  _ActionSchema(this._step, this._subtypeIndex);

  /// Resolver ownership stays with the Builder invocation.
  final BuildStep _step;

  /// Shared immutable edge facts for Props, Action and nested DTO validation.
  final _DataSubtypeIndex _subtypeIndex;

  /// Constants have a separate generous work bound to preserve schema sizing.
  final _constantBudget = _LegacySchemaBudget(
    label: 'UI DTO Action constant schema',
  );

  /// Bounds total schema expansion, including repeated nested occurrences.
  int _nodes = 0;

  /// Selects the new path only when the reachable field graph contains a union.
  bool containsUnion(DartType type) {
    final pending = <DartType>[type];
    final visited = <Element>{};
    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      if (current is! InterfaceType || current.element is! ClassElement)
        continue;
      final element = current.element as ClassElement;
      // SDK sealed scalars do not opt legacy DTOs into schema 3.
      if (element.library.uri.scheme != 'package' || !visited.add(element))
        continue;
      if (element.isSealed) return true;
      pending.addAll(
        element.fields
            .where((field) => !field.isStatic)
            .map((field) => field.type),
      );
    }
    return false;
  }

  /// Produces deterministic data schemas, rejecting unsupported graphs early.
  Future<Object> read(DartType type, Set<Element> stack, Element origin) async {
    if (++_nodes > 512 || stack.length >= 32) {
      _fail('UI DTO Action union exceeds 512 nodes or 32 data levels.', origin);
    }
    if (type is! InterfaceType ||
        type.element.isPrivate ||
        type.typeArguments.isNotEmpty) {
      _fail(
        'UI DTO Action union requires public non-generic data types.',
        origin,
      );
    }
    final element = type.element;
    if (element is! ClassElement ||
        element.library.uri.toString() == 'dart:core') {
      return _schema(type, stack, origin, subtypeIndex: _subtypeIndex);
    }
    _validateData(element);
    if (!stack.add(element)) {
      _fail('UI DTO Action union field graph must be acyclic.', origin);
    }
    try {
      if (element.isSealed) {
        if (element.supertype?.isDartCoreObject != true) {
          _fail(
            'UI DTO Action union roots must directly extend Object.',
            element,
          );
        }
        final variants = _subtypes(element);
        if (variants.isEmpty) {
          _fail(
            'UI DTO Action union requires at least one final leaf.',
            element,
          );
        }
        final result = await _data(type, stack);
        result['kind'] = 'union';
        result['variants'] = [
          for (final variant in variants)
            await _variant(variant, element, stack),
        ];
        return result;
      }
      if (!element.isFinal || element.supertype?.isDartCoreObject != true) {
        _fail(
          'UI DTO Action data must be final and directly extend Object.',
          element,
        );
      }
      if (_subtypes(element).isNotEmpty) {
        _fail(
          'UI DTO Action data must be terminal; same-library subtypes are unsupported.',
          element,
        );
      }
      return await _data(type, stack);
    } finally {
      stack.remove(element);
    }
  }

  /// Finds all direct subtype edges, including forbidden implements/mixin edges.
  List<InterfaceElement> _subtypes(ClassElement root) =>
      _subtypeIndex.subtypes(root);

  /// Enforces actual leaves; Dart's final modifier alone allows same-library heirs.
  Future<Object> _variant(
    InterfaceElement variant,
    ClassElement root,
    Set<Element> stack,
  ) async {
    if (variant is! ClassElement ||
        !variant.isFinal ||
        variant.isAbstract ||
        variant.isSealed ||
        variant.supertype?.element != root ||
        variant.library != root.library) {
      _fail(
        'UI DTO Action union variants must be final direct data leaves.',
        variant,
      );
    }
    _validateData(variant);
    if (_subtypes(variant).isNotEmpty) {
      _fail(
        'UI DTO Action union final leaves cannot have further subtypes.',
        variant,
      );
    }
    if (++_nodes > 512 || stack.length >= 32) {
      _fail(
        'UI DTO Action union exceeds 512 nodes or 32 data levels.',
        variant,
      );
    }
    if (!stack.add(variant)) {
      _fail('UI DTO Action union field graph must be acyclic.', variant);
    }
    try {
      final inherited = root.fields
          .where((field) => !field.isStatic)
          .map((field) => field.displayName)
          .toSet();
      if (variant.fields.any(
        (field) => !field.isStatic && inherited.contains(field.displayName),
      )) {
        _fail(
          'UI DTO Action union leaves cannot override inherited fields.',
          variant,
        );
      }
      final result = await _data(variant.thisType, stack, parent: root);
      result['kind'] = 'variant';
      result['supertype'] = _identity(root);
      return result;
    } finally {
      stack.remove(variant);
    }
  }

  /// Applies immutable Pure Dart member rules before recursion or construction.
  void _validateData(ClassElement element) {
    final uri = element.library.uri.toString();
    if (element.isPrivate ||
        element.typeParameters.isNotEmpty ||
        !uri.startsWith('package:') ||
        const [
          'package:flutter/',
          'package:ccrouter/',
          'package:ccrouter_core/',
          'package:ccrouter_contracts/',
          'package:ccrouter_ui/',
        ].any(uri.startsWith) ||
        element.interfaces.isNotEmpty ||
        element.mixins.isNotEmpty ||
        element.methods.isNotEmpty ||
        element.getters.any((getter) => getter.isOriginDeclaration) ||
        element.setters.any((setter) => setter.isOriginDeclaration) ||
        element.fields.any(
          (field) =>
              !field.isStatic &&
              (!field.isFinal || field.isPrivate || !field.isOriginDeclaration),
        ) ||
        element.constructors.isEmpty ||
        element.constructors.any((c) => !c.isConst || c.isFactory)) {
      _fail(
        'UI DTO Action union requires public immutable Pure Dart data and const generative constructors.',
        element,
      );
    }
  }

  /// Encodes declared fields; inherited fields are encoded once on the union root.
  Future<Map<String, Object?>> _data(
    InterfaceType type,
    Set<Element> stack, {
    ClassElement? parent,
  }) async {
    final element = type.element as ClassElement;
    final fields = element.fields.where((field) => !field.isStatic).toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
    final constructors = element.constructors.toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
    return {
      'type': _identity(element),
      'nullable': type.getDisplayString().endsWith('?'),
      'fields': [
        for (final field in fields)
          {
            'name': field.displayName,
            'schema': await read(field.type, stack, field),
            if (field.hasInitializer)
              'initializer': _constant(field.computeConstantValue(), field),
          },
      ],
      'constructors': [
        for (final constructor in constructors)
          await _constructor(constructor, fields, parent, stack),
      ],
    };
  }

  /// Proves that constructor parameters cannot transform stored data or defaults.
  Future<Object> _constructor(
    ConstructorElement constructor,
    List<FieldElement> fields,
    ClassElement? parent,
    Set<Element> stack,
  ) async {
    final node = await _step.resolver.astNodeFor(constructor.firstFragment);
    final parameters = constructor.formalParameters;
    final initialized = parameters
        .whereType<FieldFormalParameterElement>()
        .map((parameter) => parameter.field)
        .toSet();
    if (node is! ConstructorDeclaration ||
        node.initializers.isNotEmpty ||
        node.redirectedConstructor != null ||
        node.body is! EmptyFunctionBody ||
        parameters.any(
          (p) =>
              p is! FieldFormalParameterElement &&
              (parent == null || p is! SuperFormalParameterElement),
        ) ||
        fields.any(
          (field) => !field.hasInitializer && !initialized.contains(field),
        )) {
      _fail(
        'UI DTO Action union constructors allow only this.field and const super.field forwarding; explicit initializers, asserts and redirects are unsupported.',
        constructor,
      );
    }
    final superConstructor = constructor.superConstructor;
    if (parent != null &&
        (superConstructor == null ||
            superConstructor.enclosingElement != parent ||
            !superConstructor.isConst ||
            superConstructor.isFactory)) {
      _fail(
        'UI DTO Action union requires a proven const superclass constructor.',
        constructor,
      );
    }
    final forwarded = parameters
        .whereType<SuperFormalParameterElement>()
        .toList();
    for (final parameter in forwarded) {
      final target = parameter.superConstructorParameter;
      if (target is! FieldFormalParameterElement ||
          target.enclosingElement != superConstructor) {
        _fail(
          'UI DTO Action union super parameters must forward directly to stored base fields.',
          parameter,
        );
      }
    }
    if (superConstructor != null &&
        parent != null &&
        superConstructor.formalParameters.any(
          (p) =>
              p.isRequired &&
              !forwarded.any((f) => f.superConstructorParameter == p),
        )) {
      _fail(
        'UI DTO Action union must forward every required base parameter.',
        constructor,
      );
    }
    return {
      'name': constructor.name,
      if (parent != null) 'superConstructor': superConstructor!.name,
      'parameters': [
        for (final parameter in parameters)
          {
            'name': parameter.displayName,
            'required': parameter.isRequired,
            'named': parameter.isNamed,
            'default': parameter.hasDefaultValue
                ? _constant(parameter.computeConstantValue(), parameter)
                : null,
            'binding': parameter is SuperFormalParameterElement
                ? 'super'
                : 'field',
            'schema': await read(parameter.type, stack, parameter),
            if (parameter is SuperFormalParameterElement)
              'baseParameter': parameter.superConstructorParameter!.displayName,
          },
      ],
    };
  }

  /// Includes concrete variant identity and inherited fields in constant defaults.
  Object? _constant(DartObject? value, Element origin, [int depth = 0]) {
    _constantBudget.visit(depth, origin);
    if (value == null || !value.hasKnownValue)
      _fail('UI DTO Action union default could not be evaluated.', origin);
    final type = value.type;
    if (!value.isNull &&
        type is InterfaceType &&
        type.element is ClassElement &&
        type.element.library.uri.toString() != 'dart:core') {
      final fields = <String, Object?>{};
      InterfaceType? current = type;
      while (current != null && !current.isDartCoreObject) {
        for (final field in current.element.fields.where((f) => !f.isStatic)) {
          final fieldValue = ConstantReader(value).read(field.displayName);
          fields[field.displayName] = fieldValue.isNull
              ? null
              : _constant(fieldValue.objectValue, origin, depth + 1);
        }
        current = current.superclass;
      }
      return {'type': _identity(type.element), 'fields': fields};
    }
    return _constantShape(value, origin);
  }

  /// Uses defining-library identity, so moving declarations within parts is inert.
  String _identity(InterfaceElement element) =>
      '${element.library.uri}#${element.displayName}';
}
