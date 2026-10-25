part of 'protocol.dart';

/// Payload-free state shared by Failure, Fallback, Pending and InitTask views.
///
/// Only explicit fields cross the process boundary. No arbitrary metadata,
/// exception text, address, parameter, result or control operation is accepted.
/// Optional values are unknown/not applicable, never inferred from another Host.
final class CCDevToolsDiagnosticRecord {
  /// Creates a safe state record; dependencies are copied into an immutable list.
  CCDevToolsDiagnosticRecord({
    required this.kind,
    required this.id,
    required this.status,
    this.timestamp,
    this.routeId,
    this.initialRouteId,
    this.hostId,
    this.outlet,
    this.operation,
    this.stage,
    this.reason,
    this.attempt,
    this.errorType,
    this.recoveryDepth,
    this.recoverySelected,
    this.capability,
    this.behavior,
    this.origin,
    this.expiresAt,
    this.ownerComponentId,
    this.gateId,
    this.failurePolicy,
    this.blockedByTaskId,
    this.durationMicros,
    Iterable<String> dependsOn = const [],
  }) : dependsOn = List.unmodifiable(dependsOn);

  /// Record domain: failure, fallback, pending or initTask.
  final String kind;

  /// Navigation or InitTask identity within the producing Runtime.
  final String id;

  /// Terminal outcome, pending state, or current task state.
  final String status;

  /// Failure/fallback occurrence or pending creation time; absent for task state.
  final DateTime? timestamp;

  /// Stable affected Route ID, when resolution reached one.
  final String? routeId;

  /// Original Route before redirect/recovery, when known.
  final String? initialRouteId;

  /// Concrete attempted Host, or invocation Host before target resolution.
  final String? hostId;

  /// Resolved target Outlet, absent if unresolved.
  final String? outlet;

  /// Navigation stack operation.
  final String? operation;

  /// Stable framework failure stage.
  final String? stage;

  /// Stable framework failure reason, excluding arbitrary cancellation codes.
  final String? reason;

  /// Request, redirect, recovery or pending-resume attempt.
  final String? attempt;

  /// Concrete failure type, without exception text.
  final String? errorType;

  /// Number of earlier recovery decisions in this navigation chain.
  final int? recoveryDepth;

  /// Whether recovery was selected; this is not proof that it later succeeded.
  final bool? recoverySelected;

  /// Missing backend capability for a fallback record.
  final String? capability;

  /// Selected safe fallback behavior.
  final String? behavior;

  /// Trusted ingress classification for a pending request.
  final String? origin;

  /// Pending continuation deadline; null indicates no configured expiry.
  final DateTime? expiresAt;

  /// Registered task Owner component.
  final String? ownerComponentId;

  /// Registered task Gate identity.
  final String? gateId;

  /// Required/optional task failure behavior.
  final String? failurePolicy;

  /// Dependency preventing task execution, when known.
  final String? blockedByTaskId;

  /// Task execution duration after completion, when available.
  final int? durationMicros;

  /// Registered task dependency IDs, never mutable runtime task objects.
  final List<String> dependsOn;

  /// Encodes only the fixed safe fields understood by this protocol extension.
  Map<String, Object?> toJson() => {
    'kind': kind,
    'id': id,
    'status': status,
    if (timestamp != null) 'timestamp': timestamp!.toUtc().toIso8601String(),
    if (routeId != null) 'routeId': routeId,
    if (initialRouteId != null) 'initialRouteId': initialRouteId,
    if (hostId != null) 'hostId': hostId,
    if (outlet != null) 'outlet': outlet,
    if (operation != null) 'operation': operation,
    if (stage != null) 'stage': stage,
    if (reason != null) 'reason': reason,
    if (attempt != null) 'attempt': attempt,
    if (errorType != null) 'errorType': errorType,
    if (recoveryDepth != null) 'recoveryDepth': recoveryDepth,
    if (recoverySelected != null) 'recoverySelected': recoverySelected,
    if (capability != null) 'capability': capability,
    if (behavior != null) 'behavior': behavior,
    if (origin != null) 'origin': origin,
    if (expiresAt != null) 'expiresAt': expiresAt!.toUtc().toIso8601String(),
    if (ownerComponentId != null) 'ownerComponentId': ownerComponentId,
    if (gateId != null) 'gateId': gateId,
    if (failurePolicy != null) 'failurePolicy': failurePolicy,
    if (blockedByTaskId != null) 'blockedByTaskId': blockedByTaskId,
    if (durationMicros != null) 'durationMicros': durationMicros,
    'dependsOn': dependsOn,
  };

