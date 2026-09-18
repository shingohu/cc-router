/// Describes how a route is presented by a navigation adapter.
///
/// Route owners select one presentation in their generated definition. The
/// presentation is adapter-neutral metadata: business callers cannot override
/// it for individual navigation operations, and adapters must reject a route
/// at initialization when they cannot preserve the requested semantics.
sealed class CCRoutePresentation {
  /// Creates presentation metadata for a route definition.
  const CCRoutePresentation();
}

/// Selects the Flutter page-route family requested by a page presentation.
///
/// The values describe portable intent rather than exposing Flutter's
/// `PageRoute` classes through the Pure Dart contracts package. Navigation
/// adapters map the selected value to their corresponding backend primitive.
enum CCPageRouteType {
  /// Delegates page-route selection to the adapter and host application.
  ///
  /// Use this for most pages so a Material, Cupertino, or custom host can apply
  /// its configured platform behavior without route-specific overrides.
  platformDefault,

  /// Requests Material page-route semantics.
  ///
  /// Use this when the route intentionally follows the host's Material page
  /// transition policy. This does not require a fixed Android animation:
  /// Flutter's Material route can still adapt through `PageTransitionsTheme`.
  material,

  /// Requests Cupertino page-route semantics.
  ///
  /// Use this for a route that specifically requires Cupertino transitions and
  /// back-gesture behavior instead of the host application's default route.
  cupertino,
}

/// Selects a portable transition animation for a page presentation.
///
/// This describes the page's entrance and reverse transition without exposing
/// Flutter animation classes through the Pure Dart contracts package. An
/// adapter may map [platformDefault] to its host transition policy, while
/// explicit values must be preserved or rejected during initialization.
enum CCPageTransitionType {
  /// Uses the selected page family's default transition.
  ///
  /// Use this for ordinary pages that should follow the Material, Cupertino,
  /// or host application transition policy.
  platformDefault,

  /// Fades the page in and out.
  ///
  /// Use this for subtle state changes or an intentionally low-motion page.
  fade,

  /// Scales the page from a slightly smaller size while fading it in.
  ///
  /// Use this for focused content that should feel elevated without being a
  /// modal dialog.
  scale,

  /// Slides the page in from the right and reverses back to the right.
  ///
  /// Use this when a route should explicitly follow a conventional detail
  /// navigation transition independent of the host platform.
  slideFromRight,

  /// Slides a full-screen page in from the bottom and reverses downward.
  ///
  /// Use this for full-screen tasks such as a poster-sharing or preview page.
  /// This is still a normal page route; use [CCModalBottomSheetPresentation]
  /// when the destination should be a draggable, barrier-backed sheet.
  slideFromBottom,

  /// Presents the page without an animated transition.
  ///
  /// Use this for state restoration, accessibility-sensitive flows, or pages
  /// whose content supplies its own animation.
  none,
}

/// Selects the Flutter dialog-route family requested by a dialog presentation.
///
/// Dialog routes have different transition and modal-barrier conventions from
/// page routes, so this type remains separate from [CCPageRouteType]. Adapters
/// that cannot provide the requested family must reject the route during
/// initialization.
enum CCDialogRouteType {
  /// Delegates dialog-route selection to the adapter and host application.
  ///
  /// Use this for dialogs that should follow the surrounding Material,
  /// Cupertino, or custom application style.
  platformDefault,

  /// Requests Material dialog-route transitions and barrier conventions.
  ///
  /// Use this only when the dialog intentionally belongs to a Material flow,
  /// independent of the host application's default dialog family.
  material,

  /// Requests Cupertino dialog-route transitions and barrier conventions.
  ///
  /// Use this for alerts or decisions that specifically require Cupertino
  /// presentation rather than the host application's default dialog family.
  cupertino,
}

/// Presents route content as a page in a navigator stack.
///
/// Use this for full-screen application destinations, including transparent
/// overlay pages. Use [CCModalBottomSheetPresentation] for a modal sheet or
/// [CCDialogPresentation] for a centered dialog rather than approximating
/// either one with a non-opaque page.
final class CCPagePresentation extends CCRoutePresentation {
  /// Creates page presentation metadata.
  const CCPagePresentation({
    this.routeType = CCPageRouteType.platformDefault,
    this.transition = CCPageTransitionType.platformDefault,
    this.opaque = true,
    this.fullscreenDialog = false,
  });

