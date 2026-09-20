part of 'package_workspace.dart';

/// Current schema of the source-location catalog embedded in Package indexes.
const int ccCapabilitySourceCatalogSchemaVersion = 1;

/// Capability kinds reserved by the source-catalog schema.
///
/// Route generation emits only `route` today. The remaining values let later
/// Service and messaging generators join the same discoverability model
/// without introducing parallel files or incompatible DevTools models.
const Set<String> _ccCapabilitySourceKinds = {
  'route',
  'service',
  'command',
  'action',
  'event',
};

/// A versioned, immutable inventory of framework capabilities and their code.
///
/// This type is tooling-internal even though its declaration is public within
/// `src/`: application and component code consume generated Markdown or future
/// CLI/DevTools views rather than importing generator implementation types.
final class CCCapabilitySourceCatalog {
  /// Creates a normalized catalog from validated records.
  CCCapabilitySourceCatalog(Iterable<CCCapabilitySourceRecord> records)
    : records = List.unmodifiable(_mergeCapabilityRecords(records));

  /// Capability records ordered by component, kind, and stable identity.
  final List<CCCapabilitySourceRecord> records;

  /// Builds Package-local or Host-wide records from normalized Builder data.
  ///
  /// Older metadata without exact line information remains readable: its
  /// source reference is retained with nullable coordinates, allowing a Host
  /// to consume one older dependency without inventing a filesystem path.
  factory CCCapabilitySourceCatalog.fromMetadata(
    Iterable<Map<String, Object?>> documents,
  ) {
    final records = <CCCapabilitySourceRecord>[];
    for (final document in documents) {
      final fallbackPackage = '${document['package'] ?? ''}';
      final fallbackSource = '${document['source'] ?? ''}';
      for (final route in _catalogObjectList(document['routes'])) {
        final id = '${route['id'] ?? ''}';
        final componentId = '${route['componentId'] ?? ''}';
        if (id.isEmpty || componentId.isEmpty) continue;
        final declaration = _catalogObject(route['declaration']);
        final contract = CCSourceReference.fromJson(
          declaration,
          fallbackPackage: '${declaration['package'] ?? fallbackPackage}',
          fallbackLibrary: '${declaration['library'] ?? fallbackSource}',
        );
        final declarationKind = '${declaration['kind'] ?? ''}';
        records.add(
          CCCapabilitySourceRecord(
            kind: 'route',
            id: id,
            componentId: componentId,
            packageName: contract.packageName,
            contract: contract,
            implementation: declarationKind == 'page' ? contract : null,
            generatedArtifacts: _catalogObjectList(
              route['generatedArtifacts'],
            ).map(CCGeneratedArtifact.fromJson),
          ),
        );
      }
      for (final implementation in _catalogObjectList(
        document['routeImplementations'],
      )) {
        final id = '${implementation['routeId'] ?? ''}';
        final componentId = '${implementation['componentId'] ?? ''}';
        if (id.isEmpty || componentId.isEmpty) continue;
        final contractObject = _catalogObject(implementation['contract']);
        final contract = contractObject.isEmpty
            ? null
            : CCSourceReference.fromJson(contractObject);
        final implementationSource = CCSourceReference.fromJson(
          _catalogObject(implementation['implementation']),
          fallbackPackage: '${implementation['package'] ?? fallbackPackage}',
          fallbackLibrary: '${implementation['source'] ?? fallbackSource}',
        );
        records.add(
          CCCapabilitySourceRecord(
            kind: 'route',
            id: id,
            componentId: componentId,
            packageName:
                contract?.packageName ?? implementationSource.packageName,
            contract: contract,
            implementation: implementationSource,
            generatedArtifacts: _catalogObjectList(
              implementation['generatedArtifacts'],
            ).map(CCGeneratedArtifact.fromJson),
          ),
        );
      }
    }
    return CCCapabilitySourceCatalog(records);
  }

