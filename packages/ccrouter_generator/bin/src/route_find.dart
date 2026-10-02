import 'dart:io';

import 'package:ccrouter_generator/src/generated_client_naming.dart';
import 'package:ccrouter_generator/src/package_workspace.dart';

/// Prints capabilities matching an exact ID or Route Pattern in one Host closure.
///
/// This lookup consumes validated published Package indexes without running
/// builders or scanning source files. It does not resolve a concrete URL with
/// dynamic Path parameters; that remains a Runtime navigation operation.
Future<bool> findCapability({
  required Directory buildRoot,
  required Directory hostRoot,
  required bool workspace,
  required String query,
  String? usageComponentId,
}) async {
  final resolved = await CCPackageWorkspace.load(
    buildRoot: buildRoot,
    hostRoot: hostRoot,
    workspace: workspace,
  );
  final indexes = <String, CCPackageIndex>{};
  final records = <CCCapabilitySourceRecord>[];
  final patterns = <String, Set<_DeclaredPattern>>{};
  final matchingIds = <String>{};
  for (final package in resolved.packages.values) {
    if (!package.indexFile.existsSync()) {
      if (package == resolved.host || package.requiresPackageIndex) {
        throw CCPackageWorkspaceException(
          'CCRouter Package index is missing for "${package.name}". '
          'Run `ccrouter generate ${hostRoot.path}` before searching.',
        );
      }
      continue;
    }
    final index = await CCPackageIndex.read(package, verifyBundle: false);
    indexes[package.name] = index;
    records.addAll(index.capabilityCatalog.records);
    for (final document in index.metadata) {
      final routes = document['routes'];
      if (routes is! List) continue;
      for (final rawRoute in routes.whereType<Map>()) {
        final route = rawRoute.cast<String, Object?>();
        final id = route['id'];
        if (id is! String || id.isEmpty) continue;
        if (id == query) matchingIds.add(id);
        final rawPatterns = route['patterns'];
        if (rawPatterns is! List) continue;
        for (final rawPattern in rawPatterns.whereType<Map>()) {
          final pattern = rawPattern.cast<String, Object?>();
          final value = pattern['value'];
          if (value is! String || value.isEmpty) continue;
          patterns
              .putIfAbsent(id, () => <_DeclaredPattern>{})
              .add(_DeclaredPattern(value, pattern['primary'] == true));
          if (value == query) matchingIds.add(id);
        }
      }
    }
  }

  for (final entry in indexes.entries) {
    final package = resolved.packages[entry.key]!;
    final expectedNames = package.dependencies
        .where(indexes.containsKey)
        .toSet();
    final recorded = {
      for (final dependency in entry.value.dependencies)
        dependency.name: dependency,
    };
    if (recorded.length != entry.value.dependencies.length ||
        !recorded.keys.toSet().containsAll(expectedNames) ||
        !expectedNames.containsAll(recorded.keys)) {
      throw CCPackageWorkspaceException(
        'Package index for "${package.name}" has stale direct generated '
        'dependencies. Run `ccrouter generate ${hostRoot.path}` and retry.',
      );
    }
    for (final name in expectedNames) {
      final expected = indexes[name]!;
      final dependency = recorded[name]!;
      if (dependency.version != expected.packageVersion ||
          dependency.contentFingerprint != expected.contentFingerprint) {
        throw CCPackageWorkspaceException(
          'Package index for "${package.name}" references a different '
          '"$name" identity. Generation may be in progress or the indexes '
          'are stale; retry after `ccrouter generate ${hostRoot.path}`.',
        );
      }
    }
  }

  final catalog = CCCapabilitySourceCatalog(records);
  final matches = catalog.records
      .where(
        (record) =>
            record.id == query ||
            (record.kind == 'route' && matchingIds.contains(record.id)),
      )
      .toList(growable: false);
  if (matches.isEmpty) {
    stderr.writeln(
      'No capability matched the exact ID or Route declared Pattern.',
    );
    return false;
  }
  for (final record in matches) {
    stdout.writeln(
      '${_capabilityKindLabel(record.kind)} ${record.id} '
      '(component: ${record.componentId})',
    );
    stdout.writeln('  Declaring package: ${record.packageName}');
    if (record.contract case final contract?) {
      stdout.writeln('  Contract/declaration: ${_sourceLocation(contract)}');
    }
    if (record.implementation case final implementation?) {
      stdout.writeln('  Implementation: ${_sourceLocation(implementation)}');
    }
    final declared = record.kind == 'route'
        ? (patterns[record.id]?.toList() ?? <_DeclaredPattern>[])
        : <_DeclaredPattern>[];
    declared.sort((left, right) {
      if (left.primary != right.primary) return left.primary ? -1 : 1;
      return left.value.compareTo(right.value);
    });
    for (final pattern in declared) {
      stdout.writeln(
        '  Pattern: ${pattern.value}${pattern.primary ? ' (primary)' : ''}',
      );
    }
    for (final artifact in record.generatedArtifacts) {
      stdout.writeln(
        '  Generated ${artifact.role}: ${artifact.packageUri} '
        '(${artifact.symbol})',
      );
    }
  }
  if (usageComponentId != null) {
    if (matches.length != 1) {
      stderr.writeln(
        '`--usage` requires one unique capability match; the query matched '
        '${matches.length}.',
      );
      return false;
    }
    return _printUsageRecipe(
      resolved: resolved,
      indexes: indexes,
      record: matches.single,
      consumerComponentId: usageComponentId,
    );
  }
  return true;
}

