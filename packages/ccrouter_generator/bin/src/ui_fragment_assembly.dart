part of '../ccrouter_generator.dart';

/// Emits opt-in stable UI Client barrels; the old API barrel is unchanged.
Future<Set<String>> _generateUIAPIs(
  CCPackageWorkspace workspace,
  Map<String, CCPackageIndex> indexes,
) async {
  final outputs = <String>{};
  for (final index in indexes.values) {
    final package = workspace.packages[index.packageName]!;
    for (final document in index.metadata) {
      final requirements = _objects(document['uiRequirements']);
      final renderers = _objects(document['uiRenderers']);
      if (requirements.isEmpty && renderers.isEmpty) continue;
      if (!package.dependencies.contains('ccrouter_ui')) {
        throw CCPackageWorkspaceException(
          'UI Package "${package.name}" must directly depend on ccrouter_ui.',
        );
      }
      if (!package.writable || requirements.isEmpty) continue;
      final consumer = '${requirements.first['consumer']}';
      final className = '${_pascalIdentifier(consumer)}Fragments';
      final library = '${document['uiLibrary']}'.substring(
        'lib/src/ccrouter_generated/'.length,
      );
      final file = File(
        path.join(
          package.root.path,
          'lib/src/ccrouter_generated',
          '${_fileStem(consumer)}.ui.api.g.dart',
        ),
      );
      outputs.add(path.normalize(file.path));
      await _writeIfChanged(
        file,
        _dartFormatter.format('''
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint

/// Stable component-specific UI Client; implementation factories stay private.
export '$library' show $className;
'''),
      );
    }
  }
  return outputs;
}

/// Host-only imports and collection expressions derived from resolved indexes.
({String imports, String contributions, String requirements}) _uiHostInputs(
  CCPackageWorkspace workspace,
  Map<String, CCPackageIndex> indexes,
) {
  // An installed provider alone must not opt an existing Host into UI.
  // Only required consumer edges need the optional Host catalog and dependency.
  if (!indexes.values.any(
    (index) => index.metadata.any(
      (document) => _objects(document['uiRequirements']).isNotEmpty,
    ),
  )) {
    return (imports: '', contributions: '', requirements: '');
  }
  final libraries = <String>{};
  for (final index in indexes.values) {
    for (final document in index.metadata) {
      if (_objects(document['uiRequirements']).isEmpty &&
          _objects(document['uiRenderers']).isEmpty)
        continue;
      libraries.add(
        'package:${index.packageName}/${'${document['uiLibrary']}'.substring(4)}',
      );
    }
  }
  if (libraries.isEmpty)
    return (imports: '', contributions: '', requirements: '');
  if (!workspace.host.dependencies.contains('ccrouter_ui')) {
    throw CCPackageWorkspaceException(
      'A UI Host must directly depend on ccrouter_ui.',
    );
  }
  final imports = StringBuffer(
    "import 'package:ccrouter_ui/ccrouter_ui_host.dart';\n",
  );
  final contributions = StringBuffer();
  final requirements = StringBuffer();
  var index = 0;
  for (final library in libraries.toList()..sort()) {
    final prefix = 'ui_package_${index++}';
    imports.writeln('import ${_dartLiteral(library)} as $prefix;');
    contributions.writeln('...$prefix.ccUIContributions,');
    requirements.writeln('...$prefix.ccUIRequirements,');
  }
  return (
    imports: imports.toString(),
    contributions: contributions.toString(),
    requirements: requirements.toString(),
  );
}