  /// Decodes a published Package-index catalog and validates its closed schema.
  factory CCCapabilitySourceCatalog.fromJson(Map<String, Object?> json) {
    if (json['schemaVersion'] != ccCapabilitySourceCatalogSchemaVersion) {
      throw FormatException(
        'Unsupported capability source catalog schema: '
        '${json['schemaVersion']}.',
      );
    }
    return CCCapabilitySourceCatalog(
      _catalogObjectList(
        json['records'],
      ).map(CCCapabilitySourceRecord.fromJson),
    );
  }

  /// Encodes the canonical machine representation stored in a Package index.
  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': ccCapabilitySourceCatalogSchemaVersion,
    'records': [for (final record in records) record.toJson()],
  };

  /// Renders a deterministic source-discovery view for review and IDE search.
  ///
  /// Locations remain Package URIs so the same generated file works in a local
  /// workspace, Git checkout, Pub cache, or a future remote DevTools client.
  String toMarkdown({required String scope}) {
    final out = StringBuffer()
      ..writeln('# CCRouter Capability Sources')
      ..writeln()
      ..writeln('Scope: `$scope`. Generated file; do not edit by hand.')
      ..writeln()
      ..writeln(
        'Source locations use portable Package URIs. Line and column are '
        '1-based when the producing generator could resolve them.',
      )
      ..writeln();
    if (records.isEmpty) {
      out.writeln('No generated capabilities were found.');
      return out.toString();
    }
    String? currentComponent;
    for (final record in records) {
      if (currentComponent != record.componentId) {
        currentComponent = record.componentId;
        out
          ..writeln('## `${record.componentId}`')
          ..writeln();
      }
      out
        ..writeln('### ${_catalogKindLabel(record.kind)} `${record.id}`')
        ..writeln()
        ..writeln('- Declaring package: `${record.packageName}`');
      if (record.contract case final contract?) {
        out.writeln('- Contract/declaration: ${contract.markdownLocation}');
      }
      if (record.implementation case final implementation?) {
        out.writeln('- Implementation: ${implementation.markdownLocation}');
      }
      if (record.generatedArtifacts.isNotEmpty) {
        out.writeln('- Generated artifacts:');
        for (final artifact in record.generatedArtifacts) {
          out.writeln(
            '  - `${artifact.role}`: `${artifact.packageUri}` '
            '(`${artifact.symbol}`)',
          );
        }
      }
      out.writeln();
    }
    return out.toString();
  }
}

/// One capability identity linked to authored and generated declarations.
final class CCCapabilitySourceRecord {
  /// Creates one immutable source record.
  CCCapabilitySourceRecord({
    required this.kind,
    required this.id,
    required this.componentId,
    required this.packageName,
    required this.contract,
    required this.implementation,
    required Iterable<CCGeneratedArtifact> generatedArtifacts,
  }) : generatedArtifacts = List.unmodifiable(generatedArtifacts) {
    if (!_ccCapabilitySourceKinds.contains(kind) ||
        id.isEmpty ||
        componentId.isEmpty ||
        packageName.isEmpty) {
      throw FormatException('Invalid capability source record for "$id".');
    }
  }

  /// Closed capability category used for filtering and future DevTools views.
  final String kind;

  /// Stable route, service, or messaging identity.
  final String id;

  /// Component that owns the capability lifecycle.
  final String componentId;

  /// Package declaring the capability contract or local source declaration.
  final String packageName;

  /// Contract schema or source declaration from which the capability is built.
  final CCSourceReference? contract;

  /// Concrete page, provider, or handler when one is statically known.
  final CCSourceReference? implementation;

  /// Generated bridges relevant to maintainers, never runtime inputs.
  final List<CCGeneratedArtifact> generatedArtifacts;

