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
@CCRoute<void>(component: probeComponent, id: 'probe.detail', pattern: CCPathPattern('/probe/:id', constraints: {'id': r'\\d+'}), deepLink: CCDeepLinkPolicy.enabled, presentation: CCPagePresentation(transition: CCPageTransitionType.slideFromBottom, opaque: false), placement: CCRoutePlacement(hostId: 'secondary', parentRouteId: 'probe.root', shellId: 'probe.shell', navigatorOutlet: 'detail'), interceptors: ['probe.auth'], popGuards: ['probe.dirty'], description: 'Probe details.')
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
                  'ccrouter_generated/src/orders/probe.route.json',
                ),
              ),
            )
            as Map;
    final route = (json['routes'] as List).single as Map;
    expect((json['componentDeclarations'] as List), isEmpty);
    expect(json['componentManifests'], isEmpty);
    expect((json['components'] as List).single['version'], '1.2.3');
    expect(route['componentId'], 'probe');
    expect(route['componentVersion'], '1.2.3');
    expect(route['exposure'], 'internal');
    expect(route['description'], 'Probe details.');
    expect(route['interceptorIds'], ['probe.auth']);
    expect(route['popGuardIds'], ['probe.dirty']);
    final declaration = route['declaration'] as Map;
    expect(declaration['package'], 'ccrouter_test');
    expect(declaration['library'], 'lib/src/orders/probe.dart');
    expect(declaration['kind'], 'page');
    expect(declaration['symbol'], 'Probe');
    expect(
      declaration['packageUri'],
      'package:ccrouter_test/src/orders/probe.dart',
    );
    expect(declaration['line'], isA<int>());
    expect(declaration['column'], isA<int>());
    expect(route['navigationSources'], [
      'typedIntent',
      'internalUri',
      'externalDeepLink',
    ]);
    expect(route['restoration'], {'status': 'unsupported'});
    expect(route['placement'], {
      'hostId': 'secondary',
      'parentRouteId': 'probe.root',
      'shellId': 'probe.shell',
      'navigatorOutlet': 'detail',
    });
    expect(route['presentation'], {
      'type': 'page',
      'routeType': 'platformDefault',
      'transition': 'slideFromBottom',
      'opaque': false,
      'fullscreenDialog': false,
    });
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
    expect((route['generatedArtifacts'] as List).single, {
      'role': 'routePart',
      'symbol': '_ProbeRoute',
      'packageUri':
          'package:ccrouter_test/src/ccrouter_generated/orders/probe.route.g.dart',
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
      AssetId('ccrouter_test', 'ccrouter_generated/src/orders/probe.route.md'),
    );
    expect(markdown, contains('`probe.detail`'));
    expect(markdown, contains('Documented identity.'));
    expect(markdown, contains('host `secondary`, outlet `detail`'));
    expect(markdown, contains('Restoration: `unsupported`'));
  });

  test('metadata serializes modal presentation intent', () async {
    await testBuilder(
      ccRouteMetadataBuilder(BuilderOptions.empty),
      {
        'ccrouter_test|lib/src/modal_probe.dart': r'''
import 'package:ccrouter/ccrouter.dart';
const probeComponent = CCComponentDescriptor(id: 'probe', version: '1.0.0');
@CCRoute<void>(component: probeComponent, id: 'probe.sheet', pattern: CCPathPattern('/sheet'), presentation: CCModalBottomSheetPresentation(isDismissible: false, enableDrag: false, isScrollControlled: true, showDragHandle: true, useSafeArea: true))
final class SheetProbe { const SheetProbe(); }
@CCRoute<void>(component: probeComponent, id: 'probe.dialog', pattern: CCPathPattern('/dialog'), presentation: CCDialogPresentation(routeType: CCDialogRouteType.cupertino, barrierDismissible: false, useSafeArea: false))
final class DialogProbe { const DialogProbe(); }
''',
      },
      rootPackage: 'ccrouter_test',
      generateFor: {'ccrouter_test|lib/src/modal_probe.dart'},
      isInput: (id) => id == 'ccrouter_test|lib/src/modal_probe.dart',
      readerWriter: reader,
      flattenOutput: true,
    );
    final json =
        jsonDecode(
              await reader.readAsString(
                AssetId(
                  'ccrouter_test',
                  'ccrouter_generated/src/modal_probe.route.json',
                ),
              ),
            )
            as Map;
    final routes = (json['routes'] as List).cast<Map>();
    final sheet = routes.singleWhere((route) => route['id'] == 'probe.sheet');
    final dialog = routes.singleWhere((route) => route['id'] == 'probe.dialog');
    expect(sheet['presentation'], {
      'type': 'modalBottomSheet',
      'isDismissible': false,
      'enableDrag': false,
      'isScrollControlled': true,
      'showDragHandle': true,
      'useSafeArea': true,
    });
    expect(dialog['presentation'], {
      'type': 'dialog',
      'routeType': 'cupertino',
      'barrierDismissible': false,
      'useSafeArea': false,
    });
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
                  'ccrouter_generated/src/orders/probe_contract.route.json',
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
    expect((route['declaration'] as Map)['symbol'], 'ProbeRouteContract');
    expect((route['generatedArtifacts'] as List).single, {
      'role': 'routeContract',
      'symbol': 'ProbeRoute',
      'packageUri':
          'package:ccrouter_test/src/ccrouter_generated/orders/probe_contract.route.contract.g.dart',
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
                    'ccrouter_generated/src/probe_page.route.json',
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
      expect(
        (implementation['contract'] as Map)['symbol'],
        'ProbeDetailRouteContract',
      );
      expect(
        (implementation['contract'] as Map)['packageUri'],
        'package:ccrouter_test/probe_route_contract.dart',
      );
      expect((implementation['implementation'] as Map)['symbol'], 'ProbePage');
      expect(
        (implementation['implementation'] as Map)['packageUri'],
        'package:ccrouter_test/src/probe_page.dart',
      );
      final markdown = await reader.readAsString(
        AssetId('ccrouter_test', 'ccrouter_generated/src/probe_page.route.md'),
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
                  'ccrouter_generated/src/orders/probe_component.component.json',
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
        'ccrouter_generated/src/orders/probe_component.component.md',
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
@CCRoute<void>(component: probeComponent, id: 'probe', patterns: [CCPathPattern('/probe/:id', primary: true)], popGuards: ['probe.dirty'])
final class Probe { const Probe({required this.id}); final int id; }
''');
      expect(code, contains('part of'));
      expect(code, contains('abstract final class _ProbeRoute'));
      expect(code, contains('CCRouteIntent<void>'));
      expect(code, contains('registry.registerRoute(definition)'));
      expect(code, contains('ccrouterRegisterProbeRoute'));
      expect(code, contains('ccrouterDescribeProbeRoute'));
      expect(code, contains('ccrouterBuildProbeRoute'));
      expect(
        code,
        contains(
          'CCRouteDefinition<dynamic, dynamic> ccrouterDescribeProbeRoute()',
        ),
      );
      expect(code, isNot(contains('CCNavigationRoute(')));
      expect(code, contains('popGuardIds: const ["probe.dirty"]'));
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
    'builder keeps embedded contracts private and documents metadata',
    () async {
      final code = await generate(r'''
@CCRoute<String>(component: probeComponent, id: 'probe', patterns: [CCPathPattern('/probe', primary: true)], description: r'$secret')
final class Probe { const Probe(); }
''');
      expect(code, contains('abstract final class _ProbeRoute'));
      expect(code, contains(r'/// $secret'));
      expect(code, isNot(contains('description:')));
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

  test('builder emits repeated Query codecs for List and Set values', () async {
    final code = await generate(r'''
enum ProbeState { pending, completed }
@CCRoute<void>(component: probeComponent, id: 'probe', pattern: CCPathPattern('/probe'))
final class Probe {
  const Probe({
    @CCQueryParam() required this.tags,
    @CCQueryParam() this.ids = const {2, 1},
    @CCQueryParam() this.states,
  });
  final List<String> tags;
  final Set<int> ids;
  final List<ProbeState>? states;
}
''');
    expect(
      code,
      contains(
        'List<String>.unmodifiable(_values_tags.map((raw_tags) => raw_tags))',
      ),
    );
    expect(code, contains('int.tryParse(raw_ids)'));
    expect(code, contains('"pending" => ProbeState.pending'));
    expect(code, contains('arguments.tags.isEmpty'));
    expect(code, contains('tags = List.unmodifiable(tags)'));
    expect(code, contains('ids = Set.unmodifiable(ids)'));
    expect(code, contains('final values = <String>['));
    expect(code, contains('values.sort()'));
    expect(code, contains('if (arguments.states != null)'));
    expect(code, contains('"states": ['));
  });

  test('builder emits an isolated custom Query codec boundary', () async {
    final code = await generate(r'''
final class ProbeFilter { const ProbeFilter(this.value); final String value; }
final class ProbeFilterCodec implements CCRouteQueryCodec<ProbeFilter> {
  const ProbeFilterCodec();
  @override
  ProbeFilter decode(List<String> values) => ProbeFilter(values.single);
  @override
  List<String> encode(ProbeFilter value) => [value.value];
}
@CCRoute<void>(component: probeComponent, id: 'probe', pattern: CCPathPattern('/probe'))
final class Probe {
  const Probe({@CCQueryParam(codec: ProbeFilterCodec) required this.filter});
  final ProbeFilter filter;
}
''');
    expect(code, contains('return const ProbeFilterCodec().decode('));
    expect(code, contains('List<String>.unmodifiable(_values_filter)'));
    expect(code, contains('const ProbeFilterCodec().encode(arguments.filter)'));
    expect(code, contains('if (values.isEmpty)'));
    expect(code, contains('catch (_)'));
  });

  test(
    'contract builder imports public Query value and codec types once',
    () async {
      final code = await generateContract(
        r'''
@CCRouteContract<void>(component: probeComponent, id: 'probe', pattern: CCPathPattern('/probe'))
abstract class ProbeRouteContract {
  const ProbeRouteContract({@CCQueryParam(codec: ProbeFilterCodec) required this.filter});
  final ProbeFilter filter;
}
''',
        imports: "import 'package:ccrouter_test/probe_filter.dart';",
        additionalAssets: {
          'ccrouter_test|lib/probe_filter.dart': r'''
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
final class ProbeFilter { const ProbeFilter(this.value); final String value; }
final class ProbeFilterCodec implements CCRouteQueryCodec<ProbeFilter> {
  const ProbeFilterCodec();
  @override
  ProbeFilter decode(List<String> values) => ProbeFilter(values.single);
  @override
  List<String> encode(ProbeFilter value) => [value.value];
}
''',
        },
      );
      expect(
        RegExp(
          "import 'package:ccrouter_test/probe_filter.dart' as contract_type_0;",
        ).allMatches(code),
        hasLength(1),
      );
      expect(code, contains('final contract_type_0.ProbeFilter filter'));
      expect(code, contains('const contract_type_0.ProbeFilterCodec().decode'));
    },
  );

  test('metadata documents repeated and custom Query parameters', () async {
    await testBuilder(
      ccRouteMetadataBuilder(BuilderOptions.empty),
      {
        'ccrouter_test|lib/src/query_probe.dart': r'''
import 'package:ccrouter/ccrouter.dart';
const probeComponent = CCComponentDescriptor(id: 'probe', version: '1.0.0');
final class ProbeFilter { const ProbeFilter(); }
final class ProbeFilterCodec implements CCRouteQueryCodec<ProbeFilter> {
  const ProbeFilterCodec();
  @override
  ProbeFilter decode(List<String> values) => const ProbeFilter();
  @override
  List<String> encode(ProbeFilter value) => const ['filter'];
}
@CCRoute<void>(component: probeComponent, id: 'probe', pattern: CCPathPattern('/probe'))
final class Probe {
  const Probe({@CCQueryParam() required this.tags, @CCQueryParam(codec: ProbeFilterCodec) required this.filter});
  final List<String> tags;
  final ProbeFilter filter;
}
''',
      },
      rootPackage: 'ccrouter_test',
      generateFor: {'ccrouter_test|lib/src/query_probe.dart'},
      isInput: (id) => id == 'ccrouter_test|lib/src/query_probe.dart',
      readerWriter: reader,
      flattenOutput: true,
    );
    final json =
        jsonDecode(
              await reader.readAsString(
                AssetId(
                  'ccrouter_test',
                  'ccrouter_generated/src/query_probe.route.json',
                ),
              ),
            )
            as Map;
    final parameters =
        ((json['routes'] as List).single as Map)['parameters'] as List;
    expect(parameters[0]['cardinality'], 'repeated');
    expect(parameters[0].containsKey('codec'), isFalse);
    expect(parameters[1]['cardinality'], 'repeated');
    expect(parameters[1]['codec'], 'ProbeFilterCodec');
    final markdown = await reader.readAsString(
      AssetId('ccrouter_test', 'ccrouter_generated/src/query_probe.route.md'),
    );
    expect(markdown, contains('Cardinality'));
    expect(markdown, contains('ProbeFilterCodec'));
  });

  test(
    'builder supports super formals and mixed constructor parameters',
    () async {
      final code = await generate(r'''
abstract class ProbeBase {
  const ProbeBase(this.id);
  final int id;
}
@CCRoute<void>(component: probeComponent, id: 'probe', pattern: CCPathPattern('/probe/:id'))
final class Probe extends ProbeBase {
  const Probe(super.id, {@CCQueryParam() this.tab = 'summary', @CCQueryParam() this.page = 1});
  final String tab;
  final int page;
}
''');
      expect(
        code,
        contains(
          'Probe(arguments.id, tab: arguments.tab, page: arguments.page)',
        ),
      );
      expect(code, contains('required int id'));
      expect(code, contains("String tab = 'summary'"));
      expect(code, contains('int page = 1'));
    },
  );

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
    'nested query collection': (
      "@CCRoute<void>(component: probeComponent, id: 'probe', pattern: CCPathPattern('/probe')) final class Probe { const Probe({@CCQueryParam() required this.values}); final List<List<String>> values; }",
      'URI parameters support',
    ),
    'nullable query collection element': (
      "@CCRoute<void>(component: probeComponent, id: 'probe', pattern: CCPathPattern('/probe')) final class Probe { const Probe({@CCQueryParam() required this.values}); final List<String?> values; }",
      'URI parameters support',
    ),
    'unsupported query collection element': (
      "@CCRoute<void>(component: probeComponent, id: 'probe', pattern: CCPathPattern('/probe')) final class Probe { const Probe({@CCQueryParam() required this.values}); final Set<Object> values; }",
      'URI parameters support',
    ),
    'query codec without interface': (
      "final class BadCodec { const BadCodec(); } final class Value { const Value(); } @CCRoute<void>(component: probeComponent, id: 'probe', pattern: CCPathPattern('/probe')) final class Probe { const Probe({@CCQueryParam(codec: BadCodec) required this.value}); final Value value; }",
      'must implement CCRouteQueryCodec',
    ),
    'query codec value mismatch': (
      "final class BadCodec implements CCRouteQueryCodec<String> { const BadCodec(); String decode(List<String> values) => ''; List<String> encode(String value) => [value]; } final class Value { const Value(); } @CCRoute<void>(component: probeComponent, id: 'probe', pattern: CCPathPattern('/probe')) final class Probe { const Probe({@CCQueryParam(codec: BadCodec) required this.value}); final Value value; }",
      'must exactly match',
    ),
    'query codec without const no-argument constructor': (
      "final class BadCodec implements CCRouteQueryCodec<Value> { BadCodec(this.seed); final String seed; Value decode(List<String> values) => const Value(); List<String> encode(Value value) => ['value']; } final class Value { const Value(); } @CCRoute<void>(component: probeComponent, id: 'probe', pattern: CCPathPattern('/probe')) final class Probe { const Probe({@CCQueryParam(codec: BadCodec) required this.value}); final Value value; }",
      'const unnamed constructor without parameters',
    ),
    'scalar query with custom codec': (
      "final class BadCodec implements CCRouteQueryCodec<String> { const BadCodec(); String decode(List<String> values) => values.single; List<String> encode(String value) => [value]; } @CCRoute<void>(component: probeComponent, id: 'probe', pattern: CCPathPattern('/probe')) final class Probe { const Probe({@CCQueryParam(codec: BadCodec) required this.value}); final String value; }",
      'only valid for a non-scalar',
    ),
    'collection query with custom codec': (
      "final class BadCodec implements CCRouteQueryCodec<List<String>> { const BadCodec(); List<String> decode(List<String> values) => values; List<String> encode(List<String> value) => value; } @CCRoute<void>(component: probeComponent, id: 'probe', pattern: CCPathPattern('/probe')) final class Probe { const Probe({@CCQueryParam(codec: BadCodec) required this.value}); final List<String> value; }",
      'only valid for a non-scalar',
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
