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
Generation keeps the selected Package `requestedRoot` separate from the Pub
`resolutionRoot`. A Workspace member uses only its validated
`.dart_tool/pub/workspace_ref.json` or an exact enclosing Workspace membership;
a standalone nested Package does not inherit an unrelated ancestor graph.
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
Its Pub-resolution hint uses the selected Package's explicit
`requestedRoot/resolutionRoot`, `.metadata`, and `ccrouter.yaml` role. It can
therefore distinguish Host, Flutter package-local, and Pure Dart package-local
guidance without an active watch. Treat malformed or stale Workspace evidence
as unavailable diagnostics, not permission to borrow an ancestor graph. When a
Workspace root is analyzed, every explicit participating member receives and
clears its own saved-versus-resolved hint; the plugin indexes the manifest list
instead of recursively scanning the Workspace.

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
- Enable `ccrouter_analyzer_plugin` only through the host Package's Analysis Server bootstrap. Keep its Analyzer dependency isolated from the application Workspace; do not add a path dependency to the rule Package when the Analysis Server will copy the bootstrap to a temporary directory. Pin unreleased Git bootstraps to a reviewed commit and use `ccrouter analyzer status/doctor <host-root>` for read-only identity, compatibility, analysis, and loader checks; maintainers use `ccrouter analyzer pin-check <host-root>` to verify manifest/lock/resolved identity, exact remote SHA availability, and advisory Plugin production drift. Do not make pending drift a hard gate for the first-stage Plugin commit. Switch to the provided Hosted manifest only after publication. Analyzer diagnostics use the current unsaved editor overlay and combine single-file rules with an exact generated-Metadata owner index. Its Quick Fix may delete one mutually exclusive Route/InitTask argument or add one uniquely proven Service/Command owner to a missing/direct required dependency list when the public owner constant is already imported. When every missing Owner of the same Component is uniquely provable, it may offer one additional fix that adds all of them in stable order. It never invents a Contract, identity, alias, timeout, or import, and never rewrites variables, spreads, conditionals, or computed dependency collections. `analyzer status` proves only static bootstrap consistency; use `analyzer doctor` for dependency, analysis, loader, and stale plugin-manager cache checks. Doctor reports source, cache, temporary loader smoke, restart, and live verification separately; it never controls the IDE. Neither command proves a running IDE session, and `dart analyze` does not run legacy Analysis Server Plugins; verify realtime diagnostics in an IDE or real Language Server session. If doctor names a stale cache, stop the Analysis Server from the IDE, confirm any reported candidate process has exited, and manually move the whole listed cache entry to its exact backup path outside `.plugin_manager`; doctor never kills, moves, or deletes global state. Analyzer `install/upgrade/uninstall` now support explicit Host setup and `--dry-run`; use a published Hosted version or remote full Git SHA. Existing manual bootstraps are not adopted. Follow the IDE reference for owned files, rollback journals and restart verification; do not attach installation to generation or Pub Hook. If the plugin is unavailable or incompatible, disable the bootstrap and keep Dart Analyzer plus `ccrouter generate --check` as the authoritative gates.
  When Plugin production behavior changes, first commit, verify, and push that
  change, then update each maintained Demo/Host Git bootstrap to the remotely
  resolvable full SHA in a separate commit. Update its lockfile, run `analyzer
  doctor`, restart Analysis Server, and verify a real diagnostic or Quick Fix.
  Tests, comments, and behavior-preserving refactors do not require a pin bump;
  never use a branch, floating tag, unpushed SHA, or a self-referential ref.
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
fvm dart run ccrouter_generator:ccrouter create component <package-name> <parent-directory> [--with-example]
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
The component itself is explicitly `project_type: package`. `--with-example`
uses Flutter's official empty app template and creates an app-role Host with
direct component and CCRouter dependencies. Add both directories to a Workspace
when prompted, resolve Pub from the example Host, then generate that Host.
Treat the CLI's printed `Next steps` as non-mutating guidance. Confirm the actual
Host and dependency owner before applying them; the scaffold does not infer or
edit that ownership.

After Route, Service, Command, Event, or InitTask annotation, component definition, contribution, or dependency changes, run from the workspace root:

```bash
fvm dart run ccrouter_generator:ccrouter generate <host-root>
```

