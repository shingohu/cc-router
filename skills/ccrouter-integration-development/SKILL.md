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
3. When a production scenario appears unsupported, incomplete, or defective, follow [CCRouter-production-adoption-workflow.md](../../docs/CCRouter-production-adoption-workflow.md) before inventing a workaround or requesting a framework API.
4. Inspect existing generated APIs, the Package's single component definition, contribution registrations, and Host topology. Do not invent APIs from design documents.
5. Implement through the narrowest public CCRouter API. Keep Host SPI out of feature code.
6. Run generation after annotation or component assembly changes. Never edit generated files.
7. Add focused tests for success, failure, lifecycle cleanup, and relevant concurrency.
8. Run analyze, focused tests, and `generate --check` before completion.

For generator, scaffolding, cleanup, source lookup, or deferred Contract
migration work, also read
[`skills/ccrouter-cli-development/SKILL.md`](../ccrouter-cli-development/SKILL.md).
That Skill is authoritative for the command matrix and for the dry-run boundary
when a requested CLI 2.0 command has not been implemented.

If the scenario cannot be expressed safely, report whether it is a framework
defect, application responsibility, developer-experience gap, general reusable
capability, or conditionally deferred work. Do not import internal APIs or
weaken lifecycle, type, failure, or diagnostic semantics to make the feature
appear supported.

For live IDE boundary feedback, use the optional `ccrouter_analyzer_plugin`.
It reports only deterministic single-file diagnostics and never runs generation,
rewrites imports, or replaces `ccrouter generate --check`. Treat generated Dart
APIs as the source of completion and auto-import behavior, `ccrouter find` and
Catalog metadata as the source of location lookup, and the CLI/Workspace
Validator as the final authority. Follow
[`references/ide-analysis-server.md`](references/ide-analysis-server.md) for
setup, version isolation, and fallback behavior.

Read [implementation-patterns.md](references/implementation-patterns.md) when adding or changing code. Read [review-checklist.md](references/review-checklist.md) when reviewing, migrating, or validating a feature.

## Non-Negotiable Boundaries

- Navigate CCRouter-managed destinations only through `CCRouter.navigator`.
- Use a generated typed Intent for a statically known destination. Use `CCRouter.navigator.open` only for an application-controlled dynamic URI.
- Route platform links, notification URIs, and scanned values through `CCDeepLinkIngress`; never treat them as internal `open` calls.
- Do not call `Navigator.push/pop`, `GoRouter.push/go`, or an Adapter for a CCRouter-managed page.
- Local Flutter Dialog, BottomSheet, Menu, and Overlay may use Flutter APIs when they do not need a cross-component contract, typed result, Interceptor, Trace, or Route Scope.
- Do not import `ccrouter_core/src/*`, `ccrouter_host.dart`, Adapter types, generated binding/package/host files, or another component's page implementation from feature code.
- Import a component's generated `<componentId>.api.g.dart` stable barrel for its typed Route,
  Service Proxy, Command, and Event APIs. Do not import the underlying
  `ccrouter_generated/component/*_api.g.dart` files; they are generator/Host SPI.