  /// Decodes a record, rejecting malformed known fields and ignoring unknowns.
  factory CCDevToolsDiagnosticRecord.fromJson(Map<String, Object?> json) =>
      CCDevToolsDiagnosticRecord(
        kind: _requiredString(json, 'kind'),
        id: _requiredString(json, 'id'),
        status: _requiredString(json, 'status'),
        timestamp: json['timestamp'] == null
            ? null
            : _requiredDateTime(json, 'timestamp'),
        routeId: _optionalString(json, 'routeId'),
        initialRouteId: _optionalString(json, 'initialRouteId'),
        hostId: _optionalString(json, 'hostId'),
        outlet: _optionalString(json, 'outlet'),
        operation: _optionalString(json, 'operation'),
        stage: _optionalString(json, 'stage'),
        reason: _optionalString(json, 'reason'),
        attempt: _optionalString(json, 'attempt'),
        errorType: _optionalString(json, 'errorType'),
        recoveryDepth: json['recoveryDepth'] == null
            ? null
            : _requiredNonNegativeInt(json, 'recoveryDepth'),
        recoverySelected: _optionalBool(json, 'recoverySelected'),
        capability: _optionalString(json, 'capability'),
        behavior: _optionalString(json, 'behavior'),
        origin: _optionalString(json, 'origin'),
        expiresAt: json['expiresAt'] == null
            ? null
            : _requiredDateTime(json, 'expiresAt'),
        ownerComponentId: _optionalString(json, 'ownerComponentId'),
        gateId: _optionalString(json, 'gateId'),
        failurePolicy: _optionalString(json, 'failurePolicy'),
        blockedByTaskId: _optionalString(json, 'blockedByTaskId'),
        durationMicros: json['durationMicros'] == null
            ? null
            : _requiredNonNegativeInt(json, 'durationMicros'),
        dependsOn: _optionalList(
          json,
          'dependsOn',
        ).map((value) => _stringValue(value, 'dependsOn')),
      );
}

/// Capacity completeness for one event history, excluding live backend state.
final class CCDevToolsHistoryStatus {
  /// Creates one immutable count row.
  const CCDevToolsHistoryStatus({
    required this.name,
    required this.capacity,
    required this.retainedCount,
    required this.omittedCount,
  });

  /// Framework-defined history name.
  final String name;

  /// Per-history limit; zero means retention disabled.
  final int capacity;

  /// Number of currently retained observations.
  final int retainedCount;

  /// Observations omitted through zero capacity or rotation since construction.
  final int omittedCount;

  /// Encodes a payload-free completeness row.
  Map<String, Object> toJson() => {
    'name': name,
    'capacity': capacity,
    'retainedCount': retainedCount,
    'omittedCount': omittedCount,
  };

  /// Decodes and validates history counts.
  factory CCDevToolsHistoryStatus.fromJson(Map<String, Object?> json) =>
      CCDevToolsHistoryStatus(
        name: _requiredString(json, 'name'),
        capacity: _requiredNonNegativeInt(json, 'capacity'),
        retainedCount: _requiredNonNegativeInt(json, 'retainedCount'),
        omittedCount: _requiredNonNegativeInt(json, 'omittedCount'),
      );
}

/// Read-only Runtime ownership and observer counts for tooling.
///
/// This optional protocol value is a point-in-time health view. It does not
/// expose mutation handles or imply that retained render resources are leaks.
final class CCDevToolsRuntimeHealth {
  /// Captures current navigation ownership and observer counts.
  const CCDevToolsRuntimeHealth({
    required this.activeRouteEntries,
    required this.exitingRouteEntries,
    required this.pendingNavigations,
    required this.inFlightNavigations,
    required this.trackedNavigationHosts,
    required this.activeBackendEntries,
    required this.backendEntries,
    required this.desynchronizedBackendHosts,
    required this.observerQueueDepth,
    required this.observerQueueCapacity,
    required this.navigationEvents,
    required this.routeEntryTransitions,
    required this.backendEvents,
    required this.unattributedBackendEvents,
  });

