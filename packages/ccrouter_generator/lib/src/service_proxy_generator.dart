part of 'service_generator.dart';

/// Emits one typed method-level Proxy API for each consuming component.
final class _ServiceProxyGenerator extends Generator {
  /// Generates nothing when the library declares no consumed Services.
  @override
  String generate(LibraryReader library, BuildStep buildStep) {
    if (buildStep.inputId.path.contains('/ccrouter_generated/')) return '';
    final components = <_ServiceConsumerComponentModel>[];
    for (final element
        in library.allElements.whereType<TopLevelVariableElement>()) {
      if (!_serviceComponentChecker.isExactlyType(element.type)) continue;
      final value = element.computeConstantValue();
      if (!element.isConst || value == null) {
        _failService(
          'CCComponent declarations must be top-level const values.',
          element,
        );
      }
      final component = _readServiceConsumerComponent(value, element);
      if (component.dependencies.isNotEmpty) components.add(component);
    }
    if (components.isEmpty) return '';
    if (components.length > 1) {
      _failService(
        'A source library may declare only one CCComponent with Service '
        'dependencies.',
        components.last.element,
      );
    }
    return _emitServiceProxyLibrary(library.element, components.single);
  }
}

/// One consuming component and its explicit cross-component dependencies.
final class _ServiceConsumerComponentModel {
  /// Stores the source declaration and normalized generated inputs.
  const _ServiceConsumerComponentModel({
    required this.element,
    required this.id,
    required this.dependencies,
  });

  /// Top-level component constant that owns the generated Client.
  final TopLevelVariableElement element;

  /// Stable caller component identity embedded in every Proxy invocation.
  final String id;

  /// Explicit Service dependencies ordered by generated member name.
  final List<_ServiceDependencyModel> dependencies;
}

/// One validated component-to-Service dependency declaration.
final class _ServiceDependencyModel {
  /// Stores the resolved contract, implementation Key, and generated member.
  const _ServiceDependencyModel({
    required this.contract,
    required this.key,
    required this.member,
  });

  /// Public contract whose methods are implemented by the generated Proxy.
  final _ServiceContractModel contract;

  /// Stable Provider Key, or null for default resolution.
  final String? key;

  /// Public lower-camel member exposed by the generated component Client.
  final String member;
}

