import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'support/analysis_server_session.dart';

const _source = '''
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
@CCService(id: 'sample.service')
class Sample {
  void dispose() {}
}
''';
const _file = 'lib/src/sample.dart';
const _disposable = 'ccrouter_service_disposable_missing';

bool _has(List<Map<String, dynamic>> errors, String code) =>
    errors.any((error) => (error['code'] as String).toLowerCase() == code);

void main() {
  test(
    'real LSP clears route placement and policy errors on unsaved repair',
    () async {
      const file = 'lib/src/routes.dart';
      const source = '''
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
@CCRoute<void>(id: 'sample.home', pattern: CCPathPattern('/'),
  placement: CCRoutePlacement(hostId: 'Bad Host', parentRouteId: 'sample.home'),
  popGuards: ['dirty.check', 'dirty.check'])
class Home {}
''';
      const codes = {
        'ccrouter_route_placement_invalid',
        'ccrouter_route_parent_self',
        'ccrouter_route_policy_duplicate',
      };
      final server = await AnalysisServerSession.start({
        file: source,
      }, lsp: true);
      addTearDown(server.close);
      final uri = Uri.file(server.path(file)).toString();
      server.notify('textDocument/didOpen', {
        'textDocument': {
          'uri': uri,
          'languageId': 'dart',
          'version': 1,
          'text': source,
        },
      });
      await server.waitFor(
        file,
        (errors) => codes.every((code) => _has(errors, code)),
      );
      final revision = server.revisions[server.path(file)]!;
      server.notify('textDocument/didChange', {
        'textDocument': {'uri': uri, 'version': 2},
        'contentChanges': [
          {
            'text': source
                .replaceFirst(
                  "hostId: 'Bad Host', parentRouteId: 'sample.home'",
                  "hostId: 'main'",
                )
                .replaceFirst("'dirty.check', 'dirty.check'", "'dirty.check'"),
          },
        ],
      });
      await server.waitFor(
        file,
        (errors) => codes.every((code) => !_has(errors, code)),
        after: revision,
      );
      expect(
        File(server.path(file)).readAsStringSync(),
        source,
        reason:
            'The repair must be verified from the editor overlay, not a save.',
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'real LSP diagnoses component lifecycle and refreshes after Host role change',
    timeout: const Timeout(Duration(minutes: 2)),
    () async {
      const componentPath = 'modules/feature/lib/src/lifecycle.dart';
      const code = 'ccrouter_host_lifecycle_access';
      const source =
          "import 'package:ccrouter/ccrouter_host.dart' as cc;\nvoid stop() => cc.CCRouterHost.shutdown();\n";
      final server = await AnalysisServerSession.start(
        {
          'lib/main.dart':
              "import 'package:ccrouter_contracts/ccrouter_contracts.dart';\n$source\n@CCInitTask() void start() {}\n",
          '.metadata': 'project_type: app\n',
        },
        lsp: true,
        hostManifest:
            'name: e2e_host\nenvironment:\n  sdk: ^3.10.0\ndependencies:\n  ccrouter: any\nworkspace:\n  - modules/feature\n  - modules/ccrouter\n',
        dependencyPackages: {
          'feature': {'lib/src/lifecycle.dart': source},
          'ccrouter': {
            'lib/ccrouter_host.dart':
                "export 'src/facade.dart' show CCRouterHost;",
            'lib/src/facade.dart':
                'abstract final class CCRouterHost { static void shutdown() {} }',
          },
        },
        dependencyManifests: {
          'feature':
              'name: feature\nresolution: workspace\nenvironment:\n  sdk: ^3.10.0\ndependencies:\n  ccrouter: any\n',
        },
      );
      addTearDown(server.close);
      for (final file in ['lib/main.dart', componentPath]) {
        server.notify('textDocument/didOpen', {
          'textDocument': {
            'uri': Uri.file(server.path(file)).toString(),
            'languageId': 'dart',
            'version': 1,
            'text': File(server.path(file)).readAsStringSync(),
          },
        });
      }
      await server.waitFor(componentPath, (errors) => _has(errors, code));
      await server.waitFor(
        'lib/main.dart',
        (errors) =>
            _has(errors, 'ccrouter_annotation_arguments_conflict') &&
            !_has(errors, code),
      );
      final revision = server.revisions[server.path(componentPath)]!;
      server.write('modules/feature/ccrouter.yaml', 'host:\n  enabled: true\n');
      await server.waitFor(
        componentPath,
        (errors) => !_has(errors, code),
        after: revision,
      );
      final hostRevision = server.revisions[server.path(componentPath)]!;
      server.write(
        'modules/feature/ccrouter.yaml',
        'host:\n  enabled: false\n',
      );
      await server.waitFor(
        componentPath,
        (errors) => _has(errors, code),
        after: hostRevision,
      );
    },
  );

  test('real server publishes and clears invalid ccrouter.yaml', () async {
    const code = 'ccrouter_project_configuration_invalid';
    final server = await AnalysisServerSession.start({
      _file: _source,
      'ccrouter.yaml': 'host:\n  enabled: yes\n',
    });
    addTearDown(server.close);

    await server.waitFor('ccrouter.yaml', (errors) => _has(errors, code));
    final invalidRevision = server.revisions[server.path('ccrouter.yaml')]!;

    server.write('ccrouter.yaml', 'host:\n  enabled: false\n');

    await server.waitFor(
      'ccrouter.yaml',
      (errors) => !_has(errors, code),
      after: invalidRevision,
    );
  });

  test(
    'real LSP reports and clears UI alias diagnostics on editor overlay',
    () async {
      const file = 'lib/src/ui.dart';
      const source =
          "import 'package:ccrouter_contracts/ccrouter_contracts.dart';\nimport 'package:ccrouter_contracts/ccrouter_ui_contracts.dart';\nclass Marker {}\nconst component = CCComponent(id: CCComponentId('consumer'), version: '1.0.0', uiDependencies: [CCUIFragmentDependency<Marker>(alias: 'bad-alias', versionRange: '*')]);\n";
      final server = await AnalysisServerSession.start({
        file: source,
      }, lsp: true);
      addTearDown(server.close);
      final uri = Uri.file(server.path(file)).toString();
      server.notify('textDocument/didOpen', {
        'textDocument': {
          'uri': uri,
          'languageId': 'dart',
          'version': 1,
          'text': source,
        },
      });
      const code = 'ccrouter_ui_alias_invalid';
      await server.waitFor(file, (errors) => _has(errors, code));
      final revision = server.revisions[server.path(file)]!;
      server.notify('textDocument/didChange', {
        'textDocument': {'uri': uri, 'version': 2},
        'contentChanges': [
          {'text': source.replaceFirst('bad-alias', 'card')},
        ],
      });
      await server.waitFor(
        file,
        (errors) => !_has(errors, code),
        after: revision,
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'real LSP accepts DTO Action after editor shape repair',
    () async {
      const file = 'lib/src/payload.dart';
      const source = '''
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:ccrouter_contracts/ccrouter_ui_contracts.dart';
final class Props { const Props(); }
class Selection { const Selection(this.id); final String id; }
@CCUIFragmentContract<Props, Selection>(componentId: CCComponentId('orders'), id: 'selection', version: '2.0.0')
abstract final class Marker {}
''';
      final server = await AnalysisServerSession.start({
        file: source,
      }, lsp: true);
      addTearDown(server.close);
      final uri = Uri.file(server.path(file)).toString();
      server.notify('textDocument/didOpen', {
        'textDocument': {
          'uri': uri,
          'languageId': 'dart',
          'version': 1,
          'text': source,
        },
      });
      const code = 'ccrouter_ui_action_invalid';
      await server.waitFor(file, (errors) => _has(errors, code));
      final revision = server.revisions[server.path(file)]!;
      server.notify('textDocument/didChange', {
        'textDocument': {'uri': uri, 'version': 2},
        'contentChanges': [
          {
            'text': source.replaceFirst(
              'class Selection',
              'final class Selection',
            ),
          },
        ],
      });
      await server.waitFor(
        file,
        (errors) => !_has(errors, code),
        after: revision,
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  for (final (lsp, bridgeCode) in [
    (false, 'ccrouter_host_component_owner_missing'),
    (true, 'ccrouter_host_component_owner_missing'),
    (true, 'ccrouter_ui_missing_implementation'),
  ]) {
    test(
      'real ${lsp ? 'LSP' : 'legacy'} $bridgeCode server bridges and clears current watch diagnostics',
      () async {
        const sourcePath = 'lib/src/bridge.dart';
        final server = await AnalysisServerSession.start({
          sourcePath: 'const bridgeValue = 1;\n',
        }, lsp: lsp);
        addTearDown(server.close);
        final statusPath = '.dart_tool/ccrouter/v1/watch/status.json';
        final diagnosticsPath = '.dart_tool/ccrouter/v1/watch/diagnostics.json';
        Map<String, Object?> identity(int revision) => {
          'schemaVersion': 1,
          'hostRoot': server.host.path,
          'buildRoot': server.host.path,
          'sessionId': 'session-1',
          'eventRevision': revision,
          'cycle': 2,
          'resolutionFingerprint': 'resolution-1',
        };
        server.write(
          diagnosticsPath,
          jsonEncode({
            ...identity(7),
            'lastEvent': 'failed',
            'cycleResolutionState': 'matched',
            'diagnostics': [
              {
                'code': bridgeCode,
                'severity': 'error',
                'message': 'Host closure is missing owner component "orders".',
                'correction': 'Restore the owner Package and run Pub get.',
                'rootCauseGroup': 'missing-owner:orders',
                'primaryLocation': {
                  'uri': 'package:e2e_host/src/bridge.dart',
                  'line': 1,
                  'column': 7,
                  'length': 11,
                },
              },
            ],
          }),
        );
        server.write(
          statusPath,
          jsonEncode({...identity(7), 'active': true, 'lastEvent': 'failed'}),
        );

        final code = bridgeCode;
        await server.waitFor(sourcePath, (errors) => _has(errors, code));
        final failedRevision = server.revisions[server.path(sourcePath)]!;
        server.write(
          statusPath,
          jsonEncode({
            ...identity(8),
            'active': true,
            'lastEvent': 'aggregationSucceeded',
          }),
        );
        server.write(
          diagnosticsPath,
          jsonEncode({
            ...identity(8),
            'lastEvent': 'aggregationSucceeded',
            'cycleResolutionState': 'matched',
            'diagnostics': const <Object?>[],
          }),
        );
        await server.waitFor(
          sourcePath,
          (errors) => !_has(errors, code),
          after: failedRevision,
        );

        final recoveredRevision = server.revisions[server.path(sourcePath)]!;
        server.write(
          diagnosticsPath,
          jsonEncode({
            ...identity(7),
            'lastEvent': 'failed',
            'cycleResolutionState': 'matched',
            'diagnostics': [
              {
                'code': code,
                'severity': 'error',
                'message': 'Stale diagnostic.',
                'correction': 'Must not be shown.',
                'rootCauseGroup': 'missing-owner:stale',
                'primaryLocation': {
                  'uri': 'package:e2e_host/src/bridge.dart',
                  'line': 1,
                  'column': 7,
                  'length': 11,
                },
              },
            ],
          }),
        );
        await Future<void>.delayed(const Duration(seconds: 1));
        server.checkHealthy();
        expect(
          server.diagnostics[server.path(sourcePath)] ?? const [],
          isNot(contains(predicate<Map>((error) => error['code'] == code))),
        );
        expect(
          server.revisions[server.path(sourcePath)] ?? recoveredRevision,
          greaterThanOrEqualTo(recoveredRevision),
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  }

  for (final lsp in [false, true]) {
    test(
      'real ${lsp ? 'LSP' : 'legacy'} server follows unsaved Pub manifest overlays',
      () async {
        const manifest = '''
name: e2e_host
environment:
  sdk: ^3.10.0
dependencies:
  ccrouter_contracts: any
  demo_order: any
''';
        const staleManifest = '''
name: e2e_host
environment:
  sdk: ^3.10.0
dependencies:
  ccrouter_contracts: any
#  demo_order: any
''';
        final server = await AnalysisServerSession.start(
          {
            _file: 'const sample = 1;\n',
            '.dart_tool/package_graph.json': jsonEncode({
              'packages': [
                {
                  'name': 'e2e_host',
                  'version': '1.0.0',
                  'dependencies': ['ccrouter_contracts', 'demo_order'],
                },
              ],
            }),
          },
          lsp: lsp,
          hostManifest: manifest,
        );
        addTearDown(server.close);
        const code = 'ccrouter_pub_resolution_stale';
        final pubspecPath = server.path('pubspec.yaml');

        if (lsp) {
          server.notify('textDocument/didOpen', {
            'textDocument': {
              'uri': Uri.file(pubspecPath).toString(),
              'languageId': 'yaml',
              'version': 1,
              'text': staleManifest,
            },
          });
        } else {
          await server.overlay('pubspec.yaml', staleManifest);
        }
        await server.waitFor('pubspec.yaml', (errors) => _has(errors, code));

        final staleRevision = server.revisions[pubspecPath]!;
        if (lsp) {
          server.notify('textDocument/didChange', {
            'textDocument': {
              'uri': Uri.file(pubspecPath).toString(),
              'version': 2,
            },
            'contentChanges': [
              {'text': manifest},
            ],
          });
        } else {
          await server.overlay('pubspec.yaml', manifest);
        }
        await server.waitFor(
          'pubspec.yaml',
          (errors) => !_has(errors, code),
          after: staleRevision,
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  }

  for (final lsp in [false, true]) {
    test(
      'real ${lsp ? 'LSP' : 'legacy'} server publishes and clears stale Pub resolution hints',
      () async {
        final server = await AnalysisServerSession.start({
          _file: 'const sample = 1;\n',
        }, lsp: lsp);
        addTearDown(server.close);
        server.write(
          '.dart_tool/ccrouter/v1/watch/status.json',
          jsonEncode({
            'schemaVersion': 1,
            'active': true,
            'hostRoot': server.host.path,
            'buildRoot': server.host.path,
            'sessionId': 'session-1',
            'eventRevision': 1,
            'cycle': 1,
            'lastEvent': 'ready',
          }),
        );
        void writeGraph(List<String> dependencies) {
          server.write(
            '.dart_tool/package_graph.json',
            jsonEncode({
              'packages': [
                {
                  'name': 'e2e_host',
                  'version': '1.0.0',
                  'dependencies': dependencies,
                },
              ],
            }),
          );
        }

        writeGraph(['ccrouter', 'demo_order']);
        server.write('pubspec.yaml', '''
name: e2e_host
environment:
  sdk: ^3.10.0
dependencies:
  ccrouter: any
  # demo_order: any
''');
        const code = 'ccrouter_pub_resolution_stale';
        await server.waitFor('pubspec.yaml', (errors) => _has(errors, code));

        final staleRevision = server.revisions[server.path('pubspec.yaml')]!;
        writeGraph(['ccrouter']);
        await server.waitFor(
          'pubspec.yaml',
          (errors) => !_has(errors, code),
          after: staleRevision,
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  }

  test(
    'real server publishes an initial stale Pub hint for a Workspace member',
    () async {
      const member = 'member_contracts';
      final server = await AnalysisServerSession.start(
        {
          _file: 'const sample = 1;\n',
          '.dart_tool/package_graph.json': jsonEncode({
            'packages': [
              {
                'name': member,
                'version': '1.0.0',
                'dependencies': ['ccrouter_contracts', 'stale_dependency'],
              },
            ],
          }),
        },
        dependencyPackages: {
          member: {'lib/member.dart': 'const memberValue = 1;\n'},
        },
        dependencyManifests: const {
          member: '''
name: member_contracts
resolution: workspace
environment:
  sdk: ^3.10.0
dependencies:
  ccrouter_contracts: any
''',
        },
      );
      addTearDown(server.close);

      const code = 'ccrouter_pub_resolution_stale';
      await server.waitFor(
        'modules/$member/pubspec.yaml',
        (errors) => _has(errors, code),
      );
      final staleRevision =
          server.revisions[server.path('modules/$member/pubspec.yaml')]!;
      server.write(
        '.dart_tool/package_graph.json',
        jsonEncode({
          'packages': [
            {
              'name': member,
              'version': '1.0.0',
              'dependencies': ['ccrouter_contracts'],
            },
          ],
        }),
      );
      await server.waitFor(
        'modules/$member/pubspec.yaml',
        (errors) => !_has(errors, code),
        after: staleRevision,
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'real server polls structured diagnostics for a nested Workspace Host',
    () async {
      const nestedHost = 'nested_host';
      const sourcePath = 'modules/$nestedHost/lib/src/bridge.dart';
      final server = await AnalysisServerSession.start(
        {_file: 'const sample = 1;\n'},
        dependencyPackages: {
          nestedHost: {
            '.metadata': 'project_type: app\n',
            'lib/src/bridge.dart': 'const nestedBridge = 1;\n',
          },
        },
        dependencyManifests: const {
          nestedHost: '''
name: nested_host
resolution: workspace
environment:
  sdk: ^3.10.0
dependencies:
  ccrouter: any
''',
        },
      );
      addTearDown(server.close);
      final nestedRoot = Directory(server.path('modules/$nestedHost'));
      final identity = <String, Object?>{
        'schemaVersion': 1,
        'hostRoot': nestedRoot.path,
        'buildRoot': server.host.path,
        'sessionId': 'nested-session',
        'eventRevision': 1,
        'cycle': 1,
        'resolutionFingerprint': 'nested-resolution',
      };
      server.write(
        'modules/$nestedHost/.dart_tool/ccrouter/v1/watch/status.json',
        jsonEncode({...identity, 'active': true, 'lastEvent': 'failed'}),
      );
      server.write(
        'modules/$nestedHost/.dart_tool/ccrouter/v1/watch/diagnostics.json',
        jsonEncode({
          ...identity,
          'lastEvent': 'failed',
          'cycleResolutionState': 'matched',
          'diagnostics': [
            {
              'code': 'ccrouter_host_component_owner_missing',
              'severity': 'error',
              'message': 'Nested Host closure is missing an owner.',
              'correction': 'Restore the owner Package and run Pub get.',
              'rootCauseGroup': 'missing-owner:nested',
              'primaryLocation': {
                'uri': 'package:nested_host/src/bridge.dart',
                'line': 1,
                'column': 7,
                'length': 12,
              },
            },
          ],
        }),
      );

      const code = 'ccrouter_host_component_owner_missing';
      await server.waitFor(sourcePath, (errors) => _has(errors, code));
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'real server clears foreign annotation diagnostics despite unrelated errors',
    () async {
      const framework = '''
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
@CCInitTask(id: 'sample', gate: CCInitTaskGate.appStarted,
  failurePolicy: CCInitTaskFailurePolicy.optional)
void start() {}
''';
      const foreign = '''
import 'package:ccrouter_contracts/ccrouter_contracts.dart' as framework;
class CCInitTask { const CCInitTask({String? id, Object? contract}); }
@CCInitTask(id: 'bad id', contract: 1)
int _start(int a, int b) => 0;
void broken() { missingFunction(); }
''';
      final server = await AnalysisServerSession.start({_file: framework});
      addTearDown(server.close);
      await server.waitFor(
        _file,
        (errors) => _has(errors, 'ccrouter_generated_output_missing'),
      );
      final revision = server.revisions[server.path(_file)]!;
      await server.overlay(_file, foreign);
      await server.waitFor(
        _file,
        (errors) =>
            _has(errors, 'undefined_function') &&
            !errors.any(
              (e) =>
                  (e['code'] as String).toLowerCase().startsWith('ccrouter_'),
            ),
        after: revision,
      );
      final restoredRevision = server.revisions[server.path(_file)]!;
      await server.overlay(_file, framework);
      await server.waitFor(
        _file,
        (errors) => _has(errors, 'ccrouter_generated_output_missing'),
        after: restoredRevision,
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'real watcher refreshes consumers across workspace Contract packages',
    () async {
      const componentFile = 'lib/src/component.dart';
      const metadataFile =
          'lib/src/ccrouter_generated/metadata/ccrouter_package.json';
      String ownerMetadata(String owner) => jsonEncode({
        'capabilityCatalog': {
          'records': [
            {
              'kind': 'service',
              'componentId': owner,
              'contract': {
                'symbol': 'SharedService',
                'packageUri': 'package:owner_contracts/src/contracts.dart',
              },
            },
          ],
        },
      });
      const contracts = '''
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
const ownerId = CCComponentId('owner');
const alternateId = CCComponentId('alternate');
abstract interface class SharedService {}
@CCService(id: 'owner.probe')
class OwnerProbe {}
''';
      final server = await AnalysisServerSession.start(
        {
          componentFile: '''
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:owner_contracts/src/contracts.dart';
const component = CCComponent(
  id: CCComponentId('consumer'), version: '1.0.0',
  dependencies: [alternateId],
  serviceDependencies: [CCServiceDependency<SharedService>()],
);
''',
          metadataFile: jsonEncode({
            'metadata': [
              {
                'components': [
                  {'id': 'consumer'},
                ],
                'package': 'e2e_host',
                'source': componentFile,
              },
            ],
          }),
        },
        dependencyPackages: {
          'owner_contracts': {
            'lib/src/contracts.dart': contracts,
            metadataFile: ownerMetadata('owner'),
          },
        },
      );
      addTearDown(server.close);
      const missing = 'ccrouter_component_owner_dependency_missing';
      final initial = await server.waitFor(
        componentFile,
        (errors) => _has(errors, missing),
      );
      expect(
        initial.where(
          (error) => error['severity'] == 'ERROR' && error['code'] != missing,
        ),
        isEmpty,
      );
      await server.waitFor(
        'modules/owner_contracts/lib/src/contracts.dart',
        (errors) => _has(errors, 'ccrouter_generated_output_missing'),
      );
      final ownerFile = File(
        server.path('modules/owner_contracts/$metadataFile'),
      );
      var revision = server.revisions[server.path(componentFile)]!;
      ownerFile.writeAsStringSync(ownerMetadata('alternate'));
      await server.waitFor(
        componentFile,
        (errors) => !_has(errors, missing),
        after: revision,
      );
      revision = server.revisions[server.path(componentFile)]!;
      ownerFile.writeAsStringSync(ownerMetadata('owner'));
      await server.waitFor(
        componentFile,
        (errors) => _has(errors, missing),
        after: revision,
      );
      final contractFile = File(
        server.path('modules/owner_contracts/lib/src/contracts.dart'),
      );
      revision = server.revisions[server.path(componentFile)]!;
      contractFile.writeAsStringSync(
        contracts.replaceFirst(
          "CCComponentId('alternate')",
          "CCComponentId('owner')",
        ),
      );
      await server.waitFor(
        componentFile,
        (errors) => !_has(errors, missing),
        after: revision,
      );
      revision = server.revisions[server.path(componentFile)]!;
      contractFile.writeAsStringSync(contracts);
      await server.waitFor(
        componentFile,
        (errors) => _has(errors, missing),
        after: revision,
      );
      revision = server.revisions[server.path(componentFile)]!;
      ownerFile.deleteSync();
      await server.waitFor(
        componentFile,
        (errors) => !_has(errors, missing),
        after: revision,
      );
      revision = server.revisions[server.path(componentFile)]!;
      ownerFile.writeAsStringSync(ownerMetadata('owner'));
      await server.waitFor(
        componentFile,
        (errors) => _has(errors, missing),
        after: revision,
      );
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );

  test(
    'real LSP diagnostics and codeAction fix the open document',
    () async {
      final server = await AnalysisServerSession.start({
        _file: _source,
      }, lsp: true);
      addTearDown(server.close);
      final uri = Uri.file(server.path(_file)).toString();
      server.notify('textDocument/didOpen', {
        'textDocument': {
          'uri': uri,
          'languageId': 'dart',
          'version': 1,
          'text': _source,
        },
      });
      final errors = await server.waitFor(
        _file,
        (errors) => _has(errors, _disposable),
      );
      expect(errors.where((error) => error['severity'] == 1), isEmpty);
      final diagnostic = errors.firstWhere(
        (error) => error['code'] == _disposable,
      );
      final response = await server.request('textDocument/codeAction', {
        'textDocument': {'uri': uri},
        'range': diagnostic['range'],
        'context': {
          'diagnostics': [diagnostic],
          'only': ['quickfix'],
        },
      });
      final actions = (response['value'] as List).where(
        (action) => (action['title'] as String).contains('CCDisposable'),
      );
      expect(actions, hasLength(1));
      final action = actions.single as Map;
      final workspaceEdit = action['edit'] as Map;
      final changes = (workspaceEdit['changes'] as Map)[uri] as List;
      var fixed = _source;
      int offset(Map position) {
        final lines = _source.split('\n');
        return lines
                .take(position['line'] as int)
                .fold<int>(0, (n, line) => n + line.length + 1) +
            (position['character'] as int);
      }

      changes.sort(
        (a, b) => offset(
          b['range']['start'] as Map,
        ).compareTo(offset(a['range']['start'] as Map)),
      );
      for (final edit in changes) {
        fixed = fixed.replaceRange(
          offset(edit['range']['start'] as Map),
          offset(edit['range']['end'] as Map),
          edit['newText'] as String,
        );
      }
      final revision = server.revisions[server.path(_file)]!;
      server.notify('textDocument/didChange', {
        'textDocument': {'uri': uri, 'version': 2},
        'contentChanges': [
          {'text': fixed},
        ],
      });
      await server.waitFor(
        _file,
        (errors) =>
            !_has(errors, _disposable) &&
            !errors.any((error) => error['severity'] == 1),
        after: revision,
      );
      final restored = server.revisions[server.path(_file)]!;
      server.notify('textDocument/didClose', {
        'textDocument': {'uri': uri},
      });
      await server.waitFor(
        _file,
        (errors) => _has(errors, _disposable),
        after: restored,
      );
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );

  for (final lsp in [false, true]) {
    test(
      'real ${lsp ? 'LSP' : 'legacy'} disk watcher refreshes all five generated capability kinds',
      () async {
        const declarations = <String, String>{
          'route':
              "@CCRoute<void>(id: 'sample.route', pattern: CCPathPattern('/sample'))\nclass Sample {}",
          'service': "@CCService(id: 'sample.service')\nclass Sample {}",
          'command':
              'class SampleCommand implements CCCommand<void> {}\n@CCCommandHandler()\nvoid handle(SampleCommand command) {}',
          'event':
              'class SampleEvent implements CCEvent {}\n@CCEventSubscription()\nvoid handle(SampleEvent event) {}',
          'init_task':
              "const task = CCInitTaskContract(id: 'sample.task');\n@CCInitTask(contract: task, gate: CCInitTaskGate.appStarted, failurePolicy: CCInitTaskFailurePolicy.required)\nvoid start() {}",
        };
        final server = await AnalysisServerSession.start({
          for (final entry in declarations.entries)
            'lib/src/${entry.key}.dart':
                "import 'package:ccrouter_contracts/ccrouter_contracts.dart';\n${entry.value}\n",
        }, lsp: lsp);
        addTearDown(server.close);
        const missing = 'ccrouter_generated_output_missing';
        for (final kind in declarations.keys) {
          final source = 'lib/src/$kind.dart';
          final initial = await server.waitFor(
            source,
            (errors) => _has(errors, missing),
          );
          expect(
            initial.where(
              (error) => error['severity'] == 'ERROR' || error['severity'] == 1,
            ),
            isEmpty,
          );
          final outputs = [
            'lib/src/ccrouter_generated/$kind/$kind.$kind.g.dart',
            if (kind == 'route')
              'lib/src/ccrouter_generated/binding/route.route_binding.g.dart',
          ];
          var revision = server.revisions[server.path(source)]!;
          for (final output in outputs) {
            server.write(output, '// Fixture output.\n');
          }
          await server.waitFor(
            source,
            (errors) => !_has(errors, missing),
            after: revision,
          );

          revision = server.revisions[server.path(source)]!;
          server.write(outputs.first, '// Modified fixture output.\n');
          // LSP suppresses unchanged diagnostics; legacy exposes the refresh.
          await server.waitFor(
            source,
            (errors) => !_has(errors, missing),
            after: lsp ? 0 : revision,
          );

          // Rename away and back, then delete/recreate: equivalent disk events to
          // clean/regenerate, without claiming that this runs the generator.
          revision = server.revisions[server.path(source)]!;
          File(
            server.path(outputs.first),
          ).renameSync('${server.path(outputs.first)}.backup');
          await server.waitFor(
            source,
            (errors) => _has(errors, missing),
            after: revision,
          );
          revision = server.revisions[server.path(source)]!;
          File(
            '${server.path(outputs.first)}.backup',
          ).renameSync(server.path(outputs.first));
          await server.waitFor(
            source,
            (errors) => !_has(errors, missing),
            after: revision,
          );
          revision = server.revisions[server.path(source)]!;
          for (final output in outputs) {
            File(server.path(output)).deleteSync();
          }
          await server.waitFor(
            source,
            (errors) => _has(errors, missing),
            after: revision,
          );
          revision = server.revisions[server.path(source)]!;
          for (final output in outputs) {
            server.write(output, '// Regenerated fixture.\n');
          }
          await server.waitFor(
            source,
            (errors) => !_has(errors, missing),
            after: revision,
          );
        }
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  }
  test(
    'real server: unsaved overlays and service Quick Fix round trip',
    () async {
      final server = await AnalysisServerSession.start({_file: _source});
      addTearDown(server.close);
      final errors = await server.waitFor(
        _file,
        (errors) => _has(errors, _disposable),
      );
      expect(errors.where((error) => error['severity'] == 'ERROR'), isEmpty);
      final diagnostic = errors.firstWhere(
        (error) => (error['code'] as String).toLowerCase() == _disposable,
      );
      final result = await server.request('edit.getFixes', {
        'file': server.path(_file),
        'offset': (diagnostic['location'] as Map)['offset'],
      });
      final fixes = (result['fixes'] as List).where(
        (fix) => (fix['error']['code'] as String).toLowerCase() == _disposable,
      );
      expect(fixes, hasLength(1));
      final edits = ((fixes.single['fixes'] as List).first['edits'] as List);
      expect(edits, hasLength(1));
      expect(edits.single['file'], server.path(_file));
      var fixed = _source;
      final sourceEdits =
          (edits.single['edits'] as List).cast<Map<String, dynamic>>()..sort(
            (a, b) => (b['offset'] as int).compareTo(a['offset'] as int),
          );
      for (final edit in sourceEdits) {
        fixed = fixed.replaceRange(
          edit['offset'] as int,
          (edit['offset'] as int) + (edit['length'] as int),
          edit['replacement'] as String,
        );
      }
      final revision = server.revisions[server.path(_file)]!;
      await server.overlay(_file, fixed);
      await server.waitFor(
        _file,
        (errors) =>
            !_has(errors, _disposable) &&
            !errors.any((error) => error['severity'] == 'ERROR'),
        after: revision,
      );
      final restored = server.revisions[server.path(_file)]!;
      await server.overlay(_file, null);
      await server.waitFor(
        _file,
        (errors) => _has(errors, _disposable),
        after: restored,
      );

      // Rapid edits exercise async resolution and stale-result suppression.
      final beforeBurst = server.revisions[server.path(_file)]!;
      await Future.wait([
        for (var i = 0; i < 12; i++)
          server.overlay(_file, i.isEven ? _source : fixed),
      ]);
      await server.waitFor(
        _file,
        (errors) =>
            !_has(errors, _disposable) &&
            !errors.any((error) => error['severity'] == 'ERROR'),
        after: beforeBurst,
      );
      final currentFixes = await server.request('edit.getFixes', {
        'file': server.path(_file),
        'offset': fixed.indexOf('Sample'),
      });
      expect(
        (currentFixes['fixes'] as List).where(
          (fix) =>
              (fix['error']['code'] as String).toLowerCase() == _disposable,
        ),
        isEmpty,
      );
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
