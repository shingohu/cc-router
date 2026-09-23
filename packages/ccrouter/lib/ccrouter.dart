/// Public business-facing CCRouter API.
///
/// Flutter business and component code imports this library for framework
/// contracts and the static facade. Runtime internals remain hidden.
library;

export 'package:ccrouter_contracts/ccrouter_contracts.dart'
    hide
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
        CCRouteRestorationOpportunitySignal,
        CCRouteRestorationOpportunitySource;
export 'package:ccrouter_core/ccrouter_core.dart'
    hide
        CCRouterRuntime,
        CCScope,
        CCScopeState,
        CCMemoryNavigationAdapter,
        CCServiceOverrideEntry;
export 'src/app.dart' hide CCRouterAppBackend, CCPageLifecycleHostBridge;
export 'src/facade.dart' hide CCRouterHostBinding;
