import 'dart:convert';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

/// Maximum stable Event or Subscriber identifier length.
const int _eventMaxStableIdLength = 128;

/// Maximum Event description retained in metadata.
const int _eventMaxDescriptionLength = 4096;

/// Portable syntax shared by Event and Subscriber identities.
final RegExp _eventStableIdPattern = RegExp(
  r'^[a-z][A-Za-z0-9]*(?:[._-][A-Za-z0-9]+)*$',
);

/// Matches generated Event contracts.
const TypeChecker _eventContractChecker = TypeChecker.typeNamedLiterally(
  'CCEventContract',
  inPackage: 'ccrouter_contracts',
);

/// Matches static Event subscription functions.
const TypeChecker _eventSubscriptionChecker = TypeChecker.typeNamedLiterally(
  'CCEventSubscription',
  inPackage: 'ccrouter_contracts',
);

/// Matches the Event marker interface.
const TypeChecker _eventChecker = TypeChecker.typeNamedLiterally(
  'CCEvent',
  inPackage: 'ccrouter_contracts',
);

/// Creates package-internal Subscriber registration bridges.
Generator ccEventGenerator() => _EventGenerator();

/// Creates disposable Event metadata for workspace aggregation.
Builder ccEventMetadataBuilderInternal() => _EventMetadataBuilder();

/// Emits one registration function per static Event subscription.
final class _EventGenerator extends Generator {
  /// Generates no source for libraries without Event subscriptions.
  @override
  String generate(LibraryReader library, BuildStep buildStep) {
    if (buildStep.inputId.path.contains('/ccrouter_generated/')) return '';
    final subscriptions = _readEventSubscriptions(library);
    if (subscriptions.isEmpty) return '';
    final sourceUri = _eventPackageUri(
      buildStep.inputId.package,
      buildStep.inputId.path,
    );
    final imports = <String, String>{};
    for (final subscription in subscriptions) {
      final uri = subscription.contract.element.library.uri.toString();
      if (uri != sourceUri) {
        imports.putIfAbsent(uri, () => 'event_type_${imports.length}');
      }
    }
    final out = StringBuffer()
      ..writeln("import 'package:ccrouter/ccrouter_generated.dart';")
      ..writeln("import '$sourceUri' as event_source;");
    for (final entry in imports.entries) {
      out.writeln("import '${entry.key}' as ${entry.value};");
    }
    out.writeln();
    for (final subscription in subscriptions) {
      final typeUri = subscription.contract.element.library.uri.toString();
      final prefix = typeUri == sourceUri ? 'event_source' : imports[typeUri]!;
      final eventType = '$prefix.${subscription.contract.element.displayName}';
      final handler = subscription.element.formalParameters.length == 1
          ? '(event, _) => event_source.${subscription.element.displayName}(event)'
          : 'event_source.${subscription.element.displayName}';
      out
        ..writeln(
          '/// Registers one generated subscriber for `${subscription.contract.id}`.',
        )
        ..writeln('void ${subscription.registrationFunction}(')
        ..writeln('  CCRegistry registry, {')
        ..writeln('  required String subscriberId,')
        ..writeln('}) {')
        ..writeln('  registry.registerEventSubscriber<$eventType>(')
        ..writeln('    CCEventSubscriber<$eventType>(')
        ..writeln('      id: CCEventSubscriberId<$eventType>(subscriberId),')
        ..writeln('      eventId: ${jsonEncode(subscription.contract.id)},')
        ..writeln('      handler: $handler,')
        ..writeln('    ),')
        ..writeln('  );')
        ..writeln('}')
        ..writeln();
    }
    return out.toString();
  }
}

/// Emits Event Contract and Subscription records into the build cache.
final class _EventMetadataBuilder implements Builder {
  /// Creates source-preserving cache outputs.
  _EventMetadataBuilder()
    : buildExtensions = const {
        r'^lib/{{}}.dart': [
          'lib/src/ccrouter_generated/metadata/{{}}.event.json',
        ],
      };

  @override
  final Map<String, List<String>> buildExtensions;