The argument selects a Package, not always a Host. An app-role Host generates
its writable dependency closure and performs cross-Package validation and Host
assembly. A component or contracts Package runs package-local generation and
publishes only its own API, Bundle, index, and catalog; use this after editing
that Package when no Host-level validation is required yet. Finish integration
work with `generate <actual-host> --no-cache --check`. Do not use a Workspace
aggregator as a surrogate Host, and start watch only from an app-role Host.
An independently runnable nested example owns its subtree from its own
`pubspec.yaml`; parent Package generation and clean do not mutate its artifacts.

The repository Workspace root is an aggregator rather than a Host. The Pub Hook
skips any current Package that does not directly declare `ccrouter` or
`ccrouter_contracts`, even when its resolved Workspace graph contains CCRouter
Packages. An app-role Host runs Host generation; a participating Flutter/Pure
Dart Package runs package-local generation. Run Host generation from the actual
Host directory (for this repository, `demo/`); the Hook never guesses a member
Host from an aggregator.
The per-SDK Hook covers successful `flutter pub` and direct `dart pub` dependency
commands. On macOS/Linux it wraps Flutter's inner Dart executable, including the
path commonly launched by IDE Pub actions. On Windows only `bin/dart.bat` is
covered; direct IDE execution of `cache/dart-sdk/bin/dart.exe` remains outside
the boundary and is reported by `pub-hook status`. Flutter Tool's own implicit
Pub resolution is not a Hook event. Use `CCROUTER_PUB_HOOK_DISABLE=1` only for
an explicit one-shot bypass, then run the appropriate generation check.
Wrapper command detection consumes only known global options and their declared
values before selecting the first real top-level command and Pub subcommand.
Tokens inside option values, Dart script arguments, or business arguments never
trigger generation; unknown global-option arity safely bypasses the Hook.

Validate with:

```bash
fvm dart analyze
fvm flutter test <focused-test-target>
fvm dart run ccrouter_generator:ccrouter generate <host-root> --check
```

