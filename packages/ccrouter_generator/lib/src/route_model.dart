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
    this.resultType,
    this.contractFirst,
  );

  /// Annotated page or abstract schema supplying the normalized route model.
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
  final DartType resultType;

  /// Whether the source is an abstract Contract-first schema rather than UI.
  final bool contractFirst;

  /// Return type rendered for the source library's existing import namespace.
  String get result => _typeSource(resultType, page.library);

  /// Source-level import boundary recorded before workspace aggregation.
  ///
  /// Page annotations are library-private. Contract-first declarations are
  /// public, while the workspace later derives whether their implementation is
  /// in the same Package or an external contracts Package.
  String get exposure => contractFirst ? 'public' : 'internal';

  /// Stable generated API stem shared by contract and implementation packages.
  String get apiStem {
    final name = page.displayName.replaceFirst(RegExp(r'^_'), '');
    if (!contractFirst) return '${name}Route';
    return name.substring(0, name.length - 'Contract'.length);
  }

  /// Public exported or library-private route API name.
  String get api => '${contractFirst ? '' : '_'}$apiStem';

  /// Immutable argument type kept at the same exposure as the route API.
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
  static _RouteModel read(
    Element element,
    ConstantReader annotation, {
    bool contractFirst = false,
  }) {
    if (element is! ClassElement ||
        element.isAbstract != contractFirst ||
        element.typeParameters.isNotEmpty) {
      _fail(
        contractFirst
            ? 'CCRouteContract requires an abstract, non-generic schema class.'
            : 'CCRoute requires a concrete, non-generic page class.',
        element,
      );
    }
    if (contractFirst &&
        (!element.displayName.endsWith('RouteContract') ||
            element.displayName == 'RouteContract')) {
      _fail(
        'CCRouteContract schema names must end with RouteContract.',
        element,
      );
    }
    final id = annotation.read('id').stringValue;
    _validateStableId(id, 'Route ID', element);
    final interceptorIds = annotation
        .read('interceptors')
        .listValue
        .map((value) => value.toStringValue()!)
        .toList(growable: false);
    final popGuardIds = annotation
        .read('popGuards')
        .listValue
        .map((value) => value.toStringValue()!)
        .toList(growable: false);
    _validatePolicyIds(interceptorIds, 'Route interceptor ID', element);
    _validatePolicyIds(popGuardIds, 'Route Pop guard ID', element);
    final placement = annotation.read('placement').objectValue;
    final hostId = _field(placement, 'hostId').toStringValue()!;
    final parentRouteId = _field(placement, 'parentRouteId').toStringValue();
    final shellId = _field(placement, 'shellId').toStringValue();
    final navigatorOutlet = _field(
      placement,
      'navigatorOutlet',
    ).toStringValue()!;
    _validateStableId(hostId, 'Host ID', element);
    _validateStableId(navigatorOutlet, 'Navigator Outlet ID', element);
    if (parentRouteId != null) {
      _validateStableId(parentRouteId, 'Parent Route ID', element);
      if (parentRouteId == id) {
        _fail('Route "$id" cannot be its own parent.', element);
      }
    }
    if (shellId != null) _validateStableId(shellId, 'Shell ID', element);
    final description = annotation.read('description');
    if (!description.isNull &&
        description.stringValue.length > _maxRouteDescriptionLength) {
      _fail(
        'Route "$id" description exceeds $_maxRouteDescriptionLength characters.',
        element,
      );
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
        if ((patterns[index].type as InterfaceType).element.displayName !=
            'CCRegexPattern')
          index,
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
        if (template.length > _maxRouteRegexLength) {
          _fail(
            'Route "$id" regular expression exceeds $_maxRouteRegexLength characters.',
            element,
          );
        }
        try {
          RegExp(template);
        } on FormatException {
          _fail('Route "$id" has an invalid regular expression.', element);
        }
        final captures = RegExp(
          r'\(\?<([a-zA-Z_]\w*)>',
        ).allMatches(template).toList(growable: false);
        if (captures.length > _maxRouteRegexCaptures) {
          _fail(
            'Route "$id" regular expression exceeds $_maxRouteRegexCaptures named captures.',
            element,
          );
        }
        patternKeys = captures.map((match) => match[1]!).toSet();
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
          final constraint = entry.value!.toStringValue()!;
          if (constraint.length > _maxConstraintRegexLength) {
            _fail(
              'Route "$id" parameter constraint exceeds '
              '$_maxConstraintRegexLength characters.',
              element,
            );
          }
          try {
            RegExp(constraint);
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
    final component = _ComponentModel.read(
      annotation.read('component'),
      element,
    );
    return _RouteModel(
      element,
      annotation,
      component,
      id,
      patterns,
      primaryPatternIndex,
      parameters,
      result,
      contractFirst,
    );
  }
}

/// Validates ordered policy references and rejects duplicate execution entries.
void _validatePolicyIds(List<String> ids, String kind, Element element) {
  final seen = <String>{};
  for (final id in ids) {
    _validateStableId(id, kind, element);
    if (!seen.add(id)) _fail('Duplicate $kind "$id".', element);
  }
}

/// Validated binding between one Contract-first schema and its concrete page.
final class _RouteImplementationModel {
  /// Stores the destination after constructor compatibility has been proven.
  const _RouteImplementationModel({
    required this.page,
    required this.contract,
    required this.contractPrefix,
  });

  /// Concrete Flutter destination owned by the implementing component.
  final ClassElement page;

  /// Pure Dart route contract imported from the domain contracts package.
  final _RouteModel contract;

  /// Import prefix used by the page library for the contract package.
  final String contractPrefix;

  /// Generated route API as referenced from the implementation library.
  String get contractApi => '$contractPrefix${contract.api}';

  /// Stable package-internal bridge used by the generated component index.
  String get registrationFunction =>
      'ccrouterRegister${page.displayName.replaceFirst(RegExp(r'^_'), '')}Route';

  /// Adapter-neutral metadata bridge consumed by Host generation.
  String get descriptorFunction =>
      'ccrouterDescribe${page.displayName.replaceFirst(RegExp(r'^_'), '')}Route';

  /// Page-construction bridge that decodes through the external contract.
  String get builderFunction =>
      'ccrouterBuild${page.displayName.replaceFirst(RegExp(r'^_'), '')}Route';

  /// Reads the referenced contract and verifies exact constructor compatibility.
  static _RouteImplementationModel read(
    Element element,
    ConstantReader annotation,
  ) {
    if (element is! ClassElement ||
        element.isAbstract ||
        element.typeParameters.isNotEmpty) {
      _fail(
        'CCRouteImplementation requires a concrete, non-generic page class.',
        element,
      );
    }
    final constructor = element.unnamedConstructor;
    if (constructor == null || constructor.isFactory) {
      _fail(
        'CCRouteImplementation requires an unnamed generative constructor.',
        element,
      );
    }
    final contractType = annotation.read('contract').typeValue;
    final contractElement = contractType.element;
    if (contractElement is! ClassElement) {
      _fail(
        'CCRouteImplementation must reference a CCRouteContract schema class.',
        element,
      );
    }
    const checker = TypeChecker.typeNamedLiterally(
      'CCRouteContract',
      inPackage: 'ccrouter_contracts',
    );
    final contractAnnotations = checker
        .annotationsOfExact(contractElement)
        .toList(growable: false);
    if (contractAnnotations.length != 1) {
      _fail(
        'CCRouteImplementation must reference exactly one CCRouteContract declaration.',
        element,
      );
    }
    final contract = _RouteModel.read(
      contractElement,
      ConstantReader(contractAnnotations.single),
      contractFirst: true,
    );
    String? contractPrefix;
    for (final fragment in element.library.fragments) {
      for (final directive in fragment.libraryImports) {
        final prefix = directive.prefix?.element.displayName;
        final visible =
            directive.namespace.get2(contractElement.displayName) ==
                contractElement ||
            (prefix != null &&
                directive.namespace.getPrefixed2(
                      prefix,
                      contractElement.displayName,
                    ) ==
                    contractElement);
        if (visible) {
          contractPrefix = prefix == null ? '' : '$prefix.';
          break;
        }
      }
      if (contractPrefix != null) break;
    }
    if (contractPrefix == null) {
      _fail(
        'CCRouteImplementation contract must be available through an explicit import.',
        element,
      );
    }
    final pageParameters = constructor.formalParameters
        .where(
          (parameter) =>
              !(parameter.displayName == 'key' &&
                  parameter.isOptional &&
                  parameter.isNamed),
        )
        .toList(growable: false);
    if (pageParameters.length != contract.parameters.length) {
      _fail(
        'Route implementation for "${contract.id}" must declare exactly the contract parameters plus an optional key.',
        element,
      );
    }
    for (var index = 0; index < contract.parameters.length; index++) {
      final expected = contract.parameters[index].element;
      final actual = pageParameters[index];
      final typeSystem = element.library.typeSystem;
      final sameType =
          typeSystem.isAssignableTo(actual.type, expected.type) &&
          typeSystem.isAssignableTo(expected.type, actual.type);
      if (actual.displayName != expected.displayName ||
          actual.isNamed != expected.isNamed ||
          !sameType) {
        _fail(
          'Route implementation parameter "${actual.displayName}" does not match contract parameter "${expected.displayName}".',
          actual,
        );
      }
    }
    return _RouteImplementationModel(
      page: element,
      contract: contract,
      contractPrefix: contractPrefix,
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
    _validateComponentId(id, element);
    if (!_semanticVersionPattern.hasMatch(version)) {
      _fail('Component "$id" must use a SemVer 2.0 version.', element);
    }
    final all = [...dependencies, ...optionalDependencies];
    if (all.any(
          (dependency) =>
              dependency.length > _maxStableIdLength ||
              !_componentIdPattern.hasMatch(dependency) ||
              dependency == id,
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
  _ParameterModel(
    this.element,
    this.source,
    this.wireName, {
    this.queryCodecType,
  });

  /// Original parameter for Dart defaults, nullability and page invocation.
  final FormalParameterElement element;

  /// One of path, query or extra; unknown sources are compile-time errors.
  final String source;

  /// URI key; Extra uses its Dart name for diagnostic messages only.
  final String wireName;

  /// Explicit complex Query codec validated against the parameter value type.
  final InterfaceType? queryCodecType;

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

  /// Whether the Query value uses one repeated key for a `List` or `Set`.
  bool get isQueryCollection {
    final type = element.type;
    return source == 'query' &&
        type is InterfaceType &&
        (type.isDartCoreList || type.isDartCoreSet);
  }

  /// Collection element type, or the scalar parameter type for URI conversion.
  InterfaceType get queryValueType {
    final type = element.type as InterfaceType;
    return isQueryCollection
        ? type.typeArguments.single as InterfaceType
        : type;
  }

  /// Stable cardinality recorded in generated route documentation.
  String get queryCardinality =>
      isQueryCollection || queryCodecType != null ? 'repeated' : 'single';

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
    final codecType = queries.isEmpty
        ? null
        : queries.single.getField('codec')?.toTypeValue();
    final model = _ParameterModel(
      parameter,
      source,
      wireName,
      queryCodecType: codecType is InterfaceType ? codecType : null,
    );
    if (codecType != null && codecType is! InterfaceType) {
      _fail(
        'Query codec for "${parameter.displayName}" must be a concrete class type.',
        parameter,
      );
    }
    if (source == 'path' && (model.nullable || model.defaultCode != null)) {
      _fail(
        'Path parameters must be non-nullable without defaults.',
        parameter,
      );
    }
    if (model.queryCodecType != null) {
      _validateQueryCodec(model);
    } else if (source != 'extra') {
      final type = parameter.type;
      if (type is! InterfaceType || !_isSupportedUriType(type, source)) {
        _fail(
          'URI parameters support String, int, double, bool, enums, and Query-only List/Set collections of those values; use Extra or an explicit Query codec for objects.',
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

  /// Checks the closed set of scalar and repeated URI parameter types.
  static bool _isSupportedUriType(InterfaceType type, String source) {
    if (_isSupportedUriScalar(type)) return true;
    if (source != 'query' ||
        (!type.isDartCoreList && !type.isDartCoreSet) ||
        type.typeArguments.length != 1) {
      return false;
    }
    final element = type.typeArguments.single;
    return element is InterfaceType &&
        element.nullabilitySuffix != NullabilitySuffix.question &&
        _isSupportedUriScalar(element);
  }

  /// Checks one URI scalar without accepting nested or nullable elements.
  static bool _isSupportedUriScalar(InterfaceType type) =>
      type.isDartCoreString ||
      type.isDartCoreInt ||
      type.isDartCoreDouble ||
      type.isDartCoreBool ||
      type.element is EnumElement;

  /// Validates a stateless complex Query codec and its exact generic contract.
  static void _validateQueryCodec(_ParameterModel model) {
    final parameter = model.element;
    final parameterType = parameter.type;
    if (model.source != 'query' ||
        parameterType is! InterfaceType ||
        _isSupportedUriType(parameterType, 'query')) {
      _fail(
        'Query codec for "${parameter.displayName}" is only valid for a non-scalar, non-collection Query object.',
        parameter,
      );
    }
    final codecType = model.queryCodecType!;
    final codecElement = codecType.element;
    if (codecElement is! ClassElement ||
        codecElement.isAbstract ||
        codecElement.typeParameters.isNotEmpty) {
      _fail(
        'Query codec for "${parameter.displayName}" must be a concrete, non-generic class.',
        parameter,
      );
    }
    final constructor = codecElement.unnamedConstructor;
    if (constructor == null ||
        constructor.isFactory ||
        !constructor.isConst ||
        constructor.formalParameters.isNotEmpty) {
      _fail(
        'Query codec for "${parameter.displayName}" requires a const unnamed constructor without parameters.',
        parameter,
      );
    }
    final codecContracts = codecElement.allSupertypes.where(
      (type) =>
          type.element.displayName == 'CCRouteQueryCodec' &&
          type.element.library.uri.toString().startsWith(
            'package:ccrouter_contracts/',
          ),
    );
    if (codecContracts.length != 1) {
      _fail(
        'Query codec for "${parameter.displayName}" must implement CCRouteQueryCodec<T>.',
        parameter,
      );
    }
    final valueType = codecContracts.single.typeArguments.single;
    final expectedType = parameter.library!.typeSystem.promoteToNonNull(
      parameterType,
    );
    final typeSystem = parameter.library!.typeSystem;
    if (!typeSystem.isAssignableTo(valueType, expectedType) ||
        !typeSystem.isAssignableTo(expectedType, valueType)) {
      _fail(
        'Query codec value type for "${parameter.displayName}" must exactly match the parameter type.',
        parameter,
      );
    }
  }
}
