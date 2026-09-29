import 'dart:convert';

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

import 'contract_fingerprint.dart';
import 'generated_client_naming.dart';

/// Maximum stable Command identifier length.
const int _commandMaxStableIdLength = 128;

/// Maximum Command description retained in metadata.
const int _commandMaxDescriptionLength = 4096;

/// Portable syntax shared by generated Command identities.
final RegExp _commandStableIdPattern = RegExp(
  r'^[a-z][A-Za-z0-9]*(?:[._-][A-Za-z0-9]+)*$',
);

/// SemVer 2.0 syntax used by independent Command Contracts.
final RegExp _commandSemanticVersionPattern = RegExp(
  r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)'
  r'(?:-(?:0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*)'
  r'(?:\.(?:0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*))*)?'
  r'(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$',
);

/// Matches generated Command contracts from the canonical contracts package.
const TypeChecker _commandContractChecker = TypeChecker.typeNamedLiterally(
  'CCCommandContract',
  inPackage: 'ccrouter_contracts',
);

/// Matches Command handler functions from the canonical contracts package.
const TypeChecker _commandHandlerChecker = TypeChecker.typeNamedLiterally(
  'CCCommandHandler',
  inPackage: 'ccrouter_contracts',
);

/// Matches the typed Command marker.
const TypeChecker _commandChecker = TypeChecker.typeNamedLiterally(
  'CCCommand',
  inPackage: 'ccrouter_contracts',
);

/// Creates package-internal Handler registration bridges.
Generator ccCommandGenerator() => _CommandGenerator();

/// Creates disposable Command metadata for workspace aggregation.
Builder ccCommandMetadataBuilderInternal() => _CommandMetadataBuilder();

/// Emits one registration function for every annotated Handler source.
final class _CommandGenerator extends Generator {
  /// Generates no source for libraries without Command handlers.
  @override
  String generate(LibraryReader library, BuildStep buildStep) {
    if (buildStep.inputId.path.contains('/ccrouter_generated/')) return '';
    final handlers = _readCommandHandlers(library);
    if (handlers.isEmpty) return '';
    final sourceUri = _commandPackageUri(
      buildStep.inputId.package,
      buildStep.inputId.path,
    );
    final imports = <String, String>{};
    for (final handler in handlers) {
      final uri = handler.contract.element.library.uri.toString();
      if (uri != sourceUri) {
        imports.putIfAbsent(uri, () => 'command_type_${imports.length}');
      }
    }
    final out = StringBuffer()
      ..writeln("import 'package:ccrouter/ccrouter_generated.dart';")
      ..writeln("import '$sourceUri' as command_source;");
    for (final entry in imports.entries) {
      out.writeln("import '${entry.key}' as ${entry.value};");
    }
    out.writeln();
    for (final handler in handlers) {
      final typeUri = handler.contract.element.library.uri.toString();
      final prefix = typeUri == sourceUri
          ? 'command_source'
          : imports[typeUri]!;
      final commandType = '$prefix.${handler.contract.element.displayName}';
      final resultType = _commandTypeSource(handler.contract.resultType);
      out
        ..writeln('/// Registers generated Command `${handler.contract.id}`.')
        ..writeln('void ${handler.registrationFunction}(CCRegistry registry) {')
        ..writeln('  registry.registerCommand<$commandType, $resultType>(')
        ..writeln(
          handler.element.formalParameters.length == 1
              ? '    (command, _) => command_source.${handler.element.displayName}(command),'
              : '    command_source.${handler.element.displayName},',
        )
        ..writeln('    commandId: ${jsonEncode(handler.contract.id)},')
        ..writeln('  );')
        ..writeln('}')
        ..writeln();
    }
    return out.toString();
  }
}

/// Emits Contract and Handler records consumed by workspace generation.
final class _CommandMetadataBuilder implements Builder {
  /// Creates source-preserving cache outputs.
  _CommandMetadataBuilder()
    : buildExtensions = const {
        r'^lib/{{}}.dart': [
          'lib/src/ccrouter_generated/metadata/{{}}.command.json',
        ],
      };

