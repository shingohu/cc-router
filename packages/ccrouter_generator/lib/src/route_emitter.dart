part of 'route_generator.dart';

/// Resolves one generated parameter type for the selected output library.
typedef _ParameterTypeEmitter = String Function(_ParameterModel parameter);

/// Resolves one constructor default for the selected output library.
typedef _ParameterDefaultEmitter = String? Function(_ParameterModel parameter);

/// Resolves an analyzer type in the namespace of the selected output library.
typedef _DartTypeEmitter = String Function(DartType type, Element owner);

/// Emits one standalone typed contract, callable factory, and registration.
String _emitStandaloneRoute(
  _RouteModel route, {
  required _ParameterTypeEmitter parameterType,
  required _DartTypeEmitter typeSource,
  required _ParameterDefaultEmitter parameterDefault,
}) {
  final resultType = typeSource(route.resultType, route.page);
  return '${_emitTypedRouteContract(route, parameterType: parameterType, typeSource: typeSource, resultType: resultType, parameterDefault: parameterDefault, includeOwnerMethods: false)}\n${_emitIntentFactory(route, parameterType: parameterType, resultType: resultType, parameterDefault: parameterDefault)}\n${_emitRouteOwnerGlue(route, resultType: resultType)}';
}

/// Emits a Pure Dart contract without page construction or registration APIs.
String _emitPublicRouteContract(
  _RouteModel route,
  _ContractImportPlan imports,
) => _emitTypedRouteContract(
  route,
  parameterType: imports.parameterType,
  typeSource: imports.typeSource,
  resultType: imports.typeSource(route.resultType, route.page),
  parameterDefault: imports.parameterDefault,
  includeOwnerMethods: false,
);

/// Emits Arguments, Intent, Definition, and Codec into one contract library.
String _emitTypedRouteContract(
  _RouteModel route, {
  required _ParameterTypeEmitter parameterType,
  required _DartTypeEmitter typeSource,
  required String resultType,
  required _ParameterDefaultEmitter parameterDefault,
  required bool includeOwnerMethods,
}) {
  final out = StringBuffer();
  final params = route.parameters;
  final declarations = params
      .map((parameter) {
        final defaultCode = parameterDefault(parameter);
        return '${parameter.required ? 'required ' : ''}${parameterType(parameter)} ${parameter.name}${defaultCode == null ? '' : ' = $defaultCode'}';
      })
      .join(', ');
  final constructorParameters = params
      .map((parameter) {
        final defaultCode = parameterDefault(parameter);
        final declaration = parameter.isQueryCollection
            ? '${parameterType(parameter)} ${parameter.name}'
            : 'this.${parameter.name}';
        return '${parameter.required ? 'required ' : ''}$declaration${defaultCode == null ? '' : ' = $defaultCode'}';
      })
      .join(', ');
  final collectionInitializers = params
      .where((parameter) => parameter.isQueryCollection)
      .map((parameter) {
        final collectionType = parameter.element.type as InterfaceType;
        final copy = collectionType.isDartCoreSet
            ? 'Set.unmodifiable(${parameter.name})'
            : 'List.unmodifiable(${parameter.name})';
        return '${parameter.name} = ${parameter.nullable ? '${parameter.name} == null ? null : ' : ''}$copy';
      })
      .join(', ');
  final signature = params.isEmpty ? '()' : '({$declarations})';
  final argsSignature = params.isEmpty
      ? '()'
      : '({$constructorParameters})${collectionInitializers.isEmpty ? '' : ' : $collectionInitializers'}';
  final argumentsConstructorPrefix = collectionInitializers.isEmpty
      ? 'const '
      : '';
  final assignments = params
      .map((parameter) => '${parameter.name}: ${parameter.name}')
      .join(', ');
  out.writeln('''
/// Immutable arguments for route ${route.id}; URI values remain typed.
final class ${route.arguments} {
  /// Creates arguments without navigating or retaining a backend context.
  $argumentsConstructorPrefix${route.arguments}$argsSignature;
''');
  for (final parameter in params) {
    out.writeln(
      '/// ${parameter.source} parameter ${parameter.wireName} for ${route.id}.\nfinal ${parameterType(parameter)} ${parameter.name};',
    );
  }
  out.writeln('}\n');
  out.writeln('''
/// ${_doc(route.annotation.read('description').isNull ? 'Typed contract for ${route.id}.' : route.annotation.read('description').stringValue)}
abstract final class ${route.api} {
  /// Stable identity used by registration, diagnostics and typed navigation.
  static const id = ${_quote(route.id)};

  /// Creates a typed Intent; navigate through CCRouter.navigator.
  static CCRouteIntent<$resultType> intent$signature =>
      ${route.intent}(${route.arguments}($assignments));

  /// Component-owned definition; business callers should use [intent].
  static final definition = CCRouteDefinition<${route.arguments}, $resultType>(
    routeId: id,
    patterns: ${_emitPatterns(route)},
    codec: const ${route.codec}(),
    deepLink: ${_constant(route.annotation.read('deepLink').objectValue)},
    presentation: ${_constant(route.annotation.read('presentation').objectValue)},
    placement: ${_constant(route.annotation.read('placement').objectValue)},
    interceptorIds: ${_constant(route.annotation.read('interceptors').objectValue)},
    popGuardIds: ${_constant(route.annotation.read('popGuards').objectValue)},
  );
''');
  if (includeOwnerMethods) {
    out.writeln('''
  /// Called by the owning component registrar, never by a business caller.
  static void register(CCRegistry registry) => registry.registerRoute(definition);

  /// Injects already decoded arguments into the page without backend coupling.
  static ${route.page.displayName} build(${route.arguments} arguments) =>
      ${route.page.displayName}(${_pageArguments(params)});
''');
  }
  out.writeln('}\n');
  out.writeln('''
/// Private data-only Intent carrying this route's typed result contract.
final class ${route.intent} implements CCRouteIntent<$resultType> {
  /// Captures immutable typed arguments for later Runtime validation.
  const ${route.intent}(this.arguments);

  /// Stable identity of the owned destination.
  @override
  String get routeId => ${route.api}.id;

  /// Typed payload consumed only by the matching route codec.
  @override
  final ${route.arguments} arguments;
}
''');
  _emitRouteCodec(
    out,
    route,
    parameterType: parameterType,
    typeSource: typeSource,
    parameterDefault: parameterDefault,
  );
  return out.toString();
}

