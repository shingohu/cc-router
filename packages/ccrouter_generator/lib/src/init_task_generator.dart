import 'dart:convert';

import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

import 'contract_fingerprint.dart';

/// Maximum stable initialization identity length.
const int _initTaskMaxStableIdLength = 128;

/// Maximum initialization task description retained in metadata.
const int _initTaskMaxDescriptionLength = 4096;

/// Portable syntax shared by generated Task and Gate identities.
final RegExp _initTaskStableIdPattern = RegExp(
  r'^[a-z][A-Za-z0-9]*(?:[._-][A-Za-z0-9]+)*$',
);

/// SemVer 2.0 syntax used by independent InitTask Contracts.
final RegExp _initTaskSemanticVersionPattern = RegExp(
  r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)'
  r'(?:-(?:0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*)'
  r'(?:\.(?:0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*))*)?'
  r'(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$',
);

/// Matches typed initialization task contracts.
const TypeChecker _initTaskContractChecker = TypeChecker.typeNamedLiterally(
  'CCInitTaskContract',
  inPackage: 'ccrouter_contracts',
);

/// Matches generated initialization task handlers.
const TypeChecker _initTaskChecker = TypeChecker.typeNamedLiterally(
  'CCInitTask',
  inPackage: 'ccrouter_contracts',
);

/// Creates package-internal initialization task registration bridges.
Generator ccInitTaskGenerator() => _InitTaskGenerator();

/// Creates disposable initialization metadata for workspace aggregation.
Builder ccInitTaskMetadataBuilderInternal() => _InitTaskMetadataBuilder();

/// Emits one registration function per annotated initialization handler.
final class _InitTaskGenerator extends Generator {
  /// Generates no source for libraries without initialization handlers.
  @override
  String generate(LibraryReader library, BuildStep buildStep) {
    if (buildStep.inputId.path.contains('/ccrouter_generated/')) return '';
    final tasks = _readInitTasks(library);
    if (tasks.isEmpty) return '';
    final sourceUri = _initTaskPackageUri(
      buildStep.inputId.package,
      buildStep.inputId.path,
    );
    final out = StringBuffer()
      ..writeln("import 'package:ccrouter/ccrouter.dart';")
      ..writeln("import '$sourceUri' as init_source;")
      ..writeln();
    for (final task in tasks) {
      final handler = task.element.formalParameters.isEmpty
          ? '(_) => init_source.${task.element.displayName}()'
          : 'init_source.${task.element.displayName}';
      out
        ..writeln('/// Registers generated InitTask `${task.id}`.')
        ..writeln('void ${task.registrationFunction}(CCRegistry registry) {')
        ..writeln('  registry.registerInitTask(')
        ..writeln('    CCInitTaskDefinition(')
        ..writeln('      id: ${jsonEncode(task.id)},')
        ..writeln('      dependsOn: const [')
        ..writeAll(
          task.dependencies.map((id) => '        ${jsonEncode(id)},\n'),
        )
        ..writeln('      ],')
        ..writeln('      gate: CCInitTaskGate(${jsonEncode(task.gateId)}),')
        ..writeln(
          '      failurePolicy: CCInitTaskFailurePolicy.${task.failurePolicy},',
        );
      if (task.timeoutMicroseconds != null) {
        out.writeln(
          '      timeout: Duration(microseconds: ${task.timeoutMicroseconds}),',
        );
      }
      out
        ..writeln('      run: $handler,')
        ..writeln('    ),')
        ..writeln('  );')
        ..writeln('}')
        ..writeln();
    }
    return out.toString();
  }
}

/// Emits task Contract and Handler records into the build cache.
final class _InitTaskMetadataBuilder implements Builder {
  /// Creates source-preserving cache outputs.
  _InitTaskMetadataBuilder()
    : buildExtensions = const {
        r'^lib/{{}}.dart': [
          'lib/src/ccrouter_generated/metadata/{{}}.init_task.json',
        ],
      };

  @override
  final Map<String, List<String>> buildExtensions;

