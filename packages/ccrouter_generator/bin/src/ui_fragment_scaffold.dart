import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:ccrouter_generator/src/generated_client_naming.dart';
import 'package:dart_style/dart_style.dart';
import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';

import 'scaffold.dart';

/// Parses and executes the optional UI scaffold independently of other create
/// commands. It never resolves Pub, generates glue or edits existing source.
Future<bool> runUIFragmentScaffold(List<String> arguments) async {
  if (arguments.contains('--help') || arguments.contains('-h')) {
    stdout.writeln(_usage);
    return true;
  }
  try {
    final positional = <String>[];
    final options = <String, String>{};
    var dryRun = false;
    for (var i = 0; i < arguments.length; i++) {
      final argument = arguments[i];
      if (argument == '--dry-run' && !dryRun) {
        dryRun = true;
      } else if (const {
        '--owner-source',
        '--owner-symbol',
        '--id',
        '--renderer-root',
      }.contains(argument)) {
        if (options.containsKey(argument) ||
            i + 1 >= arguments.length ||
            arguments[i + 1].startsWith('--')) {
          throw CCScaffoldException(
            'Missing or duplicate value for $argument.',
          );
        }
        options[argument] = arguments[++i];
      } else if (argument.startsWith('-')) {
        throw CCScaffoldException('Unknown or repeated option: $argument.');
      } else {
        positional.add(argument);
      }
    }
    if (positional.length != 2 ||
        !options.keys.toSet().containsAll({
          '--owner-source',
          '--owner-symbol',
          '--id',
        })) {
      throw const CCScaffoldException(_usage);
    }
    final plan = planUIFragmentScaffold(
      name: positional[0],
      contractsRoot: Directory(positional[1]),
      ownerSource: options['--owner-source']!,
      ownerSymbol: options['--owner-symbol']!,
      id: options['--id']!,
      rendererRoot: options['--renderer-root'] == null
          ? null
          : Directory(options['--renderer-root']!),
    );
    stdout.writeln(
      dryRun ? 'UI Fragment preview (no writes):' : 'Creating UI Fragment:',
    );
    for (final entry in plan.files.entries) {
      stdout.writeln('  ${entry.key.path}');
      if (dryRun) stdout.writeln(entry.value);
    }
    if (!dryRun) await plan.write();
    stdout.writeln(plan.nextSteps);
    return true;
  } on CCScaffoldException catch (error) {
    stderr.writeln('error: ${error.message}');
    return false;
  } on FileSystemException catch (error) {
    stderr.writeln(
      'error: Cannot create UI Fragment: ${error.message} (${error.path}).',
    );
    return false;
  }
}

/// A reviewable, non-overwriting set of authored templates and manual steps.
final class UIFragmentScaffoldPlan {
  /// Freezes file content so preview and execution use the same plan.
  UIFragmentScaffoldPlan(Map<File, String> files, this.nextSteps)
    : files = Map.unmodifiable(files);

  /// Only new authored files; generated directories are never targets.
  final Map<File, String> files;

  /// Existing dependency edits and Host verification remain explicit.
  final String nextSteps;

  /// Publishes new files exclusively and rolls back only this operation's files.
  Future<void> write() async {
    final created = <File>[];
    try {
      for (final entry in files.entries) {
        await entry.key.parent.create(recursive: true);
        await entry.key.create(exclusive: true);
        created.add(entry.key);
        await entry.key.writeAsString(entry.value, flush: true);
      }
    } on Object {
      for (final file in created.reversed) {
        await file.delete();
      }
      rethrow;
    }
  }
}

