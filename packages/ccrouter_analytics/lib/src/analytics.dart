import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

/// Bounded payload and state limits enforced by the provider-neutral layer.
///
/// These limits protect navigation and widget callbacks from accidentally
/// retaining or queueing an unbounded analytics payload. Applications that
/// need larger business data should aggregate or persist it in their own
/// analytics adapter instead of widening this framework boundary.
final class CCAnalyticsLimits {
  /// Maximum number of properties attached to one event.
  static const int maxPropertyCount = 64;

  /// Maximum number of UTF-16 code units in one String value.
  static const int maxStringLength = 256;

  /// Maximum number of items in one primitive list value.
  static const int maxListLength = 32;

  /// Maximum conservative size of all property values in one event.
  static const int maxPropertyValueUnits = 4096;

  /// Maximum number of event IDs retained by the common throttle state.
  static const int maxThrottleEntries = 1024;

  /// Maximum number of blacklisted IDs in one policy.
  static const int maxBlockedEventIds = 256;

  const CCAnalyticsLimits._();
}

/// Product analytics event categories supported by the provider-neutral layer.
///
/// Framework-generated events use [pageView] and [pageLeave]. Applications
/// should use [click], [scroll], [exposure], or [custom] only when they can
/// provide a stable business meaning for the event.
enum CCAnalyticsEventType {
  /// A managed CCRouter destination became current in its Outlet.
  pageView,

  /// A managed CCRouter destination stopped being current in its Outlet.
  pageLeave,

  /// A stable, explicitly declared interactive target was activated.
  click,

  /// A scroll interaction reached a sampled aggregate boundary.
  scroll,

  /// A stable target crossed an application-defined visibility threshold.
  exposure,

  /// An application-defined business event with an explicit schema.
  custom,

  /// A product-relevant error that is safe to export after sanitization.
  error,
}

/// One primitive property attached to a product analytics event.
///
/// The value must be a String, num, bool, or a list containing only String or
/// num values. Maps, Widgets, exceptions, credentials, and arbitrary business
/// objects are rejected so an analytics adapter cannot accidentally serialize
/// a sensitive object graph.
final class CCAnalyticsProperty {
  /// Creates a validated property with a stable [name] and primitive [value].
  CCAnalyticsProperty(this.name, Object value)
    : value = _snapshotAnalyticsPropertyValue(value) {
    _validateAnalyticsPropertyName(name);
  }

  /// Stable property name understood by the application analytics schema.
  final String name;

  /// Provider-neutral primitive value, copied into an immutable list if needed.
  ///
  /// Mutating the caller's original list cannot change this property or any
  /// queued event; sinks receive the same immutable snapshot.
  final Object value;
}

/// Immutable, validated properties attached to one analytics event.
///
/// Use [from] instead of passing a raw map through the framework boundary.
/// Duplicate names are rejected to keep provider mappings deterministic.
final class CCAnalyticsProperties {
  /// Creates an empty immutable property set.
  const CCAnalyticsProperties.empty() : _values = const {};

  /// Builds an immutable property set from validated [entries].
  factory CCAnalyticsProperties.from(Iterable<CCAnalyticsProperty> entries) {
    final values = <String, Object>{};
    var valueUnits = 0;
    for (final entry in entries) {
      if (values.length >= CCAnalyticsLimits.maxPropertyCount) {
        throw ArgumentError.value(
          entries,
          'entries',
          'Analytics events may contain at most '
              '${CCAnalyticsLimits.maxPropertyCount} properties.',
        );
      }
      if (values.containsKey(entry.name)) {
        throw ArgumentError.value(
          entry.name,
          'entries',
          'Analytics property names must be unique.',
        );
      }
      values[entry.name] = entry.value;
      valueUnits += _analyticsValueUnits(entry.value);
      if (valueUnits > CCAnalyticsLimits.maxPropertyValueUnits) {
        throw ArgumentError.value(
          entries,
          'entries',
          'Analytics property values exceed the bounded event limit.',
        );
      }
    }
    return CCAnalyticsProperties._(Map.unmodifiable(values));
  }

  /// Creates an immutable property set from a prevalidated map.
  const CCAnalyticsProperties._(this._values);

  /// Immutable provider-neutral property values.
  Map<String, Object> get values => _values;

  /// Internal immutable storage shared by the public read-only view.
  final Map<String, Object> _values;
}

