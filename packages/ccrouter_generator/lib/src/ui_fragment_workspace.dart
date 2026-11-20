import 'package:ccrouter_contracts/ccrouter_contracts.dart';

import 'workspace_validator.dart';
import 'contract_validation.dart';

/// Validates UI metadata independently of the original five Contract families.
///
/// Package-local generation checks local declarations; only Host generation
/// requires every required Renderer to be installed in the resolved closure.
List<String> validateUIFragmentWorkspace(
  Iterable<Map<String, Object?>> documents, {
  required bool host,
}) {
  return [
    for (final issue in validateUIFragmentWorkspaceDiagnostics(
      documents,
      host: host,
    ))
      issue.message,
  ]..sort();
}

/// Emits typed UI failures without parsing human messages in CLI or IDE code.
/// Legacy records without proven locations still fail CLI validation, but do
/// not acquire speculative IDE source positions.
List<CCWorkspaceDiagnostic> validateUIFragmentWorkspaceDiagnostics(
  Iterable<Map<String, Object?>> documents, {
  required bool host,
}) {
  final values = documents.toList();
  final errors = <CCWorkspaceDiagnostic>[];
  void report(
    String code,
    String message,
    Map<String, Object?> record,
    String locationKey,
    String correction,
  ) {
    final primary = _location(record[locationKey]);
    final declaration = _location(record['declaration']);
    errors.add(
      CCWorkspaceDiagnostic(
        code: 'ccrouter_ui_$code',
        severity: CCWorkspaceDiagnosticSeverity.error,
        message: message,
        rootCauseGroup:
            'ui:$code:${_identity(record)}:${record['consumer'] ?? ''}',
        primaryLocation: primary,
        correction: correction,
        relatedLocations: [
          if (declaration != null && locationKey != 'declaration')
            CCWorkspaceRelatedDiagnosticLocation(
              message: 'UI Contract declaration.',
              location: declaration,
            ),
        ],
      ),
    );
  }

  final components = <String, Map<String, Object?>>{};
  final owners = <String, String>{};
  final contracts = <String, Map<String, Object?>>{};
  final implementations = <String, Map<String, Object?>>{};
  final ranges = <String, CCContractVersionRange>{};
  for (final document in values) {
    for (final component in _objects(document['components'])) {
      components['${component['id']}'] = component;
      owners['${document['package']}'] = '${component['id']}';
    }
    final records = [
      ..._objects(document['uiContracts']),
      ..._objects(document['uiRenderers']),
      ..._objects(document['uiRequirements']),
    ];
    final requiredSchema = records.fold<int>(1, (version, record) {
      final required = record['uiSchemaVersion'];
      return required is int && required > version ? required : version;
    });
    if ((document.containsKey('uiSchemaVersion') &&
            (document['uiSchemaVersion'] is! int ||
                document['uiSchemaVersion'] != requiredSchema)) ||
        (!document.containsKey('uiSchemaVersion') && requiredSchema > 1) ||
        records.any(
          (r) =>
              r.containsKey('uiSchemaVersion') &&
              (r['uiSchemaVersion'] is! int ||
                  r['uiSchemaVersion'] != 1 &&
                      r['uiSchemaVersion'] != 2 &&
                      r['uiSchemaVersion'] != 3),
        )) {
      report(
        'stale_generated_output',
        'UI staleGeneratedOutput: unsupported UI schema; upgrade generator.',
        const {},
        'declaration',
        'Upgrade the Generator and regenerate UI metadata.',
      );
    }
    for (final (role, locationKey) in const [
      ('uiContracts', 'declaration'),
      ('uiRenderers', 'implementation'),
      ('uiRequirements', 'consumerDeclaration'),
    ]) {
      for (final record in _objects(document[role])) {
        if (!_validDescriptor(record)) {
          report(
            'stale_generated_output',
            'UI staleGeneratedOutput: invalid descriptor for ${_identity(record)}.',
            record,
            locationKey,
            'Regenerate valid bounded identities, versions and SHA-256 fingerprints.',
          );
        }
        if (role == 'uiRequirements') {
          final range = record['versionRange'];
          try {
            if (range is! String) throw const FormatException();
            ranges.putIfAbsent(
              range,
              () => CCContractVersionRange.parse(range),
            );
          } on FormatException {
            report(
              'stale_generated_output',
              'UI staleGeneratedOutput: invalid consumer range for ${_identity(record)}.',
              record,
              locationKey,
              'Repair the consumer range and regenerate.',
            );
          }
        }
      }
    }
    for (final contract in _objects(document['uiContracts'])) {
      final identity = _identity(contract);
      if (contracts.containsKey(identity)) {
        report(
          'contract_duplicate',
          'UI duplicate contract: $identity.',
          contract,
          'declaration',
          'Keep one public UI Contract for this identity.',
        );
      }
      contracts[identity] = contract;
    }
  }
  for (final document in values) {
    for (final renderer in _objects(document['uiRenderers'])) {
      final identity = _identity(renderer);
      if (owners['${document['package']}'] != renderer['componentId']) {
        report(
          'owner_mismatch',
          'UI ownerMismatch: $identity.',
          renderer,
          'implementation',
          'Move the Renderer to the declared Owner component.',
        );
      }
      if (implementations.containsKey(identity)) {
        report(
          'implementation_duplicate',
          'UI duplicateImplementation: $identity.',
          renderer,
          'implementation',
          'Keep one Renderer in the Host closure.',
        );
      }
      implementations[identity] = renderer;
      if (!_sameSchema(contracts[identity], renderer)) {
        report(
          'stale_generated_output',
          'UI staleGeneratedOutput: Renderer $identity.',
          renderer,
          'implementation',
          'Regenerate the Renderer and Host against the current Contract.',
        );
      }
    }
    for (final requirement in _objects(document['uiRequirements'])) {
      final identity = _identity(requirement);
      final consumer = components['${requirement['consumer']}'];
      if (owners['${document['package']}'] != requirement['consumer'] ||
          consumer == null ||
          !_strings(
            consumer['dependencies'],
          ).contains('${requirement['componentId']}')) {
        report(
          'dependency_missing',
          'UI dependencyMissing: $identity for consumer '
              '"${requirement['consumer']}" in Package "${document['package']}". '
              'Verify the declaring consumer and add the public Owner CCComponentId '
              'to its CCComponent.dependencies; optionalDependencies is insufficient. '
              'Regenerate the consumer and Host after correcting the declaration.',
          requirement,
          'consumerDeclaration',
          'Add the public Owner CCComponentId to required dependencies and regenerate the consumer and Host.',
        );
      }
      if (!_sameSchema(contracts[identity], requirement)) {
        report(
          'stale_generated_output',
          'UI staleGeneratedOutput: consumer $identity.',
          requirement,
          'consumerDeclaration',
          'Regenerate the consumer and Host against the current Contract.',
        );
      }
    }
  }
  if (host) {
    for (final document in values) {
      for (final requirement in _objects(document['uiRequirements'])) {
        final identity = _identity(requirement);
        final renderer = implementations[identity];
        if (renderer == null) {
          report(
            'missing_implementation',
            'UI missingImplementation: $identity required by consumer '
                '"${requirement['consumer']}". Include the Owner implementation '
                'with its @CCUIFragmentRenderer in the Host dependency closure, '
                'then regenerate that Host.',
            requirement,
            'consumerDeclaration',
            'Include the Owner implementation with its Renderer in the Host dependency closure and regenerate that Host.',
          );
        } else if (renderer['shapeFingerprint'] !=
            requirement['shapeFingerprint']) {
          report(
            'fingerprint_changed',
            'UI fingerprintChanged: $identity.',
            requirement,
            'consumerDeclaration',
            'Regenerate the consumer, Renderer and Host against the same Contract shape.',
          );
        } else {
          final range = ranges[requirement['versionRange']];
          // Invalid fields already have a source-located error from the first pass.
          if (range != null && _validDescriptor(renderer)) {
            if (!range.allowsText(renderer['version'] as String)) {
              report(
                'version_out_of_range',
                'UI versionOutOfRange: $identity.',
                requirement,
                'consumerDeclaration',
                'Align the required version range and installed Renderer version.',
              );
            }
          }
        }
      }
    }
  }
  return errors..sort((a, b) => a.message.compareTo(b.message));
}

