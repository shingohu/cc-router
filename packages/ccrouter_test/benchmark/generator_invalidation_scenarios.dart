part of 'generator_component_topology.dart';

/// Measures exact-byte invalidation without changing Builder/cache decisions.
/// Each Package contains all five capabilities and reads a common dependency.
/// Samples are exploratory, not a P95 claim or permission to prune dependencies.
Future<Map<String, Object?>> _runInvalidationScale(
  Directory workspaceRoot,
  int scale,
) async {
  final fixture = Directory.systemTemp.createTempSync(
    'ccrouter-invalidation-${scale}x-',
  );
  var succeeded = false;
  try {
    final count = 6 * scale;
    _writeWorkspace(
      workspaceRoot: workspaceRoot,
      fixture: fixture,
      componentCount: count,
      hostDependencyCount: count,
    );
    File file(String relative) => File(path.join(fixture.path, relative));
    void write(String relative, String source) {
      final target = file(relative);
      target.parent.createSync(recursive: true);
      target.writeAsStringSync(source);
    }

    void replace(String relative, String from, String to) {
      final target = file(relative);
      final source = target.readAsStringSync();
      if (!source.contains(from))
        throw StateError('Missing fixture marker: $relative');
      target.writeAsStringSync(source.replaceAll(from, to));
    }

    replace('pubspec.yaml', 'workspace:\n', 'workspace:\n  - shared_values\n');
    write('shared_values/pubspec.yaml', '''name: shared_values
version: 1.0.0
resolution: workspace
environment:
  sdk: ^3.10.0
''');
    write(
      'shared_values/lib/shared_values.dart',
      "export 'src/values.dart';\nexport 'src/other.dart';\n",
    );
    write('shared_values/lib/src/values.dart', '''const sharedDefault = 1;
const sharedDescription = 'Shared capability description.';
int sharedImplementation(int value) => value + 1;
''');
    write('shared_values/lib/src/other.dart', 'const otherValue = 10;\n');
    for (var index = 0; index < count; index++) {
      final name = _packageName(index);
      final prefix = 'components/$name';
      replace(
        '$prefix/pubspec.yaml',
        'dependencies:\n  ccrouter:',
        'dependencies:\n  shared_values: ^1.0.0\n  ccrouter:',
      );
      for (final kind in [
        'routes',
        'service',
        'command',
        'event',
        'init_task',
      ]) {
        final relative = '$prefix/lib/src/${name}_$kind.dart';
        write(
          relative,
          "import 'package:shared_values/shared_values.dart';\n${file(relative).readAsStringSync()}",
        );
        final source = file(relative).readAsStringSync().replaceAll(
          RegExp(r"description: 'Synthetic[^']*'"),
          'description: sharedDescription',
        );
        write(relative, source);
      }
      replace(
        '$prefix/lib/src/${name}_routes.dart',
        '{required this.id, super.key}',
        '{required this.id, @CCQueryParam() this.revision = sharedDefault, super.key}',
      );
      replace(
        '$prefix/lib/src/${name}_routes.dart',
        'final int id;',
        '/// Initial item identity.\n  final int id;\n  final int revision;',
      );
      replace(
        '$prefix/lib/src/${name}_service.dart',
        'value + $index',
        'sharedImplementation(value)',
      );
    }
    final pubMs = await _pubGet(fixture);
    final cold = await _runGeneration(fixture, noCache: true);
    _expectCatalog(
      cold,
      components: count,
      routes: count * _routesPerComponent,
      packages: count + 1,
    );
    final warm = <Map<String, Object>>[];
    for (var i = 0; i < 3; i++) {
      final run = await _runGeneration(fixture, check: true);
      _expectPlan(run, 'unchanged');
      warm.add(run.toJson());
    }
    final name = _packageName(0);
    final routes = 'components/$name/lib/src/${name}_routes.dart';
    final scenarios = <String, void Function()>{
      'local-trailing-comment': () => write(
        routes,
        '${file(routes).readAsStringSync()}\n// ordinary trailing comment\n',
      ),
      'local-dartdoc': () =>
          replace(routes, 'Initial item identity.', 'Updated item identity.'),
      'local-position': () {
        for (final kind in [
          'routes',
          'service',
          'command',
          'event',
          'init_task',
        ]) {
          final relative = 'components/$name/lib/src/${name}_$kind.dart';
          write(relative, '\n${file(relative).readAsStringSync()}');
        }
      },
      'dependency-implementation': () => replace(
        'shared_values/lib/src/values.dart',
        'value + 1',
        'value + 2',
      ),
      'dependency-constant': () => replace(
        'shared_values/lib/src/values.dart',
        'sharedDefault = 1',
        'sharedDefault = 2',
      ),
      'dependency-description': () => replace(
        'shared_values/lib/src/values.dart',
        'Shared capability description.',
        'Updated capability description.',
      ),
      'dependency-barrel': () => write(
        'shared_values/lib/shared_values.dart',
        "export 'src/other.dart';\nexport 'src/values.dart';\n",
      ),
    };
    final samples = <Map<String, Object?>>[];
    for (final entry in scenarios.entries) {
      final before = await _ArtifactSnapshot.capture(fixture);
      entry.value();
      final run = await _runGeneration(fixture);
      _expectPlan(run, 'runBuilder');
      final after = await _ArtifactSnapshot.capture(fixture);
      final delta = run.attribution['output-delta'] as Map;
      final actualChanges = <String>{...before.files.keys, ...after.files.keys}
          .where(
            (name) =>
                before.files[name] == null ||
                after.files[name] == null ||
                !_bytesEqual(before.files[name]!, after.files[name]!),
          )
          .length;
      if (delta['files'] != actualChanges)
        throw StateError('Output attribution missed changed files.');
      final kinds = delta['artifacts'] as Map;
      int changed(String kind) =>
          (kinds[kind] as Map).values.cast<int>().fold(0, (a, b) => a + b);
      if ([
            'local-trailing-comment',
            'dependency-implementation',
            'dependency-barrel',
          ].contains(entry.key) &&
          (changed('dart') != 0 ||
              changed('metadata') != 0 ||
              changed('documentation') != 0)) {
        throw StateError(
          'Non-generating scenario changed business artifacts: ${entry.key}',
        );
      }
      if (entry.key == 'dependency-constant' && changed('dart') == 0) {
        throw StateError(
          'A consumed default value did not update generated Dart.',
        );
      }
      if ([
            'local-dartdoc',
            'local-position',
            'dependency-description',
          ].contains(entry.key) &&
          changed('metadata') == 0) {
        throw StateError('Documentation/location metadata did not update.');
      }
      final inputs = run.attribution['input-delta'] as Map;
      if (inputs['status'] != 'compared' ||
          (inputs['authored'] as Map)['count'] != 1) {
        throw StateError('Expected one changed source Package.');
      }
      if (entry.key.startsWith('dependency-') &&
          (inputs['resolutionOnly'] as Map)['count'] < count) {
        throw StateError('Shared dependency propagation was not observed.');
      }
      for (final group in [
        'authored',
        'authoredUnavailable',
        'resolution',
        'resolutionOnly',
        'added',
        'removed',
      ]) {
        final values = inputs[group] as Map;
        final names = values['packages'] as List;
        if (names.length > 12 ||
            names.length + (values['omitted'] as int) != values['count']) {
          throw StateError('Attribution truncation lost complete counts.');
        }
      }
      final accuracy = await _verifyReference(fixture);
      samples.add({
        'change': entry.key,
        ...run.toJson(),
        'reference': accuracy.toJson(),
      });
      stderr.writeln(
        'Invalidation ${scale}x ${entry.key}: exact reference passed.',
      );
    }
    succeeded = true;
    return {
      'scenario': 'invalidation-attribution',
      'scale': scale,
      'components': count,
      'capabilities': {
        'routes': count * _routesPerComponent,
        'services': count,
        'commands': count,
        'events': count,
        'initTasks': count,
      },
      'pubMs': pubMs,
      'cold': cold.toJson(),
      'warm': warm,
      'samples': samples,
      'equivalence': 'all managed file names and bytes, with no-cache --check',
    };
  } finally {
    if (succeeded) {
      fixture.deleteSync(recursive: true);
    } else {
      stderr.writeln(
        'Invalidation fixture retained for diagnosis: ${fixture.path}',
      );
    }
  }
}
