import 'dart:convert';

import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

import 'contract_fingerprint.dart';

part 'service_proxy_generator.dart';

/// Maximum length accepted for generated Service identities and Keys.
const int _serviceMaxStableIdLength = 128;

/// Maximum description length retained in generated Service metadata.
const int _serviceMaxDescriptionLength = 4096;

/// Stable identifier syntax shared by generated Service contracts and Keys.
final RegExp _serviceStableIdPattern = RegExp(
  r'^[a-z][A-Za-z0-9]*(?:[._-][A-Za-z0-9]+)*$',
);

/// SemVer 2.0 syntax used by independent Service Contracts.
final RegExp _serviceSemanticVersionPattern = RegExp(
  r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)'
  r'(?:-(?:0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*)'
  r'(?:\.(?:0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*))*)?'
  r'(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$',
);

/// Matches Service contract declarations from the canonical contracts package.
const TypeChecker _serviceContractChecker = TypeChecker.typeNamedLiterally(
  'CCServiceContract',
  inPackage: 'ccrouter_contracts',
);

/// Matches Service implementation declarations from the canonical package.
const TypeChecker _serviceChecker = TypeChecker.typeNamedLiterally(
  'CCService',
  inPackage: 'ccrouter_contracts',
);

/// Matches typed cross-component Service dependency declarations.
const TypeChecker _serviceDependencyChecker = TypeChecker.typeNamedLiterally(
  'CCServiceDependency',
  inPackage: 'ccrouter_contracts',
);

/// Matches one implementation Package's canonical component definition.
const TypeChecker _serviceComponentChecker = TypeChecker.typeNamedLiterally(
  'CCComponent',
  inPackage: 'ccrouter_contracts',
);

/// Creates typed Tokens reserved for generated and owner-only Service SPI.
Generator ccServiceContractGenerator() => _ServiceContractGenerator();

/// Creates generated Provider registration bridges for simple Services.
Generator ccServiceGenerator() => _ServiceGenerator();

/// Creates component-specific typed Clients for declared Service dependencies.
Generator ccServiceProxyGenerator() => _ServiceProxyGenerator();

/// Creates cache-only Service metadata for workspace aggregation.
Builder ccServiceMetadataBuilderInternal() => _ServiceMetadataBuilder();

/// Emits one typed Token for every validated Service contract declaration.
final class _ServiceContractGenerator extends Generator {
  /// Generates nothing for libraries without `CCServiceContract` declarations.
  @override
  String generate(LibraryReader library, BuildStep buildStep) {
    if (buildStep.inputId.path.contains('/ccrouter_generated/')) return '';
    final contracts = _readServiceContracts(library);
    if (contracts.isEmpty) return '';
    final sourceUri = _servicePackageUri(
      buildStep.inputId.package,
      buildStep.inputId.path,
    );
    final out = StringBuffer()
      ..writeln("import 'package:ccrouter_contracts/ccrouter_contracts.dart';")
      ..writeln("import '$sourceUri' as service_contract;")
      ..writeln();
    for (final contract in contracts) {
      out
        ..writeln(
          '/// Owner-only generated token for Service `${contract.id}`.',
        )
        ..writeln(
          'const ${contract.tokenSymbol} = '
          'CCServiceToken<service_contract.${contract.element.displayName}>('
          '${jsonEncode(contract.id)});',
        )
        ..writeln();
    }
    return out.toString();
  }
}