/// One sanitized product analytics event.
///
/// The event separates product analytics from `CCDiagnosticEvent`. It may be
/// exported to Firebase, ThinkingData, OpenTelemetry, or an application-owned
/// sink, but it never retains Widgets, Route objects, typed arguments, full
/// URI values, tokens, or arbitrary exception messages.
final class CCAnalyticsEvent {
  /// Creates one immutable analytics event.
  CCAnalyticsEvent({
    required this.eventId,
    required this.type,
    required this.occurredAt,
    this.navigationId,
    this.traceId,
    this.routeId,
    this.componentId,
    this.hostId,
    this.outlet,
    this.source,
    this.anonymousVisitorId,
    this.applicationSessionId,
    this.properties = const CCAnalyticsProperties.empty(),
  }) {
    _validateAnalyticsEventId(eventId);
    _validateOptionalIdentifier(navigationId, 'navigationId');
    _validateOptionalIdentifier(traceId, 'traceId');
    _validateOptionalIdentifier(routeId, 'routeId');
    _validateOptionalIdentifier(componentId, 'componentId');
    _validateOptionalIdentifier(hostId, 'hostId');
    _validateOptionalIdentifier(outlet, 'outlet');
    _validateOptionalIdentifier(source, 'source');
    _validateOptionalIdentifier(anonymousVisitorId, 'anonymousVisitorId');
    _validateOptionalIdentifier(applicationSessionId, 'applicationSessionId');
  }

  /// Stable analytics event identity.
  final String eventId;

  /// Product event category.
  final CCAnalyticsEventType type;

  /// Wall-clock occurrence time supplied by the producing boundary.
  final DateTime occurredAt;

  /// CCRouter navigation identity, when the event belongs to a navigation.
  final String? navigationId;

  /// Trace identity shared with the surrounding framework operation.
  final String? traceId;

  /// Stable route contract identity, without route parameters.
  final String? routeId;

  /// Owning component identity, when known.
  final String? componentId;

  /// Navigation Host identity, when known.
  final String? hostId;

  /// Navigator Outlet identity, when known.
  final String? outlet;

  /// Stable product source attribution, when supplied.
  final String? source;

  /// Pseudonymous analytics visitor identity, never an account or device ID.
  final String? anonymousVisitorId;

  /// Pseudonymous application analytics session identity.
  final String? applicationSessionId;

  /// Validated primitive properties.
  final CCAnalyticsProperties properties;
}

/// Stable context inherited by explicit business analytics events.
///
/// Keep this context at a feature or page boundary. It contains only stable
/// identifiers and can be reused for several click, scroll, or custom events;
/// it does not retain a BuildContext, Widget, Route, or business object.
final class CCAnalyticsContext {
  /// Creates an immutable analytics context.
  const CCAnalyticsContext({
    this.navigationId,
    this.traceId,
    this.routeId,
    this.componentId,
    this.hostId,
    this.outlet,
    this.source,
    this.anonymousVisitorId,
    this.applicationSessionId,
  });

  /// CCRouter navigation identity, when the event belongs to a navigation.
  final String? navigationId;

  /// Trace identity shared with the surrounding framework operation.
  final String? traceId;

  /// Stable route contract identity, without route parameters.
  final String? routeId;

  /// Owning component identity, when known.
  final String? componentId;

  /// Navigation Host identity, when known.
  final String? hostId;

  /// Navigator Outlet identity, when known.
  final String? outlet;

  /// Stable product source attribution, when supplied.
  final String? source;

  /// Pseudonymous analytics visitor identity.
  final String? anonymousVisitorId;

  /// Pseudonymous application analytics session identity.
  final String? applicationSessionId;

  /// Merges non-null fields from [override] over this context.
  ///
  /// An empty override preserves the current context. This is intended for
  /// nested Flutter analytics scopes and does not retain either scope's
  /// BuildContext or Widget.
  CCAnalyticsContext merge(CCAnalyticsContext override) => CCAnalyticsContext(
    navigationId: override.navigationId ?? navigationId,
    traceId: override.traceId ?? traceId,
    routeId: override.routeId ?? routeId,
    componentId: override.componentId ?? componentId,
    hostId: override.hostId ?? hostId,
    outlet: override.outlet ?? outlet,
    source: override.source ?? source,
    anonymousVisitorId: override.anonymousVisitorId ?? anonymousVisitorId,
    applicationSessionId: override.applicationSessionId ?? applicationSessionId,
  );
}

/// Explicit event recorder for business callbacks and interaction boundaries.
///
/// Use this API when a click, scroll aggregate, exposure, or custom event has a
/// stable business meaning. It does not install a GestureDetector, inspect
/// Widget text, or intercept existing Flutter gestures.
final class CCAnalyticsTracker {
  /// Creates a tracker using an application-owned [dispatcher].
  const CCAnalyticsTracker({
    required this.dispatcher,
    this.context = const CCAnalyticsContext(),
    this.enabled = true,
  });

  /// Bounded dispatcher receiving accepted events.
  final CCAnalyticsEventDispatcher dispatcher;

