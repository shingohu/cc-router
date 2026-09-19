import 'route_pattern.dart';
import 'route_placement.dart';
import 'route_presentation.dart';
import 'route.dart';
import 'shell.dart';

/// Classifies the product-level source attached to one navigation request.
///
/// Business callers use this value for telemetry attribution. It does not
/// establish whether input is trusted and cannot enable or bypass Deep Link
/// policy checks.
enum CCNavigationSourceType {
  /// Navigation initiated by an application feature or user interaction.
  feature,

  /// Navigation attributed to a platform or browser Deep Link campaign.
  deepLink,

  /// Navigation attributed to a notification interaction.
  notification,

  /// Navigation attributed to a scanned code.
  qrCode,

  /// Navigation initiated by framework or application-host infrastructure.
  system,
}

/// Describes a non-sensitive product source for navigation telemetry.
///
/// Use stable identifiers such as `home.order_banner`; do not include complete
/// URIs, user input, tokens, or business payloads. Runtime trust decisions use
/// [CCNavigationOrigin] instead of this caller-provided metadata.
final class CCNavigationSource {
  /// Creates source metadata with an explicit [type] and stable [id].
  const CCNavigationSource({required this.type, required this.id});

  /// Creates source metadata for an application feature entry point.
  const CCNavigationSource.feature(String id)
    : this(type: CCNavigationSourceType.feature, id: id);

  /// Creates telemetry metadata for a Deep Link entry category.
  ///
  /// This constructor does not mark a request as externally sourced.
  const CCNavigationSource.deepLink(String id)
    : this(type: CCNavigationSourceType.deepLink, id: id);

  /// Creates source metadata for a notification entry point.
  const CCNavigationSource.notification(String id)
    : this(type: CCNavigationSourceType.notification, id: id);

  /// Creates source metadata for a scanned-code entry point.
  const CCNavigationSource.qrCode(String id)
    : this(type: CCNavigationSourceType.qrCode, id: id);

  /// Creates source metadata for framework or host infrastructure.
  const CCNavigationSource.system(String id)
    : this(type: CCNavigationSourceType.system, id: id);

  /// Product-level category used by telemetry consumers.
  final CCNavigationSourceType type;

  /// Stable, non-sensitive source identifier.
  final String id;
}

/// Identifies the trusted ingress that created a navigation request.
///
/// Framework hosts create this value; normal business navigation APIs do not
/// accept it. Deep Link policy is enforced whenever [isExternal] is true,
/// independently of whether the location is a path or an absolute URI.
enum CCNavigationOrigin {
  /// Trusted in-process navigation, including typed Intents and state restore.
  internal(false),

  /// URI received from a platform Universal Link, App Link, or custom Scheme.
  externalPlatform(true),

  /// URI extracted from an externally supplied notification payload.
  externalNotification(true),

  /// URI or path obtained from a scanned code or equivalent untrusted input.
  externalQrCode(true);

  /// Creates an origin with its immutable external-entry classification.
  const CCNavigationOrigin(this.isExternal);

  /// Whether route resolution must enforce the route's Deep Link policy.
  final bool isExternal;
}

/// Selects the stack operation requested from a navigation adapter.
enum CCNavigationOperation {
  /// Adds a route and completes with its eventual Pop result.
  push,

  /// Replaces the current route and completes with the replacement's result.
  replace,

  /// Changes the current location without exposing a typed Pop result.
  go,

  /// Replaces the adapter's navigation state with one root location.
  reset,

  /// Opens a dynamically resolved URI without a statically known result type.
  open,

  /// Pops the current route and pushes a typed replacement in one operation.
  popAndPush,

  /// Pushes a typed route and removes previous entries by a stack predicate.
  pushAndRemoveUntil,

  /// Replaces the managed entry immediately below an exact anchor entry.
  replaceBelow,
}

