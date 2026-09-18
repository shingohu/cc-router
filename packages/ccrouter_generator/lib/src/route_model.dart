part of 'route_generator.dart';

/// Validated page metadata used only during one library build.
final class _RouteModel {
  /// Stores constructor and parameter information after static validation.
  _RouteModel(
    this.page,
    this.annotation,
    this.id,
    this.parameters,
    this.result,
  );

  /// Concrete annotated destination; it may be private to its Dart library.
  final ClassElement page;

  /// Evaluated immutable annotation metadata.
  final ConstantReader annotation;

  /// Stable, non-empty route identity.
  final String id;

  /// Constructor parameters with unambiguous URI or Extra sources.
  final List<_ParameterModel> parameters;

  /// Return type inferred from the annotation's generic argument.
  final String result;

  /// Whether declarations intentionally form a cross-library contract.
  bool get exported => _enumValue(
    annotation.read('visibility').objectValue,
  ).endsWith('.exported');

  /// Public exported or library-private route API name.
  String get api =>
      '${exported ? '' : '_'}${page.displayName.replaceFirst(RegExp(r'^_'), '')}Route';

  /// Immutable argument type kept at the same visibility as the route API.
  String get arguments => '${api}Arguments';

  /// Library-private boundary codec, never exported as a business API.
  String get codec => '_${api.replaceFirst(RegExp(r'^_'), '')}Codec';

  /// Library-private Intent implementation behind the typed factory.
  String get intent => '_${api.replaceFirst(RegExp(r'^_'), '')}Intent';

  /// Validates metadata and constructor injection without backend assumptions.
  static _RouteModel read(Element element, ConstantReader annotation) {
    if (element is! ClassElement ||
        element.isAbstract ||
        element.typeParameters.isNotEmpty) {
      _fail('CCRoute requires a concrete, non-generic page class.', element);
    }
    final id = annotation.read('id').stringValue;
    if (id.isEmpty || RegExp(r'\s').hasMatch(id)) {
      _fail('Route ID must be non-empty without whitespace.', element);
    }
    final constructor = element.unnamedConstructor;
    if (constructor == null || constructor.isFactory) {
      _fail('CCRoute requires an unnamed generative constructor.', element);
    }
    final patterns = annotation.read('patterns').listValue;
    final primary = patterns
        .where((pattern) => _field(pattern, 'primary').toBoolValue()!)
        .toList();
    if (primary.length != 1 ||
        _field(primary.single, 'matchOnly').toBoolValue()!) {
      _fail(
        'Route "$id" needs exactly one reversible primary pattern.',
        element,
      );
    }
    final keys = <String>{};
    Set<String>? canonicalKeys;
    final labels = <String>{};
    for (final pattern in patterns) {
      final type = (pattern.type as InterfaceType).element.displayName;
      final template = pattern
          .getField(type == 'CCRegexPattern' ? 'expression' : 'template')!
          .toStringValue()!;
      if (!labels.add('$type:$template')) {
        _fail('Route "$id" has a duplicate pattern.', element);
      }
      Set<String> patternKeys;
      if (type == 'CCRegexPattern') {
        try {
          RegExp(template);
        } on FormatException {
          _fail('Route "$id" has an invalid regular expression.', element);
        }
        patternKeys = RegExp(
          r'\(\?<([a-zA-Z_]\w*)>',
        ).allMatches(template).map((match) => match[1]!).toSet();
      } else {
        final uri = Uri.tryParse(template);
        if (uri == null ||
            uri.hasQuery ||
            uri.hasFragment ||
            uri.userInfo.isNotEmpty ||
            (type == 'CCPathPattern' &&
                (!template.startsWith('/') ||
                    uri.hasScheme ||
                    uri.hasAuthority)) ||
            (type == 'CCUriPattern' && (!uri.hasScheme || uri.host.isEmpty))) {
          _fail('Route "$id" has an invalid path or URI template.', element);
        }
        patternKeys = <String>{};
        final segments = uri.path.split('/');
        for (var index = 0; index < segments.length; index++) {
          final segment = segments[index];
          if (!segment.startsWith(':') && !segment.startsWith('*')) continue;
          final name = segment.substring(1);
          if (!RegExp(r'^[a-zA-Z_]\w*$').hasMatch(name) ||
              !patternKeys.add(name) ||
              (segment.startsWith('*') && index != segments.length - 1)) {
            _fail(
              'Route "$id" has an invalid or duplicate path parameter.',
              element,
            );
          }
        }
        for (final entry
            in pattern.getField('constraints')!.toMapValue()!.entries) {
          if (!patternKeys.contains(entry.key!.toStringValue())) {
            _fail('Route "$id" constrains an unknown path parameter.', element);
          }
          try {
            RegExp(entry.value!.toStringValue()!);
          } on FormatException {
            _fail('Route "$id" has an invalid parameter constraint.', element);
          }
        }
      }
      if (canonicalKeys == null) {
        canonicalKeys = patternKeys;
      }
      if (patternKeys.length != canonicalKeys.length ||
          !patternKeys.containsAll(canonicalKeys)) {
        _fail(
          'Route "$id" aliases must capture the same path parameters.',
          element,
        );
      }
      keys.addAll(patternKeys);
    }
    final parameters = <_ParameterModel>[];
    final queryKeys = <String>{};
    var extras = 0;
    for (final parameter in constructor.formalParameters) {
      final model = _ParameterModel.read(parameter, keys, id);
      if (model == null) continue;
      if (model.source == 'query' && !queryKeys.add(model.wireName)) {
        _fail(
          'Route "$id" has duplicate query key "${model.wireName}".',
          parameter,
        );
      }
      if (model.source == 'extra') {
        extras++;
        if (extras > 1)
          _fail('A route may declare only one Extra parameter.', parameter);
        if (model.required &&
            _enumValue(
              annotation.read('deepLink').objectValue,
            ).endsWith('.enabled')) {
          _fail('Deep-link routes cannot require in-memory Extra.', parameter);
        }
      }
      parameters.add(model);
    }
    if (!parameters
        .where((p) => p.source == 'path')
        .map((p) => p.name)
        .toSet()
        .containsAll(keys)) {
      _fail(
        'Every path capture must have a matching constructor parameter.',
        element,
      );
    }
    final result =
        (annotation.objectValue.type as InterfaceType).typeArguments.single;
    if (result is DynamicType || result is TypeParameterType) {
      _fail(
        'CCRoute must explicitly specify its result type; use void when absent.',
        element,
      );
    }
    if (_enumValue(
      annotation.read('placement').objectValue.getField('routeKind')!,
    ).endsWith('.shell')) {
      _fail(
        'Shell containers must be registered separately, not as pages.',
        element,
      );
    }
    return _RouteModel(
      element,
      annotation,
      id,
      parameters,
      _typeSource(result, element.library),
    );
  }
}

