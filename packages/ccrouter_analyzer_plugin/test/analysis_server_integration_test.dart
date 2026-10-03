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