  /// Writes nothing when one library has no initialization declarations.
  @override
  Future<void> build(BuildStep buildStep) async {
    if (buildStep.inputId.path.contains('/ccrouter_generated/')) return;
    if (!await buildStep.resolver.isLibrary(buildStep.inputId)) return;
    final library = LibraryReader(
      await buildStep.resolver.libraryFor(buildStep.inputId),
    );
    await _validateInitTaskReferences(library.element, buildStep);
    final contracts = _readInitTaskContracts(library);
    final tasks = _readInitTasks(library);
    if (contracts.isEmpty && tasks.isEmpty) return;
    final package = buildStep.inputId.package;
    final source = buildStep.inputId.path;
    final registrationLibrary = _initTaskGeneratedLibraryPath(source);
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
      'commandContracts': <Object>[],
      'commandHandlers': <Object>[],
      'eventContracts': <Object>[],
      'eventSubscriptions': <Object>[],
      'initTaskContracts': [
        for (final contract in contracts)
          <String, Object?>{
            'id': contract.id,
            'componentId': contract.componentId,
            'version': contract.version,
            'description': contract.description,
            'package': package,
            'source': source,
            'declaration': _initTaskSourceReference(contract.element),
            'shapeFingerprint': contractShapeFingerprint(<String, Object?>{
              'kind': 'init_task',
              'id': contract.id,
              'owner': contract.componentId,
            }),
          },
      ],
      'initTasks': [
        for (final task in tasks)
          <String, Object?>{
            'id': task.id,
            'componentId': task.componentId,
            'contractId': task.contractId,
            'dependsOn': task.dependencies,
            'dependencyOwners': task.dependencyOwners,
            'gateId': task.gateId,
            'failurePolicy': task.failurePolicy,
            'timeoutMicroseconds': task.timeoutMicroseconds,
            'isAsync': task.isAsync,
            'package': package,
            'source': source,
            'implementation': _initTaskSourceReference(task.element),
            'registration': task.registrationFunction,
            'registrationLibrary': registrationLibrary,
            'generatedArtifacts': [
              <String, Object?>{
                'role': 'initTaskRegistration',
                'symbol': task.registrationFunction,
                'packageUri': _initTaskPackageUri(package, registrationLibrary),
              },
            ],
          },
      ],
    };
    final output = buildStep.allowedOutputs.singleWhere(
      (candidate) => candidate.path.endsWith('.init_task.json'),
    );
    await buildStep.writeAsString(
      output,
      '${const JsonEncoder.withIndent('  ').convert(payload)}\n',
    );
  }
}

/// Validated top-level initialization task contract constant.
final class _InitTaskContractModel {
  /// Creates one immutable task contract model.
  const _InitTaskContractModel({
    required this.element,
    required this.id,
    required this.componentId,
    required this.version,
    required this.description,
  });

  /// Top-level constant that declares the local or exported contract.
  final Element element;

  /// Stable task identity.
  final String id;

  /// Explicit owner, or null for a component-local contract.
  final String? componentId;

  /// Independent InitTask Contract SemVer.
  final String version;

  /// Documented purpose and usage scenario.
  final String description;
}

/// Validated generated initialization task handler.
final class _InitTaskModel {
  /// Creates one immutable task implementation model.
  const _InitTaskModel({
    required this.element,
    required this.id,
    required this.componentId,
    required this.contractId,
    required this.dependencies,
    required this.dependencyOwners,
    required this.gateId,
    required this.failurePolicy,
    required this.timeoutMicroseconds,
    required this.isAsync,
  });

  /// Public top-level Handler function.
  final TopLevelFunctionElement element;

  /// Stable task identity.
  final String id;

  /// Contract owner, or null for Package owner inference.
  final String? componentId;

  /// Contract identity when this Handler implements a typed Contract.
  final String? contractId;

  /// Stable typed dependency identities.
  final List<String> dependencies;

  /// Declared dependency owners aligned with [dependencies].
  final List<String?> dependencyOwners;

  /// Stable Gate identity.
  final String gateId;

  /// Serialized failure policy enum name.
  final String failurePolicy;

  /// Positive timeout in microseconds, or null when unbounded.
  final int? timeoutMicroseconds;

  /// Whether the Handler returns `Future<void>` or `FutureOr<void>`.
  final bool isAsync;

  /// Stable package-internal registration bridge.
  String get registrationFunction =>
      'ccrouterRegister${element.displayName[0].toUpperCase()}${element.displayName.substring(1)}InitTask';
}

/// Reads and validates top-level task Contract constants in one library.
List<_InitTaskContractModel> _readInitTaskContracts(LibraryReader library) {
  final contracts = <_InitTaskContractModel>[];
  final ids = <String>{};
  for (final element
      in library.allElements.whereType<TopLevelVariableElement>()) {
    if (!_initTaskContractChecker.isExactlyType(element.type)) continue;
    if (!element.isConst) {
      _failInitTask(
        'CCInitTaskContract declarations must be top-level const values.',
        element,
      );
    }
    final value = element.computeConstantValue();
    if (value == null) {
      _failInitTask(
        'CCInitTaskContract must be compile-time constant.',
        element,
      );
    }
    final model = _contractFromObject(value, element: element);
    if (!ids.add(model.id)) {
      _failInitTask(
        'Duplicate InitTask Contract ID "${model.id}" in this library.',
        element,
      );
    }
    contracts.add(model);
  }
  contracts.sort((left, right) => left.id.compareTo(right.id));
  return contracts;
}