/// Prints one non-mutating component integration recipe from Package indexes.
bool _printUsageRecipe({
  required CCPackageWorkspace resolved,
  required Map<String, CCPackageIndex> indexes,
  required CCCapabilitySourceRecord record,
  required String consumerComponentId,
}) {
  final components = _componentFacts(indexes);
  final consumer = components[consumerComponentId];
  if (consumer == null) {
    stderr.writeln(
      'Consumer component "$consumerComponentId" was not found in the '
      'selected Host dependency closure.',
    );
    return false;
  }
  final contract = _contractFact(indexes, record);
  if (contract == null) {
    stderr.writeln(
      'Capability "${record.id}" has no generated Contract metadata. '
      'A usage recipe cannot be proven for this migration-only capability.',
    );
    return false;
  }
  final consumerPackage = resolved.packages[consumer.packageName];
  if (consumerPackage == null) {
    stderr.writeln(
      'Consumer Package "${consumer.packageName}" is absent from Pub '
      'resolution.',
    );
    return false;
  }

  stdout.writeln('Usage recipe for component $consumerComponentId');
  stdout.writeln('  Consumer package: ${consumer.packageName}');
  stdout.writeln('  Owner component: ${record.componentId}');
  stdout.writeln('  Contract package: ${contract.packageName}');
  final publicLibraries = _preferredPublicLibraries(contract);
  if (publicLibraries.isEmpty) {
    stdout.writeln(
      '  Public import: unavailable; this capability is not exposed by a '
      'verified public barrel or its published Index predates this fact.',
    );
  } else {
    for (final library in publicLibraries) {
      stdout.writeln('  Public import: $library');
    }
  }
  if (consumerComponentId != record.componentId && publicLibraries.isEmpty) {
    stdout.writeln(
      '  Cross-component usage: unavailable until the Contract is publicly '
      'exported and regenerated; no dependency edit is suggested.',
    );
    return true;
  }
  final hasPackageDependency =
      consumer.packageName == contract.packageName ||
      consumerPackage.dependencies.contains(contract.packageName);
  stdout.writeln(
    '  Pub dependency: ${hasPackageDependency ? 'satisfied' : 'missing'} '
    '(${contract.packageName})',
  );
  if (!hasPackageDependency) {
    stdout.writeln(
      '  Add a direct pubspec dependency on ${contract.packageName} using '
      'the source and version approved by this workspace.',
    );
  }

  if (consumerComponentId == record.componentId) {
    _printOwnerUsage(record, contract, consumer);
    return true;
  }

  switch (record.kind) {
    case 'route':
      _printRouteUsage(contract);
    case 'service':
      _printServiceUsage(record, contract, consumer);
    case 'command':
      _printCommandUsage(record, contract, consumer);
    case 'event':
      _printEventUsage(record, contract, consumer, indexes);
    case 'initTask':
      _printInitTaskUsage(record, contract, consumer, indexes);
    default:
      stderr.writeln(
        'No integration recipe is defined for capability kind '
        '"${record.kind}".',
      );
      return false;
  }
  return true;
}

/// Prefers the canonical Package barrel while retaining proven alternatives.
List<String> _preferredPublicLibraries(_ContractFact contract) {
  final canonical =
      'package:${contract.packageName}/${contract.packageName}.dart';
  if (contract.publicLibraries.contains(canonical)) return [canonical];
  return contract.publicLibraries;
}

