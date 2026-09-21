part of 'route_generator.dart';

/// Emits one self-contained route library without requiring a page-side part.
String _emitStandaloneRouteLibrary(
  LibraryReader library,
  BuildStep buildStep,
  List<_RouteModel> routes,
) {
  final imports = _StandaloneRouteImportPlan(
    library.element,
    buildStep.inputId,
    routes,
  );
  final out = StringBuffer()
    ..writeln("import 'package:ccrouter/ccrouter.dart';");
  for (final entry in imports.imports.entries) {
    out.writeln("import '${entry.key}' as ${entry.value};");
  }
  out.writeln();
  for (final route in routes) {
    out
      ..writeln(
        _emitStandaloneRoute(
          route,
          parameterType: imports.parameterType,
          typeSource: imports.typeSource,
          parameterDefault: imports.parameterDefault,
        ),
      )
      ..writeln();
  }
  return out.toString();
}

/// Plans deterministic imports, types, and constants for a route library.
final class _StandaloneRouteImportPlan {
  /// Collects every type required by generated signatures and codecs.
  _StandaloneRouteImportPlan(
    this._sourceLibrary,
    AssetId input,
    List<_RouteModel> routes,
  ) : sourceUri = _sourcePackageUri(input) {
    final uris = <Uri>{};
    for (final route in routes) {
      _collectType(route.resultType, route.page, uris);
      for (final parameter in route.parameters) {
        _collectType(parameter.element.type, parameter.element, uris);
        if (parameter.queryCodecType case final codec?) {
          _collectType(codec, parameter.element, uris);
        }
      }
    }
    final sorted = uris.toList()
      ..sort((left, right) => left.toString().compareTo(right.toString()));
    _aliases = {
      for (final entry in sorted.indexed)
        entry.$2.toString(): entry.$2.toString() == sourceUri
            ? 'route_source'
            : 'route_type_${entry.$1}',
    };
  }

  /// Analyzer library containing the annotated page declarations.
  final LibraryElement _sourceLibrary;

  /// Package URI used to import the page library from generated code.
  final String sourceUri;

  /// Type definitions mapped to the import through which they are accessible.
  final Map<Element, Uri> _elementImports = {};

  /// Import URI to deterministic generated prefix.
  late final Map<String, String> _aliases;

  /// External imports required after the framework and page libraries.
  Map<String, String> get imports => Map.unmodifiable(_aliases);

  /// Renders one route parameter type in the generated library namespace.
  String parameterType(_ParameterModel parameter) =>
      typeSource(parameter.element.type, parameter.element);

  /// Renders a compile-time default without copying unresolved source text.
  String? parameterDefault(_ParameterModel parameter) {
    if (parameter.defaultCode == null) return null;
    final value = parameter.element.computeConstantValue();
    if (value == null) {
      _fail(
        'Route default for "${parameter.name}" must be a compile-time constant.',
        parameter.element,
      );
    }
    return _renderConstant(value, parameter.element);
  }

  /// Renders one supported analyzer type using stable import prefixes.
  String typeSource(DartType type, Element owner) {
    if (type is VoidType) return 'void';
    if (type is NeverType) return 'Never${_nullability(type)}';
    if (type is! InterfaceType) {
      _fail(
        'Generated routes support interface, void, and Never types only.',
        owner,
      );
    }
    final alias = type.alias;
    final element = alias?.element ?? type.element;
    final arguments = alias?.typeArguments ?? type.typeArguments;
    final definitionUri = element.library.uri;
    final importUri = _elementImports[element];
    final prefix =
        definitionUri.toString() == 'dart:core' || _isFrameworkUri(importUri)
        ? ''
        : '${_aliases[importUri.toString()]!}.';
    final generics = arguments.isEmpty
        ? ''
        : '<${arguments.map((argument) => typeSource(argument, owner)).join(', ')}>';
    return '$prefix${element.displayName}$generics${_nullability(type)}';
  }

  /// Collects one public type and every nested generic argument.
  void _collectType(DartType type, Element owner, Set<Uri> imports) {
    if (type is VoidType || type is NeverType) return;
    if (type is! InterfaceType) {
      _fail(
        'Generated routes cannot expose function, record, dynamic, or '
        'type-parameter values.',
        owner,
      );
    }
    final alias = type.alias;
    final element = alias?.element ?? type.element;
    final arguments = alias?.typeArguments ?? type.typeArguments;
    if (element.displayName.startsWith('_')) {
      _fail(
        'Route type "${element.displayName}" must be public because the route '
        'contract is generated in a standalone library.',
        owner,
      );
    }
    final definitionUri = element.library.uri;
    if (definitionUri.toString() == 'dart:core') {
      for (final argument in arguments) {
        _collectType(argument, owner, imports);
      }
      return;
    }
    final importUri = element.library == _sourceLibrary
        ? Uri.parse(sourceUri)
        : _visibleImportUri(element) ?? definitionUri;
    _elementImports[element] = importUri;
    if (!_isFrameworkUri(importUri)) {
      if (importUri.scheme != 'dart' && importUri.scheme != 'package') {
        _fail(
          'Route type "${element.displayName}" must be available through a '
          'dart: or package: import.',
          owner,
        );
      }
      imports.add(importUri);
    }
    for (final argument in arguments) {
      _collectType(argument, owner, imports);
    }
  }