/// Emits one package-internal registration function per simple Service class.
final class _ServiceGenerator extends Generator {
  /// Generates nothing for libraries without `CCService` declarations.
  @override
  String generate(LibraryReader library, BuildStep buildStep) {
    if (buildStep.inputId.path.contains('/ccrouter_generated/')) return '';
    final services = _readServices(library);
    if (services.isEmpty) return '';
    final sourceUri = _servicePackageUri(
      buildStep.inputId.package,
      buildStep.inputId.path,
    );
    final importedTypes = <String, String>{};
    for (final service in services) {
      final typeUri = service.lookupType.element.library.uri.toString();
      if (typeUri != sourceUri) {
        importedTypes.putIfAbsent(
          typeUri,
          () => 'service_type_${importedTypes.length}',
        );
      }
    }
    final out = StringBuffer()
      ..writeln("import 'package:ccrouter/ccrouter_generated.dart';")
      ..writeln("import '$sourceUri' as service_source;");
    for (final entry in importedTypes.entries) {
      out.writeln("import '${entry.key}' as ${entry.value};");
    }
    out.writeln();
    for (final service in services) {
      final lookupType = _serviceTypeReference(
        service.lookupType,
        sourceUri: sourceUri,
        importedTypes: importedTypes,
      );
      final implementation = 'service_source.${service.element.displayName}';
      out
        ..writeln(
          '/// Registers generated Service `${service.id}` for its component.',
        )
        ..writeln('void ${service.registrationFunction}(CCRegistry registry) {')
        ..writeln('  registry.registerService<$lookupType>(')
        ..writeln('    CCServiceProvider<$lookupType>(')
        ..writeln(
          '      factory: (_) => ${service.constructor.isConst ? 'const ' : ''}$implementation(),',
        );
      if (service.contractId case final contractId?) {
        out.writeln(
          '      contractToken: const CCServiceToken<$lookupType>('
          '${jsonEncode(contractId)}),',
        );
      }
      if (service.key case final key?) {
        out.writeln(
          '      key: const CCServiceKey<$lookupType>(${jsonEncode(key)}),',
        );
      }
      out
        ..writeln('      scope: CCServiceScope.${service.scope},')
        ..writeln(
          '      creationPolicy: '
          'CCServiceCreationPolicy.${service.creationPolicy},',
        )
        ..writeln('      isDefault: ${service.isDefault},')
        ..writeln('    ),')
        ..writeln('  );')
        ..writeln('}')
        ..writeln();
    }
    return out.toString();
  }
}

/// Emits Service contract and implementation metadata for Package aggregation.
final class _ServiceMetadataBuilder implements Builder {
  /// Creates the Builder with source-path-preserving cache outputs.
  _ServiceMetadataBuilder()
    : buildExtensions = const {
        r'^lib/{{}}.dart': [
          'lib/src/ccrouter_generated/metadata/{{}}.service.json',
        ],
      };

  /// Maps every source library to its optional Service metadata output.
  @override
  final Map<String, List<String>> buildExtensions;