For a long-lived local or AI development session, use `generate <host-root>
--watch=auto --machine`. Treat stdout as schema `1` NDJSON, wait for `ready`
before the first consumer action, and require `aggregationSucceeded` rather
than only `buildSucceeded` after changes. Keep stderr as diagnostic text.
Default events retain final build and aggregation timings. Add `--profile`
explicitly for benchmarks or AI diagnosis of a slow run; only then require
build_runner verbose durations and the complete cycle trace.
When Flutter's Hook owns the background watch, use `watch status <host-root>`
for one read-only snapshot or `watch follow <host-root>` for concise changes.
The wrapper prints its successful watch-start summary to stdout before the
original Flutter process begins. It must first observe `sessionReady` for the
exact wrapper lease and confirm the build-root owner lock; a forked background
process is not readiness. Startup conflict, exit, structured failure, or timeout
blocks Flutter and remains on stderr. `CCROUTER_DISABLE_WATCH_STARTUP_HANDSHAKE=1`
is an isolated A/B fallback, not a normal workflow. These summaries are not
watch NDJSON.
For `flutter run --machine`, the Hook's stdin-only reload gate waits until
watch has completed the saved authored-input revision before forwarding
`app.restart`. Generation failure appears as a Hot Reload daemon error
instead of allowing old generated code. A topology-changing watch restart
requires an explicit Hot Restart. Interactive terminal `r` is outside this
machine boundary; wait for `watch follow` success first. Closing the parent
machine stdin also closes the original Flutter Tool's stdin so IDE/AI session
termination retains Flutter's normal EOF lifecycle. Use
`CCROUTER_DISABLE_HOT_RELOAD_GATE=1` only for isolated fallback comparison.
On Windows, the wrapper runs the original Flutter Tool through a terminal-
inheriting Dart supervisor. It owns and refreshes the versioned watch lease;
normal, non-zero, and handled interrupt exits remove the lease, while a forced
supervisor death makes watch stop after the bounded heartbeat expiry. Use
`CCROUTER_DISABLE_WINDOWS_RUN_SUPERVISOR=1` only to compare the former batch
lifecycle; it deliberately removes that orphan-recovery guarantee.
The user-level `CCROUTER_HOME` owns stable V2 generation/watch locking and the
minimal Host/Builder session authority. The atomic local
`.dart_tool/ccrouter/v1/watch/status.json` is the Host-facing observability
mirror and an active watch recreates it after local cleanup. Complete
Hook diagnostics remain in `watch/flutter-run.log` and are never mixed into
Flutter Tool's machine stdout. Failure to publish observational state does not
fail or weaken direct generation, but the Hook refuses to launch Flutter when
it cannot prove readiness for its exact lease. If an abrupt exit leaves an `active` record, the
read-only commands report it as `stale` after the owner lock is released and do
not rewrite the historical status file.
An installed Flutter wrapper blocks a real top-level `flutter clean` while the
resolved build root has an active watch. Stop `flutter run/watch` before clean;
the guard deliberately does not kill another development process. The narrow
`CCROUTER_DISABLE_FLUTTER_CLEAN_GUARD=1` bypass is for recovery/A/B only.
Workspace validation failures also publish a bounded atomic
`watch/diagnostics.json`. The Analyzer Plugin accepts it only when Host/build
root, session, cycle, event revision, and resolution fingerprint match the
current status. It then maps `package:` locations through Package config and
folds one missing Owner's capability fallout into one root-cause diagnostic.
If saved `pubspec.yaml` dependencies differ from the resolved graph, the plugin
only asks for the role-appropriate Flutter or Dart Pub get and suspends
ownership conclusions; this hint is available without an active watch. Because
Analysis Server does not reliably forward `.dart_tool` events, the plugin polls
the watch snapshots, role inputs, Workspace reference, and Pub graph/config
identities every 500ms and reanalyzes after changes; it does not open a second
Analyzer graph. Use `CCROUTER_DISABLE_ANALYZER_WATCH_BRIDGE=1` for an IDE-only
fallback. Keep `--no-cache --check` as the final authority.
`buildSucceeded.buildRunner` is diagnostic-only structured phase data. Its
`invalidatedInputs` count is inferred from build_runner's public counters; it
does not expose AssetIds, prove semantic output impact, or authorize skipping a
Builder. Unknown upstream terminal formats are bounded in
`unparsedFinalLines` and do not fail generation. Set
`CCROUTER_DISABLE_BUILD_WATCH=1` for a one-shot fallback. Watch is scoped to one
resolved build root. Different Hosts in that root share one Builder owner and
target union, but each retains its own aggregation, validation, lease, status,
diagnostics, and Host-scoped input revision. `builderOwnerPid` may therefore
differ from the Host status `pid`; an active subscriber takes over when the
owner exits. Do not start a second watch for the same Host. An independently
runnable nested Package Host with its own Pub root uses a separate watch. Set
`CCROUTER_DISABLE_MULTI_HOST_WATCH=1` only for an A/B fallback. Stop all watches
for the root before finishing with `--no-cache --check`.
One-shot generation, check, and clean commands fail fast while that root watch
is active. Wait for `aggregationSucceeded` instead of polling one-shot commands.
Watch startup also fails fast while a one-shot command owns or awaits the root.
Successful hooked Pub dependency commands are the exception: for the same Host,
the Hook waits for the active watch cycle after the latest resolution input and
reuses its completed aggregation. Watch failure diagnostics are surfaced and
the Pub Hook remains fail-closed. A failure must belong to a new
`sessionId/cycle/eventRevision` after the wait begins; resolution churn returns
immediately and requires another cycle/session, while success still requires an
exact current fingerprint. This does not permit arbitrary one-shot generation
beside a watch or reuse status belonging to another Host. Use
`CCROUTER_DISABLE_PUB_HOOK_WATCH_FAILURE_FENCE=1` only for legacy A/B fallback.
For a package-local Pub command in the same build root, a Host watch target name
is not exact completion evidence. The Hook verifies build-root status plus the
live owner lock, reports whether that Host covers the requested Package, and
fails before starting a conflicting one-shot. Wait for `aggregationSucceeded`
when coverage is sufficient for iteration, or stop the watch and retry from the
Package when the Hook command itself must succeed. Ignore stale, malformed, or
wrong-root status.
Watch independently observes exact Pub-resolution changes. Covered resolution
changes run an aggregation cycle; a new closure Package, changed Builder target
set, or build_runner exit caused by resolution churn rotates to a new child
under the same lock/lease. Pub Hook must wait for that session's `ready`, not
only an earlier `aggregationSucceeded`. Use
`CCROUTER_DISABLE_WATCH_SESSION_RESTART=1` only for a fail-closed one-shot
fallback after stopping watch.
Child shutdown is bounded at 10 seconds for SIGINT, 5 seconds for SIGTERM, and
5 seconds after final SIGKILL so a stuck build_runner cannot retain the
generation lock indefinitely.
The post-Builder cycle may skip redundant planning, but never its input
barriers, preflight, snapshot, validation, aggregation, or local state writes.
Use `CCROUTER_DISABLE_WATCH_CYCLE_OPTIMIZATION=1` for a reference-cycle A/B
comparison while keeping watch active.
The aggregation cycle also runs through the in-process generation kernel by
default and reports `aggregationSucceeded.cycleMode=inProcess`. Use
`CCROUTER_DISABLE_WATCH_IN_PROCESS_CYCLE=1` only to compare against the
`subprocessReference` path; neither mode replaces the final
`--no-cache --check`.
Successful cycles share one exact-content planning snapshot between the local
fast-path manifest and Build Plan state. Use
`CCROUTER_DISABLE_SHARED_PLANNING_SNAPSHOT=1` only for byte-for-byte or timing
A/B against the separate-scan reference; all input barriers, validation,
artifact restoration, atomic writes, and the final reference gate remain.
In watch mode, the final input barrier's exact snapshot may feed the local
planning state directly. A verified aggregation hit may also reuse only the
aggregation-owned entry bytes while current Builder-owned outputs are reread.
Use `CCROUTER_DISABLE_WATCH_EVIDENCE_REUSE=1` for the full-recapture A/B path;
it does not remove a barrier or weaken `--no-cache --check`.
After a successful watch cycle, planning state may also consume the exact
current output bytes already captured for profile delta reporting. Use
`CCROUTER_DISABLE_WATCH_OUTPUT_EVIDENCE_REUSE=1` to disable only this reuse;
Builder execution, aggregation, validation, barriers, and rollback are unchanged.
The profile trace may include `aggregation-input-fingerprint` with a bounded
SHA-256 `attributes.fingerprint`. It never authorizes skipping Builder. After a
successful Builder cycle, matching Tool/input identities and exact
aggregation-owned output bytes may reuse those outputs while retaining Package
verification, Workspace validation, and both input barriers. Set
`CCROUTER_DISABLE_AGGREGATION_REUSE=1` for the full-aggregation A/B reference;
`--no-cache --check` remains authoritative.

