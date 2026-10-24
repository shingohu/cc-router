import 'dart:convert';

part 'runtime_diagnostics.dart';

/// Current wire version for CCRouter DevTools snapshot envelopes.
const ccRouterDevToolsProtocolVersion = 1;

/// A source location that can be opened by a tooling client.
final class CCDevToolsSourceLocation {
  /// Creates a portable source location.
  const CCDevToolsSourceLocation({
    required this.packageName,
    required this.packageUri,
    required this.line,
    required this.column,
  }) : assert(packageName != ''),
       assert(packageUri != ''),
       assert(line > 0),
       assert(column > 0);

  /// Pub package containing the source file.
  final String packageName;

  /// Portable `package:` URI of the source file.
  final String packageUri;

  /// One-based source line.
  final int line;

  /// One-based source column.
  final int column;

  /// Encodes this location as a stable JSON object.
  Map<String, Object> toJson() => <String, Object>{
    'package': packageName,
    'uri': packageUri,
    'line': line,
    'column': column,
  };

  /// Decodes a location from a validated JSON object.
  factory CCDevToolsSourceLocation.fromJson(Map<String, Object?> json) =>
      CCDevToolsSourceLocation(
        packageName: _requiredString(json, 'package'),
        packageUri: _requiredString(json, 'uri'),
        line: _requiredPositiveInt(json, 'line'),
        column: _requiredPositiveInt(json, 'column'),
      );
}

/// One statically generated capability or component record.
final class CCDevToolsCatalogRecord {
  /// Creates a static catalog record.
  const CCDevToolsCatalogRecord({
    required this.kind,
    required this.id,
    required this.ownerComponentId,
    required this.packageName,
    this.source,
    this.description,
  }) : assert(kind != ''),
       assert(id != ''),
       assert(ownerComponentId != ''),
       assert(packageName != '');

  /// Capability kind such as `route`, `service`, `command`, or `event`.
  final String kind;

  /// Stable capability or component identity.
  final String id;

  /// Component that owns the record.
  final String ownerComponentId;

  /// Package that declared the record.
  final String packageName;

  /// Authored source location, when available.
  final CCDevToolsSourceLocation? source;

  /// Non-sensitive developer-facing description.
  final String? description;

  /// Encodes this record as a stable JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind,
    'id': id,
    'ownerComponentId': ownerComponentId,
    'package': packageName,
    if (source != null) 'source': source!.toJson(),
    if (description != null) 'description': description,
  };

  /// Decodes a catalog record from a validated JSON object.
  factory CCDevToolsCatalogRecord.fromJson(Map<String, Object?> json) =>
      CCDevToolsCatalogRecord(
        kind: _requiredString(json, 'kind'),
        id: _requiredString(json, 'id'),
        ownerComponentId: _requiredString(json, 'ownerComponentId'),
        packageName: _requiredString(json, 'package'),
        source: _optionalObject(
          json,
          'source',
          CCDevToolsSourceLocation.fromJson,
        ),
        description: _optionalString(json, 'description'),
      );
}

/// One statically generated component node used by the dependency graph.
final class CCDevToolsCatalogComponent {
  /// Creates a component node with deterministic dependency lists.
  CCDevToolsCatalogComponent({
    required this.id,
    required this.version,
    Iterable<String> dependencies = const [],
    Iterable<String> optionalDependencies = const [],
  }) : dependencies = List.unmodifiable(dependencies),
       optionalDependencies = List.unmodifiable(optionalDependencies),
       assert(id != ''),
       assert(version != '');

  /// Stable Component ID.
  final String id;

  /// Published Component version.
  final String version;

  /// Required Component dependencies.
  final List<String> dependencies;

  /// Optional dependencies present in the generated Host closure.
  final List<String> optionalDependencies;

  /// Encodes this component node as JSON.
  Map<String, Object> toJson() => <String, Object>{
    'id': id,
    'version': version,
    'dependencies': dependencies,
    'optionalDependencies': optionalDependencies,
  };