  /// Writes no output when the source declares no Service capability.
  @override
  Future<void> build(BuildStep buildStep) async {
    if (buildStep.inputId.path.contains('/ccrouter_generated/')) return;
    if (!await buildStep.resolver.isLibrary(buildStep.inputId)) return;
    final library = LibraryReader(
      await buildStep.resolver.libraryFor(buildStep.inputId),
    );
    final contracts = _readServiceContracts(library);
    final services = _readServices(library);
    if (contracts.isEmpty && services.isEmpty) return;
    final package = buildStep.inputId.package;
    final source = buildStep.inputId.path;
    final contractLibrary = _serviceGeneratedLibraryPath(
      source,
      directory: 'contract',
      suffix: '.service.contract.g.dart',
    );
    final serviceLibrary = _serviceGeneratedLibraryPath(
      source,
      directory: 'service',
      suffix: '.service.g.dart',
    );
    final payload = <String, Object?>{
      'schemaVersion': 4,
      'package': package,
      'source': source,
      'componentDeclarations': <String>[],
      'componentManifests': <String, String>{},
      'componentSymbols': <String, String>{},
      'components': <Object>[],
      'routes': <Object>[],
      'routeImplementations': <Object>[],
      'contributions': <Object>[],
      'serviceContracts': [
        for (final contract in contracts)
          <String, Object?>{
            'id': contract.id,
            'componentId': contract.componentId,
            'version': contract.version,
            'description': contract.description,
            'package': package,
            'source': source,
            'declaration': _serviceSourceReference(contract.element),
            'methods': [
              for (final member in contract.members)
                <String, Object?>{
                  'memberKind': member.kind,
                  'methodId': member.methodId,
                  'returnKind': member.isAsync ? 'future' : 'sync',
                  'returnType': member.returnType.getDisplayString(),
                  'resultType': member.resultType.getDisplayString(),
                  'typeParameters': [
                    for (final parameter in member.typeParameters)
                      _serviceTypeParameterMetadata(parameter),
                  ],
                  'parameters': [
                    for (final parameter in member.parameters)
                      <String, Object?>{
                        'name': parameter.displayName,
                        'type': parameter.type.getDisplayString(),
                        'kind': parameter.isRequiredPositional
                            ? 'requiredPositional'
                            : parameter.isOptionalPositional
                            ? 'optionalPositional'
                            : parameter.isRequiredNamed
                            ? 'requiredNamed'
                            : 'optionalNamed',
                        'default': parameter.defaultValueCode,
                      },
                  ],
                  'capabilities': <String>[
                    'typedArguments',
                    'callerIdentity',
                    'methodTrace',
                    if (member.isAsync) 'scopeCancellation',
                  ],
                  'unsupportedReason': null,
                  'declaration': _serviceSourceReference(member.element),
                },
            ],
            'shapeFingerprint': contractShapeFingerprint(<String, Object?>{
              'kind': 'service',
              'id': contract.id,
              'owner': contract.componentId,
              'methods': [
                for (final member in contract.members)
                  <String, Object?>{
                    'memberKind': member.kind,
                    'methodId': member.methodId,
                    'returnType': member.returnType.getDisplayString(),
                    'resultType': member.resultType.getDisplayString(),
                    'typeParameters': [
                      for (final parameter in member.typeParameters)
                        _serviceTypeParameterMetadata(parameter),
                    ],
                    'parameters': [
                      for (final parameter in member.parameters)
                        <String, Object?>{
                          'name': parameter.displayName,
                          'type': parameter.type.getDisplayString(),
                          'kind': parameter.isRequiredPositional
                              ? 'requiredPositional'
                              : parameter.isOptionalPositional
                              ? 'optionalPositional'
                              : parameter.isRequiredNamed
                              ? 'requiredNamed'
                              : 'optionalNamed',
                          'default': parameter.defaultValueCode,
                        },
                    ],
                  },
              ],
            }),
            'token': <String, Object?>{
              'symbol': contract.tokenSymbol,
              'library': contractLibrary,
              'packageUri': _servicePackageUri(package, contractLibrary),
            },
          },
      ],
      'serviceImplementations': [
        for (final service in services)
          <String, Object?>{
            'id': service.id,
            'componentId': null,
            'contractId': service.contractId,
            'key': service.key,
            'scope': service.scope,
            'creationPolicy': service.creationPolicy,
            'isDefault': service.isDefault,
            'package': package,
            'source': source,
            'implementation': _serviceSourceReference(service.element),
            'contract': service.contractElement == null
                ? null
                : _serviceSourceReference(service.contractElement!),
            'registration': service.registrationFunction,
            'registrationLibrary': serviceLibrary,
            'generatedArtifacts': [
              <String, Object?>{
                'role': 'serviceRegistration',
                'symbol': service.registrationFunction,
                'packageUri': _servicePackageUri(package, serviceLibrary),
              },
            ],
          },
      ],
    };
    final output = buildStep.allowedOutputs.singleWhere(
      (candidate) => candidate.path.endsWith('.service.json'),
    );
    await buildStep.writeAsString(
      output,
      '${const JsonEncoder.withIndent('  ').convert(payload)}\n',
    );
  }
}

/// Validated declaration of one generated Service contract Token.
final class _ServiceContractModel {
  /// Stores the contract declaration and stable generated identity.
  const _ServiceContractModel({
    required this.element,
    required this.componentId,
    required this.id,
    required this.version,
    required this.description,
    required this.members,
  });

  /// Public abstract interface carrying the business method signatures.
  final ClassElement element;

  /// Explicit owner retained even when the contracts Package has many owners.
  final String componentId;

  /// Stable Runtime identity serialized into the generated Token.
  final String id;

  /// Independent Service Contract SemVer.
  final String version;

