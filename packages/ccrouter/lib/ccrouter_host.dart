/// Host-only Flutter composition APIs for CCRouter backends.
///
/// Application composition roots and generated host assembly import this
/// library when wiring component page factories to a concrete navigation
/// backend. Feature code should continue to import `ccrouter.dart` and navigate
/// only through `CCRouter.navigator`.
library;

export 'package:ccrouter_contracts/ccrouter_contracts.dart'
    show
        CCNavigationAdapter,
        CCNavigationAdapterCapabilities,
        CCNavigationAdapterCapabilitySource,
        CCNavigationAdapterHostBinding,
        CCNavigationBackendEntrySnapshot,
        CCNavigationBackendEvent,
        CCNavigationBackendEventListener,
        CCNavigationBackendEventSource,
        CCNavigationBackendSnapshotSource,
        CCNavigationHostCapabilitySource,
        CCNavigationManagedEntryReleaseSink,
        CCNavigationPopCoordinator,
        CCNavigationPopGuardBinding,
        CCNavigationPopTarget,
        CCNavigationPopTargetSource,
        CCNavigationPredictiveBackSource,
        CCNavigationPredictiveBackSourceProvider,
        CCNavigationRoute,
        CCNavigationRequest,
        CCNavigationShell,
        CCPopGuardEvaluator,
        CCPredictiveBackEvent,
        CCPredictiveBackEventListener,
        CCPredictiveBackPhase,
        CCRouteRestorationOpportunityReason,
        CCRouteRestorationOpportunitySignal,
        CCRouteRestorationOpportunitySource;
export 'src/app.dart' show CCRouterAppBackend, CCPageLifecycleHostBridge;
export 'src/facade.dart' show CCRouterHostBinding;
export 'src/flutter_route_factory.dart';
export 'src/generated_package_bundle.dart';
export 'src/multi_host.dart';
export 'src/restoration_diagnostics.dart';
export 'src/route_catalog.dart';
