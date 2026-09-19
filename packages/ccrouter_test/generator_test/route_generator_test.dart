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

  Future<String> generate(
    String declarations, {
    bool fails = false,
    String imports = '',
    Map<String, String> additionalAssets = const {},
    String sourcePath = 'lib/src/probe.dart',
    String partUri = 'ccrouter_generated/probe.route.g.dart',
    String outputPath = 'lib/src/ccrouter_generated/probe.route.g.dart',
  }) async {
    final logs = <String>[];
    await testBuilder(
      ccRouteBuilder(BuilderOptions.empty),
      {
        ...additionalAssets,
        'ccrouter_test|$sourcePath':
            "import 'package:ccrouter/ccrouter.dart';\n$imports\npart '$partUri';\nconst probeComponent = CCComponentDescriptor(id: 'probe', version: '1.0.0');\n$declarations",
      },
      rootPackage: 'ccrouter_test',
      generateFor: {'ccrouter_test|$sourcePath'},
      isInput: (id) => id == 'ccrouter_test|$sourcePath',
      readerWriter: reader,
      flattenOutput: true,
      onLog: (log) => logs.add(log.message),
    );
    final output = AssetId('ccrouter_test', outputPath);
    if (fails) {
      expect(await reader.canRead(output), isFalse);
      return logs.join('\n');
    }
    return reader.readAsString(output);
  }

  Future<String> generateContract(
    String declarations, {
    bool fails = false,
    String imports = '',
    Map<String, String> additionalAssets = const {},
  }) async {
    final logs = <String>[];
    const sourcePath = 'lib/src/probe.dart';
    const outputPath = 'lib/src/ccrouter_generated/probe.route.contract.g.dart';
    await testBuilder(
      ccRouteContractBuilder(BuilderOptions.empty),
      {
        ...additionalAssets,
        'ccrouter_test|$sourcePath':
            "import 'package:ccrouter/ccrouter.dart';\n$imports\nconst probeComponent = CCComponentDescriptor(id: 'probe', version: '1.0.0');\n$declarations",
      },
      rootPackage: 'ccrouter_test',
      generateFor: {'ccrouter_test|$sourcePath'},
      isInput: (id) => id == 'ccrouter_test|$sourcePath',
      readerWriter: reader,
      flattenOutput: true,
      onLog: (log) => logs.add(log.message),
    );
    final output = AssetId('ccrouter_test', outputPath);
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
        'ccrouter_test|lib/src/orders/probe.dart': '''
import 'package:ccrouter/ccrouter.dart';
const probeComponent = CCComponentDescriptor(id: 'probe', version: '1.2.3');
@CCComponent(probeComponent)
final class ProbeRegistrar implements CCComponentRegistrar {
  const ProbeRegistrar();
  @override
  void register(CCRegistry registry) {}
}
@CCRoute<void>(component: probeComponent, id: 'probe.detail', pattern: CCPathPattern('/probe/:id', constraints: {'id': r'\\d+'}), description: 'Probe details.')
final class Probe {
  const Probe({required this.id});
  /// Documented identity.
  final int id;
}
''',
      },
      rootPackage: 'ccrouter_test',
      generateFor: {'ccrouter_test|lib/src/orders/probe.dart'},
      isInput: (id) => id == 'ccrouter_test|lib/src/orders/probe.dart',
      readerWriter: reader,
      flattenOutput: true,
    );
    final json =
        jsonDecode(
              await reader.readAsString(
                AssetId(
                  'ccrouter_test',
                  'ccrouter_generated/metadata/src/orders/probe.route.json',
                ),
              ),
            )
            as Map;
    final route = (json['routes'] as List).single as Map;
    expect((json['componentDeclarations'] as List), isEmpty);
    expect(json['componentManifests'], isEmpty);
    expect((json['components'] as List).single['version'], '1.2.3');
    expect(route['componentId'], 'probe');
    expect(route['exposure'], 'internal');
    expect(route['description'], 'Probe details.');
    expect(route['contracts'], {
      'route': '_ProbeRoute',
      'arguments': '_ProbeRouteArguments',
      'package': 'ccrouter_test',
      'library': 'lib/src/orders/probe.dart',
    });
    expect(route['registration'], 'ccrouterRegisterProbeRoute');
    expect(route['destination'], {
      'descriptor': 'ccrouterDescribeProbeRoute',
      'builder': 'ccrouterBuildProbeRoute',
    });
    expect(((route['patterns'] as List).single as Map)['constraints'], {
      'id': r'\d+',
    });
    expect(((route['patterns'] as List).single as Map)['primary'], isTrue);
    expect(
      (route['parameters'] as List).single['description'],
      'Documented identity.',
    );
    final markdown = await reader.readAsString(
      AssetId(
        'ccrouter_test',
        'ccrouter_generated/metadata/src/orders/probe.route.md',
      ),
    );
    expect(markdown, contains('`probe.detail`'));
    expect(markdown, contains('Documented identity.'));
  });

  test('metadata records the public contract library', () async {
    await testBuilder(
      ccRouteMetadataBuilder(BuilderOptions.empty),
      {
        'ccrouter_test|lib/src/orders/probe_contract.dart': '''
import 'package:ccrouter/ccrouter.dart';
const probeComponent = CCComponentDescriptor(id: 'probe', version: '1.0.0');
@CCRouteContract<void>(component: probeComponent, id: 'probe.public', pattern: CCPathPattern('/probe'))
abstract class ProbeRouteContract { const ProbeRouteContract(); }
''',
      },
      rootPackage: 'ccrouter_test',
      generateFor: {'ccrouter_test|lib/src/orders/probe_contract.dart'},
      isInput: (id) => id == 'ccrouter_test|lib/src/orders/probe_contract.dart',
      readerWriter: reader,
      flattenOutput: true,
    );
    final json =
        jsonDecode(
              await reader.readAsString(
                AssetId(
                  'ccrouter_test',
                  'ccrouter_generated/metadata/src/orders/probe_contract.route.json',
                ),
              ),
            )
            as Map;
    final route = (json['routes'] as List).single as Map;
    expect(route['exposure'], 'public');
    expect(route['contracts'], {
      'route': 'ProbeRoute',
      'arguments': 'ProbeRouteArguments',
      'package': 'ccrouter_test',
      'library':
          'lib/src/ccrouter_generated/orders/probe_contract.route.contract.g.dart',
    });
  });

  test(
    'metadata separates an external contract from its page binding',
    () async {
      await testBuilder(
        ccRouteMetadataBuilder(BuilderOptions.empty),
        {
          'ccrouter_test|lib/probe_route_contract.dart': r'''
import 'package:ccrouter/ccrouter.dart';
const probeOwner = CCComponentDescriptor(id: 'probe', version: '1.0.0');
@CCRouteContract<void>(component: probeOwner, id: 'probe.detail', pattern: CCPathPattern('/probe/:id'))
abstract class ProbeDetailRouteContract {
  const ProbeDetailRouteContract({required this.id});
  final int id;
}
''',
          'ccrouter_test|lib/src/probe_page.dart': r'''
import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter_test/probe_route_contract.dart';
@CCRouteImplementation(ProbeDetailRouteContract)
final class ProbePage {
  const ProbePage({required this.id});
  final int id;
}
''',
        },
        rootPackage: 'ccrouter_test',
        generateFor: {'ccrouter_test|lib/src/probe_page.dart'},
        isInput: (id) => id == 'ccrouter_test|lib/src/probe_page.dart',
        readerWriter: reader,
        flattenOutput: true,
      );
      final json =
          jsonDecode(
                await reader.readAsString(
                  AssetId(
                    'ccrouter_test',
                    'ccrouter_generated/metadata/src/probe_page.route.json',
                  ),
                ),
              )
              as Map;
      expect(json['routes'], isEmpty);
      final implementation =
          (json['routeImplementations'] as List).single as Map;
      expect(implementation['routeId'], 'probe.detail');
      expect(implementation['componentId'], 'probe');
      expect(implementation['package'], 'ccrouter_test');
      expect(implementation['source'], 'lib/src/probe_page.dart');
      expect(implementation['registration'], 'ccrouterRegisterProbePageRoute');
      final markdown = await reader.readAsString(
        AssetId(
          'ccrouter_test',
          'ccrouter_generated/metadata/src/probe_page.route.md',
        ),
      );
      expect(markdown, contains('Route Implementations'));
      expect(markdown, contains('ccrouter_test:lib/src/probe_page.dart'));
    },
  );

  test('component metadata builder emits identity and dependencies', () async {
    await testBuilder(
      ccComponentMetadataBuilder(BuilderOptions.empty),
      {
        'ccrouter_test|lib/src/orders/probe_component.dart': '''
import 'package:ccrouter/ccrouter.dart';
const probeComponent = CCComponentDescriptor(
  id: 'probe',
  version: '1.2.3',
  dependencies: ['accounts'],
  optionalDependencies: ['analytics'],
);
@CCComponent(probeComponent)
final class ProbeRegistrar implements CCComponentRegistrar {
  const ProbeRegistrar();
  @override
  void register(CCRegistry registry) {}
}
''',
      },
      rootPackage: 'ccrouter_test',
      generateFor: {'ccrouter_test|lib/src/orders/probe_component.dart'},
      isInput: (id) =>
          id == 'ccrouter_test|lib/src/orders/probe_component.dart',
      readerWriter: reader,
      flattenOutput: true,
    );
    final json =
        jsonDecode(
              await reader.readAsString(
                AssetId(
                  'ccrouter_test',
                  'ccrouter_generated/metadata/src/orders/probe_component.component.json',
                ),
              ),
            )
            as Map;
    expect(json['componentDeclarations'], ['probe']);
    expect(json['componentManifests'], {'probe': 'probeManifest'});
    expect((json['routes'] as List), isEmpty);
    expect((json['components'] as List).single, {
      'id': 'probe',
      'version': '1.2.3',
      'dependencies': ['accounts'],
      'optionalDependencies': ['analytics'],
    });
    final markdown = await reader.readAsString(
      AssetId(
        'ccrouter_test',
        'ccrouter_generated/metadata/src/orders/probe_component.component.md',
      ),
    );
    expect(markdown, contains('# CCRouter Components'));
    expect(markdown, contains('`accounts`'));
  });

  test(
    'component builder generates a Manifest for a private Registrar',
    () async {
      await testBuilder(
        ccComponentBuilder(BuilderOptions.empty),
        {
          'ccrouter_test|lib/src/probe_component_registrar.dart': '''
import 'package:ccrouter/ccrouter.dart';
part 'ccrouter_generated/probe_component_registrar.component.g.dart';
const probeComponent = CCComponentDescriptor(
  id: 'probe_component',
  version: '1.2.3',
  dependencies: ['account'],
  optionalDependencies: ['analytics'],
);
@CCComponent(probeComponent)
final class _ProbeComponentRegistrar implements CCComponentRegistrar {
  const _ProbeComponentRegistrar();
  @override
  void register(CCRegistry registry) {}
}
''',
        },
        rootPackage: 'ccrouter_test',
        generateFor: {'ccrouter_test|lib/src/probe_component_registrar.dart'},
        isInput: (id) =>
            id == 'ccrouter_test|lib/src/probe_component_registrar.dart',
        readerWriter: reader,
        flattenOutput: true,
      );
      final code = await reader.readAsString(
        AssetId(
          'ccrouter_test',
          'lib/src/ccrouter_generated/probe_component_registrar.component.g.dart',
        ),
      );
      expect(code, contains('const probeComponentManifest'));
      expect(code, contains('id: "probe_component"'));
      expect(code, contains('dependencies: const ["account"]'));
      expect(code, contains('optionalDependencies: const ["analytics"]'));
      expect(code, contains('registrar: _ProbeComponentRegistrar()'));
    },
  );

  test(
    'component builder rejects a Registrar without a const constructor',
    () async {
      final logs = <String>[];
      await testBuilder(
        ccComponentBuilder(BuilderOptions.empty),
        {
          'ccrouter_test|lib/src/invalid_component_registrar.dart': '''
import 'package:ccrouter/ccrouter.dart';
part 'ccrouter_generated/invalid_component_registrar.component.g.dart';
const invalidComponent = CCComponentDescriptor(
  id: 'invalid_component',
  version: '1.0.0',
);
@CCComponent(invalidComponent)
final class _InvalidComponentRegistrar implements CCComponentRegistrar {
  _InvalidComponentRegistrar();
  @override
  void register(CCRegistry registry) {}
}
''',
        },
        rootPackage: 'ccrouter_test',
        generateFor: {'ccrouter_test|lib/src/invalid_component_registrar.dart'},
        isInput: (id) =>
            id == 'ccrouter_test|lib/src/invalid_component_registrar.dart',
        readerWriter: reader,
        flattenOutput: true,
        onLog: (log) => logs.add(log.message),
      );
      expect(
        await reader.canRead(
          AssetId(
            'ccrouter_test',
            'lib/src/ccrouter_generated/invalid_component_registrar.component.g.dart',
          ),
        ),
        isFalse,
      );
      expect(logs.join('\n'), contains('const unnamed Registrar constructor'));
    },
  );

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
      expect(code, contains('ccrouterRegisterProbeRoute'));
      expect(code, contains('ccrouterDescribeProbeRoute'));
      expect(code, contains('ccrouterBuildProbeRoute'));
      expect(code, contains('CCNavigationRoute('));
      expect(code, isNot(contains('GoRoute(')));
      expect(code, isNot(contains('CCRouter.navigator.push')));
    },
  );

  test('infers the sole reversible primary in a Pattern list', () async {
    final code = await generate(r'''
@CCRoute<void>(component: probeComponent, id: 'probe', patterns: [CCRegexPattern(r'/legacy'), CCPathPattern('/probe')])
final class Probe { const Probe(); }
''');
    expect(code, contains('primary: true'));
    expect(code, contains('const CCRegexPattern("/legacy")'));
  });

  test('preserves nested source directories in generated route paths', () async {
    final code = await generate(
      "@CCRoute<void>(component: probeComponent, id: 'probe', pattern: CCPathPattern('/probe')) final class Probe { const Probe(); }",
      sourcePath: 'lib/src/orders/probe.dart',
      partUri: '../ccrouter_generated/orders/probe.route.g.dart',
      outputPath: 'lib/src/ccrouter_generated/orders/probe.route.g.dart',
    );
    expect(code, contains("part of '../../orders/probe.dart'"));
    expect(code, contains('abstract final class _ProbeRoute'));
  });

  test(
    'builder keeps embedded contracts private and escapes metadata',
    () async {
      final code = await generate(r'''
@CCRoute<String>(component: probeComponent, id: 'probe', patterns: [CCPathPattern('/probe', primary: true)], description: r'$secret')
final class Probe { const Probe(); }
''');
      expect(code, contains('abstract final class _ProbeRoute'));
      expect(code, contains(r'\$secret'));
    },
  );

  test('contract builder emits a standalone Pure Dart contract', () async {
    final code = await generateContract(r'''
@CCRouteContract<String>(component: probeComponent, id: 'probe', pattern: CCPathPattern('/probe/:id'))
abstract class ProbeRouteContract { const ProbeRouteContract({required this.id, @CCQueryParam() this.tab = 'summary'}); final int id; final String tab; }
''');
    expect(
      code,
      contains("import 'package:ccrouter_contracts/ccrouter_contracts.dart';"),
    );
    expect(code, contains('final class ProbeRouteArguments'));
    expect(code, contains('abstract final class ProbeRoute'));
    expect(code, contains('CCRouteIntent<String>'));
    expect(code, contains('CCRouteDefinition<ProbeRouteArguments, String>'));
    expect(code, contains('final class _ProbeRouteCodec'));
    expect(code, isNot(contains('CCRegistry')));
    expect(code, isNot(contains('static Probe build')));
    expect(code, isNot(contains("package:flutter/")));
  });

  test('contract builder emits nothing for the embedded default', () async {
    final logs = await generateContract(r'''
@CCRoute<void>(component: probeComponent, id: 'probe', pattern: CCPathPattern('/probe'))
final class Probe { const Probe(); }
''', fails: true);
    expect(logs, isNot(contains('InvalidGenerationSourceError')));
  });

  test('contract builder emits a Contract-first Pure Dart API', () async {
    final code = await generateContract(r'''
@CCRouteContract<String>(
  component: probeComponent,
  id: 'probe.detail',
  pattern: CCPathPattern('/probe/:id'),
)
abstract class ProbeDetailRouteContract {
  const ProbeDetailRouteContract({required this.id, @CCQueryParam() this.tab = 'summary'});
  final int id;
  final String tab;
}
''');
    expect(code, contains('final class ProbeDetailRouteArguments'));
    expect(code, contains('abstract final class ProbeDetailRoute'));
    expect(code, contains('CCRouteIntent<String>'));
    expect(code, isNot(contains('CCRouteVisibility')));
    expect(code, isNot(contains('visibleTo')));
    expect(code, isNot(contains('CCRegistry')));
  });

  test(
    'page builder binds a Contract-first route without duplicating it',
    () async {
      final code = await generate(
        r'''
@CCRouteImplementation(ProbeDetailRouteContract)
final class ProbePage {
  const ProbePage({required this.id, required this.tab});
  final int id;
  final String tab;
}
''',
        imports: "import 'package:ccrouter_test/probe_route_contract.dart';",
        additionalAssets: {
          'ccrouter_test|lib/probe_route_contract.dart': r'''
import 'package:ccrouter/ccrouter.dart';
const probeOwner = CCComponentDescriptor(id: 'probe', version: '1.0.0');
@CCRouteContract<String>(component: probeOwner, id: 'probe.detail', pattern: CCPathPattern('/probe/:id'))
abstract class ProbeDetailRouteContract {
  const ProbeDetailRouteContract({required this.id, @CCQueryParam() this.tab = 'summary'});
  final int id;
  final String tab;
}
abstract final class ProbeDetailRoute {
  static final definition = CCRouteDefinition<ProbeDetailRouteArguments, String>(
    routeId: 'probe.detail',
    patterns: const [CCPathPattern('/probe/:id', primary: true)],
    codec: const _ProbeCodec(),
  );
}
final class ProbeDetailRouteArguments {
  const ProbeDetailRouteArguments({required this.id, required this.tab});
  final int id;
  final String tab;
}
final class _ProbeCodec implements CCRouteCodec<ProbeDetailRouteArguments> {
  const _ProbeCodec();
  @override
  ProbeDetailRouteArguments decode(CCEncodedRouteArguments input) => throw UnimplementedError();
  @override
  CCEncodedRouteArguments encode(ProbeDetailRouteArguments arguments) => throw UnimplementedError();
}
''',
        },
      );
      expect(
        code,
        contains('registry.registerRoute(ProbeDetailRoute.definition)'),
      );
      expect(
        code,
        contains('final decoded = ProbeDetailRoute.definition.codec'),
      );
      expect(code, contains('return ProbePage('));
      expect(code, contains('id: decoded.id'));
      expect(code, contains('tab: decoded.tab'));
      expect(code, isNot(contains('final class ProbeDetailRouteArguments')));
    },
  );

  test('page builder rejects a Contract-first constructor mismatch', () async {
    final logs = await generate(
      r'''
@CCRouteImplementation(ProbeDetailRouteContract)
final class ProbePage {
  const ProbePage({required this.other});
  final int other;
}
''',
      imports: "import 'package:ccrouter_test/probe_route_contract.dart';",
      additionalAssets: {
        'ccrouter_test|lib/probe_route_contract.dart': r'''
import 'package:ccrouter/ccrouter.dart';
const probeOwner = CCComponentDescriptor(id: 'probe', version: '1.0.0');
@CCRouteContract<void>(component: probeOwner, id: 'probe.detail', pattern: CCPathPattern('/probe/:id'))
abstract class ProbeDetailRouteContract {
  const ProbeDetailRouteContract({required this.id});
  final int id;
}
''',
      },
      fails: true,
    );
    expect(logs, contains('does not match contract parameter'));
  });

  test('contract builder rejects page-library contract types', () async {
    final logs = await generateContract(r'''
enum ProbeResult { accepted }
@CCRouteContract<ProbeResult>(component: probeComponent, id: 'probe', pattern: CCPathPattern('/probe'))
abstract class ProbeRouteContract { const ProbeRouteContract(); }
''', fails: true);
    expect(logs, contains('cannot be declared beside the route source'));
  });

  test('contract builder rejects Flutter contract types', () async {
    final logs = await generateContract(
      r'''
@CCRouteContract<void>(component: probeComponent, id: 'probe', pattern: CCPathPattern('/probe'))
abstract class ProbeRouteContract { const ProbeRouteContract({@CCExtraParam() this.color}); final Color? color; }
''',
      imports: "import 'package:flutter/material.dart';",
      fails: true,
    );
    expect(logs, contains('cannot depend on Flutter'));
  });

  test('contract builder preserves public imported contract types', () async {
    final code = await generateContract(
      r'''
@CCRouteContract<ProbeResult>(component: probeComponent, id: 'probe', pattern: CCPathPattern('/probe'))
abstract class ProbeRouteContract { const ProbeRouteContract({@CCExtraParam() this.payload, @CCQueryParam() this.status = ProbeStatus.pending}); final ProbePayload? payload; final ProbeStatus status; }
''',
      imports: "import 'package:ccrouter_test/probe_contract.dart';",
      additionalAssets: {
        'ccrouter_test|lib/probe_contract.dart': '''
enum ProbeResult { accepted }
enum ProbeStatus { pending, completed }
final class ProbePayload { const ProbePayload(); }
''',
      },
    );
    expect(
      code,
      contains(
        "import 'package:ccrouter_test/probe_contract.dart' as contract_type_0;",
      ),
    );
    expect(code, contains('CCRouteIntent<contract_type_0.ProbeResult>'));
    expect(code, contains('final contract_type_0.ProbePayload? payload'));
    expect(code, contains('this.status = contract_type_0.ProbeStatus.pending'));
  });

  test(
    'contract builder reuses the unprefixed framework contract import',
    () async {
      final code = await generateContract(r'''
@CCRouteContract<CCNavigationSource>(component: probeComponent, id: 'probe', pattern: CCPathPattern('/probe'))
abstract class ProbeRouteContract { const ProbeRouteContract(); }
''', imports: "import 'package:ccrouter_contracts/ccrouter_contracts.dart';");
      expect(code, contains('CCRouteIntent<CCNavigationSource>'));
      expect(
        RegExp(
          "import 'package:ccrouter_contracts/ccrouter_contracts.dart';",
        ).allMatches(code),
        hasLength(1),
      );
    },
  );

  test('builder rejects registration bridge name collisions', () async {
    final logs = await generate(r'''
void ccrouterRegisterProbeRoute(CCRegistry registry) {}
@CCRoute<void>(component: probeComponent, id: 'probe', pattern: CCPathPattern('/probe'))
final class Probe { const Probe(); }
''', fails: true);
    expect(logs, contains('Generated declaration'));
  });

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
    'ambiguous inferred primary': (
      "@CCRoute<void>(component: probeComponent, id: 'probe', patterns: [CCPathPattern('/probe'), CCPathPattern('/legacy')]) final class Probe { const Probe(); }",
      'multiple reversible patterns',
    ),
    'duplicate primaries': (
      "@CCRoute<void>(component: probeComponent, id: 'probe', patterns: [CCPathPattern('/a', primary: true), CCPathPattern('/b', primary: true)]) final class Probe { const Probe(); }",
      'exactly one reversible primary',
    ),
    'single and plural patterns': (
      "@CCRoute<void>(component: probeComponent, id: 'probe', pattern: CCPathPattern('/probe'), patterns: [CCPathPattern('/legacy')]) final class Probe { const Probe(); }",
      'cannot set both pattern and patterns',
    ),
    'missing patterns': (
      "@CCRoute<void>(component: probeComponent, id: 'probe') final class Probe { const Probe(); }",
      'must set pattern or patterns',
    ),
    'single regex pattern': (
      "@CCRoute<void>(component: probeComponent, id: 'probe', pattern: CCRegexPattern('/probe')) final class Probe { const Probe(); }",
      'Regex patterns are match-only',
    ),
    'regex-only pattern list': (
      "@CCRoute<void>(component: probeComponent, id: 'probe', patterns: [CCRegexPattern('/probe')]) final class Probe { const Probe(); }",
      'Regex patterns are match-only',
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
      "@CCRoute<void>(component: probeComponent, id: 'probe', patterns: [CCPathPattern('/a', primary: true)]) final class A { const A(); } final class _ARoute {}",
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
