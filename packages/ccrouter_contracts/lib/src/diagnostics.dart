import 'dart:async';

/// Functional area associated with one sanitized framework diagnostic.
enum CCDiagnosticCategory {
  /// Navigation requests, resolution, redirects, and failures.
  navigation,

  /// Service resolution, readiness, and generated method calls.
  service,

  /// One-to-one Command dispatch.
  command,

  /// Event publication and individual subscriber execution.
  event,

  /// Component assembly, Runtime startup, initialization task, and Gate
  /// execution.
  initialization,

  /// Route, Session, Scope, or page lifecycle observations.
  lifecycle,

  /// Adapter and backend stack observations.
  backend,

  /// Restoration demand observations.
  restoration,

  /// Runtime timing and capacity observations.
  performance,
}

/// Severity used when an event is exported to an application observability
/// system.
enum CCDiagnosticLevel {
  /// Detailed development information that is normally sampled or disabled.
  debug,

  /// Ordinary successful framework activity.
  info,

  /// A degraded, cancelled, or otherwise noteworthy operation.
  warning,

  /// A failed operation or broken framework invariant.
  error,
}

/// Controls whether one diagnostic category is forwarded to a configured Sink.
///
/// This policy only controls external diagnostic delivery. Runtime behavior and
/// the bounded internal failure history remain active regardless of the policy.
final class CCDiagnosticCategoryPolicy {
  /// Creates one category policy.
  const CCDiagnosticCategoryPolicy({
    required this.category,
    this.enabled = true,
    this.minimumLevel = CCDiagnosticLevel.info,
    this.sampleRate = 1,
  });

  /// Category controlled by this policy.
  final CCDiagnosticCategory category;

  /// Whether matching events are eligible for external delivery.
  final bool enabled;

  /// Lowest severity forwarded for this category.
  final CCDiagnosticLevel minimumLevel;

  /// Fraction of eligible events forwarded, from 0 to 1.
  final double sampleRate;
}

/// Immutable Runtime configuration for the structured diagnostic Sink.
///
/// The default configuration has no external Sink. Install a Host-owned Sink
/// when the application wants to bridge sanitized events to its logger,
/// Crashlytics, Sentry, OpenTelemetry, or a local development console.
final class CCDiagnosticsConfig {
  /// Creates diagnostic delivery configuration.
  const CCDiagnosticsConfig({
    this.sink,
    this.queueCapacity,
    this.policies = const [],
    this.defaultEnabled = true,
    this.defaultMinimumLevel = CCDiagnosticLevel.info,
    this.defaultSampleRate = 1,
  });

  /// Optional application-owned structured diagnostic destination.
  final CCDiagnosticSink? sink;

  /// Maximum waiting events, excluding the single unfinished Sink write.
  ///
  /// Set a positive value to tune delivery independently of retained history.
  /// Null preserves the legacy limit, max(64, navigationDiagnosticCapacity).
  /// Overflow discards the oldest waiting event, regardless of severity.
  /// Use category policies to disable delivery; zero is not a valid capacity.
  final int? queueCapacity;

  /// Category-specific overrides. At most one policy may target a category.
  final Iterable<CCDiagnosticCategoryPolicy> policies;

  /// Whether categories without an explicit policy are enabled.
  final bool defaultEnabled;

  /// Minimum level for categories without an explicit policy.
  final CCDiagnosticLevel defaultMinimumLevel;

  /// Sampling fraction for categories without an explicit policy.
  final double defaultSampleRate;
}

/// A sanitized, immutable framework observation suitable for application logs.
///
/// Payloads, arguments, credentials, full URI values, Widgets, Navigator
/// objects, and raw exception messages are intentionally absent. Optional
/// fields identify the relevant framework object without widening the data
/// boundary. A Sink must treat this value as read-only and must not block the
/// Runtime's business operation.
final class CCDiagnosticEvent {
  /// Creates one structured diagnostic event.
  const CCDiagnosticEvent({
    required this.category,
    required this.level,
    required this.occurredAt,
    required this.operation,
    required this.status,
    required this.duration,
    this.runtimeId,
    this.traceId,
    this.spanId,
    this.parentSpanId,
    this.invocationId,
    this.target,
    this.callerComponentId,
    this.targetComponentId,
    this.scopeId,
    this.navigationId,
    this.routeId,
    this.eventId,
    this.subscriberId,
    this.hostId,
    this.outlet,
    this.failureStage,
    this.errorType,
    this.fallbackKind,
  });

  /// Functional area of this event.
  final CCDiagnosticCategory category;

  /// Severity used by external logging bridges.
  final CCDiagnosticLevel level;

  /// Wall-clock time at which the observation was produced.
  final DateTime occurredAt;

