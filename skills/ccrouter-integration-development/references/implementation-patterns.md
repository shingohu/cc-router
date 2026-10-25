# Implementation Patterns

Examples show separate integration patterns, not one file to concatenate.
Application symbols such as `analytics`, `database`, and manifests must come
from the consuming project. Generated Client names come from its real component
and Contract declarations. Do not invent these APIs or register both an
annotated Provider and its alternative handwritten Provider.

## Package Roles

For the optional cross-component UI path, follow [ui-fragments.md](ui-fragments.md).
This path adds an explicit business `ccrouter_ui.dart` import and a separate
generated UI Client barrel; it does not expose Host/Generated SPI or change
the ordinary Route, Service, Command, Event and InitTask integration patterns.

### Host

Here, **Managed** means that the CCRouter Runtime owns route resolution,
policy admission, Route Entry, Route Scope, typed results, and Host/Outlet
stack state. The Managed Backend only projects that state through Flutter's
`RouterDelegate + Navigator.pages`; it does not own the whole application or
implicitly control Runtime initialization and shutdown. Foreign Routes created
by Flutter or another Router remain outside this ownership boundary.

A new application should use `ccrouter_host.dart` with the Runtime Managed
Backend: call
`CCRouterHost.initialize(hostAssembly: ccrouterGeneratedHostAssembly)`, then
mount `CCManagedRouterApp`. The convenience widget creates
`CCManagedRouterBackend` from the initialized Catalog and mounts it through
`CCRouterApp.managed` and `MaterialApp.router`; use its `backendFactory` for
custom Shell/Outlet topology. Managed page stacks are the navigation source of truth;
Flutter `RouterDelegate + Navigator.pages` is only their projection. The
generated stable Host barrel exports only the atomic Assembly. The Host owns
the generated Catalog, Backend, Shell/Outlet topology, platform Deep Link
ingress, global policies, and final `CCRouterHost.shutdown`.

For full control, create `CCManagedRouterBackend` explicitly and pass its
`RouterConfig` to `MaterialApp.router`; this is the advanced/test composition,
not the default application path.

Keep this API separation visible in code review: feature Packages import only
`ccrouter.dart` and generated business APIs; the Composition Root owns
`ccrouter_host.dart`; Backend, Catalog, Assembly, Shell, and MultiHost types are
Host-only assembly details. A read-only Host/debug health panel may use
`CCRouter.runtimeHealth`, but must not use its counts to mutate navigation or
infer memory leaks. `unattributedBackendEventCount` includes Foreign and opaque
backend observations, so it is not a direct `Navigator.pop` counter.
`trackedNavigationHostCount` counts Host lifetimes captured lazily by navigation,
Pop or scoped clients until detach. It is not the Adapter registration count and
can be zero before a lifetime is captured. `inFlightNavigationCount` counts only
`singleFlight/rejectDuplicate` concurrency gates; zero under default `allow` does
not mean all navigation has finished. Observer queue depth excludes current
delivery; capacity stays `max(64, navigationDiagnosticCapacity)` when history
retention is disabled.

Managed startup treats `initialLocation` as a trusted fallback. A non-root
platform default route takes precedence and passes external ingress policy;
`overridePlatformDefaultLocation: true` deliberately forces the Host fallback.
Null always reads the platform URI as external input. Custom `backendFactory`
implementations forward both fields, alongside Shell/Outlet configuration.
Do not mark a platform URI internal to avoid a Deep Link rejection.

For each Managed Host, a newer platform/browser location cancels that Host's
unfinished ingress, even when the new URI already equals the current location.
The lifetime spans async interception, redirect, defer/resume and Failure Policy
recovery. Cancellation ends framework waiting and consumes late values/errors;
policies own stopping their external work through their cancellation token.
Ordinary business Push concurrency and other Hosts' requests are unchanged.

For declared `parentRouteId`, Managed Go/Reset/Open-Go and startup/browser
navigation resolve a root-to-leaf plan before Backend mutation. Each ancestor
decodes the child's Path/Query through its own Codec without copying Extra,
then canonical encoding validates its required fields. Ancestor interceptors
run before the leaf with the original origin. Missing required data, an
unreconstructible Extra, cancellation or timeout leaves the old stack intact;
redirect rebuilds the plan and defer resumes the leaf through fresh validation.
Every installed ancestor owns its own Entry identity and Route Scope, with no
business caller waiting for its result. Push/Replace preserve the existing
stack rather than implicitly rebuilding it. A leaf allowed as a Deep Link can
reconstruct an internal-only structural parent, but does not make that parent
directly addressable externally or bypass its access interceptors.

`CCNavigationParentStackAdapter` is optional Host SPI. Native Managed accepts
the transient `CCNavigationRequest.parentStack` in one synchronous transaction;
MultiHost queries its resolved child. Custom implementations must reject before
mutation, preserve independent ancestor lifetimes, and strip parent planning
metadata from retained leaf requests so exact close can release ancestor data.
Do not call an Adapter from feature code or fabricate parents in a Shell builder.

Shell ownership follows the registered Outlet, including generic destinations
opened with a Shell page's Context. Closing a covered seed releases only that
Entry and Scope. Branch Go and Host tab activation share visibility projection;
URL follows the selected retained branch, while pointer focus changes only the
default Back target. Ordinary Flutter popups remain foreign live Routes. Their
identity and top observations drive Runtime hiding and guard selection without
creating a Managed Scope. A live foreign `CCNavigationPopTarget.owner` also
protects the underlying page before queued observation arrives; legacy Adapters
that omit it keep their ledger/Runtime fallback.
`CCNavigationScopedPopTargetSource` resolves a Context-selected Host/Outlet's
actual target without changing active Host or focus; a real ancestor popup can
select root. Do not infer a popup merely from a legacy structural ledger Entry
classified as foreign. Pop/Remove/Replace and disposal
release live Route references; retained diagnostics contain no Route or payload.

Managed cross-Shell push retains earlier Shell anchors, branch stacks, and
Widget State. Once the current child cannot pop further, Back can remove its
outer anchor and reveal the caller. A Root Context resolves the selected child
as the guard/pop target rather than the root page underneath the Shell. Shell
identity is singleton per Host topology: revisiting the same Shell promotes
its retained container, not a second Navigator for each declared Outlet.
When an outer Shell is already exiting, its rendered branch Pages and Scopes
survive through the outer transition. Re-entry retires that outgoing projection
before the new container claims its Outlet keys. The old exit cannot revive the
live Store or clear the replacement renderer. Detach/shutdown also ends waits.
Within one Managed Host, a named Outlet belongs to only one Shell and `root`
cannot be a Shell child; initialization rejects either topology conflict.