  /// Writes nothing when one library has no Event declarations.
  @override
  Future<void> build(BuildStep buildStep) async {
    if (buildStep.inputId.path.contains('/ccrouter_generated/')) return;
    if (!await buildStep.resolver.isLibrary(buildStep.inputId)) return;
    final libraryElement = await buildStep.resolver.libraryFor(
      buildStep.inputId,
    );
    final library = LibraryReader(libraryElement);
    await _validateGeneratedEventUsage(libraryElement, buildStep);
    final contracts = _readEventContracts(library);
    final subscriptions = _readEventSubscriptions(library);
    if (contracts.isEmpty && subscriptions.isEmpty) return;
    final package = buildStep.inputId.package;
    final source = buildStep.inputId.path;
    final registrationLibrary = _eventGeneratedLibraryPath(source);
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
      'serviceContracts': <Object>[],
      'serviceImplementations': <Object>[],
      'commandContracts': <Object>[],
      'commandHandlers': <Object>[],
      'eventContracts': [
        for (final contract in contracts)
          <String, Object?>{
            'id': contract.id,
            'componentId': contract.componentId,
            'description': contract.description,
            'package': package,
            'source': source,
            'type': contract.element.displayName,
            'declaration': _eventSourceReference(contract.element),
          },
      ],
      'eventSubscriptions': [
        for (final subscription in subscriptions)
          <String, Object?>{
            'eventId': subscription.contract.id,
            'eventComponentId': subscription.contract.componentId,
            'componentId': null,
            'subscriberId': subscription.subscriberId,
            'package': package,
            'source': source,
            'eventType': subscription.contract.element.displayName,
            'contract': _eventSourceReference(subscription.contract.element),
            'implementation': _eventSourceReference(subscription.element),
            'registration': subscription.registrationFunction,
            'registrationLibrary': registrationLibrary,
            'generatedArtifacts': [
              <String, Object?>{
                'role': 'eventSubscriptionRegistration',
                'symbol': subscription.registrationFunction,
                'packageUri': _eventPackageUri(package, registrationLibrary),
              },
            ],
          },
      ],
    };
    final output = buildStep.allowedOutputs.singleWhere(
      (candidate) => candidate.path.endsWith('.event.json'),
    );
    await buildStep.writeAsString(
      output,
      '${const JsonEncoder.withIndent('  ').convert(payload)}\n',
    );
  }
}

/// Validated generated Event contract.
final class _EventContractModel {
  /// Creates one immutable Event model.
  const _EventContractModel({
    required this.element,
    required this.componentId,
    required this.id,
    required this.description,
  });

  /// Annotated Event class.
  final ClassElement element;

  /// Explicit owner, or null for a package-internal Event.
  final String? componentId;

  /// Stable Event identity.
  final String id;

  /// Documented fact and usage scenario.
  final String description;
}

/// Validated static Event subscription.
final class _EventSubscriptionModel {
  /// Creates one immutable Subscription model.
  const _EventSubscriptionModel({
    required this.element,
    required this.contract,
    required this.subscriberId,
  });

  /// Public top-level subscriber function.
  final TopLevelFunctionElement element;

  /// Event Contract inferred from the first parameter.
  final _EventContractModel contract;

  /// Explicit Subscriber ID, or null for workspace default inference.
  final String? subscriberId;

  /// Stable package-internal registration bridge.
  String get registrationFunction =>
      'ccrouterRegister${element.displayName[0].toUpperCase()}${element.displayName.substring(1)}EventSubscription';
}

