import 'dart:convert';

import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:dart_style/dart_style.dart';
import 'package:source_gen/source_gen.dart';

import 'contract_fingerprint.dart';
import 'generated_client_naming.dart';

/// Creates the opt-in UI source or metadata builder; old libraries emit nothing.
Builder createUIFragmentBuilder({required bool metadata}) =>
    _UIFragmentBuilder(metadata);

/// Exact framework identity checks prevent foreign same-name annotations.
TypeChecker _checker(String name) =>
    TypeChecker.typeNamedLiterally(name, inPackage: 'ccrouter_contracts');

/// Fails with a source-associated message before any UI artifacts are emitted.
Never _fail(String message, Element element) =>
    throw InvalidGenerationSourceError(message, element: element);

/// Portable stable ID grammar shared by UI identity and component ownership.
final _id = RegExp(r'^[a-z][A-Za-z0-9]*(?:[._-][A-Za-z0-9]+)*$');

/// Formats authored-builder output before publication, never after generation.
final _formatter = DartFormatter(
  languageVersion: DartFormatter.latestLanguageVersion,
);

/// Validated contract and referenced DTO types used by both builders.
final class _Contract {
  /// Validates the marker and reads its generic annotation schema.
  _Contract(InterfaceElement marker) {
    final annotation = _checker(
      'CCUIFragmentContract',
    ).firstAnnotationOfExact(marker, throwOnUnresolved: false);
    if (annotation == null ||
        marker is! ClassElement ||
        marker.typeParameters.isNotEmpty ||
        marker.isPrivate) {
      _fail('UI contract must be a public non-generic marker class.', marker);
    }
    final arguments = (annotation.type! as InterfaceType).typeArguments;
    props = arguments[0];
    action = arguments[1];
    owner = annotation
        .getField('componentId')!
        .getField('value')!
        .toStringValue()!;
    id = annotation.getField('id')!.toStringValue()!;
    version = annotation.getField('version')!.toStringValue()!;
    if (!_id.hasMatch(id) ||
        id.length > 128 ||
        !RegExp(r'^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*$').hasMatch(owner) ||
        owner.length > 128) {
      _fail('UI contract requires stable owner and capability IDs.', marker);
    }
    try {
      CCSemVer.parse(version);
    } catch (_) {
      _fail('UI contract requires a valid SemVer.', marker);
    }
    if (props is! InterfaceType ||
        (props as InterfaceType).element is! ClassElement ||
        action is! InterfaceType ||
        (action as InterfaceType).element is! EnumElement) {
      _fail('UI v1 requires immutable DTO Props and enum Action.', marker);
    }
    final shape = {
      'schemaVersion': 1,
      'owner': owner,
      'id': id,
      'props': _schema(props, <Element>{}, marker),
      'action': _schema(action, <Element>{}, marker),
    };
    fingerprint = contractShapeFingerprint(shape);
    final publicTypes = <String>{'${marker.library.uri}#${marker.displayName}'};
    void collect(Object? value) {
      if (value is Map) {
        final name = value['type'];
        if (name is String &&
            name.startsWith('package:') &&
            name.contains('#')) {
          publicTypes.add(name);
        }
        for (final nested in value.values) {
          collect(nested);
        }
      } else if (value is List) {
        for (final nested in value) {
          collect(nested);
        }
      }
    }

    collect(shape);
    declarations = [
      for (final value in publicTypes.toList()..sort())
        (() {
          final parts = value.split('#');
          final uri = Uri.parse(parts.first);
          return <String, String>{
            'package': uri.pathSegments.first,
            'source': 'lib/${uri.pathSegments.skip(1).join('/')}',
            'symbol': parts.last,
          };
        })(),
    ];
  }

  /// Immutable input DTO type.
  late final DartType props;

  /// Closed public Action enum.
  late final DartType action;

  /// Canonical component identity.
  late final String owner;

  /// Owner-local capability identity.
  late final String id;

  /// Validated SemVer text.
  late final String version;

  /// Complete canonical public shape fingerprint.
  late final String fingerprint;

  /// All public marker/DTO/enum declarations required by the closed schema.
  late final List<Map<String, String>> declarations;

  /// Normalized record consumed by Host validation and rendering codegen.
  Map<String, Object?> get record => {
    'componentId': owner,
    'id': id,
    'version': version,
    'shapeFingerprint': fingerprint,
    'publicTypes': declarations,
  };

  /// Typed generated descriptor expression; no business code writes these IDs.
  String get expression =>
      'const CCUIFragmentDescriptor('
      'owner: ${jsonEncode(owner)}, id: ${jsonEncode(id)}, '
      'version: ${jsonEncode(version)}, fingerprint: ${jsonEncode(fingerprint)})';
}

