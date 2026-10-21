/// Public business-facing CCRouter API.
///
/// Flutter business and component code imports this library for framework
/// contracts and the static facade. Runtime internals remain hidden.
library;

export 'package:ccrouter_contracts/ccrouter_contracts.dart'
    hide
        CCNavigationAdapter,
        CCNavigationTargetedCloseAdapter,
        CCNavigationAdapterCapabilities,
        CCNavigationAdapterCapabilitySource,
        CCNavigationAdapterHostBinding,
        CCInitialBackendEntrySnapshot,
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
        CCServiceToken,
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
        CCRouterRuntimeRouteEntries,
        CCScope,
        CCScopeState,
        CCMemoryNavigationAdapter,
        CCServiceOverrideEntry;
export 'src/app.dart' hide CCRouterAppBackend, CCPageLifecycleHostBridge;
export 'src/facade.dart'
    hide
        CCRouterGeneratedCommandBinding,
        CCRouterGeneratedEventBinding,
        CCRouterGeneratedServiceBinding,
        CCRouterHost,
        CCRouterHostBinding,
        CCRouterTestBinding;