  /// Stable page or feature context applied to each event.
  final CCAnalyticsContext context;

  /// Whether this tracker is enabled by its owning Scope.
  ///
  /// A disabled tracker returns false without constructing or queueing an
  /// event. This local switch does not change the Dispatcher's global policy.
  final bool enabled;

  /// Records an event of [type] and returns whether it entered the queue.
  bool track({
    required String eventId,
    required CCAnalyticsEventType type,
    CCAnalyticsProperties properties = const CCAnalyticsProperties.empty(),
  }) {
    if (!enabled) return false;
    return dispatcher.dispatch(
      CCAnalyticsEvent(
        eventId: eventId,
        type: type,
        occurredAt: DateTime.now(),
        navigationId: context.navigationId,
        traceId: context.traceId,
        routeId: context.routeId,
        componentId: context.componentId,
        hostId: context.hostId,
        outlet: context.outlet,
        source: context.source,
        anonymousVisitorId: context.anonymousVisitorId,
        applicationSessionId: context.applicationSessionId,
        properties: properties,
      ),
    );
  }

  /// Records one explicit click or activation event.
  bool click({
    required String eventId,
    CCAnalyticsProperties properties = const CCAnalyticsProperties.empty(),
  }) => track(
    eventId: eventId,
    type: CCAnalyticsEventType.click,
    properties: properties,
  );

  /// Records one already aggregated scroll interaction.
  bool scroll({
    required String eventId,
    CCAnalyticsProperties properties = const CCAnalyticsProperties.empty(),
  }) => track(
    eventId: eventId,
    type: CCAnalyticsEventType.scroll,
    properties: properties,
  );

  /// Records one explicit visibility or exposure event.
  bool exposure({
    required String eventId,
    CCAnalyticsProperties properties = const CCAnalyticsProperties.empty(),
  }) => track(
    eventId: eventId,
    type: CCAnalyticsEventType.exposure,
    properties: properties,
  );

  /// Records one application-defined business event.
  bool custom({
    required String eventId,
    CCAnalyticsProperties properties = const CCAnalyticsProperties.empty(),
  }) => track(
    eventId: eventId,
    type: CCAnalyticsEventType.custom,
    properties: properties,
  );
}

/// Binds one stable event ID to an existing business callback.
///
/// This target is deliberately callback-based rather than a Flutter Widget.
/// Use `onPressed: () => target.run(submit)` or [runAsync] so the application keeps
/// control of gesture semantics and widget composition.
final class CCAnalyticsTarget {
  /// Creates an explicit target backed by [tracker].
  const CCAnalyticsTarget({required this.tracker, required this.eventId});

  /// Tracker receiving the click event.
  final CCAnalyticsTracker tracker;

  /// Stable business event ID emitted before the callback runs.
  final String eventId;

  /// Records the click and then invokes synchronous [action].
  T run<T>(T Function() action) {
    tracker.click(eventId: eventId);
    return action();
  }

  /// Records the click and then invokes asynchronous [action].
  Future<T> runAsync<T>(Future<T> Function() action) async {
    tracker.click(eventId: eventId);
    return action();
  }
}

/// Controls whether product analytics may enter the delivery queue.
///
/// Applications should construct this with `consentGranted: false` until the
/// applicable privacy decision is available. The default is enabled but not
/// granted, so an application must explicitly opt in after its privacy flow.
final class CCAnalyticsPolicy {
  /// Creates a validated immutable analytics delivery policy.
  CCAnalyticsPolicy({
    this.enabled = true,
    this.consentGranted = false,
    this.sampleRate = 1,
    Iterable<String> blockedEventIds = const [],
    this.throttleWindow,
  }) : blockedEventIds = Set.unmodifiable(blockedEventIds) {
    if (!sampleRate.isFinite || sampleRate < 0 || sampleRate > 1) {
      throw ArgumentError.value(
        sampleRate,
        'sampleRate',
        'Must be between 0 and 1.',
      );
    }
    if (this.blockedEventIds.length > CCAnalyticsLimits.maxBlockedEventIds) {
      throw ArgumentError.value(
        this.blockedEventIds,
        'blockedEventIds',
        'A policy may contain at most '
            '${CCAnalyticsLimits.maxBlockedEventIds} blocked IDs.',
      );
    }
    for (final eventId in this.blockedEventIds) {
      _validateAnalyticsEventId(eventId);
    }
    final window = throttleWindow;
    if (window != null && window <= Duration.zero) {
      throw ArgumentError.value(
        throttleWindow,
        'throttleWindow',
        'Must be positive when provided.',
      );
    }
  }

  /// Whether analytics delivery is enabled for this application state.
  final bool enabled;

  /// Whether the required application privacy consent has been granted.
  final bool consentGranted;

