@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  for (final union in [false, true]) {
    test(
      'prebuilt ${union ? 'sealed UI' : 'Service'} Package survives independent Git and archive consumption',
      () async {
        final root = Directory(
          (await Directory.systemTemp.createTemp(
            'ccrouter_distribution_',
          )).resolveSymbolicLinksSync(),
        );
        addTearDown(() => root.delete(recursive: true));
        // Reuse downloaded hosted packages offline, but keep fixture Git clones
        // and temporary Pub files out of the developer's persistent Pub cache.
        final cache = Directory(path.join(root.path, 'pub-cache'))
          ..createSync();
        final sharedCache =
            Platform.environment['PUB_CACHE'] ??
            path.join(Platform.environment['HOME']!, '.pub-cache');
        for (final name in ['hosted', 'hosted-hashes']) {
          final shared = Directory(path.join(sharedCache, name));
          if (shared.existsSync()) {
            Link(path.join(cache.path, name)).createSync(shared.path);
          }
        }
        final producer = Directory(path.join(root.path, 'producer'))
          ..createSync();
        final consumer = Directory(path.join(root.path, 'consumer'))
          ..createSync();
        final dto = Directory(path.join(root.path, 'dto'))..createSync();
        _write(
          dto,
          'pubspec.yaml',
          'name: distribution_dto\nversion: 1.0.0\nenvironment:\n  sdk: ^3.10.0\n',
        );
        _write(dto, 'lib/dto.dart', 'final class Value { const Value(); }\n');
        _write(
          producer,
          'pubspec.yaml',
          _pubspec(
            'distributed_component',
            extraDev: '  test: ^1.30.0\n',
            extraDependencies:
                '  distribution_dto: ^1.0.0\n${union ? '  ccrouter_contracts: ^0.1.0\n' : ''}',
            extraOverrides: '  distribution_dto:\n    path: ${dto.path}\n',
          ),
        );
        _write(producer, 'ccrouter.yaml', 'generation:\n  portable: true\n');
        _write(
          producer,
          'lib/component.dart',
          "export 'src/component.dart';\n",
        );
        _write(producer, 'lib/src/component.dart', '''
import 'package:ccrouter/ccrouter.dart';
import 'package:distribution_dto/dto.dart';
const component = CCComponent(id: CCComponentId('distributed'), version: '1.0.0');
@CCService(id: 'distributed.service')
final class DistributedService { DistributedService(); Value value() => const Value(); }
''');
        if (union) {
          _write(
            producer,
            'lib/component.dart',
            "export 'src/component.dart' show component, DistributedService;\nexport 'src/panel.dart' show PanelProps, PanelAction, Settings, Selected, PanelContract, Target, User;\n",
          );
          _write(producer, 'lib/src/panel.dart', '''
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:ccrouter_contracts/ccrouter_ui_contracts.dart';
part 'targets.dart';
final class PanelProps { const PanelProps(); }
sealed class PanelAction { const PanelAction(); }
final class Settings extends PanelAction { const Settings(); }
final class Selected extends PanelAction { const Selected(this.target); final Target target; }
@CCUIFragmentContract<PanelProps, PanelAction>(componentId: CCComponentId('distributed'), id: 'distributed.panel', version: '1.0.0')
abstract final class PanelContract {}
''');
          _write(
            producer,
            'lib/src/targets.dart',
            "part of 'panel.dart'; sealed class Target { const Target(this.id); final String id; } final class User extends Target { const User(super.id); }\n",
          );
        }
        await _pubGet(producer);
        await _prepare(producer);
        await _run(Platform.resolvedExecutable, ['analyze', 'lib'], producer);
        final original = _generated(producer);
        if (union) {
          final index =
              jsonDecode(
                    File(
                      path.join(
                        producer.path,
                        'lib/src/ccrouter_generated/metadata/ccrouter_package.json',
                      ),
                    ).readAsStringSync(),
                  )
                  as Map;
          expect(index['schemaVersion'], 5);
          final targetFile = File(
            path.join(producer.path, 'lib/src/targets.dart'),
          );
          final source = targetFile.readAsStringSync();
          targetFile.writeAsStringSync(
            source.replaceFirst('final String id;', 'final num id;'),
          );
          final stale = await _generate(producer, ['--check'], expectedExit: 1);
          expect('${stale.stderr}', contains('stale'));
          expect(
            _generated(producer),
            original,
            reason: '--check restores managed outputs after a part-only change',
          );
          await _prepare(producer);
          expect(
            _generated(producer),
            isNot(original),
            reason:
                'A part-only inherited field change must invalidate metadata and Portable State',
          );
          targetFile.writeAsStringSync(source);
          await _prepare(producer);
          expect(_generated(producer), original);
        }

        await _run('git', ['init', '--quiet'], producer);
        await _run('git', [
          'add',
          'pubspec.yaml',
          'ccrouter.yaml',
          'lib',
        ], producer);
        await _run('git', [
          '-c',
          'user.name=CCRouter Test',
          '-c',
          'user.email=test@example.invalid',
          'commit',
          '--quiet',
          '-m',
          'prebuilt fixture',
        ], producer);
        final revision = (await _run('git', [
          'rev-parse',
          'HEAD',
        ], producer)).stdout.toString().trim();
        _write(
          consumer,
          'pubspec.yaml',
          _pubspec(
            'distribution_host',
            extraOverrides: '  distribution_dto:\n    path: ${dto.path}\n',
            extraDependencies:
                '''
  distributed_component:
    git:
      url: ${producer.uri}
      ref: $revision
''',
          ),
        );
        _write(consumer, 'ccrouter.yaml', 'host:\n  enabled: true\n');
        _write(consumer, 'lib/host.dart', '// Host composition fixture.\n');
        await _pubGet(consumer);
        final graph =
            jsonDecode(
                  File(
                    path.join(consumer.path, '.dart_tool/package_graph.json'),
                  ).readAsStringSync(),
                )
                as Map;
        final distributed = (graph['packages'] as List).cast<Map>().singleWhere(
          (p) => p['name'] == 'distributed_component',
        );
        expect(distributed['devDependencies'] ?? const [], isEmpty);
        expect(
          (graph['packages'] as List).cast<Map>().any(
            (p) => p['name'] == 'test',
          ),
          isFalse,
        );
        final consumed = await _generate(consumer, ['--no-cache']);
        expect(consumed.stdout.toString(), contains('Validated 1 components'));
        await _run(Platform.resolvedExecutable, ['analyze', 'lib'], consumer);
        await _generate(consumer, ['--check']);
        await _generate(consumer, ['--no-cache', '--check']);
        expect(_generated(producer), original);

        // An exported source archive has no author Git identity or build cache.
        final archive = path.join(root.path, 'component.tar');
        await _run('git', [
          'archive',
          '--format=tar',
          '--output=$archive',
          revision,
        ], producer);
        final extracted = Directory(path.join(root.path, 'archive'))
          ..createSync();
        await _run('tar', ['-xf', archive, '-C', extracted.path], root);
        _write(
          consumer,
          'pubspec.yaml',
          _pubspec(
            'distribution_host',
            extraOverrides: '  distribution_dto:\n    path: ${dto.path}\n',
            extraDependencies:
                '''
  distributed_component:
    path: ${extracted.path}
''',
          ),
        );
        await _pubGet(consumer);
        await _generate(consumer, ['--no-cache']);
        await _generate(consumer, ['--check']);
        expect(_generated(extracted), original);

        // A warm cache must not accept stale external authored or generated bytes.
        final source = File(
          path.join(extracted.path, 'lib/src/component.dart'),
        );
        final sourceBytes = source.readAsStringSync();
        source.writeAsStringSync('$sourceBytes\n// external edit\n');
        for (final flags in [
          <String>['--check'],
          <String>['--no-cache', '--check'],
        ]) {
          final result = await _generate(consumer, flags, expectedExit: 1);
          expect(result.stderr.toString(), contains('authoredInputMismatch'));
        }
        source.writeAsStringSync(sourceBytes);
        final generatedFile = File(
          path.join(
            extracted.path,
            original.keys.firstWhere((f) => f.endsWith('.service.g.dart')),
          ),
        );
        final generatedBytes = generatedFile.readAsStringSync();
        generatedFile.writeAsStringSync(
          '$generatedBytes\n// external output edit\n',
        );
        for (final flags in [
          <String>['--check'],
          <String>['--no-cache', '--check'],
        ]) {
          final result = await _generate(consumer, flags, expectedExit: 1);
          expect(result.stderr.toString(), contains('managedOutputMismatch'));
        }
        generatedFile.writeAsStringSync(generatedBytes);
        await _generate(consumer, ['--check']);
        generatedFile.deleteSync();
        for (final flags in [
          <String>['--check'],
          <String>['--no-cache', '--check'],
        ]) {
          final result = await _generate(consumer, flags, expectedExit: 1);
          expect(result.stderr.toString(), contains('managedOutputMismatch'));
        }
        generatedFile.writeAsStringSync(generatedBytes);
        await _generate(consumer, ['--check']);
        final dtoFile = File(path.join(dto.path, 'lib/dto.dart'));
        final dtoBytes = dtoFile.readAsStringSync();
        dtoFile.writeAsStringSync('$dtoBytes\n// transitive DTO edit\n');
        for (final flags in [
          <String>['--check'],
          <String>['--no-cache', '--check'],
        ]) {
          final result = await _generate(consumer, flags, expectedExit: 1);
          expect(result.stderr.toString(), contains('resolutionMismatch'));
        }
        dtoFile.writeAsStringSync(dtoBytes);
        await _generate(consumer, ['--check']);
      },
      timeout: const Timeout(Duration(minutes: 8)),
    );
  }
}