/// Rejects inline Contract construction where a typed constant is required.
Future<void> _validateInitTaskReferences(
  LibraryElement library,
  BuildStep buildStep,
) async {
  for (final fragment in library.fragments) {
    final node = await buildStep.resolver.astNodeFor(fragment, resolve: true);
    if (node == null) continue;
    node.accept(_InitTaskReferenceVisitor());
  }
}

/// Validates the authored syntax of Contract and dependency references.
final class _InitTaskReferenceVisitor extends RecursiveAstVisitor<void> {
  @override
  void visitAnnotation(Annotation node) {
    super.visitAnnotation(node);
    final annotationElement = node.element;
    if (annotationElement?.enclosingElement?.displayName != 'CCInitTask' ||
        annotationElement?.library?.uri.toString() !=
            'package:ccrouter_contracts/src/initialization.dart') {
      return;
    }
    for (final argument
        in node.arguments?.arguments.whereType<NamedExpression>() ??
            const <NamedExpression>[]) {
      final name = argument.name.label.name;
      final expression = argument.expression;
      if (name == 'contract' && !_isInitTaskContractReference(expression)) {
        throw InvalidGenerationSourceError(
          'CCInitTask contract must reference a top-level '
          'CCInitTaskContract constant.',
          node: expression,
        );
      }
      if (name != 'dependsOn') continue;
      if (expression is! ListLiteral ||
          expression.elements.any(
            (element) =>
                element is! Expression ||
                !_isInitTaskContractReference(element),
          )) {
        throw InvalidGenerationSourceError(
          'CCInitTask dependsOn accepts only top-level '
          'CCInitTaskContract constant references.',
          node: expression,
        );
      }
    }
  }
}

/// Whether one expression directly identifies a local or imported constant.
bool _isInitTaskContractReference(Expression expression) =>
    expression is SimpleIdentifier || expression is PrefixedIdentifier;

/// Reads and validates every annotated initialization Handler.
List<_InitTaskModel> _readInitTasks(LibraryReader library) {
  final tasks = <_InitTaskModel>[];
  final ids = <String>{};
  for (final annotated in library.annotatedWith(_initTaskChecker)) {
    final element = annotated.element;
    if (element is! TopLevelFunctionElement ||
        element.displayName.startsWith('_') ||
        element.typeParameters.isNotEmpty) {
      _failInitTask(
        'CCInitTask requires a public, top-level, non-generic function.',
        element,
      );
    }
    final parameters = element.formalParameters;
    if (parameters.length > 1 ||
        parameters.any((parameter) => parameter.isOptional)) {
      _failInitTask(
        'CCInitTask Handler accepts no parameters or one CCInvocationContext.',
        element,
      );
    }
    if (parameters.isNotEmpty) {
      final context = parameters.single.type.element;
      if (context?.displayName != 'CCInvocationContext' ||
          context?.library?.uri.toString() !=
              'package:ccrouter_contracts/src/invocation.dart') {
        _failInitTask(
          'CCInitTask Handler parameter must be CCInvocationContext.',
          parameters.single,
        );
      }
    }
    if (!_initTaskVoidResult(element.returnType)) {
      _failInitTask(
        'CCInitTask Handler must return void, Future<void>, or FutureOr<void>.',
        element,
      );
    }
    final contractObject = annotated.annotation.peek('contract')?.objectValue;
    final rawId = annotated.annotation.peek('id');
    final directId = rawId == null || rawId.isNull ? null : rawId.stringValue;
    if ((contractObject == null) == (directId == null)) {
      _failInitTask(
        'CCInitTask must set exactly one of contract and id.',
        element,
      );
    }
    final contract = contractObject == null
        ? null
        : _contractFromObject(contractObject, element: element);
    final id = contract?.id ?? directId!;
    _validateInitTaskId(id, 'InitTask ID', element);
    if (!ids.add(id)) {
      _failInitTask('Duplicate InitTask ID "$id" in this library.', element);
    }
    final dependencies = <String>[];
    final dependencyOwners = <String?>[];
    final dependencyValues = annotated.annotation.read('dependsOn').listValue;
    for (final dependencyValue in dependencyValues) {
      final dependency = _contractFromObject(dependencyValue, element: element);
      if (dependency.id == id || dependencies.contains(dependency.id)) {
        _failInitTask(
          'InitTask "$id" has a duplicate or self dependency "${dependency.id}".',
          element,
        );
      }
      dependencies.add(dependency.id);
      dependencyOwners.add(dependency.componentId);
    }
    final gate = annotated.annotation.read('gate').objectValue;
    final gateId = gate.getField('id')?.toStringValue();
    if (gateId == null) {
      _failInitTask('CCInitTask gate must have a const ID.', element);
    }
    _validateInitTaskId(gateId, 'Initialization Gate ID', element);
    final failureIndex = annotated.annotation
        .read('failurePolicy')
        .objectValue
        .getField('index')
        ?.toIntValue();
    if (failureIndex == null || failureIndex < 0 || failureIndex > 1) {
      _failInitTask('CCInitTask failure policy is unsupported.', element);
    }
    final failurePolicy = failureIndex == 0 ? 'required' : 'optional';
    final timeoutObject = annotated.annotation.peek('timeout')?.objectValue;
    final timeoutMicroseconds = timeoutObject
        ?.getField('_duration')
        ?.toIntValue();
    if (timeoutObject != null &&
        (timeoutMicroseconds == null || timeoutMicroseconds <= 0)) {
      _failInitTask('CCInitTask timeout must be positive.', element);
    }
    final isAsync = element.returnType is! VoidType;
    if (failurePolicy == 'required' && contract == null) {
      _failInitTask(
        'Required CCInitTask "$id" must use a CCInitTaskContract.',
        element,
      );
    }
    if (failurePolicy == 'required' && isAsync && timeoutMicroseconds == null) {
      _failInitTask(
        'Async required CCInitTask "$id" must declare a positive timeout.',
        element,
      );
    }
    tasks.add(
      _InitTaskModel(
        element: element,
        id: id,
        componentId: contract?.componentId,
        contractId: contract?.id,
        dependencies: List.unmodifiable(dependencies),
        dependencyOwners: List.unmodifiable(dependencyOwners),
        gateId: gateId,
        failurePolicy: failurePolicy,
        timeoutMicroseconds: timeoutMicroseconds,
        isAsync: isAsync,
      ),
    );
  }
  tasks.sort((left, right) => left.id.compareTo(right.id));
  return tasks;
}