- Do not access `CCRouterRuntime`, `CCScope`, mutable Route Entries, Registry internals, or framework disposal entry points.
- Do not manually dispose framework-owned Service instances, Route Scopes, Adapters, or Sessions.
- Do not edit anything under `lib/src/ccrouter_generated/`.
- Do not add a generated `part` to a page, Service, component definition, or contribution. Generated libraries are standalone files assembled by the generator.
- Keep an internal route on `@CCRoute`. Promote it to `@CCRouteContract` only when a real external component consumer appears.
- Use `@CCExtraParam` only for typed, process-local, short-lived objects. Generated page bindings preserve the declared static type and reject a mismatched runtime object with `CCRouteParameterError`; Extra is not a Deep Link, restoration, persistence, or cross-process channel.
- Put stable cross-component contracts in a Pure Dart contracts package. Consumers depend on the contracts package, not the implementation package.
- Do not simulate unsupported Action Pipeline, dynamic component activation/deactivation, complete state restoration, or Navigator 1.0 Backend. Generated Command/Event/InitTask capabilities and Service Proxies support only their documented declaration and dependency models.
- Use `@CCEventContract` plus public top-level `@CCEventSubscription` functions for static component Events, and publish annotated Events only through the generated Owner Client. Omit a Subscriber ID only when the component has exactly one Subscriber for that Event. Keep `CCEventSubscriberId<E>`, `CCEventSubscriber<E>`, and the legacy string overload for unannotated migration capabilities and low-level tests.
- Connect application logging through `CCDiagnosticsConfig(sink: ...)`. A `CCDiagnosticSink` is asynchronous, bounded, observational, and failure-isolated. Category policies control external delivery and sampling only; they do not disable Runtime traces or lifecycle state. Forward only the sanitized fields supplied by `CCDiagnosticEvent` and never append raw URI, arguments, Extra, tokens, widgets, backend objects, exception messages, or business results.
- Treat `componentGraph`, `componentRegistration`, and `runtimeInitialize` as the framework-owned component/startup diagnostic flow. Configure the Host Sink at `CCRouter.initialize` with `CCDiagnosticLevel.debug` when start events are needed; do not duplicate these lifecycle logs in application bootstrap code.
- Use `ccrouter_analytics` for provider-neutral product events. Route page view/leave events may be bridged from `CCNavigationAspect`; click, scroll, and exposure events require stable explicit targets. Keep Firebase, ThinkingData, local persistence, and upload adapters in the application layer (the Demo example lives under `demo/modules/`); do not add vendor SDK dependencies to framework `packages/*`, and do not infer business event IDs from Widget text or arbitrary Keys.
- Keep the analytics dispatcher behind an explicit `CCAnalyticsPolicy`: its default is consent-denied, and the app must call `updatePolicy` after privacy consent. Sampling and consent filtering happen before queueing; revocation clears pending events, while already-running sink writes cannot be retracted.
- Use `ccrouter_analytics_flutter` only when the app opts in to explicit `CCAnalyticsScrollable` or `CCAnalyticsExposureTarget` wrappers. Configure exposure thresholds deliberately; do not treat the approximation as ad verification or a security signal.
- Use `ccrouter_devtools` only for an application-owned debug route, drawer, or local overlay. The `CCRouterDevToolsPanel` is read-only and must not be used as a navigation, retry, scope disposal, component activation, or Adapter control surface.
- Tooling that crosses the Flutter application boundary must use the versioned
  `ccrouter_devtools_protocol` snapshots. Do not serialize Runtime, Navigator,
  Widget, route arguments, complete URIs, Tokens, or business results.
- For the official DevTools Extension, register
  `CCDevToolsServiceExtension` only from a debug Host composition root. Build
  `devtools/ccrouter_extension` with a stable Flutter Web SDK; the OHOS SDK is
  not a valid Web Extension test target. The Extension is read-only and must
  tolerate a missing Runtime endpoint without changing application behavior.
- When a generated or application-owned static Catalog is available, pass it to
  `CCRouterDevToolsSnapshotProvider(catalog: ...)` and
  `CCDevToolsServiceExtension.register(catalog: ...)`. The Catalog is joined to
  Runtime entries and trace edges by stable IDs; missing Catalog records are
  shown as unresolved rather than inferred. Source locations are copyable
  `package:` references. An IDE opener may be supplied through the panel's
  `onOpenSource` callback, but the framework never assumes an editor or local
  filesystem mapping.
