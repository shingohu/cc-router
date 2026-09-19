part of 'route_generator.dart';

/// Validated page metadata used only during one library build.
final class _RouteModel {
  /// Stores constructor and parameter information after static validation.
  _RouteModel(
    this.page,
    this.annotation,
    this.component,
    this.id,
    this.patterns,
    this.primaryPatternIndex,
    this.parameters,
    this.result,
  );

  /// Concrete annotated destination; it may be private to its Dart library.
  final ClassElement page;

  /// Evaluated immutable annotation metadata.
  final ConstantReader annotation;

  /// Validated component owner shared with generated workspace metadata.
  final _ComponentModel component;

  /// Stable, non-empty route identity.
  final String id;

  /// Normalized one-to-many patterns supplied by either annotation field.
  final List<DartObject> patterns;

  /// Effective reversible primary pattern after applying safe inference rules.
  final int primaryPatternIndex;

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

  /// Stable package-internal bridge used by the generated component index.
  ///
  /// The bridge is emitted in the page's own library so it can call a
  /// library-private route contract. It is intentionally not exported from a
  /// package barrel and is only consumed by generated component code.
  String get registrationFunction =>
      'ccrouterRegister${page.displayName.replaceFirst(RegExp(r'^_'), '')}Route';

  /// Stable package-internal bridge exposing adapter-neutral route metadata.
  String get descriptorFunction =>
      'ccrouterDescribe${page.displayName.replaceFirst(RegExp(r'^_'), '')}Route';

  /// Stable package-internal bridge decoding arguments and building the page.
  String get builderFunction =>
      'ccrouterBuild${page.displayName.replaceFirst(RegExp(r'^_'), '')}Route';

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
    final pattern = annotation.read('pattern');
    final declaredPatterns = annotation.read('patterns').listValue;
    final hasSinglePattern = !pattern.isNull;
    if (hasSinglePattern && declaredPatterns.isNotEmpty) {
      _fail(
        'Route "$id" cannot set both pattern and patterns; keep only patterns when declaring multiple addresses.',
        element,
      );
    }
    if (!hasSinglePattern && declaredPatterns.isEmpty) {
      _fail('Route "$id" must set pattern or patterns.', element);
    }
    final patterns = hasSinglePattern
        ? <DartObject>[pattern.objectValue]
        : declaredPatterns;
    final explicitPrimaryIndexes = <int>[
      for (var index = 0; index < patterns.length; index++)
        if (_field(patterns[index], 'primary').toBoolValue()!) index,
    ];
    if (explicitPrimaryIndexes.length > 1) {
      _fail(
        'Route "$id" needs exactly one reversible primary pattern.',
        element,
      );
    }
    final reversibleIndexes = <int>[
      for (var index = 0; index < patterns.length; index++)
        if (!_field(patterns[index], 'matchOnly').toBoolValue()!) index,
    ];
    late final int primaryPatternIndex;
    if (explicitPrimaryIndexes case [final explicitIndex]) {
      if (!reversibleIndexes.contains(explicitIndex)) {
        _fail('Route "$id" primary pattern must be reversible.', element);
      }
      primaryPatternIndex = explicitIndex;
    } else if (reversibleIndexes case [final inferredIndex]) {
      primaryPatternIndex = inferredIndex;
    } else if (reversibleIndexes.isEmpty) {
      _fail(
        'Route "$id" needs a reversible Path or URI pattern; Regex patterns are match-only.',
        element,
      );
    } else {
      _fail(
        'Route "$id" has multiple reversible patterns; mark exactly one as primary.',
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
    final component = _ComponentModel.read(
      annotation.read('component'),
      element,
    );
    final visibleTo = annotation
        .read('visibleTo')
        .setValue
        .map((value) => value.toStringValue()!)
        .toSet();
    final exported = _enumValue(
      annotation.read('visibility').objectValue,
    ).endsWith('.exported');
    if (!exported && visibleTo.isNotEmpty) {
      _fail(
        'Component-only route "$id" cannot declare visibleTo consumers.',
        element,
      );
    }
    if (visibleTo.contains(component.id)) {
      _fail(
        'Route "$id" cannot list its owning component in visibleTo.',
        element,
      );
    }
    return _RouteModel(
      element,
      annotation,
      component,
      id,
      patterns,
      primaryPatternIndex,
      parameters,
      _typeSource(result, element.library),
    );
  }
}

/// Validated compile-time component identity used by route metadata builders.
final class _ComponentModel {
  /// Stores normalized descriptor fields after local structural validation.
  const _ComponentModel({
    required this.id,
    required this.version,
    required this.dependencies,
    required this.optionalDependencies,
  });

  /// Stable component ID.
  final String id;

  /// Semantic contract version.
  final String version;

  /// Required dependency IDs.
  final List<String> dependencies;

  /// Optional dependency IDs.
  final List<String> optionalDependencies;

  /// Validates a descriptor used by either a route or component annotation.
  static _ComponentModel read(ConstantReader descriptor, Element element) {
    final id = descriptor.read('id').stringValue;
    final version = descriptor.read('version').stringValue;
    final dependencies = descriptor
        .read('dependencies')
        .listValue
        .map((value) => value.toStringValue()!)
        .toList(growable: false);
    final optionalDependencies = descriptor
        .read('optionalDependencies')
        .listValue
        .map((value) => value.toStringValue()!)
        .toList(growable: false);
    final idPattern = RegExp(r'^[a-z][a-z0-9_.-]*$');
    if (!idPattern.hasMatch(id)) {
      _fail('Component ID "$id" is invalid.', element);
    }
    if (!RegExp(r'^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$').hasMatch(version)) {
      _fail('Component "$id" must use a semantic version.', element);
    }
    final all = [...dependencies, ...optionalDependencies];
    if (all.any(
          (dependency) => !idPattern.hasMatch(dependency) || dependency == id,
        ) ||
        all.toSet().length != all.length) {
      _fail(
        'Component "$id" has invalid, duplicate or self dependencies.',
        element,
      );
    }
    return _ComponentModel(
      id: id,
      version: version,
      dependencies: dependencies,
      optionalDependencies: optionalDependencies,
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
