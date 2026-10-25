# ccrouter

Flutter-facing CCRouter facade for application and component code. Its business
entry point exposes typed navigation, Service/Command/Event access, Session
operations, and page lifecycle integration.
Read-only `CCRouter.diagnosticSnapshot` reports history completeness and external
Sink health. `CCRouter.runtimeHealth` adds payload-free Managed/Backend Entry,
captured Host lifetime, concurrency gate and observer queue counts; these are
point-in-time diagnostics, not navigation handles or proof of a memory leak.
Failure diagnostics preserve attempted Host/Outlet and fixed reason,
attempt and recovery depth; arbitrary business payloads remain excluded.

Business code normally imports:

```dart
import 'package:ccrouter/ccrouter.dart';
```

The application Composition Root imports `ccrouter_host.dart` for
`CCRouterHost.initialize`, `shutdown`, `runInitTasks`, and `CCHostAssembly`.
These lifecycle entry points are absent from the business `CCRouter` facade;
feature components must not initialize or shut down the Runtime. Unmounting a
navigation Host does not shut down the shared Runtime.

Default Page/Dialog routes follow the nearest MaterialApp/CupertinoApp ancestor;
explicit route types take precedence. Optional Android predictive-back Host
wiring observes Flutter-owned animation and Pop. See the
[support and lifecycle guide](../../docs/CCRouter-predictive-back.md) for its
default-off switch, local gates, Theme constraints, and recovery behavior.
For typed cross-component local UI, opt in separately to `ccrouter_ui` and its
[integration guide](../../skills/ccrouter-integration-development/references/ui-fragments.md).

Do not import `ccrouter_core/src/*` or use Runtime internals directly. Use native
`CCManagedRouterApp`, or compose `CCManagedRouterBackend` and
`CCRouterApp.managed` with `MaterialApp.router(routerConfig: backend.routerConfig)`.
The GoRouter compatibility package and attach API have been removed.
`CCManagedRouterApp` is the recommended application path; explicit Backends and
`CCRouterApp.managed` remain advanced Host/test composition. Backend replacement
requires unmount, awaited `CCRouterHost.shutdown`, reinitialization and a fresh
App/Backend. Changing only the Key cannot transfer ownership. Managed and direct
HostBinding aliases are rejected without disposing their current owner, including
reentrant attachment and pending cleanup. See the
[Host ownership guide](../../skills/ccrouter-integration-development/references/implementation-patterns.md)
for failure cleanup, TestHost overlays and cross-Zone shutdown semantics.

Managed completes ordinary Pop results at logical removal and keeps the outgoing
content and Route Scope until Flutter finishes rendering the exit. Exact close
releases business resources promptly, including underneath retained foreign
Popups. Shutdown cancels render waits without requiring another frame.
MultiHost layout selection is forwarded into each Managed Store and remains
authoritative through navigation and focus changes. Both optional backend
bindings belong to the Host SPI, not the business facade.

Renderer unmount releases Route/guard/foreign/lifecycle references without
closing the retained logical Stack, result or Route Service. Remount preserves
managed identities; Widget State and foreign popups follow Flutter lifetime.
Native Back policy uses exact Host/Outlet/Entry identity through optional
Host-only `CCNavigationScopedPopGuardBinding`, retaining legacy binding support.
After folding hides focus, Back can select the sole visible mounted Outlet.

The package is currently pre-release and is not yet published. See the
[workspace README](https://github.com/shingohu/cc-router/blob/main/README.md)
for usage and the
[release checklist](https://github.com/shingohu/cc-router/blob/main/docs/CCRouter-release-readiness.md)
for current publication blockers.