/// Reads one component constant and its explicitly declared Service consumers.
_ServiceConsumerComponentModel _readServiceConsumerComponent(
  DartObject value,
  TopLevelVariableElement element,
) {
  final id = _serviceObjectField(
    _serviceObjectField(value, 'id'),
    'value',
  ).toStringValue();
  if (id == null) {
    _failService('CCComponent requires a const CCComponentId.', element);
  }
  _validateServiceId(id, 'Component ID', element);
  final requiredOwners = <String>{
    for (final dependency
        in _serviceObjectField(value, 'dependencies').toListValue() ?? const [])
      if (_serviceObjectField(dependency, 'value').toStringValue()
          case final owner?)
        owner,
  };
  final dependencies = <_ServiceDependencyModel>[];
  final members = <String>{};
  final identities = <String>{};
  final rawDependencies =
      _serviceObjectField(value, 'serviceDependencies').toListValue() ??
      const <DartObject>[];
  for (final dependency in rawDependencies) {
    final dependencyType = dependency.type;
    if (dependencyType is! InterfaceType ||
        !_serviceDependencyChecker.isExactlyType(dependencyType) ||
        dependencyType.typeArguments.length != 1) {
      _failService(
        'CCComponent.serviceDependencies accepts const '
        'CCServiceDependency<T> values only.',
        element,
      );
    }
    final contractType = dependencyType.typeArguments.single;
    if (contractType is! InterfaceType ||
        contractType.element is! ClassElement) {
      _failService(
        'CCServiceDependency<T> requires a public Service contract interface.',
        element,
      );
    }
    final contract = _serviceContractAnnotation(contractType.element);
    if (contract == null) {
      _failService(
        'CCServiceDependency<${contractType.getDisplayString()}> requires T '
        'to be annotated with CCServiceContract.',
        element,
      );
    }
    if (contract.componentId == id) {
      _failService(
        'Component "$id" must not declare its own Service contract '
        '"${contract.id}" as a cross-component dependency; use direct '
        'Service lookup internally.',
        element,
      );
    }
    if (!requiredOwners.contains(contract.componentId)) {
      _failService(
        'Component "$id" consumes Service "${contract.id}" owned by '
        '"${contract.componentId}". Add that owner to CCComponent.dependencies; '
        'optionalDependencies cannot satisfy a required Service call.',
        element,
      );
    }
    final keyValue = _serviceObjectField(dependency, 'key');
    final key = keyValue.isNull
        ? null
        : _serviceObjectField(keyValue, 'name').toStringValue();
    if (key != null) _validateServiceId(key, 'Service Key', element);
    final aliasValue = _serviceObjectField(dependency, 'alias');
    final alias = aliasValue.isNull ? null : aliasValue.toStringValue();
    final member =
        alias ??
        contract.alias ??
        defaultServiceClientMember(contract.element.displayName);
    if (!isGeneratedClientMemberName(member)) {
      _failService(
        'Service dependency alias "$member" must be a public lower-camel Dart '
        'identifier and must not be a keyword.',
        element,
      );
    }
    if (!members.add(member)) {
      _failService(
        'Component "$id" generates duplicate Service Client member "$member". '
        'Set a distinct CCServiceDependency alias.',
        element,
      );
    }
    final identity = '${contract.id}\u0000${key ?? ''}';
    if (!identities.add(identity)) {
      _failService(
        'Component "$id" declares Service "${contract.id}" with Key '
        '"${key ?? '<default>'}" more than once.',
        element,
      );
    }
    dependencies.add(
      _ServiceDependencyModel(contract: contract, key: key, member: member),
    );
  }
  dependencies.sort((left, right) => left.member.compareTo(right.member));
  return _ServiceConsumerComponentModel(
    element: element,
    id: id,
    dependencies: List.unmodifiable(dependencies),
  );
}

/// Emits one standalone component Service Client and its private Proxies.
String _emitServiceProxyLibrary(
  LibraryElement sourceLibrary,
  _ServiceConsumerComponentModel component,
) {
  final imports = _ServiceProxyImportPlan(sourceLibrary, component);
  final clientName =
      '${_servicePascal(_serviceComponentApiOwner(component.id))}Services';
  final out = StringBuffer()
    ..writeln(
      "import 'package:ccrouter/ccrouter_generated.dart' as ${imports.frameworkPrefix};",
    );
  for (final entry in imports.imports.entries) {
    out.writeln("import '${entry.key}' as ${entry.value};");
  }
  out
    ..writeln()
    ..writeln(
      '/// Generated typed Service entry points for component `${component.id}`.',
    )
    ..writeln('abstract final class $clientName {');
  for (final dependency in component.dependencies) {
    final contractType = imports.typeSource(
      dependency.contract.element.thisType,
      dependency.contract.element,
    );
    final proxyName = '_${_servicePascal(dependency.member)}ServiceProxy';
    out
      ..writeln('  /// Calls `${dependency.contract.id}` as `${component.id}`.')
      ..writeln(
        '  static const $contractType ${dependency.member} = $proxyName();',
      );
  }
  out
    ..writeln('}')
    ..writeln();
  for (final dependency in component.dependencies) {
    final contract = dependency.contract;
    final contractType = imports.typeSource(
      contract.element.thisType,
      contract.element,
    );
    final proxyName = '_${_servicePascal(dependency.member)}ServiceProxy';
    out
      ..writeln('/// Stateless generated Proxy for `${contract.id}`.')
      ..writeln('final class $proxyName implements $contractType {')
      ..writeln(
        '  /// Creates the generated caller without resolving a Service.',
      )
      ..writeln('  const $proxyName();')
      ..writeln();
    for (final member in contract.members) {
      _emitServiceProxyMember(
        out,
        imports: imports,
        component: component,
        dependency: dependency,
        contractType: contractType,
        member: member,
      );
    }
    out
      ..writeln('}')
      ..writeln();
  }
  return out.toString();
}

