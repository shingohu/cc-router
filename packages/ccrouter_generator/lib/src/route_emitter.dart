part of 'route_generator.dart';

/// Emits cohesive typed contracts plus private codec and Intent implementations.
String _emitRoute(_RouteModel route) {
  final out = StringBuffer();
  final params = route.parameters;
  final declarations = params
      .map(
        (p) =>
            '${p.required ? 'required ' : ''}${p.type} ${p.name}${p.defaultCode == null ? '' : ' = ${p.defaultCode}'}',
      )
      .join(', ');
  final fields = params
      .map(
        (p) =>
            '${p.required ? 'required ' : ''}this.${p.name}${p.defaultCode == null ? '' : ' = ${p.defaultCode}'}',
      )
      .join(', ');
  final signature = params.isEmpty ? '()' : '({$declarations})';
  final argsSignature = params.isEmpty ? '()' : '({$fields})';
  final assignments = params.map((p) => '${p.name}: ${p.name}').join(', ');
  out.writeln('''
/// Immutable arguments for route ${route.id}; URI values remain typed.
final class ${route.arguments} {
  /// Creates arguments without navigating or retaining a backend context.
  const ${route.arguments}$argsSignature;
''');
  for (final p in params) {
    out.writeln(
      '/// ${p.source} parameter ${p.wireName} for ${route.id}.\nfinal ${p.type} ${p.name};',
    );
  }
  out.writeln('}\n');
  out.writeln('''
/// ${_doc(route.annotation.read('description').isNull ? 'Typed contract for ${route.id}.' : route.annotation.read('description').stringValue)}
abstract final class ${route.api} {
  /// Stable identity used by registration, diagnostics and typed navigation.
  static const id = ${_quote(route.id)};

  /// Creates a typed Intent; navigate through CCRouter.navigator.
  static CCRouteIntent<${route.result}> intent$signature =>
      ${route.intent}(${route.arguments}($assignments));

  /// Component-owned definition; registration does not select a backend.
  static final definition = CCRouteDefinition<${route.arguments}, ${route.result}>(
    routeId: id,
    patterns: ${_emitPatterns(route)},
    codec: const ${route.codec}(),
    visibility: ${_constant(route.annotation.read('visibility').objectValue)},
    visibleTo: ${_constant(route.annotation.read('visibleTo').objectValue)},
    deepLink: ${_constant(route.annotation.read('deepLink').objectValue)},
    presentation: ${_constant(route.annotation.read('presentation').objectValue)},
    placement: ${_constant(route.annotation.read('placement').objectValue)},
    interceptorIds: ${_constant(route.annotation.read('interceptors').objectValue)},
    description: ${_constant(route.annotation.objectValue.getField('description')!)},
  );

  /// Called by the owning component registrar, never by a business caller.
  static void register(CCRegistry registry) => registry.registerRoute(definition);

  /// Injects already decoded arguments into the page without backend coupling.
  static ${route.page.displayName} build(${route.arguments} arguments) =>
      ${route.page.displayName}(${_pageArguments(params)});
}

/// Private data-only Intent carrying this route's typed result contract.
final class ${route.intent} implements CCRouteIntent<${route.result}> {
  /// Captures immutable typed arguments for later Runtime validation.
  const ${route.intent}(this.arguments);
  /// Stable identity of the owned destination.
  @override
  String get routeId => ${route.api}.id;
  /// Typed payload consumed only by the matching route codec.
  @override
  final ${route.arguments} arguments;
}

/// Package-internal bridge used by the generated component route index.
///
/// Keep this symbol out of public package barrels. It exists so a component
/// registrar can register library-private routes without exposing their
/// typed contracts to business code.
void ${route.registrationFunction}(CCRegistry registry) =>
    ${route.api}.register(registry);

/// Private boundary conversion; raw input is never included in error messages.
final class ${route.codec} implements CCRouteCodec<${route.arguments}> {
  /// Stateless codec shared by the component's route definition.
  const ${route.codec}();

  /// Rejects missing, repeated or malformed values before creating a page.
  @override
  ${route.arguments} decode(CCEncodedRouteArguments input) {
''');
  for (final p in params.where(
    (p) =>
        p.source != 'extra' &&
        (p.element.type as InterfaceType).isDartCoreDouble,
  )) {
    out.writeln('''
    double _parse_${p.name}(String raw) {
      final value = double.tryParse(raw);
      if (value == null || !value.isFinite) {
        throw CCRouteParameterError(${_quote('Route "${route.id}" parameter "${p.wireName}" must be finite.')});
      }
      return value;
    }
''');
  }
  for (final p in params) {
    final error = _quote(
      'Route "${route.id}" parameter "${p.wireName}" is invalid.',
    );
    final missing =
        p.defaultCode ??
        (p.nullable ? 'null' : 'throw CCRouteParameterError($error)');
    if (p.source == 'extra') {
      out.writeln(
        'final _value_${p.name} = input.extra == null ? $missing : input.extra;',
      );
      out.writeln(
        'if (_value_${p.name} is! ${p.type}) throw CCRouteParameterError($error);',
      );
      continue;
    }
    if (p.source == 'query') {
      out.writeln(
        'final _values_${p.name} = input.query[${_quote(p.wireName)}];',
      );
      out.writeln(
        'if (_values_${p.name} != null && _values_${p.name}.length != 1) throw CCRouteParameterError($error);',
      );
      out.writeln('final _raw_${p.name} = _values_${p.name}?.single;');
    } else {
      out.writeln('final _raw_${p.name} = input.path[${_quote(p.wireName)}];');
    }
    out.writeln(
      'final ${p.type} _value_${p.name} = _raw_${p.name} == null ? $missing : ${_decodeValue(p, error)};',
    );
  }
  out.writeln(
    'return ${route.arguments}(${params.map((p) => '${p.name}: _value_${p.name}').join(', ')});\n}\n',
  );
  out.writeln('''
  /// Encodes unescaped scalar values; Runtime owns URI escaping exactly once.
  @override
  CCEncodedRouteArguments encode(${route.arguments} arguments) {
''');
  for (final p in params.where(
    (p) =>
        p.element.type is InterfaceType &&
        (p.element.type as InterfaceType).isDartCoreDouble &&
        p.source != 'extra',
  )) {
    out.writeln(
      'if (${p.nullable ? 'arguments.${p.name} != null && !arguments.${p.name}!.isFinite' : '!arguments.${p.name}.isFinite'}) throw CCRouteParameterError(${_quote('Route "${route.id}" parameter "${p.wireName}" must be finite.')});',
    );
  }
  out.writeln('return CCEncodedRouteArguments(path: {');
  for (final p in params.where((p) => p.source == 'path')) {
    out.writeln('${_quote(p.wireName)}: ${_encodeValue(p)},');
  }
  out.writeln('}, query: {');
  for (final p in params.where((p) => p.source == 'query')) {
    out.writeln(
      '${p.nullable ? 'if (arguments.${p.name} != null) ' : ''}${_quote(p.wireName)}: [${_encodeValue(p)}],',
    );
  }
  out.writeln(
    '}, extra: ${params.where((p) => p.source == 'extra').isEmpty ? 'null' : 'arguments.${params.singleWhere((p) => p.source == 'extra').name}'});\n}\n}',
  );
  return out.toString();
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
    .map((p) => '${p.element.isNamed ? '${p.name}: ' : ''}arguments.${p.name}')
    .join(', ');

/// Emits strict scalar parsing with safe, route-specific error information.
String _decodeValue(_ParameterModel p, String error) {
  final type = p.element.type as InterfaceType;
  final raw = '_raw_${p.name}';
  if (type.isDartCoreString) return raw;
  if (type.isDartCoreInt)
    return '(int.tryParse($raw) ?? (throw CCRouteParameterError($error)))';
  if (type.isDartCoreDouble) return '_parse_${p.name}($raw)';
  if (type.isDartCoreBool)
    return 'switch ($raw) { "true" => true, "false" => false, _ => throw CCRouteParameterError($error) }';
  final enumName = _typeSource(
    type,
    p.element.library!,
  ).replaceFirst(RegExp(r'\?$'), '');
  final cases = type.element.fields
      .where((field) => field.isEnumConstant)
      .map(
        (field) =>
            '${_quote(field.displayName)} => $enumName.${field.displayName}',
      )
      .join(', ');
  return 'switch ($raw) { $cases, _ => throw CCRouteParameterError($error) }';
}

/// Emits scalar strings without URL encoding; enum wire values are stable names.
String _encodeValue(_ParameterModel p) {
  final type = p.element.type as InterfaceType;
  final value = 'arguments.${p.name}${p.nullable ? '!' : ''}';
  if (type.isDartCoreString) return value;
  if (type.element is EnumElement) return 'EnumName($value).name';
  return '$value.toString()';
}
