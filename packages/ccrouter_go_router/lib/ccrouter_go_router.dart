/// GoRouter integration for the adapter-neutral CCRouter navigation SPI.
library;

export 'src/adapter.dart';
export 'src/assembler.dart';
export 'src/backend.dart';
export 'src/modal_pages.dart';
export 'src/navigation_observer.dart';
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