/// Emits one overriding method or getter through the generated Runtime bridge.
void _emitServiceProxyMember(
  StringBuffer out, {
  required _ServiceProxyImportPlan imports,
  required _ServiceConsumerComponentModel component,
  required _ServiceDependencyModel dependency,
  required String contractType,
  required _ServiceMemberModel member,
}) {
  final returnType = imports.typeSource(member.returnType, member.element);
  final resultType = imports.typeSource(member.resultType, member.element);
  final typeParameters = _serviceTypeParameterSignature(
    member.typeParameters,
    imports,
  );
  final forwardedTypeArguments = _serviceForwardedTypeArguments(
    member.typeParameters,
  );
  final parameters = _serviceParameterSignature(member.parameters, imports);
  final invocation = member.isAsync ? 'invoke' : 'invokeSync';
  final reserved = {
    for (final parameter in member.parameters) parameter.displayName,
    for (final parameter in member.typeParameters) parameter.displayName,
  };
  final receiver = _serviceUnusedName('service', reserved);
  final key = dependency.key == null
      ? ''
      : '      key: const ${imports.frameworkPrefix}.CCServiceKey<$contractType>(${jsonEncode(dependency.key)}),\n';
  final call = member.kind == 'getter'
      ? '$receiver.${member.element.displayName}'
      : '$receiver.${member.element.displayName}$forwardedTypeArguments(${_serviceForwardedArguments(member.parameters)})';
  out
    ..writeln('  /// Invokes `${dependency.contract.id}.${member.methodId}`.')
    ..writeln('  @override');
  if (member.kind == 'getter') {
    out.writeln('  $returnType get ${member.element.displayName} =>');
  } else {
    out.writeln(
      '  $returnType ${member.element.displayName}$typeParameters($parameters) =>',
    );
  }
  out
    ..writeln(
      '      ${imports.frameworkPrefix}.CCRouterGeneratedServiceBinding.$invocation<$contractType, $resultType>(',
    )
    ..write(key)
    ..writeln('        methodId: ${jsonEncode(member.methodId)},')
    ..writeln('        callerComponentId: ${jsonEncode(component.id)},')
    ..writeln('        call: ($receiver, _) => $call,')
    ..writeln('      );')
    ..writeln();
}

/// Plans public imports and stable type prefixes for one generated Client.
final class _ServiceProxyImportPlan {
  /// Collects every contract and signature type required by [component].
  _ServiceProxyImportPlan(
    this._sourceLibrary,
    _ServiceConsumerComponentModel component,
  ) {
    final uris = <Uri>{};
    final reservedPrefixes = <String>{};
    for (final dependency in component.dependencies) {
      _collectType(
        dependency.contract.element.thisType,
        dependency.contract.element,
        uris,
      );
      for (final member in dependency.contract.members) {
        reservedPrefixes.add(member.element.displayName);
        for (final typeParameter in member.typeParameters) {
          reservedPrefixes.add(typeParameter.displayName);
          final bound = typeParameter.bound;
          if (bound != null) _collectType(bound, typeParameter, uris);
        }
        _collectType(member.returnType, member.element, uris);
        for (final parameter in member.parameters) {
          reservedPrefixes.add(parameter.displayName);
          _collectType(parameter.type, parameter, uris);
        }
      }
    }
    final sorted = uris.toList()
      ..sort((left, right) => left.toString().compareTo(right.toString()));
    frameworkPrefix = _serviceUnusedName(
      'ccrouter_service_runtime',
      reservedPrefixes,
    );
    reservedPrefixes.add(frameworkPrefix);
    var prefixIndex = 0;
    _aliases = {};
    for (final uri in sorted) {
      var prefix = 'service_type_$prefixIndex';
      while (reservedPrefixes.contains(prefix)) {
        prefix = 'service_type_${++prefixIndex}';
      }
      _aliases[uri.toString()] = prefix;
      prefixIndex++;
    }
  }