  @override
  final Map<String, List<String>> buildExtensions;

  /// Writes no output when one library has no Command declarations.
  @override
  Future<void> build(BuildStep buildStep) async {
    if (buildStep.inputId.path.contains('/ccrouter_generated/')) return;
    if (!await buildStep.resolver.isLibrary(buildStep.inputId)) return;
    final library = LibraryReader(
      await buildStep.resolver.libraryFor(buildStep.inputId),
    );
    await _validateGeneratedCommandUsage(library.element, buildStep);
    final contracts = _readCommandContracts(library);
    final handlers = _readCommandHandlers(library);
    if (contracts.isEmpty && handlers.isEmpty) return;
    final package = buildStep.inputId.package;
    final source = buildStep.inputId.path;
    final registrationLibrary = _commandGeneratedLibraryPath(source);
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
      'serviceContracts': <Object>[],
      'serviceImplementations': <Object>[],
      'commandContracts': [
        for (final contract in contracts)
          <String, Object?>{
            'id': contract.id,
            'componentId': contract.componentId,
            if (contract.alias != null) 'alias': contract.alias,
            'version': contract.version,
            'description': contract.description,
            'package': package,
            'source': source,
            'type': contract.element.displayName,
            'resultType': contract.resultType.getDisplayString(),
            'payloadFields': [
              for (final field in contract.element.fields.where(
                (field) => !field.isStatic,
              ))
                <String, Object?>{
                  'name': field.displayName,
                  'type': field.type.getDisplayString(),
                },
            ],
            'shapeFingerprint': contractShapeFingerprint(<String, Object?>{
              'kind': 'command',
              'id': contract.id,
              'owner': contract.componentId,
              if (contract.alias != null) 'alias': contract.alias,
              'resultType': contract.resultType.getDisplayString(),
              'payloadFields': [
                for (final field in contract.element.fields.where(
                  (field) => !field.isStatic,
                ))
                  <String, Object?>{
                    'name': field.displayName,
                    'type': field.type.getDisplayString(),
                  },
              ],
            }),
            'declaration': _commandSourceReference(contract.element),
          },
      ],
      'commandHandlers': [
        for (final handler in handlers)
          <String, Object?>{
            'id': handler.contract.id,
            'componentId': handler.contract.componentId,
            'package': package,
            'source': source,
            'commandType': handler.contract.element.displayName,
            'resultType': handler.contract.resultType.getDisplayString(),
            'contract': _commandSourceReference(handler.contract.element),
            'implementation': _commandSourceReference(handler.element),
            'registration': handler.registrationFunction,
            'registrationLibrary': registrationLibrary,
            'generatedArtifacts': [
              <String, Object?>{
                'role': 'commandRegistration',
                'symbol': handler.registrationFunction,
                'packageUri': _commandPackageUri(package, registrationLibrary),
              },
            ],
          },
      ],
    };
    final output = buildStep.allowedOutputs.singleWhere(
      (candidate) => candidate.path.endsWith('.command.json'),
    );
    await buildStep.writeAsString(
      output,
      '${const JsonEncoder.withIndent('  ').convert(payload)}\n',
    );
  }
}

/// Rejects raw facade dispatch for a statically annotated Command argument.
Future<void> _validateGeneratedCommandUsage(
  LibraryElement library,
  BuildStep buildStep,
) async {
  for (final fragment in library.fragments) {
    final node = await buildStep.resolver.astNodeFor(fragment, resolve: true);
    if (node == null) continue;
    node.accept(_RawCommandInvocationVisitor());
  }
}

