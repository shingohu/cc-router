import 'package:ccrouter_contracts/ccrouter_contracts.dart';

/// Validates UI metadata independently of the original five Contract families.
///
/// Package-local generation checks local declarations; only Host generation
/// requires every required Renderer to be installed in the resolved closure.
List<String> validateUIFragmentWorkspace(
  Iterable<Map<String, Object?>> documents, {
  required bool host,
}) {
  final values = documents.toList();
  final errors = <String>[];
  final components = <String, Map<String, Object?>>{};
  final owners = <String, String>{};
  final contracts = <String, Map<String, Object?>>{};
  final implementations = <String, Map<String, Object?>>{};
  for (final document in values) {
    for (final component in _objects(document['components'])) {
      components['${component['id']}'] = component;
      owners['${document['package']}'] = '${component['id']}';
    }
    if (document.containsKey('uiSchemaVersion') &&
        document['uiSchemaVersion'] != 1) {
      errors.add(
        'UI staleGeneratedOutput: unsupported UI schema; upgrade generator.',
      );
    }
    for (final contract in _objects(document['uiContracts'])) {
      final identity = _identity(contract);
      if (contracts.containsKey(identity)) {
        errors.add('UI duplicate contract: $identity.');
      }
      contracts[identity] = contract;
    }
  }
  for (final document in values) {
    for (final renderer in _objects(document['uiRenderers'])) {
      final identity = _identity(renderer);
      if (owners['${document['package']}'] != renderer['componentId']) {
        errors.add('UI ownerMismatch: $identity.');
      }
      if (implementations.containsKey(identity)) {
        errors.add('UI duplicateImplementation: $identity.');
      }
      implementations[identity] = renderer;
      if (!_sameSchema(contracts[identity], renderer)) {
        errors.add('UI staleGeneratedOutput: Renderer $identity.');
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
        errors.add('UI dependencyMissing: $identity.');
      }
      if (!_sameSchema(contracts[identity], requirement)) {
        errors.add('UI staleGeneratedOutput: consumer $identity.');
      }
    }
  }
  if (host) {
    for (final document in values) {
      for (final requirement in _objects(document['uiRequirements'])) {
        final identity = _identity(requirement);
        final renderer = implementations[identity];
        if (renderer == null) {
          errors.add('UI missingImplementation: $identity.');
        } else if (renderer['shapeFingerprint'] !=
            requirement['shapeFingerprint']) {
          errors.add('UI fingerprintChanged: $identity.');
        } else {
          try {
            if (!CCContractVersionRange.parse(
              '${requirement['versionRange']}',
            ).allowsText('${renderer['version']}')) {
              errors.add('UI versionOutOfRange: $identity.');
            }
          } on FormatException {
            errors.add(
              'UI staleGeneratedOutput: invalid version for $identity.',
            );
          }
        }
      }
    }
  }
  return errors..sort();
}

/// Composite public identity independent of instance Key.
String _identity(Map<String, Object?> record) =>
    '${record['componentId']}/${record['id']}';

/// Verifies that generated Renderer and consumer snapshots match authored shape.
bool _sameSchema(Map<String, Object?>? a, Map<String, Object?> b) =>
    a != null &&
    a['shapeFingerprint'] == b['shapeFingerprint'] &&
    a['version'] == b['version'];

/// Reads a JSON list without accepting unrelated scalar metadata.
Iterable<Map<String, Object?>> _objects(Object? value) => value is List
    ? value.whereType<Map>().map((v) => v.cast<String, Object?>())
    : const [];

/// Reads component dependency identities from normalized metadata.
Iterable<String> _strings(Object? value) =>
    value is List ? value.whereType<String>() : const [];
