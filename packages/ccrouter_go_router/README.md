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
automatically. Initialize, run startup Gates, and shut down the default Runtime
only through `CCRouterHost` from `ccrouter_host.dart`; unmounting the navigation
Host does not shut down the shared Runtime.
An application tree with multiple independent Router surfaces
may use `CCGoRouterMultiHostBackend.managed`, whose Host factories receive that
Catalog and their declared Host ID. The aggregate does not choose a layout or
provide native platform-window lifecycle integration. Tabs, Shell branches,
and master-detail panes normally remain Outlets of one Host.

`enablePredictiveBack` defaults to false and preserves existing Route types and
Flutter back handling. When enabled, managed generated default Android Material
pages connect automatically to the Adapter-owned phase bridge; Flutter alone
executes Pop. Attached/custom/Shell Page builders explicitly pass
`adapter.predictiveBackBridge` as `predictiveBackHandler`. Guard, modal, local
history and custom-transition fallback remain unchanged. Do not manually forward
phases for automatically wired Routes. A closed local gate at commit or a
navigation change cancels the original preview without a second Pop. Ancestor
Navigator popups protect covered nested pages, including transient coverage
during a gesture. After attached Adapter disposal, old gestures remain invalid
and new gestures on the surviving Router resume Flutter handling.
Reading `Route.popGestureEnabled` preserves the old commit fence. If the platform
loses the old terminal callback, the next start first cancels that preview before
detaching the retired handler and starting a new Flutter gesture.
Changing to an unsupported Theme platform/transition during a preview cancels
the animation and releases Navigator gesture state without completing a result
or disposing a Route Scope; restoring the Theme does not revive the old preview.
Declined starts are exposed through the bounded, sanitized
`adapter.predictiveBackFallbacks` Host diagnostic. It shares
`lifecycleEventCapacity`; the disabled path allocates no fallback history.
Adapter registration is rolled back atomically if construction fails, and a
throwing custom handler lifetime probe relinquishes an idle Route to Flutter;
an in-flight sequence keeps its original commit protection until it ends.

See the [support and verification guide](../../docs/CCRouter-predictive-back.md)
for Theme requirements, lifecycle semantics and platform limitations.

See the
[workspace README](https://github.com/shingohu/cc-router/blob/main/README.md),
[route design](https://github.com/shingohu/cc-router/blob/main/docs/CCRouter-route-design.md),
and
[release checklist](https://github.com/shingohu/cc-router/blob/main/docs/CCRouter-release-readiness.md).