The application owns layout metrics, breakpoints, fold interpretation and pane
selection. At the Host composition boundary, apply the resolved visibility with
`CCMultiHostNavigationAdapter.setActiveOutlets(hostId: hostId, outlets: visible)`.
The list is copied and must be non-empty, unique and non-blank. Invalid input or
an unknown Host leaves visibility unchanged. This operation does not activate a
Host, change stacks, remove entries or dispose Route Scopes. Do not use it for
business navigation. The Demo owns its `DemoAdaptive…` policy and geometry types.
Native Managed forwards this selection into the child's Store; navigation,
focus and Shell branch selection preserve it until the Host updates the layout.
Root overlays mask it temporarily. Custom Adapters can implement the optional
Host-only `CCNavigationOutletVisibilityBinding` and own effective visibility
publication; Adapters without it retain lifecycle/event forwarding.

Ordinary Managed Pop separates logical removal from rendering: the result and
active Entry end first, while outgoing content and Route Scope survive until
Flutter's transition completes. This permits rebuilds that resolve Route Services
without blanking the animation. Exact close and retained foreign anchors release
business resources promptly. The last foreign Popup leaving through pop, remove
or replace retires its empty anchor; replacing it with another Popup preserves
the boundary. Runtime shutdown cancels render waits and never requires a UI frame.
Custom Backends opt in with Host-only `CCNavigationRouteExitBinding`, returning
a detachable callback rather than retaining Runtime through an unfinished Future.

The initial page created by Managed startup owns an Entry and Route Scope just
like later destinations. Foreign Routes and `CCManagedOutlet.baseBuilder` local
surfaces do not create their own Managed Scope; do not borrow an underlying
page's binding for their independent resources.
Feature code must not call the SPI or start business work during visual exit.

This applies to native Navigator Pop and iOS gesture commit as well as business
Pop. Native gates evaluate exact Host/Outlet/backend identity through optional
`CCNavigationScopedPopGuardBinding`, not global focus. Runtime prefers this
binding; older one-argument Adapters remain supported. A multi-Navigator custom
Adapter must supply the Route's actual identity, never temporarily change focus.

Renderer unmount releases its Route correlations, PopEntries, foreign records
and PageLifecycle top without closing managed Entries, Scopes or pending results.
Remount creates a fresh renderer generation and projects the retained Stack.
An old generation cannot clear its replacement. Widget State follows Flutter's
lifetime and disposed foreign popups do not return. Reusing a RouterConfig does
not replay completed startup Go. Context-free Back uses the sole visible mounted
Outlet after focus is hidden; ambiguous multiple panes still require Host
selection and real root popups keep priority.

Same-frame reparenting keeps the renderer with its Navigator rather than ending
its lifetime: live foreign popups and native PopGuard gates must survive a pane
reorder. This differs from an unmount that really disposes the Navigator.

For a standalone adaptive pane's local UI, mount
`CCManagedOutlet(backend: backend, outlet: paneId, baseBuilder: buildLocalPane)`.
The base remains below Managed Entries and receives normal local Widget state
updates. It has no Managed Entry, result channel, or Route Scope; use a declared
route when those lifetimes are needed. A generated Intent pushed with this
surface's Context renders in the same Outlet and returns to it on pop. Mount
each registered Outlet key exactly once; do not layer a second handwritten
Navigator over the Managed renderer.

The GoRouter compatibility package and its Host APIs have been removed. Existing
business Intents, navigator calls, Route Service lifetimes and typed results
remain valid. Composition Roots use `CCManagedRouterApp`, or compose:

```dart
final backend = CCManagedRouterBackend(routeCatalog: applicationRouteCatalog);
final app = CCRouterApp.managed(
  backend: backend,
  child: MaterialApp.router(routerConfig: backend.routerConfig),
);
```

Initialize the Runtime first with one `CCHostAssembly`. Generated Hosts use
their generated Assembly; handwritten Hosts include their Catalog in the same
`CCHostAssembly.fromComponents` call.

<!-- verified-example: host-assembly -->
```dart
final hostAssembly = CCHostAssembly.fromComponents(
  components: [ordersManifest, accountManifest],
  routeCatalog: applicationRouteCatalog,
);
CCRouterHost.initialize(hostAssembly: hostAssembly);
```

`CCManagedRouterApp` forwards non-routing MaterialApp settings (theme, locale,
localizations, shortcuts/actions, restoration and debug flags). Its stable
`backendFactory` runs once. Backend inputs cannot change after mounting:
unmount, await shutdown, initialize a new Runtime, then recreate it with a new Key
when changing routing ownership. A custom factory
must preserve both initialLocation and overridePlatformDefaultLocation.
Advanced Hosts may explicitly create a Backend and mount it through
`CCRouterApp.managed`; do not configure Router ownership twice.

Progressive adoption uses an embedded Managed Outlet for a feature area or a
separate Managed Host. It does not attach to an existing GoRouter. The outer
application remains responsible for its existing Navigator and system-back
handoff. Business code never chooses or disposes Backends.

A custom Host Adapter builds from `CCNavigationRequest.pathParameters` already
resolved by Runtime. Never rematch the URI against the primary pattern: aliases,
Regex and constraints have already been resolved.

### Runtime ownership and diagnostics

