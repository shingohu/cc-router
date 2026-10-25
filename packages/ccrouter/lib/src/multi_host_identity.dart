part of 'multi_host.dart';

/// Qualifies a child's local identity without keeping a historical ID map.
///
/// Empty and absent IDs remain uncorrelated. Registration namespaces isolate
/// independent children and successive lifetimes of the same logical Host.
String? _entryIdForHost(String namespace, String? id) =>
    id == null || id.isEmpty ? id : '$namespace-entry-$id';

/// Qualifies both sides of a child transition within its registered Host.
/// Rejects stale child sequences before any forwarding side effect. Child gaps
/// reserve missing aggregate sequence positions, preserving Runtime diagnostics
/// alongside aggregate-owned Outlet and detach events.
CCNavigationBackendEvent? _eventForHost(
  String hostId,
  _CCNavigationHostAdapterRecord record,
  CCNavigationBackendEvent event,
) {
  final sequence = event.sequence;
  if (sequence != null) {
    final snapshot = record.snapshotChildSequence;
    if (snapshot != null && sequence <= snapshot) return null;
    final previous = record.lastChildSequence;
    if (previous != null) {
      if (sequence <= previous) return null;
      record.eventSequence += sequence - previous - 1;
    }
    record.lastChildSequence = sequence;
  }
  return CCNavigationBackendEvent(
    kind: event.kind,
    timestamp: event.timestamp,
    backendEntryId: _entryIdForHost(
      record.eventNamespace,
      event.backendEntryId,
    ),
    backendOperationId: event.backendOperationId == null
        ? null
        : '${record.eventNamespace}-child-${event.backendOperationId}',
    previousBackendEntryId: _entryIdForHost(
      record.eventNamespace,
      event.previousBackendEntryId,
    ),
    hostId: hostId,
    navigatorOutlet: event.navigatorOutlet,
    sequence: ++record.eventSequence,
    owner: event.owner,
    navigationId: event.navigationId,
    routeId: event.routeId,
    uri: event.uri,
    placement: CCRoutePlacement(
      hostId: hostId,
      parentRouteId: event.placement.parentRouteId,
      shellId: event.placement.shellId,
      navigatorOutlet: event.placement.navigatorOutlet,
    ),
    location: event.location,
    origin: event.origin,
    source: event.source,
    activeNavigatorOutlets: event.activeNavigatorOutlets,
  );
}

/// Imports a snapshot into the same identity domain used by subsequent events.
CCInitialBackendEntrySnapshot _snapshotForHost(
  String hostId,
  _CCNavigationHostAdapterRecord record,
  CCInitialBackendEntrySnapshot snapshot, {
  required int? sequence,
}) => CCInitialBackendEntrySnapshot(
  backendEntryId: _entryIdForHost(
    record.eventNamespace,
    snapshot.backendEntryId,
  )!,
  owner: snapshot.owner,
  navigatorOutlet: snapshot.navigatorOutlet,
  visibilityState: snapshot.visibilityState,
  routeEntryId: snapshot.routeEntryId,
  routeId: snapshot.routeId,
  hostId: hostId,
  location: snapshot.location,
  sequence: sequence,
);

/// Translates a child's Pop receipt using its dispatch-time registration.
///
/// Focus changes and same-Host replacements cannot relabel a pending receipt.
/// Results remain on the original navigation Future, never in this metadata.
CCPopOutcome _outcomeForHost(
  String hostId,
  String namespace,
  CCPopOutcome outcome,
  String? fallbackOutlet,
) => CCPopOutcome(
  handled: outcome.handled,
  removedBackendEntryId: _entryIdForHost(
    namespace,
    outcome.removedBackendEntryId,
  ),
  removedEntryOwner: outcome.removedEntryOwner,
  trigger: outcome.trigger,
  guardDeniedCode: outcome.guardDeniedCode,
  hostId: hostId,
  navigatorOutlet: outcome.navigatorOutlet ?? fallbackOutlet,
);

/// Qualifies an active/scoped/Guard target before Runtime ledger correlation.
CCNavigationPopTarget _targetForHost(
  String hostId,
  _CCNavigationHostAdapterRecord record,
  CCNavigationPopTarget target,
) => CCNavigationPopTarget(
  hostId: hostId,
  navigatorOutlet: target.navigatorOutlet,
  backendEntryId: _entryIdForHost(record.eventNamespace, target.backendEntryId),
  owner: target.owner,
  handlesPopInternally: target.handlesPopInternally,
);

/// Keeps gesture phases and progress intact while translating a committed Pop.
CCPredictiveBackEvent _predictiveEventForHost(
  String hostId,
  _CCNavigationHostAdapterRecord record,
  CCPredictiveBackEvent event,
) => CCPredictiveBackEvent(
  phase: event.phase,
  timestamp: event.timestamp,
  progress: event.progress,
  outcome: event.outcome == null
      ? null
      : _outcomeForHost(hostId, record.eventNamespace, event.outcome!, null),
);
