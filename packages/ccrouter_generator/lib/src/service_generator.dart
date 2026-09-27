import 'dart:convert';

import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

/// Maximum length accepted for generated Service identities and Keys.
const int _serviceMaxStableIdLength = 128;

/// Maximum description length retained in generated Service metadata.
const int _serviceMaxDescriptionLength = 4096;

/// Stable identifier syntax shared by generated Service contracts and Keys.
final RegExp _serviceStableIdPattern = RegExp(
  r'^[a-z][A-Za-z0-9]*(?:[._-][A-Za-z0-9]+)*$',
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

/// Creates generated typed Tokens for public Service contracts.
Generator ccServiceContractGenerator() => _ServiceContractGenerator();

/// Creates generated Provider registration bridges for simple Services.
Generator ccServiceGenerator() => _ServiceGenerator();

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
        ..writeln('/// Typed token for Service `${contract.id}`.')
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
      ..writeln("import 'package:ccrouter/ccrouter.dart';")
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
          '      contract: const CCServiceToken<$lookupType>('
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
      'schemaVersion': 3,
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
            'description': contract.description,
            'package': package,
            'source': source,
            'declaration': _serviceSourceReference(contract.element),
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
    required this.description,
  });

  /// Public abstract interface carrying the business method signatures.
  final ClassElement element;

  /// Explicit owner retained even when the contracts Package has many owners.
  final String componentId;

  /// Stable Runtime identity serialized into the generated Token.
  final String id;

  /// Authored usage scenario retained in generated catalogs.
  final String description;

  /// Predictable public Token symbol exported by the contracts Package.
  String get tokenSymbol => '${_serviceLowerCamel(element.displayName)}Token';
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
    _validateServiceId(id, 'Service contract ID', element);
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
      description: description,
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
    final contract = annotation.read('contract');
    final hasContract = !contract.isNull;
    if (hasContract == !declaredId.isNull) {
      _failService(
        'CCService must set exactly one of id or contract.',
        element,
      );
    }
    late final InterfaceType lookupType;
    ClassElement? contractElement;
    String? contractId;
    late final String id;
    if (hasContract) {
      final token = contract.objectValue;
      final tokenType = token.type;
      if (tokenType is! InterfaceType || tokenType.typeArguments.length != 1) {
        _failService(
          'CCService contract must be a typed CCServiceToken.',
          element,
        );
      }
      final type = tokenType.typeArguments.single;
      if (type is! InterfaceType || type.element is! ClassElement) {
        _failService(
          'CCService contract Token must reference a public interface type.',
          element,
        );
      }
      lookupType = type;
      contractElement = type.element as ClassElement;
      if (contractElement.displayName.startsWith('_')) {
        _failService('CCService contract type must be public.', element);
      }
      contractId = token.getField('id')?.toStringValue();
      if (contractId == null) {
        _failService(
          'CCService contract must carry a stable Token ID.',
          element,
        );
      }
      _validateServiceId(contractId, 'Service contract ID', element);
      id = contractId;
      if (!element.library.typeSystem.isAssignableTo(element.thisType, type)) {
        _failService(
          'CCService implementation ${element.displayName} must implement '
          '${contractElement.displayName}.',
          element,
        );
      }
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