  /// Fraction of eligible events to accept, from 0 to 1.
  final double sampleRate;

  /// Stable Event IDs that must never enter the analytics queue.
  ///
  /// Use this for privacy or product-level exclusions. The rule is applied
  /// before sampling and queue accounting, so blocked events cannot consume
  /// memory or reach any provider Adapter.
  final Set<String> blockedEventIds;

  /// Optional minimum interval between accepted events with the same ID.
  ///
  /// This is a provider-neutral safety valve for high-frequency click,
  /// scroll, or exposure sources. A null value disables common throttling.
  final Duration? throttleWindow;

  /// Creates a policy with selected fields replaced.
  CCAnalyticsPolicy copyWith({
    bool? enabled,
    bool? consentGranted,
    double? sampleRate,
    Iterable<String>? blockedEventIds,
    Duration? throttleWindow,
    bool clearThrottleWindow = false,
  }) {
    final nextSampleRate = sampleRate ?? this.sampleRate;
    if (!nextSampleRate.isFinite || nextSampleRate < 0 || nextSampleRate > 1) {
      throw ArgumentError.value(
        nextSampleRate,
        'sampleRate',
        'Must be between 0 and 1.',
      );
    }
    return CCAnalyticsPolicy(
      enabled: enabled ?? this.enabled,
      consentGranted: consentGranted ?? this.consentGranted,
      sampleRate: nextSampleRate,
      blockedEventIds: blockedEventIds ?? this.blockedEventIds,
      throttleWindow: clearThrottleWindow
          ? null
          : (throttleWindow ?? this.throttleWindow),
    );
  }
}

/// Receives immutable analytics events at the application boundary.
///
/// Implementations should enqueue or batch quickly. A sink must not change
/// navigation or business results when it fails; callers isolate sink errors.
abstract interface class CCAnalyticsSink {
  /// Accepts one event for export or local processing.
  FutureOr<void> write(CCAnalyticsEvent event);
}

/// Reports an isolated analytics sink failure.
typedef CCAnalyticsSinkErrorHandler =
    void Function(Object error, StackTrace stackTrace, CCAnalyticsEvent event);

/// Payload-free health counters for one configured Sink position.
///
/// [sinkIndex] follows the immutable order supplied to the Dispatcher. The
/// snapshot deliberately omits the Sink object, event IDs, and error text so
/// it can be forwarded to diagnostics without retaining application data.
final class CCAnalyticsSinkHealth {
  /// Creates one immutable Sink health snapshot.
  const CCAnalyticsSinkHealth({
    required this.sinkIndex,
    required this.successfulWriteCount,
    required this.failedWriteCount,
    required this.timedOutWriteCount,
    required this.totalWriteDuration,
    required this.quarantined,
  });

  /// Position of the Sink in the Dispatcher configuration.
  final int sinkIndex;

  /// Number of writes that completed successfully.
  final int successfulWriteCount;

  /// Number of writes that failed, including timed out writes.
  final int failedWriteCount;

  /// Number of writes that exceeded the configured timeout.
  final int timedOutWriteCount;

  /// Sum of observed write durations for completed or failed writes.
  final Duration totalWriteDuration;

  /// Whether this Sink is currently quarantined after a timeout.
  final bool quarantined;
}

/// Immutable, payload-free delivery health for one analytics Dispatcher.
///
/// Use this for bounded health dashboards and performance regression checks.
/// It is not an audit log, replay source, or evidence that a provider
/// durably uploaded an event.
final class CCAnalyticsDeliverySnapshot {
  /// Creates one delivery health snapshot.
  const CCAnalyticsDeliverySnapshot({
    required this.acceptedEventCount,
    required this.pendingEventCount,
    required this.peakQueueDepth,
    required this.droppedEventCount,
    required this.filteredEventCount,
    required this.blacklistedEventCount,
    required this.throttledEventCount,
    required this.sinkHealth,
    required this.isClosed,
  });

  /// Number of events accepted into the bounded queue.
  final int acceptedEventCount;

  /// Number of events currently waiting for a Sink.
  final int pendingEventCount;

  /// Highest queue depth observed since construction.
  final int peakQueueDepth;

  /// Number of events evicted under queue pressure.
  final int droppedEventCount;

  /// Number of events rejected by enablement, consent, or sampling.
  final int filteredEventCount;

  /// Number of events rejected by the blacklist.
  final int blacklistedEventCount;

  /// Number of events rejected by the common throttle.
  final int throttledEventCount;

  /// Health counters in configured Sink order.
  final List<CCAnalyticsSinkHealth> sinkHealth;

  /// Whether the Dispatcher has stopped accepting events.
  final bool isClosed;
}