Use `ccrouter find <capability-id-or-route-pattern> <host-root>` to locate a generated Route, Service, Command, Event, or InitTask instead of scanning or guessing. Route declarations additionally support Pattern lookup. Add `--usage <consumer-component-id>` for a read-only recipe based on verified Package Index facts; it never edits dependencies or imports, and an unavailable public barrel requires explicit Contract exposure followed by regeneration. Normal generation may use an exact-content fast path only when authored inputs, tool identity, Package graph, external indexes, and every managed output match the last successful manifest. Use `--no-cache` as the authoritative reference-path check and `--profile` only for generation performance diagnosis. The profile trace is diagnostic data: do not make application logic, cache policy, or CI correctness depend on its timings. On a miss, `build-targets` names Builder inputs while `dirty-packages` names post-build aggregate invalidations and their propagation reasons; do not treat them as the same set. `input-delta` and `output-delta` provide bounded exact-content attribution; resolution-only changes do not prove causal dependencies, and changed state files do not imply changed business APIs. See the generation guidance in implementation-patterns for trace schema, unavailable-baseline, and check-restoration semantics. The Build Plan's `suggested` is only a candidate; only `actual=aggregateOnly` means build_runner was skipped. It supports a proven pure Package removal and a pure addition whose committed Portable Generation State exactly matches current source, resolution, metadata, and managed output. A writable unproven addition runs Builder; a read-only external Package with missing or stale state fails explicitly. Set `CCROUTER_DISABLE_AGGREGATE_ONLY=1` for an emergency full-Builder fallback. Commit `lib/src/ccrouter_generated/metadata/ccrouter_generation_state.json` with generated output, never commit `.dart_tool/ccrouter/v1/build_plans/` or `profiles/`, and retain `--no-cache --check` as the CI authority. Never delete caches or touch files merely to force an ordinary generation run.

## Completion Standard

- Confirm the feature uses the correct capability and dependency direction.
- Confirm all navigation paths use generated Intent or controlled dynamic URI APIs.
- Confirm failure, cancellation, result typing, and disposal behavior are tested where relevant.
- Confirm no generated output was manually changed.
- Confirm no new public API or cross-component dependency was introduced without a real consumer.
- Report unsupported requirements explicitly instead of implementing a semantically weaker workaround.