  /// Current logical Managed Route Entries.
  final int activeRouteEntries;

  /// Removed Entries whose render transition still retains resources.
  final int exitingRouteEntries;

  /// Navigation requests waiting for external policy.
  final int pendingNavigations;

  /// In-flight singleFlight/rejectDuplicate gates; allow can report zero
  /// despite unfinished navigation. This is not a count of every request.
  final int inFlightNavigations;

  /// Host lifetimes lazily captured by Runtime navigation, Pop, or scoped clients.
  /// This is not the Adapter's complete Host registration count.
  final int trackedNavigationHosts;

  /// Active backend Entries in the adapter ledger.
  final int activeBackendEntries;

  /// All backend Entries retained by the ledger.
  final int backendEntries;

  /// Backend Hosts with a sequence gap or an uncorrelated Managed Pop.
  final int desynchronizedBackendHosts;

  /// Waiting observer batches, excluding batches already delivering.
  final int observerQueueDepth;

  /// Maximum waiting depth; terminal overflow applies synchronous backpressure.
  final int observerQueueCapacity;

  /// Lifetime navigation lifecycle phases.
  final int navigationEvents;

  /// Lifetime Managed Route Entry transitions.
  final int routeEntryTransitions;

  /// Lifetime backend observations accepted by Runtime.
  final int backendEvents;

  /// Backend observations without a correlated Runtime navigation identity.
  /// This includes Foreign Routes and opaque transitions; it is not a direct
  /// `Navigator.pop` counter.
  final int unattributedBackendEvents;

  /// Encodes this point-in-time health view.
  Map<String, Object> toJson() => {
    'activeRouteEntries': activeRouteEntries,
    'exitingRouteEntries': exitingRouteEntries,
    'pendingNavigations': pendingNavigations,
    'inFlightNavigations': inFlightNavigations,
    'trackedNavigationHosts': trackedNavigationHosts,
    'activeBackendEntries': activeBackendEntries,
    'backendEntries': backendEntries,
    'desynchronizedBackendHosts': desynchronizedBackendHosts,
    'observerQueueDepth': observerQueueDepth,
    'observerQueueCapacity': observerQueueCapacity,
    'navigationEvents': navigationEvents,
    'routeEntryTransitions': routeEntryTransitions,
    'backendEvents': backendEvents,
    'unattributedBackendEvents': unattributedBackendEvents,
  };

  /// Decodes a Runtime health view, accepting the former `registeredHosts` key
  /// as the same lazily tracked lifetime count when the corrected key is absent.
  factory CCDevToolsRuntimeHealth.fromJson(
    Map<String, Object?> json,
  ) => CCDevToolsRuntimeHealth(
    activeRouteEntries: _requiredNonNegativeInt(json, 'activeRouteEntries'),
    exitingRouteEntries: _requiredNonNegativeInt(json, 'exitingRouteEntries'),
    pendingNavigations: _requiredNonNegativeInt(json, 'pendingNavigations'),
    inFlightNavigations: _requiredNonNegativeInt(json, 'inFlightNavigations'),
    trackedNavigationHosts: _requiredNonNegativeInt(
      json,
      json.containsKey('trackedNavigationHosts')
          ? 'trackedNavigationHosts'
          : 'registeredHosts',
    ),
    activeBackendEntries: _requiredNonNegativeInt(json, 'activeBackendEntries'),
    backendEntries: _requiredNonNegativeInt(json, 'backendEntries'),
    desynchronizedBackendHosts: _requiredNonNegativeInt(
      json,
      'desynchronizedBackendHosts',
    ),
    observerQueueDepth: _requiredNonNegativeInt(json, 'observerQueueDepth'),
    observerQueueCapacity: _requiredPositiveInt(json, 'observerQueueCapacity'),
    navigationEvents: _requiredNonNegativeInt(json, 'navigationEvents'),
    routeEntryTransitions: _requiredNonNegativeInt(
      json,
      'routeEntryTransitions',
    ),
    backendEvents: _requiredNonNegativeInt(json, 'backendEvents'),
    unattributedBackendEvents: _requiredNonNegativeInt(
      json,
      'unattributedBackendEvents',
    ),
  );
}

