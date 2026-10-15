# Implementation Patterns

Examples show separate integration patterns, not one file to concatenate.
Application symbols such as `analytics`, `database`, and manifests must come
from the consuming project. Generated Client names come from its real component
and Contract declarations. Do not invent these APIs or register both an
annotated Provider and its alternative handwritten Provider.

## Package Roles

### Host

The Host may import `ccrouter_go_router` and `ccrouter_host.dart`. A new GoRouter
application should first call
`CCRouterHost.initialize(hostAssembly: ccrouterGeneratedHostAssembly)` and then use
`const CCGoRouterApp()` for the minimal Host assembly path. The widget resolves
the exact Catalog retained from initialization through a Host-only Binding; do
not repeat the Catalog argument or expose it through the business Facade. The
generated stable Host barrel exports only the atomic Assembly.
`CCGoRouterApp` never initializes or shuts down the process Runtime. The Host
owns generated Host assembly, navigation Backend,
Shell/Outlet topology, platform Deep Link ingress, global policies and final
`CCRouterHost.shutdown`.

Direct `CCGoRouterBackend.managed/attach` usage remains an advanced Host SPI and
still receives an explicit Catalog. This supports existing application-owned
Routers, custom multi-Host composition, and focused Backend tests without
making routing metadata available to feature code.

When one application tree has multiple genuinely independent Router Hosts, use
`CCGoRouterMultiHostBackend.managed`. It reads the initialized Catalog once,
supplies that snapshot and each declared Host ID to the child Backend factories,
validates their identity, aggregates `CCMultiHostNavigationAdapter`, and releases
all child Router resources after Runtime Adapter teardown. The application owns
the visual arrangement and active-Host policy. When two surfaces remain
interactive at once, activate the owning Host on pointer-down and focus entry at
the Composition Root before a descendant callback runs. This keeps default
placement and Pop operations local without exposing Host selection to feature
pages. Pass a call-site Context when a forward navigation also needs exact
Host/Outlet placement. Do not use it for master-detail, tabs, or Shell branches
that are Outlets of one Host, and do not treat it as a native multi-window
lifecycle bridge.

A handwritten Host uses the same lifecycle contract:

<!-- verified-example: host-assembly -->
```dart
final hostAssembly = CCHostAssembly.fromComponents(
  components: [ordersManifest, accountManifest],
  routeCatalog: applicationRouteCatalog,
);
CCRouterHost.initialize(hostAssembly: hostAssembly);
```

Do not pass loose component or Contract collections to `CCRouterHost.initialize`;
the required Assembly is the compile-time boundary that keeps one startup
snapshot internally consistent. A handwritten Host that owns routes must place
its Catalog in the same `fromComponents` call; `CCGoRouterApp` has no separate
Catalog override.

`CCGoRouterApp` mirrors the non-routing configuration of `MaterialApp.router`,
including themes, locale and localization delegates, `ScaffoldMessenger`,
shortcuts/actions, restoration, scrolling, and debug flags. Configure those
directly on `CCGoRouterApp`; do not wrap it in another `MaterialApp`. Routing
properties (`routerConfig`, delegates, information provider/parser, and back
button dispatcher) remain exclusively owned by `CCGoRouterBackend` and are not
pass-through options.

Runtime and multi-Host teardown use best-effort structural cleanup. Listener or
PopGuard removal failures do not skip remaining child Adapters or Scopes, while
the first cleanup error is still returned to the Host. A rejected Adapter attach
remains Host-owned; Runtime rolls back its partial listener and ledger state so
the Host can dispose that Adapter or safely attach another one.

Cancellation listeners are notified from a released snapshot, so one throwing
listener cannot retain the remaining callbacks or skip their notification.
Scope records cancellation failures with its disposal errors and continues
cleanup. An early App cancellation failure reaches the shutdown caller only
after Runtime teardown. Shutdown establishes its reentry gate before callbacks;
reentrant calls join cleanup, and initialization remains unavailable until it
finishes. A disposable must not await its own Owner's teardown Future.

Use `CCGoRouterApp.backendFactory` when the application needs custom Shell,
redirect, refresh, or Router construction but can retain the standard Material
application wrapper. The factory receives immutable configuration and is called
once. Use `CCRouterApp.managed` with a manually created `CCRouterAppBackend`
only for a fully custom application tree. Use
`CCGoRouterBackend.attach` for an existing application-owned GoRouter; the
minimal widget is not an attach replacement and never disposes an external
Router.

Feature packages must not perform these duties.

`CCRouterHost` and `CCHostAssembly` are Host-only exports from
`package:ccrouter/ccrouter_host.dart`. `CCRouter` exposes neither lifecycle
control nor an Assembly type. There are no deprecated aliases. A feature page
that obtains privacy consent reports that product decision through a narrow
Host-provided callback or Contract. The Host chooses
`CCInitTaskGate.privacyGranted` and calls `CCRouterHost.runInitTasks`; do not
inject a generic Gate runner or import Host SPI in the page. The Demo uses
`DemoInitializationActions` callbacks installed by `demo/lib/demo_initialization.dart`
for its privacy and timeout lab actions, including multi-Host composition.


### CLI Scaffolding

For the complete implemented command matrix and AI-assisted fallback workflows
for deferred CLI 2.0 capabilities, read
[`ccrouter-cli-development`](../../ccrouter-cli-development/SKILL.md). Use the
fallback only when no existing command covers the operation; it must produce a
dry-run summary before changing Contracts, dependencies, or public exposure.

