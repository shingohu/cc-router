part of 'route_generator.dart';

/// Generates standalone Pure Dart contracts from Contract-first schemas.
final class _RouteContractGenerator extends Generator {
  /// Matches abstract Contract-first schemas in Pure Dart packages.
  static const _contract = TypeChecker.typeNamedLiterally(
    'CCRouteContract',
    inPackage: 'ccrouter_contracts',
  );

  /// Emits no library when the input has no public route-contract schema.
  @override
  String generate(LibraryReader library, BuildStep buildStep) {
    if (buildStep.inputId.path.contains('/ccrouter_generated/')) return '';
    final routes = _readContractModels(library);
    if (routes.isEmpty) return '';
    final imports = _ContractImportPlan(routes);
    final out = StringBuffer()
      ..writeln("import 'package:ccrouter_contracts/ccrouter_contracts.dart';");
    for (final entry in imports.imports.entries) {
      out.writeln("import '${entry.key}' as ${entry.value};");
    }
    out.writeln();
    for (final route in routes) {
      out.writeln(_emitPublicRouteContract(route, imports));
    }
    return out.toString();
  }
}

/// Reads Contract-first schemas and validates generated declaration collisions.
List<_RouteModel> _readContractModels(LibraryReader library) {
  final contracts = <_RouteModel>[];
  final ids = <String>{};
  final names = library.allElements
      .map((element) => element.displayName)
      .toSet();
  for (final annotated in library.annotatedWith(
    _RouteContractGenerator._contract,
  )) {
    final model = _RouteModel.read(
      annotated.element,
      annotated.annotation,
      contractFirst: true,
    );
    if (!ids.add(model.id)) {
      _fail(
        'Duplicate route contract ID "${model.id}" in this library.',
        annotated.element,
      );
    }
    for (final name in [
      model.api,
      model.arguments,
      model.codec,
      model.intent,
    ]) {
      if (!names.add(name)) {
        _fail(
          'Generated declaration "$name" collides with another declaration.',
          annotated.element,
        );
      }
    }
    contracts.add(model);
  }
  return contracts;
}

/// Plans deterministic imports and type names for a standalone contract file.
final class _ContractImportPlan {
  /// Public Pure Dart framework contract library already imported unprefixed.
  static const _frameworkContracts =
      'package:ccrouter_contracts/ccrouter_contracts.dart';

  /// Validates contract-facing types and assigns stable import aliases.
  _ContractImportPlan(List<_RouteModel> routes)
    : _sourceLibrary = routes.first.page.library {
    final uris = <Uri>{};
    for (final route in routes) {
      _collectType(route.resultType, route.page, uris);
      for (final parameter in route.parameters) {
        _collectType(parameter.element.type, parameter.element, uris);
        if (parameter.defaultCode != null) {
          _renderDefault(parameter, aliases: const {});
        }
      }
    }
    final sorted = uris.toList()
      ..sort((left, right) => left.toString().compareTo(right.toString()));
    _aliases = {
      for (final entry in sorted.indexed)
        entry.$2.toString(): 'contract_type_${entry.$1}',
    };
  }

  /// Source library from which the standalone contract is derived.
  final LibraryElement _sourceLibrary;

  /// Import URI to generated alias, ordered deterministically by URI.
  late final Map<String, String> _aliases;

  /// Contract-facing elements mapped to the public imports used by the page.
  final Map<Element, Uri> _elementImports = {};

  /// External Pure Dart imports required by parameter and result types.
  Map<String, String> get imports => Map.unmodifiable(_aliases);

  /// Renders a constructor parameter type in the contract namespace.
  String parameterType(_ParameterModel parameter) =>
      typeSource(parameter.element.type, parameter.element);

  /// Renders a portable evaluated constructor default in the contract library.
  String? parameterDefault(_ParameterModel parameter) {
    if (parameter.defaultCode == null) return null;
    return _renderDefault(parameter, aliases: _aliases);
  }

  /// Renders a validated type with deterministic external import prefixes.
  String typeSource(DartType type, Element owner) {
    if (type is VoidType) return 'void';
    if (type is NeverType) return 'Never${_nullability(type)}';
    if (type is! InterfaceType) {
      _fail(
        'Public route contracts support interface and void result types; '
        'move complex contract types to a public Pure Dart library.',
        owner,
      );
    }
    final alias = type.alias;
    final element = alias?.element ?? type.element;
    final arguments = alias?.typeArguments ?? type.typeArguments;
    final definitionUri = element.library.uri;
    final importUri = _elementImports[element];
    final prefix =
        definitionUri.toString() == 'dart:core' ||
            importUri.toString() == _frameworkContracts
        ? ''
        : '${_aliases[importUri.toString()]!}.';
    final generics = arguments.isEmpty
        ? ''
        : '<${arguments.map((argument) => typeSource(argument, owner)).join(', ')}>';
    return '$prefix${element.displayName}$generics${_nullability(type)}';
  }

