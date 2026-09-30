# ccrouter_go_router

GoRouter backend integration for CCRouter Hosts. It provides managed and attach
modes, route assembly, observers, Shell/StatefulShell bindings, Outlet support,
Flutter Page/Route presentation adapters, and managed aggregation for multiple
independent Router Hosts.

Only the application Composition Root should depend on this package. Feature
code continues to navigate through `CCRouter.navigator` and generated typed
Intents; it must not call GoRouter directly for CCRouter-managed destinations.

New single-Host applications initialize CCRouter with their generated Host
Assembly and mount `CCGoRouterApp()`; the widget resolves the same Route Catalog
automatically. An application tree with multiple independent Router surfaces
may use `CCGoRouterMultiHostBackend.managed`, whose Host factories receive that
Catalog and their declared Host ID. The aggregate does not choose a layout or
provide native platform-window lifecycle integration. Tabs, Shell branches,
and master-detail panes normally remain Outlets of one Host.

See the
[workspace README](https://github.com/shingohu/cc-router/blob/main/README.md),
[route design](https://github.com/shingohu/cc-router/blob/main/docs/CCRouter-route-design.md),
and
[release checklist](https://github.com/shingohu/cc-router/blob/main/docs/CCRouter-release-readiness.md).
