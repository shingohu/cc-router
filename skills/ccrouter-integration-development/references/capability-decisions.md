# Capability Decisions

Use this guide before selecting an API. Start from the business semantics, not from which API is easiest to call.

## Before Selecting a Framework Capability

A capability can expose an ordinary narrow Client/interface when its Owner,
construction, lifetime and dependency direction are already explicit. A second
consumer or a native plugin does not itself require a CCRouter Service or a new
contracts Package. Use Service when framework Scope, asynchronous readiness,
resolution or generated cross-component dependency validation adds needed
semantics. Plain calls do not receive those checks, tracing or cancellation
semantics automatically; the component must own them where needed.

Likewise, a local operation can remain a method or injected callback. Choose
Command only when its single-owner dispatch/result semantics are needed, and
Event only for independent fact subscribers. Do not use ordinary APIs to bypass
an already selected managed Route, Service or message contract.

## Primary Capability Matrix

| Need | Use | Do not use |
| --- | --- | --- |
| Show a page/modal and optionally return a result | Route | Service or Event as navigation |
| Repeated methods, state reads, owned resource | Narrow Client; Service when framework Scope/readiness/resolution is needed | Command per getter or unowned global state |
| Typed local data with explicit account/environment/device isolation | Owning storage API + namespace value object; Service if framework-managed | Unscoped global Map or EventBus |
| Ask one owner to perform work | Command | Event when success matters |
| Announce a fact after it happened | Event | Command fan-out |
| Run startup work once with dependencies | InitTask | Page lifecycle callback |
| Decide whether navigation may proceed | Interceptor | Aspect or page callback |
| Decide whether current route may leave | PopGuard/`PopScope` | Navigation Interceptor |
| Observe navigation timing/outcome | Aspect/diagnostic listener | Interceptor |
| Observe current PageRoute and app foreground | Page lifecycle | Service ownership |

## Route

Choose Route when the user enters a destination. Prefer a generated Intent because it statically owns arguments and result type.

Use an internal `@CCRoute` when only the owning component calls the route. Promote to `@CCRouteContract` when another component needs it. Preserve route ID, wire parameter names, result type, and URI semantics during promotion.

Use a CCRouter Dialog or BottomSheet Route only when it needs one or more of:

- cross-component invocation;
- generated parameters or typed result;
- Interceptor or Deep Link policy;
- Trace/Aspect attribution;
- Route Scope and exact disposal.

For local confirmation, menus, transient BottomSheet, `OverlayEntry`, `MenuAnchor`, or a third-party popup, use the native Flutter/package API. Treat it as foreign UI and do not register a fake route.

## Service

跨 Package 的 Route、Service、Command、Event、InitTask Contract 都要维护独立的 SemVer。
生成 metadata 会携带确定性的 `shapeFingerprint`；公共形状改变时应升级 Contract 版本，破坏性
变更优先使用新 Contract ID，不要用组件版本或运行时字符串猜测兼容性。
生成的 Host Assembly 同时携带 Contract descriptor 和消费者的精确版本/指纹要求；Host 启动时
将完整 Assembly 通过 `CCRouterHost.initialize(hostAssembly: ...)` 传入，不单独传 `contractBundle`
或 components，由 Generator、Host 和 Runtime 分层拒绝缺失、
Owner 不匹配、版本范围不满足、指纹漂移、重复实现和陈旧生成物。业务不手写这些字符串。

Choose Service for a durable capability that needs the framework semantics above. A repository, account facade, analytics client or page controller is not automatically a Service merely because of its name.

Scope selection:

- `app`: usable without authentication and valid until Runtime shutdown.
- `session`: account-bound state that must be recreated after logout/account switch.
- `route`: tied to one concrete managed RouteEntry, not merely a route ID or visible page.

