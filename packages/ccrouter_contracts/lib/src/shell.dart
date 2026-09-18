/// Selects the navigation structure owned by one Shell contract.
enum CCShellType {
  /// One persistent Shell container backed by a single nested Navigator.
  ///
  /// Use this for shared scaffolds, master-detail containers, and other layouts
  /// whose child destinations share one navigation history.
  singleNavigator,

  /// Multiple persistent branches with independent Navigator histories.
  ///
  /// Use this for tab bars, navigation rails, and adaptive destinations that
  /// preserve a separate stack for every branch.
  statefulBranches,
}

/// Component-owned, adapter-neutral definition of a navigation Shell.
///
/// Generated component registrars install this contract before Runtime
/// initialization. It declares stable Shell and Outlet identities but contains
/// no widgets, BuildContext, Navigator keys, or backend route objects.
final class CCShellDefinition {
  /// Creates a Shell definition with ordered [outlets].
  CCShellDefinition({
    required this.shellId,
    required this.type,
    required List<String> outlets,
    required this.initialOutlet,
    this.description,
  }) : outlets = List.unmodifiable(outlets);

  /// Stable application-wide identity referenced by route placement.
  final String shellId;

  /// Single-Navigator or stateful multi-branch navigation structure.
  final CCShellType type;

  /// Ordered stable Outlet names owned by this Shell.
  ///
  /// For stateful branches, order is part of the contract and must match the
  /// backend branch order. Use stable names rather than visual positions.
  final List<String> outlets;

  /// Outlet selected when the Shell has no restored or URI-selected branch.
  final String initialOutlet;

  /// Optional human-readable documentation description.
  final String? description;
}

/// Adapter-facing immutable snapshot of one installed Shell contract.
///
/// Navigation adapters receive this during initialization to validate their
/// application-owned Shell bindings without receiving component ownership or
/// mutable Runtime state.
final class CCNavigationShell {
  /// Creates an immutable Adapter Shell snapshot.
  CCNavigationShell({
    required this.shellId,
    required this.type,
    required List<String> outlets,
    required this.initialOutlet,
  }) : outlets = List.unmodifiable(outlets);

  /// Stable Shell identity shared with route placement and backend bindings.
  final String shellId;

  /// Navigation structure required from the backend binding.
  final CCShellType type;

  /// Ordered stable Outlet names required from the backend binding.
  final List<String> outlets;

  /// Default Outlet declared by the component contract.
  final String initialOutlet;
}
