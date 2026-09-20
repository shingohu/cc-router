import 'dart:convert';

import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

part 'route_model.dart';
part 'route_emitter.dart';
part 'route_contract_generator.dart';
part 'component_generator.dart';
part 'component_metadata_builder.dart';
part 'route_metadata_builder.dart';

/// Maximum length of a stable framework identifier.
const int _maxStableIdLength = 128;

/// Maximum accepted length of a full route regular expression.
const int _maxRouteRegexLength = 2048;

/// Maximum accepted number of named captures in one route expression.
const int _maxRouteRegexCaptures = 32;

/// Maximum accepted length of a path-parameter constraint expression.
const int _maxConstraintRegexLength = 256;

/// Maximum description length retained in generated catalogs.
const int _maxRouteDescriptionLength = 4096;

/// Stable identifier syntax shared by generated navigation metadata.
final RegExp _stableIdPattern = RegExp(
  r'^[a-z][A-Za-z0-9]*(?:[._-][A-Za-z0-9]+)*$',
);

/// Lowercase package-style syntax retained for component ownership IDs.
final RegExp _componentIdPattern = RegExp(
  r'^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*$',
);

/// Full SemVer 2.0 syntax used by component contract versions.
final RegExp _semanticVersionPattern = RegExp(
  r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)'
  r'(?:-(?:0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*)'
  r'(?:\.(?:0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*))*)?'
  r'(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$',
);

/// Validates a generated identifier without publishing a framework utility.
void _validateStableId(String value, String kind, Element element) {
  if (value.length > _maxStableIdLength || !_stableIdPattern.hasMatch(value)) {
    _fail(
      '$kind "$value" is invalid; start with lowercase and use alphanumeric segments '
      'separated by ".", "_", or "-" (maximum $_maxStableIdLength characters).',
      element,
    );
  }
}

/// Validates one component ID against its stricter package-style syntax.
void _validateComponentId(String value, Element element) {
  if (value.length > _maxStableIdLength ||
      !_componentIdPattern.hasMatch(value)) {
    _fail(
      'Component ID "$value" is invalid; use lowercase alphanumeric segments '
      'separated by ".", "_", or "-" (maximum $_maxStableIdLength characters).',
      element,
    );
  }
}

/// Creates the internal generator for the build-runner factory only.
///
/// Kept out of the package barrel; business code consumes generated Intents,
/// not analyzer elements or generation services.
Generator ccRouteGenerator() => _RouteGenerator();

/// Creates the standalone Pure Dart route-contract generator.
///
/// Only explicit `CCRouteContract` schemas emit output; page-level `CCRoute`
/// declarations remain library-private and never create a public contract.
Generator ccRouteContractGenerator() => _RouteContractGenerator();

/// Creates the internal component Manifest generator for build-runner.
///
/// Keeping the implementation in this library lets route and component
/// generation share descriptor validation without exposing analyzer objects.
Generator ccComponentGenerator() => _ComponentGenerator();

/// Creates the metadata Builder while keeping its implementation private.
Builder ccRouteMetadataBuilderInternal() => _RouteMetadataBuilder();

/// Creates the component metadata Builder while keeping its implementation private.
Builder ccComponentMetadataBuilderInternal() => _ComponentMetadataBuilder();

/// Finds route declarations and validates a complete library before emitting.
final class _RouteGenerator extends Generator {
  /// Matches only CCRouter's annotation, not unrelated same-named classes.
  static const _route = TypeChecker.typeNamedLiterally(
    'CCRoute',
    inPackage: 'ccrouter_contracts',
  );

  /// Matches page bindings to Contract-first declarations.
  static const _implementation = TypeChecker.typeNamedLiterally(
    'CCRouteImplementation',
    inPackage: 'ccrouter_contracts',
  );

  /// Generates private implementation and deliberately exported contracts.
  @override
  String generate(LibraryReader library, BuildStep buildStep) {
    if (buildStep.inputId.path.contains('/ccrouter_generated/')) return '';
    return [
      ..._readRouteModels(library).map(_emitRoute),
      ..._readRouteImplementationModels(library).map(_emitImplementationGlue),
    ].join('\n');
  }
}