/// Computes a conservative closed schema; collection and sealed unions await v2.
Object _schema(DartType type, Set<Element> stack, Element origin) {
  if (type is! InterfaceType ||
      type.element.isPrivate ||
      type.typeArguments.isNotEmpty) {
    _fail(
      'UI DTOs cannot contain dynamic, generics, collections or functions.',
      origin,
    );
  }
  final element = type.element;
  final uri = element.library.uri.toString();
  final name = element.displayName;
  final nullable = type.getDisplayString().endsWith('?');
  if (uri == 'dart:core' &&
      const {'String', 'bool', 'int', 'double', 'num'}.contains(name)) {
    return {'type': name, 'nullable': nullable};
  }
  if (element is EnumElement) {
    if (!uri.startsWith('package:') || uri.startsWith('package:flutter/')) {
      _fail(
        'UI DTO enums must come from Pure Dart contract libraries.',
        element,
      );
    }
    if (element.fields.any(
      (field) => !field.isStatic && field.isOriginDeclaration,
    )) {
      _fail('UI v1 enums cannot carry additional instance data.', element);
    }
    return {
      'type': '$uri#$name',
      'nullable': nullable,
      'values': [
        for (final field in element.fields)
          if (field.isEnumConstant) field.displayName,
      ],
    };
  }
  if (element is! ClassElement ||
      !element.isFinal ||
      !uri.startsWith('package:') ||
      uri.startsWith('package:flutter/') ||
      const [
        'package:ccrouter/',
        'package:ccrouter_core/',
        'package:ccrouter_contracts/',
        'package:ccrouter_ui/',
      ].any(uri.startsWith) ||
      element.supertype?.element.displayName != 'Object' ||
      element.interfaces.isNotEmpty ||
      element.mixins.isNotEmpty ||
      element.methods.isNotEmpty ||
      !stack.add(element)) {
    _fail(
      'UI DTOs must be final, acyclic Pure Dart data classes without inheritance.',
      origin,
    );
  }
  if (element.constructors.isEmpty ||
      element.constructors.any((c) => !c.isConst || c.isFactory)) {
    _fail('UI DTOs require const generative constructors only.', element);
  }
  final fields = element.fields.where((f) => !f.isStatic).toList()
    ..sort((a, b) => a.displayName.compareTo(b.displayName));
  final result = {
    'type': '$uri#$name',
    'nullable': nullable,
    'fields': [
      for (final field in fields)
        (() {
          if (!field.isFinal || field.isPrivate || !field.isOriginDeclaration) {
            _fail('UI DTO fields must be public, final stored data.', field);
          }
          return {
            'name': field.displayName,
            'schema': _schema(field.type, stack, field),
          };
        })(),
    ],
    'constructors': [
      for (final constructor in element.constructors)
        {
          'name': constructor.name,
          'parameters': [
            for (final parameter in constructor.formalParameters)
              {
                'name': parameter.displayName,
                'required': parameter.isRequired,
                'named': parameter.isNamed,
                'default': parameter.hasDefaultValue
                    ? _constantShape(
                        parameter.computeConstantValue(),
                        parameter,
                      )
                    : null,
                'schema': _schema(parameter.type, stack, parameter),
              },
          ],
        },
    ],
  };
  stack.remove(element);
  return result;
}

/// Fingerprints effective constant defaults, including imported const values.
Object? _constantShape(DartObject? value, Element origin) {
  if (value == null) _fail('UI DTO default could not be evaluated.', origin);
  if (value.isNull) return null;
  if (value.toBoolValue() case final boolean?) return boolean;
  if (value.toIntValue() case final integer?) return integer;
  if (value.toStringValue() case final text?) return text;
  if (value.toDoubleValue() case final number?) {
    if (!number.isFinite) _fail('UI DTO default must be finite.', origin);
    return number;
  }
  final type = value.type;
  if (type is InterfaceType && type.element is EnumElement) {
    return {
      'enum': '${type.element.library.uri}#${type.element.displayName}',
      'index': value.getField('index')?.toIntValue(),
    };
  }
  if (type is InterfaceType && type.element is ClassElement) {
    return {
      for (final field in type.element.fields.where((f) => !f.isStatic))
        field.displayName: _constantShape(
          value.getField(field.displayName),
          origin,
        ),
    };
  }
  _fail('Unsupported UI DTO constant default.', origin);
}

/// Resolves only public authored contract exports, never implementation imports.
final class _Imports {
  /// Generated import statements in deterministic discovery order.
  final Map<String, String> libraries = {};