  /// Decodes one record from a validated Package index.
  factory CCCapabilitySourceRecord.fromJson(Map<String, Object?> json) {
    final contract = json['contract'];
    final implementation = json['implementation'];
    return CCCapabilitySourceRecord(
      kind: '${json['kind'] ?? ''}',
      id: '${json['id'] ?? ''}',
      componentId: '${json['componentId'] ?? ''}',
      packageName: '${json['packageName'] ?? ''}',
      contract: contract is Map
          ? CCSourceReference.fromJson(contract.cast<String, Object?>())
          : null,
      implementation: implementation is Map
          ? CCSourceReference.fromJson(implementation.cast<String, Object?>())
          : null,
      generatedArtifacts: _catalogObjectList(
        json['generatedArtifacts'],
      ).map(CCGeneratedArtifact.fromJson),
    );
  }

  /// Encodes one deterministic machine record.
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind,
    'id': id,
    'componentId': componentId,
    'packageName': packageName,
    'contract': contract?.toJson(),
    'implementation': implementation?.toJson(),
    'generatedArtifacts': [
      for (final artifact in generatedArtifacts) artifact.toJson(),
    ],
  };
}

/// Portable location of one authored Dart declaration.
final class CCSourceReference {
  /// Creates an immutable Package-URI source reference.
  const CCSourceReference({
    required this.symbol,
    required this.packageUri,
    required this.line,
    required this.column,
  });

  /// Declared class or member name at the referenced source position.
  final String symbol;

  /// Portable URI beginning with `package:`.
  final String packageUri;

  /// One-based source line, or `null` for metadata from an older generator.
  final int? line;

  /// One-based source column, or `null` for metadata from an older generator.
  final int? column;

  /// Package identity parsed from [packageUri].
  String get packageName {
    final uri = Uri.tryParse(packageUri);
    if (uri?.scheme != 'package' || uri!.pathSegments.isEmpty) return '';
    return uri.pathSegments.first;
  }

  /// Human-readable location retaining symbol and exact coordinates.
  String get markdownLocation {
    final suffix = line == null
        ? ''
        : ':$line${column == null ? '' : ':$column'}';
    final symbolSuffix = symbol.isEmpty ? '' : ' (`$symbol`)';
    return '`$packageUri$suffix`$symbolSuffix';
  }

  /// Decodes a source reference, deriving Package URI for schema-v2 metadata.
  factory CCSourceReference.fromJson(
    Map<String, Object?> json, {
    String fallbackPackage = '',
    String fallbackLibrary = '',
  }) {
    final packageUri = '${json['packageUri'] ?? ''}'.trim();
    final effectiveUri = packageUri.isNotEmpty
        ? packageUri
        : _catalogPackageUri(fallbackPackage, fallbackLibrary);
    if (!effectiveUri.startsWith('package:')) {
      throw FormatException('Capability source must use a Package URI.');
    }
    return CCSourceReference(
      symbol: '${json['symbol'] ?? ''}',
      packageUri: effectiveUri,
      line: json['line'] is int ? json['line']! as int : null,
      column: json['column'] is int ? json['column']! as int : null,
    );
  }

  /// Encodes a portable source reference.
  Map<String, Object?> toJson() => <String, Object?>{
    'symbol': symbol,
    'packageUri': packageUri,
    'line': line,
    'column': column,
  };
}

/// Generated source file associated with a capability declaration.
final class CCGeneratedArtifact {
  /// Creates a generated artifact reference without source coordinates.
  const CCGeneratedArtifact({
    required this.role,
    required this.symbol,
    required this.packageUri,
  });

  /// Stable artifact role such as `routePart` or `routeContract`.
  final String role;

  /// Primary generated symbol useful for text search and diagnostics.
  final String symbol;

  /// Portable generated-library Package URI.
  final String packageUri;

  /// Decodes one generated artifact reference.
  factory CCGeneratedArtifact.fromJson(Map<String, Object?> json) {
    final artifact = CCGeneratedArtifact(
      role: '${json['role'] ?? ''}',
      symbol: '${json['symbol'] ?? ''}',
      packageUri: '${json['packageUri'] ?? ''}',
    );
    if (artifact.role.isEmpty ||
        artifact.symbol.isEmpty ||
        !artifact.packageUri.startsWith('package:')) {
      throw const FormatException('Invalid generated capability artifact.');
    }
    return artifact;
  }