/// Finds resolved `CCRouter.command(annotatedCommand)` calls.
final class _RawCommandInvocationVisitor extends RecursiveAstVisitor<void> {
  /// Validates one method invocation after visiting its children.
  @override
  void visitMethodInvocation(MethodInvocation node) {
    super.visitMethodInvocation(node);
    if (node.methodName.name != 'command' ||
        node.argumentList.arguments.isEmpty) {
      return;
    }
    final method = node.methodName.element;
    if (method?.enclosingElement?.displayName != 'CCRouter' ||
        method?.library?.uri.toString() != 'package:ccrouter/src/facade.dart') {
      return;
    }
    final type = node.argumentList.arguments.first.staticType;
    if (type is! InterfaceType || type.element is! ClassElement) return;
    if (_commandContractChecker.firstAnnotationOfExact(type.element) == null) {
      return;
    }
    _failCommand(
      'Annotated Command ${type.element.displayName} must use its generated '
      'component Client instead of CCRouter.command so stable ID and caller '
      'identity cannot be bypassed.',
      type.element,
    );
  }
}

/// Validated generated Command contract.
final class _CommandContractModel {
  /// Creates an immutable generation model.
  const _CommandContractModel({
    required this.element,
    required this.componentId,
    required this.id,
    required this.alias,
    required this.version,
    required this.description,
    required this.resultType,
  });

  /// Annotated Command class.
  final ClassElement element;

  /// Explicit owner, or null for an implementation-package internal Command.
  final String? componentId;

  /// Stable Command identity.
  final String id;

  /// Contract-wide default method for generated owner and consumer Clients.
  final String? alias;

  /// Independent Command Contract SemVer.
  final String version;

  /// Documented usage scenario.
  final String description;

  /// Typed Command result.
  final DartType resultType;
}

/// Validated generated Command handler.
final class _CommandHandlerModel {
  /// Creates one Handler model.
  const _CommandHandlerModel({required this.element, required this.contract});

  /// Public top-level Handler function.
  final TopLevelFunctionElement element;

  /// Command Contract inferred from the first parameter.
  final _CommandContractModel contract;

  /// Stable package-internal registration bridge.
  String get registrationFunction =>
      'ccrouterRegister${element.displayName[0].toUpperCase()}${element.displayName.substring(1)}Command';
}

/// Reads and validates every Command contract in one library.
List<_CommandContractModel> _readCommandContracts(LibraryReader library) {
  final contracts = <_CommandContractModel>[];
  final ids = <String>{};
  for (final annotated in library.annotatedWith(_commandContractChecker)) {
    final element = annotated.element;
    if (element is! ClassElement ||
        element.isAbstract ||
        element.typeParameters.isNotEmpty ||
        element.displayName.startsWith('_')) {
      _failCommand(
        'CCCommandContract requires a public, concrete, non-generic class.',
        element,
      );
    }
    final commandInterfaces = element.allSupertypes
        .where((type) => _commandChecker.isExactlyType(type))
        .toList(growable: false);
    if (commandInterfaces.length != 1 ||
        commandInterfaces.single.typeArguments.length != 1) {
      _failCommand(
        'CCCommandContract ${element.displayName} must implement exactly one CCCommand<R>.',
        element,
      );
    }
    final resultType = commandInterfaces.single.typeArguments.single;
    _validateCommandType(resultType, element, role: 'result');
    for (final field in element.fields.where((field) => !field.isStatic)) {
      if (!field.isFinal || field.setter != null) {
        _failCommand(
          'Command payload field "${field.displayName}" must be final and have no setter.',
          field,
        );
      }
      _validateCommandType(field.type, field, role: 'payload');
    }
    final componentObject = annotated.annotation
        .peek('componentId')
        ?.objectValue;
    final componentId = componentObject?.getField('value')?.toStringValue();
    if (componentId != null) {
      _validateCommandId(componentId, 'Component ID', element);
    }
    final id = annotated.annotation.read('id').stringValue;
    final aliasReader = annotated.annotation.peek('alias');
    final alias = aliasReader == null || aliasReader.isNull
        ? null
        : aliasReader.stringValue;
    final version = annotated.annotation.read('version').stringValue;
    _validateCommandId(id, 'Command ID', element);
    if (alias != null && !isGeneratedClientMemberName(alias)) {
      _failCommand(
        'Command "$id" alias "$alias" must be a public lower-camel Dart '
        'identifier and must not be a keyword.',
        element,
      );
    }
    if (!_commandSemanticVersionPattern.hasMatch(version)) {
      _failCommand('Command "$id" must use SemVer 2.0.', element);
    }
    if (!ids.add(id)) {
      _failCommand('Duplicate Command ID "$id" in this library.', element);
    }
    final description = annotated.annotation.read('description').stringValue;
    if (description.length > _commandMaxDescriptionLength) {
      _failCommand(
        'Command "$id" description exceeds $_commandMaxDescriptionLength characters.',
        element,
      );
    }
    contracts.add(
      _CommandContractModel(
        element: element,
        componentId: componentId,
        id: id,
        alias: alias,
        version: version,
        description: description,
        resultType: resultType,
      ),
    );
  }
  contracts.sort((left, right) => left.id.compareTo(right.id));
  return contracts;
}

