# Implementation Patterns

## Package Roles

### Host

The Host may import `ccrouter_go_router` and `ccrouter_host.dart`. A new GoRouter
application should first call
`CCRouter.initialize(hostAssembly: ccrouterGeneratedHostAssembly)` and then use
`const CCGoRouterApp()` for the minimal Host assembly path. The widget resolves
the exact Catalog retained from initialization through a Host-only Binding; do
not repeat the Catalog argument or expose it through the business Facade. The
generated stable Host barrel exports only the atomic Assembly.
`CCGoRouterApp` never initializes or shuts down the process Runtime. The Host
owns generated Host assembly, navigation Backend,
Shell/Outlet topology, platform Deep Link ingress, global policies and final
`CCRouter.shutdown`.

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

```dart
final hostAssembly = CCHostAssembly.fromComponents(
  components: [ordersManifest, accountManifest],
  routeCatalog: applicationRouteCatalog,
);
CCRouter.initialize(hostAssembly: hostAssembly);
```

Do not pass loose component or Contract collections to `CCRouter.initialize`;
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

Use `CCGoRouterApp.backendFactory` when the application needs custom Shell,
redirect, refresh, or Router construction but can retain the standard Material
application wrapper. The factory receives immutable configuration and is called
once. Use `CCRouterApp.managed` with a manually created `CCRouterAppBackend`
only for a fully custom application tree. Use
`CCGoRouterBackend.attach` for an existing application-owned GoRouter; the
minimal widget is not an attach replacement and never disposes an external
Router.

Feature packages must not perform these duties.

### CLI Scaffolding

For the complete implemented command matrix and AI-assisted fallback workflows
for deferred CLI 2.0 capabilities, read
[`ccrouter-cli-development`](../../ccrouter-cli-development/SKILL.md). Use the
fallback only when no existing command covers the operation; it must produce a
dry-run summary before changing Contracts, dependencies, or public exposure.

If automatic generation after dependency resolution is desired, install the
explicit per-SDK `pub-hook` documented in
[`CCRouter-cli-pub-hook.md`](../../../docs/CCRouter-cli-pub-hook.md). Do not
modify Flutter internals manually. The hook covers successful `flutter pub`
commands and runs a fail-closed preflight before `flutter run/build`; direct
`dart pub` and Flutter Tool's internal implicit `pub get` remain outside its
boundary.

Use the generator CLI to create a new component Package or an internal Route
page when starting a feature:

```bash
fvm dart run ccrouter_generator:ccrouter create component catalog demo/modules
fvm dart run ccrouter_generator:ccrouter create page ProductPage demo/modules/catalog
```

The command creates only missing authored files and fails before writing when a
target already exists. Run Pub resolution and `ccrouter generate` afterwards;
the scaffold never edits Host dependencies or generated output. Treat the page
as component-internal by default and create a Pure Dart Route Contract only
after a real cross-component consumer appears.

Capability scaffolds follow the same internal-first rule. A Service starts as
one concrete `@CCService(id: ...)`, an Event does not assume a local Subscriber,
and an independent InitTask uses `id` directly. Add `--with-subscriber` or
`--with-contract` only when that extra relationship is intentional.

### Component Implementation

The implementation Package owns exactly one public top-level `const CCComponent`, pages, local policies, Services and message handlers. The generator keeps its Registrar and Manifest private. Export only intended business contracts.

### Contracts Package

Keep it Pure Dart where possible. Depend on `ccrouter_contracts`, never on Flutter page implementations. Export only generated public contract types and explicit Service interfaces/tokens.

## Typed Navigation

```dart
final result = await CCRouter.navigator.push<String>(
  OrderRoutes.detail(orderId: 42),
  source: const CCNavigationSource.feature('checkout'),
);
```

Use `replace` only when the current entry should no longer remain. Use `go` for declarative location changes and `reset` only for an explicit new root. Do not emulate unsupported remove-until operations with a sequence of pops and pushes.

Use `context:` only when call-site Host/Outlet placement is required. Without
Context, default placement resolves through the active Host while an explicit
route Host/Outlet remains authoritative.

## Dynamic and External URI

```dart
await CCRouter.navigator.open(Uri.parse(location));

await CCDeepLinkIngress.fromPlatform(uri);
await CCDeepLinkIngress.fromNotification(uri);
await CCDeepLinkIngress.fromQrCode(uri);
```

Configure exact Host allowlist entries and explicitly enable external ingress on the destination. Keep push as the default external open mode unless declarative Shell reconstruction requires `go`.

## Component-Internal Route

```dart
@CCRoute<void>(
  id: 'catalog.product',
  pattern: CCPathPattern('/products/:productId'),
  description: 'Product details.',
)
final class ProductPage extends StatelessWidget {
  const ProductPage({required this.productId, super.key});
  final String productId;
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

The Service should depend on a backend-neutral `CCStorageBackend`; a memory Fake is
the default for deterministic tests. Persistent or secure implementations belong to
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

Export only the interface from the business contracts barrel. Bind a simple
implementation by directly implementing exactly one contract:

```dart
@CCService()
final class CartSummaryServiceImpl implements CartSummaryService {
  const CartSummaryServiceImpl();

  @override
  String summary() => '...';
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

This is Component-author SPI, not a business lookup pattern. Consumers still
call `CCRouter.service<CartSummaryService>()` and never import the owner barrel.

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

final initResult = await CCRouter.runInitTasks(
  gate: CCInitTaskGate.privacyGranted,
);
// Use only when this Host deliberately cannot start in degraded mode.
// initResult.throwIfRequiredFailed();
```

`CCRouter.initialize` creates the process-default Runtime and pairs with the
Composition Root's awaited `CCRouter.shutdown`. Do not call `shutdown` from a
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

The command owns files under `lib/src/ccrouter_generated/`. Do not edit or
relocate generated outputs. A Host's handwritten public barrel may re-export
the generated `src/ccrouter_generated/ccrouter_host.api.g.dart`; do not point it
at implementation-only files under `host/` or repeat the generated `show` list.
Component and contracts Packages must still export only their intended business
contracts and stable component API.

An unchanged command may report a generation fast-path hit. This is valid only
after exact authored-input, tool, resolved-Package, external-index, and managed-
output fingerprints match a previous successful run. Use `--no-cache --check`
when validating the reference path after generator, SDK, or build configuration
changes; do not make application code depend on cache or manifest files.

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

After `ccrouter clean`, generation may temporarily bootstrap missing component
Route, Command, and Event APIs from valid Builder metadata before build_runner.
This only repairs the import graph for the same build pass: current metadata is
still rebuilt and every final artifact is regenerated and validated.

Packages with no generated capability have no `ccrouter_generated` directory.
Removing the final declaration removes empty managed directories while
preserving unknown or handwritten files.