/// Read-only identity snapshot supplied to stack-operation predicates.
///
/// Predicates may inspect stable route identity and normalized URI, but they do
/// not receive mutable Adapter entries, Flutter `Route` objects, or business
/// result values. A later operation evaluates the predicate against the current
/// stack rather than relying on a retained snapshot.
final class CCNavigationEntry {
  /// Creates an immutable stack-entry snapshot.
  const CCNavigationEntry({
    required this.navigationId,
    required this.routeId,
    required this.uri,
  });

  /// Runtime-unique identity of the stack entry.
  final String navigationId;

  /// Stable registered route ID represented by the entry.
  final String routeId;

  /// Normalized address used to create the entry.
  final Uri uri;
}

/// Selects the stack entry at which a pop or removal operation must stop.
typedef CCNavigationStackPredicate = bool Function(CCNavigationEntry entry);

/// Adapter-facing immutable description of one registered route.
///
/// Adapters receive these snapshots during initialization to validate supported
/// presentation capabilities and prepare backend route tables. Codecs and
/// component ownership remain inside the Runtime.
final class CCNavigationRoute {
  /// Creates an immutable adapter-facing route description.
  CCNavigationRoute({
    required this.routeId,
    required List<CCRoutePattern> patterns,
    required this.presentation,
    required this.deepLink,
    this.placement = const CCRoutePlacement.root(),
  }) : patterns = List.unmodifiable(patterns);

  /// Stable route identity shared with generated Intents and diagnostics.
  final String routeId;

  /// Canonical address Pattern and accepted matching aliases.
  final List<CCRoutePattern> patterns;

  /// Adapter-neutral presentation behavior owned by the route definition.
  final CCRoutePresentation presentation;

  /// Whether trusted external ingress may enter this route.
  ///
  /// Runtime enforces this policy before creating a request. Adapters use the
  /// snapshot only when preparing backend Deep Link route tables.
  final CCDeepLinkPolicy deepLink;

  /// Structural placement consumed by adapters when selecting a Navigator.
  final CCRoutePlacement placement;
}

/// Immutable navigation request delivered to an adapter after Runtime checks.
///
/// The Runtime creates requests only after route availability, Deep Link policy,
/// Pattern matching or generation, and Codec validation succeed. Adapters must
/// execute the requested stack operation without repeating business routing.
final class CCNavigationRequest {
  /// Creates a fully resolved navigation request.
  const CCNavigationRequest({
    required this.navigationId,
    required this.operation,
    required this.routeId,
    required this.uri,
    required this.arguments,
    required this.presentation,
    required this.origin,
    this.ownerComponentId = '',
    this.hostId = 'default',
    this.placement = const CCRoutePlacement.root(),
    this.extra,
    this.source,
  });

  /// Runtime-unique identity used to correlate execution and diagnostics.
  final String navigationId;

  /// Stack operation the adapter must execute.
  final CCNavigationOperation operation;

  /// Stable ID of the resolved route definition.
  final String routeId;

  /// Canonical generated URI or normalized dynamically opened URI.
  final Uri uri;

  /// Typed arguments produced or accepted by the route's Codec.
  final Object arguments;

  /// Optional in-memory value encoded by a typed Intent.
  ///
  /// External navigation never carries this value.
  final Object? extra;

  /// Presentation behavior that the route owner declared.
  final CCRoutePresentation presentation;

  /// Structural parent, Shell, and Navigator outlet for this request.
  ///
  /// Adapters use this to select an explicit stack; business callers cannot
  /// override it on an individual navigation operation.
  final CCRoutePlacement placement;

  /// Trusted ingress classification assigned by framework infrastructure.
  final CCNavigationOrigin origin;

  /// Trusted owner of the resolved route, when supplied by Runtime.
  ///
  /// Business callers cannot override this value; it is used for Route Scope
  /// ownership and diagnostics rather than authorization.
  final String ownerComponentId;

  /// Window or display Host resolved for this navigation operation.
  ///
  /// When a route uses the default placement, Runtime resolves this value from
  /// an optional [CCNavigationAdapterHostBinding]. Adapters use the resolved
  /// identity to isolate windows or external displays; business callers cannot
  /// override it on an individual operation.
  final String hostId;