- Enable `ccrouter_analyzer_plugin` only through the host Package's Analysis Server bootstrap. Keep its Analyzer dependency isolated from the application Workspace; do not add a path dependency to the rule Package when the Analysis Server will copy the bootstrap to a temporary directory. Pin unreleased Git bootstraps to a reviewed commit and use the isolated loader `analyze/compile` smoke; switch to the provided Hosted manifest only after publication. If the plugin is unavailable or incompatible, disable the bootstrap and keep Dart Analyzer plus `ccrouter generate --check` as the authoritative gates.
- Keep analytics separate from diagnostics: `CCDiagnosticEvent` explains framework execution and failure, while `CCAnalyticsEvent` represents a product behavior. Analytics properties must use validated primitive values and must not contain credentials, full URI values, Widgets, exceptions, or business objects. Analytics Sink failures and queue pressure must never alter navigation or component results.
- The analytics dispatcher exposes only payload-free pressure counters (`acceptedEventCount`, `pendingEventCount`, `peakQueueDepth`, and `droppedEventCount`) for bounded health/performance checks. They are not an audit log, replay source, or permission to inspect queued events; use the standalone benchmark when comparing SDK/platform behavior.
- Use `CCRouter.traceBundle(traceId)` for bounded local troubleshooting across nested calls. It is not an audit log, replay source, or business Event store; records may be incomplete after capacity rotation.
- When using generated Host assembly, pass both `componentManifests` and the
  read-only `contractBundle` to `CCRouter.initialize`. Never hand-write
  Contract versions or fingerprints. Generation and Host/Runtime boundaries
  reject missing, owner-mismatched, out-of-range, fingerprint-drifted,
  duplicate, or stale Contract artifacts with stable compatibility codes.

### Read-only DevTools

- Use the optional `ccrouter_devtools` package only for a Host-owned debug or
  internal diagnostics surface. `CCRouterDevToolsPanel` consumes immutable,
  bounded snapshots and existing observation listeners.
- Do not add navigation, Pop, retry, Scope disposal, component activation, or
  Adapter controls to the panel. Those operations would violate the Runtime
  ownership boundary and make a visualizer part of the business API.
- Keep the panel behind an application debug/build gate. It is not an audit
  log, replay source, or production telemetry transport; use
  `CCDiagnosticsConfig` for application logging.
- Preserve the sanitized data boundary: no full URI, Path/Query values, Extra,
  Token, Widget, Navigator, backend Route object, exception message, or business
  result may be added to the view. See
  `references/devtools.md` for the integration pattern.

## Decision Rules

- Use **Route** for showing a destination and optionally receiving a typed Pop result.
- Use **Service** for repeatable methods, state reads, or lifecycle-owned resources.
- Use **Command<R>** for one requested operation with exactly one owner; use `R = void` when only completion matters.
- Use **Event** for an already completed fact delivered to zero or more independent subscribers.
- Use **InitTask** for one Runtime-lifetime startup task with dependencies or an explicit Gate.
- Do not create a new public framework abstraction when these capabilities already express the behavior.

For namespace-aware key-value storage, use a Service with an explicit namespace value
object and typed primitive/JSON methods. Keep global, guest, user, API-environment,
and hardware namespaces distinct; the same key in two namespaces must not alias.
Treat a namespace as an isolation and lifecycle selector, not as encryption or an
authorization boundary. Keep the persistence/secure-storage implementation behind a
Backend SPI and inject it from the Host or component Composition Root. A memory Fake
is appropriate for Pure Dart and Widget tests; do not expose a vendor storage type in
the Service Contract.

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
- Call and await `CCRouter.shutdown` only when the owning application
  Composition Root ends the default Runtime. Page, component, Session,
  application-background, and individual navigation Host lifecycles must not
  call it. Reinitialize only after the shutdown Future completes.
- Select the narrowest Service Scope: app, session, or route.
- Prefer singleton; use `newInstance` only for stateless or immutable helpers whose ownership remains safe.
- Use async Service readiness only when callers cannot safely use the instance immediately after synchronous construction.
- Use `@CCService` only for a public concrete non-generic class with an unnamed zero-argument generative constructor. A promoted implementation must directly implement exactly one `@CCServiceContract`; do not pass or export a Service Token from business code. Use `@CCCommandContract` plus a public top-level `@CCCommandHandler` for generated Commands. Use `@CCEventContract` plus public top-level `@CCEventSubscription` functions for static Events. Use `CCInitTaskContract` plus a public top-level `@CCInitTask` function for generated initialization tasks. Use `@CCComponentContribution` for custom factories, constructor injection, async Service initializers, unannotated migration capabilities, Shell, and policy registration.
- Keep InitTask dependency targets as top-level `const CCInitTaskContract` values. Set exactly one of `contract` and `id`; use `id` only for an independent component-internal task. Always declare `gate` and `failurePolicy` explicitly; ordinary startup uses `CCInitTaskGate.appStarted`, while generated CLI scaffolds merely write that value for you rather than relying on a framework default. Cross-component task dependencies require a public contracts-Package barrel and a required dependency on the task Owner. Call `CCRouter.runInitTasks(gate: ...)` with an explicit Gate from the Host, never invoke generated task bridges from business code.
- Declare every cross-component Service consumer in the consuming component's `serviceDependencies`, keep the owner in required `dependencies`, and call the generated `<Component>Services` member. Do not scan Package dependencies, handwrite a Proxy, pass caller IDs, or use a generated Client for a component-local Service.
- Put a shared generated member name on `CCServiceContract.alias` or
  `CCCommandContract.alias`; use the matching Dependency alias only for a
  consumer-specific override or keyed Service. The deterministic priority is
  Dependency alias, Contract alias, then type-name inference. Do not introduce
  a global namespace Facade that hides the consuming component's caller identity.