  /// Component library containing the top-level dependency declaration.
  final LibraryElement _sourceLibrary;

  /// Resolved declaration elements mapped to public source imports.
  final Map<Element, Uri> _elementImports = {};

  /// Import URI to deterministic generated prefix.
  late final Map<String, String> _aliases;

  /// Qualified SPI namespace that no generated method can shadow.
  late final String frameworkPrefix;

  /// Imports required by the generated standalone Proxy library.
  Map<String, String> get imports => Map.unmodifiable(_aliases);

  /// Renders one validated method type in the generated namespace.
  String typeSource(DartType type, Element owner) {
    if (type is TypeParameterType) {
      return '${type.element.displayName}${_serviceNullability(type)}';
    }
    final alias = type.alias;
    if (alias != null) {
      final element = alias.element;
      final importUri = _elementImports[element]!;
      final prefix = _serviceTypePrefix(element, importUri);
      final arguments = alias.typeArguments;
      return '$prefix${element.displayName}'
          '${arguments.isEmpty ? '' : '<${arguments.map((argument) => typeSource(argument, owner)).join(', ')}>'}'
          '${_serviceNullability(type)}';
    }
    if (type is VoidType) return 'void';
    if (type is NeverType) return 'Never${_serviceNullability(type)}';
    if (type is RecordType) {
      final positional = [
        for (final field in type.positionalFields)
          typeSource(field.type, owner),
      ];
      final named = [
        for (final field in type.namedFields)
          '${typeSource(field.type, owner)} ${field.name}',
      ];
      final fields = [
        ...positional,
        if (named.isNotEmpty) '{${named.join(', ')}}',
      ];
      final trailing = positional.length == 1 && named.isEmpty ? ',' : '';
      return '(${fields.join(', ')}$trailing)${_serviceNullability(type)}';
    }
    if (type is! InterfaceType) {
      _failService('Unsupported generated Service Proxy type.', owner);
    }
    final element = type.element;
    final uri = element.library.uri;
    final prefix = uri.toString() == 'dart:core'
        ? ''
        : _serviceTypePrefix(element, _elementImports[element]!);
    final arguments = type.typeArguments;
    return '$prefix${element.displayName}'
        '${arguments.isEmpty ? '' : '<${arguments.map((argument) => typeSource(argument, owner)).join(', ')}>'}'
        '${_serviceNullability(type)}';
  }

  /// Adds all public declarations needed to render [type].
  void _collectType(DartType type, Element owner, Set<Uri> imports) {
    if (type is TypeParameterType) return;
    final alias = type.alias;
    if (alias != null) {
      final definitionUri = alias.element.library.uri;
      final importUri = definitionUri.scheme == 'dart'
          ? definitionUri
          : _publicImportUri(alias.element, owner);
      _elementImports[alias.element] = importUri;
      if (!_serviceFrameworkOrCoreUri(importUri)) imports.add(importUri);
      for (final argument in alias.typeArguments) {
        _collectType(argument, owner, imports);
      }
      return;
    }
    if (type is VoidType || type is NeverType) return;
    if (type is RecordType) {
      for (final field in [...type.positionalFields, ...type.namedFields]) {
        _collectType(field.type, owner, imports);
      }
      return;
    }
    if (type is! InterfaceType) {
      _failService('Unsupported generated Service Proxy type.', owner);
    }
    final element = type.element;
    final definitionUri = element.library.uri;
    if (definitionUri.toString() != 'dart:core') {
      final importUri =
          definitionUri.scheme == 'dart' ||
              _serviceFrameworkOrCoreUri(definitionUri)
          ? definitionUri
          : _publicImportUri(element, owner);
      _elementImports[element] = importUri;
      if (!_serviceFrameworkOrCoreUri(importUri)) imports.add(importUri);
    }
    for (final argument in type.typeArguments) {
      _collectType(argument, owner, imports);
    }
  }

