/// Frozen GoRouter compatibility integration for existing CCRouter Hosts.
@Deprecated(
  'Use CCManagedRouterApp, CCManagedRouterBackend, or '
  'CCManagedMultiHostBackend from package:ccrouter/ccrouter.dart. '
  'ccrouter_go_router is a frozen compatibility package.',
)
library;

export 'src/adapter.dart';
export 'src/app.dart';
export 'src/assembler.dart';
export 'src/backend.dart';
export 'src/modal_pages.dart';
export 'src/multi_host_backend.dart';
export 'src/navigation_observer.dart'
    show
        CCGoRouterNavigationEventKind,
        CCGoRouterNavigationEvent,
        CCGoRouterNavigationEventSnapshot,
        CCGoRouterNavigationObserver;
export 'src/page.dart';
export 'src/route_binding.dart';
export 'src/shell_binding.dart';

/// Re-exports the GoRouter types required to assemble the application-owned
/// router and shell bindings without exposing the entire backend library.
export 'package:go_router/go_router.dart'
    show
        GoRouter,
        GoRoute,
        RouteBase,
        ShellRoute,
        StatefulNavigationShell,
        StatefulShellRoute,
        StatefulShellBranch;
