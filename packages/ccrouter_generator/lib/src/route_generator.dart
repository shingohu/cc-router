import 'dart:convert';

import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

part 'route_model.dart';
part 'route_emitter.dart';
part 'component_metadata_builder.dart';
part 'route_metadata_builder.dart';

/// Creates the internal generator for the build-runner factory only.
///
/// Kept out of the package barrel; business code consumes generated Intents,
/// not analyzer elements or generation services.
Generator ccRouteGenerator() => _RouteGenerator();

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

  /// Generates private implementation and deliberately exported contracts.
  @override
  String generate(LibraryReader library, BuildStep buildStep) {
    if (buildStep.inputId.path.contains('/ccrouter_generated/')) return '';
    final routes = <_RouteModel>[];
    final ids = <String>{};
    final names = library.allElements
        .where(
          (element) => !element.firstFragment.libraryFragment!.source.uri.path
              .endsWith('.route.g.dart'),
        )
        .map((element) => element.displayName)
        .toSet();
    for (final annotated in library.annotatedWith(_route)) {
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
    return routes.map(_emitRoute).join('\n');
  }
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
      ['hostId', 'parentRouteId', 'shellId', 'navigatorOutlet', 'routeKind'],
    ),
    _ => throw StateError('Unsupported route metadata: $name'),
  };
  return 'const $name(${[...positional.map((field) => _constant(_field(value, field))), ...named.map((field) => '$field: ${_constant(_field(value, field))}')].join(', ')})';
}
