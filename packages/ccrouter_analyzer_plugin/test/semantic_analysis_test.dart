import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:analyzer_plugin/channel/channel.dart';
import 'package:analyzer_plugin/protocol/protocol.dart';
import 'package:analyzer_plugin/protocol/protocol_common.dart';
import 'package:analyzer_plugin/protocol/protocol_generated.dart';
import 'package:ccrouter_analyzer_plugin/src/plugin.dart';
import 'package:ccrouter_analyzer_plugin/src/contract_owner_index.dart';
import 'package:ccrouter_analyzer_plugin/src/quick_fixes.dart';
import 'package:ccrouter_analyzer_plugin/src/source_analyzer.dart'
    show CCRouterAnalyzerDiagnostic, CCRouterSourceAnalyzer;
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  late _Fixture fixture;
  setUp(() => fixture = _Fixture());
  tearDown(() => fixture.dispose());

  test(
    'canonical Contract placement diagnoses without rejecting factory values',
    () async {
      final result = await fixture.resolve('''
import 'package:ccrouter_contracts/ccrouter_contracts.dart' as cc;
typedef Placement = cc.CCRoutePlacement;
@cc.CCRouteContract<void>(componentId: cc.CCComponentId('consumer'),
  id: 'sample.home', pattern: cc.CCPathPattern('/'),
  placement: Placement(hostId: 'Bad Host'),
  popGuards: ['dirty.check', 'dirty.check'])
abstract class HomeRouteContract {}
''');
      final codes = fixture.diagnostics(result).map((d) => d.code);
      expect(
        result.diagnostics.where(
          (d) => d.diagnosticCode.severity.name == 'ERROR',
        ),
        isEmpty,
      );
      expect(codes, contains('ccrouter_route_placement_invalid'));
      expect(codes, contains('ccrouter_route_policy_duplicate'));
    },
  );

  test(
    'resolved foreign constructors and computed placement values defer',
    () async {
      final result = await fixture.resolve('''
import 'package:ccrouter_contracts/ccrouter_contracts.dart' as cc;
const placement = cc.CCRoutePlacement(hostId: 'Bad Host');
cc.CCRoutePlacement makePlacement({String hostId = ''}) => placement;
@cc.CCRoute<void>(id: 'a', pattern: cc.CCPathPattern('/a'), placement: placement)
class A {}
@cc.CCRoute<void>(id: 'b', pattern: cc.CCPathPattern('/b'), placement: makePlacement(hostId: 'Bad Host'))
class B {}
''');
      expect(
        fixture
            .diagnostics(result)
            .where((d) => d.code.startsWith('ccrouter_route_')),
        isEmpty,
      );
    },
  );

  test(
    'prefixed and transitive lifecycle references retain framework identity',
    () async {
      final result = await fixture.resolve('''
import 'package:owner_contracts/lifecycle.dart' as root;
Future<void> stop() async {
  root.CCRouterHost.initialize();
  final stop = root.CCRouterHost.shutdown;
  await stop();
  await root.CCRouterHost.runInitTasks();
}
''');
      final issues = fixture
          .diagnostics(result)
          .where((d) => d.code == 'ccrouter_host_lifecycle_access');
      expect(issues, hasLength(3));
      expect(
        issues.every(
          (d) =>
              result.content.substring(d.offset, d.offset + d.length) ==
              'CCRouterHost',
        ),
        isTrue,
      );
    },
  );

  test('foreign same-name lifecycle declarations are ignored', () async {
    final result = await fixture.resolve('''
abstract final class CCRouterHost { static void shutdown() {} }
void stop() => CCRouterHost.shutdown();
''');
    expect(
      fixture
          .diagnostics(result)
          .where((d) => d.code == 'ccrouter_host_lifecycle_access'),
      isEmpty,
    );
  });

  for (final form in [
    'fileBarrel',
    'queryBarrel',
    'fileFacade',
    'queryFacade',
    'facadeAlias',
  ]) {
    test(
      'Host lifecycle boundary recognizes $form identity',
      () async {
        final facade = File(
          path.join(fixture.root.path, 'framework/lib/src/facade.dart'),
        );
        final barrel = File(
          path.join(fixture.root.path, 'framework/lib/ccrouter_host.dart'),
        );
        Link(
          path.join(fixture.root.path, 'owner/lib/root_alias.dart'),
        ).createSync(facade.path);
        final uri = switch (form) {
          'fileBarrel' => barrel.uri.toString(),
          'queryBarrel' => 'package:ccrouter/ccrouter_host.dart?query',
          'fileFacade' => facade.uri.toString(),
          'queryFacade' => 'package:ccrouter/src/facade.dart?query',
          _ => 'package:owner_contracts/root_alias.dart',
        };
        final source =
            "import '$uri' as root;\nvoid stop() => root.CCRouterHost.shutdown();";
        final result = await fixture.resolve(source);
        expect(
          result.diagnostics.where(
            (d) => d.diagnosticCode.severity.name == 'ERROR',
          ),
          isEmpty,
        );
        final issues = CCRouterSourceAnalyzer.analyze(
          source: source,
          filePath: fixture.file,
          packageRoot: fixture.root.path,
          packageName: 'consumer',
          resolvedUnit: result.unit,
          uriConverter: fixture.collection
              .contextFor(fixture.file)
              .currentSession
              .uriConverter,
        ).where((d) => d.code == 'ccrouter_host_lifecycle_access');
        expect(issues, isNotEmpty);
      },
      skip: Platform.isWindows && form == 'facadeAlias'
          ? 'POSIX symlink fixture'
          : false,
    );
  }

  for (final (label, source, forbidden) in [
    (
      'typedef call',
      "import 'package:owner_contracts/lifecycle.dart' as root;\ntypedef Root = root.CCRouterHost;\nvoid stop() => Root.shutdown();",
      true,
    ),
    (
      'named type',
      "import 'package:owner_contracts/lifecycle.dart' as root;\nroot.CCRouterHost? host;",
      true,
    ),
    (
      'hidden symbol',
      "import 'package:ccrouter/ccrouter_host.dart' hide CCRouterHost;",
      false,
    ),
    (
      'transitive show',
      "import 'package:owner_contracts/lifecycle.dart' show CCRouterHost;",
      true,
    ),
    (
      'show then hide',
      "import 'package:owner_contracts/lifecycle.dart' show CCRouterHost hide CCRouterHost;",
      false,
    ),
  ]) {
    test('Host lifecycle checks $label by semantic identity', () async {
      final result = await fixture.resolve(source);
      expect(
        result.diagnostics.where(
          (d) => d.diagnosticCode.severity.name == 'ERROR',
        ),
        isEmpty,
      );
      final issues = fixture
          .diagnostics(result)
          .where((d) => d.code == 'ccrouter_host_lifecycle_access');
      expect(issues.isNotEmpty, forbidden);
      if (label == 'typedef call') {
        expect(
          issues.map((d) => d.offset),
          contains(source.lastIndexOf('Root.shutdown')),
        );
      }
    });
  }

  test('a foreign same-name facade copy is not the configured Host', () async {
    fixture._write(
      'owner/lib/src/facade.dart',
      'abstract final class CCRouterHost { static void shutdown() {} }',
    );
    final result = await fixture.resolve(
      "import 'package:owner_contracts/src/facade.dart' as root;\nvoid stop() => root.CCRouterHost.shutdown();",
    );
    expect(
      result.diagnostics.where(
        (d) => d.diagnosticCode.severity.name == 'ERROR',
      ),
      isEmpty,
    );
    final issues = CCRouterSourceAnalyzer.analyze(
      source: result.content,
      filePath: fixture.file,
      packageRoot: fixture.root.path,
      packageName: 'consumer',
      resolvedUnit: result.unit,
      uriConverter: fixture.collection
          .contextFor(fixture.file)
          .currentSession
          .uriConverter,
    );
    expect(
      issues.where((d) => d.code == 'ccrouter_host_lifecycle_access'),
      isEmpty,
    );
  });

  for (final form in ['file', 'query', 'conditional']) {
    test('bare Host $form directives retain the lifecycle boundary', () async {
      final uri = File(
        path.join(fixture.root.path, 'framework/lib/ccrouter_host.dart'),
      ).uri;
      final source = switch (form) {
        'file' => "export '$uri';",
        'query' => "export 'package:ccrouter/ccrouter_host.dart?query';",
        _ =>
          "export 'package:owner_contracts/wrong.dart' if (dart.library.io) '$uri';",
      };
      final result = await fixture.resolve(source);
      expect(
        result.diagnostics.where(
          (d) => d.diagnosticCode.severity.name == 'ERROR',
        ),
        isEmpty,
      );
      final issues = CCRouterSourceAnalyzer.analyze(
        source: source,
        filePath: fixture.file,
        packageRoot: fixture.root.path,
        packageName: 'consumer',
        uriConverter: fixture.collection
            .contextFor(fixture.file)
            .currentSession
            .uriConverter,
      );
      expect(
        issues.where((d) => d.code == 'ccrouter_host_lifecycle_access'),
        hasLength(1),
      );
    });
  }

  test(
    'foreign same-name annotations never produce framework diagnostics or fixes',
    () async {
      final result = await fixture.resolve('''
class CCInitTask { const CCInitTask({String? id, Object? contract}); }
class CCRoute<T> { const CCRoute({Object? pattern, Object? patterns}); }
@CCInitTask(id: 'Bad ID', contract: 1)
int _start(int a, int b) => 0;
@CCRoute<void>(pattern: 1, patterns: 2)
class Page {}
''');
      // Exercise generated-output checks as well as argument/signature rules.
      final diagnostics = CCRouterSourceAnalyzer.analyze(
        source: result.content,
        filePath: path.join(fixture.root.path, 'lib/src/probe.dart'),
        packageRoot: fixture.root.path,
        packageName: 'consumer',
        resolvedUnit: result.unit,
      );
      expect(diagnostics, isEmpty);
      for (final name in ['CCInitTask', 'CCRoute']) {
        expect(
          CCRouterQuickFixes.compute(
            source: result.content,
            filePath: fixture.file,
            offset: result.content.indexOf('@$name'),
            resolvedUnit: result.unit,
          ),
          isEmpty,
        );
      }
    },
  );

  test(
    'computed dependency values are deferred rather than guessed missing',
    () async {
      final result = await fixture.resolve(
        _component('true ? right.ownerComponentId : wrong.ownerComponentId'),
      );
      expect(
        fixture
            .diagnostics(result)
            .where(
              (d) => d.code == 'ccrouter_component_owner_dependency_missing',
            ),
        isEmpty,
      );
    },
  );

  test('deferred imports cannot supply a disposable interface fix', () async {
    final result = await fixture.resolve('''
import 'package:ccrouter_contracts/ccrouter_contracts.dart' show CCService;
import 'package:ccrouter_contracts/ccrouter_contracts.dart' deferred as cc;
@CCService(id: 'sample')
class Sample { void dispose() {} }
''');
    final issue = fixture
        .diagnostics(result)
        .singleWhere((d) => d.code == 'ccrouter_service_disposable_missing');
    expect(fixture.fixes(result, issue), isEmpty);
  });

  test(
    'allocating into another instance does not prove this Service owns it',
    () async {
      final result = await fixture.resolve('''
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
class Client implements CCDisposable { void dispose() {} }
@CCService(id: 'other')
class OtherAssigned {
  late final Client _client;
  OtherAssigned(OtherAssigned other) { other._client = Client(); }
}
''');
      expect(
        fixture
            .diagnostics(result)
            .where((d) => d.code.startsWith('ccrouter_service_')),
        isEmpty,
      );
    },
  );

  test(
    'real plugin session fixes and unsaved overlays use resolved semantics',
    () async {
      final result = await fixture.resolve('''
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
@CCService(id: 'sample')
class Sample { void dispose() {} }
''');
      final plugin = CCRouterAnalyzerPlugin(PhysicalResourceProvider.INSTANCE);
      plugin.start(_Channel());
      await plugin.handleAnalysisSetContextRoots(
        AnalysisSetContextRootsParams([ContextRoot(fixture.root.path, [])]),
      );
      addTearDown(
        () => plugin.handleAnalysisSetContextRoots(
          AnalysisSetContextRootsParams([]),
        ),
      );
      final params = EditGetFixesParams(
        fixture.file,
        result.content.indexOf('class Sample'),
      );
      final fixed = await plugin.handleEditGetFixes(params);
      expect(
        fixed.fixes.single.error.code,
        'ccrouter_service_disposable_missing',
      );
      expect(
        fixed
            .fixes
            .single
            .fixes
            .single
            .change
            .edits
            .single
            .edits
            .single
            .replacement,
        contains('CCDisposable'),
      );

      final pending = plugin.handleEditGetFixes(params);
      await plugin.handleAnalysisUpdateContent(
        AnalysisUpdateContentParams({
          fixture.file: AddContentOverlay(
            result.content.replaceFirst(
              'class Sample {',
              'class Sample implements CCDisposable {',
            ),
          ),
        }),
      );
      expect((await pending).fixes, isEmpty);
      expect((await plugin.handleEditGetFixes(params)).fixes, isEmpty);
    },
  );

  test('real plugin session checks bare Package aliases', () async {
    fixture._write(
      'owner/lib/src/ccrouter_generated/hidden.dart',
      'const hidden = 1;',
    );
    Link(
      path.join(fixture.root.path, 'owner/lib/public_alias.dart'),
    ).createSync(
      path.join(
        fixture.root.path,
        'owner/lib/src/ccrouter_generated/hidden.dart',
      ),
    );
    const source =
        "import 'package:owner_contracts/public_alias.dart' show hidden;\nfinal value = hidden;";
    await fixture.resolve(source);
    final channel = _Channel();
    final plugin = CCRouterAnalyzerPlugin(PhysicalResourceProvider.INSTANCE)
      ..start(channel);
    addTearDown(
      () => plugin.handleAnalysisSetContextRoots(
        AnalysisSetContextRootsParams([]),
      ),
    );
    await plugin.handleAnalysisSetContextRoots(
      AnalysisSetContextRootsParams([ContextRoot(fixture.root.path, [])]),
    );
    await plugin.handleAnalysisUpdateContent(
      AnalysisUpdateContentParams({fixture.file: AddContentOverlay(source)}),
    );
    final errors = channel.notifications
        .where((n) => n.event == 'analysis.errors')
        .map(AnalysisErrorsParams.fromNotification)
        .where((p) => p.file == fixture.file)
        .last
        .errors;
    expect(
      errors.map((e) => e.code),
      contains('ccrouter_cross_package_generated_import'),
    );
  }, skip: Platform.isWindows ? 'POSIX symlink fixture' : false);

  test(
    'real plugin session checks typed UI SPI without a Component declaration',
    () async {
      Link(
        path.join(fixture.root.path, 'owner/lib/ui_alias.dart'),
      ).createSync(path.join(fixture.root.path, 'ui/lib/src/ui_fragment.dart'));
      const source =
          "import 'package:owner_contracts/ui_alias.dart' as ui;\nui.CCUIHostAssembly? assembly;";
      await fixture.resolve(source);
      final channel = _Channel();
      final plugin = CCRouterAnalyzerPlugin(PhysicalResourceProvider.INSTANCE)
        ..start(channel);
      addTearDown(
        () => plugin.handleAnalysisSetContextRoots(
          AnalysisSetContextRootsParams([]),
        ),
      );
      await plugin.handleAnalysisSetContextRoots(
        AnalysisSetContextRootsParams([ContextRoot(fixture.root.path, [])]),
      );
      await plugin.handleAnalysisUpdateContent(
        AnalysisUpdateContentParams({fixture.file: AddContentOverlay(source)}),
      );
      final errors = channel.notifications
          .where((n) => n.event == 'analysis.errors')
          .map(AnalysisErrorsParams.fromNotification)
          .where((p) => p.file == fixture.file)
          .last
          .errors;
      expect(errors.map((e) => e.code), contains('ccrouter_ui_spi_access'));
      const renderer = '''
import 'package:ccrouter_contracts/ccrouter_ui_contracts.dart';
import 'package:owner_contracts/right.dart' show ownerComponentId;
final class Props { const Props(); }
enum Action { select }
@CCUIFragmentContract<Props, Action>(componentId: ownerComponentId, id: 'right.card')
abstract final class Card {}
@CCUIFragmentRenderer(Card)
int render(int input) => 0;
''';
      final resolved = await fixture.resolve(renderer);
      expect(
        resolved.diagnostics.where(
          (d) => d.diagnosticCode.severity.name == 'ERROR',
        ),
        isEmpty,
      );
      await plugin.handleAnalysisUpdateContent(
        AnalysisUpdateContentParams({
          fixture.file: AddContentOverlay(renderer),
        }),
      );
      final rendererErrors = channel.notifications
          .where((n) => n.event == 'analysis.errors')
          .map(AnalysisErrorsParams.fromNotification)
          .where((p) => p.file == fixture.file)
          .last
          .errors;
      expect(
        rendererErrors.map((e) => e.code),
        contains('ccrouter_ui_renderer_invalid'),
      );
      expect(
        rendererErrors.map((e) => e.code),
        isNot(contains('ccrouter_ui_spi_access')),
      );
    },
    skip: Platform.isWindows ? 'POSIX symlink fixture' : false,
  );

  test(
    'parsed aliases use the borrowed SDK URI converter without a resolved unit',
    () {
      fixture._write(
        'owner/lib/src/ccrouter_generated/hidden.dart',
        'const hidden = 1;',
      );
      Link(
        path.join(fixture.root.path, 'owner/lib/public_alias.dart'),
      ).createSync(
        path.join(
          fixture.root.path,
          'owner/lib/src/ccrouter_generated/hidden.dart',
        ),
      );
      fixture._write('owner/lib/public.dart', 'const hidden = 2;');
      for (final declaration in [
        "import 'package:owner_contracts/public_alias.dart' show hidden;",
        "import 'package:owner_contracts/public_alias.dart' if (dart.library.io) 'package:owner_contracts/public.dart' show hidden;",
        "import 'package:owner_contracts/public.dart' if (dart.library.io) 'package:owner_contracts/public_alias.dart' show hidden;",
      ]) {
        final source = '$declaration\nfinal value = hidden;';
        final issues = CCRouterSourceAnalyzer.analyze(
          source: source,
          filePath: fixture.file,
          packageRoot: fixture.root.path,
          packageName: 'consumer',
          uriConverter: fixture.collection
              .contextFor(fixture.file)
              .currentSession
              .uriConverter,
        ).where((d) => d.code == 'ccrouter_cross_package_generated_import');
        expect(issues, hasLength(1), reason: declaration);
        expect(
          source.substring(
            issues.single.offset,
            issues.single.offset + issues.single.length,
          ),
          "'package:owner_contracts/public_alias.dart'",
        );
      }
    },
    skip: Platform.isWindows ? 'POSIX symlink fixture' : false,
  );

  test('required async InitTask aliases still require a timeout', () async {
    final result = await fixture.resolve('''
import 'dart:async' as async;
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
typedef Completion = async.Future<void>;
const task = CCInitTaskContract(id: 'sample');
@CCInitTask(contract: task, gate: CCInitTaskGate.appStarted, failurePolicy: CCInitTaskFailurePolicy.required)
Completion start() async {}
''');
    expect(
      fixture
          .diagnostics(result)
          .where(
            (d) => d.code == 'ccrouter_required_init_task_timeout_missing',
          ),
      hasLength(1),
    );
  });

  test('fix preserves existing interfaces and comments', () async {
    final result = await fixture.resolve('''
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
abstract interface class Feature {}
@CCService(id: 'sample')
class Sample implements Feature /* existing contract */ {
  void dispose() {}
}
''');
    final issue = fixture
        .diagnostics(result)
        .singleWhere((d) => d.code == 'ccrouter_service_disposable_missing');
    final changed = _apply(result.content, fixture.fixes(result, issue).single);
    expect(
      changed,
      contains('implements Feature, CCDisposable /* existing contract */'),
    );
    final repaired = await fixture.resolve(changed);
    expect(
      repaired.diagnostics.where(
        (d) => d.diagnosticCode.severity.name == 'ERROR',
      ),
      isEmpty,
    );
  });

  test('two imports with the same name cannot supply an owner fix', () async {
    final result = await fixture.resolve('''
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:owner_contracts/right.dart';
import 'package:owner_contracts/wrong.dart';
const component = CCComponent(id: CCComponentId('consumer'), version: '1',
  serviceDependencies: [CCServiceDependency<SharedService>()]);
''');
    final issue = fixture
        .diagnostics(result)
        .singleWhere(
          (d) => d.code == 'ccrouter_component_owner_dependency_missing',
        );
    expect(fixture.fixes(result, issue), isEmpty);
  });

  for (final type in [
    'void',
    'async.Future<void>',
    'async.FutureOr<void>',
    'async.Future<void>?',
    'Completion',
  ]) {
    test('resolved handler accepts $type', () async {
      final result = await fixture.resolve('''
import 'dart:async' as async;
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
typedef Completion = async.Future<void>;
@CCEventSubscription()
$type receive(Object event) => throw StateError('test');
''');
      expect(
        fixture
            .diagnostics(result)
            .where((d) => d.code == 'ccrouter_handler_signature_invalid'),
        isEmpty,
      );
    });
  }
  for (final type in [
    'int',
    'async.Future<int>',
    'BadCompletion',
    'dynamic',
    'Future<void>',
  ]) {
    test(
      'resolved handler rejects $type including a shadowed Future',
      () async {
        final result = await fixture.resolve('''
import 'dart:async' as async;
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
typedef BadCompletion = async.Future<int>;
class Future<T> {}
@CCEventSubscription()
$type receive(Object event) => throw StateError('test');
''');
        expect(
          fixture
              .diagnostics(result)
              .where((d) => d.code == 'ccrouter_handler_signature_invalid'),
          hasLength(1),
        );
      },
    );
  }

  test(
    'wrong prefixed owner is diagnosed and fixed with the right reference',
    () async {
      final result = await fixture.resolve(
        _component('wrong.ownerComponentId'),
      );
      final diagnostic = fixture
          .diagnostics(result)
          .singleWhere(
            (d) => d.code == 'ccrouter_component_owner_dependency_missing',
          );
      final fixes = fixture.fixes(result, diagnostic);
      expect(fixes, hasLength(1));
      expect(fixes.single.replacement, contains('right.ownerComponentId'));
      final repaired = await fixture.resolve(
        _apply(result.content, fixes.single),
      );
      expect(
        fixture.diagnostics(repaired).where((d) => d.code == diagnostic.code),
        isEmpty,
      );
    },
  );

  test(
    'local const aliases preserve the exact imported owner identity',
    () async {
      final result = await fixture.resolve(
        _component(
          'localAlias',
          extra: 'const localAlias = right.ownerComponentId;',
        ),
      );
      expect(
        fixture
            .diagnostics(result)
            .where(
              (d) => d.code == 'ccrouter_component_owner_dependency_missing',
            ),
        isEmpty,
      );
    },
  );

  test('local shadow cannot be inserted by a fix', () async {
    final result = await fixture.resolve('''
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:owner_contracts/right.dart';
const ownerComponentId = CCComponentId('wrong');
const component = CCComponent(id: CCComponentId('consumer'), version: '1',
  serviceDependencies: [CCServiceDependency<SharedService>()]);
''');
    final diagnostic = fixture
        .diagnostics(result)
        .singleWhere(
          (d) => d.code == 'ccrouter_component_owner_dependency_missing',
        );
    expect(fixture.fixes(result, diagnostic), isEmpty);
  });

  for (final escaped in [false, true]) {
    test(
      'valid Dart ${escaped ? 'escaped' : 'file URI'} imports retain the generated boundary',
      () async {
        fixture._write(
          'owner/lib/src/ccrouter_generated/hidden.dart',
          'const hidden = 1;',
        );
        final uri = escaped
            ? r'package:owner_contracts/src/\u0063\u0063router_generated/hidden.dart'
            : File(
                path.join(
                  fixture.root.path,
                  'owner/lib/src/ccrouter_generated/hidden.dart',
                ),
              ).uri.toString();
        final source = "import '$uri' show hidden;\nfinal value = hidden;";
        final result = await fixture.resolve(source);
        expect(
          result.diagnostics.where(
            (d) => d.diagnosticCode.severity.name == 'ERROR',
          ),
          isEmpty,
        );
        expect(
          fixture.diagnostics(result).map((d) => d.code),
          contains('ccrouter_cross_package_generated_import'),
        );
      },
    );
  }

  test(
    'localhost file URIs are valid Dart and retain the generated boundary',
    () async {
      if (Platform.isWindows) return;
      fixture._write(
        'owner/lib/src/ccrouter_generated/hidden.dart',
        'const hidden = 1;',
      );
      final uri = File(
        path.join(
          fixture.root.path,
          'owner/lib/src/ccrouter_generated/hidden.dart',
        ),
      ).uri.replace(host: 'localhost');
      final result = await fixture.resolve(
        "import '$uri' show hidden;\nfinal value = hidden;",
      );
      expect(
        result.diagnostics.where(
          (d) => d.diagnosticCode.severity.name == 'ERROR',
        ),
        isEmpty,
      );
      expect(
        fixture
            .diagnostics(result)
            .where((d) => d.code == 'ccrouter_cross_package_generated_import'),
        hasLength(1),
      );
    },
  );

  test('POSIX file authorities retain the local generated boundary', () async {
    if (Platform.isWindows) return;
    fixture._write(
      'owner/lib/src/ccrouter_generated/hidden.dart',
      'const hidden = 1;',
    );
    final uri = File(
      path.join(
        fixture.root.path,
        'owner/lib/src/ccrouter_generated/hidden.dart',
      ),
    ).uri.replace(host: 'not-local.invalid');
    final result = await fixture.resolve(
      "import '$uri' show hidden;\nfinal value = hidden;",
    );
    expect(
      result.diagnostics.where(
        (d) => d.diagnosticCode.severity.name == 'ERROR',
      ),
      isEmpty,
    );
    expect(
      fixture
          .diagnostics(result)
          .where((d) => d.code == 'ccrouter_cross_package_generated_import'),
      hasLength(1),
    );
  });

  for (final form in [
    'fileQuery',
    'fileFragment',
    'fileSeparator',
    'packageQuery',
    'packageFragment',
    'packageAbsolute',
    'packageAuthority',
    'packageSeparator',
  ]) {
    test('resolved $form imports retain generated identity', () async {
      fixture._write(
        'owner/lib/src/ccrouter_generated/hidden.dart',
        'const hidden = 1;',
      );
      final fileUri = File(
        path.join(
          fixture.root.path,
          'owner/lib/src/ccrouter_generated/hidden.dart',
        ),
      ).uri;
      final packageUri = Uri.parse(
        'package:owner_contracts/src/ccrouter_generated/hidden.dart',
      );
      final uri = switch (form) {
        'fileQuery' => fileUri.replace(query: 'query').toString(),
        'fileFragment' => fileUri.replace(fragment: 'fragment').toString(),
        'fileSeparator' => fileUri.toString().replaceFirst('/src/', '/src%2F'),
        'packageQuery' => packageUri.replace(query: 'query').toString(),
        'packageFragment' =>
          packageUri.replace(fragment: 'fragment').toString(),
        'packageAbsolute' =>
          'package:/owner_contracts/src/ccrouter_generated/hidden.dart',
        'packageAuthority' =>
          'package://ignored/owner_contracts/src/ccrouter_generated/hidden.dart',
        _ => packageUri.toString().replaceFirst('/src/', '/src%2F'),
      };
      final result = await fixture.resolve(
        "import '$uri' show hidden;\nfinal value = hidden;",
      );
      final fragment = form == 'fileFragment' || form == 'packageFragment';
      expect(
        result.diagnostics.where(
          (d) => d.diagnosticCode.severity.name == 'ERROR',
        ),
        fragment ? isNotEmpty : isEmpty,
      );
      expect(
        fixture
            .diagnostics(result)
            .where((d) => d.code == 'ccrouter_cross_package_generated_import'),
        fragment ? isEmpty : hasLength(1),
      );
    });
  }

  test(
    'resolved Package aliases retain their generated target identity',
    () async {
      fixture._write(
        'owner/lib/src/ccrouter_generated/hidden.dart',
        'const hidden = 1;',
      );
      Link(
        path.join(fixture.root.path, 'owner/lib/public_alias.dart'),
      ).createSync(
        path.join(
          fixture.root.path,
          'owner/lib/src/ccrouter_generated/hidden.dart',
        ),
      );
      final result = await fixture.resolve(
        "import 'package:owner_contracts/public_alias.dart' show hidden;\nfinal value = hidden;",
      );
      expect(
        result.diagnostics.where(
          (d) => d.diagnosticCode.severity.name == 'ERROR',
        ),
        isEmpty,
      );
      expect(
        fixture
            .diagnostics(result)
            .where((d) => d.code == 'ccrouter_cross_package_generated_import'),
        hasLength(1),
      );
    },
    skip: Platform.isWindows ? 'POSIX symlink fixture' : false,
  );

  test(
    'a named extension is valid source but must not be inserted as an Owner value',
    () async {
      const source = '''
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:owner_contracts/right.dart';
extension ownerComponentId on Object {}
const component = CCComponent(id: CCComponentId('consumer'), version: '1.0.0',
  serviceDependencies: [CCServiceDependency<SharedService>()]);
''';
      final result = await fixture.resolve(source);
      expect(result.diagnostics, isEmpty);
      final issue = fixture
          .diagnostics(result)
          .singleWhere(
            (issue) =>
                issue.code == 'ccrouter_component_owner_dependency_missing',
          );
      expect(fixture.fixes(result, issue), isEmpty);
      final broken = await fixture.resolve(
        source.replaceFirst(
          'serviceDependencies:',
          'dependencies: [ownerComponentId], serviceDependencies:',
        ),
      );
      expect(broken.diagnostics, isNotEmpty);
    },
  );

  for (final mode in ['conditionalImport', 'partImport']) {
    test('parser-only $mode Owner edit would introduce a Dart error', () async {
      fixture._write('owner/lib/empty.dart', '');
      fixture._write('owner/lib/with_part.dart', "part 'owner_part.dart';");
      fixture._write('owner/lib/owner_part.dart', '''
part of 'with_part.dart';
const ownerComponentId = 'wrong';
''');
      final competing = mode == 'conditionalImport'
          ? "'package:owner_contracts/empty.dart' if (dart.library.io) 'package:owner_contracts/wrong.dart'"
          : "'package:owner_contracts/with_part.dart'";
      final source =
          '''
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:owner_contracts/right.dart' as api show SharedService;
import 'package:owner_contracts/right.dart' as owner show ownerComponentId;
import $competing as owner show ownerComponentId;
const component = CCComponent(id: CCComponentId('consumer'), version: '1.0.0',
  serviceDependencies: [CCServiceDependency<api.SharedService>()]);
''';
      final result = await fixture.resolve(source);
      expect(
        result.diagnostics.where(
          (d) => d.diagnosticCode.severity.name == 'ERROR',
        ),
        isEmpty,
      );
      final fixes = CCRouterQuickFixes.compute(
        source: source,
        filePath: fixture.file,
        offset: source.indexOf('CCServiceDependency<'),
        diagnosticCode: 'ccrouter_component_owner_dependency_missing',
        sourcePackage: 'consumer',
        contractOwners: fixture.owners,
      );
      expect(fixes, isEmpty);
      // Select the alternate explicitly; Analyzer's platform defaults can differ.
      final selected = mode == 'conditionalImport'
          ? source.replaceFirst(
              competing,
              "'package:owner_contracts/wrong.dart'",
            )
          : source;
      final broken = await fixture.resolve(
        selected.replaceFirst(
          'serviceDependencies:',
          'dependencies: [owner.ownerComponentId], serviceDependencies:',
        ),
      );
      expect(
        broken.diagnostics.where(
          (d) => d.diagnosticCode.severity.name == 'ERROR',
        ),
        isNotEmpty,
      );
    });
  }

  for (final (library, prefix, expected) in [
    ('foreign.dart', '', false),
    ('foreign.dart', 'api', false),
    ('foreign_barrel.dart', 'api', false),
    ('right_barrel.dart', 'api', true),
    ('right_barrel.dart', '', true),
  ]) {
    test(
      'parsed Contract identity follows $library with prefix $prefix',
      () async {
        fixture._write('owner/lib/foreign.dart', '''
abstract interface class SharedService {}
''');
        fixture._write(
          'owner/lib/foreign_barrel.dart',
          "export 'foreign.dart' show SharedService;",
        );
        fixture._write(
          'owner/lib/right_barrel.dart',
          "export 'right.dart' show SharedService;",
        );
        final source =
            '''
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:owner_contracts/$library' ${prefix.isEmpty ? '' : 'as $prefix'} show SharedService;
const component = CCComponent(id: CCComponentId('consumer'), version: '1.0.0',
  serviceDependencies: [CCServiceDependency<${prefix.isEmpty ? '' : '$prefix.'}SharedService>()]);
''';
        final result = await fixture.resolve(source);
        expect(
          result.diagnostics.where(
            (d) => d.diagnosticCode.severity.name == 'ERROR',
          ),
          isEmpty,
        );
        final issues = CCRouterSourceAnalyzer.analyze(
          source: source,
          filePath: fixture.file,
          packageRoot: fixture.root.path,
          packageName: 'consumer',
          contractOwners: fixture.owners,
        );
        expect(
          issues.any(
            (d) => d.code == 'ccrouter_component_owner_dependency_missing',
          ),
          expected,
        );
      },
    );
  }

  for (final signature in ['void', 'Future<void>', 'FutureOr<void>']) {
    test(
      'Service $signature dispose gets a fix which passes reanalysis',
      () async {
        final result = await fixture.resolve('''
import 'dart:async';
import 'package:ccrouter_contracts/ccrouter_contracts.dart' as cc;
@cc.CCService(id: 'sample')
class Sample {
  $signature dispose() => throw StateError('test');
}

''');
        final diagnostic = fixture
            .diagnostics(result)
            .singleWhere(
              (d) => d.code == 'ccrouter_service_disposable_missing',
            );
        final fixes = fixture.fixes(result, diagnostic);
        expect(fixes, hasLength(1));
        expect(fixes.single.replacement, contains('cc.CCDisposable'));
        final repaired = await fixture.resolve(
          _apply(result.content, fixes.single),
        );
        expect(
          repaired.diagnostics.where(
            (d) => d.diagnosticCode.severity.name == 'ERROR',
          ),
          isEmpty,
        );
        expect(
          fixture
              .diagnostics(repaired)
              .where((d) => d.code.startsWith('ccrouter_service_')),
          isEmpty,
        );
      },
    );
  }

  test(
    'inherited disposer can be connected but inherited CCDisposable is already safe',
    () async {
      final result = await fixture.resolve('''
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
class Base { void dispose() {} }
class Managed implements CCDisposable { void dispose() {} }
@CCService(id: 'unconnected')
class Unconnected extends Base {}
@CCService(id: 'managed')
class AlreadyManaged extends Managed {}
''');
      final issues = fixture
          .diagnostics(result)
          .where((d) => d.code.startsWith('ccrouter_service_'))
          .toList();
      expect(issues, hasLength(1));
      expect(
        result.content.substring(
          issues.single.offset,
          issues.single.offset + issues.single.length,
        ),
        'Unconnected',
      );
    },
  );

  test(
    'private final fresh resource warns without inventing cleanup',
    () async {
      final result = await fixture.resolve('''
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
class Client implements CCDisposable { void dispose() {} }
@CCService(id: 'field')
class FieldOwned { final _client = Client(); }
@CCService(id: 'initializer')
class InitializerOwned { InitializerOwned() : _client = Client(); final Client _client; }
@CCService(id: 'body')
class BodyOwned { BodyOwned() { _client = Client(); } late final Client _client; }
''');
      final issues = fixture
          .diagnostics(result)
          .where((d) => d.code == 'ccrouter_service_owned_resource')
          .toList();
      expect(
        issues.map(
          (d) => result.content.substring(d.offset, d.offset + d.length),
        ),
        ['FieldOwned', 'InitializerOwned', 'BodyOwned'],
      );
      for (final issue in issues) {
        expect(fixture.fixes(result, issue), isEmpty);
      }
    },
  );

  test(
    'borrowed, shared, factory, ordinary and incompatible Services are not auto-fixed',
    () async {
      final result = await fixture.resolve('''
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
class Client implements CCDisposable { void dispose() {} }
final shared = Client();
class Pooled implements CCDisposable { factory Pooled() => throw StateError('pool'); void dispose() {} }
@CCService(id: 'borrowed')
class Borrowed { Borrowed(this._client); final Client _client; }
@CCService(id: 'shared')
class Shared { final _client = shared; }
@CCService(id: 'factory')
class Factory { final _client = Pooled(); }
@CCService(id: 'ordinary')
class Ordinary {}
@CCService(id: 'incompatible')
class Incompatible { int dispose() => 1; }
@CCService(id: 'static')
class Static { static final _client = Client(); static void dispose() {} }
''');
      expect(
        fixture
            .diagnostics(result)
            .where((d) => d.code.startsWith('ccrouter_service_')),
        isEmpty,
      );
    },
  );

  test(
    'hidden disposable import and same-name foreign interfaces get no fix',
    () async {
      final result = await fixture.resolve('''
import 'package:ccrouter_contracts/ccrouter_contracts.dart' hide CCDisposable;
abstract interface class CCDisposable { void dispose(); }
@CCService(id: 'foreign')
class Sample implements CCDisposable { void dispose() {} }
''');
      final issue = fixture
          .diagnostics(result)
          .singleWhere((d) => d.code == 'ccrouter_service_disposable_missing');
      expect(fixture.fixes(result, issue), isEmpty);
    },
  );
}

