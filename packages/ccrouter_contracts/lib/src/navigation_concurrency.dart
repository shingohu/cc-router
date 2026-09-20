/// Controls how Runtime treats identical navigation requests that overlap.
///
/// Use [allow] when repeated pushes are meaningful, [rejectDuplicate] when a
/// user action must not start a second identical operation, and [singleFlight]
/// when callers should share one in-flight result. The policy is not a time
/// based debounce and never suppresses a completed navigation. Navigations
/// carrying process-local Extra values always execute independently because
/// Runtime cannot safely compare or hash arbitrary business objects.
enum CCNavigationConcurrencyPolicy {
  /// Executes every navigation request independently.
  allow,

  /// Fails a request while an identical request is still in flight.
  rejectDuplicate,

  /// Returns the first request's Future while an identical request is in
  /// flight.
  singleFlight,
}