- Treat generated Service, Command, and Event bridges as framework SPI, not an authorization bypass. Runtime revalidates installed component identities and required/optional dependency edges; stale generation or a handwritten bridge call must fail with `CCResolutionError` before business work executes.
- Concurrent InitTask Gate opens share one single-flight drain. Code may open a later Gate while another drain is active; do not add polling or a second task runner, because Runtime continues until the newly ready DAG is quiescent.
- Keep a `@CCServiceContract` interface itself non-generic. Its methods may use method-owned generic parameters with public Pure Dart bounds; generated Proxies preserve bounds, nullability, and explicit type arguments. Do not use method generics to pass Flutter objects, callbacks, Streams, or private implementation types across a component boundary.

## Generated Code and Validation

For a new component or internal page, the generator CLI provides non-overwriting
templates:

```bash
fvm dart run ccrouter_generator:ccrouter create component <package-name> <parent-directory>
fvm dart run ccrouter_generator:ccrouter create page <PageName> <component-directory>
fvm dart run ccrouter_generator:ccrouter create service <ServiceName> <component-directory>
fvm dart run ccrouter_generator:ccrouter create command <CommandName> <component-directory>
fvm dart run ccrouter_generator:ccrouter create event <EventName> <component-directory>
fvm dart run ccrouter_generator:ccrouter create init-task <TaskName> <component-directory>
```

The scaffold only creates authored source and refuses to replace existing files.
Run `pub get` and `generate` afterwards. It creates an internal `@CCRoute` page;
promoting that page to a cross-component Contract remains an explicit design step.

After Route, Service, Command, Event, or InitTask annotation, component definition, contribution, or dependency changes, run from the workspace root:

```bash
fvm dart run ccrouter_generator:ccrouter generate <host-root>
```

The repository Workspace root is an aggregator rather than a Host. Until the
documented Pub Hook host-detection defect is fixed, run hooked `flutter pub`
commands from the actual Host directory (for this repository, `demo/`). For
root-only dependency resolution, set `CCROUTER_PUB_HOOK_DISABLE=1` and run the
explicit Host `generate --check` afterwards. Do not describe a successful Pub
operation followed by a Hook failure as dependency-resolution failure.

Validate with:

```bash
fvm dart analyze
fvm flutter test <focused-test-target>
fvm dart run ccrouter_generator:ccrouter generate <host-root> --check
```

Use `ccrouter find <capability-id-or-route-pattern> <host-root>` to locate a generated Route, Service, Command, Event, or InitTask instead of scanning or guessing. Route declarations additionally support Pattern lookup. Normal generation may use an exact-content fast path only when authored inputs, tool identity, Package graph, external indexes, and every managed output match the last successful manifest. Use `--no-cache` as the authoritative reference-path check and `--profile` only for generation performance diagnosis; never delete caches or touch files merely to force an ordinary generation run.

## Completion Standard

- Confirm the feature uses the correct capability and dependency direction.
- Confirm all navigation paths use generated Intent or controlled dynamic URI APIs.
- Confirm failure, cancellation, result typing, and disposal behavior are tested where relevant.
- Confirm no generated output was manually changed.
- Confirm no new public API or cross-component dependency was introduced without a real consumer.
- Report unsupported requirements explicitly instead of implementing a semantically weaker workaround.