/// A bounded asynchronous fan-out dispatcher for analytics sinks.
///
/// Events are delivered in FIFO order to each sink on a later event-loop turn.
/// When [capacity] is full, the oldest queued analytics event is dropped
/// and [droppedEventCount] increases. The dispatcher never waits for a sink on
/// the caller's navigation or widget callback stack.
final class CCAnalyticsEventDispatcher {
  /// Creates a dispatcher with a bounded queue and immutable sink list.
  CCAnalyticsEventDispatcher({
    required Iterable<CCAnalyticsSink> sinks,
    this.capacity = 256,
    this.onSinkError,
    this.sinkWriteTimeout,
    int throttleCapacity = CCAnalyticsLimits.maxThrottleEntries,
    CCAnalyticsPolicy? policy,
    double Function()? randomSource,
    DateTime Function()? clock,
  }) : sinks = List.unmodifiable(sinks),
       _policy = policy ?? CCAnalyticsPolicy(),
       _throttleCapacity = throttleCapacity {
    if (capacity <= 0) {
      throw ArgumentError.value(capacity, 'capacity', 'Must be positive.');
    }
    if (throttleCapacity <= 0 ||
        throttleCapacity > CCAnalyticsLimits.maxThrottleEntries) {
      throw ArgumentError.value(
        throttleCapacity,
        'throttleCapacity',
        'Must be between 1 and ${CCAnalyticsLimits.maxThrottleEntries}.',
      );
    }
    final timeout = sinkWriteTimeout;
    if (timeout != null && timeout <= Duration.zero) {
      throw ArgumentError.value(
        timeout,
        'sinkWriteTimeout',
        'Must be positive when provided.',
      );
    }
    _randomSource = randomSource ?? _defaultAnalyticsRandomSource;
    _clock = clock ?? DateTime.now;
  }

  /// Maximum number of events retained while sinks are busy.
  final int capacity;

  /// Sinks receiving each accepted event in declaration order.
  final List<CCAnalyticsSink> sinks;

  /// Optional isolated sink failure callback.
  final CCAnalyticsSinkErrorHandler? onSinkError;

  /// Maximum time awaited for one sink write before that sink is quarantined.
  ///
  /// The default is null and preserves the normal Sink contract: [close]
  /// waits for a write to finish. A configured timeout bounds dispatcher
  /// shutdown and prevents a permanently slow sink from blocking other sinks.
  /// Dart Futures cannot be cancelled, so the underlying write may still
  /// finish later; the quarantined sink receives no further events.
  final Duration? sinkWriteTimeout;

  /// Current immutable consent, enablement, and sampling policy.
  CCAnalyticsPolicy get policy => _policy;

  /// Observes policy changes and closure without receiving event payloads.
  ///
  /// Explicit UI targets use this to cancel dwell timers on revocation and
  /// start fresh measurements after grant. Callbacks run synchronously after
  /// state changes, must be short, and must not call [updatePolicy] reentrantly.
  /// Failures are isolated. The owner must call the returned remover on detach;
  /// [close] notifies and releases all listeners. A close during notification
  /// lets remaining observers read the terminal state in that same pass.
  /// Closed dispatchers do not
  /// accept listeners, and registration does not emit an initial notification.
  void Function() addPolicyListener(void Function() listener) {
    if (_closed) return () {};
    _policyListeners.add(listener);
    return () => _policyListeners.remove(listener);
  }

  /// Number of events discarded because the bounded queue was full.
  int get droppedEventCount => _droppedEventCount;

  /// Number of events currently waiting for a sink.
  ///
  /// The event currently being written by a sink is not included. This is a
  /// bounded diagnostic value for queue-pressure benchmarks and health
  /// dashboards, not for replay or event inspection.
  int get pendingEventCount => _queue.length;

  /// Highest number of events retained in the queue since construction.
  ///
  /// This value contains no event payloads and is intended for comparing
  /// bounded queue pressure between equivalent runs.
  int get peakQueueDepth => _peakQueueDepth;

  /// Number of events accepted by policy and placed in the queue.
  int get acceptedEventCount => _acceptedEventCount;

  /// Number of events rejected by [policy] before queueing.
  int get filteredEventCount => _filteredEventCount;

  /// Number of events rejected specifically by the policy blacklist.
  int get blacklistedEventCount => _blacklistedEventCount;

  /// Number of events rejected by the common per-ID throttle window.
  int get throttledEventCount => _throttledEventCount;

  /// Number of sinks quarantined after exceeding [sinkWriteTimeout].
  ///
  /// This is a payload-free health signal. A quarantined sink remains skipped
  /// until this dispatcher is closed; create a new dispatcher after repairing
  /// the application-owned sink.
  int get quarantinedSinkCount => _quarantinedSinks.length;