  /// Decodes a component node from a validated JSON object.
  factory CCDevToolsCatalogComponent.fromJson(Map<String, Object?> json) =>
      CCDevToolsCatalogComponent(
        id: _requiredString(json, 'id'),
        version: _requiredString(json, 'version'),
        dependencies: _stringList(json, 'dependencies'),
        optionalDependencies: _stringList(json, 'optionalDependencies'),
      );
}

/// One static relationship between a Component or capability and another node.
final class CCDevToolsCatalogRelation {
  /// Creates an immutable relation for graph and call-chain views.
  const CCDevToolsCatalogRelation({
    required this.sourceId,
    required this.targetId,
    required this.kind,
  }) : assert(sourceId != ''),
       assert(targetId != ''),
       assert(kind != '');

  /// Stable source Component or capability ID.
  final String sourceId;

  /// Stable target Component or capability ID.
  final String targetId;

  /// Relationship kind such as `dependsOn`, `calls`, or `subscribes`.
  final String kind;

  /// Encodes this relation as JSON.
  Map<String, Object> toJson() => <String, Object>{
    'sourceId': sourceId,
    'targetId': targetId,
    'kind': kind,
  };

  /// Decodes a relation from a validated JSON object.
  factory CCDevToolsCatalogRelation.fromJson(Map<String, Object?> json) =>
      CCDevToolsCatalogRelation(
        sourceId: _requiredString(json, 'sourceId'),
        targetId: _requiredString(json, 'targetId'),
        kind: _requiredString(json, 'kind'),
      );
}

/// Immutable generated Catalog snapshot used by tooling.
final class CCDevToolsStaticCatalogSnapshot {
  /// Creates a bounded static Catalog snapshot.
  CCDevToolsStaticCatalogSnapshot({
    required this.capturedAt,
    this.protocolVersion = ccRouterDevToolsProtocolVersion,
    Iterable<CCDevToolsCatalogRecord> records = const [],
    Iterable<CCDevToolsCatalogComponent> components = const [],
    Iterable<CCDevToolsCatalogRelation> relations = const [],
    this.catalogFingerprint,
  }) : records = List.unmodifiable(records),
       components = List.unmodifiable(components),
       relations = List.unmodifiable(relations);

  /// Capture timestamp in UTC.
  final DateTime capturedAt;

  /// Protocol version used to encode this snapshot.
  final int protocolVersion;

  /// Deterministically ordered generated records.
  final List<CCDevToolsCatalogRecord> records;

  /// Components participating in the static dependency graph.
  final List<CCDevToolsCatalogComponent> components;

  /// Static capability and dependency relationships.
  final List<CCDevToolsCatalogRelation> relations;

  /// Optional generator fingerprint for stale-catalog diagnostics.
  final String? catalogFingerprint;

  /// Encodes this Catalog snapshot as JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'protocolVersion': protocolVersion,
    'capturedAt': capturedAt.toUtc().toIso8601String(),
    if (catalogFingerprint != null) 'catalogFingerprint': catalogFingerprint,
    'records': records.map((record) => record.toJson()).toList(growable: false),
    'components': components
        .map((component) => component.toJson())
        .toList(growable: false),
    'relations': relations
        .map((relation) => relation.toJson())
        .toList(growable: false),
  };

  /// Decodes a Catalog snapshot from JSON.
  factory CCDevToolsStaticCatalogSnapshot.fromJson(Map<String, Object?> json) =>
      CCDevToolsStaticCatalogSnapshot(
        capturedAt: _requiredDateTime(json, 'capturedAt'),
        protocolVersion: _supportedProtocolVersion(json),
        catalogFingerprint: _optionalString(json, 'catalogFingerprint'),
        records: _requiredList(json, 'records')
            .map((value) => CCDevToolsCatalogRecord.fromJson(_object(value)))
            .toList(growable: false),
        components: _optionalList(json, 'components')
            .map((value) => CCDevToolsCatalogComponent.fromJson(_object(value)))
            .toList(growable: false),
        relations: _optionalList(json, 'relations')
            .map((value) => CCDevToolsCatalogRelation.fromJson(_object(value)))
            .toList(growable: false),
      );
}