/// Reads and validates every Event Contract in one source library.
List<_EventContractModel> _readEventContracts(LibraryReader library) {
  final contracts = <_EventContractModel>[];
  final ids = <String>{};
  for (final annotated in library.annotatedWith(_eventContractChecker)) {
    final element = annotated.element;
    if (element is! ClassElement ||
        element.isAbstract ||
        element.typeParameters.isNotEmpty ||
        element.displayName.startsWith('_')) {
      _failEvent(
        'CCEventContract requires a public, concrete, non-generic class.',
        element,
      );
    }
    if (!_eventChecker.isAssignableFromType(element.thisType)) {
      _failEvent(
        'CCEventContract ${element.displayName} must implement CCEvent.',
        element,
      );
    }
    for (final field in element.fields.where((field) => !field.isStatic)) {
      if (!field.isFinal || field.setter != null) {
        _failEvent(
          'Event payload field "${field.displayName}" must be final and have no setter.',
          field,
        );
      }
      _validateEventType(field.type, field);
    }
    final component = annotated.annotation.peek('componentId')?.objectValue;
    final componentId = component?.getField('value')?.toStringValue();
    if (componentId != null) {
      _validateEventId(componentId, 'Component ID', element);
    }
    final id = annotated.annotation.read('id').stringValue;
    _validateEventId(id, 'Event ID', element);
    if (!ids.add(id)) {
      _failEvent('Duplicate Event ID "$id" in this library.', element);
    }
    final description = annotated.annotation.read('description').stringValue;
    if (description.length > _eventMaxDescriptionLength) {
      _failEvent(
        'Event "$id" description exceeds $_eventMaxDescriptionLength characters.',
        element,
      );
    }
    contracts.add(
      _EventContractModel(
        element: element,
        componentId: componentId,
        id: id,
        description: description,
      ),
    );
  }
  contracts.sort((left, right) => left.id.compareTo(right.id));
  return contracts;
}

/// Reads and validates every static Event Subscription in one source library.
List<_EventSubscriptionModel> _readEventSubscriptions(LibraryReader library) {
  final subscriptions = <_EventSubscriptionModel>[];
  final explicitIds = <String>{};
  for (final annotated in library.annotatedWith(_eventSubscriptionChecker)) {
    final element = annotated.element;
    if (element is! TopLevelFunctionElement ||
        element.displayName.startsWith('_') ||
        element.typeParameters.isNotEmpty) {
      _failEvent(
        'CCEventSubscription requires a public, top-level, non-generic function.',
        element,
      );
    }
    final parameters = element.formalParameters;
    if (parameters.isEmpty || parameters.length > 2) {
      _failEvent(
        'CCEventSubscription accepts (Event) or (Event, CCInvocationContext).',
        element,
      );
    }
    final eventType = parameters.first.type;
    if (eventType is! InterfaceType || eventType.element is! ClassElement) {
      _failEvent(
        'The first Subscription parameter must be an Event class.',
        element,
      );
    }
    final contract = _readEventContract(eventType.element as ClassElement);
    if (parameters.length == 2) {
      final context = parameters[1].type.element;
      if (context?.displayName != 'CCInvocationContext' ||
          context?.library?.uri.toString() !=
              'package:ccrouter_contracts/src/invocation.dart') {
        _failEvent(
          'The second Subscription parameter must be CCInvocationContext.',
          parameters[1],
        );
      }
    }
    if (!_eventVoidResult(element.returnType)) {
      _failEvent(
        'Event Subscription must return void, Future<void>, or FutureOr<void>.',
        element,
      );
    }
    final idReader = annotated.annotation.peek('id');
    final subscriberId = idReader == null || idReader.isNull
        ? null
        : idReader.stringValue;
    if (subscriberId != null) {
      _validateEventId(subscriberId, 'Subscriber ID', element);
      if (!explicitIds.add(subscriberId)) {
        _failEvent(
          'Duplicate Subscriber ID "$subscriberId" in this library.',
          element,
        );
      }
    }
    subscriptions.add(
      _EventSubscriptionModel(
        element: element,
        contract: contract,
        subscriberId: subscriberId,
      ),
    );
  }
  subscriptions.sort((left, right) {
    final event = left.contract.id.compareTo(right.contract.id);
    return event != 0
        ? event
        : left.element.displayName.compareTo(right.element.displayName);
  });
  return subscriptions;
}