  /// Number of sink writes that exceeded [sinkWriteTimeout].
  int get timedOutSinkWriteCount => _timedOutSinkWriteCount;

  /// Returns a payload-free health snapshot for this Dispatcher.
  CCAnalyticsDeliverySnapshot get snapshot => CCAnalyticsDeliverySnapshot(
    acceptedEventCount: acceptedEventCount,
    pendingEventCount: pendingEventCount,
    peakQueueDepth: peakQueueDepth,
    droppedEventCount: droppedEventCount,
    filteredEventCount: filteredEventCount,
    blacklistedEventCount: blacklistedEventCount,
    throttledEventCount: throttledEventCount,
    sinkHealth: List.unmodifiable(
      List.generate(
        sinks.length,
        (index) => _sinkHealth[index].snapshot(
          sinkIndex: index,
          quarantined: _quarantinedSinks.contains(sinks[index]),
        ),
      ),
    ),
    isClosed: isClosed,
  );

  /// Whether [close] has stopped accepting new events.
  bool get isClosed => _closed;

  /// Enqueues [event] without waiting for sink completion.
  ///
  /// Returns false after [close] or when no event can be accepted. The current
  /// implementation drops the oldest queued event under pressure so a recent
  /// page or interaction signal remains available to the provider.
  bool dispatch(CCAnalyticsEvent event) {
    if (_closed || sinks.isEmpty || !_accepts(event)) return false;
    if (_queue.length >= capacity) {
      _queue.removeFirst();
      _droppedEventCount++;
    }
    _queue.addLast(event);
    _acceptedEventCount++;
    if (_queue.length > _peakQueueDepth) {
      _peakQueueDepth = _queue.length;
    }
    _scheduleDrain();
    return true;
  }

  /// Replaces [nextPolicy] and clears pending events when delivery is disabled.
  ///
  /// Revoking consent or disabling delivery also invalidates the remaining
  /// sinks of an in-flight event, even if consent is granted again immediately.
  /// A write already executing in a sink cannot be retracted. Other policy
  /// fields (sampling, blacklist, throttle) apply when accepting new events.
  void updatePolicy(CCAnalyticsPolicy nextPolicy) {
    if (_notifyingPolicy) {
      throw StateError('Analytics policy listeners cannot update policy.');
    }
    _policy = nextPolicy;
    _lastAcceptedAt.clear();
    if (!nextPolicy.enabled || !nextPolicy.consentGranted) {
      _deliveryEpoch++;
      _queue.clear();
    }
    _notifyPolicyListeners();
  }

  /// Stops accepting events and waits for already queued events to finish.
  ///
  /// This also waits for a scheduled drain that has not started yet. A sink
  /// must not await this Future from its own write, since close waits for that
  /// same write. Consent revocation may still discard pending deliveries.
  Future<void> close() async {
    if (!_closed) {
      _closed = true;
      _notifyPolicyListeners();
      if (!_notifyingPolicy) _policyListeners.clear();
    }
    final drain = _drainFuture;
    if (drain != null) await drain;
    _queue.clear();
  }

  /// Events waiting for a sink to become available.
  final Queue<CCAnalyticsEvent> _queue = Queue<CCAnalyticsEvent>();

  /// In-flight queue drain, used to make [close] await the same operation.
  Future<void>? _drainFuture;

  /// Whether this dispatcher has entered its terminal state.
  bool _closed = false;

  /// Number of events evicted by queue pressure.
  int _droppedEventCount = 0;

  /// Highest observed number of queued events.
  int _peakQueueDepth = 0;

  /// Number of events accepted before asynchronous delivery.
  int _acceptedEventCount = 0;

  /// Number of events filtered by consent, enablement, or sampling.
  int _filteredEventCount = 0;

  /// Number of events excluded by [CCAnalyticsPolicy.blockedEventIds].
  int _blacklistedEventCount = 0;

  /// Number of events excluded by [CCAnalyticsPolicy.throttleWindow].
  int _throttledEventCount = 0;

  /// Number of event IDs retained by the throttle map.
  final int _throttleCapacity;

  /// Current mutable policy slot updated only through [updatePolicy].
  CCAnalyticsPolicy _policy;

  /// Lifecycle-owned observers; entries carry no analytics payloads.
  final Set<void Function()> _policyListeners = {};

  /// Prevents recursive policy mutation while a state snapshot is observed.
  bool _notifyingPolicy = false;

  /// Delivers lifecycle state changes without letting observers alter results.
  void _notifyPolicyListeners() {
    if (_notifyingPolicy) return;
    _notifyingPolicy = true;
    try {
      for (final listener in _policyListeners.toList()) {
        if (!_policyListeners.contains(listener)) continue;
        try {
          listener();
        } catch (_) {
          // Policy observation cannot interrupt consent or queue cleanup.
        }
      }
    } finally {
      _notifyingPolicy = false;
      if (_closed) _policyListeners.clear();
    }
  }