/// External records require the same field grammar as Generator and UI Host.
bool _validDescriptor(Map<String, Object?> record) {
  final owner = record['componentId'];
  final id = record['id'];
  final version = record['version'];
  final fingerprint = record['shapeFingerprint'];
  return owner is String &&
      owner.length <= 128 &&
      RegExp(r'^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*$').hasMatch(owner) &&
      id is String &&
      id.length <= 128 &&
      RegExp(r'^[a-z][A-Za-z0-9]*(?:[._-][A-Za-z0-9]+)*$').hasMatch(id) &&
      version is String &&
      isContractSemanticVersion(version) &&
      fingerprint is String &&
      RegExp(r'^[a-f0-9]{64}$').hasMatch(fingerprint);
}

/// Composite public identity independent of instance Key.
String _identity(Map<String, Object?> record) =>
    '${record['componentId']}/${record['id']}';

/// Verifies that generated Renderer and consumer snapshots match authored shape.
bool _sameSchema(Map<String, Object?>? a, Map<String, Object?> b) =>
    a != null &&
    (a['uiSchemaVersion'] ?? 1) == (b['uiSchemaVersion'] ?? 1) &&
    a['shapeFingerprint'] == b['shapeFingerprint'] &&
    a['version'] == b['version'];

/// Reads a JSON list without accepting unrelated scalar metadata.
Iterable<Map<String, Object?>> _objects(Object? value) => value is List
    ? value.whereType<Map>().map((v) => v.cast<String, Object?>())
    : const [];

/// Reads component dependency identities from normalized metadata.
Iterable<String> _strings(Object? value) =>
    value is List ? value.whereType<String>() : const [];

/// Accepts only portable authored positions; missing legacy evidence defers IDE.
CCWorkspaceDiagnosticLocation? _location(Object? value) {
  if (value is! Map) return null;
  final uri = value['packageUri'];
  final line = value['line'];
  final column = value['column'];
  if (line is! int || line < 1 || column is! int || column < 1) return null;
  try {
    final parsed = uri is String ? Uri.tryParse(uri) : null;
    if (parsed == null ||
        parsed.scheme != 'package' ||
        parsed.hasAuthority ||
        parsed.hasAbsolutePath ||
        parsed.hasQuery ||
        parsed.hasFragment ||
        parsed.pathSegments.length < 2 ||
        parsed.pathSegments.any(
          (s) =>
              s.isEmpty ||
              s == '..' ||
              s == '.' ||
              s.contains('/') ||
              s.contains(r'\') ||
              s.contains('\u0000'),
        ))
      return null;
  } on FormatException {
    return null;
  }
  final symbol = value['symbol'];
  return CCWorkspaceDiagnosticLocation(
    uri: uri as String,
    line: line,
    column: column,
    length: symbol is String && symbol.isNotEmpty ? symbol.length : 1,
  );
}