/// Explains the narrower same-owner API instead of suggesting a fake edge.
void _printOwnerUsage(
  CCCapabilitySourceRecord record,
  _ContractFact contract,
  _ComponentFact consumer,
) {
  stdout.writeln(
    '  Owner dependency: not applicable (consumer owns the capability)',
  );
  switch (record.kind) {
    case 'route':
      _printRouteUsage(contract);
    case 'service':
      stdout.writeln(
        '  Use local lookup: CCRouter.service<${contract.symbol}>()',
      );
    case 'command':
      final member = _clientMember(contract, command: true);
      stdout.writeln(
        '  Generated API: ${_clientClass(consumer.id, 'Commands')}.$member',
      );
    case 'event':
      stdout.writeln(
        '  Use the owner Event publication Client; no subscriber dependency '
        'is required for publishing.',
      );
    case 'initTask':
      stdout.writeln(
        '  InitTask execution remains Host/Gate-owned; business code does not '
        'invoke a generated task Client.',
      );
  }
}

/// Prints typed navigation guidance without introducing a component edge.
void _printRouteUsage(_ContractFact contract) {
  final routeType =
      '${contract.data['contracts'] is Map ? (contract.data['contracts'] as Map)['route'] : ''}';
  final resultType = '${contract.data['resultType'] ?? 'void'}';
  stdout.writeln('  Owner dependency: not required for a Route Contract');
  stdout.writeln(
    '  Typed call: CCRouter.navigator.push<$resultType>('
    '$routeType.intent(...))',
  );
}

/// Prints the exact Service owner edge, dependency declaration, and Client.
void _printServiceUsage(
  CCCapabilitySourceRecord record,
  _ContractFact contract,
  _ComponentFact consumer,
) {
  final hasOwner = consumer.dependencies.contains(record.componentId);
  final dependency = consumer.serviceDependencies.cast<Map?>().firstWhere(
    (candidate) =>
        candidate?['id'] == record.id &&
        candidate?['componentId'] == record.componentId,
    orElse: () => null,
  );
  final member = dependency?['member'] is String
      ? dependency!['member']! as String
      : _clientMember(contract, command: false);
  stdout.writeln(
    '  Owner dependency: ${hasOwner ? 'satisfied' : 'missing'} '
    '(${record.componentId})',
  );
  if (!hasOwner) {
    _printOwnerDependencySuggestion(record.componentId);
  }
  stdout.writeln(
    '  Service dependency: ${dependency == null ? 'missing' : 'satisfied'}',
  );
  if (dependency == null) {
    stdout.writeln(
      '  Add to serviceDependencies: '
      'CCServiceDependency<${contract.symbol}>()',
    );
  }
  _printGeneratedClient(
    consumer,
    '${_clientClass(consumer.id, 'Services')}.$member',
  );
}

/// Prints the exact Command owner edge, dependency declaration, and Client.
void _printCommandUsage(
  CCCapabilitySourceRecord record,
  _ContractFact contract,
  _ComponentFact consumer,
) {
  final hasOwner = consumer.dependencies.contains(record.componentId);
  final dependency = consumer.commandDependencies.cast<Map?>().firstWhere(
    (candidate) =>
        candidate?['id'] == record.id &&
        candidate?['componentId'] == record.componentId,
    orElse: () => null,
  );
  final member = dependency?['member'] is String
      ? dependency!['member']! as String
      : _clientMember(contract, command: true);
  stdout.writeln(
    '  Owner dependency: ${hasOwner ? 'satisfied' : 'missing'} '
    '(${record.componentId})',
  );
  if (!hasOwner) {
    _printOwnerDependencySuggestion(record.componentId);
  }
  stdout.writeln(
    '  Command dependency: ${dependency == null ? 'missing' : 'satisfied'}',
  );
  if (dependency == null) {
    stdout.writeln(
      '  Add to commandDependencies: '
      'CCCommandDependency<${contract.symbol}>()',
    );
  }
  _printGeneratedClient(
    consumer,
    '${_clientClass(consumer.id, 'Commands')}.$member',
  );
}

/// Prints Event subscription guidance without inventing `eventDependencies`.
void _printEventUsage(
  CCCapabilitySourceRecord record,
  _ContractFact contract,
  _ComponentFact consumer,
  Map<String, CCPackageIndex> indexes,
) {
  final subscriptions = _allDocuments(indexes)
      .expand((document) => _objects(document['eventSubscriptions']))
      .where(
        (subscription) =>
            subscription['eventId'] == record.id &&
            subscription['componentId'] == consumer.id,
      )
      .toList(growable: false);
  final hasOwner =
      consumer.dependencies.contains(record.componentId) ||
      consumer.optionalDependencies.contains(record.componentId);
  stdout.writeln(
    '  Owner dependency: ${hasOwner ? 'satisfied' : 'missing'} '
    '(${record.componentId}; required or optional is allowed)',
  );
  if (!hasOwner) {
    stdout.writeln(
      '  Declare component ${record.componentId} in required or optional '
      'dependencies before adding the subscription.',
    );
  }
  stdout.writeln(
    '  Event subscription: '
    '${subscriptions.isEmpty ? 'missing' : 'satisfied'}',
  );
  if (subscriptions.isEmpty) {
    stdout.writeln(
      '  Add a public top-level @CCEventSubscription function accepting '
      '${contract.symbol}; there is no eventDependencies list.',
    );
  }
}