  /// Authored usage scenario retained in generated catalogs.
  final String description;

  /// Validated instance methods and getters implemented by generated Proxies.
  final List<_ServiceMemberModel> members;

  /// Predictable Token symbol optionally exported by an owner-only SPI barrel.
  String get tokenSymbol => '${_serviceLowerCamel(element.displayName)}Token';
}

/// One supported method or getter in a generated Service contract.
final class _ServiceMemberModel {
  /// Stores the executable signature after generation-boundary validation.
  const _ServiceMemberModel({
    required this.element,
    required this.kind,
    required this.returnType,
    required this.resultType,
    required this.isAsync,
    required this.typeParameters,
    required this.parameters,
  });

  /// Authored method or getter declaration.
  final ExecutableElement element;

  /// Stable metadata kind: `method` or `getter`.
  final String kind;

  /// Exact return type retained in the overriding Proxy member.
  final DartType returnType;

  /// Synchronous result type, or the value inside `Future<T>`.
  final DartType resultType;

  /// Whether Runtime must use its asynchronous invocation boundary.
  final bool isAsync;

  /// Method-owned generic parameters reproduced by the generated Proxy.
  final List<TypeParameterElement> typeParameters;

  /// Parameters forwarded without serialization or dynamic maps.
  final List<FormalParameterElement> parameters;

  /// Stable method-level diagnostic identity.
  String get methodId => element.displayName;
}

/// Validated declaration of one generated simple Service Provider.
final class _ServiceModel {
  /// Stores all values needed by registration and metadata generation.
  const _ServiceModel({
    required this.element,
    required this.constructor,
    required this.lookupType,
    required this.contractElement,
    required this.id,
    required this.contractId,
    required this.key,
    required this.scope,
    required this.creationPolicy,
    required this.isDefault,
  });

  /// Concrete implementation instantiated lazily by the generated Provider.
  final ClassElement element;

  /// Validated unnamed zero-argument generative constructor.
  final ConstructorElement constructor;

  /// Runtime registration and lookup type.
  final InterfaceType lookupType;

  /// Public contract interface when this is a promoted Service.
  final ClassElement? contractElement;

  /// Stable Service identity used by metadata and diagnostics.
  final String id;

  /// Promoted Token identity, or null for a type-local Service.
  final String? contractId;

  /// Named implementation key, when configured.
  final String? key;

  /// Name of the owning Runtime Scope enum value.
  final String scope;

  /// Name of the Provider creation-policy enum value.
  final String creationPolicy;

  /// Whether unkeyed resolution selects this keyed implementation.
  final bool isDefault;

  /// Stable package-internal registration bridge name.
  String get registrationFunction =>
      'ccrouterRegister${element.displayName}Service';
}

/// Reads and validates every public Service contract in one source library.
List<_ServiceContractModel> _readServiceContracts(LibraryReader library) {
  final contracts = <_ServiceContractModel>[];
  final ids = <String>{};
  final tokenSymbols = <String>{};
  for (final annotated in library.annotatedWith(_serviceContractChecker)) {
    final element = annotated.element;
    if (element is! ClassElement ||
        !element.isAbstract ||
        element.typeParameters.isNotEmpty ||
        element.displayName.startsWith('_')) {
      _failService(
        'CCServiceContract requires a public, abstract, non-generic interface.',
        element,
      );
    }
    _validateServiceContractInheritance(element);
    final component = annotated.annotation.read('componentId').objectValue;
    final componentId = component.getField('value')?.toStringValue();
    if (componentId == null) {
      _failService(
        'CCServiceContract requires a const CCComponentId.',
        element,
      );
    }
    _validateServiceId(componentId, 'Component ID', element);
    final id = annotated.annotation.read('id').stringValue;
    final version = annotated.annotation.read('version').stringValue;
    _validateServiceId(id, 'Service contract ID', element);
    if (!_serviceSemanticVersionPattern.hasMatch(version)) {
      _failService('Service contract "$id" must use SemVer 2.0.', element);
    }
    final description = annotated.annotation.read('description').stringValue;
    if (description.length > _serviceMaxDescriptionLength) {
      _failService(
        'Service contract "$id" description exceeds '
        '$_serviceMaxDescriptionLength characters.',
        element,
      );
    }
    final model = _ServiceContractModel(
      element: element,
      componentId: componentId,
      id: id,
      version: version,
      description: description,
      members: _readServiceMembers(element),
    );
    if (!ids.add(id)) {
      _failService(
        'Duplicate Service contract ID "$id" in this library.',
        element,
      );
    }
    if (!tokenSymbols.add(model.tokenSymbol)) {
      _failService(
        'Service contracts in this library generate duplicate Token symbol '
        '"${model.tokenSymbol}".',
        element,
      );
    }
    contracts.add(model);
  }
  contracts.sort((left, right) => left.id.compareTo(right.id));
  return contracts;
}

