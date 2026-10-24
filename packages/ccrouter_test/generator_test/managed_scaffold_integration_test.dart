@TestOn('vm')
@Timeout(Duration(minutes: 8))
library;

import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

/// Validates real standalone Pub roots rather than borrowing Workspace state.
void main() {
  test(
    'standalone scaffold prepares its parent and runs generated Managed routes',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'ccrouter-managed-scaffold-',
      );
      addTearDown(() => root.delete(recursive: true));
      final sources = <String, Directory>{};
      for (final name in [
        'ccrouter_contracts',
        'ccrouter_core',
        'ccrouter',
        'ccrouter_generator',
      ]) {
        final target = Directory(path.join(root.path, 'framework', name));
        await _copyPackage(Directory('packages/$name'), target);
        sources[name] = target;
      }
      File(path.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: scaffold_invoker
environment:
  sdk: ^3.10.0
dependencies:
  ccrouter:
    path: framework/ccrouter
dev_dependencies:
  ccrouter_generator:
    path: framework/ccrouter_generator
  build_runner: ^2.10.0
''');
      await _run(Directory.current, Platform.resolvedExecutable, [
        'run',
        'ccrouter_generator:ccrouter',
        'create',
        'component',
        'fixture_feature',
        root.path,
        '--with-example',
      ]);
      final component = Directory(path.join(root.path, 'fixture_feature'));
      final example = Directory(path.join(component.path, 'example'));
      final overrides =
          'dependency_overrides:\n${sources.entries.map((e) => '  ${e.key}:\n    path: ${e.value.path}\n').join()}';
      for (final package in [component, example]) {
        File(
          path.join(package.path, 'pubspec_overrides.yaml'),
        ).writeAsStringSync(overrides);
      }
      await _run(Directory.current, Platform.resolvedExecutable, [
        'run',
        'ccrouter_generator:ccrouter',
        'create',
        'page',
        'InventoryPage',
        component.path,
      ]);
      File(
        path.join(example.path, 'lib/src/detail_page.dart'),
      ).writeAsStringSync('''
import 'package:ccrouter/ccrouter.dart';
import 'package:flutter/material.dart';
@CCRoute<String>(id: 'fixture_feature_example.detail', pattern: CCPathPattern('/detail/:id'))
final class DetailPage extends StatelessWidget {
  const DetailPage({required this.id, super.key});
  final int id;
  @override
  Widget build(BuildContext context) => Scaffold(body: Text('detail:\$id'));
}
''');
      await _run(component, _flutterExecutable(), ['pub', 'get', '--offline']);
      await _generate(component, ['portable', 'prepare', '.']);
      await _run(example, _flutterExecutable(), ['pub', 'get', '--offline']);
      await _generate(example, ['generate', '.']);
      final test = File(
        path.join(example.path, 'test/managed_example_test.dart'),
      );
      test.parent.createSync(recursive: true);
      test.writeAsStringSync('''
import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fixture_feature_example/main.dart' as app;
import 'package:fixture_feature_example/src/ccrouter_generated/fixture_feature_example.api.g.dart';

void main() {
  testWidgets('generated Assembly, parent dependency, typed result and exact close', (tester) async {
    app.main();
    await tester.pumpAndSettle();
    expect(find.text('Add component pages and open their typed Intents here.'), findsOneWidget);
    // The parent's sources are generated only by its own Portable prepare.
    await CCRouter.navigator.open(Uri.parse('/inventory'));
    await tester.pumpAndSettle();
    expect(find.text('InventoryPage'), findsOneWidget);
    CCRouter.navigator.pop();
    await tester.pumpAndSettle();
    final first = CCRouter.navigator.push(FixtureFeatureExampleRoutes.detail(id: 7));
    await tester.pumpAndSettle();
    final handle = CCRouter.routeEntryHandleOf(tester.element(find.text('detail:7')));
    expect(handle, isNotNull);
    final second = CCRouter.navigator.push(FixtureFeatureExampleRoutes.detail(id: 8));
    await tester.pumpAndSettle();
    final closed = await CCRouter.navigator.close(handle!, result: 'closed:7');
    await tester.pumpAndSettle();
    expect(closed.status, CCRouteCloseStatus.closed);
    expect(await first, 'closed:7');
    expect(find.text('detail:8'), findsOneWidget);
    CCRouter.navigator.pop(result: 'popped:8');
    await tester.pumpAndSettle();
    expect(await second, 'popped:8');
    expect(find.text('Add component pages and open their typed Intents here.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await CCRouterHost.shutdown();
  });
}
''');
      await _run(example, Platform.resolvedExecutable, [
        'analyze',
        '--fatal-infos',
      ]);
      await _run(example, _flutterExecutable(), [
        'test',
        '--no-pub',
        'test/managed_example_test.dart',
      ]);
      await _generate(example, ['generate', '.', '--no-cache', '--check']);
    },
  );
}

Future<void> _generate(Directory root, List<String> arguments) => _run(
  root,
  Platform.resolvedExecutable,
  ['run', '--verbosity=error', 'ccrouter_generator:ccrouter', ...arguments],
);

Future<void> _run(
  Directory root,
  String executable,
  List<String> arguments,
) async {
  final result = await Process.run(
    executable,
    arguments,
    workingDirectory: root.path,
    environment: {...Platform.environment, 'CCROUTER_PUB_HOOK_DISABLE': '1'},
  );
  expect(
    result.exitCode,
    0,
    reason:
        '${root.path}: $executable ${arguments.join(' ')}\n${result.stdout}\n${result.stderr}',
  );
}

/// Copies authored sources and Builder config, never Pub/build cache evidence.
Future<void> _copyPackage(Directory source, Directory target) async {
  target.createSync(recursive: true);
  File(path.join(target.path, 'pubspec.yaml')).writeAsStringSync(
    File(
      path.join(source.path, 'pubspec.yaml'),
    ).readAsStringSync().replaceFirst(
      RegExp(r'^resolution: workspace\r?\n', multiLine: true),
      '',
    ),
  );
  final builderConfig = File(path.join(source.path, 'build.yaml'));
  if (builderConfig.existsSync())
    await builderConfig.copy(path.join(target.path, 'build.yaml'));
  for (final name in ['lib', 'bin']) {
    final directory = Directory(path.join(source.path, name));
    if (directory.existsSync())
      await _copySources(directory, Directory(path.join(target.path, name)));
  }
}

Future<void> _copySources(Directory source, Directory target) async {
  target.createSync(recursive: true);
  for (final entity in source.listSync(followLinks: false)) {
    final name = path.basename(entity.path);
    if (entity is Directory) {
      await _copySources(entity, Directory(path.join(target.path, name)));
    } else if (entity is File) {
      await entity.copy(path.join(target.path, name));
    }
  }
}

String _flutterExecutable() {
  final name = Platform.isWindows ? 'flutter.bat' : 'flutter';
  final sdk = File(
    Platform.resolvedExecutable,
  ).absolute.parent.parent.parent.parent;
  return path.join(sdk.path, name);
}