Unmounting a navigation surface does not shut down the shared Runtime.
Composition Roots explicitly await `CCRouterHost.shutdown()`. Runtime releases
its owned Adapter before Backend RouterDelegate/provider resources. Managed and
HostBinding entry points share ownership reservations. Backend/Adapter aliases
are rejected without disposal while reserved, attached, or still being cleaned
up by shutdown or rejected-Backend disposal. A distinct rejected wrapper sharing the Adapter remains
caller-owned; release its resources without disposing the shared Adapter again.
Capture the Adapter getter once, then recheck ownership: a getter can
synchronously reenter HostBinding and transfer that exact Adapter.
If an attachment callback synchronously starts shutdown, that shutdown owns the
provisional Adapter and registered Backend cleanup. Await it after attachment
fails without disposing again. Ordinary managed attachment failure cleans up
independent rejected resources; ordinary direct HostBinding failure leaves
cleanup with its caller. The managed transaction also covers Host mounting and
page-lifecycle bridging: rejection rolls back mounts acquired by that State,
without unmounting another tree's Host. Inside a TestHost Runtime overlay,
managed attachment is rejected before ownership transfer, so even independent
explicitly supplied resources remain caller-owned. `CCManagedRouterApp` and the
Host Catalog accessor reject that overlay before Backend factory allocation.
An initialization callback starting disposal cancels initialization; operations
and Session creation cannot resume. Nested initialize calls are rejected.
Session close
does not dispose navigation or permit reattachment. Initialization failure disposes unpublished Runtime
state and preserves the original exception. Await shutdown to join rollback
before retrying. Concurrent shutdown callers join one cleanup generation in
their own error Zones. Listener/PopGuard/disposal failures must not skip other
resources; cleanup returns the first structural failure after attempting all
owned cleanup. Removed Route Scope and asynchronous Service cleanup are joined
also when exit subscription or removal callbacks synchronously start shutdown.
Pending Route closures carry failure data across error Zones. An exit remover
may reenter shutdown from a different error Zone and then throw; Adapter, App
Scope and Backend cleanup still finish before shutdown delivers the original
error and stack to each caller. Observe the returned Future in its caller Zone.
Shutdown and Host detach cancel outgoing render waits without another UI frame.
Batch removal drains every matching Entry despite a failing Adapter release
hook, advances terminal states and closes each Scope. Host detach completes its
Backend ledger cleanup as well. Shutdown returns the first original cleanup
error/stack; business `go/reset` retain sanitized Adapter error semantics.
A navigation dispatch failure keeps its primary error even if removal/release
also throws; `lost/after/failed` observations still terminate. Cleanup diagnostics
retain only the failure type. Synchronous removal errors and asynchronous Scope
closure use one shared receipt: a reentrant shutdown waits for Scope closure
before restoring the first removal error and stack in its caller Zone.
An earlier lifecycle Binding detach failure takes precedence over subsequent
Runtime/Adapter/Backend cleanup errors after all cleanup completes. Health
cache invalidation precedes external callbacks after structural changes.
Terminal observer overflow reserves the incoming slot before synchronous
backpressure; nested fan-out preserves each listener's FIFO and bounded waiting
depth without duplicating callbacks.
Do not await an Owner's teardown from its own disposable.

For isolated tests, `CCRouterTestHost.dispose()` also joins concurrent,
synchronously reentrant and late callers, carrying the original error and stack
to each caller's error Zone. Observe each returned Future in that Zone. If a
test directly asserts a cleanup failure, its registered teardown must assert
that same failure rather than assuming a later dispose succeeds.

Configure traceCapacity and navigationDiagnosticCapacity at Host initialization.
Each defaults to 1000 per history, not a shared byte budget. Zero disables
retention, not active entries or delivery; observer queues/deduplication still
use at least 64 slots. A diagnostic Sink has its own bounded queue and one
in-flight write. Use sanitized Runtime snapshots and delivery counters.
The old lifecycleEventCapacity/lifecycleEvents Adapter ring has been removed.
Do not retain Route, Context, Widget, arguments or results in historical data.
Managed predictive fallback history separately retains at most 100 sanitized
events per Adapter.

### Foreign and opaque UI reporting

Ordinary foreign Routes on a Managed Navigator are observed automatically.
For an independent Navigator that cannot install observers, use Host-only
`backend.adapter.foreignRouteBridge`. push/replace/pop/remove return or consume
`CCForeignRouteHandle`; pushOpaque/removeOpaque use `CCOpaqueUiHandle` for
OverlayEntry, menus and other non-Route UI. These report diagnostics only:
they never navigate, create managed Entries/Scopes or complete business results.
Do not double-report an automatically observed Route. Handles are exact and
bridge-owned; duplicate/cross-bridge/ended handles are rejected. Disposing the
Adapter invalidates handles and clears callbacks so a retained bridge cannot
retain the Adapter.

Native close removes the selected Entry by identity. It preserves foreign
popups even when closing the last root/Shell Entry: an empty structural boundary
survives only until those popups end, with no business content or Scope.
A copied Page key does not establish managed ownership. A direct Flutter
Navigator.pop(result) is observed after Flutter commits the Pop and must preserve
the original typed result exactly once. It is a compatibility reconciliation path,
not a policy-aware CCRouter Pop: it cannot reliably run PopGuards, async
confirmation, cancellation, or the complete leave policy. Use
`CCRouter.navigator.maybePop()` for policy-aware Back and
`CCRouter.navigator.pop` after an explicit business decision.

### Optional Android predictive back

Set `enablePredictiveBack: true` on Managed App/Backend and enable
`android:enableOnBackInvokedCallback="true"` on the effective Android application.
The default false preserves Flutter construction and animation. Default Material
Pages wire Host-only `CCPredictiveBackCoordinator` automatically; custom Routes
may use `CCFlutterRouteFactory` with a predictiveBackHandler. Never manually
forward phases for an automatically wired Route.

Flutter alone animates/pops. The bridge confirms exact backend identity and
protects against duplicate/late terminals, navigation interruption, ancestor
popups, local PopScope/Form changes and unsupported Theme changes. Cancellation
does not end a result/Scope or trigger business confirmation. Eligibility
reads do not change an in-flight gesture's owner. A retired custom handler
detaches only after fencing its old terminal or cancelling the old preview on
the next start; new Flutter sequences may then recover.

Stock PredictiveBackPageTransitionsBuilder and
PredictiveBackFullscreenPageTransitionsBuilder are supported. Android Guard,
Modal, LocalHistory, custom-transition and unsupported-platform cases use their
documented fallback. iOS default opaque guarded pages run the synchronous Guard
before starting Flutter's interactive gesture. Deny must remain still; allow
must track the finger, cancel must retain the page, and commit must remove it
once. Widget tests or macOS do not replace device gesture acceptance.

The Demo entry is `lib/main_predictive_back.dart`; the Managed alias remains.
Host fallback diagnostics contain only stable reason/Host/Outlet/timestamp,
never URI or business payload. Adapter teardown releases observer, Timer, Routes,
listeners, PopGuard and backend callbacks.

### Multiple Hosts and Shells

`CCManagedMultiHostBackend.managed` aggregates independent Managed children from
the initialized Catalog, validates declared Host identity and owns child cleanup.
The Composition Root renders surfaces and handles active-Host fallback for
context-free navigation. Pass the call-site BuildContext or acquire
`CCRouter.navigatorOf(context)` when exact Host/Outlet selection matters.
Large-screen panes and tabs normally use Outlets of one Host;
the aggregate is not a native Window lifecycle implementation.