  /// Finds a public component-source import that exposes [element].
  Uri _publicImportUri(Element element, Element owner) {
    final name = element.displayName;
    final candidates = <Uri>{};
    for (final fragment in _sourceLibrary.fragments) {
      for (final directive in fragment.libraryImports) {
        final prefix = directive.prefix?.element.displayName;
        final visible =
            directive.namespace.get2(name) == element ||
            (prefix != null &&
                directive.namespace.getPrefixed2(prefix, name) == element);
        if (!visible) continue;
        final imported = directive.importedLibrary;
        if (imported != null) candidates.add(imported.uri);
      }
    }
    final ordered = candidates.toList()
      ..sort((left, right) => left.toString().compareTo(right.toString()));
    for (final candidate in ordered) {
      if (_servicePublicImport(candidate)) return candidate;
    }
    _failService(
      'Service Proxy type "$name" must be available through an explicit '
      'public package import in the CCComponent source library. Export the '
      'contract and its DTOs from the contracts Package barrel.',
      owner,
    );
  }

  /// Returns the generated prefix for one imported declaration.
  String _serviceTypePrefix(Element element, Uri importUri) {
    if (importUri.toString() == 'dart:core') return '';
    if (_serviceFrameworkOrCoreUri(importUri)) return '$frameworkPrefix.';
    return '${_aliases[importUri.toString()]!}.';
  }
}

/// Allocates a deterministic generated name outside the authored scope.
String _serviceUnusedName(String preferred, Set<String> reserved) {
  var candidate = preferred;
  for (var suffix = 1; reserved.contains(candidate); suffix++) {
    candidate = '$preferred$suffix';
  }
  return candidate;
}

/// Renders method-owned generic parameters and their public Pure Dart bounds.
String _serviceTypeParameterSignature(
  List<TypeParameterElement> parameters,
  _ServiceProxyImportPlan imports,
) {
  if (parameters.isEmpty) return '';
  final declarations = <String>[];
  for (final parameter in parameters) {
    final bound = parameter.bound;
    declarations.add(
      bound == null
          ? parameter.displayName
          : '${parameter.displayName} extends ${imports.typeSource(bound, parameter)}',
    );
  }
  return '<${declarations.join(', ')}>';
}

/// Renders explicit generic arguments so zero-argument methods retain types.
String _serviceForwardedTypeArguments(List<TypeParameterElement> parameters) =>
    parameters.isEmpty
    ? ''
    : '<${parameters.map((parameter) => parameter.displayName).join(', ')}>';

/// Renders a complete overriding method parameter list.
String _serviceParameterSignature(
  List<FormalParameterElement> parameters,
  _ServiceProxyImportPlan imports,
) {
  final requiredPositional = <String>[];
  final optionalPositional = <String>[];
  final named = <String>[];
  for (final parameter in parameters) {
    final type = imports.typeSource(parameter.type, parameter);
    final defaultValue = parameter.hasDefaultValue
        ? ' = ${_serviceDefaultValue(parameter, imports)}'
        : '';
    final declaration = '$type ${parameter.displayName}$defaultValue';
    if (parameter.isRequiredPositional) {
      requiredPositional.add(declaration);
    } else if (parameter.isOptionalPositional) {
      optionalPositional.add(declaration);
    } else {
      named.add('${parameter.isRequiredNamed ? 'required ' : ''}$declaration');
    }
  }
  return [
    ...requiredPositional,
    if (optionalPositional.isNotEmpty) '[${optionalPositional.join(', ')}]',
    if (named.isNotEmpty) '{${named.join(', ')}}',
  ].join(', ');
}

/// Renders deterministic forwarded arguments without dynamic containers.
String _serviceForwardedArguments(List<FormalParameterElement> parameters) => [
  for (final parameter in parameters)
    parameter.isNamed
        ? '${parameter.displayName}: ${parameter.displayName}'
        : parameter.displayName,
].join(', ');