When a framework-managed Service moves across Packages, declare `@CCServiceContract` in a Pure Dart contracts Package and let the implementation bind it automatically. Each consuming component adds an exact `CCServiceDependency<T>` and calls its generated `<Component>Services` Client; stable Token, caller identity and method ID plumbing belongs to generated code. Keep `CCRouter.service<T>()` for component-internal lookup. Use `CCServiceKey<T>` for multiple implementations and `serviceOrNull` only for a genuinely optional local capability.

Use a Contract alias when every consumer should see the same generated Client
member. Use a Dependency alias only for a keyed implementation or local naming
override. Do not create a global Service namespace that hides which component
made the call.

Do not use a Service as an event bus, a route registry, or a container for arbitrary global mutable state.

## Command

Choose `CCCommand<R>` when exactly one component owns an operation and the caller needs completion, failure, or a typed result. Examples: submit order, request payment, refresh cache, upload file.

Use `CCCommand<void>` when no value is returned. It still retains completion, timeout, cancellation, error, and Trace semantics.

Do not use Command for repeated state queries that belong on a Service. Do not register multiple handlers for one Command.

## Event

Choose `CCEvent` only after a fact is complete. Examples: order paid, account switched, cache invalidated. Publishers must not depend on subscriber count, order, return values, or success.

Subscribers have stable typed IDs (`CCEventSubscriberId<E>`) and Runtime lifetime. The ID identifies the subscriber, not the Event type, so multiple subscribers of one Event use different IDs. A subscriber failure is isolated. If the publisher needs one owner to succeed, use Command. Bridge framework observations to application logs with `CCDiagnosticsConfig` and a Host-owned `CCDiagnosticSink`; keep raw payloads out of the sink and use `traceBundle` only for bounded troubleshooting.

## InitTask

Choose `@CCInitTask` for one-time Runtime startup work that needs DAG ordering, a Gate, timeout, or explicit required/optional failure classification. Use a `CCInitTaskContract` when another task references it; keep handwritten `CCInitTaskDefinition` for unannotated migration or low-level registration. Examples: privacy-gated analytics startup, loading foundational config, preparing a native SDK. The declaration and `CCRouterHost.runInitTasks(gate: ...)` both require an explicit Gate; `appStarted` is a common value, not an API default. Task business failures are returned in `CCInitTaskRunResult`; only a Composition Root that cannot degrade should call `throwIfRequiredFailed()`.

Do not use InitTask for every Service's normal construction, repeatable refresh work, page entry work, or work that must rerun for each Session. Use Service initializer for lazy instance readiness and Command for repeatable operations.

## Policy and Observation

### Interceptor

Use for authorization and navigation policy before backend mutation. Allowed outcomes are proceed, cancel, redirect, and defer. Keep it deterministic, cancellable, bounded by timeout, and free of UI/navigation re-entry.

### PopGuard

Use for synchronous route exit rules. It may inspect current in-memory state. It must not display a Dialog or await I/O. Put asynchronous confirmation UI in `PopScope`, then explicitly call the navigator after confirmation.

### Aspect

Use for found/arrival/completion/failure observation, latency and sanitized attribution. Aspect exceptions must not change navigation. Never include full URI, arguments, Extra, tokens, or business result objects in telemetry.

### Page Lifecycle

Use `PageShow/PageHide` to observe whether a PageRoute is current in an active Outlet. It is not pixel visibility and not Widget creation/destruction. Use foreground/background only for app lifecycle observation. Do not own/dispose resources from these callbacks.

### Development Diagnostics

Use `CCRouterDevToolsPanel` from `ccrouter_devtools` only in an application-owned
debug page, drawer, or local overlay. It consumes immutable, bounded snapshots and
must remain observational: do not add buttons that navigate, retry, activate a
component, dispose a Scope, or control an Adapter through the panel.

Use `ccrouter_analyzer_plugin` for editor-time boundary and generated-output
diagnostics. Its Analysis Server bootstrap is resolved in an isolated dependency
environment; keep Analyzer versions separate from the Workspace generator and
use `generate --check` as the authoritative build gate. The plugin never writes
generated files or replaces a Contract/Generator validation.