Mount each `navigatorFor(outlet)` at most once. Keep inactive branches mounted,
for example in an `IndexedStack`, when their Widget State must survive. Unmount
preserves logical Entries, results and Route Scopes, but disposed Widget State
does not restore. Before selecting a branch, inspect hasEntries(outlet):
initialize an empty branch, activate a retained branch without navigation, and
reserve Go reset for explicit reselection.
This is Host policy and never a feature stack-query API.

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
The example main initializes the generated Assembly and runs `CCManagedRouterApp`,
with an authored `/` Route. Both Packages declare `build_runner` and SDK Flutter
test dependencies. Outside a Workspace, first Pub get and `ccrouter portable
prepare .` in the component, then Pub get and `ccrouter generate .` in the example.
Repeat prepare after component changes. The parent is a read-only Path dependency
of the example; mismatched toolchain resolutions must be aligned rather than
bypassing Portable verification.
Example tool dependencies come from the staged component manifest, including
rebased Paths. SDK ranges and Git refs retain string identity through YAML
serialization; compare parsed values rather than assuming unquoted text.

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

The Host is the application composition root: it selects application-wide
infrastructure, platform bindings and cross-component contracts. It is not the
construction site for every component's internal object graph. Components
create and release their own page controllers/ViewModels, coordinators and
repositories, using narrow injected dependencies where a replacement boundary
actually exists. Do not export these internals merely to let the Host wire them.
Framework-owned Route/Session Services retain their documented Scope ownership;
component assembly must not dispose framework-owned instances.

An injected dependency, getter or process-local Extra grants use, not permission
to reinitialize, replace or close its Owner's resource. For an Extra carrying a
borrowed capability, document the Owner, lifetime, optional/missing behavior and
failure after closure. If the caller can close while the destination remains
open, make stale operations fail explicitly and define pending-Future handling;
the destination must not silently bind the old reference to a new Session or
Runtime. The framework's type check does not enforce these business lifetimes.
An immutable result snapshot may outlive its producer under its own contract.

The implementation Package owns exactly one public top-level `const CCComponent`, pages, local policies, Services and message handlers. The generator keeps its Registrar and Manifest private. Export only intended business contracts.

### Contracts Package

For multiple domains, public/Owner/value entry points and safe source moves,
see [Contracts layout and relocation](contracts-layout.md). Public libraries
currently remain directly under `lib/`; nested handwritten declarations belong
under `lib/src/<domain>/` when grouping improves cohesion.

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

For repeated local operations, resolve once inside the intended Navigator:

```dart
final navigator = CCRouter.navigatorOf(context);
final result = await navigator.push<String>(
  OrderDetailRoute.intent(orderId: 42),
);
```

This returns `CCNavigator`, reusing existing navigation policy and typed results.
It retains no BuildContext, Navigator or Runtime and installs no listeners; no
dispose is needed. Resolve in build, didChangeDependencies or an interaction
callback, not initState. Reacquire after moving to a different Host/Outlet.
Focus changes and async delays cannot retarget the client. Explicit route
placement remains authoritative. Host unregister or Runtime shutdown permanently
invalidates it with a synchronous `CCRouteCancelledError('host_detached')`;
same-ID replacement cannot revive it. Page/renderer unmount alone does not
invalidate this registration-scoped client or cancel page-owned work.
If a call also supplies Context, it must resolve to the same Host/Outlet;
otherwise `CCNavigationOutletResolutionError` is thrown. Acquire another client
for a different region. Exact close still follows its handle, even if an
explicit destination was placed elsewhere; Pop does not follow the last push.
The existing global facade and per-call Context APIs remain unchanged.

Snapshot the operation's concrete default Host before awaiting policy. Initial
explicit Host placement wins, while redirect/recovery/default targets keep that
Host even after focus changes or explicit intermediate targets. Later explicit
Hosts remain authoritative; preserve the declared Shell, Outlet and parent.
Unknown-URI recovery uses the invocation Host snapshot. Host removal produces a
failure, not fallback to the currently active Host. These rules do not require
new business parameters or retaining BuildContext.

Dynamic unregister also ends the captured registration's uncommitted policy,
recovery and pending replay with `CCRouteCancelledError('host_detached')`. A new
registration with the same ID is independent, including concurrency admission;
late decisions cannot migrate into it, and Failure Policy cannot revive the
cancelled operation. The Composition Root owns dynamic registration and child
Backend disposal; the aggregate factory list is a fixed initial assembly.
Unmount the old CCRouterApp before mounting another instance with that Host ID.
Run `demo/lib/multi_host_demo.dart`, select the Host lifecycle tab, start delayed
navigation, close/reopen, navigate in the new instance and release the old gate.
The old outcome stays cancelled and the new Entry identity remains unchanged.
Repeat several generations and leave/re-enter without restarting Runtime;
advance the replacement to a different page before releasing the old decision.
The auxiliary Demo initializes its trusted `/` home with
`overridePlatformDefaultLocation: true`, keeping route-information startup
enabled so initial content is real and the primary platform link is not reused.
Custom Adapter operation IDs need only be stable within one registration;
MultiHost namespaces them per registration and rejects retired subscriptions'
queued notifications. Repeated notifications with the same operation ID within
one registration retain Runtime's bounded deduplication semantics.
Optional child event sequences are checked per registration: duplicate or
non-increasing values are discarded before forwarding; gaps remain visible to
Runtime's Backend desync diagnostics. Aggregate-generated Outlet/detach events
and unsequenced child events do not advance the child sequence baseline. A new
registration starts independently, even when it reuses the logical Host ID.
Ordinary Backend/Outlet events use FIFO fan-out under synchronous observer
reentry. Explicit detach still completes synchronously while its retiring
reservation is held; queued events from a retired registration are discarded.
Operation deduplication is separate from stream sequence acceptance: a repeated
operation with a newer valid sequence advances the baseline without applying
again. Stale events do not reserve operation IDs. A true gap still invalidates
health snapshots even when that operation is a duplicate.
Initial snapshots must describe a coherent active stack at read entry. Runtime
imports that state before replaying events emitted during the read. Snapshot
Entry versions share the Host event sequence domain: their maximum rejects
older buffered reports, but is not a stream watermark and does not establish
the live gap-detection baseline. Removed entries may have advanced the stream
before observation began. MultiHost validates child versions separately and
maps snapshots to its aggregate read boundary, preserving FIFO order with
aggregate Outlet events and observer reentry. Without sequence metadata,
arrival order is the fallback and delayed old reports cannot be rejected reliably.