/// Reads one imported Event Contract annotation.
_EventContractModel _readEventContract(ClassElement element) {
  final annotation = _eventContractChecker.firstAnnotationOfExact(element);
  if (annotation == null) {
    _failEvent(
      'CCEventSubscription parameter ${element.displayName} must be annotated with CCEventContract.',
      element,
    );
  }
  if (!_eventChecker.isAssignableFromType(element.thisType)) {
    _failEvent('${element.displayName} must implement CCEvent.', element);
  }
  final id = annotation.getField('id')?.toStringValue();
  if (id == null) _failEvent('CCEventContract requires a const id.', element);
  return _EventContractModel(
    element: element,
    componentId: annotation
        .getField('componentId')
        ?.getField('value')
        ?.toStringValue(),
    id: id,
    description: annotation.getField('description')?.toStringValue() ?? '',
  );
}

/// Validates one Event payload type recursively.
void _validateEventType(DartType type, Element owner) {
  if (type is DynamicType ||
      type is FunctionType ||
      type is TypeParameterType) {
    _failEvent(
      'Event payload types must be concrete and callback-free.',
      owner,
    );
  }
  if (type is InterfaceType) {
    final element = type.element;
    if (element.displayName.startsWith('_')) {
      _failEvent('Event payload types must be public.', owner);
    }
    final uri = element.library.uri;
    if (uri.scheme == 'package' && uri.path.startsWith('flutter/')) {
      _failEvent('Event payload types must not depend on Flutter.', owner);
    }
    if (element.displayName == 'Stream' && uri.toString() == 'dart:async') {
      _failEvent('Event payload types must not contain Stream.', owner);
    }
    for (final argument in type.typeArguments) {
      _validateEventType(argument, owner);
    }
    return;
  }
  if (type is RecordType) {
    for (final field in [...type.positionalFields, ...type.namedFields]) {
      _validateEventType(field.type, owner);
    }
    return;
  }
  _failEvent(
    'Unsupported Event payload type ${type.getDisplayString()}.',
    owner,
  );
}

/// Whether one Subscription result has no business value.
bool _eventVoidResult(DartType type) {
  if (type is VoidType) return true;
  if (type is! InterfaceType || type.typeArguments.length != 1) return false;
  final uri = type.element.library.uri.toString();
  return uri == 'dart:async' &&
      (type.element.displayName == 'Future' ||
          type.element.displayName == 'FutureOr') &&
      type.typeArguments.single is VoidType;
}

/// Rejects raw facade publication for a statically annotated Event.
Future<void> _validateGeneratedEventUsage(
  LibraryElement library,
  BuildStep buildStep,
) async {
  for (final fragment in library.fragments) {
    final node = await buildStep.resolver.astNodeFor(fragment, resolve: true);
    if (node == null) continue;
    node.accept(_RawEventInvocationVisitor());
  }
}

/// Finds resolved `CCRouter.event(annotatedEvent)` calls.
final class _RawEventInvocationVisitor extends RecursiveAstVisitor<void> {
  @override
  void visitMethodInvocation(MethodInvocation node) {
    super.visitMethodInvocation(node);
    if (node.methodName.name != 'event' ||
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
    if (_eventContractChecker.firstAnnotationOfExact(type.element) == null) {
      return;
    }
    _failEvent(
      'Annotated Event ${type.element.displayName} must use its generated owner '
      'Client instead of CCRouter.event so Event ID and publisher identity '
      'cannot be bypassed.',
      type.element,
    );
  }
}

/// Validates one stable Event, Subscriber, or component identity.
void _validateEventId(String value, String kind, Element owner) {
  if (value.length > _eventMaxStableIdLength ||
      !_eventStableIdPattern.hasMatch(value)) {
    _failEvent('$kind "$value" is invalid.', owner);
  }
}

/// Reports one source-attached Event generation failure.
Never _failEvent(String message, Element element) =>
    throw InvalidGenerationSourceError(message, element: element);

/// Converts one package-relative source path into a Package URI.
String _eventPackageUri(String package, String source) =>
    'package:$package/${source.substring('lib/'.length)}';

/// Derives the generated Subscriber registration library path.
String _eventGeneratedLibraryPath(String source) {
  final relative = source.substring('lib/src/'.length, source.length - 5);
  return 'lib/src/ccrouter_generated/event/$relative.event.g.dart';
}

/// Serializes a portable Package URI and exact source coordinates.
Map<String, Object?> _eventSourceReference(Element element) {
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