/// Decodes and validates one constant task Contract object.
_InitTaskContractModel _contractFromObject(
  DartObject value, {
  required Element element,
}) {
  final id = value.getField('id')?.toStringValue();
  if (id == null) {
    _failInitTask('CCInitTaskContract requires a const id.', element);
  }
  _validateInitTaskId(id, 'InitTask Contract ID', element);
  final componentId = value
      .getField('componentId')
      ?.getField('value')
      ?.toStringValue();
  final version = value.getField('version')?.toStringValue() ?? '0.1.0';
  if (!_initTaskSemanticVersionPattern.hasMatch(version)) {
    _failInitTask('InitTask "$id" must use SemVer 2.0.', element);
  }
  if (componentId != null) {
    _validateInitTaskId(componentId, 'Component ID', element);
  }
  final description = value.getField('description')?.toStringValue() ?? '';
  if (description.length > _initTaskMaxDescriptionLength) {
    _failInitTask(
      'InitTask "$id" description exceeds '
      '$_initTaskMaxDescriptionLength characters.',
      element,
    );
  }
  return _InitTaskContractModel(
    element: element,
    id: id,
    componentId: componentId,
    version: version,
    description: description,
  );
}

/// Whether one Handler result has no business value.
bool _initTaskVoidResult(DartType type) {
  if (type is VoidType) return true;
  if (type is! InterfaceType || type.typeArguments.length != 1) return false;
  final uri = type.element.library.uri.toString();
  return uri == 'dart:async' &&
      (type.element.displayName == 'Future' ||
          type.element.displayName == 'FutureOr') &&
      type.typeArguments.single is VoidType;
}

/// Validates one stable Task, Gate, or component identity.
void _validateInitTaskId(String value, String kind, Element owner) {
  if (value.length > _initTaskMaxStableIdLength ||
      !_initTaskStableIdPattern.hasMatch(value)) {
    _failInitTask('$kind "$value" is invalid.', owner);
  }
}

/// Reports one source-attached InitTask generation failure.
Never _failInitTask(String message, Element element) =>
    throw InvalidGenerationSourceError(message, element: element);

/// Converts one package-relative source path into a Package URI.
String _initTaskPackageUri(String package, String source) =>
    'package:$package/${source.substring('lib/'.length)}';

/// Derives the generated task registration library path.
String _initTaskGeneratedLibraryPath(String source) {
  final relative = source.substring('lib/src/'.length, source.length - 5);
  return 'lib/src/ccrouter_generated/init_task/$relative.init_task.g.dart';
}

/// Serializes a portable Package URI and exact source coordinates.
Map<String, Object?> _initTaskSourceReference(Element element) {
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