  /// Imports one library once and returns a stable local prefix.
  String prefix(String uri) =>
      libraries.putIfAbsent(uri, () => 'ui_${libraries.length}');

  /// Preserves nullable type references; supported schema types are non-generic.
  String type(DartType value) {
    final interface = value as InterfaceType;
    final element = interface.element;
    if (element.library.uri.toString() == 'dart:core')
      return value.getDisplayString();
    final reference =
        '${prefix(element.library.uri.toString())}.${element.displayName}';
    return '$reference${value.getDisplayString().endsWith('?') ? '?' : ''}';
  }
}

/// Produces isolated source and disposable metadata without changing old APIs.
final class _UIFragmentBuilder implements Builder {
  /// Selects cache metadata or generated source publication.
  _UIFragmentBuilder(this.metadata);

  /// Whether this instance writes only build-cache JSON.
  final bool metadata;

  @override
  /// Maps authored source paths without introducing outputs for old libraries.
  Map<String, List<String>> get buildExtensions => metadata
      ? const {
          r'^lib/src/{{}}.dart': [
            'lib/src/ccrouter_generated/metadata/{{}}.ui.json',
          ],
        }
      : const {
          r'^lib/src/{{}}.dart': [
            'lib/src/ccrouter_generated/ui/{{}}.ui.g.dart',
          ],
        };