/// Emits owner-only registration and metadata bridges without importing UI.
String _emitRouteOwnerGlue(_RouteModel route, {required String resultType}) =>
    '''
/// Package-internal bridge used by the generated component route index.
///
/// Keep this symbol out of public package barrels. It exists so a component
/// registrar can register library-private routes without exposing owner APIs.
void ${route.registrationFunction}(CCRegistry registry) =>
    registry.registerRoute(${route.api}.definition);

/// Typed route definition bridge shared by Host generation and page binding.
///
/// Retaining the generated argument type lets the isolated Flutter binding
/// access decoded fields without dynamic calls. Host aggregation may erase the
/// type only after page construction has been bound.
CCRouteDefinition<${route.arguments}, $resultType> ${route.descriptorFunction}() =>
    ${route.api}.definition;
''';

/// Emits the page construction bridge in an isolated Flutter binding library.
String _emitRouteBinding(
  _RouteModel route, {
  required String pageType,
  required String definition,
}) {
  final out = StringBuffer()
    ..writeln('''
/// Package-internal page factory bridge used by generated Flutter catalogs.
$pageType ${route.builderFunction}(
  CCEncodedRouteArguments ${route.parameters.isEmpty ? '_' : 'arguments'},
)''');
  if (route.parameters.isEmpty) {
    out.writeln('    => $pageType();');
    return out.toString();
  }
  out
    ..writeln('{')
    ..writeln('  final decoded = $definition.codec.decode(arguments);')
    ..writeln(
      '  return $pageType(${_pageArgumentsFromDecoded(route.parameters, 'decoded')});',
    )
    ..writeln('}');
  return out.toString();
}

/// Emits the callable factory re-exported by the component's unique Route API.
String _emitIntentFactory(
  _RouteModel route, {
  required _ParameterTypeEmitter parameterType,
  required String resultType,
  required _ParameterDefaultEmitter parameterDefault,
}) {
  final declarations = route.parameters
      .map((parameter) {
        final defaultCode = parameterDefault(parameter);
        return '${parameter.required ? 'required ' : ''}${parameterType(parameter)} ${parameter.name}${defaultCode == null ? '' : ' = $defaultCode'}';
      })
      .join(', ');
  final signature = route.parameters.isEmpty ? '()' : '({$declarations})';
  final arguments = route.parameters
      .map((parameter) => '${parameter.name}: ${parameter.name}')
      .join(', ');
  return '''
/// Package-internal typed factory surfaced by the generated component API.
final class ${route.intentFactory} {
  /// Creates the stateless factory used by generated static route members.
  const ${route.intentFactory}();

  /// Creates an immutable Intent without performing navigation.
  CCRouteIntent<$resultType> call$signature =>
      ${route.api}.intent($arguments);
}
''';
}