Custom Adapter synchronous callbacks and old Scope cancellation/disposal may
retire the dispatch Host or Runtime before a new Entry is committed. The Runtime
rechecks ownership at these handoffs and consumes abandoned Backend Futures'
late errors without waiting for their application work. This does not replace
Backend rollback or change a committed Push's eventual Pop-result semantics.

Dynamic registration takes an unowned Adapter after argument/lifetime validation;
duplicate-ID or initialization/binding failure releases that ownership. Passing
an already owned Adapter is rejected without disposing its current registration.
Same-ID initialization reentry is rejected. Binding may unregister and replace
its owner; the old transaction must fail without erasing the replacement. A
failed binding also retires any Runtime-observed provisional Host lifetime and
active Backend state before cleanup hooks; an old scoped navigator never revives
when the logical ID is reused. A pending Host cannot become active or replace
the current active Host. Registering
before aggregate initialization installs bindings once at initialization.
The aggregate's initialization transaction rejects recursive initialize/register
operations instead of mutating the collection being configured.
The old detach is fully delivered before invoking unsubscribe/dispose hooks.
Same-ID registration during delivery is rejected; after delivery, cleanup hooks
may create a replacement with a fresh Adapter without the old event cancelling
its newly opened page. The old Adapter remains reserved until unsubscribe and
dispose return, including error paths; it cannot be registered under any Host
inside those callbacks. Each child Backend/predictive and aggregate Outlet event
checks its original registration before every observer delivery. Retirement in
an earlier observer stops the old event; explicit detach delivery still completes.

For overlapping requests, Host `navigationConcurrencyPolicy` defaults to allow.
`singleFlight` shares one unfinished result, and `rejectDuplicate` rejects only
requests with the same exact origin, Host/Outlet, operation, Open mode, route ID
and URI. Distinct platform/notification/QR/internal origins still run their own
Interceptor checks. Telemetry attribution is not a trust boundary. Extra values
are never compared; completion/error releases the gate so later retries execute.
Shared navigation failures retain the original error identity and stack even
when joined from a different Dart error Zone. Handle each returned Future in
its caller Zone; this does not make arbitrary foreign error Futures cross-Zone.
Each shared call keeps its own navigation observation; policy cancellation
reports a cancelled Aspect outcome for the original and every joined call.
Lifecycle/Entry/Visibility/Failure/Backend/Capability listeners use exact
registration identity. A remover is idempotent, cancels only its registration's
pending deliveries and cannot remove a later re-add of the same function.
Simultaneous duplicate adds still deliver once and share cleanup ownership.

Use explicit initializer start gates to test shared-readiness timeout. First
start an owner waiter, await initialization's start, time out another waiter,
then finish initialization and join the owner. Timeout alone does not prove work
began. A factory that closes its Scope still transfers returned disposables to
bounded cleanup. Invocation timeout cleanup errors become sanitized diagnostics;
the caller retains the original timeout. Manage authentication outside factories.

Deferred navigation pins the original concrete Host and call-site placement.
Changing the active Host does not retarget a saved request. Resume revalidates
typed arguments with the codec encoder while preserving arguments/Extra identity;
dynamic URI requests match and decode again. Redirect targets with explicit
placement still override call-site defaults. Keep a timeout or cancel abandoned
continuations so in-memory payloads are released.

Handle the original navigation and each Resume Future in its own calling Zone.
Replay returns/throws its local result independently instead of awaiting the
original caller's error Future, so distinct error Zones, repeated defer, timeout,
Host detach and shutdown still terminate each waiter. The original pipeline owns
Host Failure Policy recovery: it can recover while the Resume caller receives the
replay error. Recovery is not invoked a second time for that observer.

Runtime shutdown completes pending Interceptor and Failure Policy waits with
`CCRouteCancelledError` and prevents late decisions from reaching the Adapter.
Interceptors should observe `context.cancellation`; arbitrary business Futures
cannot be forcibly stopped. Do not turn shutdown cancellation into a recovery
navigation or use it to continue the ended Runtime.

MultiHost Pop receipts use the Host selected before dispatch and the child's
actual handled Outlet. Focus changes, unregister and shutdown cannot relabel a
pending result. A root Popup above a named Outlet reports root; LocalHistory-only
handling does not become a managed removal. Do not reconstruct ownership from
the post-Pop active target.

### Active Route Revalidation

Use an explicit revalidation pass only after an application state owner has
committed authentication, permission, Session, compliance, or feature-state
changes that may invalidate retained pages. Runtime does not subscribe to a
`Listenable`, Stream, Provider, Bloc, or another state manager.

```dart
final class AccountRoutePolicy implements CCRouteRevalidationPolicy {
  const AccountRoutePolicy(this.accessState);

  final AccountAccessState accessState;

  @override
  CCRouteRevalidationDecision evaluate(CCRouteRevalidationContext context) {
    if (!accessState.isSignedIn &&
        context.entry.routeId == 'account.profile') {
      return CCRouteRevalidationReset(LoginRoute.intent());
    }
    return const CCRouteRevalidationKeep();
  }
}

// Host Composition Root
CCRouterHost.initialize(
  hostAssembly: hostAssembly,
  routeRevalidationPolicies: [
    CCGlobalRouteRevalidationPolicy(
      id: 'account.active_routes',
      policy: AccountRoutePolicy(accountAccessState),
      timeout: const Duration(seconds: 1),
    ),
  ],
);

// State owner, after committing the new state
await CCRouter.revalidateActiveRoutes(reason: 'authentication_changed');
```

The policy reads a stable application-owned state facade so later committed
values are visible; do not retain a Widget,
`BuildContext`, Route, Scope, raw arguments, or result. Evaluation must be
side-effect-free and non-reentrant. Runtime orders registrations by stable ID,
uses the first non-keep decision for each Entry, evaluates the complete snapshot
before mutation, serializes overlapping passes, and cancels a pending pass on
shutdown. A policy error or timeout produces no mutations.