/// Reads and validates every simple Service implementation in one library.
List<_ServiceModel> _readServices(LibraryReader library) {
  final services = <_ServiceModel>[];
  final registrationFunctions = <String>{};
  for (final annotated in library.annotatedWith(_serviceChecker)) {
    final element = annotated.element;
    if (element is! ClassElement ||
        element.isAbstract ||
        element.typeParameters.isNotEmpty ||
        element.displayName.startsWith('_')) {
      _failService(
        'CCService requires a public, concrete, non-generic class.',
        element,
      );
    }
    final constructor = element.unnamedConstructor;
    if (constructor == null ||
        constructor.isFactory ||
        constructor.formalParameters.isNotEmpty) {
      _failService(
        'CCService requires an unnamed zero-argument generative constructor. '
        'Use CCComponentContribution for custom construction.',
        element,
      );
    }
    final annotation = annotated.annotation;
    final declaredId = annotation.read('id');
    final directContracts = <_ServiceContractModel>[
      for (final interface in element.interfaces)
        if (_serviceContractAnnotation(interface.element) case final contract?)
          contract,
    ];
    final directContractElements = directContracts
        .map((contract) => contract.element)
        .toSet();
    final inheritedContracts =
        element.allSupertypes
            .where(
              (type) =>
                  !directContractElements.contains(type.element) &&
                  _serviceContractAnnotation(type.element) != null,
            )
            .map((type) => type.element.displayName)
            .toSet()
            .toList()
          ..sort();
    if (directContracts.length > 1) {
      final names =
          directContracts
              .map((contract) => contract.element.displayName)
              .toList()
            ..sort();
      _failService(
        'CCService ${element.displayName} directly implements multiple '
        'CCServiceContract interfaces (${names.join(', ')}). Split the '
        'implementations so each generated Provider has one stable contract.',
        element,
      );
    }
    final inferredContract = directContracts.singleOrNull;
    if (inheritedContracts.isNotEmpty) {
      _failService(
        'CCService ${element.displayName} inherits Service contract '
        '${inheritedContracts.join(', ')} indirectly. Implement exactly one '
        'CCServiceContract directly and remove other inherited contracts so '
        'automatic binding is unambiguous.',
        element,
      );
    }
    if (inferredContract != null && !declaredId.isNull) {
      _failService(
        'CCService ${element.displayName} implements '
        '${inferredContract.element.displayName}; omit id because the public '
        'contract already owns the stable Service identity.',
        element,
      );
    }
    if (inferredContract == null && declaredId.isNull) {
      _failService(
        'CCService ${element.displayName} must declare id when it does not '
        'directly implement a CCServiceContract.',
        element,
      );
    }
    late final InterfaceType lookupType;
    ClassElement? contractElement;
    String? contractId;
    late final String id;
    if (inferredContract != null) {
      lookupType = inferredContract.element.thisType;
      contractElement = inferredContract.element;
      contractId = inferredContract.id;
      id = inferredContract.id;
    } else {
      id = declaredId.stringValue;
      _validateServiceId(id, 'Service ID', element);
      lookupType = element.thisType;
    }
    final keyReader = annotation.read('key');
    final key = keyReader.isNull ? null : keyReader.stringValue;
    if (key != null) _validateServiceId(key, 'Service Key', element);
    final model = _ServiceModel(
      element: element,
      constructor: constructor,
      lookupType: lookupType,
      contractElement: contractElement,
      id: id,
      contractId: contractId,
      key: key,
      scope: _serviceEnumName(annotation.read('scope').objectValue),
      creationPolicy: _serviceEnumName(
        annotation.read('creationPolicy').objectValue,
      ),
      isDefault: annotation.read('isDefault').boolValue,
    );
    if (!registrationFunctions.add(model.registrationFunction)) {
      _failService(
        'CCService declarations generate duplicate registration function '
        '"${model.registrationFunction}".',
        element,
      );
    }
    services.add(model);
  }
  services.sort((left, right) => left.id.compareTo(right.id));
  return services;
}