  /// Page-route family that the navigation adapter must preserve.
  ///
  /// Leave this as [CCPageRouteType.platformDefault] for ordinary pages. An
  /// explicit family is appropriate only when the page interaction depends on
  /// that family's transition or back-navigation semantics.
  final CCPageRouteType routeType;

  /// Entrance and reverse transition requested for this page.
  ///
  /// Use [CCPageTransitionType.slideFromBottom] for a full-screen page that
  /// enters from the bottom, such as a share poster preview. The transition
  /// does not turn the page into a modal bottom sheet.
  final CCPageTransitionType transition;

  /// Whether the page completely obscures routes below it after transitioning.
  ///
  /// Keep this true for ordinary pages. Set it to false for transparent overlay
  /// pages whose content intentionally reveals an earlier route; the adapter
  /// must then retain and render the covered route.
  final bool opaque;

  /// Whether the page behaves as a full-screen modal dialog.
  ///
  /// Use this for full-screen tasks that need dialog transitions or a close
  /// affordance. It does not represent a bottom sheet or a non-full-screen
  /// dialog.
  final bool fullscreenDialog;
}

/// Presents route content as a modal bottom sheet.
///
/// A modal sheet prevents interaction with the route beneath it and remains a
/// real navigation entry, so push results, pop operations, interceptors, and
/// telemetry continue through CCRouter. Use it for focused choices, filters,
/// or short forms; persistent Scaffold sheets are view state and should not be
/// declared as routes.
final class CCModalBottomSheetPresentation extends CCRoutePresentation {
  /// Creates modal bottom-sheet presentation metadata.
  const CCModalBottomSheetPresentation({
    this.isDismissible = true,
    this.enableDrag = true,
    this.isScrollControlled = false,
    this.showDragHandle,
    this.useSafeArea = false,
  });

  /// Whether tapping the modal barrier may dismiss the sheet.
  ///
  /// Disable this for flows that require an explicit decision, while still
  /// providing an accessible in-sheet action that can close or cancel it.
  final bool isDismissible;

  /// Whether the user may drag the sheet and dismiss it with a downward swipe.
  ///
  /// Disable this when an accidental gesture could abandon required input.
  final bool enableDrag;

  /// Whether the sheet may integrate with scroll-controlled sheet behavior.
  ///
  /// Enable this for long or scrollable content that needs to grow beyond the
  /// adapter's normal non-scroll-controlled height.
  final bool isScrollControlled;

  /// Whether a drag handle should be shown, or null to use the adapter theme.
  ///
  /// Set an explicit value only when the route's interaction design requires a
  /// stable choice independent of application theme defaults.
  final bool? showDragHandle;

  /// Whether the sheet content should avoid relevant system intrusions.
  ///
  /// Enable this when edge content must remain clear of system UI. Adapters map
  /// the intent to the safe-area mechanism available in their backend.
  final bool useSafeArea;
}

/// Presents route content as a modal dialog above the current route.
///
/// Use a registered dialog route when a cross-component flow needs typed
/// results, interception, telemetry, or navigation restoration. Page-local
/// confirmations and transient error messages should stay local to their page
/// instead of expanding the application route contract.
final class CCDialogPresentation extends CCRoutePresentation {
  /// Creates modal-dialog presentation metadata.
  const CCDialogPresentation({
    this.routeType = CCDialogRouteType.platformDefault,
    this.barrierDismissible,
    this.useSafeArea = true,
  });

  /// Dialog-route family that the navigation adapter must preserve.
  ///
  /// Leave this as [CCDialogRouteType.platformDefault] for dialogs that should
  /// follow the host application's design system.
  final CCDialogRouteType routeType;

  /// Whether tapping the modal barrier dismisses the dialog.
  ///
  /// A null value preserves the selected dialog family's default: Material
  /// dialogs are normally dismissible while Cupertino dialogs are normally not.
  /// Set an explicit value when the workflow requires consistent behavior on
  /// every platform.
  final bool? barrierDismissible;

  /// Whether dialog content should avoid system intrusions.
  ///
  /// Keep this enabled for ordinary dialogs. Disable it only for intentional
  /// edge-to-edge dialog content that handles system insets itself.
  final bool useSafeArea;
}
