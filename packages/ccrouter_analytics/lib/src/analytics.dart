import 'dart:async';
import 'dart:collection';

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
  CCAnalyticsProperty(this.name, this.value) {
    _validateAnalyticsPropertyName(name);
    _validateAnalyticsPropertyValue(value);
  }

  /// Stable property name understood by the application analytics schema.
  final String name;

  /// Provider-neutral primitive value.
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
    for (final entry in entries) {
      if (values.containsKey(entry.name)) {
        throw ArgumentError.value(
          entry.name,
          'entries',
          'Analytics property names must be unique.',
        );
      }
      values[entry.name] = entry.value;
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
  });

  /// Bounded dispatcher receiving accepted events.
  final CCAnalyticsEventDispatcher dispatcher;

  /// Stable page or feature context applied to each event.
  final CCAnalyticsContext context;

  /// Records an event of [type] and returns whether it entered the queue.
  bool track({
    required String eventId,
    required CCAnalyticsEventType type,
    CCAnalyticsProperties properties = const CCAnalyticsProperties.empty(),
  }) => dispatcher.dispatch(
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
  }) : sinks = List.unmodifiable(sinks) {
    if (capacity <= 0) {
      throw ArgumentError.value(capacity, 'capacity', 'Must be positive.');
    }
  }

  /// Maximum number of events retained while sinks are busy.
  final int capacity;

  /// Sinks receiving each accepted event in declaration order.
  final List<CCAnalyticsSink> sinks;

  /// Optional isolated sink failure callback.
  final CCAnalyticsSinkErrorHandler? onSinkError;

  /// Number of events discarded because the bounded queue was full.
  int get droppedEventCount => _droppedEventCount;

  /// Whether [close] has stopped accepting new events.
  bool get isClosed => _closed;

  /// Enqueues [event] without waiting for sink completion.
  ///
  /// Returns false after [close] or when no event can be accepted. The current
  /// implementation drops the oldest queued event under pressure so a recent
  /// page or interaction signal remains available to the provider.
  bool dispatch(CCAnalyticsEvent event) {
    if (_closed || sinks.isEmpty) return false;
    if (_queue.length >= capacity) {
      _queue.removeFirst();
      _droppedEventCount++;
    }
    _queue.addLast(event);
    _scheduleDrain();
    return true;
  }

  /// Stops accepting events and waits for already queued events to finish.
  Future<void> close() async {
    _closed = true;
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

  /// Schedules exactly one asynchronous queue drain.
  void _scheduleDrain() {
    if (_drainFuture != null) return;
    _drainFuture = _drain().whenComplete(() => _drainFuture = null);
  }

  /// Delivers queued events while isolating every sink failure.
  Future<void> _drain() async {
    while (_queue.isNotEmpty) {
      final event = _queue.removeFirst();
      for (final sink in sinks) {
        try {
          await sink.write(event);
        } catch (error, stackTrace) {
          try {
            onSinkError?.call(error, stackTrace, event);
          } catch (_) {
            // Observability failures must never escape into the caller.
          }
        }
      }
    }
  }
}

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

/// Validates the deliberately narrow analytics property value set.
void _validateAnalyticsPropertyValue(Object value) {
  if (value is String || value is num || value is bool) return;
  if (value is List<Object?> &&
      value.every((item) => item is String || item is num)) {
    return;
  }
  throw ArgumentError.value(
    value,
    'value',
    'Only String, num, bool, or String/num lists are supported.',
  );
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
