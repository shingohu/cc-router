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

    replace(
      'pubspec.yaml',
      'workspace:\n',
      'workspace:\n  - shared_values\n  - edge_values\n',
    );
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
    write('edge_values/pubspec.yaml', '''name: edge_values
version: 1.0.0
resolution: workspace
environment:
  sdk: ^3.10.0
''');
    write('edge_values/lib/edge_values.dart', 'const unusedEdgeValue = 1;\n');
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
    final name = _packageName(0);
    final routes = 'components/$name/lib/src/${name}_routes.dart';
    final publicBarrel = 'components/$name/lib/$name.dart';
    final componentExport =
        "export 'src/${name}_component.dart' show ${_componentName(0)};";
    final markerExport =
        "export 'src/${name}_public_marker.dart' show benchmarkPublicMarker0;";
    write(
      'components/$name/lib/src/${name}_public_marker.dart',
      'const benchmarkPublicMarker0 = 0;\n',
    );
    write(publicBarrel, '$componentExport\n$markerExport\n');
    final removableRoute =
        'components/$name/lib/src/${name}_removable_route.dart';
    final capabilityCatalog =
        'components/$name/lib/src/ccrouter_generated/metadata/cc_catalog.md';
    write(removableRoute, '''import 'package:ccrouter/ccrouter.dart';
import 'package:flutter/widgets.dart';

@CCRoute<void>(
  id: 'benchmark.component.removable',
  pattern: CCPathPattern('/benchmark/removable'),
)
final class BenchmarkRemovableRoutePage extends StatelessWidget {
  const BenchmarkRemovableRoutePage({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''');
    final pubMs = await _pubGet(fixture);
    final cold = await _runGeneration(fixture, noCache: true);
    _expectCatalog(
      cold,
      components: count,
      routes: count * _routesPerComponent + 1,
      packages: count + 1,
    );
    var previousAggregationInputFingerprint =
        cold.aggregationInputFingerprint ??
        (throw StateError(
          'Cold generation did not report aggregation inputs.',
        ));
    final warm = <Map<String, Object>>[];
    for (var i = 0; i < 3; i++) {
      final run = await _runGeneration(fixture, check: true);
      _expectPlan(run, 'unchanged');
      warm.add(run.toJson());
    }
    final routesBaseline = file(routes).readAsStringSync();
    write(routes, '$routesBaseline\n// aggregation reuse warm-up\n');
    final aggregationReuseSeed = await _runGeneration(fixture);
    if (aggregationReuseSeed.aggregationInputFingerprint !=
            previousAggregationInputFingerprint ||
        aggregationReuseSeed.aggregationReuseResult != 'miss' ||
        aggregationReuseSeed.aggregationReuseReason != 'state-missing') {
      throw StateError('Aggregation reuse warm-up did not seed full output.');
    }
    write(routes, routesBaseline);
    final aggregationReuseRestore = await _runGeneration(fixture);
    if (aggregationReuseRestore.aggregationInputFingerprint !=
            previousAggregationInputFingerprint ||
        aggregationReuseRestore.aggregationReuseResult != 'hit' ||
        aggregationReuseRestore.aggregationReuseReason != 'verified') {
      throw StateError('Aggregation reuse warm-up restore did not hit.');
    }
    final scenarios = <_InvalidationScenario>[
      _InvalidationScenario(
        'local-trailing-comment',
        changesAggregationInput: false,
        expectedAggregationReuseReason: 'verified',
        apply: () => write(
          routes,
          '${file(routes).readAsStringSync()}\n// ordinary trailing comment\n',
        ),
      ),
      _InvalidationScenario(
        'local-dartdoc',
        changesAggregationInput: true,
        expectedAggregationReuseReason: 'input-changed',
        apply: () =>
            replace(routes, 'Initial item identity.', 'Updated item identity.'),
      ),
      _InvalidationScenario(
        'local-position',
        changesAggregationInput: true,
        expectedAggregationReuseReason: 'input-changed',
        apply: () {
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
      ),
      _InvalidationScenario(
        'dependency-implementation',
        changesAggregationInput: false,
        expectedAggregationReuseReason: 'verified',
        apply: () => replace(
          'shared_values/lib/src/values.dart',
          'value + 1',
          'value + 2',
        ),
      ),
      _InvalidationScenario(
        'dependency-constant',
        changesAggregationInput: false,
        expectedAggregationReuseReason: 'verified',
        apply: () => replace(
          'shared_values/lib/src/values.dart',
          'sharedDefault = 1',
          'sharedDefault = 2',
        ),
      ),
      _InvalidationScenario(
        'dependency-description',
        changesAggregationInput: true,
        expectedAggregationReuseReason: 'input-changed',
        apply: () => replace(
          'shared_values/lib/src/values.dart',
          'Shared capability description.',
          'Updated capability description.',
        ),
      ),
      _InvalidationScenario(
        'dependency-barrel',
        changesAggregationInput: false,
        expectedAggregationReuseReason: 'verified',
        apply: () => write(
          'shared_values/lib/shared_values.dart',
          "export 'src/other.dart';\nexport 'src/values.dart';\n",
        ),
      ),
      _InvalidationScenario(
        'local-public-barrel',
        changesAggregationInput: false,
        expectedAggregationReuseReason: 'verified',
        apply: () => write(publicBarrel, '$markerExport\n$componentExport\n'),
      ),
      _InvalidationScenario(
        'package-dependency-edge',
        changesAggregationInput: true,
        expectedAggregationReuseReason: 'input-changed',
        apply: () async {
          replace(
            'components/$name/pubspec.yaml',
            'dependencies:\n  shared_values:',
            'dependencies:\n  edge_values: ^1.0.0\n  shared_values:',
          );
          await _pubGet(fixture);
        },
      ),
      _InvalidationScenario(
        'aggregation-output-tamper',
        changesAggregationInput: false,
        expectedAggregationReuseReason: 'output-changed',
        expectedInputDeltaStatus: 'unavailable',
        expectedAuthoredChanges: 0,
        apply: () => write(
          capabilityCatalog,
          '${file(capabilityCatalog).readAsStringSync()}\n<!-- tampered -->\n',
        ),
      ),
      _InvalidationScenario(
        'local-declaration-delete',
        changesAggregationInput: true,
        expectedAggregationReuseReason: 'input-changed',
        apply: () => file(removableRoute).deleteSync(),
      ),
    ];
    final samples = <Map<String, Object?>>[];
    for (final scenario in scenarios) {
      await scenario.apply();
      final before = await _ArtifactSnapshot.capture(fixture);
      final run = await _runGeneration(fixture);
      _expectPlan(run, 'runBuilder');
      final aggregationInputFingerprint =
          run.aggregationInputFingerprint ??
          (throw StateError(
            '${scenario.name} did not report aggregation inputs.',
          ));
      final aggregationInputChanged =
          aggregationInputFingerprint != previousAggregationInputFingerprint;
      if (aggregationInputChanged != scenario.changesAggregationInput) {
        throw StateError(
          '${scenario.name} aggregation input changed '
          '$aggregationInputChanged; expected '
          '${scenario.changesAggregationInput}.',
        );
      }
      final expectedReuseResult =
          scenario.expectedAggregationReuseReason == 'verified'
          ? 'hit'
          : 'miss';
      if (run.aggregationReuseResult != expectedReuseResult ||
          run.aggregationReuseReason !=
              scenario.expectedAggregationReuseReason) {
        throw StateError(
          '${scenario.name} aggregation reuse was '
          '${run.aggregationReuseResult}/${run.aggregationReuseReason}; '
          'expected $expectedReuseResult/'
          '${scenario.expectedAggregationReuseReason}.',
        );
      }
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
            'local-public-barrel',
            'package-dependency-edge',
          ].contains(scenario.name) &&
          (changed('dart') != 0 ||
              changed('metadata') != 0 ||
              changed('documentation') != 0)) {
        throw StateError(
          'Non-generating scenario changed business artifacts: '
          '${scenario.name}',
        );
      }
      if (scenario.name == 'dependency-constant' && changed('dart') == 0) {
        throw StateError(
          'A consumed default value did not update generated Dart.',
        );
      }
      if ([
            'local-dartdoc',
            'local-position',
            'dependency-description',
          ].contains(scenario.name) &&
          changed('metadata') == 0) {
        throw StateError('Documentation/location metadata did not update.');
      }
      final inputs = run.attribution['input-delta'] as Map;
      if (inputs['status'] != scenario.expectedInputDeltaStatus) {
        throw StateError(
          'Expected input delta ${scenario.expectedInputDeltaStatus} for '
          '${scenario.name}, got ${inputs['status']}.',
        );
      }
      if (inputs['status'] == 'compared') {
        if ((inputs['authored'] as Map)['count'] !=
            scenario.expectedAuthoredChanges) {
          throw StateError(
            'Expected ${scenario.expectedAuthoredChanges} changed source '
            'Package(s) for ${scenario.name}.',
          );
        }
        if (scenario.name.startsWith('dependency-') &&
            (inputs['resolutionOnly'] as Map)['count'] < count) {
          throw StateError('Shared dependency propagation was not observed.');
        }
        if (scenario.name == 'package-dependency-edge') {
          final added = inputs['added'] as Map;
          if (inputs['hostGraphChanged'] != true ||
              !(added['packages'] as List).contains('edge_values')) {
            throw StateError('Package dependency edge was not attributed.');
          }
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
      }
      if (scenario.name == 'local-declaration-delete' &&
          (kinds['dart'] as Map)['removed'] == 0) {
        throw StateError('Deleted declaration left stale Builder Dart.');
      }
      if (scenario.name == 'local-declaration-delete') {
        _expectCatalog(
          run,
          components: count,
          routes: count * _routesPerComponent,
          packages: count + 1,
        );
      }
      final accuracy = await _verifyReference(
        fixture,
        expectedAggregationInputFingerprint: aggregationInputFingerprint,
      );
      samples.add({
        'change': scenario.name,
        'aggregationInput': {
          'before': previousAggregationInputFingerprint,
          'after': aggregationInputFingerprint,
          'changed': aggregationInputChanged,
          'expectedChanged': scenario.changesAggregationInput,
        },
        'aggregationReuse': {
          'result': run.aggregationReuseResult,
          'reason': run.aggregationReuseReason,
        },
        ...run.toJson(),
        'reference': accuracy.toJson(),
      });
      previousAggregationInputFingerprint = aggregationInputFingerprint;
      stderr.writeln(
        'Invalidation ${scale}x ${scenario.name}: exact reference passed.',
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
      'aggregationReuseWarmup': {
        'seed': aggregationReuseSeed.toJson(),
        'restore': aggregationReuseRestore.toJson(),
      },
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

final class _InvalidationScenario {
  const _InvalidationScenario(
    this.name, {
    required this.changesAggregationInput,
    required this.expectedAggregationReuseReason,
    this.expectedInputDeltaStatus = 'compared',
    this.expectedAuthoredChanges = 1,
    required this.apply,
  });

  final String name;
  final bool changesAggregationInput;
  final String expectedAggregationReuseReason;
  final String expectedInputDeltaStatus;
  final int expectedAuthoredChanges;
  final FutureOr<void> Function() apply;
}