/// One validated constructor argument and its boundary conversion policy.
final class _ParameterModel {
  /// Captures a constructor parameter with one explicit or inferred source.
  _ParameterModel(this.element, this.source, this.wireName);

  /// Original parameter for Dart defaults, nullability and page invocation.
  final FormalParameterElement element;

  /// One of path, query or extra; unknown sources are compile-time errors.
  final String source;

  /// URI key; Extra uses its Dart name for diagnostic messages only.
  final String wireName;

  /// Parameter name retained in typed arguments and page construction.
  String get name => element.displayName;

  /// Source type including nullability.
  String get type => _typeSource(element.type, element.library!);

  /// Whether URI absence may produce null.
  bool get nullable =>
      element.type.nullabilitySuffix == NullabilitySuffix.question;

  /// Whether the generated factory requires an explicit argument.
  bool get required => element.isRequiredNamed || element.isRequiredPositional;

  /// Compiler-parsed default expression reused in the same Dart library.
  String? get defaultCode => element.defaultValueCode;

  /// Validates supported scalar types and detects conflicting annotations.
  static _ParameterModel? read(
    FormalParameterElement parameter,
    Set<String> paths,
    String id,
  ) {
    const queryChecker = TypeChecker.typeNamedLiterally(
      'CCQueryParam',
      inPackage: 'ccrouter_contracts',
    );
    const extraChecker = TypeChecker.typeNamedLiterally(
      'CCExtraParam',
      inPackage: 'ccrouter_contracts',
    );
    final queries = queryChecker.annotationsOfExact(parameter).toList();
    final extras = extraChecker.annotationsOfExact(parameter).toList();
    final path = paths.contains(parameter.displayName);
    if (queries.length + extras.length + (path ? 1 : 0) > 1) {
      _fail(
        'Parameter "${parameter.displayName}" has conflicting route sources.',
        parameter,
      );
    }
    if (!path && queries.isEmpty && extras.isEmpty) {
      if (parameter.displayName == 'key' &&
          parameter.isOptional &&
          parameter.isNamed)
        return null;
      _fail(
        'Parameter "${parameter.displayName}" must be a path capture, CCQueryParam or CCExtraParam.',
        parameter,
      );
    }
    final source = path
        ? 'path'
        : queries.isNotEmpty
        ? 'query'
        : 'extra';
    final wireName = queries.isNotEmpty
        ? queries.single.getField('name')!.toStringValue() ??
              parameter.displayName
        : parameter.displayName;
    if (wireName.trim().isEmpty || RegExp(r'[\r\n]').hasMatch(wireName)) {
      _fail('Query names cannot be empty or contain line breaks.', parameter);
    }
    final model = _ParameterModel(parameter, source, wireName);
    if (source == 'path' && (model.nullable || model.defaultCode != null)) {
      _fail(
        'Path parameters must be non-nullable without defaults.',
        parameter,
      );
    }
    if (source != 'extra') {
      final type = parameter.type;
      if (type is! InterfaceType ||
          !(type.isDartCoreString ||
              type.isDartCoreInt ||
              type.isDartCoreDouble ||
              type.isDartCoreBool ||
              type.element is EnumElement)) {
        _fail(
          'URI parameters support String, int, double, bool and enums; use Extra for objects.',
          parameter,
        );
      }
    } else if (parameter.type is DynamicType ||
        parameter.type is FunctionType ||
        parameter.type is TypeParameterType) {
      _fail(
        'Extra must have an explicit, non-function object type.',
        parameter,
      );
    }
    return model;
  }
}