String _pubspec(
  String name, {
  String extraDependencies = '',
  String extraDev = '',
  String extraOverrides = '',
}) =>
    '''
name: $name
version: 1.0.0
environment:
  sdk: ^3.10.0
dependencies:
  ccrouter: ^0.1.0
$extraDependencies
dev_dependencies:
  ccrouter_generator: ^0.1.0
  build_runner: ^2.10.0
$extraDev
dependency_overrides:
$extraOverrides
${['ccrouter', 'ccrouter_core', 'ccrouter_contracts', 'ccrouter_generator'].map((p) => '  $p:\n    path: ${path.join(Directory.current.path, 'packages', p)}').join('\n')}
''';

void _write(Directory root, String relative, String content) {
  final file = File(path.join(root.path, relative));
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
}

Future<ProcessResult> _run(
  String executable,
  List<String> args,
  Directory root, {
  int expectedExit = 0,
}) async {
  final result = await Process.run(
    executable,
    args,
    workingDirectory: root.path,
    environment: {
      'CCROUTER_PUB_HOOK_DISABLE': '1',
      'PUB_CACHE': path.join(root.parent.path, 'pub-cache'),
    },
  );
  expect(
    result.exitCode,
    expectedExit,
    reason: '$executable $args\n${result.stdout}\n${result.stderr}',
  );
  return result;
}

Future<void> _pubGet(Directory root) async {
  final flutter = path.join(
    File(Platform.resolvedExecutable).parent.parent.parent.parent.path,
    Platform.isWindows ? 'flutter.bat' : 'flutter',
  );
  await _run(flutter, ['pub', 'get', '--offline'], root);
}

Future<ProcessResult> _generate(
  Directory root,
  List<String> flags, {
  int expectedExit = 0,
}) => _run(
  Platform.resolvedExecutable,
  [
    'run',
    '--verbosity=error',
    'ccrouter_generator:ccrouter',
    'generate',
    '.',
    ...flags,
  ],
  root,
  expectedExit: expectedExit,
);

Future<ProcessResult> _prepare(Directory root) =>
    _run(Platform.resolvedExecutable, [
      'run',
      '--verbosity=error',
      'ccrouter_generator:ccrouter',
      'portable',
      'prepare',
      '.',
    ], root);

Map<String, String> _generated(Directory root) => {
  for (final file in Directory(
    path.join(root.path, 'lib/src/ccrouter_generated'),
  ).listSync(recursive: true).whereType<File>())
    path.relative(file.path, from: root.path): file.readAsStringSync(),
};