/// Emits implementation-only glue for a Contract-first destination page.
String _emitImplementationGlue(
  _RouteImplementationModel implementation, {
  required String pageType,
  required String contractApi,
}) {
  final route = implementation.contract;
  return '''
/// Package-internal bridge used by the generated component route index.
///
/// Registration retains the external Pure Dart contract as the single source
/// of route identity, parameters, and navigation policy.
void ${implementation.registrationFunction}(CCRegistry registry) =>
    registry.registerRoute($contractApi.definition);

/// Package-internal route definition bridge used by Host generation.
CCRouteDefinition<dynamic, dynamic> ${implementation.descriptorFunction}() =>
    $contractApi.definition;

/// Package-internal page factory bound to the public route contract.
$pageType ${implementation.builderFunction}(
  CCEncodedRouteArguments ${route.parameters.isEmpty ? '_' : 'arguments'},
) {
  ${route.parameters.isEmpty ? 'return $pageType();' : 'final decoded = $contractApi.definition.codec.decode(arguments);\n  return $pageType(\n    ${_pageArgumentsFromDecoded(route.parameters, 'decoded')}\n  );'}
}
''';
}

/// Emits the private boundary Codec shared by Intent and Runtime registration.
void _emitRouteCodec(
  StringBuffer out,
  _RouteModel route, {
  required _ParameterTypeEmitter parameterType,
  required _DartTypeEmitter typeSource,
  required _ParameterDefaultEmitter parameterDefault,
}) {
  final params = route.parameters;
  out.writeln('''
/// Private boundary conversion; raw input is never included in error messages.
final class ${route.codec} implements CCRouteCodec<${route.arguments}> {
  /// Stateless codec shared by the component's route definition.
  const ${route.codec}();

  /// Rejects missing, repeated or malformed values before creating arguments.
  @override
  ${route.arguments} decode(CCEncodedRouteArguments input) {
''');
  for (final parameter in params.where(
    (parameter) =>
        parameter.source != 'extra' &&
        parameter.queryCodecType == null &&
        parameter.queryValueType.isDartCoreDouble,
  )) {
    out.writeln('''
    double _parse_${parameter.name}(String raw) {
      final value = double.tryParse(raw);
      if (value == null || !value.isFinite) {
        throw CCRouteParameterError(${_quote('Route "${route.id}" parameter "${parameter.wireName}" must be finite.')});
      }
      return value;
    }
''');
  }
  for (final parameter in params) {
    final error = _quote(
      'Route "${route.id}" parameter "${parameter.wireName}" is invalid.',
    );
    final missing =
        parameterDefault(parameter) ??
        (parameter.nullable ? 'null' : 'throw CCRouteParameterError($error)');
    if (parameter.source == 'extra') {
      out.writeln(
        'final _value_${parameter.name} = input.extra == null ? $missing : input.extra;',
      );
      out.writeln(
        'if (_value_${parameter.name} is! ${parameterType(parameter)}) throw CCRouteParameterError($error);',
      );
      continue;
    }
    if (parameter.source == 'query') {
      out.writeln(
        'final _values_${parameter.name} = input.query[${_quote(parameter.wireName)}];',
      );
      if (parameter.queryCodecType != null || parameter.isQueryCollection) {
        out.writeln(
          'if (_values_${parameter.name} != null && _values_${parameter.name}.isEmpty) throw CCRouteParameterError($error);',
        );
        final decoded = parameter.queryCodecType == null
            ? _decodeQueryCollection(
                parameter,
                error,
                valueType: typeSource(
                  parameter.queryValueType,
                  parameter.element,
                ),
              )
            : _decodeCustomQuery(
                parameter,
                error,
                codecType: typeSource(
                  parameter.queryCodecType!,
                  parameter.element,
                ),
              );
        out.writeln(
          'final ${parameterType(parameter)} _value_${parameter.name} = _values_${parameter.name} == null ? $missing : $decoded;',
        );
        continue;
      }
      out.writeln(
        'if (_values_${parameter.name} != null && _values_${parameter.name}.length != 1) throw CCRouteParameterError($error);',
      );
      out.writeln(
        'final _raw_${parameter.name} = _values_${parameter.name}?.single;',
      );
    } else {
      out.writeln(
        'final _raw_${parameter.name} = input.path[${_quote(parameter.wireName)}];',
      );
    }
    out.writeln(
      'final ${parameterType(parameter)} _value_${parameter.name} = _raw_${parameter.name} == null ? $missing : ${_decodeScalarValue(parameter.queryValueType, '_raw_${parameter.name}', error, type: typeSource(parameter.queryValueType, parameter.element), doubleParser: '_parse_${parameter.name}')};',
    );
  }
  out.writeln(
    'return ${route.arguments}(${params.map((parameter) => '${parameter.name}: _value_${parameter.name}').join(', ')});\n}\n',
  );
  out.writeln('''
  /// Encodes unescaped scalar values; Runtime owns URI escaping exactly once.
  @override
  CCEncodedRouteArguments encode(${route.arguments} arguments) {
''');
  for (final parameter in params.where(
    (parameter) =>
        parameter.queryCodecType == null &&
        parameter.queryValueType.isDartCoreDouble &&
        parameter.source != 'extra',
  )) {
    final value = 'arguments.${parameter.name}${parameter.nullable ? '!' : ''}';
    final invalid = parameter.isQueryCollection
        ? '$value.any((value) => !value.isFinite)'
        : '!$value.isFinite';
    out.writeln(
      'if (${parameter.nullable ? 'arguments.${parameter.name} != null && ' : ''}$invalid) throw CCRouteParameterError(${_quote('Route "${route.id}" parameter "${parameter.wireName}" must be finite.')});',
    );
  }
  for (final parameter in params.where(
    (parameter) => parameter.isQueryCollection,
  )) {
    if (parameter.encodesEmptyQueryCollectionAsAbsent) continue;
    final value = 'arguments.${parameter.name}${parameter.nullable ? '!' : ''}';
    out.writeln(
      'if (${parameter.nullable ? 'arguments.${parameter.name} != null && ' : ''}$value.isEmpty) throw CCRouteParameterError(${_quote('Route "${route.id}" parameter "${parameter.wireName}" cannot encode an empty collection.')});',
    );
  }
  out.writeln('return CCEncodedRouteArguments(path: {');
  for (final parameter in params.where(
    (parameter) => parameter.source == 'path',
  )) {
    out.writeln(
      '${_quote(parameter.wireName)}: ${_encodeScalarValue(parameter.queryValueType, 'arguments.${parameter.name}')},',
    );
  }
  out.writeln('}, query: {');
  for (final parameter in params.where(
    (parameter) => parameter.source == 'query',
  )) {
    final encoded = parameter.queryCodecType != null
        ? _encodeCustomQuery(
            parameter,
            _quote(
              'Route "${route.id}" parameter "${parameter.wireName}" is invalid.',
            ),
            codecType: typeSource(parameter.queryCodecType!, parameter.element),
          )
        : parameter.isQueryCollection
        ? _encodeQueryCollection(parameter)
        : '[${_encodeScalarValue(parameter.queryValueType, 'arguments.${parameter.name}${parameter.nullable ? '!' : ''}')}]';
    final inclusion = parameter.nullable
        ? 'if (arguments.${parameter.name} != null) '
        : parameter.encodesEmptyQueryCollectionAsAbsent
        ? 'if (arguments.${parameter.name}.isNotEmpty) '
        : '';
    out.writeln('$inclusion${_quote(parameter.wireName)}: $encoded,');
  }
  out.writeln(
    '}, extra: ${params.where((parameter) => parameter.source == 'extra').isEmpty ? 'null' : 'arguments.${params.singleWhere((parameter) => parameter.source == 'extra').name}'});\n}\n}',
  );
}