/// Reads and validates annotated top-level Command handlers.
List<_CommandHandlerModel> _readCommandHandlers(LibraryReader library) {
  final handlers = <_CommandHandlerModel>[];
  final ids = <String>{};
  final registrations = <String>{};
  for (final annotated in library.annotatedWith(_commandHandlerChecker)) {
    final element = annotated.element;
    if (element is! TopLevelFunctionElement ||
        element.displayName.startsWith('_') ||
        element.typeParameters.isNotEmpty) {
      _failCommand(
        'CCCommandHandler requires a public, top-level, non-generic function.',
        element,
      );
    }
    final parameters = element.formalParameters;
    if (parameters.isEmpty || parameters.length > 2) {
      _failCommand(
        'CCCommandHandler accepts (Command) or (Command, CCInvocationContext).',
        element,
      );
    }
    final commandType = parameters.first.type;
    if (commandType is! InterfaceType || commandType.element is! ClassElement) {
      _failCommand(
        'The first Handler parameter must be a Command class.',
        element,
      );
    }
    final contract = _readCommandContract(commandType.element as ClassElement);
    if (parameters.length == 2) {
      final context = parameters[1].type;
      if (context.element?.displayName != 'CCInvocationContext' ||
          context.element?.library?.uri.toString() !=
              'package:ccrouter_contracts/src/invocation.dart') {
        _failCommand(
          'The second Handler parameter must be CCInvocationContext.',
          parameters[1],
        );
      }
    }
    final actualResult = _commandUnwrapFuture(element.returnType);
    if (!_commandTypesEqual(actualResult, contract.resultType)) {
      _failCommand(
        'Handler result ${element.returnType.getDisplayString()} does not match '
        'CCCommand<${contract.resultType.getDisplayString()}>.',
        element,
      );
    }
    final model = _CommandHandlerModel(element: element, contract: contract);
    if (!ids.add(contract.id)) {
      _failCommand(
        'Command "${contract.id}" has more than one Handler in this library.',
        element,
      );
    }
    if (!registrations.add(model.registrationFunction)) {
      _failCommand(
        'Command handlers generate duplicate registration symbol "${model.registrationFunction}".',
        element,
      );
    }
    handlers.add(model);
  }
  handlers.sort((left, right) => left.contract.id.compareTo(right.contract.id));
  return handlers;
}