  @override
  /// Resolves exact annotations and emits only explicitly declared UI surfaces.
  Future<void> build(BuildStep buildStep) async {
    if (buildStep.inputId.path.contains('/ccrouter_generated/')) return;
    if (!await buildStep.resolver.isLibrary(buildStep.inputId)) return;
    final library = await buildStep.resolver.libraryFor(buildStep.inputId);
    final reader = LibraryReader(library);
    final contracts = <Map<String, Object?>>[];
    final renderers = <Map<String, Object?>>[];
    final requirements = <Map<String, Object?>>[];
    final imports = _Imports();
    final out = StringBuffer();
    final contributions = <String>[];
    final sourceUri =
        'package:${buildStep.inputId.package}/${buildStep.inputId.path.substring(4)}';
    final sourcePrefix = imports.prefix(sourceUri);
    for (final element in reader.allElements.whereType<InterfaceElement>()) {
      if (_checker('CCUIFragmentContract').hasAnnotationOfExact(element)) {
        contracts.add(_Contract(element).record);
      }
    }
    for (final function in library.topLevelFunctions) {
      final annotation = _checker(
        'CCUIFragmentRenderer',
      ).firstAnnotationOfExact(function, throwOnUnresolved: false);
      if (annotation == null) continue;
      final marker = annotation.getField('contract')?.toTypeValue();
      if (marker is! InterfaceType)
        _fail('Renderer requires a UI contract marker.', function);
      final contract = _Contract(marker.element);
      final parameters = function.formalParameters;
      final input = parameters.length == 1 ? parameters.single.type : null;
      final result = function.returnType;
      if (function.isPrivate ||
          function.typeParameters.isNotEmpty ||
          result is! InterfaceType ||
          result.element.displayName != 'Widget' ||
          !result.element.library.uri.toString().startsWith(
            'package:flutter/',
          ) ||
          input is! InterfaceType ||
          input.element.displayName != 'CCUIFragmentRenderInput' ||
          !input.element.library.uri.toString().startsWith(
            'package:ccrouter_ui/',
          ) ||
          input.typeArguments.length != 2 ||
          input.typeArguments[0] != contract.props ||
          input.typeArguments[1] != contract.action ||
          !parameters.single.isRequiredPositional ||
          input.getDisplayString().endsWith('?') ||
          result.getDisplayString().endsWith('?')) {
        _fail(
          'rendererSignatureMismatch: public synchronous Widget function with one exact CCUIFragmentRenderInput<P, A> required.',
          function,
        );
      }
      final props = imports.type(contract.props);
      final action = imports.type(contract.action);
      contributions.add(
        'CCUIRenderer<$props, $action>(contract: ${contract.expression}, renderer: $sourcePrefix.${function.displayName})',
      );
      renderers.add({...contract.record, 'function': function.displayName});
    }
    for (final variable in library.topLevelVariables) {
      if (!_checker('CCComponent').isExactlyType(variable.type)) continue;
      final value = variable.computeConstantValue();
      if (value == null) continue; // Existing component validator reports this.
      final dependencies =
          value.getField('uiDependencies')?.toListValue() ?? [];
      if (dependencies.isEmpty) continue;
      if (variable.isPrivate || !variable.isConst)
        _fail('UI consumer component must be public const.', variable);
      final consumer = value
          .getField('id')!
          .getField('value')!
          .toStringValue()!;
      final owners = {
        for (final item in value.getField('dependencies')!.toListValue()!)
          item.getField('value')!.toStringValue()!,
      };
      final aliases = <String>{};
      final identities = <String>{};
      final className =
          '${consumer.split(RegExp(r'[._-]')).map((s) => s[0].toUpperCase() + s.substring(1)).join()}Fragments';
      out.writeln('abstract final class $className {');
      for (final dependency in dependencies) {
        final depType = dependency.type;
        if (depType is! InterfaceType ||
            !_checker('CCUIFragmentDependency').isExactlyType(depType) ||
            depType.typeArguments.single is! InterfaceType) {
          _fail('UI dependency requires a contract marker.', variable);
        }
        final contract = _Contract(
          (depType.typeArguments.single as InterfaceType).element,
        );
        final alias = dependency.getField('alias')!.toStringValue()!;
        final range = dependency.getField('versionRange')!.toStringValue()!;
        if (!isGeneratedClientMemberName(alias) ||
            alias == 'hashCode' ||
            alias == 'runtimeType' ||
            alias == 'toString' ||
            alias == 'noSuchMethod' ||
            !aliases.add(alias) ||
            !identities.add('${contract.owner}/${contract.id}')) {
          _fail(
            'UI aliases and contract dependencies must be unique Dart members.',
            variable,
          );
        }
        if (!owners.contains(contract.owner) || consumer == contract.owner) {
          _fail(
            'dependencyMissing: UI owner must be a required external component.',
            variable,
          );
        }
        try {
          CCContractVersionRange.parse(range);
        } catch (_) {
          _fail('UI dependency requires a valid version range.', variable);
        }
        final requirement =
            'const CCUIFragmentRequirement(consumer: ${jsonEncode(consumer)}, contract: ${contract.expression}, versionRange: ${jsonEncode(range)})';
        requirements.add({
          ...contract.record,
          'consumer': consumer,
          'versionRange': range,
        });
        final props = imports.type(contract.props);
        final action = imports.type(contract.action);
        out.writeln(
          'static Widget $alias({Key? key, required $props props, required ValueChanged<$action> onAction, bool active = true}) => CCUIGeneratedFragment<$props, $action>(key: key, props: props, onAction: onAction, active: active, requirement: $requirement);',
        );
      }
      out.writeln('}');
    }
    if (contracts.isEmpty && renderers.isEmpty && requirements.isEmpty) return;
    final stem = buildStep.inputId.path.substring(
      'lib/src/'.length,
      buildStep.inputId.path.length - 5,
    );
    final generated = 'lib/src/ccrouter_generated/ui/$stem.ui.g.dart';
    if (metadata) {
      await buildStep.writeAsString(
        buildStep.allowedOutputs.single,
        '${jsonEncode({'schemaVersion': 5, 'componentDeclarations': <String>[], 'package': buildStep.inputId.package, 'source': buildStep.inputId.path, 'uiSchemaVersion': 1, 'uiLibrary': generated, 'uiContracts': contracts, 'uiRenderers': renderers, 'uiRequirements': requirements})}\n',
      );
      return;
    }
    // Pure contracts emit metadata only and do not acquire a Flutter dependency.
    if (contributions.isEmpty && requirements.isEmpty) return;
    final source =
        StringBuffer(
            '// GENERATED CODE - DO NOT MODIFY BY HAND\n// ignore_for_file: type=lint, unused_import\n',
          )
          ..writeln("import 'package:flutter/widgets.dart';")
          ..writeln("import 'package:ccrouter_ui/ccrouter_ui_generated.dart';");
    for (final entry in imports.libraries.entries) {
      source.writeln('import ${jsonEncode(entry.key)} as ${entry.value};');
    }
    source.writeln(out);
    source.writeln(
      'final ccUIContributions = <CCUIFragmentContribution>[${contributions.join(',')}];',
    );
    final expressions = [
      for (final r in requirements)
        'CCUIFragmentRequirement(consumer: ${jsonEncode(r['consumer'])}, contract: CCUIFragmentDescriptor(owner: ${jsonEncode(r['componentId'])}, id: ${jsonEncode(r['id'])}, version: ${jsonEncode(r['version'])}, fingerprint: ${jsonEncode(r['shapeFingerprint'])}), versionRange: ${jsonEncode(r['versionRange'])})',
    ];
    source.writeln(
      'const ccUIRequirements = <CCUIFragmentRequirement>[${expressions.join(',')}];',
    );
    await buildStep.writeAsString(
      buildStep.allowedOutputs.single,
      _formatter.format(source.toString()),
    );
  }
}
