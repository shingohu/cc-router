/// Host-only Flutter composition APIs for CCRouter backends.
///
/// Application composition roots and generated host assembly import this
/// library when wiring component page factories to a concrete navigation
/// backend. Feature code should continue to import `ccrouter.dart` and navigate
/// only through `CCRouter.navigator`.
library;

export 'package:ccrouter_contracts/ccrouter_contracts.dart'
    show
        CCContractBundleDescriptor,
        CCContractCompatibilityCode,
        CCContractCompatibilityError,
        CCContractCompatibilityIssue,
        CCContractDescriptor,
        CCContractKind,
        CCContractRequirement,
        CCNavigationAdapter,
        CCNavigationTargetedCloseAdapter,
        CCNavigationDispatch,
        CCNavigationDispatchAdapter,
        CCNavigationParentStackAdapter,
        CCRouteCloseOutcome,
        CCRouteCloseStatus,
        CCNavigationAdapterCapabilities,
        CCNavigationAdapterCapabilitySource,
        CCNavigationAdapterHostBinding,
        CCNavigationOutletVisibilityBinding,
        CCInitialBackendEntrySnapshot,
        CCNavigationBackendEvent,
        CCNavigationBackendEventListener,
        CCNavigationBackendEventSource,
        CCNavigationBackendSnapshotSource,
        CCNavigationHostCapabilitySource,
        CCNavigationManagedEntryReleaseSink,
        CCNavigationRouteExitBinding,
        CCNavigationPopCoordinator,
        CCNavigationScopedPopCoordinator,
        CCNavigationPopGuardBinding,
        CCNavigationScopedPopGuardBinding,
        CCNavigationPopTarget,
        CCNavigationPopTargetSource,
        CCNavigationScopedPopTargetSource,
        CCNavigationPredictiveBackSource,
        CCNavigationPredictiveBackSourceProvider,
        CCNavigationRoute,
        CCNavigationRequest,
        CCNavigationShell,
        CCPopGuardEvaluator,
        CCScopedPopGuardEvaluator,
        CCPredictiveBackEvent,
        CCPredictiveBackEventListener,
        CCPredictiveBackPhase;
export 'src/app.dart' show CCRouterAppBackend, CCPageLifecycleHostBridge;
export 'src/facade.dart' show CCRouterHost, CCRouterHostBinding;
export 'src/flutter_route_factory.dart';
export 'src/generated_package_bundle.dart';
export 'src/host_tool_integration.dart';
export 'src/host_lifecycle_binding.dart' show CCHostLifecycleBinding;
export 'src/multi_host.dart';
export 'src/managed_router.dart';
export 'src/managed_multi_host.dart';
export 'src/managed_predictive_back.dart';
export 'src/managed_router_app.dart';
export 'src/predictive_back_coordinator.dart';
export 'src/route_catalog.dart';