/// Emits the normalized route patterns with one effective primary entry.
String _emitPatterns(_RouteModel route) =>
    'const [${route.patterns.indexed.map((entry) => _emitPattern(entry.$2, primary: entry.$1 == route.primaryPatternIndex)).join(', ')}]';

/// Serializes one supported pattern while applying its effective primary flag.
String _emitPattern(DartObject pattern, {required bool primary}) {
  final type = (pattern.type as InterfaceType).element.displayName;
  if (type == 'CCRegexPattern') return _constant(pattern);
  return 'const $type(${_constant(_field(pattern, 'template'))}, primary: $primary, constraints: ${_constant(_field(pattern, 'constraints'))})';
}

/// Converts multiline metadata into line-comment text, never source directives.
String _doc(String value) =>
    value.replaceAll('\r', '').replaceAll('\n', '\n/// ');

/// Preserves positional versus named page constructor invocation semantics.
String _pageArguments(List<_ParameterModel> parameters) => parameters
    .map(
      (parameter) =>
          '${parameter.element.isNamed ? '${parameter.name}: ' : ''}arguments.${parameter.name}',
    )
    .join(', ');

/// Builds a page invocation from one decoded contract expression exactly once.
String _pageArgumentsFromDecoded(
  List<_ParameterModel> parameters,
  String decodedExpression,
) {
  if (parameters.isEmpty) return '';
  return [
    for (final parameter in parameters)
      '${parameter.element.isNamed ? '${parameter.name}: ' : ''}$decodedExpression.${parameter.name}',
  ].join(', ');
}