/// Prints typed InitTask DAG guidance without inventing a business Client.
void _printInitTaskUsage(
  CCCapabilitySourceRecord record,
  _ContractFact contract,
  _ComponentFact consumer,
  Map<String, CCPackageIndex> indexes,
) {
  final dependentTasks = _allDocuments(indexes)
      .expand((document) => _objects(document['initTasks']))
      .where(
        (task) =>
            task['componentId'] == consumer.id &&
            _strings(task['dependsOn']).contains(record.id),
      )
      .toList(growable: false);
  final hasOwner = consumer.dependencies.contains(record.componentId);
  stdout.writeln(
    '  Owner dependency: ${hasOwner ? 'satisfied' : 'missing'} '
    '(${record.componentId})',
  );
  if (!hasOwner) {
    _printOwnerDependencySuggestion(record.componentId);
  }
  stdout.writeln(
    '  InitTask dependency: '
    '${dependentTasks.isEmpty ? 'missing' : 'satisfied'}',
  );
  if (dependentTasks.isEmpty) {
    stdout.writeln(
      '  Add ${contract.symbol} to the dependsOn list of the consuming '
      '@CCInitTask; no task Client is generated.',
    );
  }
}

/// Prints an actionable required edge without guessing a Dart constant name.
void _printOwnerDependencySuggestion(String ownerComponentId) {
  stdout.writeln(
    '  Declare component $ownerComponentId in required dependencies; '
    'use the public owner constant exposed by its Contract package.',
  );
}

/// Prints the stable generated component barrel and callable member.
void _printGeneratedClient(_ComponentFact consumer, String symbol) {
  stdout.writeln(
    '  Generated API entry: package:${consumer.packageName}/src/'
    'ccrouter_generated/${consumer.id}.api.g.dart',
  );
  stdout.writeln('  Generated Client: $symbol');
  stdout.writeln(
    '  Regenerate after applying the authored dependency changes.',
  );
}

/// Returns the generated member from Contract alias or stable type fallback.
String _clientMember(_ContractFact contract, {required bool command}) {
  final alias = contract.data['alias'];
  if (alias is String && alias.isNotEmpty) return alias;
  return command
      ? defaultCommandClientMember(contract.symbol)
      : defaultServiceClientMember(contract.symbol);
}

/// Reproduces the generated component Client owner naming rule.
String _clientClass(String componentId, String suffix) {
  final owner = componentId.endsWith('_component')
      ? componentId.substring(0, componentId.length - '_component'.length)
      : componentId;
  final pascal = owner
      .split(RegExp('[^A-Za-z0-9]+'))
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join();
  return '$pascal$suffix';
}

/// Builds exact component facts from generated component metadata.
Map<String, _ComponentFact> _componentFacts(
  Map<String, CCPackageIndex> indexes,
) {
  final result = <String, _ComponentFact>{};
  for (final entry in indexes.entries) {
    for (final document in entry.value.metadata) {
      for (final component in _objects(document['components'])) {
        final id = '${component['id'] ?? ''}';
        if (id.isEmpty) continue;
        final fact = _ComponentFact(
          id: id,
          packageName: entry.key,
          dependencies: _strings(component['dependencies']),
          optionalDependencies: _strings(component['optionalDependencies']),
          serviceDependencies: _objects(component['serviceDependencies']),
          commandDependencies: _objects(component['commandDependencies']),
        );
        final previous = result[id];
        if (previous != null && previous.packageName != fact.packageName) {
          throw FormatException(
            'Component "$id" is declared by multiple Packages.',
          );
        }
        result[id] = fact;
      }
    }
  }
  return result;
}

