/// Public business-facing CCRouter API.
///
/// Flutter business and component code imports this library for framework
/// contracts and the static facade. Runtime internals remain hidden.
library;

export 'package:ccrouter_contracts/ccrouter_contracts.dart'
    hide
        CCNavigationManagedEntryReleaseSink,
        CCNavigationPopTarget,
        CCNavigationPopTargetSource,
        CCRouteRestorationOpportunitySignal,
        CCRouteRestorationOpportunitySource;
export 'package:ccrouter_core/ccrouter_core.dart'
    hide CCRouterRuntime, CCScope, CCScopeState, CCMemoryNavigationAdapter;
export 'src/app.dart' hide CCRouterAppBackend, CCPageLifecycleHostBridge;
export 'src/facade.dart' hide CCRouterHostBinding;