Exact close bypasses PopGuard and `PopScope` because access revocation is not a
user Pop. Replace is accepted only while the exact Entry remains topmost in its
Host/Outlet. The topmost reset selected per Host supersedes that Host's other
decisions even if the selected reset later becomes `stale` or `unsupported`, so
lower-priority actions cannot partially mutate that Host. It does not activate
or touch another Host. Concurrent navigation
can make a planned Entry `stale`; an Adapter without exact-close support reports
`unsupported`. Destination Intents, Interceptor redirects, and Failure Policy
recoveries cannot change the selected operation or escape the original replace
Host/Outlet or reset Host; an incompatible final request also reports
`unsupported`. A default-placement Entry remains pinned to the concrete Host
resolved when it was admitted, regardless of later focus changes. Revalidation
mutations are isolated from ordinary `singleFlight/rejectDuplicate`
coordination, and replace completes its report after the replacement Entry
commits rather than after its eventual Pop result. Shutdown cancels a deferred
revalidation continuation before joining the serialized queue. Never replace either
outcome with positional Pop. The two-phase
evaluation boundary does not make mutations across independent Backends
rollback-atomic, so inspect `CCRouteRevalidationReport` and trigger a later fresh
pass when application state changes again.

Revalidation Replace requires the Host-only `CCNavigationDispatchAdapter` SPI.
Its synchronous method returns `CCNavigationDispatch` only after an atomic
Backend transaction; rejection throws before mutation, and `receipt.result`
represents the eventual Pop result. Native Managed and Memory implement it.
MultiHost delegates to the resolved child, returning null without dispatch when
the child cannot prove acceptance. Runtime then reports `unsupported`. The
custom legacy Adapters retain ordinary navigation
but do not gain this capability automatically. Never synthesize a receipt around
an asynchronous acceptance Future or dispatch the same request twice.

Host binding applies independently of Shell, Parent, and named Outlet metadata:
a concrete call-site/revalidation Host binds a declared `default` Host while
preserving declared topology. An explicit non-default Host still wins and the
revalidation partition fence rejects any incompatible destination.
Backend close/reset waits terminate with `CCRouteCancelledError` on shutdown,
release their cancellation listeners and consume late values/errors. Arbitrary
Backend work is not made cancellable by Dart Futures; its Adapter owns stopping
that work during disposal and must not require Runtime to await it first.
Queued passes also end with `CCRouteCancelledError`. A non-framework Backend
close failure is wrapped in `CCNavigationAdapterError` without its raw message;
an unchanged Backend stack keeps the original Runtime Entry alive.

For an unsaved editor, local `PopScope` or `Form(canPop: false)` still vetoes
system back and `CCRouter.navigator.maybePop` even when the framework PopGuard
allows exit. Use the local refusal callback for confirmation UI and explicitly
call `CCRouter.navigator.pop` after confirmation; do not trigger navigation from
the Guard. Native Managed default opaque iOS pages synchronously evaluate the
Guard before starting an edge swipe: deny does not animate, while allow retains
Flutter's interactive transition. Cancellation, a declined start, Route removal
and Backend disposal close the temporary gate. Custom transitions keep the
conservative non-interactive fallback;
pages without a Guard retain their default platform gesture.

Confirmation remains page-owned: merge repeated attempts, check that the page
is still mounted and update the business allowed-exit state before explicit Pop.
The existing synchronous Guards still apply. On iOS, `canPop: false` can disable
the edge gesture entirely without invoking the refusal callback. Provide an
explicit leave/save action; there is no framework resume token or UI coordinator.

LocalHistory-only Back is not a Managed leave: skip its leave Guards and keep
the Entry, result and Scope. If LocalHistory disappears while `willPop` waits,
the actual leave still checks the current exact target's Guard. Local Flutter
PopScope/Form decisions remain authoritative. Native Managed consumes duplicate
pending `maybePop` calls for one live Route without overwriting its result or
queuing another Pop. Only the operation that actually removes it receives the
removal receipt; a concurrent Push/Close/Pop cannot be claimed by a waiting call.
Different Outlets remain independent. Renderer teardown terminates framework
waiting without requiring an application's unfinished `willPop` to return.

## Dynamic and External URI

```dart
await CCRouter.navigator.open(Uri.parse(location));

await CCDeepLinkIngress.fromPlatform(uri);
await CCDeepLinkIngress.fromNotification(uri);
await CCDeepLinkIngress.fromQrCode(uri);
```

Configure exact Host allowlist entries and explicitly enable external ingress on the destination. Keep push as the default external open mode unless declarative Shell reconstruction requires `go`.

Crossing a Shell is not itself a reason to choose `go`. Managed cross-Shell
`push` retains the original Shell's branches and Widget State for return; `go`
reconstructs the Host location. A Host Tab activation alone does not add a Push
history entry. Choose the operation from product stack semantics, not a removed
GoRouter Backend limitation.

## Component-Internal Route

默认页面根据应用宿主选择 MaterialPageRoute / CupertinoPageRoute；MaterialApp 的 Material
路由会按主题适配 iOS 滑动返回和 Android 系统返回。MaterialApp 也提供 CupertinoTheme，不能
据此强制使用 Cupertino 路由。仅在产品明确需要时指定 `CCPageRouteType.cupertino`；不要为了
Android 返回问题逐页加防抖或拦截系统返回。默认 Dialog 复用同一宿主判定并保留各自的 barrier
默认值。没有 MaterialApp/CupertinoApp 祖先的自定义 Host 可用显式 CupertinoTheme 选择
Cupertino 默认策略；已知 App 宿主始终优先于 Theme fallback。

MaterialApp 内显式选择 Cupertino Route 时，转场不会替页面设置正文样式。
`CupertinoPageScaffold` 的正文可用
`DefaultTextStyle(style: CupertinoTheme.of(context).textTheme.textStyle, child: ...)`
设置样式。需要 Cupertino 图标时在应用组件声明 `cupertino_icons`，不要修改框架全局主题
来修复单个页面。回归应检查实际 RichText 字号/装饰和小屏溢出，而不只检查没有异常。

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

The Consumer barrel selects generated Route types from the stable
`<package>.contracts.api.g.dart`. The Owner entry exports the authored schema
from its source, as in the Demo:

```dart
// demo_order_contracts_owner.dart
export 'demo_order_contracts.dart'; // Optional Consumer API reuse
export 'src/order_detail_route_contract.dart' show OrderDetailRouteContract;
```

The implementation imports that Owner entry for
`@CCRouteImplementation(OrderDetailRouteContract)`. The generated Consumer entry
contains no authored schema. Generated Arguments, Definition and Codec remain
SPI; exporting them does not supply the missing Contract declaration.

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
Shared failure outcomes also reach concurrent and late waiters in distinct
error Zones with the original error and stack. Cancelling one wait does not
cancel or restart the shared initializer.
An independent waiter's cancellation/deadline or original Session/Route closure
unsubscribes its internal readiness relay. Its caller Zone is not kept alive by
the shared setup; other live/late callers still receive the original outcome.

