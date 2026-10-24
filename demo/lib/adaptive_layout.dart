/// Application-owned Demo geometry and adaptive-layout policy.
///
/// These values describe one navigation Host's available layout space and
/// presentation intent without claiming that the Host is a native platform
/// Window or importing Flutter, display APIs, or Widget types.
library;

/// Broad width class used by adaptive navigation policies.
enum DemoHostSizeClass {
  /// Compact layout, normally one primary pane.
  compact,

  /// Medium layout, suitable for a primary pane with optional secondary UI.
  medium,

  /// Expanded layout, suitable for persistent list/detail or multi-pane UI.
  expanded,
}

/// Common layout shape selected for a Host.
enum DemoAdaptiveLayoutKind {
  /// One active navigation outlet fills the available Host surface.
  singlePane,

  /// Two related outlets are visible at the same time.
  splitPane,

  /// Multiple persistent outlets can remain visible concurrently.
  multiPane,
}

/// Rectangular display-feature bounds in logical units.
final class DemoLayoutRect {
  /// Creates immutable bounds for a fold, hinge, or cutout.
  const DemoLayoutRect({
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
enum DemoDisplayFeatureType {
  /// A hinge or fold that separates two display regions.
  hinge,

  /// A non-separating fold or crease.
  fold,

  /// A camera or sensor cutout that occludes content.
  cutout,
}

/// Physical display feature reported for one navigation Host layout.
final class DemoDisplayFeature {
  /// Creates a display-feature observation.
  const DemoDisplayFeature({
    required this.type,
    required this.bounds,
    this.separating = false,
  });

  /// Physical feature classification.
  final DemoDisplayFeatureType type;

  /// Feature bounds in logical window units.
  final DemoLayoutRect bounds;

  /// Whether the feature separates the window into distinct regions.
  final bool separating;
}

/// Immutable geometry and display state for one navigation Host layout.
///
/// A Host may fill a Flutter View or occupy an embedded navigation surface.
/// Native Window identity is deliberately absent until a platform multi-window
/// bridge can supply and own that lifecycle.
final class DemoHostLayoutMetrics {
  /// Creates one layout snapshot for [hostId].
  DemoHostLayoutMetrics({
    required this.hostId,
    required this.width,
    required this.height,
    List<DemoDisplayFeature> displayFeatures = const [],
  }) : displayFeatures = List.unmodifiable(displayFeatures);

  /// Stable navigation Host identity.
  final String hostId;

  /// Logical width available to the Host.
  final double width;

  /// Logical height available to the Host.
  final double height;

  /// Fold, hinge, and cutout observations affecting placement.
  final List<DemoDisplayFeature> displayFeatures;

  /// Width class used by the default adaptive policy.
  DemoHostSizeClass get sizeClass {
    if (width < 600) return DemoHostSizeClass.compact;
    if (width < 840) return DemoHostSizeClass.medium;
    return DemoHostSizeClass.expanded;
  }

  /// Whether at least one separating display feature is present.
  bool get hasSeparatingFeature =>
      displayFeatures.any((feature) => feature.separating);
}

/// Maps a Host size class to a navigation layout shape.
final class DemoAdaptiveLayoutPolicy {
  /// Creates a policy with conservative single-pane defaults.
  const DemoAdaptiveLayoutPolicy({
    this.compact = DemoAdaptiveLayoutKind.singlePane,
    this.medium = DemoAdaptiveLayoutKind.splitPane,
    this.expanded = DemoAdaptiveLayoutKind.splitPane,
  });

  /// Layout selected for compact Host surfaces.
  final DemoAdaptiveLayoutKind compact;

  /// Layout selected for medium Host surfaces.
  final DemoAdaptiveLayoutKind medium;

  /// Layout selected for expanded Host surfaces.
  final DemoAdaptiveLayoutKind expanded;

  /// Selects the layout for [metrics] without mutating navigation state.
  DemoAdaptiveLayoutKind select(DemoHostLayoutMetrics metrics) =>
      switch (metrics.sizeClass) {
        DemoHostSizeClass.compact => compact,
        DemoHostSizeClass.medium => medium,
        DemoHostSizeClass.expanded => expanded,
      };
}

/// Maps adaptive layout kinds to the Navigator Outlets visible in one Host.
///
/// Use this at the application composition root for list/detail, foldable, or
/// desktop layouts. Route contracts still own destination placement; this
/// policy only determines which retained Outlet tops participate in display.
final class DemoAdaptiveOutletPolicy {
  /// Creates an immutable Outlet policy.
  DemoAdaptiveOutletPolicy({
    required this.primaryOutlet,
    this.secondaryOutlet,
    Iterable<String> multiPaneOutlets = const [],
  }) : multiPaneOutlets = List.unmodifiable(multiPaneOutlets) {
    if (primaryOutlet.isEmpty) {
      throw ArgumentError.value(
        primaryOutlet,
        'primaryOutlet',
        'Primary Outlet cannot be empty.',
      );
    }
    if (secondaryOutlet?.isEmpty ?? false) {
      throw ArgumentError.value(
        secondaryOutlet,
        'secondaryOutlet',
        'Secondary Outlet cannot be empty.',
      );
    }
    final identities = <String>{primaryOutlet};
    if (secondaryOutlet != null && !identities.add(secondaryOutlet!)) {
      throw ArgumentError.value(
        secondaryOutlet,
        'secondaryOutlet',
        'Adaptive Outlets must be unique.',
      );
    }
    for (final outlet in this.multiPaneOutlets) {
      if (outlet.isEmpty || !identities.add(outlet)) {
        throw ArgumentError.value(
          outlet,
          'multiPaneOutlets',
          'Adaptive Outlets must be non-empty and unique.',
        );
      }
    }
  }

  /// Outlet retained in every layout size.
  final String primaryOutlet;

  /// Optional detail or supporting Outlet added for split layouts.
  final String? secondaryOutlet;

  /// Additional Outlets displayed only for a multi-pane layout.
  final List<String> multiPaneOutlets;

  /// Resolves the active Outlets for [layout] without mutating navigation.
  List<String> activeOutletsFor(DemoAdaptiveLayoutKind layout) =>
      List.unmodifiable(switch (layout) {
        DemoAdaptiveLayoutKind.singlePane => [primaryOutlet],
        DemoAdaptiveLayoutKind.splitPane => [primaryOutlet, ?secondaryOutlet],
        DemoAdaptiveLayoutKind.multiPane => [
          primaryOutlet,
          ?secondaryOutlet,
          ...multiPaneOutlets,
        ],
      });
}

/// Immutable adaptive navigation state for one Host layout surface.
final class DemoAdaptiveHostLayoutSnapshot {
  /// Creates one resolved Host layout snapshot.
  DemoAdaptiveHostLayoutSnapshot({
    required this.metrics,
    required this.layout,
    required Iterable<String> activeOutlets,
  }) : activeOutlets = List.unmodifiable(activeOutlets);

  /// Host geometry and display-feature inputs used for this decision.
  final DemoHostLayoutMetrics metrics;

  /// Layout kind selected by the adaptive layout policy.
  final DemoAdaptiveLayoutKind layout;

  /// Navigator Outlets participating in display simultaneously.
  final List<String> activeOutlets;
}