/// One current Runtime entry retained for read-only tooling.
final class CCDevToolsRuntimeEntry {
  /// Creates a sanitized Runtime entry.
  const CCDevToolsRuntimeEntry({
    required this.kind,
    required this.id,
    required this.state,
    required this.ownerComponentId,
    required this.hostId,
    required this.outlet,
    this.routeId,
    this.traceId,
  }) : assert(kind != ''),
       assert(id != ''),
       assert(state != ''),
       assert(ownerComponentId != ''),
       assert(hostId != ''),
       assert(outlet != '');

  /// Entry category such as `route`, `backend`, or `task`.
  final String kind;

  /// Stable entry identity.
  final String id;

  /// Current lifecycle state.
  final String state;

  /// Owning component, or a stable `foreign`/`unknown` marker.
  final String ownerComponentId;

  /// Navigation Host identity.
  final String hostId;

  /// Navigator Outlet identity.
  final String outlet;

  /// Managed Route ID when this entry represents a route.
  final String? routeId;

  /// Related trace identity, when one exists.
  final String? traceId;

  /// Encodes this entry as JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind,
    'id': id,
    'state': state,
    'ownerComponentId': ownerComponentId,
    'hostId': hostId,
    'outlet': outlet,
    if (routeId != null) 'routeId': routeId,
    if (traceId != null) 'traceId': traceId,
  };

  /// Decodes an entry from JSON.
  factory CCDevToolsRuntimeEntry.fromJson(Map<String, Object?> json) =>
      CCDevToolsRuntimeEntry(
        kind: _requiredString(json, 'kind'),
        id: _requiredString(json, 'id'),
        state: _requiredString(json, 'state'),
        ownerComponentId: _requiredString(json, 'ownerComponentId'),
        hostId: _requiredString(json, 'hostId'),
        outlet: _requiredString(json, 'outlet'),
        routeId: _optionalString(json, 'routeId'),
        traceId: _optionalString(json, 'traceId'),
      );
}

/// One sanitized causal edge in a single framework operation.
final class CCDevToolsTraceEdge {
  /// Creates a trace edge without arbitrary payload data.
  const CCDevToolsTraceEdge({
    required this.traceId,
    required this.spanId,
    required this.sourceId,
    required this.targetId,
    required this.kind,
    required this.status,
    required this.startedAt,
    required this.durationMicros,
    this.parentSpanId,
    this.ownerComponentId,
  }) : assert(traceId != ''),
       assert(spanId != ''),
       assert(sourceId != ''),
       assert(targetId != ''),
       assert(kind != ''),
       assert(status != ''),
       assert(durationMicros >= 0);

  /// Trace identity shared by the operation.
  final String traceId;

  /// Current span identity.
  final String spanId;

  /// Parent span identity, if this edge has one.
  final String? parentSpanId;

  /// Stable source capability or ingress identity.
  final String sourceId;

  /// Stable target capability or lifecycle identity.
  final String targetId;

  /// Framework operation category.
  final String kind;

  /// Terminal or intermediate status.
  final String status;

  /// Start timestamp in UTC.
  final DateTime startedAt;

  /// Elapsed duration in microseconds.
  final int durationMicros;

  /// Target owner, when known.
  final String? ownerComponentId;

  /// Encodes this edge as JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'traceId': traceId,
    'spanId': spanId,
    if (parentSpanId != null) 'parentSpanId': parentSpanId,
    'sourceId': sourceId,
    'targetId': targetId,
    'kind': kind,
    'status': status,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'durationMicros': durationMicros,
    if (ownerComponentId != null) 'ownerComponentId': ownerComponentId,
  };

  /// Decodes a trace edge from JSON.
  factory CCDevToolsTraceEdge.fromJson(Map<String, Object?> json) =>
      CCDevToolsTraceEdge(
        traceId: _requiredString(json, 'traceId'),
        spanId: _requiredString(json, 'spanId'),
        parentSpanId: _optionalString(json, 'parentSpanId'),
        sourceId: _requiredString(json, 'sourceId'),
        targetId: _requiredString(json, 'targetId'),
        kind: _requiredString(json, 'kind'),
        status: _requiredString(json, 'status'),
        startedAt: _requiredDateTime(json, 'startedAt'),
        durationMicros: _requiredNonNegativeInt(json, 'durationMicros'),
        ownerComponentId: _optionalString(json, 'ownerComponentId'),
      );
}