/// Finds the Contract metadata underlying one merged source record.
_ContractFact? _contractFact(
  Map<String, CCPackageIndex> indexes,
  CCCapabilitySourceRecord record,
) {
  final group = switch (record.kind) {
    'service' => 'serviceContracts',
    'command' => 'commandContracts',
    'event' => 'eventContracts',
    'initTask' => 'initTaskContracts',
    _ => null,
  };
  for (final entry in indexes.entries) {
    for (final document in entry.value.metadata) {
      if (record.kind == 'route') {
        for (final route in _objects(document['routes'])) {
          if (route['id'] != record.id ||
              route['componentId'] != record.componentId ||
              route['exposure'] == 'internal') {
            continue;
          }
          final contracts = route['contracts'];
          if (contracts is! Map) continue;
          return _ContractFact(
            packageName: '${contracts['package'] ?? entry.key}',
            symbol: '${contracts['route'] ?? ''}',
            publicLibraries: _strings(contracts['publicLibraries']),
            data: route,
          );
        }
        continue;
      }
      if (group == null) continue;
      for (final contract in _objects(document[group])) {
        if (contract['id'] != record.id ||
            contract['componentId'] != record.componentId) {
          continue;
        }
        final declaration = contract['declaration'];
        final symbol = declaration is Map
            ? '${declaration['symbol'] ?? contract['type'] ?? ''}'
            : '${contract['type'] ?? ''}';
        return _ContractFact(
          packageName: '${contract['package'] ?? entry.key}',
          symbol: symbol,
          publicLibraries: _strings(contract['publicLibraries']),
          data: contract,
        );
      }
    }
  }
  return null;
}

/// Flattens validated Package metadata without touching source files.
Iterable<Map<String, Object?>> _allDocuments(
  Map<String, CCPackageIndex> indexes,
) sync* {
  for (final index in indexes.values) {
    yield* index.metadata;
  }
}

/// Converts one generated JSON array into mutable string-keyed objects.
List<Map<String, Object?>> _objects(Object? value) => value is List
    ? value
          .whereType<Map>()
          .map((entry) => entry.cast<String, Object?>())
          .toList(growable: false)
    : const [];

/// Converts one generated JSON array into immutable string values.
List<String> _strings(Object? value) => value is List
    ? value.whereType<String>().toList(growable: false)
    : const [];

/// Generated facts for one consumer component in the selected Host closure.
final class _ComponentFact {
  /// Creates one immutable component fact from Package metadata.
  const _ComponentFact({
    required this.id,
    required this.packageName,
    required this.dependencies,
    required this.optionalDependencies,
    required this.serviceDependencies,
    required this.commandDependencies,
  });

  /// Stable component identity.
  final String id;

  /// Package containing the component descriptor.
  final String packageName;

  /// Required owner component identities.
  final List<String> dependencies;

  /// Optional owner component identities.
  final List<String> optionalDependencies;

  /// Exact Service contracts already consumed by the component.
  final List<Map<String, Object?>> serviceDependencies;

  /// Exact Command contracts already consumed by the component.
  final List<Map<String, Object?>> commandDependencies;
}

/// Contract declaration facts needed for one read-only usage recipe.
final class _ContractFact {
  /// Creates one immutable Contract fact from generated metadata.
  const _ContractFact({
    required this.packageName,
    required this.symbol,
    required this.publicLibraries,
    required this.data,
  });

  /// Package declaring the Contract.
  final String packageName;

  /// Public authored or generated Contract symbol.
  final String symbol;

  /// Proven public Package imports that expose [symbol].
  final List<String> publicLibraries;

  /// Kind-specific metadata used to render typed examples.
  final Map<String, Object?> data;
}

/// Presents one closed catalog kind without exposing schema casing.
String _capabilityKindLabel(String kind) => switch (kind) {
  'route' => 'Route',
  'service' => 'Service',
  'command' => 'Command',
  'action' => 'Action',
  'event' => 'Event',
  'initTask' => 'InitTask',
  _ => kind,
};

/// Renders a portable declaration position without Markdown formatting.
String _sourceLocation(CCSourceReference source) {
  final line = source.line;
  final position = line == null
      ? ''
      : ':$line${source.column == null ? '' : ':${source.column}'}';
  final symbol = source.symbol.isEmpty ? '' : ' (${source.symbol})';
  return '${source.packageUri}$position$symbol';
}

/// One declared, reversible or regex Pattern used only for CLI display.
final class _DeclaredPattern {
  /// Keeps the primary marker alongside its exact declaration text.
  const _DeclaredPattern(this.value, this.primary);

  /// Generated Pattern value, not a URL resolved at runtime.
  final String value;

  /// Whether this Pattern is the canonical address generator.
  final bool primary;

  @override
  bool operator ==(Object other) =>
      other is _DeclaredPattern &&
      other.value == value &&
      other.primary == primary;

  @override
  int get hashCode => Object.hash(value, primary);
}