/// Reads one directly implemented Service contract without scanning source text.
_ServiceContractModel? _serviceContractAnnotation(InterfaceElement element) {
  final annotation = _serviceContractChecker.firstAnnotationOfExact(element);
  if (annotation == null || element is! ClassElement) return null;
  final component = annotation.getField('componentId');
  final componentId = component?.getField('value')?.toStringValue();
  final id = annotation.getField('id')?.toStringValue();
  final version = annotation.getField('version')?.toStringValue() ?? '0.1.0';
  final description = annotation.getField('description')?.toStringValue() ?? '';
  if (componentId == null || id == null) {
    _failService(
      'CCServiceContract must provide const componentId and id values.',
      element,
    );
  }
  _validateServiceId(componentId, 'Component ID', element);
  _validateServiceId(id, 'Service contract ID', element);
  if (!_serviceSemanticVersionPattern.hasMatch(version)) {
    _failService('Service contract "$id" must use SemVer 2.0.', element);
  }
  _validateServiceContractInheritance(element);
  return _ServiceContractModel(
    element: element,
    componentId: componentId,
    id: id,
    version: version,
    description: description,
    members: _readServiceMembers(element),
  );
}

/// Rejects inherited member graphs until substitution is generated precisely.
void _validateServiceContractInheritance(ClassElement contract) {
  if (contract.interfaces.isEmpty && contract.mixins.isEmpty) return;
  _failService(
    'Service contract ${contract.displayName} must declare its Proxy members '
    'directly. Contract inheritance and mixins are not supported by the first '
    'Proxy generation version.',
    contract,
  );
}

/// Reads every directly declared Proxy member and rejects ambiguous shapes.
List<_ServiceMemberModel> _readServiceMembers(ClassElement contract) {
  final members = <_ServiceMemberModel>[];
  for (final setter in contract.setters.where((member) => !member.isStatic)) {
    _failService(
      'Service contract ${contract.displayName} contains setter '
      '"${setter.displayName}". Generated Service Proxies do not support '
      'setters; expose an explicit method instead.',
      setter,
    );
  }
  for (final method in contract.methods.where((member) => !member.isStatic)) {
    if (method.displayName.startsWith('_')) {
      _failService(
        'Service contract methods must be public because the Proxy is emitted '
        'in the consuming Package.',
        method,
      );
    }
    if (method.isOperator) {
      _failService(
        'Service contract ${contract.displayName} contains operator '
        '"${method.displayName}". Generated Service Proxies support named '
        'methods only.',
        method,
      );
    }
    members.add(
      _readServiceMember(
        method,
        kind: 'method',
        typeParameters: method.typeParameters,
        parameters: method.formalParameters,
      ),
    );
  }
  for (final getter in contract.getters.where((member) => !member.isStatic)) {
    if (getter.displayName.startsWith('_')) {
      _failService(
        'Service contract getters must be public because the Proxy is emitted '
        'in the consuming Package.',
        getter,
      );
    }
    members.add(
      _readServiceMember(
        getter,
        kind: 'getter',
        typeParameters: const [],
        parameters: const [],
      ),
    );
  }
  members.sort((left, right) {
    final id = left.methodId.compareTo(right.methodId);
    return id != 0 ? id : left.kind.compareTo(right.kind);
  });
  return List.unmodifiable(members);
}