Closing the actual initializer owner (App/Session/Route Scope for a singleton,
the calling invocation for `newInstance`) settles readiness without waiting for
the business Future. Admitted calls end with `CCInvocationCancelledError` in
each caller's error Zone. Pending initializer and Event Subscriber continuations
are isolated from ended Runtime/Route wait frames; late errors are consumed and
cannot create another terminal Trace or Subscriber error after cancellation.
Keep cancellation of application resources and directly captured objects in the
application. Do not simulate disposal by completing an unrelated business Future.
For a custom MultiHost composition, pass one distinct Adapter instance per Host;
invalid constructor input is rejected before any child ownership transfers.
Child backend Entry IDs need only be unique within the child's lifetime across
all of its Outlets. MultiHost qualifies them by registration, including snapshots,
event previous IDs, active/scoped/Guard targets and ordinary/predictive Pop
outcomes. Use the aggregate's opaque identity consistently in diagnostics;
never correlate it with a raw child ID. A same-name replacement has a new domain,
and a pending old Pop keeps its dispatch registration. A retired managed Host's
Pop receipt cannot alter a replacement Host's state or desynchronization
diagnostics, even when removed-entry history has been trimmed. Host predictive
observers are isolated individually so one exception cannot hide phases from Runtime.
Registration identity is established before synchronous Guard evaluation at Pop admission, including initial stacks
without prior Runtime navigation. Host/Runtime retirement consumes a pending
external Pop (`handled: true`, no removed owner) to prevent system Back fallback
into another Host. Original Entry/Host/Runtime loss settles a pending exact close
as `notFound`; completing exact receipts retain their outcome. Core releases
consumer wait frames and consumes late errors; external work remains Adapter-owned.
Pop/close producers execute and are observed in the Runtime creation Host Zone,
with errors restored in each caller's error Zone. Custom Adapter external error
Futures must obey Dart's producer error Zone delivery rule.
Host-owned Route/Session Scopes, Host tokens and cached readiness records must
not adopt the first consumer's Zone. Scope factories and singleton initializers
use Host context plus explicit framework trace, dependency and reentrancy state;
arbitrary consumer Zone values are not shared Service configuration. New-instance
initializers continue to inherit caller cancellation ownership.

In Widget tests, initialize Runtime inside the `testWidgets` callback, then
explicitly pump fake time until Timer-based InitTasks finish. Creating it in
the real `setUp` Zone gives Host-owned producers a scheduler that Widget pumping
cannot advance. Keep real-time deadline tests in `tester.runAsync` when they
intentionally verify wall-clock semantics. Settle scroll/layout updates before
asserting lazy diagnostic content, and select its owning Scrollable rather than
a nested SelectableText scroll surface.

Synchronous `service/serviceOrNull/services` also fence cancelled or expired
parent Invocations and ended construction owners before cache/factory access and
before handing the instance back. This includes Keys and `newInstance`: a late
method or initializer from Session A cannot resolve Session B's resources after
account switch. A separate live caller still resolves normally. A singleton's
Scope-owned initializer can continue after one waiter cancels or times out.
These checks do not revoke existing object references or stop arbitrary Dart work.

A detached Future/Timer started inside a successful method still inherits that
invocation's original Scope lineage. Closing that Session or Route Scope fences
fresh calls to otherwise available Services, Commands and Events with
`CCInvocationCancelledError`, even if the callback came through an App Service
and all parent methods already returned. A callback in a still-active Scope can
continue normally. Pending child calls also observe the original Scope's
cancellation. Manage background-task completion and irreversible side effects
in application code; a directly retained object reference is not a new
framework invocation.

Service factories and singleton readiness use the concrete owning Scope rather
than the first waiter's lineage. App-owned initialization can therefore finish
after its Session caller ends; `newInstance` readiness keeps both instance and
caller lifetimes. Invocation completion releases listeners rather than retaining
them until Scope closure. A root synchronous lookup rechecks Runtime shutdown
after a factory returns: rejection does not skip adoption or once-only cleanup
of its returned disposable. Keep authentication and shutdown outside factories.

Framework invocation, construction and navigation Zones use identity tokens
without Runtime back-references. Construction owners refer weakly to their
exact Scope and, for Route-owned work, their exact Entry; active and exiting
Entries remain owned by Runtime. Retaining a Zone alone must not retain an ended
Runtime or closed Route payload through those fields. Collected owners reject
resolution rather than selecting a new Session or visible Route. The original
cancellation lineage remains intact. This does not release business objects
captured directly by callbacks or replace cancellation of application resources.

An async generated Service call rechecks cancellation, its owning Scope and
deadline after readiness before entering the actual method, even with no
initializer or an already-ready instance. Caller cancellation, Session closure
and Runtime shutdown cannot start an unentered method. Already-started work
remains cooperatively cancellable. Keep cancellation tests separate: await a
method-start Completer for in-flight work; immediate cancellation must assert
zero calls and the cancellation outcome, not just a cancelled context.

Resolve Route Service only from the exact managed page Context:

```dart
final draft = CCRouter.routeService<DraftController>(context);
```

Managed startup pages own a Route Scope just like later destinations. Foreign
Routes and local `CCManagedOutlet.baseBuilder` surfaces do not create their own
Scope. Resolve only from the owning managed page's Context; never borrow an
underlying page's binding or guess from the top route.

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

An overall Event deadline ends the publication Future with
`CCInvocationTimeoutError` and cooperatively cancels pending Subscribers. A
shared-deadline timeout is not a Subscriber failure diagnostic; a shorter
nested call timeout remains isolated to its Subscriber. Timeout scheduling does
not guarantee microsecond precision.
In Widget tests, run wall-clock deadline work inside `tester.runAsync` and await
its terminal result before pumping the UI. `pumpAndSettle` advances fake timers
without advancing `DateTime.now()` and cannot prove real deadline behavior.

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

Preserve failure placement and the fixed `failureReason`, `failureAttempt`,
`recoveryDepth` fields when bridging to a logger. Failure Context attributes
the attempted Host/Outlet, not later focus; before target resolution it uses
invocation Host ownership and an unknown Outlet remains null. A registered typed
target can report declaration placement even when its codec fails. Navigation
cancellation is warning with final Sink status `cancelled`; lifecycle phase stays
`failed`. Existing `recovered` status means recovery was selected, not that it
subsequently succeeded. Do not export application cancellation codes.

