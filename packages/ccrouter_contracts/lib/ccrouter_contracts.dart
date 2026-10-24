/// Stable pure-Dart contracts shared by CCRouter components.
///
/// Contract packages and Pure Dart integrations import this library for value
/// types that do not depend on Flutter or a navigation backend.
library;

export 'src/component.dart';
export 'src/contract_compatibility.dart';
export 'src/deep_link.dart';
export 'src/diagnostics.dart'
    show
        CCDiagnosticCategory,
        CCDiagnosticLevel,
        CCDiagnosticCategoryPolicy,
        CCDiagnosticsConfig,
        CCDiagnosticEvent,
        CCDiagnosticSink,
        CCDiagnosticDeliverySnapshot;
export 'src/errors.dart';
export 'src/invocation.dart';
export 'src/initialization.dart';
export 'src/lifecycle.dart';
export 'src/messaging.dart';
export 'src/navigation.dart';
export 'src/navigation_close.dart';
export 'src/navigation_dispatch.dart';
export 'src/navigation_backend.dart';
export 'src/navigation_capabilities.dart';
export 'src/navigation_concurrency.dart';
export 'src/navigation_failure.dart';
export 'src/navigation_aspect.dart';
export 'src/navigation_interceptor.dart';
export 'src/navigation_lifecycle.dart';
export 'src/navigation_pending.dart';
export 'src/navigation_pop_guard.dart';
export 'src/route.dart';
export 'src/route_annotation.dart';
export 'src/route_diagnostics.dart';
export 'src/route_entry.dart';
export 'src/route_pattern.dart';
export 'src/route_placement.dart';
export 'src/route_presentation.dart';
export 'src/route_revalidation.dart';
export 'src/route_visibility.dart';
export 'src/service.dart';
export 'src/shell.dart';