/// Immutable Runtime snapshot linked to a static Catalog by stable IDs.
final class CCDevToolsRuntimeSnapshot {
  /// Creates a bounded Runtime snapshot.
  CCDevToolsRuntimeSnapshot({
    required this.capturedAt,
    required this.runtimeState,
    this.protocolVersion = ccRouterDevToolsProtocolVersion,
    Iterable<String> installedComponentIds = const [],
    Iterable<CCDevToolsRuntimeEntry> entries = const [],
    Iterable<CCDevToolsTraceEdge> traceEdges = const [],
    Iterable<CCDevToolsDiagnosticRecord>? diagnostics,
    this.diagnosticHealth,
  }) : installedComponentIds = List.unmodifiable(installedComponentIds),
       entries = List.unmodifiable(entries),
       traceEdges = List.unmodifiable(traceEdges),
       diagnostics = diagnostics == null
           ? null
           : List.unmodifiable(diagnostics);

  /// Capture timestamp in UTC.
  final DateTime capturedAt;

  /// Protocol version used to encode this snapshot.
  final int protocolVersion;

  /// Runtime state such as `initialized` or `uninitialized`.
  final String runtimeState;

  /// Installed component IDs at capture time.
  final List<String> installedComponentIds;

  /// Current managed and foreign entries.
  final List<CCDevToolsRuntimeEntry> entries;

  /// Bounded causal edges retained for the current diagnostic window.
  final List<CCDevToolsTraceEdge> traceEdges;

  /// Safe failure, fallback, pending and InitTask observations. Null means the
  /// producer predates this optional protocol-v1 extension, not zero failures.
  final List<CCDevToolsDiagnosticRecord>? diagnostics;

  /// Optional capacity/delivery health; absent on older producers.
  final CCDevToolsDiagnosticHealth? diagnosticHealth;

  /// Encodes this Runtime snapshot as JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'protocolVersion': protocolVersion,
    'capturedAt': capturedAt.toUtc().toIso8601String(),
    'runtimeState': runtimeState,
    'installedComponentIds': installedComponentIds,
    'entries': entries.map((entry) => entry.toJson()).toList(growable: false),
    'traceEdges': traceEdges
        .map((edge) => edge.toJson())
        .toList(growable: false),
    if (diagnostics != null)
      'diagnostics': diagnostics!
          .map((record) => record.toJson())
          .toList(growable: false),
    if (diagnosticHealth != null)
      'diagnosticHealth': diagnosticHealth!.toJson(),
  };

  /// Decodes a Runtime snapshot from JSON.
  factory CCDevToolsRuntimeSnapshot.fromJson(Map<String, Object?> json) =>
      CCDevToolsRuntimeSnapshot(
        capturedAt: _requiredDateTime(json, 'capturedAt'),
        protocolVersion: _supportedProtocolVersion(json),
        runtimeState: _requiredString(json, 'runtimeState'),
        installedComponentIds: _requiredList(json, 'installedComponentIds')
            .map((value) => _stringValue(value, 'installedComponentIds'))
            .toList(growable: false),
        entries: _requiredList(json, 'entries')
            .map((value) => CCDevToolsRuntimeEntry.fromJson(_object(value)))
            .toList(growable: false),
        traceEdges: _requiredList(json, 'traceEdges')
            .map((value) => CCDevToolsTraceEdge.fromJson(_object(value)))
            .toList(growable: false),
        diagnostics: json['diagnostics'] == null
            ? null
            : _requiredList(json, 'diagnostics').map(
                (value) => CCDevToolsDiagnosticRecord.fromJson(_object(value)),
              ),
        diagnosticHealth: _optionalObject(
          json,
          'diagnosticHealth',
          CCDevToolsDiagnosticHealth.fromJson,
        ),
      );
}

