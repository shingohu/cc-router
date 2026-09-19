part of 'route_generator.dart';

/// Resolves one generated parameter type for the selected output library.
typedef _ParameterTypeEmitter = String Function(_ParameterModel parameter);

/// Resolves one constructor default for the selected output library.
typedef _ParameterDefaultEmitter = String? Function(_ParameterModel parameter);

/// Emits one library-private page contract and its owner-only glue.
String _emitRoute(_RouteModel route) =>
    '${_emitTypedRouteContract(route, parameterType: (parameter) => parameter.type, resultType: route.result, parameterDefault: (parameter) => parameter.defaultCode, includeOwnerMethods: true)}\n${_emitRouteGlue(route, embedded: true)}';

/// Emits a Pure Dart contract without page construction or registration APIs.
String _emitPublicRouteContract(
  _RouteModel route,
  _ContractImportPlan imports,
) => _emitTypedRouteContract(
  route,
  parameterType: imports.parameterType,
  resultType: imports.typeSource(route.resultType, route.page),
  parameterDefault: imports.parameterDefault,
  includeOwnerMethods: false,
);

/// Emits Arguments, Intent, Definition, and Codec into one contract library.
String _emitTypedRouteContract(
  _RouteModel route, {
  required _ParameterTypeEmitter parameterType,
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
  final fields = params
      .map((parameter) {
        final defaultCode = parameterDefault(parameter);
        return '${parameter.required ? 'required ' : ''}this.${parameter.name}${defaultCode == null ? '' : ' = $defaultCode'}';
      })
      .join(', ');
  final signature = params.isEmpty ? '()' : '({$declarations})';
  final argsSignature = params.isEmpty ? '()' : '({$fields})';
  final assignments = params
      .map((parameter) => '${parameter.name}: ${parameter.name}')
      .join(', ');
  out.writeln('''
/// Immutable arguments for route ${route.id}; URI values remain typed.
final class ${route.arguments} {
  /// Creates arguments without navigating or retaining a backend context.
  const ${route.arguments}$argsSignature;
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
    description: ${_constant(route.annotation.objectValue.getField('description')!)},
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
    parameterDefault: parameterDefault,
  );
  return out.toString();
}

/// Emits owner-only registration, metadata, and page construction bridges.
String _emitRouteGlue(_RouteModel route, {required bool embedded}) {
  final registration = embedded
      ? '${route.api}.register(registry)'
      : 'registry.registerRoute(${route.api}.definition)';
  final out = StringBuffer()
    ..writeln('''
/// Package-internal bridge used by the generated component route index.
///
/// Keep this symbol out of public package barrels. It exists so a component
/// registrar can register library-private routes without exposing owner APIs.
void ${route.registrationFunction}(CCRegistry registry) => $registration;

/// Package-internal adapter-neutral metadata bridge used by Host generation.
CCNavigationRoute ${route.descriptorFunction}() {
  final definition = ${route.api}.definition;
  return CCNavigationRoute(
    routeId: definition.routeId,
    patterns: definition.patterns,
    presentation: definition.presentation,
    deepLink: definition.deepLink,
    placement: definition.placement,
  );
}

/// Package-internal page factory bridge used by generated Flutter catalogs.
${route.page.displayName} ${route.builderFunction}(
  CCEncodedRouteArguments arguments,
)''');
  if (embedded) {
    out.writeln(
      '    => ${route.api}.build(${route.api}.definition.codec.decode(arguments));',
    );
  } else {
    out
      ..writeln('{')
      ..writeln(
        '  final decoded = ${route.api}.definition.codec.decode(arguments);',
      )
      ..writeln(
        '  return ${route.page.displayName}(${_pageArgumentsFromDecoded(route.parameters, 'decoded')});',
      )
      ..writeln('}');
  }
  return out.toString();
}

/// Emits implementation-only glue for a Contract-first destination page.
String _emitImplementationGlue(_RouteImplementationModel implementation) {
  final route = implementation.contract;
  final api = implementation.contractApi;
  return '''
/// Package-internal bridge used by the generated component route index.
///
/// Registration retains the external Pure Dart contract as the single source
/// of route identity, parameters, and navigation policy.
void ${implementation.registrationFunction}(CCRegistry registry) =>
    registry.registerRoute($api.definition);

/// Package-internal adapter-neutral metadata bridge used by Host generation.
CCNavigationRoute ${implementation.descriptorFunction}() {
  final definition = $api.definition;
  return CCNavigationRoute(
    routeId: definition.routeId,
    patterns: definition.patterns,
    presentation: definition.presentation,
    deepLink: definition.deepLink,
    placement: definition.placement,
  );
}

/// Package-internal page factory bound to the public route contract.
${implementation.page.displayName} ${implementation.builderFunction}(
  CCEncodedRouteArguments arguments,
) {
  final decoded = $api.definition.codec.decode(arguments);
  return ${implementation.page.displayName}(
    ${_pageArgumentsFromDecoded(route.parameters, 'decoded')}
  );
}
''';
}

/// Emits the private boundary Codec shared by Intent and Runtime registration.
void _emitRouteCodec(
  StringBuffer out,
  _RouteModel route, {
  required _ParameterTypeEmitter parameterType,
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
        (parameter.element.type as InterfaceType).isDartCoreDouble,
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
      'final ${parameterType(parameter)} _value_${parameter.name} = _raw_${parameter.name} == null ? $missing : ${_decodeValue(parameter, error, type: parameterType(parameter))};',
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
        parameter.element.type is InterfaceType &&
        (parameter.element.type as InterfaceType).isDartCoreDouble &&
        parameter.source != 'extra',
  )) {
    out.writeln(
      'if (${parameter.nullable ? 'arguments.${parameter.name} != null && !arguments.${parameter.name}!.isFinite' : '!arguments.${parameter.name}.isFinite'}) throw CCRouteParameterError(${_quote('Route "${route.id}" parameter "${parameter.wireName}" must be finite.')});',
    );
  }
  out.writeln('return CCEncodedRouteArguments(path: {');
  for (final parameter in params.where(
    (parameter) => parameter.source == 'path',
  )) {
    out.writeln('${_quote(parameter.wireName)}: ${_encodeValue(parameter)},');
  }
  out.writeln('}, query: {');
  for (final parameter in params.where(
    (parameter) => parameter.source == 'query',
  )) {
    out.writeln(
      '${parameter.nullable ? 'if (arguments.${parameter.name} != null) ' : ''}${_quote(parameter.wireName)}: [${_encodeValue(parameter)}],',
    );
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
String _decodeValue(
  _ParameterModel parameter,
  String error, {
  required String type,
}) {
  final interfaceType = parameter.element.type as InterfaceType;
  final raw = '_raw_${parameter.name}';
  if (interfaceType.isDartCoreString) return raw;
  if (interfaceType.isDartCoreInt) {
    return '(int.tryParse($raw) ?? (throw CCRouteParameterError($error)))';
  }
  if (interfaceType.isDartCoreDouble) return '_parse_${parameter.name}($raw)';
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
String _encodeValue(_ParameterModel parameter) {
  final type = parameter.element.type as InterfaceType;
  final value = 'arguments.${parameter.name}${parameter.nullable ? '!' : ''}';
  if (type.isDartCoreString) return value;
  if (type.element is EnumElement) return 'EnumName($value).name';
  return '$value.toString()';
}