/// Reads one imported Command Contract annotation.
_CommandContractModel _readCommandContract(ClassElement element) {
  final annotation = _commandContractChecker.firstAnnotationOfExact(element);
  if (annotation == null) {
    _failCommand(
      'CCCommandHandler parameter ${element.displayName} must be annotated with CCCommandContract.',
      element,
    );
  }
  final interfaces = element.allSupertypes
      .where((type) => _commandChecker.isExactlyType(type))
      .toList(growable: false);
  if (interfaces.length != 1 || interfaces.single.typeArguments.length != 1) {
    _failCommand(
      'CCCommandContract ${element.displayName} must implement exactly one CCCommand<R>.',
      element,
    );
  }
  final componentId = annotation
      .getField('componentId')
      ?.getField('value')
      ?.toStringValue();
  final id = annotation.getField('id')?.toStringValue();
  final alias = annotation.getField('alias')?.toStringValue();
  final version = annotation.getField('version')?.toStringValue() ?? '0.1.0';
  if (id == null) {
    _failCommand('CCCommandContract requires a const id.', element);
  }
  _validateCommandId(id, 'Command ID', element);
  if (alias != null && !isGeneratedClientMemberName(alias)) {
    _failCommand(
      'Command "$id" alias "$alias" must be a public lower-camel Dart '
      'identifier and must not be a keyword.',
      element,
    );
  }
  if (!_commandSemanticVersionPattern.hasMatch(version)) {
    _failCommand('Command "$id" must use SemVer 2.0.', element);
  }
  return _CommandContractModel(
    element: element,
    componentId: componentId,
    id: id,
    alias: alias,
    version: version,
    description: annotation.getField('description')?.toStringValue() ?? '',
    resultType: interfaces.single.typeArguments.single,
  );
}

/// Validates the bounded public Pure Dart shape used by generated clients.
void _validateCommandType(
  DartType type,
  Element owner, {
  required String role,
}) {
  if (type is DynamicType ||
      type is FunctionType ||
      type is TypeParameterType) {
    _failCommand(
      'Command $role type must be concrete and callback-free.',
      owner,
    );
  }
  if (type is VoidType || type is NeverType) return;
  if (type is InterfaceType) {
    final element = type.element;
    if (element.displayName.startsWith('_')) {
      _failCommand('Command $role type must be public.', owner);
    }
    final uri = element.library.uri;
    if (uri.scheme == 'package' &&
        (uri.path.startsWith('flutter/') || uri.path.startsWith('dart:ui'))) {
      _failCommand(
        'Command $role type must not depend on Flutter UI types.',
        owner,
      );
    }
    for (final argument in type.typeArguments) {
      _validateCommandType(argument, owner, role: role);
    }
    return;
  }
  if (type is RecordType) {
    for (final field in [...type.positionalFields, ...type.namedFields]) {
      _validateCommandType(field.type, owner, role: role);
    }
    return;
  }
  _failCommand(
    'Unsupported Command $role type ${type.getDisplayString()}.',
    owner,
  );
}

/// Unwraps one Future result while preserving synchronous handlers.
DartType _commandUnwrapFuture(DartType type) {
  if (type is InterfaceType &&
      type.element.library.uri.toString() == 'dart:async' &&
      type.element.displayName == 'Future' &&
      type.typeArguments.length == 1) {
    return type.typeArguments.single;
  }
  return type;
}

/// Compares normalized result types without accepting dynamic substitution.
bool _commandTypesEqual(DartType left, DartType right) =>
    left.getDisplayString() == right.getDisplayString();

/// Renders result types used by a Handler registration source.
String _commandTypeSource(DartType type) {
  if (type is VoidType) return 'void';
  return type.getDisplayString();
}

/// Validates one stable Command or component identity.
void _validateCommandId(String value, String kind, Element owner) {
  if (value.length > _commandMaxStableIdLength ||
      !_commandStableIdPattern.hasMatch(value)) {
    _failCommand(
      '$kind "$value" is invalid; use stable lowercase-leading segments.',
      owner,
    );
  }
}

/// Reports one declaration failure through source_gen.
Never _failCommand(String message, Element element) =>
    throw InvalidGenerationSourceError(message, element: element);

/// Creates a package URI for a source library.
String _commandPackageUri(String package, String source) =>
    'package:$package/${source.substring('lib/'.length)}';

/// Derives the generated Handler registration output path.
String _commandGeneratedLibraryPath(String source) {
  final relative = source.substring('lib/src/'.length, source.length - 5);
  return 'lib/src/ccrouter_generated/command/$relative.command.g.dart';
}

/// Serializes a source declaration without embedding source contents.
Map<String, Object?> _commandSourceReference(Element element) {
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