/// Emits strict scalar parsing with safe, route-specific error information.
String _decodeScalarValue(
  InterfaceType interfaceType,
  String raw,
  String error, {
  required String type,
  required String doubleParser,
}) {
  if (interfaceType.isDartCoreString) return raw;
  if (interfaceType.isDartCoreInt) {
    return '(int.tryParse($raw) ?? (throw CCRouteParameterError($error)))';
  }
  if (interfaceType.isDartCoreDouble) return '$doubleParser($raw)';
  if (interfaceType.isDartCoreBool) {
    return 'switch ($raw) { "true" => true, "false" => false, _ => throw CCRouteParameterError($error) }';
  }
  final enumName = type.replaceFirst(RegExp(r'\?$'), '');
  final cases = interfaceType.element.fields
      .where((field) => field.isEnumConstant)
      .map(
        (field) =>
            '${_quote(field.displayName)} => $enumName.${field.displayName}',
      )
      .join(', ');
  return 'switch ($raw) { $cases, _ => throw CCRouteParameterError($error) }';
}

/// Emits scalar strings without URL encoding; enum wire values are stable names.
String _encodeScalarValue(InterfaceType type, String value) {
  if (type.isDartCoreString) return value;
  if (type.element is EnumElement) return 'EnumName($value).name';
  return '$value.toString()';
}

/// Emits repeated Query decoding while preserving List order and Set semantics.
String _decodeQueryCollection(
  _ParameterModel parameter,
  String error, {
  required String valueType,
}) {
  final raw = 'raw_${parameter.name}';
  final decoded = _decodeScalarValue(
    parameter.queryValueType,
    raw,
    error,
    type: valueType,
    doubleParser: '_parse_${parameter.name}',
  );
  final conversion = '_values_${parameter.name}.map(($raw) => $decoded)';
  final collectionType = parameter.element.type as InterfaceType;
  return collectionType.isDartCoreSet
      ? 'Set<$valueType>.unmodifiable($conversion)'
      : 'List<$valueType>.unmodifiable($conversion)';
}

/// Emits a sanitized custom Query decode boundary without leaking raw values.
String _decodeCustomQuery(
  _ParameterModel parameter,
  String error, {
  required String codecType,
}) =>
    '(() { try { return const $codecType().decode(List<String>.unmodifiable(_values_${parameter.name})); } catch (_) { throw CCRouteParameterError($error); } })()';

/// Emits repeated Query encoding; Set values are sorted for canonical URIs.
String _encodeQueryCollection(_ParameterModel parameter) {
  final value = 'arguments.${parameter.name}${parameter.nullable ? '!' : ''}';
  final encoded = _encodeScalarValue(parameter.queryValueType, 'value');
  final values = '[for (final value in $value) $encoded]';
  final collectionType = parameter.element.type as InterfaceType;
  if (!collectionType.isDartCoreSet) return values;
  return '(() { final values = <String>$values; values.sort(); return values; })()';
}

/// Emits a sanitized custom Query encode boundary with non-empty output.
String _encodeCustomQuery(
  _ParameterModel parameter,
  String error, {
  required String codecType,
}) {
  final value = 'arguments.${parameter.name}${parameter.nullable ? '!' : ''}';
  return '(() { try { final values = const $codecType().encode($value); if (values.isEmpty) throw const FormatException(); return List<String>.unmodifiable(values); } catch (_) { throw CCRouteParameterError($error); } })()';
}