/// Runtime-local delivery health; counts never promise durable external upload.
final class CCDevToolsDiagnosticHealth {
  /// Captures fixed counters and immutable history completeness rows.
  CCDevToolsDiagnosticHealth({
    required this.runtimeId,
    required this.revision,
    required this.sinkConfigured,
    required this.queueCapacity,
    required this.queued,
    required this.inFlight,
    required this.peakQueued,
    required this.delivered,
    required this.failed,
    required this.dropped,
    required this.closed,
    required Iterable<CCDevToolsHistoryStatus> histories,
    this.runtimeHealth,
  }) : histories = List.unmodifiable(histories);

  /// Runtime generation, so equal revisions across restarts are distinct.
  final String runtimeId;

  /// Monotonic observation revision; delivery counts advance independently.
  final int revision;

  /// Whether an external Sink was installed, regardless of category filtering.
  final bool sinkConfigured;

  /// Maximum waiting external events, excluding the one unfinished write.
  final int queueCapacity;

  /// Events waiting for external delivery.
  final int queued;

  /// Unfinished writes, either zero or one.
  final int inFlight;

  /// Highest observed waiting queue depth.
  final int peakQueued;

  /// Successfully completed Sink writes, not durable-upload acknowledgements.
  final int delivered;

  /// Isolated Sink write failures.
  final int failed;

  /// Waiting events discarded on overflow or close.
  final int dropped;

  /// Whether the Runtime stopped external delivery.
  final bool closed;

  /// Fixed event history completeness, independent of Sink filtering/sampling.
  final List<CCDevToolsHistoryStatus> histories;

  /// Optional live Runtime health from newer producers.
  final CCDevToolsRuntimeHealth? runtimeHealth;

  /// Encodes safe delivery and completeness counters.
  Map<String, Object> toJson() => {
    'runtimeId': runtimeId,
    'revision': revision,
    'sinkConfigured': sinkConfigured,
    'queueCapacity': queueCapacity,
    'queued': queued,
    'inFlight': inFlight,
    'peakQueued': peakQueued,
    'delivered': delivered,
    'failed': failed,
    'dropped': dropped,
    'closed': closed,
    'histories': histories
        .map((history) => history.toJson())
        .toList(growable: false),
    if (runtimeHealth != null) 'runtimeHealth': runtimeHealth!.toJson(),
  };

  /// Decodes health; malformed optional extension data fails explicitly.
  factory CCDevToolsDiagnosticHealth.fromJson(Map<String, Object?> json) =>
      CCDevToolsDiagnosticHealth(
        runtimeId: _requiredString(json, 'runtimeId'),
        revision: _requiredNonNegativeInt(json, 'revision'),
        sinkConfigured: _requiredBool(json, 'sinkConfigured'),
        queueCapacity: _requiredPositiveInt(json, 'queueCapacity'),
        queued: _requiredNonNegativeInt(json, 'queued'),
        inFlight: _requiredNonNegativeInt(json, 'inFlight'),
        peakQueued: _requiredNonNegativeInt(json, 'peakQueued'),
        delivered: _requiredNonNegativeInt(json, 'delivered'),
        failed: _requiredNonNegativeInt(json, 'failed'),
        dropped: _requiredNonNegativeInt(json, 'dropped'),
        closed: _requiredBool(json, 'closed'),
        histories: _requiredList(
          json,
          'histories',
        ).map((value) => CCDevToolsHistoryStatus.fromJson(_object(value))),
        runtimeHealth: _optionalObject(
          json,
          'runtimeHealth',
          CCDevToolsRuntimeHealth.fromJson,
        ),
      );
}

/// Reads an optional bool without coercing malformed transport values.
bool? _optionalBool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null || value is bool) return value as bool?;
  throw FormatException('Expected a boolean for "$key".');
}

/// Requires a bool for known fields in a present extension object.
bool _requiredBool(Map<String, Object?> json, String key) =>
    _optionalBool(json, key) ??
    (throw FormatException('Expected a boolean for "$key".'));