  /// Revocation generation invalidating remaining writes of an active event.
  ///
  /// Granting consent never restores an older generation. Queued events are
  /// cleared on revocation, so only the active drain needs to capture it.
  int _deliveryEpoch = 0;

  /// Random source isolated for deterministic sampling tests.
  late final double Function() _randomSource;

  /// Injected clock used for deterministic throttling tests.
  late final DateTime Function() _clock;

  /// Last accepted timestamp per stable event ID.
  final Map<String, DateTime> _lastAcceptedAt = {};

  /// Sinks whose writes exceeded the configured deadline.
  final Set<CCAnalyticsSink> _quarantinedSinks = Set.identity();

  /// Mutable delivery counters in configured Sink order.
  late final List<_MutableAnalyticsSinkHealth> _sinkHealth = List.generate(
    sinks.length,
    (_) => _MutableAnalyticsSinkHealth(),
  );

  /// Number of writes that exceeded [sinkWriteTimeout].
  int _timedOutSinkWriteCount = 0;

  /// Schedules exactly one asynchronous queue drain.
  void _scheduleDrain() {
    if (_drainFuture != null) return;
    // Establish single-flight ownership before invoking any user callback.
    // Future schedules an event-loop turn rather than running the first sink
    // synchronously on a navigation or widget callback stack.
    _drainFuture = Future<void>(() async {
      try {
        do {
          await _drain();
          // Include events admitted by other completion listeners while the
          // previous drain Future was completing, before releasing ownership.
        } while (_queue.isNotEmpty);
      } finally {
        _drainFuture = null;
      }
    });
  }

  /// Delivers queued events while isolating every sink failure.
  Future<void> _drain() async {
    while (_queue.isNotEmpty) {
      final event = _queue.removeFirst();
      final epoch = _deliveryEpoch;
      for (var sinkIndex = 0; sinkIndex < sinks.length; sinkIndex++) {
        final sink = sinks[sinkIndex];
        if (_quarantinedSinks.contains(sink)) continue;
        if (epoch != _deliveryEpoch ||
            !_policy.enabled ||
            !_policy.consentGranted) {
          break;
        }
        final stopwatch = Stopwatch()..start();
        try {
          final write = Future<void>.sync(() => sink.write(event));
          final timeout = sinkWriteTimeout;
          if (timeout == null) {
            await write;
          } else {
            try {
              await write.timeout(timeout);
            } on TimeoutException {
              _timedOutSinkWriteCount++;
              _sinkHealth[sinkIndex].timedOutWriteCount++;
              _quarantinedSinks.add(sink);
              rethrow;
            }
          }
          _sinkHealth[sinkIndex].successfulWriteCount++;
        } catch (error, stackTrace) {
          _sinkHealth[sinkIndex].failedWriteCount++;
          try {
            onSinkError?.call(error, stackTrace, event);
          } catch (_) {
            // Observability failures must never escape into the caller.
          }
        } finally {
          _sinkHealth[sinkIndex].totalWriteDuration += stopwatch.elapsed;
        }
      }
    }
  }

  /// Applies the policy before an event is allowed to consume queue capacity.
  bool _accepts(CCAnalyticsEvent event) {
    if (!policy.enabled || !policy.consentGranted) {
      _filteredEventCount++;
      return false;
    }
    if (policy.sampleRate <= 0 ||
        (policy.sampleRate < 1 && _randomSource() >= policy.sampleRate)) {
      _filteredEventCount++;
      return false;
    }
    if (policy.blockedEventIds.contains(event.eventId)) {
      _filteredEventCount++;
      _blacklistedEventCount++;
      return false;
    }
    final throttleWindow = policy.throttleWindow;
    if (throttleWindow != null) {
      final now = _clock();
      _pruneThrottleState(now, throttleWindow);
      final lastAccepted = _lastAcceptedAt[event.eventId];
      if (lastAccepted != null &&
          now.difference(lastAccepted) < throttleWindow) {
        _filteredEventCount++;
        _throttledEventCount++;
        return false;
      }
      if (!_lastAcceptedAt.containsKey(event.eventId) &&
          _lastAcceptedAt.length >= _throttleCapacity) {
        _lastAcceptedAt.remove(_lastAcceptedAt.keys.first);
      }
      // Removing and re-adding gives the bounded map a deterministic oldest
      // entry for the next eviction.
      _lastAcceptedAt.remove(event.eventId);
      _lastAcceptedAt[event.eventId] = now;
    } else if (_lastAcceptedAt.isNotEmpty) {
      _lastAcceptedAt.clear();
    }
    return true;
  }