/// Reads and collision-checks every route declared by one source library.
List<_RouteModel> _readRouteModels(LibraryReader library) {
  final routes = <_RouteModel>[];
  final ids = <String>{};
  final names = library.allElements
      .where(
        (element) => !element.firstFragment.libraryFragment!.source.uri.path
            .endsWith('.route.g.dart'),
      )
      .map((element) => element.displayName)
      .toSet();
  for (final annotated in library.annotatedWith(_RouteGenerator._route)) {
    final model = _RouteModel.read(annotated.element, annotated.annotation);
    if (!ids.add(model.id)) {
      _fail(
        'Duplicate route ID "${model.id}" in this library.',
        annotated.element,
      );
    }
    for (final name in [
      model.api,
      model.arguments,
      model.codec,
      model.intent,
      model.registrationFunction,
      model.descriptorFunction,
      model.builderFunction,
    ]) {
      if (!names.add(name)) {
        _fail(
          'Generated declaration "$name" collides with another declaration.',
          annotated.element,
        );
      }
    }
    routes.add(model);
  }
  return routes;
}

/// Reads and collision-checks Contract-first page bindings in one library.
List<_RouteImplementationModel> _readRouteImplementationModels(
  LibraryReader library,
) {
  final implementations = <_RouteImplementationModel>[];
  final routeIds = <String>{};
  final names = library.allElements
      .where(
        (element) => !element.firstFragment.libraryFragment!.source.uri.path
            .endsWith('.route.g.dart'),
      )
      .map((element) => element.displayName)
      .toSet();
  for (final annotated in library.annotatedWith(
    _RouteGenerator._implementation,
  )) {
    final model = _RouteImplementationModel.read(
      annotated.element,
      annotated.annotation,
    );
    if (!routeIds.add(model.contract.id)) {
      _fail(
        'Route "${model.contract.id}" is implemented more than once in this library.',
        annotated.element,
      );
    }
    for (final name in [
      model.registrationFunction,
      model.descriptorFunction,
      model.builderFunction,
    ]) {
      if (!names.add(name)) {
        _fail(
          'Generated declaration "$name" collides with another declaration.',
          annotated.element,
        );
      }
    }
    implementations.add(model);
  }
  return implementations;
}

/// Reports a compile-time declaration error at the owning source element.
Never _fail(String message, Element element) =>
    throw InvalidGenerationSourceError(message, element: element);

/// Quotes metadata as Dart literals without enabling string interpolation.
String _quote(String value) => jsonEncode(value).replaceAll(r'$', r'\$');

/// Preserves imported type prefixes and generic arguments in the page library.
String _typeSource(DartType type, LibraryElement library) {
  if (type is! InterfaceType) return type.getDisplayString();
  final alias = type.alias;
  final element = alias?.element ?? type.element;
  var name = element.displayName;
  if (element.library != library &&
      element.library.uri.toString() != 'dart:core') {
    String? importedName;
    for (final fragment in library.fragments) {
      for (final directive in fragment.libraryImports) {
        final prefix = directive.prefix?.element.displayName;
        if (directive.namespace.get2(name) == element ||
            (prefix != null &&
                directive.namespace.getPrefixed2(prefix, name) == element)) {
          importedName = prefix == null ? name : '$prefix.$name';
          break;
        }
      }
      if (importedName != null) break;
    }
    if (importedName == null) {
      _fail(
        'Route type "$name" must be accessible through a page-library import.',
        element,
      );
    }
    name = importedName;
  }
  final arguments = alias?.typeArguments ?? type.typeArguments;
  return '$name${arguments.isEmpty ? '' : '<${arguments.map((argument) => _typeSource(argument, library)).join(', ')}>'}${type.nullabilitySuffix == NullabilitySuffix.question ? '?' : ''}';
}

/// Reads inherited const fields through analyzer's explicit superclass object.
DartObject _field(DartObject value, String name) {
  final direct = value.getField(name);
  if (direct != null) return direct;
  final parent = value.getField('(super)');
  if (parent != null) return _field(parent, name);
  throw StateError('Missing route metadata field: $name');
}

