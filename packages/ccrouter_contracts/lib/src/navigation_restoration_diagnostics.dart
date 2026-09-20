import 'navigation_telemetry.dart';

/// Platform evidence that a previous navigation state could have been restored.
///
/// These reasons describe demand signals only. They do not imply that CCRouter
/// captured or restored a navigation stack.
enum CCRouteRestorationOpportunityReason {
  /// Android recreated an Activity with non-null saved instance state.
  androidActivityRecreated,

  /// iOS or macOS requested scene or application state restoration.
  appleStateRestoration,

  /// A future desktop platform bridge reported a reopened native Window.
  desktopWindowReopened,

  /// A persisted Host marker indicates the previous session ended uncleanly.
  uncleanPreviousSession,

  /// Host evidence exists but does not fit a more precise platform category.
  unknown,
}

/// Current framework handling for a restoration opportunity.
enum CCRouteRestorationOpportunityOutcome {
  /// The opportunity was observed, but route restoration is not implemented.
  unsupported,
}

/// Sanitized Host signal consumed by Runtime restoration diagnostics.
///
/// Platform composition code creates this value from saved-instance, scene,
/// Window, or session-marker evidence. It must not contain URI parameters,
/// account identifiers, route arguments, or arbitrary application objects.
final class CCRouteRestorationOpportunitySignal {
  /// Creates one immutable demand signal.
  const CCRouteRestorationOpportunitySignal({
    required this.reason,
    required this.occurredAt,
    this.previousTopRouteId,
    this.previousHostCount,
    this.previousOutletCount,
    this.previousComponentCatalogFingerprint,
    this.applicationVersion,
  });

  /// Platform or session evidence that produced this signal.
  final CCRouteRestorationOpportunityReason reason;

  /// Time at which the Host detected the opportunity.
  final DateTime occurredAt;

  /// Last sanitized route contract ID persisted by the Host, when available.
  final String? previousTopRouteId;

  /// Number of navigation Hosts retained by the previous session.
  final int? previousHostCount;

  /// Number of visible or retained Outlets known to the previous session.
  final int? previousOutletCount;

  /// Optional fingerprint persisted for the previous component catalog.
  final String? previousComponentCatalogFingerprint;

  /// Optional application build or release version supplied by the Host.
  final String? applicationVersion;
}

/// One bounded, sanitized restoration-demand diagnostic event.
///
/// Use this event to estimate whether full route restoration is worth building.
/// It contains no restorable state and cannot be replayed as navigation input.
final class CCRouteRestorationOpportunityEvent {
  /// Creates one immutable diagnostic event from validated Host evidence.
  const CCRouteRestorationOpportunityEvent({
    required this.reason,
    required this.occurredAt,
    required this.recordedAt,
    required this.outcome,
    required this.currentComponentCatalogFingerprint,
    this.previousTopRouteId,
    this.previousHostCount,
    this.previousOutletCount,
    this.previousComponentCatalogFingerprint,
    this.applicationVersion,
    this.telemetryContext,
  });

  /// Evidence category reported by the platform Host.
  final CCRouteRestorationOpportunityReason reason;

  /// Time at which the Host detected the opportunity.
  final DateTime occurredAt;

  /// Time at which Runtime accepted the sanitized event.
  final DateTime recordedAt;

  /// Explicit statement that no restoration was attempted.
  final CCRouteRestorationOpportunityOutcome outcome;

  /// Last sanitized route ID known to the previous Host session.
  final String? previousTopRouteId;

  /// Previous Host count, when the Host persisted it.
  final int? previousHostCount;

  /// Previous Outlet count, when the Host persisted it.
  final int? previousOutletCount;

  /// Previous component catalog fingerprint, when available.
  final String? previousComponentCatalogFingerprint;

  /// Deterministic fingerprint of the currently installed component catalog.
  final String currentComponentCatalogFingerprint;

  /// Optional application release identity supplied by the Host.
  final String? applicationVersion;

  /// Anonymous analytics context captured while recording the event.
  final CCNavigationTelemetryContext? telemetryContext;
}

/// Receives one sanitized restoration-demand diagnostic event.
typedef CCRouteRestorationOpportunityListener =
    void Function(CCRouteRestorationOpportunityEvent event);

/// Host SPI supplying initial and runtime restoration-demand evidence.
///
/// Platform composition code implements this interface or uses the Flutter
/// Host controller. Runtime owns only its listener subscription and never
/// disposes the source itself.
abstract interface class CCRouteRestorationOpportunitySource {
  /// Returns and removes signals captured before Runtime initialization.
  List<CCRouteRestorationOpportunitySignal> takeInitialSignals();

  /// Subscribes to signals detected after Runtime initialization.
  ///
  /// The returned callback must detach [listener] without disposing the source.
  void Function() addListener(
    void Function(CCRouteRestorationOpportunitySignal signal) listener,
  );
}