If automatic generation after dependency resolution is desired, install the
explicit per-SDK `pub-hook` documented in
the bundled [CLI Skill](../../ccrouter-cli-development/SKILL.md#pub-hook). Do not
modify Flutter internals manually. The hook covers successful `flutter pub` and
direct `dart pub` commands and runs a fail-closed preflight before
`flutter run/build`. On POSIX it wraps Flutter's inner Dart executable; on
Windows only `bin/dart.bat` is covered, so an IDE that invokes `dart.exe`
directly remains outside the boundary. Flutter Tool's internal implicit
`pub get` also remains outside its boundary. The current Package must directly declare `ccrouter` or
`ccrouter_contracts`; app-role Hosts run Host generation and other participating
Packages run package-local generation. A Workspace aggregator is skipped even
when its resolved graph contains CCRouter Packages.
Every Hook-owned Dart entrypoint, including preflight, post-pub, supervisor,
and watch daemon processes, must pass the package config produced by the
successful Pub command through `--packages`. Never allow a bare internal
`dart run` to perform Dart-only resolution for a Flutter Host.
Schema 6 identifies wrappers with this contract. Upgrade schema 4/5 by
uninstalling the old wrapper before installing the current one.

Flutter build preflight uses ordinary generation. If the same root already has
an active watch, it validates and reuses exact current cycle evidence before
continuing Android, iOS, or `flutter build hap`; watch ownership alone is not a
build failure. DevEco/Hvigor direct builds bypass this wrapper. Register a Host-
owned Hvigor task before the Flutter plugin's `FlutterTask`, resolve Dart from
`ohos/local.properties`' Flutter SDK, and invoke
`ccrouter_generator:ccrouter pub-hook run --project-root <host> --pub-command
build`. This performs one-shot generation while idle or exact watch reuse while
active. Do not request `--no-cache`, profiling, or custom output from this task.
Keep a dedicated bypass environment variable for recovery/A/B only and run the
Host generation gate separately whenever it is used.

Use the generator CLI to create a new component Package or an internal Route
page when starting a feature:

```bash
fvm dart run ccrouter_generator:ccrouter create component catalog demo/modules
fvm dart run ccrouter_generator:ccrouter create component catalog demo/modules --with-example
fvm dart run ccrouter_generator:ccrouter create page ProductPage demo/modules/catalog
```

The Component template inherits the nearest explicit SDK and CCRouter
dependency declarations. Git declarations are retained and direct Path
dependencies are rebased relative to the new Package; an unresolved source
fails before any scaffold file is written.
The component declares Flutter `project_type: package`. The optional example is
created from Flutter's empty app template, keeps `project_type: app`, and has
direct component/CCRouter dependencies so it is independently generated as a
Host. Workspace projects must register both directories before Pub resolution.

Running `generate` for the component directory updates only that component's
generated API, Bundle, Package index, and package catalog. Running it for the
example app performs Host aggregation and cross-Package validation. Use the
component command during isolated implementation and the example/real Host
`--no-cache --check` as the final authority; do not substitute the Workspace
aggregator for either role.

The command creates only missing authored files and fails before writing when a
target already exists. Run Pub resolution and `ccrouter generate` afterwards;
the scaffold never edits Host dependencies or generated output. Treat the page
as component-internal by default and create a Pure Dart Route Contract only
after a real cross-component consumer appears.

Capability scaffolds follow the same internal-first rule. A Service starts as
one concrete `@CCService(id: ...)`, an Event does not assume a local Subscriber,
and an independent InitTask uses `id` directly. Add `--with-subscriber` or
`--with-contract` only when that extra relationship is intentional.
The CLI prints non-mutating `Next steps` after a successful scaffold. Review the
proposed Workspace/Host ownership instead of treating the hint as an inferred
dependency decision.

For an existing capability and consumer, use
`ccrouter find <capability> <host-root> --usage <component-id>` before editing
dependencies. The recipe reports only facts proven by the generated Host
closure and public export chain. Apply its kind-specific guidance manually,
then regenerate and let Analyzer/Workspace Validator remain authoritative. Do
not infer an implementation-Package dependency when the command reports that a
Contract has no verified public exposure.

### Component Implementation

The implementation Package owns exactly one public top-level `const CCComponent`, pages, local policies, Services and message handlers. The generator keeps its Registrar and Manifest private. Export only intended business contracts.

### Contracts Package

Keep it Pure Dart where possible. Depend on `ccrouter_contracts`, never on
Flutter page implementations. Re-export generated Route Consumer types through the
stable `src/ccrouter_generated/<package>.contracts.api.g.dart` entry and keep an
explicit `show` list. Export authored Service, Command, Event, and InitTask
contracts from their own source libraries; generated Arguments, Definition, and
Codec remain Owner SPI and are not business exports. The generated Route entry
does not choose authored APIs. Never bind an authored public barrel to an individual
`contract/*.route.contract.g.dart` path.

## Typed Navigation

Use the actual generated type imported from the public contracts barrel (this
example uses the Demo's `OrderDetailRoute`); do not invent a Route facade name.

```dart
final result = await CCRouter.navigator.push<String>(
  OrderDetailRoute.intent(orderId: 42),
  source: const CCNavigationSource.feature('checkout'),
);
```

Use `replace` only when the current entry should no longer remain. Use `go` for declarative location changes and `reset` only for an explicit new root. Do not emulate unsupported remove-until operations with a sequence of pops and pushes.

Use `context:` only when call-site Host/Outlet placement is required. Without
Context, default placement resolves through the active Host while an explicit
route Host/Outlet remains authoritative.

Deferred navigation pins the original concrete Host and call-site placement.
Changing the active Host does not retarget a saved request. Resume revalidates
typed arguments with the codec encoder while preserving arguments/Extra identity;
dynamic URI requests match and decode again. Redirect targets with explicit
placement still override call-site defaults. Keep a timeout or cancel abandoned
continuations so in-memory payloads are released.

Runtime shutdown completes pending Interceptor and Failure Policy waits with
`CCRouteCancelledError` and prevents late decisions from reaching the Adapter.
Interceptors should observe `context.cancellation`; arbitrary business Futures
cannot be forcibly stopped. Do not turn shutdown cancellation into a recovery
navigation or use it to continue the ended Runtime.

For an unsaved editor, local `PopScope` or `Form(canPop: false)` still vetoes
system back and `CCRouter.navigator.maybePop` even when the framework PopGuard
allows exit. Use the local refusal callback for confirmation UI and explicitly
call `CCRouter.navigator.pop` after confirmation; do not trigger navigation from
the Guard. Cupertino pages with a Guard continue to disable interactive back;
pages without one keep their default platform gesture.

## Dynamic and External URI

```dart
await CCRouter.navigator.open(Uri.parse(location));

await CCDeepLinkIngress.fromPlatform(uri);
await CCDeepLinkIngress.fromNotification(uri);
await CCDeepLinkIngress.fromQrCode(uri);
```

Configure exact Host allowlist entries and explicitly enable external ingress on the destination. Keep push as the default external open mode unless declarative Shell reconstruction requires `go`.

## Component-Internal Route

默认页面根据应用宿主选择 MaterialPageRoute / CupertinoPageRoute；MaterialApp 的 Material
路由会按主题适配 iOS 滑动返回和 Android 系统返回。MaterialApp 也提供 CupertinoTheme，不能
据此强制使用 Cupertino 路由。仅在产品明确需要时指定 `CCPageRouteType.cupertino`；不要为了
Android 返回问题逐页加防抖或拦截系统返回。默认 Dialog 复用同一宿主判定并保留各自的 barrier
默认值。没有 MaterialApp/CupertinoApp 祖先的自定义 Host 可用显式 CupertinoTheme 选择
Cupertino 默认策略；已知 App 宿主始终优先于 Theme fallback。

<!-- verified-example: route-page -->
```dart
@CCRoute<void>(
  id: 'catalog.product',
  pattern: CCPathPattern('/products/:productId'),
  description: 'Product details.',
)
final class ProductPage extends StatelessWidget {
  const ProductPage({required this.productId, super.key});
  final String productId;

  @override
  Widget build(BuildContext context) => Text(productId);
}
```

Do not add a generated `part`. Import the component's stable
`<componentId>.api.g.dart` barrel after generation when callers need a generated
Intent or Service/Command/Event client. The barrel is generated under
`lib/src/ccrouter_generated/` and is the supported business-facing entry point.
Do not import or hand-edit its underlying `component/*_api.g.dart` files; those
remain generator and Host implementation details. Components without an
exportable API do not receive an empty barrel.

Use `@CCExtraParam` for a typed process-local object that must retain identity:

<!-- verified-example: extra-page -->
```dart
final class ProductDraft {
  const ProductDraft(this.id);
  final String id;
}

@CCRoute<void>(
  id: 'catalog.product_editor',
  pattern: CCPathPattern('/products/editor'),
)
final class ProductEditorPage extends StatelessWidget {
  const ProductEditorPage({
    @CCExtraParam() required this.draft,
    super.key,
  });

  final ProductDraft draft;

  @override
  Widget build(BuildContext context) => Text(draft.id);
}
```

The generated page binding retains `ProductDraft` as a static type and validates
the runtime Extra before page construction. A mismatch throws a sanitized
`CCRouteParameterError`. Keep shareable or externally supplied values in
Path/Query; Extra is not available to Deep Links, restoration, persistence, or
cross-process navigation.

## Cross-Component Route

Declare `@CCRouteContract<R>` in a contracts package and `@CCRouteImplementation` in the page package. The consumer depends only on the contracts package. Keep all URI-shared types Pure Dart and public; do not place Flutter, `dart:ui`, `package:*/src/`, or page-private types in a public contract.

## Service Registration and Lookup

### Namespace-aware Storage

Keep storage calls behind a Service Contract with typed methods such as
`setString`, `setInt`, `setBool`, and `setJson`. Low-level Backend and migration
code may pass a controlled namespace value (`global`, `guest`, `user(accountId)`,
`apiEnvironment(environmentId)`, or `hardware(deviceId)`); ordinary business code
should use a Scoped Facade that resolves these values from a Host-owned context
provider. The same key in different namespaces must remain isolated.

The Service should depend on an application-defined backend interface (for
example `StorageBackend`, not a built-in CCRouter API); a memory Fake is useful
for deterministic tests. Persistent or secure implementations belong to
the Host/Composition Root and must define serialization, encryption, migration,
logout cleanup, and environment-switch behavior explicitly. Namespace selection is
not an access-control or encryption mechanism, and raw storage values must not be
written to framework diagnostics.

Use `@CCService` for a simple Service with an unnamed zero-argument generative
constructor. Package ownership is inferred from the sole `CCComponent`:

```dart
@CCService(
  id: 'cart.repository',
  scope: CCServiceScope.session,
)
final class CartRepository {
  CartRepository();
}
```

For a promoted contract, declare the interface in a Pure Dart contracts
Package and explicitly identify the implementation component:

<!-- verified-example: service-contract -->
```dart
final class CartSummaryValue<T extends Object> {
  const CartSummaryValue(this.value);

  final T value;
}

@CCServiceContract(
  componentId: cartComponentId,
  id: 'cart.summary',
  alias: 'cartSummary',
  description: 'Reads a display-safe cart summary.',
)
abstract interface class CartSummaryService {
  String summary();

  T unwrap<T extends Object>(CartSummaryValue<T> value);
}
```

The Contract interface itself remains non-generic. A method may declare its own
generic parameters when one operation must preserve a caller's static Pure Dart
type. The generated Proxy reproduces every bound and explicitly forwards type
arguments, including for zero-argument methods. This is a local typed component
boundary, not a serialization mechanism; generic arguments must not be used to
smuggle Flutter objects, callbacks, Streams, or private implementation types
through a public Contract.

Business parameter and generic names such as `service` remain valid: generated
callback receivers and import prefixes are allocated outside those names.
Route and Proxy collection defaults retain their actual generic types, including
empty Sets behind an Object parameter. Types appearing only in defaults must
also be publicly importable; private enums are rejected during generation.
Catalog descriptions remain literal text when emitted into Host DevTools Dart;
the generator owns Dart interpolation escaping, not the component author.
Dependency preflight resolves owners within actual Library import/export scopes,
including show/hide. Unavailable external namespaces, parts and conditional edges
defer to Builder; an early report can contain fewer owners than final validation.

Export the interface and its public value types from the business contracts barrel. Bind a simple
implementation by directly implementing exactly one contract:

<!-- verified-example: service-implementation -->
```dart
@CCService()
final class CartSummaryServiceImpl implements CartSummaryService {
  const CartSummaryServiceImpl();

  @override
  String summary() => '...';

  @override
  T unwrap<T extends Object>(CartSummaryValue<T> value) => value.value;
}
```

The consuming component declares the exact cross-component capability and
keeps its owner in required component dependencies:

```dart
const checkoutComponent = CCComponent(
  id: checkoutComponentId,
  version: '1.0.0',
  dependencies: [cartComponentId],
  serviceDependencies: [
    CCServiceDependency<CartSummaryService>(),
  ],
);
```

When the required owner is omitted, the optional Analyzer Plugin reports the
Metadata-proven mismatch during editing. Apply its dependency Quick Fix only
when it offers the exact owner constant through an existing public import; for
one component whose every missing Owner is provable, the additional batch fix
may add all owners in stable order. For computed lists or absent/ambiguous
exports, edit the descriptor deliberately and rely on
`ccrouter generate --check` as the final gate.

After generation, call the component-specific Client:

```dart
final summary = CheckoutServices.cartSummary.summary();
```

The generated member name uses the consumer's `CCServiceDependency.alias`,
then `CCServiceContract.alias`, then the contract type name without a trailing
`Service`. Use the Contract alias for one shared domain name and a Dependency
alias only for a keyed or consumer-specific override. Alias changes alter the
generated source shape and require Contract versioning plus regeneration.

Do not handwrite a Proxy or pass caller component IDs. The generated Proxy is
stateless and resolves the current Scope on every method call. Keep local
Services on `CCRouter.service<T>()`; only stable cross-component contracts need
`CCServiceDependency<T>`.

Generation validates the declared consumer graph, and Runtime repeats the
identity/dependency check against the installed Manifests before invoking the
Provider. A stale generated Client, missing component, or handwritten bridge
call without the required dependency fails with `CCResolutionError` before
Service work or attributed Trace recording begins.

Do not export or pass the generated Token in business code. Generator and
Runtime retain its stable ID for ownership, diagnostics, and package moves.

Use `@CCComponentContribution` and a handwritten Provider for custom
construction, constructor injection, or lazy async readiness:

```dart
@CCComponentContribution(id: 'cart.services')
void registerCartServices(CCRegistry registry) {
  registry.registerService<CartRepository>(
    CCServiceProvider(
      scope: CCServiceScope.session,
      factory: (_) => CartRepositoryImpl(),
    ),
  );
}

final repository = CCRouter.service<CartRepository>();
```

If a promoted Service needs constructor injection or an async initializer, the
implementation Package may expose the generated Token only from a separate
owner-only SPI barrel and attach it to the handwritten Provider:

```dart
registry.registerService<CartSummaryService>(
  CCServiceProvider(
    contractToken: cartSummaryServiceToken,
    factory: (_) => CartSummaryServiceImpl(database),
    initializer: (service, context) => service.open(context.cancellation),
  ),
);
```

This is Component-author SPI, not a business lookup pattern. Component-internal
code may use `CCRouter.service<CartSummaryService>()`; cross-component consumers
still call their generated `CheckoutServices.cartSummary` and never import the
owner-only SPI barrel. The injected implementation in this alternative must
define the shown constructor and `open` method; it replaces simple annotated
registration rather than adding a second Provider for the same capability.

For lazy async readiness:

```dart
@CCComponentContribution(id: 'configuration.services')
void registerConfigurationServices(CCRegistry registry) {
  registry.registerService<RemoteConfig>(
    CCServiceProvider(
      factory: (_) => RemoteConfig(),
      initializer: (service, context) async {
        await service.load(context.cancellation);
      },
    ),
  );
}

final config = await CCRouter.serviceAsync<RemoteConfig>();
```

Singleton readiness is single-flight within its owning Scope. Runtime tracks
active initializer dependencies, including independent concurrent roots, and
rejects cycles with `CCCircularServiceDependencyError`. A caller's timeout or
cancellation removes only its wait; other callers can still receive the shared
instance. A failed initializer remains failed for that Scope. Resolve the
dependency cycle or handle retry inside the initializer instead of polling
`serviceAsync` to restart failed work.

Resolve Route Service only from the exact managed page Context:

```dart
final draft = CCRouter.routeService<DraftController>(context);
```

Initial/foreign pages do not have a managed Route Scope. Never guess from the top route.

## Command and Event

```dart
@CCCommandContract(
  id: 'orders.submit',
  alias: 'submit',
  description: 'Submit one order.',
)
final class SubmitOrderCommand implements CCCommand<String> {
  const SubmitOrderCommand(this.id);
  final String id;
}

@CCCommandHandler()
Future<String> handleSubmitOrder(
  SubmitOrderCommand command,
  CCInvocationContext context,
) async {
  if (context.cancellation.isCancelled) {
    throw const CCInvocationCancelledError();
  }
  return submit(command.id);
}

final receipt = await OrdersCommands.submit(
  const SubmitOrderCommand('42'),
);
```

An implementation-Package Command may omit `componentId`; generation infers
the sole `CCComponent`, installs the Handler, and emits the Owner Client. A
cross-component Contract declares `componentId` in a contracts Package, while
each consumer lists `CCCommandDependency<SubmitOrderCommand>()` and the Owner
in required `dependencies`. Do not pass stable IDs or caller identities by
hand. Keep raw `CCRouter.command` for unannotated migration capabilities, Host
composition, and tests only.

Command methods use `CCCommandDependency.alias`, then
`CCCommandContract.alias`, then the Command type name without a trailing
`Command`. Keep the generated Client component-specific; do not replace it with
a global namespace Facade that would erase caller attribution.

```dart
@CCEventContract(id: 'orders.submitted', description: 'Order was submitted.')
final class OrderSubmittedEvent implements CCEvent {
  const OrderSubmittedEvent(this.id);
  final String id;
}

@CCEventSubscription(id: 'analytics.order-submitted')
Future<void> trackOrderSubmitted(
  OrderSubmittedEvent event,
  CCInvocationContext context,
) => analytics.track(event.id);

await OrdersEvents.publishOrderSubmitted(
  const OrderSubmittedEvent('42'),
);
```

Generation infers an implementation-Package Event owner, installs static
Subscribers, and emits the Owner publication Client. A shared contracts Package
declares `componentId` explicitly. A Subscriber component must declare the Owner
as a required or optional component dependency. Omit the Subscriber ID only for
the sole Subscriber to one Event in that component; multiple Subscribers must
all have distinct explicit IDs. Keep raw `CCRouter.event` and handwritten typed
Subscriber registration for unannotated migration capabilities, Host
composition, and low-level tests only.

Generated Command callers and Event publishers are not trusted as raw strings.
Runtime verifies that they are installed and that Command consumers or Event
subscribers have the required dependency edge to the capability Owner. Required
dependencies apply to Command and Service consumption; Event subscriptions may
use a required or optional dependency. A mismatch fails before Handler or
Subscriber execution.

To bridge framework observations to application logging, configure a Host-owned
`CCDiagnosticSink` through `CCDiagnosticsConfig`. The sink is asynchronous,
bounded, and observational; sink errors never alter Command, Event, Service,
navigation, or InitTask results. Category policies can disable, raise the
minimum level, or sample external delivery without disabling internal bounded
traces. Forward only the sanitized fields in `CCDiagnosticEvent`; do not add
raw URI, arguments, Extra, tokens, widgets, backend objects, exception text, or
business result data. `CCRouter.traceBundle(traceId)` is a bounded troubleshooting
view, not an audit log or replay source.

The Runtime emits `componentGraph`, `componentRegistration`, and
`runtimeInitialize` through the initialization diagnostic category. Their
`started` events use debug level, while terminal success and failure use info
and error. A Host that needs the complete startup sequence must enable debug
delivery instead of reproducing component lifecycle logging in its bootstrap.

## Analytics delivery

Keep product analytics separate from framework diagnostics. The application owns
the `CCAnalyticsEventDispatcher`, consent transitions, and vendor sinks. Use
validated primitive properties; supported String/num lists are copied into
immutable snapshots when each `CCAnalyticsProperty` is constructed. Neither the
caller nor a sink may mutate queued values.

Property values are bounded (256 characters per String, 32 list items, 64
properties and 4096 conservative value units per event), numbers must be finite,
and blacklist/throttle state is bounded. Construction rejects violations before
an event can affect a business callback.

`dispatch` accepts into a bounded queue; even the first sink starts on a later
event-loop turn. Sampling, blacklist, and throttle apply at admission. Revoking
consent or disabling delivery clears pending events and invalidates remaining
sinks of the active event. Immediate re-grant only permits new events; it cannot
resume old delivery. Already-running writes require application-level cancellation
if the vendor supports it.

The owning Composition Root must await `close()` to stop admission and finish
scheduled/in-flight delivery. By default this waits for application Sink writes.
An optional `sinkWriteTimeout` quarantines a Sink after a deadline and bounds
dispatcher close; the underlying Dart Future cannot be cancelled, so the Sink
must provide its own cancellation and will receive no further events. Do not
await close from a sink's own `write`, because it waits for the same write.
Async dispatch is not isolate offloading: keep synchronous sink work short. Widget tests must advance the event loop
(for example, `tester.pump(Duration.zero)`) before asserting sink delivery;
flushing microtasks alone does not run scheduled timers.

`dispatcher.snapshot` provides payload-free per-Sink success, failure, timeout,
quarantine, and cumulative duration counters in configured order. It is suitable
for a health panel or benchmark only; it cannot prove durable upload and is not
an audit or replay record.

`CCAnalyticsExposureTarget` binds ancestor ScrollPositions and clips measurements
to their paint bounds. It cancels dwell on revoke, background, or detach, and
restarts after grant/resume without a business rebuild. `once` counts dispatcher
admission, not successful delivery. Sampling/blacklist/throttle rejection is one
attempt per episode; do not poll until sampling eventually succeeds. Arbitrary
Overlay occlusion and opacity are outside this geometric approximation.

When several targets share a page or feature context, wrap that subtree in
`CCAnalyticsScope` from `ccrouter_analytics_flutter`. The root Scope receives
the application-owned Dispatcher; nested Scopes may add stable context fields
or disable their subtree. `trackerOf` returns a value tracker and the Scope
never closes the Dispatcher or guesses Route/Foreign Popup attribution. Keep
the explicit Target callback path for any action whose business success must be
known.

`CCNavigationAnalyticsBridge` creates one bounded visit instance per managed
Arrival/Show and adds total/foreground dwell to its Hide event. Forward Host
application lifecycle transitions to `onForeground` and `onBackground`; these
methods do not emit PageShow/PageHide. Call `dispose()` when the Host releases
the bridge. Consent-denied observations do not retain a visit.

Custom integrations may observe `addPolicyListener` without receiving payloads.
Read `policy/isClosed` for current state, keep the synchronous callback short,
never update policy from it, and call the returned remover on detach. Callback
exceptions are isolated; dispatcher close clears its observers. Ordinary targets
already own this subscription, so applications need no additional listener.

For nested resources, the registered Service must implement `CCDisposable` and
forward disposal to its client/transport. Scope cannot discover arbitrary fields.
The Demo Network Service illustrates shared asynchronous disposal, cleared token
and logs, and suppression of late log callbacks; use a Fake Backend to verify
Scope shutdown waits for closure and that a failure does not retain credentials.

## Initialization

Keep initialization identifiers in one component-owned constants class. Do not
repeat task or Gate strings across Registrar, Host, pages, and tests. If a Host
or another component must open or depend on an identifier, publish that
identifier from a contracts library instead of importing the implementation
Registrar or a `src` path. Stable IDs should use a component or capability
prefix and remain unchanged after ordinary refactors.

Declare task dependency targets as top-level constants and let generation install
the Handler into the component Registrar:

Use the framework-provided `CCInitTaskGate.privacyGranted` for work that
must wait for explicit privacy consent. The Host owns consent state and opens
the gate; CCRouter does not inspect or persist that state. Define a custom
`CCInitTaskGate` only for a different product condition.

```dart
const configLoadInitTask = CCInitTaskContract(
  id: 'config.load',
  description: 'Loads the configuration required by startup SDKs.',
);

@CCInitTask(
  contract: configLoadInitTask,
  gate: CCInitTaskGate.appStarted,
  failurePolicy: CCInitTaskFailurePolicy.required,
  timeout: Duration(seconds: 3),
)
Future<void> loadConfiguration() async {}

@CCInitTask(
  id: 'analytics.initialize',
  gate: CCInitTaskGate.privacyGranted,
  dependsOn: [configLoadInitTask],
  failurePolicy: CCInitTaskFailurePolicy.optional,
  timeout: Duration(seconds: 3),
)
Future<void> initializeAnalytics(CCInvocationContext context) =>
    analytics.initialize(context.cancellation);

final initResult = await CCRouterHost.runInitTasks(
  gate: CCInitTaskGate.privacyGranted,
);
// Use only when this Host deliberately cannot start in degraded mode.
// initResult.throwIfRequiredFailed();
```

`CCRouterHost.initialize` creates the process-default Runtime and pairs with the
Composition Root's awaited `CCRouterHost.shutdown`. Do not call `shutdown` from a
Widget, Page, component, Session, or individual navigation Host disposal.
`runInitTasks` opens a `CCInitTaskGate` and drains zero or more newly ready
tasks; it does not initialize or replace the Runtime a second time, select one
specific task, or retry a task that already completed or failed. The Gate is a
required argument in the Facade, Runtime, annotation, and handwritten
definition. CLI scaffolds write `CCInitTaskGate.appStarted` explicitly.

Every declaration must choose `required` or `optional` explicitly. Business
failures are returned in `CCInitTaskRunResult`, recorded in snapshots and
diagnostics, and skip only dependent branches. Ignoring the result after
`await` remains valid for an application that can start in degraded mode. Call
`throwIfRequiredFailed()` only from a Composition Root that intentionally uses
fail-fast startup; Runtime shutdown, cancellation, and invalid lifecycle state
still throw directly.

Overlapping Gate calls share one single-flight DAG drain. If a second Gate opens
while a layer is running, Runtime performs another readiness pass before the
shared Future completes, so newly ready tasks cannot remain pending until an
unrelated later call.

Use `contract` for every task that another task references and `id` only for an
independent internal task. A cross-component Contract belongs in a public Pure
Dart contracts Package and names its `componentId`; the dependent component
must require the Owner. The generator installs registration bridges, validates
the complete DAG, rejects required tasks without a Contract, rejects async
required Handlers without a positive timeout, and prevents required tasks from
depending directly or indirectly on optional tasks. It emits source locations
and an `Initialization DAG` catalog,
and generates no business task Client. Keep handwritten
`registerInitTask` calls for unannotated migration or low-level Host
extensions only.

## Generation

Run one orchestration command after annotations or component graph changes:

```bash
fvm dart run ccrouter_generator:ccrouter generate demo
```

The selected Package is the `requestedRoot`; the Package or Pub Workspace that
owns dependency resolution, build cache, and generation locks is the
`resolutionRoot`. A member declaring `resolution: workspace` uses Pub's
validated workspace reference. A stale reference is repaired with Pub get and
must not fall through to an arbitrary ancestor Package graph. A standalone
Package nested below a Workspace remains its own resolution root.

The command owns files under `lib/src/ccrouter_generated/`. Do not edit or
relocate generated outputs. A Host's handwritten public barrel may re-export
the generated `src/ccrouter_generated/ccrouter_host.api.g.dart`; do not point it
at implementation-only files under `host/` or repeat the generated `show` list.
Component Packages export only their intended stable component API. Contracts
Packages re-export the stable `<package>.contracts.api.g.dart` Route Consumer entry with
an explicit `show` list and separately export intended authored contracts. The
CLI bootstraps a missing stable Route entry after `clean`, so authored code must
not create or edit a placeholder by hand.

An unchanged command may report a generation fast-path hit. This is valid only
after exact authored-input, tool, resolved-Package, external-index, and managed-
output fingerprints match a previous successful run. Use `--no-cache --check`
when validating the reference path after generator, SDK, or build configuration
changes; do not make application code depend on cache or manifest files.

With `--output-dir`, check and failure rollback explicitly cover `cc_routes.json`,
`cc_catalog.md`, and the migrated `cc_routes.md`/`cc_sources.md`, even under docs
or build. Other files in that directory are not managed. `--check` still rejects
output outside the Workspace/Package build root before writing.

After a fast-path miss, the CLI may report direct, uniquely provable missing
Service/Command owners before build_runner. This conservative preflight declines
computed or ambiguous inputs and does not replace the Builder/Workspace
Validator. A failed formal generation restores the previous CCRouter-managed
source outputs instead of leaving a partially updated API graph.

Use `--profile` when diagnosing a miss. `build-targets` is the writable Host
dependency closure sent to build_runner; `dirty-packages` is computed afterwards
from metadata, managed output, direct dependency indexes, and reverse dependency
propagation. A small dirty set therefore does not imply that Workspace Analyzer
startup should be proportional to that count.

Profile output includes a schema `1` `CCRouter profile trace=<json>` line and an
atomic latest report under
`.dart_tool/ccrouter/v1/profiles/<host-identity>/latest.json`. Each span contains
`name`, monotonic `startUs`, `durationUs`, `status`, and optional bounded counts.
It covers lock wait/release, fingerprints and Build Plan, Portable State checks,
preflight, snapshot protection, build_runner, validation, aggregation, check
restore, and local planning-state writes. It contains no absolute paths, source
text, or business values. Profile mode also enables build_runner's supported
`--verbose-durations` output for Builder phase details. Treat that upstream text
as human diagnostics rather than part of the CCRouter JSON schema. Do not commit
profile reports or use timing values as generation or CI correctness inputs.

`input-delta` compares existing exact-content Build Plan facts with the last
successful local baseline. `authored` means the Package's own source/config
changed; `resolutionOnly` means unchanged own input but changed dependency
resolution identity. It does not identify a proven causal edge or permit pruning
dependencies. Missing either authored digest is `authoredUnavailable`, never
proof of equal source. A missing/untrusted baseline or forced reference path reports
`unavailable`. `output-delta` reports exact added/removed/modified counts for Dart,
metadata JSON, Markdown and portable state, before `--check` restores originals.
Equal Dart does not imply equal docs or source locations. A changed state file
does not imply a changed business API. Names are bounded to 12 per group while
counts remain complete; source values are never emitted. Diagnostics are opt-in
via `--profile`, do not change cache decisions, and keep extra output comparison
time separate as `output-delta-scan`.
Input attribution follows the existing Build Plan scope: custom `--output-dir`
does not provide `input-delta`.

Generation entrypoints share correctness semantics only where their ownership
scope overlaps. A manual Host one-shot and a no-watch Pub Hook both enter the
same generation kernel. A Host watch keeps build_runner resident, then invokes
that kernel for validation, aggregation, barriers, rollback protection, and
local state publication without repeating Builder work. An active-watch Pub
Hook waits for exact Host resolution evidence or exact per-Package input/output
evidence; it does not independently regenerate and compare a second result.
Package-local generation intentionally omits Host assembly and Host-wide
validation. Compare byte snapshots and structured diagnostics for correctness,
but report one-shot, watch, Hook wait, and Analyzer latency separately.

The Analyzer Plugin is a fail-open observer, not another generation entrypoint.
Its component alias graph is enabled by default and must remain result-equivalent
to the repeated-scan reference. Tiered exact-path polling is different: it is
off by default, enabled only with `CCROUTER_ENABLE_ANALYZER_TIERED_POLL=1` before
the Analysis Server starts, and trades a smaller per-tick scan for a five-second
worst-case missed-event fallback. Terminal correctness remains the Host
`--no-cache --check` result regardless of Analyzer availability or timing.

For iterative local work, `generate <host-root> --watch=auto --machine` keeps
build_runner's AOT entrypoint and Analyzer graph alive for one resolved build
root. Its stdout is schema `1` NDJSON; `buildSucceeded` only closes the Builder
phase, while `aggregationSucceeded` closes CCRouter validation and atomic
publication. `ready` means the initial cycle completed. Builder diagnostics stay
on stderr. Default events retain final build and aggregation timings; add
`--profile` explicitly for benchmarks or slow-run diagnosis when the complete
cycle trace and build_runner verbose durations are needed.
Different Hosts in the same resolved build root register with one Builder owner,
which watches their target union. Each Host still owns its aggregation,
validation, lease, status, diagnostics, and input revision; `builderOwnerPid`
can differ from the Host process `pid`. A live subscriber takes over after the
owner exits. A second watch for the same Host fails before status publication.
Hook-managed concurrent `flutter run` sessions are a narrower case: they create
one heartbeat lease per run and attach those leases to the existing Host watch,
instead of starting a second writer. The watch survives individual run exits and
stops only after its last valid lease disappears. A registration loser never
publishes Host status; it waits for an exact attachment acknowledgement or
retries after the exiting owner releases registration.
Hosts with distinct Pub roots remain independent. Use
`CCROUTER_DISABLE_MULTI_HOST_WATCH=1` only to compare the former exclusive-root
behavior. Subscriber departure keeps the current target superset to avoid a
restart; actual Pub target removal still rotates the child session.
`buildSucceeded.buildRunner` uses `formatVersion: 2`. The default unprofiled
event reports `available: false` instead of zero counters. With `--profile` it
reports structured per-phase duration, inputs, skipped/not-triggered, inferred
invalidated inputs, executed inputs, new/same/no-op outputs, and thresholded activities. These are
diagnostic public-counter interpretations, not private Asset Graph access or a
generation decision input. Unknown terminal formats are retained in bounded
`unparsedFinalLines` without failing generation. `flutter run` obtains the same
watch through a Dart-supervisor-owned lease under the project/Host-isolated
`CCROUTER_HOME` coordination directory;
`flutter build` stays one-shot. Use `CCROUTER_DISABLE_BUILD_WATCH=1` to fall
back. The active watch holds the build root generation lock; stop it before
running the final authoritative `--no-cache --check`.
The POSIX and Windows wrappers consume known global-option values before
selecting the first real Flutter/Dart command and the first real Pub subcommand.
They never scan arbitrary values or trailing business arguments for command
names; an unknown option with unproven arity bypasses the Hook and remains the
original CLI's responsibility.
Before the original Flutter Tool starts, the wrapper waits for `sessionReady`
from either its primary watch lease or a watch-PID-bound acknowledgement that
the active Host watch accepted that exact lease, and confirms that the build-root
owner lock is still held. A process ID or `starting` line alone is not readiness. Entrypoint
startup, ownership conflict, initial generation failure, exit, and timeout all
fail closed with the watch log path. Use
`CCROUTER_DISABLE_WATCH_STARTUP_HANDSHAKE=1` only for an isolated A/B fallback;
it does not disable preflight, watch, generation locking, or reload gating.
Wrapper-started watches keep stable ownership, serialization, and Flutter-run
leases under the user-level `CCROUTER_HOME`, isolated first by canonical build
root and then by Host. Minimal Host/Builder session authority lets Pub Hook coordinate even when
project-local observation files were removed. Watches atomically publish and
repair the Analyzer/IDE mirror at `.dart_tool/ccrouter/v1/watch/status.json`.
If `CCROUTER_HOME` is unwritable or is not a directory, the CLI reports the
exact failed target and asks for an absolute writable directory without exposing
an internal Dart stack trace.
Use read-only
`watch status <host-root>` for a snapshot or `watch follow <host-root>` for
concise state changes; keep complete diagnostics in `watch/flutter-run.log`
instead of injecting watch NDJSON into Flutter Tool's machine stdout. This
wrapper prints its pre-Flutter starting and ready summaries to stdout so IDEs
do not render it as an error; failures remain on stderr. The stdin gate closes
the original Flutter Tool's stdin when its IDE/AI parent reaches EOF, preserving
the direct process lifecycle instead of retaining an orphaned child. On POSIX
and Windows, one terminal-inheriting Dart supervisor owns each run's versioned
lease heartbeat for both machine and interactive runs, while a detached
coordinator keeps redirected watch output independent of any single supervisor.
Handled exits delete only that run's lease; if a supervisor is force-killed,
watch expires its heartbeat. The shared watch stops after its last lease expires.
During Flutter child supervision, a handled signal removes the lease before
reaching the child; closing a lease during its initial write cannot leave a
heartbeat timer running.
`CCROUTER_DISABLE_WINDOWS_RUN_SUPERVISOR=1` restores the former batch-only
lifecycle for A/B comparison. This status channel is fail-open for direct
generation and never changes locking,
validation, artifact restoration, or atomic publication. The Hook still fails
closed when this channel cannot prove that the ready watch accepted its exact
lease. If an abrupt
exit leaves an `active` record, the read-only commands report it as `stale`
after the owner lock is released without rewriting the historical status file.
Analyzer `install/upgrade/uninstall` uses that same canonical build-root identity
for one Workspace-wide operation lock and a fail-closed byte-preserving recovery
journal. Both live under the stable project coordination directory, so project
cleanup cannot silently permit a second writer or erase recovery evidence. The
legacy coordination kill switch moves both back under `.dart_tool` only for A/B;
an active lock in the other protocol makes the command fail fast.
Ordinary `generate` and `generate --check` commands encountering the root watch
lock wait for a successful cycle and validate exact current Pub resolution,
authored inputs, and managed outputs. A match reuses the cycle without starting
a second writer; watch failure, exit, missing evidence, or the bounded timeout
stays fail-closed. `--no-cache`, `--profile`, custom output, portable prepare,
and clean still fail fast because their semantics require an independent path.
Set `CCROUTER_DISABLE_ONE_SHOT_WATCH_REUSE=1` only for reject-only A/B. Stop the
watch before the final reference gate. Watch startup also fails fast while a
one-shot command owns or awaits that root.
The installed Flutter wrapper likewise fail-fast guards a real top-level
`flutter clean` while the build root has an active watch. Stop the run/watch
first; do not rely on the recovery-only
`CCROUTER_DISABLE_FLUTTER_CLEAN_GUARD=1` bypass during normal development.
If bypassed clean persistently removes build-root Pub/build_runner state, watch
publishes `invalidatedByClean`, performs bounded child shutdown, and releases
its stable locks. Restore Pub state and start a new watch instead of waiting for
in-place recovery.
After a successful hooked Pub dependency command, the same-Host Hook performs
that coordination itself: it fences on exact current resolution-file contents
and waits for the active watch's terminal aggregation event. Success reuses
that cycle. A monotonic `eventRevision` within one `sessionId` rejects historical
failures; a new failure after resolution churn returns immediately with bounded
diagnostics and requires a new cycle/session. Success never accepts a mismatched
resolution fingerprint. This Hook fence is narrower than manual one-shot reuse,
which additionally proves current authored and managed-output bytes. Set
`CCROUTER_DISABLE_PUB_HOOK_WATCH_FAILURE_FENCE=1` only to compare the legacy
fingerprint-only failure wait. Exit, unavailable state, or timeout stays
fail-closed. Neither path permits concurrent generation writers.
Package-local Pub in the same build root may reuse a Host watch only with
versioned per-target evidence. The successful cycle publishes exact Pub
resolution, authored-input, and managed-output fingerprints; the Hook
recomputes current Package bytes and accepts only a complete match under the
live owner lock. Evidence is cleared when the next build/resolution cycle
starts. Missing targets, legacy evidence, failures, timeout, and mismatches stay
fail-closed without starting a conflicting one-shot. Use
`CCROUTER_DISABLE_PACKAGE_WATCH_REUSE=1` for the former reject-only A/B path.
Stale, malformed, and wrong-root status remain untrusted.
The watch also polls cheap resolution file stats and confirms every candidate
with an exact-content fingerprint; a low-frequency exact scan covers missed
wakeups. Covered resolution-only changes publish `resolutionStarted` and run
aggregation without pretending Builder ran. A new closure Package, changed
Builder target/filter set, or child exit after an exact resolution change
publishes `sessionRestarting`, restores the current artifact snapshot, and
starts a new child under the same lock/lease. Consumers must wait for the new
session's `ready`. `CCROUTER_DISABLE_WATCH_SESSION_RESTART=1` makes this path
fail closed so a stopped-watch one-shot can serve as the reference.
Child shutdown is bounded: SIGINT gets 10 seconds, SIGTERM gets 5 seconds, and
the final SIGKILL wait is capped at 5 seconds. This preserves graceful cleanup
without allowing a stuck child to retain session restart or the generation lock.
Shutdown may arrive before a new child session reaches `ready` or reads its
first queued signal. The internal signal subscription must still be canceled
and its controller closed without retaining the generation lock.
After a successful Builder cycle, watch skips only the ordinary fast-path and
Build Plan decision that can no longer change whether Builder runs. Input
fingerprints and barriers, dependency preflight, artifact snapshots, Workspace
validation, aggregation, atomic publication, and local state writes remain.
Set `CCROUTER_DISABLE_WATCH_CYCLE_OPTIMIZATION=1` to restore the reference cycle
for byte-for-byte comparison without turning off watch.
The aggregation cycle reuses the watch process and reports
`aggregationSucceeded.cycleMode=inProcess`. For differential diagnosis,
`CCROUTER_DISABLE_WATCH_IN_PROCESS_CYCLE=1` restores the
`subprocessReference` implementation; compare all managed artifact bytes and
still finish with `--no-cache --check`.
The source/output/kernel/preflight batch file reads share an isolate-local budget
of four concurrent exact-byte reads. Use
`CCROUTER_DISABLE_PARALLEL_FILE_READS=1` for the sequential A/B path; restart
active watch processes for the environment change to take effect. Captures
retain deterministic logical order and wait for in-flight reads to settle on
failure before returning to restoration. There is no cross-cycle byte cache;
every input barrier and restore scan still reads its own current filesystem
evidence. Measure full commands and watch cycles separately from read/hash
microbenchmarks; Analyzer Plugin I/O is outside this optimization.

Successful cycles reuse one exact-content planning snapshot for the local
fast-path manifest and Build Plan state. Set
`CCROUTER_DISABLE_SHARED_PLANNING_SNAPSHOT=1` to restore separate scans for
byte-for-byte or timing A/B; input barriers, validation, restoration, atomic
writes, and the final `--no-cache --check` remain unchanged.
The one-shot and watch kernels also form unified epoch evidence from the final
input barrier plus exact output bytes already read for output delta or metadata
cache publication. Set `CCROUTER_DISABLE_UNIFIED_EPOCH_SNAPSHOT=1` to restore
full planning recapture. Entry rollback snapshots, every input barrier,
restore-time scans, byte comparisons, and the final reference gate remain
independent correctness boundaries.
For one-shot build_runner execution, the entry rollback snapshot may also
derive the build-root non-target protection view. External read-only Packages
remain separately captured and post-Builder restore still rescans current
files. `CCROUTER_DISABLE_SHARED_BUILD_PROTECTION_SNAPSHOT=1` restores the full
second scan; build filters alone never establish non-target integrity.
The final watch input barrier returns its exact snapshot to planning-state
publication instead of discarding and immediately recapturing it. On an
aggregation reuse hit, the entry artifact snapshot supplies only verified
aggregation-owned bytes; current Builder-owned outputs are still read from
disk. `planning-snapshot-capture.attributes.evidenceMode` exposes the selected
path. Set `CCROUTER_DISABLE_WATCH_EVIDENCE_REUSE=1` for full recapture without
removing barriers, validation, atomic publication, or the final reference gate.
The post-cycle output-delta scan also provides its exact current managed-output
bytes to planning publication, avoiding a second output scan. Profile reports
`input-and-current-output`; set
`CCROUTER_DISABLE_WATCH_OUTPUT_EVIDENCE_REUSE=1` to isolate this optimization
while retaining the input and aggregation evidence paths.
Profile traces may carry an `aggregation-input-fingerprint` span with a SHA-256
`attributes.fingerprint` for Builder metadata, Package indexes, and Host graph
inputs. It never authorizes skipping Builder. After Builder succeeds, matching
Tool/input identities plus exact aggregation-owned output bytes can skip only
aggregation rendering and writes. Package verification, graph/index
construction, Workspace validation, artifact restoration, and both input
barriers remain. The proof is disposable local `.dart_tool` state; missing,
invalid, tampered, or metadata-cache-corrupted state fails closed; a corrupted
metadata cache is rebuilt by that full path. Use
`CCROUTER_DISABLE_AGGREGATION_REUSE=1` for the full-aggregation A/B path and
retain `--no-cache --check` as the authoritative reference.

The Build Plan separately reports `suggested` and `actual`. Only
`actual=aggregateOnly` means build_runner was skipped, and that optimization is
limited to a pure Host Package removal with every remaining input unchanged, or
a pure Package addition where every added Package has a verified committed
Portable Generation State. Writable unproven additions execute the full Builder
path; read-only external Packages with missing or stale state fail explicitly.
Use `CCROUTER_DISABLE_AGGREGATE_ONLY=1` for an immediate local fallback and
retain `--no-cache --check` as the authoritative CI gate. Commit
`lib/src/ccrouter_generated/metadata/ccrouter_generation_state.json`; the state
under `.dart_tool/ccrouter/v1/build_plans/` remains disposable local data.

Portable proofs exclude the component's own eventual Git/archive identity and
the producer's development-only dependency closure. Exact source and runtime
dependency content plus the generator toolchain still have to match. Consumers
do not need the producer's unrelated test dependencies, and cannot repair stale
read-only artifacts. The fast path recomputes the same external source and
resolution identities as full verification and reads every external managed
output, including when checking mutable transitive Path DTO dependencies.
Do not remove or rewrite the state to suppress a mismatch; regenerate in the
owning Package and distribute a complete, verified artifact set.

After `ccrouter clean`, generation may temporarily bootstrap missing component
Route, Command, and Event APIs from valid Builder metadata before build_runner.
This only repairs the import graph for the same build pass: current metadata is
still rebuilt and every final artifact is regenerated and validated.
Clean and generation ownership stop at a nested `pubspec.yaml`. A component's
independently runnable `example/` Host keeps its generated bytes when the parent
component or another Host is cleaned or regenerated; run commands against the
example root to manage that Host.

Packages with no generated capability have no `ccrouter_generated` directory.
Removing the final declaration removes empty managed directories while
preserving unknown or handwritten files.
