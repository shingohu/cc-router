@TestOn('vm')
library;

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
            "import 'package:ccrouter/ccrouter.dart';\npart 'probe.ccroute.g.dart';\n$declarations",
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

  test(
    'builder emits a private component contract and backend-neutral registration',
    () async {
      final code = await generate('''
@CCRoute<void>(id: 'probe', patterns: [CCPathPattern('/probe/:id', primary: true)])
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
@CCRoute<String>(id: 'probe', patterns: [CCPathPattern('/probe', primary: true)], visibility: CCRouteVisibility.exported, description: r'$secret')
final class Probe { const Probe(); }
''');
      expect(code, contains('abstract final class ProbeRoute'));
      expect(code, contains(r'\$secret'));
    },
  );

  final invalid = <String, (String, String)>{
    'missing primary': (
      "@CCRoute<void>(id: 'probe', patterns: [CCPathPattern('/probe')]) final class Probe { const Probe(); }",
      'exactly one reversible primary',
    ),
    'duplicate primaries': (
      "@CCRoute<void>(id: 'probe', patterns: [CCPathPattern('/a', primary: true), CCPathPattern('/b', primary: true)]) final class Probe { const Probe(); }",
      'exactly one reversible primary',
    ),
    'unmapped parameter': (
      "@CCRoute<void>(id: 'probe', patterns: [CCPathPattern('/probe', primary: true)]) final class Probe { const Probe(this.value); final int value; }",
      'must be a path capture',
    ),
    'missing constructor capture': (
      "@CCRoute<void>(id: 'probe', patterns: [CCPathPattern('/probe/:id', primary: true)]) final class Probe { const Probe(); }",
      'Every path capture',
    ),
    'source conflict': (
      "@CCRoute<void>(id: 'probe', patterns: [CCPathPattern('/probe/:id', primary: true)]) final class Probe { const Probe({@CCQueryParam() required this.id}); final int id; }",
      'conflicting route sources',
    ),
    'unsupported query object': (
      "@CCRoute<void>(id: 'probe', patterns: [CCPathPattern('/probe', primary: true)]) final class Probe { const Probe({@CCQueryParam() this.value}); final Object? value; }",
      'URI parameters support',
    ),
    'duplicate query keys': (
      "@CCRoute<void>(id: 'probe', patterns: [CCPathPattern('/probe', primary: true)]) final class Probe { const Probe({@CCQueryParam(name: 'q') this.a, @CCQueryParam(name: 'q') this.b}); final String? a; final String? b; }",
      'duplicate query key',
    ),
    'required external Extra': (
      "@CCRoute<void>(id: 'probe', patterns: [CCPathPattern('/probe', primary: true)], deepLink: CCDeepLinkPolicy.enabled) final class Probe { const Probe({@CCExtraParam() required this.value}); final Object value; }",
      'cannot require in-memory Extra',
    ),
    'multiple Extras': (
      "@CCRoute<void>(id: 'probe', patterns: [CCPathPattern('/probe', primary: true)]) final class Probe { const Probe({@CCExtraParam() this.a, @CCExtraParam() this.b}); final Object? a; final Object? b; }",
      'only one Extra',
    ),
    'nullable path': (
      "@CCRoute<void>(id: 'probe', patterns: [CCPathPattern('/probe/:id', primary: true)]) final class Probe { const Probe({required this.id}); final int? id; }",
      'Path parameters must be non-nullable',
    ),
    'mismatched aliases': (
      "@CCRoute<void>(id: 'probe', patterns: [CCPathPattern('/probe/:id', primary: true), CCPathPattern('/alias/:other')]) final class Probe { const Probe({required this.id}); final int id; }",
      'aliases must capture the same',
    ),
    'bad regex': (
      "@CCRoute<void>(id: 'probe', patterns: [CCPathPattern('/probe', primary: true), CCRegexPattern('[')]) final class Probe { const Probe(); }",
      'invalid regular expression',
    ),
    'bad constraint': (
      "@CCRoute<void>(id: 'probe', patterns: [CCPathPattern('/probe/:id', primary: true, constraints: {'id': '['})]) final class Probe { const Probe({required this.id}); final int id; }",
      'invalid parameter constraint',
    ),
    'duplicate ID': (
      "@CCRoute<void>(id: 'probe', patterns: [CCPathPattern('/a', primary: true)]) final class A { const A(); } @CCRoute<void>(id: 'probe', patterns: [CCPathPattern('/b', primary: true)]) final class B { const B(); }",
      'Duplicate route ID',
    ),
    'generated name collision': (
      "@CCRoute<void>(id: 'probe', patterns: [CCPathPattern('/a', primary: true)], visibility: CCRouteVisibility.exported) final class A { const A(); } final class ARoute {}",
      'collides',
    ),
    'implicit result type': (
      "@CCRoute(id: 'probe', patterns: [CCPathPattern('/a', primary: true)]) final class A { const A(); }",
      'explicitly specify its result type',
    ),
    'generic page': (
      "@CCRoute<void>(id: 'probe', patterns: [CCPathPattern('/a', primary: true)]) final class A<T> { const A(); }",
      'non-generic page',
    ),
    'no unnamed constructor': (
      "@CCRoute<void>(id: 'probe', patterns: [CCPathPattern('/a', primary: true)]) final class A { const A.named(); }",
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