/// Reads enum names from evaluated constants instead of annotation source text.
String _enumValue(DartObject value) {
  final type = value.type as InterfaceType;
  final index = _field(value, 'index').toIntValue()!;
  final fields = type.element.fields
      .where((field) => field.isEnumConstant)
      .toList();
  return '${type.element.displayName}.${fields[index].displayName}';
}

/// Converts a component ID into its stable generated Manifest symbol.
String _componentManifestName(String componentId) {
  final parts = componentId
      .split(RegExp(r'[^A-Za-z0-9]+'))
      .where((part) => part.isNotEmpty)
      .toList();
  final first = parts.first;
  final stem =
      '${first[0].toLowerCase()}${first.substring(1)}${parts.skip(1).map((part) => '${part[0].toUpperCase()}${part.substring(1)}').join()}';
  return '${stem}Manifest';
}

/// Derives the standalone contract output for one `lib/src` route source.
String _routeContractOutputPath(String sourcePath) {
  const prefix = 'lib/src/';
  if (!sourcePath.startsWith(prefix) || !sourcePath.endsWith('.dart')) {
    throw StateError('Route source must be a Dart library below lib/src/.');
  }
  final relative = sourcePath.substring(prefix.length);
  final stem = relative.substring(0, relative.length - '.dart'.length);
  return 'lib/src/ccrouter_generated/$stem.route.contract.g.dart';
}

/// Derives the same-library route Part output for one `lib/src` source.
///
/// Source catalogs use this path to locate generated owner glue without
/// parsing build-runner output or duplicating its path convention elsewhere.
String _routePartOutputPath(String sourcePath) {
  const prefix = 'lib/src/';
  if (!sourcePath.startsWith(prefix) || !sourcePath.endsWith('.dart')) {
    throw StateError('Route source must be a Dart library below lib/src/.');
  }
  final relative = sourcePath.substring(prefix.length);
  final stem = relative.substring(0, relative.length - '.dart'.length);
  return 'lib/src/ccrouter_generated/$stem.route.g.dart';
}

/// Serializes the closed set of declarative route metadata into const source.
///
/// Only evaluated structured constants are accepted; no annotation string is
/// ever interpreted as arbitrary source code.
String _constant(DartObject value) {
  if (value.isNull) return 'null';
  if (value.toStringValue() case final String text) return _quote(text);
  if (value.toBoolValue() case final bool flag) return '$flag';
  if (value.toIntValue() case final int number) return '$number';
  if (value.toListValue() case final List<DartObject> list) {
    return 'const [${list.map(_constant).join(', ')}]';
  }
  if (value.toSetValue() case final Set<DartObject> set) {
    return 'const <String>{${set.map(_constant).join(', ')}}';
  }
  if (value.toMapValue() case final Map<DartObject?, DartObject?> map) {
    return 'const <String, String>{${map.entries.map((entry) => '${_constant(entry.key!)}: ${_constant(entry.value!)}').join(', ')}}';
  }
  final type = value.type as InterfaceType;
  if (type.element is EnumElement) return _enumValue(value);
  final name = type.element.displayName;
  final (positional, named) = switch (name) {
    'CCPathPattern' ||
    'CCUriPattern' => (['template'], ['primary', 'constraints']),
    'CCRegexPattern' => (['expression'], <String>[]),
    'CCPagePresentation' => (
      <String>[],
      ['routeType', 'transition', 'opaque', 'fullscreenDialog'],
    ),
    'CCModalBottomSheetPresentation' => (
      <String>[],
      [
        'isDismissible',
        'enableDrag',
        'isScrollControlled',
        'showDragHandle',
        'useSafeArea',
      ],
    ),
    'CCDialogPresentation' => (
      <String>[],
      ['routeType', 'barrierDismissible', 'useSafeArea'],
    ),
    'CCRoutePlacement' => (
      <String>[],
      ['hostId', 'parentRouteId', 'shellId', 'navigatorOutlet'],
    ),
    _ => throw StateError('Unsupported route metadata: $name'),
  };
  return 'const $name(${[...positional.map((field) => _constant(_field(value, field))), ...named.map((field) => '$field: ${_constant(_field(value, field))}')].join(', ')})';
}