  /// Stable framework operation name.
  final String operation;

  /// Terminal or intermediate operation status.
  final String status;

  /// Measured duration, when the operation has completed.
  final Duration duration;

  /// Runtime identity used to separate multiple Hosts or test Runtimes.
  final String? runtimeId;

  /// Trace identity shared across nested framework calls.
  final String? traceId;

  /// Span identity for this operation.
  final String? spanId;

  /// Parent span identity, when this operation was nested.
  final String? parentSpanId;

  /// Invocation identity, when this event came from an invocation boundary.
  final String? invocationId;

  /// Sanitized framework target identity.
  final String? target;

  /// Calling component identity, when trusted attribution exists.
  final String? callerComponentId;

  /// Owning component identity, when known.
  final String? targetComponentId;

  /// Scope identity associated with the operation.
  final String? scopeId;

  /// Navigation identity, when the event belongs to a navigation request.
  final String? navigationId;

  /// Stable Route identity, when applicable.
  final String? routeId;

  /// Stable Event type identity, when applicable.
  final String? eventId;

  /// Stable Event subscriber identity, when applicable.
  final String? subscriberId;

  /// Host identity, when the backend reports one.
  final String? hostId;

  /// Outlet identity, when the backend reports one.
  final String? outlet;

  /// Sanitized navigation failure stage.
  final String? failureStage;

  /// Error type without the original message or payload.
  final String? errorType;

  /// Capability fallback selected by an adapter, when applicable.
  final String? fallbackKind;
}

/// Receives sanitized framework diagnostics at the Host boundary.
///
/// The Runtime invokes this Sink on a later event-loop turn from a bounded
/// queue, with at most one unfinished [record] Future per Runtime. Surviving
/// events start in FIFO order; a slow Sink causes oldest waiting events to be
/// discarded, never business-operation backpressure. A returned Future must
/// represent the actual write, not acceptance into another unbounded queue.
/// Delivery and completion callbacks use the Zone in which the Runtime was
/// created, preserving Host context without inheriting invocation Zone values.
/// Each batch consumes a finite initial queue-length budget across Future
/// completions too; reentrant diagnostics yield to the event loop between
/// batches rather than extending a microtask chain indefinitely.
///
/// Shutdown attempts a final drain only if the write slot is free, preserving
/// synchronous Sink delivery. It stops at the first unfinished Future, discards
/// the remaining queue, and never waits for or cancels a write. The Host owns
/// Sink cancellation and final flushing.
/// If Runtime construction throws before returning an owner, the same final
/// drain and cleanup run on a later event-loop turn. Synchronous failure logs
/// are preserved; an unfinished Future causes the remaining logs to be dropped.
/// The construction error is rethrown without waiting for diagnostic delivery.
/// A never-completing Future occupies the slot until shutdown; Runtime does
/// not time it out and start more uncancellable work. Keep synchronous work
/// short: asynchronous delivery does not move work to another isolate. Sink
/// failures are isolated and never change navigation, Service, Command, Event,
/// or initialization results. Implementations should forward the immutable
/// event to the application's existing logging or telemetry system quickly.
abstract interface class CCDiagnosticSink {
  /// Records one sanitized event.
  FutureOr<void> record(CCDiagnosticEvent event);
}

/// Payload-free snapshot of one Runtime's external diagnostic delivery.
///
/// Use counters to tune sampling, queue capacity and the application Sink.
/// This is observational state, not an audit log or delivery acknowledgement.
final class CCDiagnosticDeliverySnapshot {
  /// Captures queue state and cumulative counts at one point in time.
  const CCDiagnosticDeliverySnapshot({
    required this.queueCapacity,
    required this.queuedEventCount,
    required this.inFlightWriteCount,
    required this.peakQueueDepth,
    required this.deliveredEventCount,
    required this.failedEventCount,
    required this.droppedEventCount,
    required this.isClosed,
  });

  /// Maximum waiting events; the one in-flight write is additional.
  final int queueCapacity;

  /// Events currently waiting for the Sink.
  final int queuedEventCount;

  /// Unfinished writes, either zero or one, including after shutdown.
  final int inFlightWriteCount;

  /// Largest observed number of waiting events, bounded by [queueCapacity].
  final int peakQueueDepth;

  /// Writes whose returned Future, or synchronous call, completed successfully.
  final int deliveredEventCount;

  /// Synchronous throws and asynchronous write failures, isolated from business.
  final int failedEventCount;

  /// Waiting events discarded by overflow or Runtime shutdown.
  final int droppedEventCount;

  /// Whether shutdown has stopped acceptance and released the waiting queue.
  final bool isClosed;
}