/// Renders supported primitive, enum, and collection defaults.
String _serviceDefaultValue(
  FormalParameterElement parameter,
  _ServiceProxyImportPlan imports,
) {
  final value = parameter.computeConstantValue();
  if (value == null) {
    _failService(
      'Service Proxy default for "${parameter.displayName}" must be a '
      'compile-time constant.',
      parameter,
    );
  }
  return _renderServiceConstant(value, parameter, imports);
}

/// Serializes one supported default constant into generated Dart source.
String _renderServiceConstant(
  DartObject value,
  Element owner,
  _ServiceProxyImportPlan imports,
) {
  if (value.isNull) return 'null';
  if (value.toStringValue() case final String text) {
    // JSON handles quotes, control characters, and backslashes, but Dart also
    // treats dollar signs as interpolation in a non-raw string literal.
    return jsonEncode(text).replaceAll(r'$', r'\$');
  }
  if (value.toBoolValue() case final bool flag) return '$flag';
  if (value.toIntValue() case final int number) return '$number';
  if (value.toDoubleValue() case final double number) {
    if (number.isNaN) return 'double.nan';
    if (number == double.infinity) return 'double.infinity';
    if (number == double.negativeInfinity) return 'double.negativeInfinity';
    return '$number';
  }
  final type = value.type;
  if (type is InterfaceType && type.element is EnumElement) {
    final enumElement = type.element as EnumElement;
    final index = _serviceObjectField(value, 'index').toIntValue()!;
    final field = enumElement.fields
        .where((candidate) => candidate.isEnumConstant)
        .elementAt(index);
    return '${imports.typeSource(type, owner)}.${field.displayName}';
  }
  if (value.toListValue() case final values?) {
    return 'const [${values.map((item) => _renderServiceConstant(item, owner, imports)).join(', ')}]';
  }
  if (value.toSetValue() case final values?) {
    return 'const {${values.map((item) => _renderServiceConstant(item, owner, imports)).join(', ')}}';
  }
  if (value.toMapValue() case final values?) {
    return 'const {${values.entries.map((entry) => '${_renderServiceConstant(entry.key!, owner, imports)}: ${_renderServiceConstant(entry.value!, owner, imports)}').join(', ')}}';
  }
  _failService(
    'Service Proxy default constants support null, primitives, enums, Lists, '
    'Sets, and Maps only.',
    owner,
  );
}

/// Reads inherited const fields from analyzer values.
DartObject _serviceObjectField(DartObject value, String name) {
  final direct = value.getField(name);
  if (direct != null) return direct;
  final parent = value.getField('(super)');
  if (parent != null) return _serviceObjectField(parent, name);
  throw StateError('Missing Service metadata field: $name');
}

/// Removes the conventional component suffix from generated API class names.
String _serviceComponentApiOwner(String componentId) =>
    componentId.endsWith('_component')
    ? componentId.substring(0, componentId.length - '_component'.length)
    : componentId;

/// Converts component/member identities into a deterministic Pascal name.
String _servicePascal(String value) => value
    .split(RegExp(r'[^A-Za-z0-9]+'))
    .where((part) => part.isNotEmpty)
    .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
    .join();

/// Whether a URI is covered by Dart core or the shared framework SPI import.
bool _serviceFrameworkOrCoreUri(Uri uri) =>
    uri.toString() == 'dart:core' ||
    uri.toString().startsWith('package:ccrouter_contracts/') ||
    uri.toString().startsWith('package:ccrouter/');

/// Whether a generated Proxy may import this authored public library.
bool _servicePublicImport(Uri uri) {
  if (uri.scheme != 'dart' && uri.scheme != 'package') return false;
  if (uri.toString() == 'dart:ui' ||
      uri.toString().startsWith('package:flutter/') ||
      uri.toString().startsWith('package:go_router/')) {
    return false;
  }
  return uri.scheme != 'package' ||
      uri.pathSegments.length < 2 ||
      uri.pathSegments[1] != 'src';
}

/// Converts analyzer nullability into generated source syntax.
String _serviceNullability(DartType type) =>
    type.nullabilitySuffix == NullabilitySuffix.question ? '?' : '';
