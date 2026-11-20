@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';

void main() {
  test(
    'CLI completes and emits consumer snapshots without replacing their constraints',
    () async {
      final source = File(
        'packages/ccrouter_generator/bin/ccrouter_generator.dart',
      ).readAsStringSync();
      // Compile the real private functions without adding a test-only public CLI API.
      String extract(String start, String end) {
        final offset = source.indexOf(start);
        expect(offset, isNonNegative, reason: start);
        final limit = source.indexOf(end, offset);
        expect(limit, greaterThan(offset), reason: end);
        return source.substring(offset, limit);
      }

      final functions = [
        extract(
          'String _emitPackageContractRequirements(',
          '/// Writes the Host facade',
        ),
        extract(
          'void _annotateConsumerContractMetadata(',
          '/// Writes non-empty Package-local capability discovery views.',
        ),
        extract(
          'Iterable<Map<String, Object?>> _objects(',
          '/// Describes the annotated component declaration',
        ),
        source
            .split('\n')
            .singleWhere((line) => line.startsWith('String _dartLiteral(')),
      ].join('\n');
      final temporary = Directory.systemTemp.createTempSync(
        'ccrouter-requirement-emission-',
      );
      addTearDown(() => temporary.deleteSync(recursive: true));
      final program = File('${temporary.path}/main.dart')
        ..writeAsStringSync('''
import 'dart:convert';
$functions
void main() {
  final fingerprint = 'a' * 64;
  final records = {'owner.service': <String, Object?>{'componentId': 'owner', 'version': '1.1.0', 'shapeFingerprint': fingerprint}};
  final result = <String, Object?>{};
  for (final kind in ['service', 'command', 'event', 'initTask']) {
    final snapshots = [for (final range in ['^1.0.0', '<1.5.0']) <String, Object?>{
      'id': 'owner.service', 'eventId': 'owner.service', 'componentId': 'owner', 'eventComponentId': 'owner',
      'requiredVersionRange': range, 'requiredShapeFingerprint': fingerprint,
    }];
    final document = <String, Object?>{
      'components': [<String, Object?>{'id': 'consumer', if (kind == 'service') 'serviceDependencies': snapshots,
        if (kind == 'command') 'commandDependencies': [snapshots.first]}],
      if (kind == 'event') 'eventSubscriptions': snapshots,
      if (kind == 'initTask') 'initTasks': [for (final snapshot in snapshots) <String, Object?>{'dependsOn': ['owner.service'], 'contractDependencies': [snapshot]}],
    };
    final ownerMetadata = <String, Object?>{
      'serviceContracts': [<String, Object?>{'id': 'owner.service', ...records['owner.service']!}],
      'commandContracts': [<String, Object?>{'id': 'owner.service', ...records['owner.service']!}],
      'eventContracts': [<String, Object?>{'id': 'owner.service', ...records['owner.service']!}],
      'initTaskContracts': [<String, Object?>{'id': 'owner.service', ...records['owner.service']!}],
    };
    _annotateConsumerContractMetadata({'consumer': [document]}, [ownerMetadata]);
    result[kind] = _emitPackageContractRequirements([document], 'consumer', records);
  }
  result['legacy'] = _emitPackageContractRequirements([{'components': [{'id': 'consumer',
    'serviceDependencies': [{'id': 'owner.service', 'componentId': 'owner'}]}]}], 'consumer', records);
  final duplicate = {'components': [{'id': 'consumer', 'serviceDependencies': List.filled(2,
    {'id': 'owner.service', 'componentId': 'owner', 'requiredVersionRange': '^1.0.0', 'requiredShapeFingerprint': fingerprint})}]};
  result['duplicate'] = _emitPackageContractRequirements([duplicate], 'consumer', records);
  final oldTask = <String, Object?>{'dependsOn': ['owner.service'], 'contractDependencies': [<String, Object?>{'id': 'owner.service', 'componentId': 'owner'}]};
  _annotateConsumerContractMetadata({'consumer': [<String, Object?>{'initTasks': [oldTask]}]}, [
    <String, Object?>{'initTaskContracts': [<String, Object?>{'id': 'owner.service', ...records['owner.service']!}]},
  ]);
  result['legacyTask'] = (oldTask['contractDependencies'] as List).single['requiredVersionRange'];
  result['legacyTaskShape'] = (oldTask['contractDependencies'] as List).single['requiredShapeFingerprint'];
  print(jsonEncode(result));
}
''');
      final result = await Process.run(Platform.resolvedExecutable, [
        program.path,
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      final outputs = (jsonDecode('${result.stdout}') as Map)
          .cast<String, String>();
      for (final kind in ['service', 'command', 'event', 'initTask']) {
        final emitted = outputs[kind]!;
        final expectedCount = kind == 'command' ? 1 : 2;
        expect(
          'CCContractRequirement('.allMatches(emitted),
          hasLength(expectedCount),
          reason: kind,
        );
        expect(
          emitted,
          contains('requiredVersionRange: "^1.0.0"'),
          reason: kind,
        );
        expect(
          emitted,
          isNot(contains('requiredVersionRange: "1.1.0"')),
          reason: kind,
        );
        if (expectedCount == 2)
          expect(emitted, contains('requiredVersionRange: "<1.5.0"'));
      }
      expect(outputs['legacy'], contains('requiredVersionRange: "1.1.0"'));
      expect(outputs['legacyTask'], '1.1.0');
      expect(outputs['legacyTaskShape'], 'a' * 64);
      expect(
        'CCContractRequirement('.allMatches(outputs['duplicate']!),
        hasLength(1),
      );
    },
  );
}
