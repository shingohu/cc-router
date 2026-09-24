---
name: ccrouter-integration-development
description: Implement, migrate, or review Flutter application and component features that integrate with CCRouter. Use when work involves component boundaries, generated route intents, CCRouter.navigator, Service scopes, Command, Event, InitTask, Deep Link, Interceptor, PopGuard, navigation Aspect, page lifecycle, Host/Outlet, or CCRouter-generated files. Do not use for changing CCRouter framework internals under packages/*/lib; use the framework-development skill for that work.
---

# CCRouter Integration Development

Use CCRouter as the application component boundary. Prefer its generated contracts and lifecycle ownership over direct navigation, global service locators, or ad hoc cross-package imports.

## Workflow

1. Identify the current package role before editing:
   - **Host**: application composition root, Backend, Shell, platform ingress.
   - **Component implementation**: pages, private capabilities, Registrar.
   - **Contracts package**: Pure Dart cross-component Route or Service contracts.
2. Classify the requested behavior with [capability-decisions.md](references/capability-decisions.md).
3. Inspect existing generated APIs, Registrar patterns, component descriptor, and Host topology. Do not invent APIs from design documents.
4. Implement through the narrowest public CCRouter API. Keep Host SPI out of feature code.
5. Run generation after annotation or component assembly changes. Never edit generated files.
6. Add focused tests for success, failure, lifecycle cleanup, and relevant concurrency.
7. Run analyze, focused tests, and `generate --check` before completion.

Read [implementation-patterns.md](references/implementation-patterns.md) when adding or changing code. Read [review-checklist.md](references/review-checklist.md) when reviewing, migrating, or validating a feature.

## Non-Negotiable Boundaries

- Navigate CCRouter-managed destinations only through `CCRouter.navigator`.
- Use a generated typed Intent for a statically known destination. Use `CCRouter.navigator.open` only for an application-controlled dynamic URI.
- Route platform links, notification URIs, and scanned values through `CCDeepLinkIngress`; never treat them as internal `open` calls.
- Do not call `Navigator.push/pop`, `GoRouter.push/go`, or an Adapter for a CCRouter-managed page.
- Local Flutter Dialog, BottomSheet, Menu, and Overlay may use Flutter APIs when they do not need a cross-component contract, typed result, Interceptor, Trace, or Route Scope.
- Do not import `ccrouter_core/src/*`, `ccrouter_host.dart`, Adapter types, generated binding/package/host files, or another component's page implementation from feature code.
- Do not access `CCRouterRuntime`, `CCScope`, mutable Route Entries, Registry internals, or framework disposal entry points.
- Do not manually dispose framework-owned Service instances, Route Scopes, Adapters, or Sessions.
- Do not edit anything under `lib/src/ccrouter_generated/`.
- Do not add a generated route `part` to a page. Only the Registrar keeps its generated `.component.g.dart` part.
- Keep an internal route on `@CCRoute`. Promote it to `@CCRouteContract` only when a real external component consumer appears.
- Put stable cross-component contracts in a Pure Dart contracts package. Consumers depend on the contracts package, not the implementation package.
- Do not simulate unsupported Action Pipeline, dynamic component activation/deactivation, complete state restoration, Navigator 1.0 Backend, or Service/Command/Event annotations.
- Use `CCEventSubscriberId<E>` and `CCEventSubscriber<E>` for new Event registrations. The ID identifies one subscriber, not the Event type; keep it stable and unique across the Runtime. The legacy string overload is only for existing 1.x registrars and low-level tests.
- Connect application logging through `CCDiagnosticsConfig(sink: ...)`. A `CCDiagnosticSink` is asynchronous, bounded, observational, and failure-isolated. Category policies control external delivery and sampling only; they do not disable Runtime traces or lifecycle state. Forward only the sanitized fields supplied by `CCDiagnosticEvent` and never append raw URI, arguments, Extra, tokens, widgets, backend objects, exception messages, or business results.
- Use `ccrouter_analytics` for provider-neutral product events. Route page view/leave events may be bridged from `CCNavigationAspect`; click, scroll, and exposure events require stable explicit targets. Do not add Firebase, ThinkingData, or other vendor SDK dependencies to Core, and do not infer business event IDs from Widget text or arbitrary Keys.
- Keep analytics separate from diagnostics: `CCDiagnosticEvent` explains framework execution and failure, while `CCAnalyticsEvent` represents a product behavior. Analytics properties must use validated primitive values and must not contain credentials, full URI values, Widgets, exceptions, or business objects. Analytics Sink failures and queue pressure must never alter navigation or component results.
- Use `CCRouter.traceBundle(traceId)` for bounded local troubleshooting across nested calls. It is not an audit log, replay source, or business Event store; records may be incomplete after capacity rotation.

## Decision Rules

- Use **Route** for showing a destination and optionally receiving a typed Pop result.
- Use **Service** for repeatable methods, state reads, or lifecycle-owned resources.
- Use **Command<R>** for one requested operation with exactly one owner; use `R = void` when only completion matters.
- Use **Event** for an already completed fact delivered to zero or more independent subscribers.
- Use **InitTask** for one Runtime-lifetime startup task with dependencies or an explicit Gate.
- Do not create a new public framework abstraction when these capabilities already express the behavior.

## Navigation Policy Rules

- Use Interceptor only for pre-navigation decisions: authentication, permission, consent, maintenance, forced upgrade, feature flag, redirect, cancel, or defer.
- Never use Interceptor for PV/UV, page arrival, data loading, UI side effects, or nested navigation.
- Use PopGuard only for synchronous, in-memory exit decisions. Use Flutter `PopScope` for confirmation UI or asynchronous work.
- Use `CCNavigationAspect` only for observation and sanitized telemetry. It must not change navigation decisions or synchronously re-enter navigation.
- Use `CCPageLifecycleMixin` or `CCPageLifecycleListener` for PageShow/PageHide and application foreground/background observation. Use Flutter `initState/dispose` for Widget lifetime.
- Use Route Service for page-instance resources that must survive PageHide and be disposed only after the exact managed RouteEntry is removed.
- Pass `BuildContext` to navigator calls only when call-site Host/Outlet resolution is required. Do not store it globally.

## Lifecycle Rules

- `CCRouter.initialize` receives the complete startup component set once.
- Open a Session after login or persisted authentication restoration. Close it on logout, token invalidation, account switch, or forced sign-out.
- Do not close a Session on page Pop, backgrounding, or tab changes.
- Call `CCRouter.shutdown` only when the owning application/test Runtime ends.
- Select the narrowest Service Scope: app, session, or route.
- Prefer singleton; use factory only for stateless/immutable helpers whose ownership remains safe.
- Use async Service readiness only when callers cannot safely use the instance immediately after synchronous construction.

## Generated Code and Validation

After route annotation, descriptor, Registrar, or dependency changes, run from the workspace root:

```bash
fvm dart run ccrouter_generator:ccrouter generate <host-root>
```

Validate with:

```bash
fvm dart analyze
fvm flutter test <focused-test-target>
fvm dart run ccrouter_generator:ccrouter generate <host-root> --check
```

Use `ccrouter find <route-id-or-pattern> <host-root>` to locate a generated route instead of scanning or guessing. Use `--no-cache` only as a reference-path check and `--profile` only for generation performance diagnosis.

## Completion Standard

- Confirm the feature uses the correct capability and dependency direction.
- Confirm all navigation paths use generated Intent or controlled dynamic URI APIs.
- Confirm failure, cancellation, result typing, and disposal behavior are tested where relevant.
- Confirm no generated output was manually changed.
- Confirm no new public API or cross-component dependency was introduced without a real consumer.
- Report unsupported requirements explicitly instead of implementing a semantically weaker workaround.