`CCRouter.diagnosticSnapshot` is a lightweight immutable health view: Runtime
identity/revision, seven named event-history counts, and external Sink counters.
It copies no event payload history. Sink completion can change counters without
changing revision. Capacity zero/rotation contributes to history `omittedCount`;
Sink filtering, sampling and dropped writes are independent. Subscriber-error
and removed-backend ledger storage are outside this history list. Do not infer
no failure from an empty or disabled history. Optional embedded DevTools polls
these counters every 250ms only while subscribed, coalesces full snapshot reads,
and stops its Timer when hidden through TickerMode or disposed.

Sink writes start FIFO, with at most one unfinished `record` Future per
Runtime. Return actual write completion, not acceptance into an unbounded queue.
An unfinished write pauses delivery; overflow keeps the latest waiting events.
There is no automatic timeout that would start replacement uncancellable work.
Delivery, completion callbacks and the final shutdown drain use the Runtime
creation Zone, retaining Host logging context without capturing later invocation
Zones. Each batch has the initial queue length as its write budget, including
asynchronous success/error completions. Reentrant writes yield via a Timer once
that budget is exhausted; remaining budget continues without a Timer per write.
Shutdown attempts a final drain if idle, preserving synchronous shutdown logs;
it stops at the first unfinished Future and releases all remaining waiting data
without waiting for the in-flight write. Late completion/errors are absorbed without restarting work;
the pending callback does not retain the Runtime. Host owns the Sink lifecycle,
network cancellation and final flush. Reusing a Sink or rebuilding Runtimes
requires Host cancellation; the bound is per Runtime, not global per Sink.
If Runtime construction fails before returning an instance, its private delivery
owner schedules a final drain and cleanup on the next event-loop turn. This
preserves deferred synchronous failure logs while dropping the remainder at the
first unfinished write. Construction errors propagate immediately; late Future
success/errors cannot restart the discarded queue. No Sink is closed by Core.
Keep synchronous work short because delivery uses the same isolate.

The Runtime emits `componentGraph`, `componentRegistration`, and
`runtimeInitialize` through the initialization diagnostic category. Their
`started` events use debug level, while terminal success and failure use info
and error. A Host that needs the complete startup sequence must enable debug
delivery instead of reproducing component lifecycle logging in its bootstrap.

## Application analytics

CCRouter supplies observation facts through `CCNavigationAspect` and page
lifecycle APIs. The application decides whether Arrival/Show/Hide means a PV,
leave, or another product event. Navigation-current state is not pixel exposure.
Keep `CCDiagnosticSink` for sanitized framework execution diagnostics.

Core and Host initialization accept no visitor/application Session identity.
The Demo bridge injects its application `identityProvider`, snapshots once on
first delivered Found (with Arrival/Show fallback), and keeps identity across
redirects and visibility intervals until removal/disposal. Observations arrive
asynchronously; this does not promise the identity at navigation invocation.
Products requiring that exact attribution must correlate it at their own action
boundary. Call `resetTracking()` before Consent/account changes; dispose fences
late callbacks and releases snapshots/provider references. Failure and invalid
identity are isolated in application code, not validated by Runtime.

Route-restoration demand is also application-owned. The repository's optional
`demo/lib/restoration_demand.dart` records bounded sanitized platform evidence
without starting CCRouter. The Host owns its platform subscriptions, Consent,
exporter and recorder disposal. There is no Core source, history or DevTools
section for this demand and no implemented replay/stack restoration.

Connect an existing application analytics client at the Host boundary.
Consent, identity, event schema, sampling, bounded delivery, persistence, retry,
vendor integration, scroll and exposure detection remain application-owned.
A plain injected client is sufficient unless Scope/readiness/generated dependency
validation actually requires a CCRouter Service. Do not introduce a framework
Analytics contract or require Demo packages in production.

The repository's `demo/modules/analytics` and `analytics_flutter` packages are
unpublished application references, using `AppAnalytics…` and
`AppNavigationAnalyticsBridge` names. They preserve an example consent-denied
default, bounded asynchronous dispatcher, explicit targets and isolated Sink
errors. They are not part of the framework API or release set.

For any chosen implementation, make teardown explicit: the owner detaches
observers, cancels exposure dwell timers/listeners, clears visit state, and
closes its dispatcher. Network cancellation belongs to the Sink/SDK; Dart
Futures cannot be cancelled by dropping their references. Widget wrappers never
close an injected dispatcher. Keep payloads primitive and bounded; never append
Tokens, raw URI, arguments, Extra, Widgets, exceptions or business results.
An analytics failure must not change navigation, business callback results or
framework cleanup.

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
The drain is published before task callbacks, so synchronous Gate reentry also
joins it and cannot run sibling tasks twice. Do not await the owning drain from
inside its task. Callers in distinct error Zones receive their own failure
delivery, while shutdown joins cancellation through a Zone-safe cleanup barrier.

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
and its controller closed without retaining the generation lock. Initial
snapshot or session setup failures publish `failed` with stage `watch-session`;
all acquired resources and the child are cleaned up before ownership/generation
locks are released. A failed session must not publish a successful `stopped`.
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
retain `--no-cache --check` as the authoritative CI gate. For portable
distribution, explicitly opt the Package in with `ccrouter.yaml`
`generation: { portable: true }`, run `ccrouter portable prepare <host-root>`,
then validate with `ccrouter portable publish <host-root>` and commit
`lib/src/ccrouter_generated/metadata/ccrouter_generation_state.json` with its
managed output. These commands also accept a component Package root within
that role's write scope; `publish` validates locally without publishing to Pub
or Git. Ordinary local generation does not produce Portable State. The state
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
Maintain a separate `--no-cache --check` gate for every independent Host before
tests or tools that regenerate artifacts; a check against the parent Host's
dependency closure cannot detect stale output in its nested `example/`.

Framework dependencies such as `ccrouter_ui` publish no business Package Index.
Generation and `find` ignore legacy framework indexes in writable and read-only
dependencies, keeping consumer identities equal before and after cleanup.
This exemption is limited to classified framework implementation Packages;
optional business Packages still require their ordinary index and Portable
State verification.

Packages with no generated capability have no `ccrouter_generated` directory.
Removing the final declaration removes empty managed directories while
preserving unknown or handwritten files.
