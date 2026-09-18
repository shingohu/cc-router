/// Adapter-neutral window and adaptive-layout contracts.
///
/// These values describe host geometry and presentation intent without
/// importing Flutter, platform display APIs, or Widget types.

/// Broad width class used by adaptive navigation policies.
enum CCWindowSizeClass {
  /// Compact layout, normally one primary pane.
  compact,

  /// Medium layout, suitable for a primary pane with optional secondary UI.
  medium,

  /// Expanded layout, suitable for persistent list/detail or multi-pane UI.
  expanded,
}

/// Common layout shape selected for a Host.
enum CCAdaptiveLayoutKind {
  /// One active navigation outlet fills the available window.
  singlePane,

  /// Two related outlets are visible at the same time.
  splitPane,

  /// Multiple persistent outlets can remain visible concurrently.
  multiPane,
}

/// Rectangular display-feature bounds in logical units.
final class CCLayoutRect {
  /// Creates immutable bounds for a fold, hinge, or cutout.
  const CCLayoutRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  /// Horizontal origin.
  final double left;

  /// Vertical origin.
  final double top;

  /// Feature width.
  final double width;

  /// Feature height.
  final double height;
}

/// Kind of physical display feature affecting adaptive layout.
enum CCDisplayFeatureType {
  /// A hinge or fold that separates two display regions.
  hinge,

  /// A non-separating fold or crease.
  fold,

  /// A camera or sensor cutout that occludes content.
  cutout,
}

/// Physical display feature reported for one Window Host.
final class CCDisplayFeature {
  /// Creates a display-feature observation.
  const CCDisplayFeature({
    required this.type,
    required this.bounds,
    this.separating = false,
  });

  /// Physical feature classification.
  final CCDisplayFeatureType type;

  /// Feature bounds in logical window units.
  final CCLayoutRect bounds;

  /// Whether the feature separates the window into distinct regions.
  final bool separating;
}

/// Immutable geometry and display state for one navigation Host.
final class CCWindowMetrics {
  /// Creates metrics for [hostId] and [windowId].
  CCWindowMetrics({
    required this.hostId,
    required this.windowId,
    required this.width,
    required this.height,
    List<CCDisplayFeature> displayFeatures = const [],
  }) : displayFeatures = List.unmodifiable(displayFeatures);

  /// Stable navigation Host identity.
  final String hostId;

  /// Stable platform Window identity within the Host.
  final String windowId;

  /// Logical width of the window.
  final double width;

  /// Logical height of the window.
  final double height;

  /// Fold, hinge, and cutout observations affecting placement.
  final List<CCDisplayFeature> displayFeatures;

  /// Width class used by the default adaptive policy.
  CCWindowSizeClass get sizeClass {
    if (width < 600) return CCWindowSizeClass.compact;
    if (width < 840) return CCWindowSizeClass.medium;
    return CCWindowSizeClass.expanded;
  }

  /// Whether at least one separating display feature is present.
  bool get hasSeparatingFeature =>
      displayFeatures.any((feature) => feature.separating);
}

/// Maps a Host size class to a navigation layout shape.
final class CCAdaptivePresentationPolicy {
  /// Creates a policy with conservative single-pane defaults.
  const CCAdaptivePresentationPolicy({
    this.compact = CCAdaptiveLayoutKind.singlePane,
    this.medium = CCAdaptiveLayoutKind.splitPane,
    this.expanded = CCAdaptiveLayoutKind.splitPane,
  });

  /// Layout selected for compact windows.
  final CCAdaptiveLayoutKind compact;

  /// Layout selected for medium windows.
  final CCAdaptiveLayoutKind medium;

  /// Layout selected for expanded windows.
  final CCAdaptiveLayoutKind expanded;

  /// Selects the layout for [metrics] without mutating navigation state.
  CCAdaptiveLayoutKind select(CCWindowMetrics metrics) =>
      switch (metrics.sizeClass) {
        CCWindowSizeClass.compact => compact,
        CCWindowSizeClass.medium => medium,
        CCWindowSizeClass.expanded => expanded,
      };
}