/// Plans a v1 Contract, a public explicit barrel and an optional Renderer.
/// The caller names the existing canonical Owner declaration; its semantic
/// framework identity and the Owner implementation are checked by generation.
UIFragmentScaffoldPlan planUIFragmentScaffold({
  required String name,
  required Directory contractsRoot,
  required String ownerSource,
  required String ownerSymbol,
  required String id,
  Directory? rendererRoot,
}) {
  if (!RegExp(r'^[A-Z][A-Za-z0-9]*$').hasMatch(name) ||
      !RegExp(r'^[A-Za-z][A-Za-z0-9_]*$').hasMatch(ownerSymbol) ||
      !RegExp(r'^[a-z][A-Za-z0-9]*(?:[._-][A-Za-z0-9]+)*$').hasMatch(id) ||
      id.length > 128) {
    throw const CCScaffoldException(
      'Use a PascalCase Fragment name, a public '
      'Owner constant identifier, and a stable capability --id.',
    );
  }
  final alias = '${name[0].toLowerCase()}${name.substring(1)}';
  if (!isGeneratedClientMemberName(alias) ||
      const {
        'hashCode',
        'runtimeType',
        'toString',
        'noSuchMethod',
      }.contains(alias)) {
    throw const CCScaffoldException(
      'Fragment name produces a reserved UI alias; choose another name.',
    );
  }
  final root = Directory(contractsRoot.resolveSymbolicLinksSync());
  final manifest = _manifest(root);
  final dependencies = manifest['dependencies'];
  if (dependencies is Map && dependencies.containsKey('flutter')) {
    throw const CCScaffoldException(
      'UI Contracts belong in a Pure Dart contracts Package.',
    );
  }
  final package = manifest['name'] as String;
  final sourcePath = path.normalize(path.join(root.path, ownerSource));
  if (path.isAbsolute(ownerSource) ||
      !RegExp(r'^lib/[A-Za-z0-9_./-]+\.dart$').hasMatch(ownerSource) ||
      !ownerSource.startsWith('lib/') ||
      !ownerSource.endsWith('.dart') ||
      ownerSource.split('/').contains('ccrouter_generated') ||
      !path.isWithin(path.join(root.path, 'lib'), sourcePath)) {
    throw const CCScaffoldException(
      '--owner-source must name authored Dart source under contracts lib/.',
    );
  }
  final ownerFile = File(sourcePath);
  if (!ownerFile.existsSync() ||
      !path.isWithin(root.path, ownerFile.resolveSymbolicLinksSync())) {
    throw const CCScaffoldException(
      '--owner-source is missing or outside the contracts Package.',
    );
  }
  _checkParents(root, ownerFile);
  final parsed = parseString(
    content: ownerFile.readAsStringSync(),
    throwIfDiagnostics: false,
  );
  if (parsed.errors.isNotEmpty ||
      parsed.unit.directives.any((d) => d is PartOfDirective) ||
      !parsed.unit.declarations.whereType<TopLevelVariableDeclaration>().any(
        (d) =>
            d.variables.isConst &&
            d.variables.variables.any((v) => v.name.lexeme == ownerSymbol),
      )) {
    throw const CCScaffoldException(
      '--owner-source must declare the requested public top-level const '
      'in a valid library. Reuse the canonical CCComponentId; no duplicate ID is created.',
    );
  }
  final stem = name
      .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]}_${m[2]}')
      .toLowerCase();
  final ownerImport = path
      .relative(sourcePath, from: path.join(root.path, 'lib', 'src'))
      .replaceAll(path.separator, '/');
  final ownerExport = path
      .relative(sourcePath, from: path.join(root.path, 'lib'))
      .replaceAll(path.separator, '/');
  final formatter = DartFormatter(
    languageVersion: DartFormatter.latestLanguageVersion,
  );
  final files = <File, String>{
    File(path.join(root.path, 'lib', 'src', '${stem}_fragment.dart')): formatter
        .format('''
import 'package:ccrouter_contracts/ccrouter_ui_contracts.dart';
import '$ownerImport' show $ownerSymbol;

/// Immutable input owned and updated by the consuming component.
final class ${name}Props {
  const ${name}Props({required this.itemId});
  final String itemId;
}

/// The consumer already knows itemId; v1 Actions cannot carry dynamic payloads.
enum ${name}Action { openDetails }

/// Public capability implemented only by the canonical Owner.
@CCUIFragmentContract<${name}Props, ${name}Action>(
  componentId: $ownerSymbol, id: '$id', version: '1.0.0',
)
abstract final class ${name}FragmentContract {}
'''),
    File(path.join(root.path, 'lib', '${stem}_fragment.dart')): formatter
        .format('''
/// Public UI Contract; implementation and generated glue remain private.
library;
export 'src/${stem}_fragment.dart' show ${name}Props, ${name}Action, ${name}FragmentContract;
export '$ownerExport' show $ownerSymbol;
'''),
  };
  if (rendererRoot != null) {
    final renderer = Directory(rendererRoot.resolveSymbolicLinksSync());
    _manifest(renderer);
    if (renderer.path == root.path) {
      throw const CCScaffoldException(
        'Renderer belongs in the Owner implementation Package, not contracts.',
      );
    }
    files[File(
      path.join(renderer.path, 'lib', 'src', '${stem}_fragment_renderer.dart'),
    )] = formatter.format('''
import 'package:flutter/widgets.dart';
import 'package:ccrouter_ui/ccrouter_ui.dart';
import 'package:$package/${stem}_fragment.dart';

/// Builds the Owner Widget; disposable resources belong in its State.
@CCUIFragmentRenderer(${name}FragmentContract)
Widget render$name(CCUIFragmentRenderInput<${name}Props, ${name}Action> input) =>
  GestureDetector(
    onTap: input.active ? () => input.onAction(${name}Action.openDetails) : null,
    child: Text(input.props.itemId),
  );
''');
  }
  for (final file in files.keys) {
    final fileRoot = path.isWithin(root.path, file.path)
        ? root
        : Directory(rendererRoot!.resolveSymbolicLinksSync());
    _checkParents(fileRoot, file);
    if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw CCScaffoldException(
        'Refusing to overwrite existing target: ${file.path}',
      );
    }
  }
  return UIFragmentScaffoldPlan(
    files,
    '''Next steps (existing files are unchanged):
  1. Contracts pubspec: add direct ccrouter_contracts using your approved Package source.
     Add ccrouter_generator to dev_dependencies for Contract generation.
  2. Owner pubspec: add direct $package, ccrouter_ui and Flutter dependencies.
     Ensure ccrouter_generator is in dev_dependencies.
     ${rendererRoot == null ? 'Add a top-level @CCUIFragmentRenderer(${name}FragmentContract) in the Owner implementation.' : 'Complete the new Renderer and verify its Package owns $ownerSymbol.'}
  3. Consumer pubspec: add direct $package and ccrouter_ui dependencies.
     Ensure ccrouter_generator is in dev_dependencies.
     In the component definition, add:
     import 'package:ccrouter_ui/ccrouter_ui.dart';
     import 'package:$package/${stem}_fragment.dart';
     Add $ownerSymbol to CCComponent.dependencies (required, not optional).
     Add to uiDependencies: CCUIFragmentDependency<${name}FragmentContract>(versionRange: '^1.0.0', alias: '$alias').
  4. Actual Host pubspec: include A/B implementation Packages and direct ccrouter_ui.
     Ensure ccrouter_generator and build_runner are in Host dev_dependencies.
     Run Flutter pub get from the Host, then ccrouter generate <host-root>.
  5. Run ccrouter find $id <host-root> --usage <consumer-component-id> for the proven Client import and call.
     Use stable business Keys; pass active for hidden Tabs; handle Session reset and State cleanup.
     Finish with analyze, tests and ccrouter generate <host-root> --no-cache --check after stopping watch.
  For an ID loaded privately by B, replace the starter enum with a restricted immutable DTO Action.
''',
  );
}