/// Validates one method/getter result and all forwarded parameters.
_ServiceMemberModel _readServiceMember(
  ExecutableElement member, {
  required String kind,
  required List<TypeParameterElement> typeParameters,
  required List<FormalParameterElement> parameters,
}) {
  final allowedTypeParameters = typeParameters.toSet();
  for (final typeParameter in typeParameters) {
    final bound = typeParameter.bound;
    if (bound != null) {
      _validateServiceProxyType(
        bound,
        typeParameter,
        allowVoid: false,
        allowedTypeParameters: allowedTypeParameters,
      );
    }
  }
  for (final parameter in parameters) {
    if (parameter.formalParameters.isNotEmpty ||
        parameter.typeParameters.isNotEmpty ||
        parameter.type is FunctionType) {
      _failService(
        'Service contract member "${member.displayName}" contains callback '
        'parameter "${parameter.displayName}". Callback lifecycle cannot be '
        'represented by the first generated Proxy version.',
        parameter,
      );
    }
    _validateServiceProxyType(
      parameter.type,
      parameter,
      allowVoid: false,
      allowedTypeParameters: allowedTypeParameters,
    );
  }
  final returnType = member.returnType;
  if (returnType.isDartAsyncFutureOr) {
    _failService(
      'Service contract member "${member.displayName}" returns FutureOr. '
      'Choose an explicitly synchronous value or Future<T>.',
      member,
    );
  }
  if (returnType.isDartAsyncStream) {
    _failService(
      'Service contract member "${member.displayName}" returns Stream. '
      'Subscription ownership is not supported by generated Service Proxies.',
      member,
    );
  }
  final isAsync = returnType.isDartAsyncFuture;
  if (isAsync && returnType.nullabilitySuffix == NullabilitySuffix.question) {
    _failService(
      'Service contract member "${member.displayName}" must not return a '
      'nullable Future; return Future<T?> when the result is nullable.',
      member,
    );
  }
  final resultType = isAsync
      ? (returnType as InterfaceType).typeArguments.single
      : returnType;
  _validateServiceProxyType(
    resultType,
    member,
    allowVoid: true,
    allowedTypeParameters: allowedTypeParameters,
  );
  return _ServiceMemberModel(
    element: member,
    kind: kind,
    returnType: returnType,
    resultType: resultType,
    isAsync: isAsync,
    typeParameters: List.unmodifiable(typeParameters),
    parameters: List.unmodifiable(parameters),
  );
}

/// Validates a type that must survive in a standalone generated Proxy library.
void _validateServiceProxyType(
  DartType type,
  Element owner, {
  required bool allowVoid,
  required Set<TypeParameterElement> allowedTypeParameters,
}) {
  if (type is VoidType) {
    if (allowVoid) return;
    _failService('Service parameters cannot use void.', owner);
  }
  if (type is NeverType) return;
  if (type is TypeParameterType) {
    if (!allowedTypeParameters.contains(type.element)) {
      _failService(
        'Generated Service Proxy type parameter "${type.element.displayName}" '
        'must be declared by the current method.',
        owner,
      );
    }
    return;
  }
  if (type is DynamicType || type is InvalidType) {
    _failService(
      'Generated Service Proxy types must be statically known; dynamic and '
      'invalid values are unsupported.',
      owner,
    );
  }
  if (type is FunctionType) {
    _failService(
      'Generated Service Proxies do not support callback or function types.',
      owner,
    );
  }
  if (type is RecordType) {
    for (final field in [...type.positionalFields, ...type.namedFields]) {
      _validateServiceProxyType(
        field.type,
        owner,
        allowVoid: false,
        allowedTypeParameters: allowedTypeParameters,
      );
    }
    return;
  }
  if (type is! InterfaceType) {
    _failService(
      'Generated Service Proxies support interface, record, void, and Never '
      'types only.',
      owner,
    );
  }
  if (type.isDartAsyncFutureOr || type.isDartAsyncStream) {
    _failService(
      'Generated Service Proxies do not support FutureOr or Stream types.',
      owner,
    );
  }
  final alias = type.alias;
  final element = alias?.element ?? type.element;
  if (element.displayName.startsWith('_')) {
    _failService(
      'Service contract type "${element.displayName}" must be public.',
      owner,
    );
  }
  final uri = element.library.uri.toString();
  if (uri == 'dart:ui' ||
      uri.startsWith('package:flutter/') ||
      uri.startsWith('package:go_router/')) {
    _failService(
      'Service contracts must remain backend-neutral Pure Dart and cannot '
      'expose Flutter, dart:ui, or GoRouter types.',
      owner,
    );
  }
  for (final argument in alias?.typeArguments ?? type.typeArguments) {
    _validateServiceProxyType(
      argument,
      owner,
      allowVoid: false,
      allowedTypeParameters: allowedTypeParameters,
    );
  }
}