  /// Encodes one deterministic generated artifact reference.
  Map<String, Object?> toJson() => <String, Object?>{
    'role': role,
    'symbol': symbol,
    'packageUri': packageUri,
  };
}

/// Merges partial contract and implementation records by stable capability ID.
List<CCCapabilitySourceRecord> _mergeCapabilityRecords(
  Iterable<CCCapabilitySourceRecord> records,
) {
  final merged = <String, CCCapabilitySourceRecord>{};
  for (final record in records) {
    final key = '${record.kind}\u0000${record.componentId}\u0000${record.id}';
    final previous = merged[key];
    if (previous == null) {
      merged[key] = record;
      continue;
    }
    final contract = _mergeSourceReference(
      previous.contract,
      record.contract,
      record.id,
      'contract',
    );
    final implementation = _mergeSourceReference(
      previous.implementation,
      record.implementation,
      record.id,
      'implementation',
    );
    final artifacts =
        <String, CCGeneratedArtifact>{
          for (final artifact in [
            ...previous.generatedArtifacts,
            ...record.generatedArtifacts,
          ])
            '${artifact.role}\u0000${artifact.packageUri}\u0000${artifact.symbol}':
                artifact,
        }.values.toList()..sort((left, right) {
          final role = left.role.compareTo(right.role);
          if (role != 0) return role;
          final uri = left.packageUri.compareTo(right.packageUri);
          return uri != 0 ? uri : left.symbol.compareTo(right.symbol);
        });
    merged[key] = CCCapabilitySourceRecord(
      kind: record.kind,
      id: record.id,
      componentId: record.componentId,
      packageName: contract?.packageName ?? previous.packageName,
      contract: contract,
      implementation: implementation,
      generatedArtifacts: artifacts,
    );
  }
  final result = merged.values.toList()
    ..sort((left, right) {
      final component = left.componentId.compareTo(right.componentId);
      if (component != 0) return component;
      final kind = left.kind.compareTo(right.kind);
      return kind != 0 ? kind : left.id.compareTo(right.id);
    });
  return result;
}

/// Selects one equal source reference or rejects conflicting generated facts.
CCSourceReference? _mergeSourceReference(
  CCSourceReference? left,
  CCSourceReference? right,
  String capabilityId,
  String role,
) {
  if (left == null) return right;
  if (right == null) return left;
  if (computeCCCanonicalJsonFingerprint(left.toJson()) !=
      computeCCCanonicalJsonFingerprint(right.toJson())) {
    throw FormatException(
      'Capability "$capabilityId" has conflicting $role source locations.',
    );
  }
  return left;
}

/// Converts old Package-relative metadata paths into Package URIs.
String _catalogPackageUri(String package, String library) {
  if (package.isEmpty || !library.startsWith('lib/')) return '';
  return 'package:$package/${library.substring('lib/'.length)}';
}

/// Converts one loosely typed JSON value to a string-keyed object.
Map<String, Object?> _catalogObject(Object? value) =>
    value is Map ? value.cast<String, Object?>() : const <String, Object?>{};

/// Converts one loosely typed JSON array to string-keyed objects.
List<Map<String, Object?>> _catalogObjectList(Object? value) => value is List
    ? value
          .whereType<Map>()
          .map((entry) => entry.cast<String, Object?>())
          .toList()
    : <Map<String, Object?>>[];

/// Renders one closed capability kind without exposing raw schema casing.
String _catalogKindLabel(String kind) => switch (kind) {
  'route' => 'Route',
  'service' => 'Service',
  'command' => 'Command',
  'action' => 'Action',
  'event' => 'Event',
  _ => kind,
};
