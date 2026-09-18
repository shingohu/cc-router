/// Public business-facing CCRouter API.
///
/// Flutter business and component code imports this library for framework
/// contracts and the static facade. Runtime internals remain hidden.
library;

export 'package:ccrouter_contracts/ccrouter_contracts.dart';
export 'package:ccrouter_core/ccrouter_core.dart'
    hide CCRouterRuntime, CCScope, CCScopeState, CCMemoryNavigationAdapter;
export 'src/facade.dart';
