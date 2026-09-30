# ccrouter_go_router

GoRouter backend integration for CCRouter Hosts. It provides managed and attach
modes, route assembly, observers, Shell/StatefulShell bindings, Outlet support,
and Flutter Page/Route presentation adapters.

Only the application Composition Root should depend on this package. Feature
code continues to navigate through `CCRouter.navigator` and generated typed
Intents; it must not call GoRouter directly for CCRouter-managed destinations.

See the
[workspace README](https://github.com/shingohu/cc-router/blob/main/README.md),
[route design](https://github.com/shingohu/cc-router/blob/main/docs/CCRouter-route-design.md),
and
[release checklist](https://github.com/shingohu/cc-router/blob/main/docs/CCRouter-release-readiness.md).