/// Serializes one method type parameter for generated Service metadata.
String _serviceTypeParameterMetadata(TypeParameterElement parameter) {
  final bound = parameter.bound;
  return bound == null
      ? parameter.displayName
      : '${parameter.displayName} extends ${bound.getDisplayString()}';
}

/// Validates one stable generated Service identifier.
void _validateServiceId(String value, String kind, Element element) {
  if (value.length > _serviceMaxStableIdLength ||
      !_serviceStableIdPattern.hasMatch(value)) {
    _failService(
      '$kind "$value" is invalid; start with lowercase and use alphanumeric '
      'segments separated by ".", "_", or "-" '
      '(maximum $_serviceMaxStableIdLength characters).',
      element,
    );
  }
}

/// Reads one evaluated enum constant's source member name.
String _serviceEnumName(DartObject value) {
  final type = value.type as InterfaceType;
  final index = value.getField('index')!.toIntValue()!;
  return type.element.fields
      .where((field) => field.isEnumConstant)
      .elementAt(index)
      .displayName;
}

/// Returns a prefixed source reference for a validated lookup type.
String _serviceTypeReference(
  InterfaceType type, {
  required String sourceUri,
  required Map<String, String> importedTypes,
}) {
  final uri = type.element.library.uri.toString();
  final prefix = uri == sourceUri ? 'service_source' : importedTypes[uri]!;
  return '$prefix.${type.element.displayName}';
}

/// Produces a lower-camel generated symbol from one public type name.
String _serviceLowerCamel(String value) =>
    value.isEmpty ? value : '${value[0].toLowerCase()}${value.substring(1)}';

/// Maps one authored library to a generated library while preserving folders.
String _serviceGeneratedLibraryPath(
  String source, {
  required String directory,
  required String suffix,
}) {
  if (!source.startsWith('lib/')) {
    throw StateError('Service source must be below lib/.');
  }
  final relative = source.substring('lib/'.length);
  final stem = relative.endsWith('.dart')
      ? relative.substring(0, relative.length - '.dart'.length)
      : relative;
  final normalized = stem.startsWith('src/')
      ? stem.substring('src/'.length)
      : stem;
  return 'lib/src/ccrouter_generated/$directory/$normalized$suffix';
}

/// Converts a Package-relative library path into a portable Package URI.
String _servicePackageUri(String package, String libraryPath) {
  if (!libraryPath.startsWith('lib/')) {
    throw StateError('Service library must be below lib/.');
  }
  return 'package:$package/${libraryPath.substring('lib/'.length)}';
}

/// Serializes one declaration's portable Package URI and source coordinates.
Map<String, Object?> _serviceSourceReference(Element element) {
  final fragment = element.firstFragment;
  final libraryFragment = fragment.libraryFragment!;
  final location = libraryFragment.lineInfo.getLocation(
    fragment.nameOffset ?? fragment.offset,
  );
  return <String, Object?>{
    'symbol': element.displayName,
    'packageUri': libraryFragment.source.uri.toString(),
    'line': location.lineNumber,
    'column': location.columnNumber,
  };
}

/// Reports a source-attached generation failure without exposing analyzer APIs.
Never _failService(String message, Element element) {
  throw InvalidGenerationSourceError(message, element: element);
}
