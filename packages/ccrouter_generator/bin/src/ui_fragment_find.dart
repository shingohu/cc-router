import 'dart:io';

import 'package:ccrouter_generator/src/generated_client_naming.dart';
import 'package:ccrouter_generator/src/package_workspace.dart';

/// One UI Contract read from a validated Package index, without source scans.
final class UIFragmentMatch {
  /// Retains the declaring Package and its authored metadata.
  const UIFragmentMatch(this.packageName, this.contract);

  /// Package containing the marker declaration.
  final String packageName;

  /// Contract shape, public import proofs and portable declaration location.
  final Map<String, Object?> contract;
}

/// Finds exact UI IDs without adding a kind to the legacy DevTools catalog.
List<UIFragmentMatch> findUIFragments(
  Map<String, CCPackageIndex> indexes,
  String query,
) => [
  for (final entry in indexes.entries)
    for (final document in entry.value.metadata)
      for (final contract in _objects(document['uiContracts']))
        if (contract['id'] == query) UIFragmentMatch(entry.key, contract),
];

/// Prints locations and a read-only recipe using only published index facts.
bool printUIFragmentMatches({
  required List<UIFragmentMatch> matches,
  required CCPackageWorkspace resolved,
  required Map<String, CCPackageIndex> indexes,
  String? consumerId,
}) {
  final documents = indexes.values.expand((index) => index.metadata).toList();
  for (final match in matches) {
    final contract = match.contract;
    stdout.writeln(
      'UI Fragment ${contract['id']} '
      '(component: ${contract['componentId']})',
    );
    stdout.writeln('  Declaring package: ${match.packageName}');
    _printLocation('Contract/declaration', contract['declaration']);
    final renderers = [
      for (final document in documents)
        for (final renderer in _objects(document['uiRenderers']))
          if (_sameContract(renderer, contract)) renderer,
    ];
    if (renderers.isEmpty) {
      stdout.writeln(
        '  Renderer: missing in the selected dependency closure; '
        'include the Owner implementation and regenerate the actual Host.',
      );
    } else {
      for (final renderer in renderers) {
        _printLocation('Implementation', renderer['implementation']);
      }
      if (renderers.length > 1) {
        stderr.writeln(
          'UI Fragment has multiple Renderers; regenerate and '
          'resolve duplicate implementations before integrating.',
        );
        return false;
      }
    }
  }
  if (consumerId == null) return true;
  if (matches.length != 1) {
    stderr.writeln('`--usage` requires one unique capability match.');
    return false;
  }
  final match = matches.single;
  final contract = match.contract;
  final consumers = [
    for (final entry in indexes.entries)
      for (final document in entry.value.metadata)
        for (final component in _objects(document['components']))
          if (component['id'] == consumerId)
            (package: entry.key, component: component),
  ];
  if (consumers.length != 1) {
    stderr.writeln(
      'Consumer component "$consumerId" was not found uniquely '
      'in the selected Host dependency closure.',
    );
    return false;
  }
  final consumer = consumers.single;
  stdout.writeln('Usage recipe for component $consumerId');
  stdout.writeln('  Consumer package: ${consumer.package}');
  stdout.writeln('  Owner component: ${contract['componentId']}');
  if (consumerId == contract['componentId']) {
    stdout.writeln(
      '  Use the ordinary local Widget; UI consumption requires '
      'an external Owner. No self dependency is suggested.',
    );
    return true;
  }
  final types = _objects(contract['publicTypes']);
  if (types.isEmpty ||
      types.any((type) => _strings(type['publicLibraries']).isEmpty)) {
    stdout.writeln(
      '  Public import: unavailable for the complete UI schema; '
      'explicitly export marker, Props and Action through public barrels '
      'and regenerate with the current Generator. No dependency edit is suggested.',
    );
    return true;
  }
  final requiredPackages = <String>{'ccrouter_ui'};
  final imports = <String>{};
  for (final type in types) {
    requiredPackages.add('${type['package']}');
    final libraries = _strings(type['publicLibraries'])..sort();
    final canonical = 'package:${type['package']}/${type['package']}.dart';
    imports.add(libraries.contains(canonical) ? canonical : libraries.first);
  }
  for (final uri in imports.toList()..sort()) {
    stdout.writeln('  Public import: $uri');
  }
  stdout.writeln('  Framework import: package:ccrouter_ui/ccrouter_ui.dart');
  final consumerPackage = resolved.packages[consumer.package]!;
  for (final package in requiredPackages.toList()..sort()) {
    final satisfied =
        package == consumer.package ||
        consumerPackage.dependencies.contains(package);
    stdout.writeln(
      '  Pub dependency: ${satisfied ? 'satisfied' : 'missing'} ($package)',
    );
    if (!satisfied)
      stdout.writeln(
        '  Add a direct dependency on $package using '
        'the source and version approved by this workspace.',
      );
  }
  final ownerSatisfied = _strings(
    consumer.component['dependencies'],
  ).contains(contract['componentId']);
  stdout.writeln(
    '  Owner dependency: ${ownerSatisfied ? 'satisfied' : 'missing'} '
    '(${contract['componentId']}; required edge)',
  );
  if (!ownerSatisfied)
    stdout.writeln(
      '  Add the public Owner CCComponentId to '
      'CCComponent.dependencies; optionalDependencies is insufficient.',
    );
  final requirements = [
    for (final document in documents)
      for (final requirement in _objects(document['uiRequirements']))
        if (requirement['consumer'] == consumerId &&
            _sameContract(requirement, contract))
          requirement,
  ];
  if (requirements.length > 1) {
    stderr.writeln(
      'Duplicate UI dependencies; keep one Contract edge and regenerate.',
    );
    return false;
  }
  stdout.writeln(
    '  UI dependency: ${requirements.isEmpty ? 'missing' : 'satisfied'}',
  );
  final declaration = contract['declaration'];
  final marker = declaration is Map ? declaration['symbol'] : null;
  final existingAlias = requirements.isEmpty
      ? null
      : requirements.single['alias'];
  // Old indexes do not retain aliases; never guess their generated member.
  final alias = existingAlias is String ? existingAlias : null;
  if (requirements.isEmpty && marker is String) {
    stdout.writeln(
      '  Add to uiDependencies: CCUIFragmentDependency<$marker>('
      'versionRange: \'^${contract['version']}\', alias: \'chooseUniqueAlias\')',
    );
    stdout.writeln(
      '  Replace chooseUniqueAlias with a unique public lowerCamelCase member.',
    );
  }
  if (alias != null && isGeneratedClientMemberName(alias)) {
    final client =
        '${consumerId.split(RegExp(r'[._-]')).map((part) => '${part[0].toUpperCase()}${part.substring(1)}').join()}Fragments';
    stdout.writeln(
      '  Generated API entry: package:${consumer.package}/src/'
      'ccrouter_generated/$consumerId.ui.api.g.dart',
    );
    stdout.writeln('  Generated Client: $client.$alias');
    stdout.writeln(
      '  Typed call: $client.$alias(key: ValueKey(instanceId), '
      'props: props, onAction: (action) { /* consumer decision */ }, active: isActive)',
    );
  } else {
    stdout.writeln(
      '  Generated Client: available after declaring an alias and '
      'regenerating; old metadata without alias must be regenerated.',
    );
  }
  stdout.writeln(
    '  Multiple instances share one dependency and use distinct stable Keys. '
    'Hidden kept-alive Tabs pass active: false; State owns resource cleanup.',
  );
  stdout.writeln(
    '  Include A/B implementations and a direct ccrouter_ui dependency '
    'in the actual Host, then run ccrouter generate <host-root> --no-cache --check '
    'after generation and stopping any active watch.',
  );
  return true;
}

/// Compares both capability ownership and declaration identity when available.
bool _sameContract(Map<String, Object?> left, Map<String, Object?> right) {
  if (left['componentId'] != right['componentId'] || left['id'] != right['id'])
    return false;
  final a = left['declaration'];
  final b = right['declaration'];
  return a is Map &&
      b is Map &&
      a['packageUri'] == b['packageUri'] &&
      a['symbol'] == b['symbol'];
}

/// Prints optional locations without fabricating missing line numbers.
void _printLocation(String label, Object? location) {
  if (location is! Map || location['packageUri'] is! String) return;
  final line = location['line'];
  final column = location['column'];
  stdout.writeln(
    '  $label: ${location['packageUri']}'
    '${line is int && column is int ? ':$line:$column' : ''} (${location['symbol']})',
  );
}

/// Copies generated maps for read-only lookup.
List<Map<String, Object?>> _objects(Object? value) => value is List
    ? value.whereType<Map>().map((e) => e.cast<String, Object?>()).toList()
    : [];

/// Reads string arrays without relying on decoded JSON runtime generics.
List<String> _strings(Object? value) =>
    value is List ? value.whereType<String>().toList() : [];