  /// Removes throttle entries that can no longer reject an event.
  void _pruneThrottleState(DateTime now, Duration window) {
    _lastAcceptedAt.removeWhere(
      (_, timestamp) =>
          !now.isBefore(timestamp) && now.difference(timestamp) >= window,
    );
  }
}

/// Mutable counterpart used only inside a Dispatcher.
final class _MutableAnalyticsSinkHealth {
  int successfulWriteCount = 0;
  int failedWriteCount = 0;
  int timedOutWriteCount = 0;
  Duration totalWriteDuration = Duration.zero;

  CCAnalyticsSinkHealth snapshot({
    required int sinkIndex,
    required bool quarantined,
  }) => CCAnalyticsSinkHealth(
    sinkIndex: sinkIndex,
    successfulWriteCount: successfulWriteCount,
    failedWriteCount: failedWriteCount,
    timedOutWriteCount: timedOutWriteCount,
    totalWriteDuration: totalWriteDuration,
    quarantined: quarantined,
  );
}

final math.Random _analyticsRandom = math.Random();

/// Default non-deterministic source used by production sampling.
double _defaultAnalyticsRandomSource() => _analyticsRandom.nextDouble();

/// Validates one stable event identity before it reaches a sink.
void _validateAnalyticsEventId(String value) {
  if (value.isEmpty ||
      value.length > 128 ||
      !_analyticsIdentifierPattern.hasMatch(value)) {
    throw ArgumentError.value(value, 'eventId', 'Invalid analytics ID.');
  }
}

/// Validates an optional correlation or framework identity field.
void _validateOptionalIdentifier(String? value, String name) {
  if (value == null) return;
  if (value.isEmpty ||
      value.length > 128 ||
      !_analyticsCorrelationPattern.hasMatch(value)) {
    throw ArgumentError.value(value, name, 'Invalid analytics identifier.');
  }
}

/// Validates a provider-neutral property name.
void _validateAnalyticsPropertyName(String value) {
  if (value.isEmpty ||
      value.length > 40 ||
      !_analyticsPropertyNamePattern.hasMatch(value)) {
    throw ArgumentError.value(
      value,
      'name',
      'Invalid analytics property name.',
    );
  }
}

/// Copies and validates the deliberately narrow analytics property value set.
///
/// Validate the copied list so no caller-owned mutable collection survives the
/// boundary. Nested collections and arbitrary objects remain unsupported.
Object _snapshotAnalyticsPropertyValue(Object value) {
  if (value is String) {
    if (value.length > CCAnalyticsLimits.maxStringLength) {
      throw ArgumentError.value(
        value,
        'value',
        'Analytics strings may contain at most '
            '${CCAnalyticsLimits.maxStringLength} characters.',
      );
    }
    return value;
  }
  if (value is num) {
    if (!value.isFinite) {
      throw ArgumentError.value(
        value,
        'value',
        'Analytics numbers must be finite.',
      );
    }
    return value;
  }
  if (value is bool) return value;
  if (value is List<Object?>) {
    if (value.length > CCAnalyticsLimits.maxListLength) {
      throw ArgumentError.value(
        value,
        'value',
        'Analytics lists may contain at most '
            '${CCAnalyticsLimits.maxListLength} items.',
      );
    }
    final snapshot = List<Object?>.unmodifiable(value);
    if (snapshot.every(
      (item) =>
          (item is String &&
              item.length <= CCAnalyticsLimits.maxStringLength) ||
          (item is num && item.isFinite),
    )) {
      return snapshot;
    }
  }
  throw ArgumentError.value(
    value,
    'value',
    'Only String, num, bool, or String/num lists are supported.',
  );
}

/// Computes a conservative bounded size for one validated property value.
int _analyticsValueUnits(Object value) {
  if (value is String || value is num || value is bool) {
    return value.toString().length;
  }
  if (value is List<Object?>) {
    return value.fold<int>(0, (total, item) => total + item.toString().length);
  }
  // [CCAnalyticsProperty] validates before a value reaches this helper.
  return CCAnalyticsLimits.maxPropertyValueUnits + 1;
}

/// Stable identifier syntax shared by event and correlation fields.
final RegExp _analyticsIdentifierPattern = RegExp(
  r'^[a-z][A-Za-z0-9]*(?:[._-][A-Za-z0-9]+)*$',
);

/// Opaque syntax for Runtime-generated IDs that may begin with a digit.
final RegExp _analyticsCorrelationPattern = RegExp(
  r'^[A-Za-z0-9][A-Za-z0-9._-]*$',
);

/// Conservative provider-neutral property name syntax.
final RegExp _analyticsPropertyNamePattern = RegExp(r'^[A-Za-z][A-Za-z0-9_]*$');
