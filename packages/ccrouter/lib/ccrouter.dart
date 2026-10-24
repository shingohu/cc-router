/// Public business-facing CCRouter API.
///
/// Flutter business and component code imports this library for framework
/// contracts and the static facade. Runtime internals remain hidden.
library;

export 'package:ccrouter_contracts/ccrouter_contracts.dart'
    hide
        CCNavigationAdapter,
        CCNavigationTargetedCloseAdapter,
        CCNavigationDispatch,
        CCNavigationDispatchAdapter,
        CCNavigationParentStackAdapter,
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
        CCServiceToken,
        CCNavigationRoute,
        CCNavigationRequest,
        CCNavigationShell,
        CCPopGuardEvaluator,
        CCScopedPopGuardEvaluator,
        CCPredictiveBackEvent,
        CCPredictiveBackEventListener,
        CCPredictiveBackPhase;
export 'package:ccrouter_core/ccrouter_core.dart'
    hide
        CCRouterRuntime,
        CCRouterRuntimeRouteEntries,
        CCNavigationHostLifetime,
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