String _component(String dependency, {String extra = ''}) =>
    '''
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:owner_contracts/right.dart' as right;
import 'package:owner_contracts/wrong.dart' as wrong;
$extra
const component = CCComponent(id: CCComponentId('consumer'), version: '1',
  dependencies: [$dependency],
  serviceDependencies: [CCServiceDependency<right.SharedService>()]);
''';

String _apply(String source, CCRouterSourceFix fix) =>
    source.replaceRange(fix.offset, fix.offset + fix.length, fix.replacement);

final class _Channel implements PluginCommunicationChannel {
  final notifications = <Notification>[];
  @override
  void close() {}
  @override
  void listen(
    void Function(Request request)? onRequest, {
    void Function()? onDone,
    Function? onError,
    Function(Notification)? onNotification,
  }) {}
  @override
  void sendNotification(Notification notification) =>
      notifications.add(notification);
  @override
  void sendResponse(Response response) {}
}

final class _Fixture {
  _Fixture() {
    final contracts = Directory('../ccrouter_contracts').absolute.path;
    _write(
      'pubspec.yaml',
      'name: consumer\nenvironment:\n  sdk: ^3.10.0\ndependencies:\n  ccrouter: any\n',
    );
    _write(
      'framework/lib/src/facade.dart',
      'abstract final class CCRouterHost { static void initialize() {} static Future<void> shutdown() async {} static Future<void> runInitTasks() async {} }',
    );
    _write(
      'framework/lib/ccrouter_host.dart',
      "export 'src/facade.dart' show CCRouterHost;",
    );
    _write(
      'ui/lib/src/ui_fragment.dart',
      'class CCUIHostAssembly {} class CCUIRenderer {}',
    );
    _write(
      'owner/lib/lifecycle.dart',
      "export 'package:ccrouter/ccrouter_host.dart' show CCRouterHost;",
    );
    _write(
      'owner/lib/right.dart',
      "import 'package:ccrouter_contracts/ccrouter_contracts.dart';\nconst ownerComponentId = CCComponentId('right');\n@CCServiceContract(componentId: ownerComponentId, id: 'right.shared')\nabstract interface class SharedService {}\n",
    );
    _write(
      'owner/lib/wrong.dart',
      "import 'package:ccrouter_contracts/ccrouter_contracts.dart';\nconst ownerComponentId = CCComponentId('wrong');\n",
    );
    _write(
      '.dart_tool/package_config.json',
      jsonEncode({
        'configVersion': 2,
        'packages': [
          {
            'name': 'consumer',
            'rootUri': '../',
            'packageUri': 'lib/',
            'languageVersion': '3.10',
          },
          {
            'name': 'owner_contracts',
            'rootUri': '../owner',
            'packageUri': 'lib/',
            'languageVersion': '3.10',
          },
          {
            'name': 'ccrouter',
            'rootUri': '../framework',
            'packageUri': 'lib/',
            'languageVersion': '3.10',
          },
          {
            'name': 'ccrouter_ui',
            'rootUri': '../ui',
            'packageUri': 'lib/',
            'languageVersion': '3.10',
          },
          {
            'name': 'ccrouter_contracts',
            'rootUri': Uri.directory(contracts).toString(),
            'packageUri': 'lib/',
            'languageVersion': '3.10',
          },
        ],
      }),
    );
    _write('lib/sample.dart', '');
    collection = AnalysisContextCollection(includedPaths: [root.path]);
  }
  final root = Directory.systemTemp.createTempSync('ccrouter-semantic-');
  late final AnalysisContextCollection collection;
  String get file => path.join(root.path, 'lib/sample.dart');
  CCRouterContractOwnerIndex get owners => CCRouterContractOwnerIndex(
    owners: const [
      CCRouterContractOwner(
        kind: CCRouterContractKind.service,
        contractSymbol: 'SharedService',
        contractPackage: 'owner_contracts',
        componentId: 'right',
        componentIdSymbol: 'ownerComponentId',
        contractLibraryUri: 'package:owner_contracts/right.dart',
      ),
    ],
    packageRoots: {
      'owner_contracts': path.join(root.path, 'owner'),
      'ccrouter_contracts': Directory('../ccrouter_contracts').absolute.path,
    },
  );
  void _write(String name, String content) => (File(
    path.join(root.path, name),
  )..createSync(recursive: true)).writeAsStringSync(content);
  Future<ResolvedUnitResult> resolve(String source) async {
    File(file).writeAsStringSync(source);
    final context = collection.contextFor(file);
    context.changeFile(file);
    await context.applyPendingFileChanges();
    return await context.currentSession.getResolvedUnit(file)
        as ResolvedUnitResult;
  }

  List<CCRouterAnalyzerDiagnostic> diagnostics(ResolvedUnitResult result) =>
      CCRouterSourceAnalyzer.analyze(
        source: result.content,
        filePath: file,
        packageRoot: root.path,
        packageName: 'consumer',
        contractOwners: owners,
        resolvedUnit: result.unit,
      );
  List<CCRouterSourceFix> fixes(
    ResolvedUnitResult result,
    CCRouterAnalyzerDiagnostic diagnostic,
  ) => CCRouterQuickFixes.compute(
    source: result.content,
    filePath: file,
    offset: diagnostic.offset,
    diagnosticCode: diagnostic.code,
    contractOwners: owners,
    sourcePackage: 'consumer',
    resolvedUnit: result.unit,
  );
  Future<void> dispose() async {
    await collection.dispose();
    root.deleteSync(recursive: true);
  }
}