  /// Finds the source import that exposes an external declaration.
  Uri? _visibleImportUri(Element element) {
    final candidates = <Uri>{};
    for (final fragment in _sourceLibrary.fragments) {
      for (final directive in fragment.libraryImports) {
        final prefix = directive.prefix?.element.displayName;
        final visible =
            directive.namespace.get2(element.displayName) == element ||
            (prefix != null &&
                directive.namespace.getPrefixed2(prefix, element.displayName) ==
                    element);
        final imported = directive.importedLibrary;
        if (visible && imported != null) candidates.add(imported.uri);
      }
    }
    final sorted = candidates.toList()
      ..sort((left, right) => left.toString().compareTo(right.toString()));
    for (final candidate in sorted) {
      if (!_isPrivatePackageLibrary(candidate)) return candidate;
    }
    return sorted.firstOrNull;
  }

  /// Serializes the supported constant subset used by constructor defaults.
  String _renderConstant(DartObject value, Element owner) {
    if (value.isNull) return 'null';
    if (value.toStringValue() case final String text) return _quote(text);
    if (value.toBoolValue() case final bool flag) return '$flag';
    if (value.toIntValue() case final int number) return '$number';
    if (value.toDoubleValue() case final double number) {
      if (number.isNaN) return 'double.nan';
      if (number == double.infinity) return 'double.infinity';
      if (number == double.negativeInfinity) return 'double.negativeInfinity';
      return '$number';
    }
    if (value.toListValue() case final values?) {
      return 'const [${values.map((item) => _renderConstant(item, owner)).join(', ')}]';
    }
    if (value.toSetValue() case final values?) {
      return 'const {${values.map((item) => _renderConstant(item, owner)).join(', ')}}';
    }
    if (value.toMapValue() case final values?) {
      return 'const {${values.entries.map((entry) => '${_renderConstant(entry.key!, owner)}: ${_renderConstant(entry.value!, owner)}').join(', ')}}';
    }
    final type = value.type;
    if (type is InterfaceType && type.element is EnumElement) {
      final fields = type.element.fields
          .where((field) => field.isEnumConstant)
          .toList(growable: false);
      final index = _field(value, 'index').toIntValue()!;
      return '${typeSource(type, owner)}.${fields[index].displayName}';
    }
    _fail(
      'Route default values support primitives, enums, List, Set, and Map '
      'constants only.',
      owner,
    );
  }

  /// Whether one URI is already exported by the unprefixed framework import.
  static bool _isFrameworkUri(Uri? uri) {
    final value = uri?.toString() ?? '';
    return value.startsWith('package:ccrouter/') ||
        value.startsWith('package:ccrouter_contracts/');
  }

  /// Whether a Package URI points at an implementation-only `src` library.
  static bool _isPrivatePackageLibrary(Uri uri) =>
      uri.scheme == 'package' &&
      uri.pathSegments.length > 1 &&
      uri.pathSegments[1] == 'src';

  /// Converts analyzer nullability into generated source syntax.
  static String _nullability(DartType type) =>
      type.nullabilitySuffix == NullabilitySuffix.question ? '?' : '';
}

/// Converts a `lib/` Builder input into its stable Package URI.
String _sourcePackageUri(AssetId input) {
  if (!input.path.startsWith('lib/')) {
    throw StateError('Route sources must be Dart libraries below lib/.');
  }
  return 'package:${input.package}/${input.path.substring('lib/'.length)}';
}

/// Locates the standalone contract generated beside a Contract-first schema.
Uri _generatedContractUri(Element contract) {
  final uri = contract.library!.uri;
  if (uri.scheme != 'package' || uri.pathSegments.length < 3) {
    _fail(
      'CCRouteContract schemas must be declared below lib/src/ so their '
      'generated contract library has a stable Package URI.',
      contract,
    );
  }
  final segments = uri.pathSegments;
  if (segments[1] != 'src' || !segments.last.endsWith('.dart')) {
    _fail('CCRouteContract schemas must be declared below lib/src/.', contract);
  }
  final file = segments.last;
  final generated =
      '${file.substring(0, file.length - 5)}.route.contract.g.dart';
  return uri.replace(
    pathSegments: [
      segments.first,
      'src',
      'ccrouter_generated',
      'contract',
      ...segments.skip(2).take(segments.length - 3),
      generated,
    ],
  );
}