/// One versioned message combining static and live tooling data.
final class CCDevToolsSnapshotEnvelope {
  /// Creates an immutable snapshot envelope.
  const CCDevToolsSnapshotEnvelope({
    required this.capturedAt,
    required this.runtime,
    this.catalog,
    this.protocolVersion = ccRouterDevToolsProtocolVersion,
  });

  /// Envelope capture timestamp in UTC.
  final DateTime capturedAt;

  /// Protocol version for the complete message.
  final int protocolVersion;

  /// Static generated Catalog, when the Host supplied one.
  final CCDevToolsStaticCatalogSnapshot? catalog;

  /// Live Runtime snapshot.
  final CCDevToolsRuntimeSnapshot runtime;

  /// Encodes the envelope as a JSON string for a tooling transport.
  String encode() => jsonEncode(toJson());

  /// Encodes this envelope as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'protocolVersion': protocolVersion,
    'capturedAt': capturedAt.toUtc().toIso8601String(),
    if (catalog != null) 'catalog': catalog!.toJson(),
    'runtime': runtime.toJson(),
  };

  /// Decodes a JSON string and validates its required fields.
  factory CCDevToolsSnapshotEnvelope.decode(String source) {
    final value = jsonDecode(source);
    return CCDevToolsSnapshotEnvelope.fromJson(_object(value));
  }

  /// Decodes an envelope from a validated JSON object.
  factory CCDevToolsSnapshotEnvelope.fromJson(Map<String, Object?> json) =>
      CCDevToolsSnapshotEnvelope(
        capturedAt: _requiredDateTime(json, 'capturedAt'),
        protocolVersion: _supportedProtocolVersion(json),
        catalog: _optionalObject(
          json,
          'catalog',
          CCDevToolsStaticCatalogSnapshot.fromJson,
        ),
        runtime: CCDevToolsRuntimeSnapshot.fromJson(
          _requiredObject(json, 'runtime'),
        ),
      );
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  return _stringValue(value, key);
}

String _stringValue(Object? value, String key) {
  if (value is String && value.isNotEmpty) return value;
  throw FormatException('Expected a non-empty string for "$key".');
}

String? _optionalString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is String) return value;
  throw FormatException('Expected a string for "$key".');
}

int _requiredPositiveInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is int && value > 0) return value;
  throw FormatException('Expected a positive integer for "$key".');
}

int _supportedProtocolVersion(Map<String, Object?> json) {
  final value = _requiredPositiveInt(json, 'protocolVersion');
  if (value != ccRouterDevToolsProtocolVersion) {
    throw FormatException('Unsupported DevTools protocol version $value.');
  }
  return value;
}

int _requiredNonNegativeInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is int && value >= 0) return value;
  throw FormatException('Expected a non-negative integer for "$key".');
}

DateTime _requiredDateTime(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed.toUtc();
  }
  throw FormatException('Expected an ISO-8601 timestamp for "$key".');
}

List<Object?> _requiredList(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is List<Object?>) return value;
  throw FormatException('Expected a JSON array for "$key".');
}

List<Object?> _optionalList(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return const [];
  if (value is List<Object?>) return value;
  throw FormatException('Expected a JSON array for "$key".');
}

List<String> _stringList(Map<String, Object?> json, String key) =>
    _requiredList(
      json,
      key,
    ).map((value) => _stringValue(value, key)).toList(growable: false);

Map<String, Object?> _requiredObject(Map<String, Object?> json, String key) {
  return _object(json[key], key: key);
}

Map<String, Object?> _object(Object? value, {String key = 'value'}) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    return value.map<String, Object?>((key, value) => MapEntry('$key', value));
  }
  throw FormatException('Expected a JSON object for "$key".');
}

T? _optionalObject<T>(
  Map<String, Object?> json,
  String key,
  T Function(Map<String, Object?>) decode,
) {
  final value = json[key];
  if (value == null) return null;
  return decode(_object(value, key: key));
}
