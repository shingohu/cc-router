# Capability Decisions

Use this guide before selecting an API. Start from the business semantics, not from which API is easiest to call.

## Primary Capability Matrix

| Need | Use | Do not use |
| --- | --- | --- |
| Show a page/modal and optionally return a result | Route | Service or Event as navigation |
| Repeated methods, state reads, owned resource | Service | Command per getter or global singleton |
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

Choose Service for a durable capability such as a repository, account state facade, analytics client, feature configuration, or page controller.

Scope selection:

- `app`: usable without authentication and valid until Runtime shutdown.
- `session`: account-bound state that must be recreated after logout/account switch.
- `route`: tied to one concrete managed RouteEntry, not merely a route ID or visible page.

Use `CCServiceToken<T>` when a contract moves to a stable cross-package boundary. Use `CCServiceKey<T>` for multiple implementations. Use `serviceOrNull` only for a genuinely optional capability.

Do not use a Service as an event bus, a route registry, or a container for arbitrary global mutable state.

## Command

Choose `CCCommand<R>` when exactly one component owns an operation and the caller needs completion, failure, or a typed result. Examples: submit order, request payment, refresh cache, upload file.

Use `CCCommand<void>` when no value is returned. It still retains completion, timeout, cancellation, error, and Trace semantics.

Do not use Command for repeated state queries that belong on a Service. Do not register multiple handlers for one Command.

## Event

Choose `CCEvent` only after a fact is complete. Examples: order paid, account switched, cache invalidated. Publishers must not depend on subscriber count, order, return values, or success.

Subscribers have stable IDs and Runtime lifetime. A subscriber failure is isolated. If the publisher needs one owner to succeed, use Command.

## InitTask

Choose `CCInitializationTask` for one-time Runtime startup work that needs DAG ordering, a Gate, timeout, or critical/optional failure semantics. Examples: privacy-gated analytics startup, loading foundational config, preparing a native SDK.

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
