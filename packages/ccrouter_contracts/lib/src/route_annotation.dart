import 'route.dart';
import 'route_pattern.dart';
import 'route_placement.dart';
import 'route_presentation.dart';

/// Declares a destination whose typed contract is generated at build time.
///
/// Component authors annotate a concrete page with an unnamed constructor,
/// then include its `.ccroute.g.dart` file using `part`. The generator creates
/// arguments, an Intent factory, a codec, a definition and a page factory. It
/// never navigates or selects a backend. [R] is the page's return type; use
/// `void` for destinations without a business result.
final class CCRoute<R> {
  /// Creates compile-time route metadata owned by the registering component.
  const CCRoute({
    required this.id,
    required this.patterns,
    this.visibility = CCRouteVisibility.component,
    this.visibleTo = const {},
    this.deepLink = CCDeepLinkPolicy.disabled,
    this.presentation = const CCPagePresentation(),
    this.placement = const CCRoutePlacement.root(),
    this.interceptors = const [],
    this.description,
  });

  /// Stable route identity shared by tracing, registration and typed Intents.
  final String id;

  /// Canonical pattern and aliases; exactly one reversible pattern is primary.
  final List<CCRoutePattern> patterns;

  /// Whether the generated contract is library-private or explicitly exported.
  ///
  /// Component-only routes generate private declarations in the page library.
  /// Exported declarations require a deliberate component barrel export;
  /// cross-package dependency and allowlist checks are a separate build stage.
  final CCRouteVisibility visibility;

  /// Consumers permitted by the future component aggregation validator.
  ///
  /// Preserved in the definition, not interpreted as Runtime authorization.
  final Set<String> visibleTo;

  /// Whether a controlled external ingress may resolve this destination.
  final CCDeepLinkPolicy deepLink;

  /// Adapter-neutral page, dialog or modal-sheet presentation metadata.
  final CCRoutePresentation presentation;

  /// Explicit host, parent, shell and outlet placement metadata.
  final CCRoutePlacement placement;

  /// Registered route-level interceptor identities in execution order.
  final List<String> interceptors;

  /// Route purpose for IDE documentation and future document exports.
  final String? description;
}

/// Marks a constructor parameter as a single URI query value.
///
/// Use for optional filters or a required query value. Scalars support String,
/// int, double, bool and enums. Missing optional values use the constructor
/// default or null; repeated scalar values and invalid values are rejected.
final class CCQueryParam {
  /// Uses the constructor parameter's name unless [name] supplies a wire name.
  const CCQueryParam({this.name});

  /// URI query key, independent of the generated Dart parameter name.
  final String? name;
}

/// Marks the one in-memory constructor parameter carried outside the URI.
///
/// Use for optional snapshots or complex application objects. A required Extra
/// cannot be combined with enabled deep links, and wrong Extra types produce
/// a parameter error. Extra is not serialized or suitable for restoration.
final class CCExtraParam {
  /// Declares a typed, process-local Extra value.
  const CCExtraParam();
}