  /// Collects importable public types and rejects implementation dependencies.
  void _collectType(DartType type, Element owner, Set<Uri> imports) {
    if (type is VoidType || type is NeverType) return;
    if (type is! InterfaceType) {
      _fail(
        'Public route contracts cannot expose function, record, dynamic, or '
        'type-parameter values.',
        owner,
      );
    }
    final alias = type.alias;
    final element = alias?.element ?? type.element;
    final arguments = alias?.typeArguments ?? type.typeArguments;
    final definitionUri = element.library.uri;
    if (element.displayName.startsWith('_')) {
      _fail(
        'Public route contract type "${element.displayName}" must be public.',
        owner,
      );
    }
    if (element.library == _sourceLibrary) {
      _fail(
        'Public route contract type "${element.displayName}" cannot be '
        'declared beside the route source; move it to a public Pure Dart model '
        'library imported by the contract declaration.',
        owner,
      );
    }
    if (definitionUri.toString() == 'dart:core') {
      for (final argument in arguments) {
        _collectType(argument, owner, imports);
      }
      return;
    }
    final importUri = _publicImportUri(element, owner);
    if (importUri.toString() == 'dart:ui' ||
        importUri.toString().startsWith('package:flutter/') ||
        importUri.toString().startsWith('package:go_router/') ||
        importUri.toString().startsWith('package:ccrouter/')) {
      _fail(
        'Public route contracts cannot depend on Flutter, dart:ui, or a '
        'navigation backend.',
        owner,
      );
    }
    if (importUri.scheme == 'package' &&
        importUri.pathSegments.length > 1 &&
        importUri.pathSegments[1] == 'src') {
      _fail(
        'Public route contract type "${element.displayName}" must come from '
        'a public package library rather than package:*/src/.',
        owner,
      );
    }
    if (importUri.scheme != 'dart' && importUri.scheme != 'package') {
      _fail(
        'Public route contract type "${element.displayName}" must be '
        'available through a dart: or package: library.',
        owner,
      );
    }
    _elementImports[element] = importUri;
    if (importUri.toString() != _frameworkContracts) imports.add(importUri);
    for (final argument in arguments) {
      _collectType(argument, owner, imports);
    }
  }

  /// Finds the explicit public import through which the page accesses [element].
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
      if (_isPublicPureImport(candidate)) return candidate;
    }
    if (ordered.isNotEmpty) return ordered.first;
    _fail(
      'Public route contract type "$name" must be accessible through an '
      'explicit public import in the route source library.',
      owner,
    );
  }

  /// Whether an import URI can safely appear in a public Pure Dart contract.
  static bool _isPublicPureImport(Uri uri) {
    if (uri.scheme != 'dart' && uri.scheme != 'package') return false;
    if (uri.toString() == 'dart:ui' ||
        uri.toString().startsWith('package:flutter/') ||
        uri.toString().startsWith('package:go_router/') ||
        uri.toString().startsWith('package:ccrouter/')) {
      return false;
    }
    return uri.scheme != 'package' ||
        uri.pathSegments.length < 2 ||
        uri.pathSegments[1] != 'src';
  }

  /// Serializes defaults without copying source-library expressions.
  String _renderDefault(
    _ParameterModel parameter, {
    required Map<String, String> aliases,
  }) {
    final value = parameter.element.computeConstantValue();
    if (value == null) {
      _fail(
        'Public route contract default for "${parameter.name}" must be a '
        'compile-time constant.',
        parameter.element,
      );
    }
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
    final type = value.type;
    if (type is InterfaceType && type.element is EnumElement) {
      final enumElement = type.element as EnumElement;
      final index = _field(value, 'index').toIntValue()!;
      final field = enumElement.fields
          .where((candidate) => candidate.isEnumConstant)
          .elementAt(index);
      if (aliases.isEmpty &&
          enumElement.library.uri.toString() != 'dart:core') {
        return field.displayName;
      }
      return '${typeSource(type, parameter.element)}.${field.displayName}';
    }
    _fail(
      'Public route contract default for "${parameter.name}" must be a '
      'primitive or enum constant.',
      parameter.element,
    );
  }

  /// Converts analyzer nullability into valid contract source syntax.
  static String _nullability(DartType type) =>
      type.nullabilitySuffix == NullabilitySuffix.question ? '?' : '';
}