  /// Optional product attribution supplied for telemetry.
  final CCNavigationSource? source;
}

/// Supplies the default Host identity served by one navigation Adapter.
///
/// Flutter and multi-window Adapters implement this SPI when the route
/// contract's `default` Host must resolve to a concrete Window identity.
/// Runtime reads the value while creating requests and concurrency keys;
/// business code must not use it to bypass generated route placement.
abstract interface class CCNavigationAdapterHostBinding {
  /// Stable non-empty Host identity used for default route placement.
  String get hostId;
}

/// Adapter-neutral navigation backend contract owned by one Runtime.
///
/// Application hosts attach one ready adapter after CCRouter initialization.
/// The Runtime configures it from the registered route catalog and disposes it
/// during shutdown. Adapter lifecycle operations are synchronous transactions;
/// asynchronous resource preparation belongs to the Host before attachment.
/// Business code navigates through `CCRouter.navigator` and must not invoke an
/// adapter directly.
abstract interface class CCNavigationAdapter {
  /// Configures the ready backend for all installed [routes] and [shells].
  ///
  /// Implementations validate unsupported presentation requirements here and
  /// must return only after navigation can begin. This method must perform no
  /// asynchronous I/O; Hosts prepare such resources before attachment. Shell
  /// snapshots describe structure only, and adapters remain responsible for
  /// binding their application-owned navigation containers.
  void initialize(
    List<CCNavigationRoute> routes, {
    List<CCNavigationShell> shells = const [],
  });

  /// Executes a Runtime-validated [request].
  ///
  /// Use this operation for one-target commands: Push and Replace complete
  /// with the eventual Pop result, while Go, Reset, and Open complete after
  /// the backend accepts the operation. Composite commands such as
  /// PopAndPush and PushAndRemoveUntil must use their dedicated methods so
  /// their Pop result or stack Predicate cannot be lost at this boundary.
  Future<Object?> navigate(CCNavigationRequest request);

  /// Asks the backend to handle a Pop and reports whether it was handled.
  ///
  /// Adapters may apply backend-specific Pop vetoes, such as unsaved-form
  /// guards or gesture state. A `true` result may represent removal of a
  /// managed route, a foreign route, or a LocalHistoryEntry; callers must not
  /// infer managed Route Entry removal from this Boolean alone. A `false`
  /// result means that the backend declined the request.
  Future<bool> maybePop({Object? result});

  /// Pops the current route and pushes [request] as one atomic stack command.
  ///
  /// [popResult] completes the removed entry's pending result. The returned
  /// Future completes with the pushed entry's eventual Pop result. The removed
  /// entry's Route Scope is closed independently of the pushed entry; a Pop or
  /// adapter failure must not complete the pushed result as the old result.
  Future<Object?> popAndPush(CCNavigationRequest request, {Object? popResult});

  /// Pops entries until [predicate] matches the current entry.
  ///
  /// Removed entries complete with `null` because this operation has one
  /// aggregate completion and no per-entry result channel.
  Future<void> popUntil(CCNavigationStackPredicate predicate);

  /// Pushes [request] and removes previous entries until [predicate] matches.
  ///
  /// The newly pushed entry is never evaluated by [predicate]. Removed
  /// entries complete with `null` and close their Route Scopes; the returned
  /// Future represents only the pushed entry and completes with its eventual
  /// Pop result. A backend failure must not leave the newly allocated Runtime
  /// entry retained.
  Future<Object?> pushAndRemoveUntil(
    CCNavigationRequest request,
    CCNavigationStackPredicate predicate,
  );

  /// Removes the current route and optionally completes it with [result].
  void pop({Object? result});

  /// Whether [pop] can currently remove a route from the active stack.
  bool canPop();

  /// Releases adapter-owned listeners and in-memory state synchronously.
  ///
  /// Implementations must not dispose application-owned Router objects or wait
  /// for asynchronous I/O. Runtime and Backend shutdown own asynchronous
  /// business and platform resource release.
  void dispose();
}
