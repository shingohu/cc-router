/// Identifies the structural role of a route in the navigation tree.
enum CCRouteKind {
  /// A destination rendered inside an existing Navigator outlet.
  page,

  /// A persistent container that owns one or more child outlets.
  shell,
}

/// Declares the explicit parent, Shell, and Navigator outlet for a route.
///
/// Route placement is adapter-neutral metadata. It prevents adapters from
/// inferring Shell structure from path prefixes and lets a GoRouter, Navigator
/// 2.0, or custom backend select a deterministic target stack. Use the root
/// placement for ordinary single-stack applications. Declare a named outlet
/// when a route belongs to a tab, master-detail pane, or another independently
/// addressable Navigator.
final class CCRoutePlacement {
  /// Creates structural placement metadata for one route contract.
  const CCRoutePlacement({
    this.parentRouteId,
    this.shellId,
    this.navigatorOutlet = 'root',
    this.routeKind = CCRouteKind.page,
  }) : assert(navigatorOutlet != '', 'navigatorOutlet cannot be empty'),
       assert(parentRouteId != '', 'parentRouteId cannot be empty'),
       assert(shellId != '', 'shellId cannot be empty');

  /// Creates the default root page placement.
  const CCRoutePlacement.root() : this();

  /// Stable route ID of the explicit parent, if this route is nested.
  ///
  /// Use this for child routes that should be resolved below a known parent;
  /// do not use a path prefix as a substitute for this relationship.
  final String? parentRouteId;

  /// Stable Shell ID that owns this route, if it is rendered in a Shell.
  ///
  /// Use the same value for routes sharing a persistent Shell container. A
  /// Shell is a layout and navigation-history boundary, not a component ID.
  final String? shellId;

  /// Stable Navigator outlet name within the parent or Shell.
  ///
  /// Use names such as `root`, `list`, `detail`, or `tab.settings` when a
  /// route must target a specific independently managed stack.
  final String navigatorOutlet;

  /// Structural role of this route in the navigation tree.
  final CCRouteKind routeKind;
}
