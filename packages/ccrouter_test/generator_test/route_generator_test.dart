@TestOn('vm')
library;

import 'dart:convert';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:ccrouter_generator/builder.dart';
import 'package:test/test.dart';

void main() {
  late TestReaderWriter reader;

  setUp(() async {
    reader = TestReaderWriter(
      rootPackage: 'ccrouter_test',
      flattenOutput: true,
    );
    await reader.testing.loadIsolateSources();
  });

  Future<String> generate(String declarations, {bool fails = false}) async {
    final logs = <String>[];
    await testBuilder(
      ccRouteBuilder(BuilderOptions.empty),
      {
        'ccrouter_test|lib/probe.dart':
            "import 'package:ccrouter/ccrouter.dart';\npart 'probe.ccroute.g.dart';\nconst probeComponent = CCComponentDescriptor(id: 'probe', version: '1.0.0');\n$declarations",
      },
      rootPackage: 'ccrouter_test',
      generateFor: {'ccrouter_test|lib/probe.dart'},
      isInput: (id) => id == 'ccrouter_test|lib/probe.dart',
      readerWriter: reader,
      flattenOutput: true,
      onLog: (log) => logs.add(log.message),
    );
    final output = AssetId('ccrouter_test', 'lib/probe.ccroute.g.dart');
    if (fails) {
      expect(await reader.canRead(output), isFalse);
      return logs.join('\n');
    }
    return reader.readAsString(output);
  }

  test('metadata builder emits documented ownership and parameters', () async {
    await testBuilder(
      ccRouteMetadataBuilder(BuilderOptions.empty),
      {
        'ccrouter_test|lib/probe.dart': '''
import 'package:ccrouter/ccrouter.dart';
const probeComponent = CCComponentDescriptor(id: 'probe', version: '1.2.3');
@CCComponent(probeComponent)
final class ProbeRegistrar implements CCComponentRegistrar {
  const ProbeRegistrar();
  @override
  void register(CCRegistry registry) {}
}
@CCRoute<void>(component: probeComponent, id: 'probe.detail', patterns: [CCPathPattern('/probe/:id', primary: true, constraints: {'id': r'\\d+'})], visibility: CCRouteVisibility.exported, description: 'Probe details.')
final class Probe {
  const Probe({required this.id});
  /// Documented identity.
  final int id;
}
''',
      },
      rootPackage: 'ccrouter_test',
      generateFor: {'ccrouter_test|lib/probe.dart'},
      isInput: (id) => id == 'ccrouter_test|lib/probe.dart',
      readerWriter: reader,
      flattenOutput: true,
    );
    final json =
        jsonDecode(
              await reader.readAsString(
                AssetId('ccrouter_test', 'lib/probe.ccroute.json'),
              ),
            )
            as Map;
    final route = (json['routes'] as List).single as Map;
    expect((json['components'] as List).single['version'], '1.2.3');
    expect(route['componentId'], 'probe');
    expect(route['description'], 'Probe details.');
    expect(route['contracts'], {
      'route': 'ProbeRoute',
      'arguments': 'ProbeRouteArguments',
    });
    expect(((route['patterns'] as List).single as Map)['constraints'], {
      'id': r'\d+',
    });
    expect(
      (route['parameters'] as List).single['description'],
      'Documented identity.',
    );
    final markdown = await reader.readAsString(
      AssetId('ccrouter_test', 'lib/probe.ccroute.md'),
    );
    expect(markdown, contains('`probe.detail`'));
    expect(markdown, contains('Documented identity.'));
  });

  test(
    'builder emits a private component contract and backend-neutral registration',
    () async {
      final code = await generate('''
@CCRoute<void>(component: probeComponent, id: 'probe', patterns: [CCPathPattern('/probe/:id', primary: true)])
final class Probe { const Probe({required this.id}); final int id; }
''');
      expect(code, contains('part of'));
      expect(code, contains('abstract final class _ProbeRoute'));
      expect(code, contains('CCRouteIntent<void>'));
      expect(code, contains('registry.registerRoute(definition)'));
      expect(code, isNot(contains('GoRoute(')));
      expect(code, isNot(contains('CCRouter.navigator.push')));
    },
  );

  test(
    'builder emits public contracts only for exported routes and escapes metadata',
    () async {
      final code = await generate(r'''
@CCRoute<String>(component: probeComponent, id: 'probe', patterns: [CCPathPattern('/probe', primary: true)], visibility: CCRouteVisibility.exported, description: r'$secret')
final class Probe { const Probe(); }
''');
      expect(code, contains('abstract final class ProbeRoute'));
      expect(code, contains(r'\$secret'));
    },
  );

  final invalid = <String, (String, String)>{
    'invalid component ID': (
      "const bad = CCComponentDescriptor(id: 'Bad ID', version: '1.0.0'); @CCRoute<void>(component: bad, id: 'probe', patterns: [CCPathPattern('/probe', primary: true)]) final class Probe { const Probe(); }",
      'Component ID',
    ),
    'invalid component version': (
      "const bad = CCComponentDescriptor(id: 'bad', version: 'latest'); @CCRoute<void>(component: bad, id: 'probe', patterns: [CCPathPattern('/probe', primary: true)]) final class Probe { const Probe(); }",
      'semantic version',
    ),
    'invalid component dependencies': (
      "const bad = CCComponentDescriptor(id: 'bad', version: '1.0.0', dependencies: ['bad']); @CCRoute<void>(component: bad, id: 'probe', patterns: [CCPathPattern('/probe', primary: true)]) final class Probe { const Probe(); }",
      'self dependencies',
    ),
    'component route allowlist': (
      "@CCRoute<void>(component: probeComponent, id: 'probe', patterns: [CCPathPattern('/probe', primary: true)], visibleTo: {'consumer'}) final class Probe { const Probe(); }",
      'cannot declare visibleTo',
    ),
    'owner in allowlist': (
      "@CCRoute<void>(component: probeComponent, id: 'probe', patterns: [CCPathPattern('/probe', primary: true)], visibility: CCRouteVisibility.exported, visibleTo: {'probe'}) final class Probe { const Probe(); }",
      'cannot list its owning component',
    ),
    'missing primary': (
      "@CCRoute<void>(component: probeComponent, id: 'probe', patterns: [CCPathPattern('/probe')]) final class Probe { const Probe(); }",
      'exactly one reversible primary',
    ),
    'duplicate primaries': (
      "@CCRoute<void>(component: probeComponent, id: 'probe', patterns: [CCPathPattern('/a', primary: true), CCPathPattern('/b', primary: true)]) final class Probe { const Probe(); }",
      'exactly one reversible primary',
    ),
    'unmapped parameter': (
      "@CCRoute<void>(component: probeComponent, id: 'probe', patterns: [CCPathPattern('/probe', primary: true)]) final class Probe { const Probe(this.value); final int value; }",
      'must be a path capture',
    ),
    'missing constructor capture': (
      "@CCRoute<void>(component: probeComponent, id: 'probe', patterns: [CCPathPattern('/probe/:id', primary: true)]) final class Probe { const Probe(); }",
      'Every path capture',
    ),
    'source conflict': (
      "@CCRoute<void>(component: probeComponent, id: 'probe', patterns: [CCPathPattern('/probe/:id', primary: true)]) final class Probe { const Probe({@CCQueryParam() required this.id}); final int id; }",
      'conflicting route sources',
    ),
    'unsupported query object': (
      "@CCRoute<void>(component: probeComponent, id: 'probe', patterns: [CCPathPattern('/probe', primary: true)]) final class Probe { const Probe({@CCQueryParam() this.value}); final Object? value; }",
      'URI parameters support',
    ),
    'duplicate query keys': (
      "@CCRoute<void>(component: probeComponent, id: 'probe', patterns: [CCPathPattern('/probe', primary: true)]) final class Probe { const Probe({@CCQueryParam(name: 'q') this.a, @CCQueryParam(name: 'q') this.b}); final String? a; final String? b; }",
      'duplicate query key',
    ),
    'required external Extra': (
      "@CCRoute<void>(component: probeComponent, id: 'probe', patterns: [CCPathPattern('/probe', primary: true)], deepLink: CCDeepLinkPolicy.enabled) final class Probe { const Probe({@CCExtraParam() required this.value}); final Object value; }",
      'cannot require in-memory Extra',
    ),
    'multiple Extras': (
      "@CCRoute<void>(component: probeComponent, id: 'probe', patterns: [CCPathPattern('/probe', primary: true)]) final class Probe { const Probe({@CCExtraParam() this.a, @CCExtraParam() this.b}); final Object? a; final Object? b; }",
      'only one Extra',
    ),
    'nullable path': (
      "@CCRoute<void>(component: probeComponent, id: 'probe', patterns: [CCPathPattern('/probe/:id', primary: true)]) final class Probe { const Probe({required this.id}); final int? id; }",
      'Path parameters must be non-nullable',
    ),
    'mismatched aliases': (
      "@CCRoute<void>(component: probeComponent, id: 'probe', patterns: [CCPathPattern('/probe/:id', primary: true), CCPathPattern('/alias/:other')]) final class Probe { const Probe({required this.id}); final int id; }",
      'aliases must capture the same',
    ),
    'bad regex': (
      "@CCRoute<void>(component: probeComponent, id: 'probe', patterns: [CCPathPattern('/probe', primary: true), CCRegexPattern('[')]) final class Probe { const Probe(); }",
      'invalid regular expression',
    ),
    'bad constraint': (
      "@CCRoute<void>(component: probeComponent, id: 'probe', patterns: [CCPathPattern('/probe/:id', primary: true, constraints: {'id': '['})]) final class Probe { const Probe({required this.id}); final int id; }",
      'invalid parameter constraint',
    ),
    'duplicate ID': (
      "@CCRoute<void>(component: probeComponent, id: 'probe', patterns: [CCPathPattern('/a', primary: true)]) final class A { const A(); } @CCRoute<void>(component: probeComponent, id: 'probe', patterns: [CCPathPattern('/b', primary: true)]) final class B { const B(); }",
      'Duplicate route ID',
    ),
    'generated name collision': (
      "@CCRoute<void>(component: probeComponent, id: 'probe', patterns: [CCPathPattern('/a', primary: true)], visibility: CCRouteVisibility.exported) final class A { const A(); } final class ARoute {}",
      'collides',
    ),
    'implicit result type': (
      "@CCRoute(component: probeComponent, id: 'probe', patterns: [CCPathPattern('/a', primary: true)]) final class A { const A(); }",
      'explicitly specify its result type',
    ),
    'generic page': (
      "@CCRoute<void>(component: probeComponent, id: 'probe', patterns: [CCPathPattern('/a', primary: true)]) final class A<T> { const A(); }",
      'non-generic page',
    ),
    'no unnamed constructor': (
      "@CCRoute<void>(component: probeComponent, id: 'probe', patterns: [CCPathPattern('/a', primary: true)]) final class A { const A.named(); }",
      'unnamed generative constructor',
    ),
  };
  for (final entry in invalid.entries) {
    test('builder rejects ${entry.key}', () async {
      expect(
        await generate(entry.value.$1, fails: true),
        contains(entry.value.$2),
      );
    });
  }
}