/// Rejects linked or nested Package parents so a template cannot escape scope.
void _checkParents(Directory root, File file) {
  var parent = file.parent;
  while (parent.path != root.path) {
    final type = FileSystemEntity.typeSync(parent.path, followLinks: false);
    if (!path.isWithin(root.path, parent.path) ||
        (type != FileSystemEntityType.directory &&
            type != FileSystemEntityType.notFound) ||
        File(path.join(parent.path, 'pubspec.yaml')).existsSync()) {
      throw CCScaffoldException(
        'Target crosses a symlink or nested Package: ${file.path}',
      );
    }
    parent = parent.parent;
  }
}

/// Reads Package identity without guessing framework dependency sources.
YamlMap _manifest(Directory root) {
  final file = File(path.join(root.path, 'pubspec.yaml'));
  Object? value;
  try {
    value = file.existsSync() ? loadYaml(file.readAsStringSync()) : null;
  } on YamlException {
    throw CCScaffoldException('Invalid pubspec.yaml: ${file.path}');
  }
  if (value is! YamlMap ||
      value['name'] is! String ||
      !RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(value['name'] as String)) {
    throw CCScaffoldException(
      'Expected a Package with a valid pubspec.yaml name: ${root.path}',
    );
  }
  return value;
}

/// Explicit canonical Owner references avoid inventing duplicate ID constants.
const _usage =
    'ccrouter create ui-fragment <Name> <contracts-root> '
    '--owner-source <lib/path.dart> --owner-symbol <canonicalOwnerConstant> '
    '--id <capability-id> [--renderer-root <owner-root>] [--dry-run]';
