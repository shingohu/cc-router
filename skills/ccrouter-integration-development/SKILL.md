---
name: ccrouter-integration-development
description: Implement, migrate, or review Flutter application and component features that integrate with CCRouter. Use when work involves component boundaries, generated route intents, CCRouter.navigator, Service scopes, Command, Event, InitTask, Deep Link, Interceptor, PopGuard, navigation Aspect, page lifecycle, Host/Outlet, or CCRouter-generated files. Do not use for changing CCRouter framework internals under packages/*/lib; use the framework-development skill for that work.
---

# CCRouter Integration Development

Use CCRouter as the application component boundary. Prefer its generated contracts and lifecycle ownership over direct navigation, global service locators, or ad hoc cross-package imports.

This Skill and the sibling `ccrouter-cli-development` directory form one
installation bundle. Keep both complete directories together, including their
references. Required guidance is bundled; framework design links are optional
background and do not require a checkout of the framework repository. Use the
application's installed package APIs and CLI help if its version differs.

## Workflow

1. Identify the current package role before editing:
   - **Host**: application composition root, Backend, Shell, platform ingress.
   - **Component implementation**: pages, private capabilities, Registrar.
   - **Contracts package**: Pure Dart cross-component Route or Service contracts.
2. Classify the requested behavior with [capability-decisions.md](references/capability-decisions.md).
3. When a production scenario appears unsupported, incomplete, or defective, use the bundled [production scenario assessment](references/production-scenarios.md) before inventing a workaround or requesting a framework API.
4. Inspect existing generated APIs, the Package's single component definition, contribution registrations, and Host topology. Do not invent APIs from design documents.
5. Implement through the narrowest public CCRouter API. Keep Host SPI out of feature code.
6. Run generation after annotation or component assembly changes. Never edit generated files.
7. Add focused tests for success, failure, lifecycle cleanup, and relevant concurrency.
8. Run analyze, focused tests, and `generate --check` before completion.

Commit generated output together with its Portable Generation State only when
the Package explicitly opts into distribution with `ccrouter.yaml`
`generation: { portable: true }`. Generate that state through
`ccrouter portable prepare <host-root>` and validate readiness with
`ccrouter portable publish <host-root>`; ordinary local `generate` maintains
only disposable `.dart_tool` planning state. A read-only declared Package with
missing or stale state fails closed, while an unproven writable Package falls
back to the full Builder path. Never treat the publish command as authorization
to contact Pub or Git.
distributing components. A cache hit must verify external source, dependency,
and managed-output content; it does not excuse stale Git/Path artifacts.
See the generation section in `references/implementation-patterns.md`.
Custom catalog directories retain the same `--check` file-restoration guarantee;
they do not transfer ownership of neighboring application files to the CLI.
Route and Service Proxy defaults preserve collection types; expose any enum or
type used only inside a default through the same public Contract barrel.
Descriptions are literal text, including dollar signs and newlines; do not
pre-escape business descriptions for generated Host DevTools Dart output.
Dependency preflight follows proven Library import/export visibility. Same-Package
unimported declarations do not establish ownership; conditional/part/unknown
namespaces defer to the authoritative Builder instead of guessing.
Analyzer diagnostics and annotation Quick Fixes require framework declaration
identity. A foreign same-name annotation is ignored; unresolved ambiguous imports
wait for semantic resolution rather than offering speculative edits.

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
It reports deterministic source diagnostics and uses the current Analysis Server
session on demand for Handler/Owner/Service type proofs. It never runs generation,
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
- Re-export generated Route contracts from the Package's stable
  `src/ccrouter_generated/<package>.contracts.api.g.dart` entry with an explicit
  `show` list. Do not bind authored public barrels to individual
  `contract/*.route.contract.g.dart` files. Continue to export authored Service,
  Command, Event, and InitTask declarations explicitly; the generated entry does
  not decide that public surface.
- Do not simulate unsupported Action Pipeline, dynamic component activation/deactivation, complete state restoration, or Navigator 1.0 Backend. Generated Command/Event/InitTask capabilities and Service Proxies support only their documented declaration and dependency models.
- Use `@CCEventContract` plus public top-level `@CCEventSubscription` functions for static component Events, and publish annotated Events only through the generated Owner Client. Omit a Subscriber ID only when the component has exactly one Subscriber for that Event. Keep `CCEventSubscriberId<E>`, `CCEventSubscriber<E>`, and the legacy string overload for unannotated migration capabilities and low-level tests.
- Connect application logging through `CCDiagnosticsConfig(sink: ...)`. A `CCDiagnosticSink` is asynchronous, bounded, observational, and failure-isolated. Category policies control external delivery and sampling only; they do not disable Runtime traces or lifecycle state. Forward only the sanitized fields supplied by `CCDiagnosticEvent` and never append raw URI, arguments, Extra, tokens, widgets, backend objects, exception messages, or business results.
- Treat `componentGraph`, `componentRegistration`, and `runtimeInitialize` as the framework-owned component/startup diagnostic flow. Configure the Host Sink at `CCRouter.initialize` with `CCDiagnosticLevel.debug` when start events are needed; do not duplicate these lifecycle logs in application bootstrap code.
- Use `ccrouter_analytics` for provider-neutral product events. Route page view/leave events may be bridged from `CCNavigationAspect`; click, scroll, and exposure events require stable explicit targets. Keep Firebase, ThinkingData, local persistence, and upload adapters in the application layer (the Demo example lives under `demo/modules/`); do not add vendor SDK dependencies to framework `packages/*`, and do not infer business event IDs from Widget text or arbitrary Keys.
- Keep the analytics dispatcher behind an explicit `CCAnalyticsPolicy`: its default is consent-denied, and the app must call `updatePolicy` after privacy consent. Revocation clears pending events and invalidates remaining sinks of the active event, even after immediate re-grant; already-running writes cannot be retracted. See the Analytics delivery section in `references/implementation-patterns.md` for asynchronous delivery and shutdown ownership.
- Use `ccrouter_analytics_flutter` only when the app opts in to `CCAnalyticsScope` and explicit `CCAnalyticsScrollable` or `CCAnalyticsExposureTarget` wrappers. Scope inherits an application-owned Dispatcher and immutable context, does not close it, and must not infer Route or Foreign Popup attribution. Configure exposure thresholds deliberately; do not treat the approximation as ad verification or a security signal.
- `CCNavigationAnalyticsBridge` assigns a bounded `visit_id` to managed Arrival/Show and reports total versus foreground dwell on Hide. The Host must forward resumed/background lifecycle transitions through `onForeground`/`onBackground` and call `dispose()` when it releases the bridge; consent-denied visits are not retained.
- Exposure targets observe ancestor scrolling and policy changes themselves. Consent grant and foreground resume start fresh dwell; filtered attempts do not consume `once` and are not retried every frame. Visibility includes ancestor clips, not arbitrary Overlay occlusion or opacity. Do not add a business rebuild loop to trigger exposure.
- Use `ccrouter_devtools` only for an application-owned debug route, drawer, or local overlay. The `CCRouterDevToolsPanel` is read-only and must not be used as a navigation, retry, scope disposal, component activation, or Adapter control surface.
- Tooling that crosses the Flutter application boundary must use the versioned
  `ccrouter_devtools_protocol` snapshots. Do not serialize Runtime, Navigator,
  Widget, route arguments, complete URIs, Tokens, or business results.
- For the official DevTools Extension, add `ccrouter_devtools` as a direct Host
  dependency and regenerate the Host Assembly. The generated Tool Integration
  registers after Runtime initialization and clears before Runtime shutdown;
  do not duplicate this lifecycle in a feature component. Build
  `devtools/ccrouter_extension` with a stable Flutter Web SDK; the OHOS SDK is
  not a valid Web Extension test target. The Extension is read-only and must
  tolerate a missing Runtime endpoint without changing application behavior.
- Generated Hosts read their static Catalog from the installed Host Tool
  Integration. Only manual/test integrations pass an application-owned Catalog
  to `CCRouterDevToolsSnapshotProvider(catalog: ...)` or
  `CCDevToolsServiceExtension.register(catalog: ...)`. The Catalog is joined to
  Runtime entries and trace edges by stable IDs; missing Catalog records are
  shown as unresolved rather than inferred. Source locations are copyable
  `package:` references. An IDE opener may be supplied through the panel's
  `onOpenSource` callback, but the framework never assumes an editor or local
  filesystem mapping.
- Enable `ccrouter_analyzer_plugin` only through the host Package's Analysis Server bootstrap. Keep its Analyzer dependency isolated from the application Workspace; do not add a path dependency to the rule Package when the Analysis Server will copy the bootstrap to a temporary directory. Pin unreleased Git bootstraps to a reviewed commit and use `ccrouter analyzer status/doctor <host-root>` for read-only identity, compatibility, analysis, and loader checks; switch to the provided Hosted manifest only after publication. Analyzer diagnostics use the current unsaved editor overlay and combine single-file rules with an exact generated-Metadata owner index. Its Quick Fix may delete one mutually exclusive Route/InitTask argument or add one uniquely proven Service/Command owner to a missing/direct required dependency list when the public owner constant is already imported. When every missing Owner of the same Component is uniquely provable, it may offer one additional fix that adds all of them in stable order. It never invents a Contract, identity, alias, timeout, or import, and never rewrites variables, spreads, conditionals, or computed dependency collections. `analyzer status` proves only static bootstrap consistency; use `analyzer doctor` for dependency, analysis, loader, and stale plugin-manager cache checks. Neither command proves a running IDE session, and `dart analyze` does not run legacy Analysis Server Plugins; verify realtime diagnostics in an IDE or real Language Server session. If doctor names a stale cache, stop the Analysis Server and move only that cache directory, then restart and rerun doctor. Analyzer `install/upgrade/uninstall` now support explicit Host setup and `--dry-run`; use a published Hosted version or remote full Git SHA. Existing manual bootstraps are not adopted. Follow the IDE reference for owned files, rollback journals and restart verification; do not attach installation to generation or Pub Hook. If the plugin is unavailable or incompatible, disable the bootstrap and keep Dart Analyzer plus `ccrouter generate --check` as the authoritative gates.
  For cache recovery, move the entire listed hash entry outside `.plugin_manager`
  as a backup, not just its `analyzer_plugin` child; Dart 3.11 otherwise reuses
  the incomplete parent. See the IDE reference for the SDK-specific boundary.
  Generated-file and Workspace Owner metadata disk changes must refresh the
  authored-source diagnostics without restarting. Framework Server-process
  tests validate this path against local sources; they do not upgrade an
  application's pinned plugin or certify its live IDE bootstrap.
- Keep analytics separate from diagnostics: `CCDiagnosticEvent` explains framework execution and failure, while `CCAnalyticsEvent` represents a product behavior. Analytics properties must use validated primitive values and must not contain credentials, full URI values, Widgets, exceptions, or business objects. Analytics Sink failures and queue pressure must never alter navigation or component results.
- The analytics dispatcher exposes only payload-free pressure counters (`acceptedEventCount`, `pendingEventCount`, `peakQueueDepth`, `droppedEventCount`, `timedOutSinkWriteCount`, and `quarantinedSinkCount`) plus `snapshot` per-Sink health for bounded health/performance checks. Properties, blacklist IDs, and throttle state are bounded; non-finite numbers and oversized values fail at construction. An optional `sinkWriteTimeout` quarantines a slow application Sink so `close()` is bounded, but Dart Futures remain non-cancellable and the Sink must own cancellation. These counters are not an audit log, replay source, or permission to inspect queued events; use the standalone benchmark when comparing SDK/platform behavior.
- Use `CCRouter.traceBundle(traceId)` for bounded local troubleshooting across nested calls. It is not an audit log, replay source, or business Event store; records may be incomplete after capacity rotation.
- When using generated Host assembly, pass it directly to
  `CCRouter.initialize(hostAssembly: ...)`; it supplies component Manifests,
  the read-only Contract Bundle, and optional Host Tool Integrations. Never hand-write
  Contract versions or fingerprints. Generation and Host/Runtime boundaries
  reject missing, owner-mismatched, out-of-range, fingerprint-drifted,
  duplicate, or stale Contract artifacts with stable compatibility codes.
- `CCRouter.initialize` accepts exactly one required `CCHostAssembly`; it does
  not accept loose component or Contract arguments. Generated Hosts use
  `ccrouterGeneratedHostAssembly`. A handwritten Host or focused Facade test
  uses `CCHostAssembly.fromComponents`, while ordinary Runtime tests prefer
  `CCRouterTestHost`. Do not split one generated assembly into separately passed
  manifests, Catalog, Contract, or tooling values.
- After initialization, the default `CCGoRouterApp()` resolves that Assembly's
  Catalog through the Host-only binding. Do not repeat the Catalog in the
  widget constructor or expose routing metadata through the business Facade.
  Direct `CCGoRouterBackend.managed/attach` calls remain Host SPI and keep an
  explicit Catalog for custom or incremental integration.
- Use `CCGoRouterMultiHostBackend.managed` only when one application tree truly
  owns multiple independent Router Hosts. Its factories receive the initialized
  Catalog and declared Host ID, while the aggregate owns Adapter and Router
  cleanup. When multiple Host surfaces are simultaneously interactive, the
  Composition Root must activate the Host on pointer/focus entry; feature pages
  must not call `activateHost`. Keep large-screen panes, tabs, and Shell branches
  as Outlets of one Host. The aggregate does not render a layout or model a native
  platform Window.

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
- Observe Interceptor cancellation cooperatively. Runtime shutdown ends pending Interceptor/Failure Policy waits with `CCRouteCancelledError` and ignores late decisions; it cannot stop arbitrary Dart work. Defer/resume preserves typed payloads, the original concrete Host, call-site Outlet, and result contract while revalidating policy. Configure a timeout or explicitly cancel abandoned continuations.
- Use PopGuard only for synchronous, in-memory exit decisions. Use Flutter `PopScope` for confirmation UI or asynchronous work.
- A PopGuard allow decision does not override local `PopScope`/`Form` denial on system back or `maybePop`. Keep the page and its result pending until local policy permits exit; an explicit `pop` after confirmation remains a deliberate application action. Guarded Cupertino pages still disable interactive back, while unguarded pages retain platform gestures.
- Use `CCNavigationAspect` only for observation and sanitized telemetry. It must not change navigation decisions or synchronously re-enter navigation.
- Use `CCPageLifecycleMixin` or `CCPageLifecycleListener` for PageShow/PageHide and application foreground/background observation. Use Flutter `initState/dispose` for Widget lifetime.
- Use Route Service for page-instance resources that must survive PageHide and be disposed only after the exact managed RouteEntry is removed.
- Pass `BuildContext` to navigator calls only when call-site Host/Outlet resolution is required. Do not store it globally.

## Lifecycle Rules

- `CCRouter.initialize` receives one complete Host Assembly once.
- Open a Session after login or persisted authentication restoration. Close it on logout, token invalidation, account switch, or forced sign-out.
- Do not close a Session on page Pop, backgrounding, or tab changes.
- Call and await `CCRouter.shutdown` only when the owning application
  Composition Root ends the default Runtime. Page, component, Session,
  application-background, and individual navigation Host lifecycles must not
  call it. Reinitialize only after the shutdown Future completes.
- Cancellation listeners must remain synchronous and short. A throwing listener does not skip other notifications or owned cleanup: Scope records notification/disposal failures internally, and Runtime reports an early App cancellation failure only after structural teardown. Reentrant shutdown joins that teardown and cannot permit early initialization. Never await an Owner's shutdown from an object that the same shutdown is waiting to dispose.
- Select the narrowest Service Scope: app, session, or route.
- A Service that owns a disposable client must itself implement `CCDisposable` and forward cleanup; implementing it only on the nested client is insufficient. Await owned asynchronous closure, make repeated disposal safe, and prevent late callbacks from retaining data after disposal. Consumers must not dispose a framework-owned Service.
- The Analyzer can connect an existing compatible `dispose()` to `CCDisposable` through an explicit Quick Fix. Its owned-resource warning is conservative and never generates cleanup or proves absence of leaks. Keep Scope lifecycle tests and consult `references/ide-analysis-server.md` for coverage and fallback boundaries.
- Prefer singleton; use `newInstance` only for stateless or immutable helpers whose ownership remains safe.
- Use async Service readiness only when callers cannot safely use the instance immediately after synchronous construction.
- Singleton readiness is shared, including across independent callers. Runtime rejects active dependency wait cycles; caller timeout/cancellation removes its wait without cancelling shared initialization. Do not retry a failed initializer implicitly within the same Scope.
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
- Keep a `@CCServiceContract` interface itself non-generic. Its methods may use method-owned generic parameters with public Pure Dart bounds; generated Proxies preserve bounds, nullability, and explicit type arguments. Internal callback names and import prefixes avoid authored parameter and generic names automatically. Do not use method generics to pass Flutter objects, callbacks, Streams, or private implementation types across a component boundary.

## Generated Code and Validation

For a new component or internal page, the generator CLI provides non-overwriting
templates:

```bash
fvm dart run ccrouter_generator:ccrouter create component <package-name> <parent-directory>
fvm dart run ccrouter_generator:ccrouter create page <PageName> <component-directory>
fvm dart run ccrouter_generator:ccrouter create service <ServiceName> <component-directory>
fvm dart run ccrouter_generator:ccrouter create command <CommandName> <component-directory>
fvm dart run ccrouter_generator:ccrouter create event <EventName> <component-directory> [--with-subscriber]
fvm dart run ccrouter_generator:ccrouter create init-task <TaskName> <component-directory> [--with-contract]
```

The scaffold only creates authored source and refuses to replace existing files.
Run `pub get` and `generate` afterwards. It creates internal capabilities by
default: Service uses a concrete `@CCService(id: ...)`, Event adds a Subscriber
only with `--with-subscriber`, and an independent InitTask adds a reusable
Contract only with `--with-contract`. Promoting a capability to a cross-component
Contract remains an explicit design step.
For a new Component, the CLI inherits the nearest proven Dart SDK and CCRouter
dependency sources, rebasing direct Path dependencies for the new Package. It
does not assume a hosted framework version when the current Workspace cannot
prove one.
Treat the CLI's printed `Next steps` as non-mutating guidance. Confirm the actual
Host and dependency owner before applying them; the scaffold does not infer or
edit that ownership.

After Route, Service, Command, Event, or InitTask annotation, component definition, contribution, or dependency changes, run from the workspace root:

```bash
fvm dart run ccrouter_generator:ccrouter generate <host-root>
```

The repository Workspace root is an aggregator rather than a Host. The Pub Hook
skips any current Package that does not directly declare `ccrouter`, even when
its resolved Workspace graph contains CCRouter Packages. Run Host generation
from the actual Host directory (for this repository, `demo/`); the Hook never
guesses a member Host from an aggregator.

Validate with:

```bash
fvm dart analyze
fvm flutter test <focused-test-target>
fvm dart run ccrouter_generator:ccrouter generate <host-root> --check
```

For a long-lived local or AI development session, use `generate <host-root>
--watch=auto --machine`. Treat stdout as schema `1` NDJSON, wait for `ready`
before the first consumer action, and require `aggregationSucceeded` rather
than only `buildSucceeded` after changes. Keep stderr as diagnostic text. Set
`CCROUTER_DISABLE_BUILD_WATCH=1` for a one-shot fallback. Watch is scoped to one
resolved build root; an independently runnable nested Package Host with its own
Pub root uses a separate watch. It holds the root generation lock, so stop it
before finishing with `--no-cache --check`.
The post-Builder cycle may skip redundant planning, but never its input
barriers, preflight, snapshot, validation, aggregation, or local state writes.
Use `CCROUTER_DISABLE_WATCH_CYCLE_OPTIMIZATION=1` for a reference-cycle A/B
comparison while keeping watch active.

Use `ccrouter find <capability-id-or-route-pattern> <host-root>` to locate a generated Route, Service, Command, Event, or InitTask instead of scanning or guessing. Route declarations additionally support Pattern lookup. Add `--usage <consumer-component-id>` for a read-only recipe based on verified Package Index facts; it never edits dependencies or imports, and an unavailable public barrel requires explicit Contract exposure followed by regeneration. Normal generation may use an exact-content fast path only when authored inputs, tool identity, Package graph, external indexes, and every managed output match the last successful manifest. Use `--no-cache` as the authoritative reference-path check and `--profile` only for generation performance diagnosis. The profile trace is diagnostic data: do not make application logic, cache policy, or CI correctness depend on its timings. On a miss, `build-targets` names Builder inputs while `dirty-packages` names post-build aggregate invalidations and their propagation reasons; do not treat them as the same set. `input-delta` and `output-delta` provide bounded exact-content attribution; resolution-only changes do not prove causal dependencies, and changed state files do not imply changed business APIs. See the generation guidance in implementation-patterns for trace schema, unavailable-baseline, and check-restoration semantics. The Build Plan's `suggested` is only a candidate; only `actual=aggregateOnly` means build_runner was skipped. It supports a proven pure Package removal and a pure addition whose committed Portable Generation State exactly matches current source, resolution, metadata, and managed output. A writable unproven addition runs Builder; a read-only external Package with missing or stale state fails explicitly. Set `CCROUTER_DISABLE_AGGREGATE_ONLY=1` for an emergency full-Builder fallback. Commit `lib/src/ccrouter_generated/metadata/ccrouter_generation_state.json` with generated output, never commit `.dart_tool/ccrouter/v1/build_plans/` or `profiles/`, and retain `--no-cache --check` as the CI authority. Never delete caches or touch files merely to force an ordinary generation run.

## Completion Standard

- Confirm the feature uses the correct capability and dependency direction.
- Confirm all navigation paths use generated Intent or controlled dynamic URI APIs.
- Confirm failure, cancellation, result typing, and disposal behavior are tested where relevant.
- Confirm no generated output was manually changed.
- Confirm no new public API or cross-component dependency was introduced without a real consumer.
- Report unsupported requirements explicitly instead of implementing a semantically weaker workaround.
