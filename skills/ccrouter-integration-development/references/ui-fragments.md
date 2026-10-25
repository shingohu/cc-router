# Typed UI Fragments

Use the optional `ccrouter_ui` package when B owns a complete local UI region
and A must consume it through a contract. Use ordinary public Flutter widgets
for simple presentation reuse, Service for data-only reuse, and Route for full
destinations. A Fragment has no RouteEntry, result Future, Scope or Deep Link.

## Check the business interaction first

Before adding declarations, check what A must receive from B. Use a plain enum
for payload-free notification when A already knows the relevant input ID. Use a
single immutable DTO Action when B privately loads or discovers the selected ID:

```dart
final class RecommendationSelected {
  const RecommendationSelected({required this.selectedId});
  final String selectedId;
}
```

Declare it as the Contract's Action type and explicitly export it with all nested
types. B calls `input.onAction(RecommendationSelected(selectedId: loaded.id))`;
A receives the exact type through its generated Client's `onAction`. The payload
is process-local and synchronous, with no JSON conversion or diagnostic retention.
DTO Actions without unions share the restricted Props schema below. Use a restricted sealed union for heterogeneous actions instead of
`kind + nullable fields` modeling. Use ordinary public
Flutter composition when Fragment version/assembly guarantees are unnecessary;
never route selection through global state, a Service getter or a broadcast Event.

## Complete first integration path

The short generated call is only the last step. Reuse existing Packages where
possible; this feature does not require creating a new contracts Package for
each Fragment. The first integration crosses these authored edit points:

| Role | Authored changes | Check |
| --- | --- | --- |
| Pure Dart contracts | Direct `ccrouter_contracts` dependency, marker/Props/Action, explicit public exports including the Owner ID | No Flutter dependency; all referenced schema types are public |
| B implementation | Direct contracts and `ccrouter_ui` dependencies, annotated top-level Renderer | Returns an ordinary Widget; State owns asynchronous work and resources |
| A consumer | Direct contracts and `ccrouter_ui` dependencies, required Owner edge and `uiDependencies`, page call | Imports its own stable UI Client, never B's implementation |
| Host | Resolved A/B implementation dependencies and direct `ccrouter_ui` dependency, normal generation | Initialize once with the generated Assembly; no handwritten UI registry |

Every participating contracts, A and B Package also declares `ccrouter_generator`
in `dev_dependencies`; the Host declares both `ccrouter_generator` and
`build_runner`. A Host's generator dependency alone does not activate Builders
for all dependency Packages. Confirm the generated component/UI counts before
using `find`; a successful command with empty indexes is not a completed integration.
The `ccrouter_ui` runtime is a framework Package and does not require business
component Portable State. External business Packages still publish their own
verified generated state; do not disable that check to complete an integration.

For example, an existing Pure Dart contracts Package can declare:

```dart
import 'package:ccrouter_contracts/ccrouter_contracts.dart' show CCComponentId;
import 'package:ccrouter_contracts/ccrouter_ui_contracts.dart';

const orderComponentId = CCComponentId('order_component');

final class OrderSummaryProps {
  const OrderSummaryProps({required this.orderId});
  final int orderId;
}

enum OrderSummaryAction { openDetails }

@CCUIFragmentContract<OrderSummaryProps, OrderSummaryAction>(
  componentId: orderComponentId,
  id: 'order.summary',
  version: '1.0.0',
)
abstract final class OrderSummaryFragmentContract {}
```

Its public barrel explicitly exports `orderComponentId`,
`OrderSummaryFragmentContract`, `OrderSummaryProps` and `OrderSummaryAction`.
Reuse the canonical Owner ID when one already exists. B's existing `CCComponent`
uses that same ID. Its Renderer imports `ccrouter_ui.dart`, the public contracts
and Flutter's `material.dart`:

```dart
@CCUIFragmentRenderer(OrderSummaryFragmentContract)
Widget renderOrderSummary(
  CCUIFragmentRenderInput<OrderSummaryProps, OrderSummaryAction> input,
) => TextButton(
  onPressed: input.active
      ? () => input.onAction(OrderSummaryAction.openDetails)
      : null,
  child: Text('Order ${input.props.orderId}'),
);
```

A imports `ccrouter.dart`, `ccrouter_ui.dart` and the public contracts in its
component definition:

```dart
const accountComponent = CCComponent(
  id: CCComponentId('account_component'),
  version: '0.1.0',
  dependencies: [orderComponentId],
  uiDependencies: [
    CCUIFragmentDependency<OrderSummaryFragmentContract>(
      versionRange: '^1.0.0',
      alias: 'orderSummary',
    ),
  ],
);
```

After Host generation, A imports its own
`src/ccrouter_generated/account_component.ui.api.g.dart` and composes:

```dart
AccountComponentFragments.orderSummary(
  key: const ValueKey('summary'),
  props: const OrderSummaryProps(orderId: 1001),
  onAction: (action) {
    // A already knows orderId 1001 and decides how to handle openDetails.
  },
)
```

Run the installed CLI's `ccrouter generate <host-root>`, then analyze and test
the actual consumer. Finish with `ccrouter generate <host-root> --no-cache --check`
after stopping any active watch. In this framework repository, the Host is
`demo`, and the executable is
`fvm dart run --verbosity=error ccrouter_generator:ccrouter`. A successful root
Workspace Pub get is not a Host generation check. Generated code, fingerprints
and Assembly glue are never authored manually.

## Contracts and dependencies

### Scaffold and inspect a first Fragment

The optional CLI scaffold reuses an existing Owner constant and creates new
authored files only. For an existing Pure Dart contracts Package, preview:

```bash
ccrouter create ui-fragment OrderBadge demo/modules/order_contracts \
  --owner-source lib/src/order_detail_route_contract.dart \
  --owner-symbol demoOrderComponentId --id order.badge \
  --renderer-root demo/modules/order --dry-run
```

Remove `--dry-run` to create `lib/src/order_badge_fragment.dart`, the explicit
public barrel `lib/order_badge_fragment.dart`, and the optional Owner Renderer.
The Owner source must be an authored library in this contracts Package declaring
the requested public top-level const. Semantic `CCComponentId` identity and the
Renderer's true Owner are verified during generation. A scaffold is not proof
that the chosen business schema or Owner is correct.
Without `--renderer-root`, only the Contract and public barrel are created.
Existing targets, linked parents and nested Package targets are refused.
Pubspecs, existing barrels/component definitions and generated output remain
unchanged; the printed steps name the required direct Pub/Owner/UI/Host edits.
In the Consumer component definition, import both the new public Contract barrel
and `package:ccrouter_ui/ccrouter_ui.dart` before adding `CCUIFragmentDependency`.
Choose dependency sources explicitly, complete the templates, resolve Pub and
generate the actual Host. The starter Props uses an `itemId` already known by A;
its enum Action is a starter notification. Replace it with a restricted DTO for dynamic selection payloads.

Then inspect a proven recipe for an existing consumer:

```bash
ccrouter find order.summary demo --usage demo_navigation_lab_component
```

UI lookup reads validated Package indexes, locates Contract/Renderer declarations
and reports complete schema public imports, direct dependencies, the required
Owner edge and the declared UI alias. The stable Client retains the full
component ID (`DemoNavigationLabComponentFragments`, including `Component`).
Missing UI dependencies receive a placeholder alias, not a claimed generated
method. Old indexes without public-type import proofs or alias defer until
regeneration; the command never scans source, edits files or runs generation.
Same-owner usage points to the ordinary local Widget.

The public contracts Package imports
`package:ccrouter_contracts/ccrouter_ui_contracts.dart` and exports the marker,
Props, Action and canonical `CCComponentId` through its authored public barrel.
Declare a public non-generic marker with
`@CCUIFragmentContract<Props, Action>(componentId: owner, id: ..., version: ...)`.
Props and DTO Actions are final classes with only const generative constructors, public final
stored fields, no inheritance/mixins/interfaces or declared methods. Fields may
contain scalar values, ordinary enums and nested DTOs, with supported nullable
fields. Generic collections, dynamic/Object, Flutter types, Future/Stream,
functions and enhanced enums are unsupported. Action unions use the separate
schema 3 rules below; sealed types remain unsupported in Props.
Scalar types (`String`, `int`, `bool`, `num`, `double`) are DTO field types only;
the root Action must be a plain enum, restricted immutable DTO or restricted
sealed union.
Enum Actions and DTO enum fields must be plain public enums: no authored fields, getters,
setters, methods, constructors, mixins or interfaces, including static members.
DTO constructors accept only `this.field` parameters. Each stored field must
either have a constant declaration initializer or be initialized by every
constructor's `this.field` parameter. Initializer-list assignments and redirecting
constructors are rejected; move defaults to `this.field = value` or the field
declaration. Breaking behavior or shape needs SemVer review; fingerprints include
effective parameter defaults, effective field initializers and enum values, not
just type names. Equivalent constant expressions produce the same fingerprint.

The consuming `CCComponent` imports `ccrouter_ui.dart` and declares:

```dart
uiDependencies: [
  CCUIFragmentDependency<OrderSummaryFragmentContract>(
    versionRange: '^1.0.0',
    alias: 'orderSummary',
  ),
],
```

The Owner must also appear in required `dependencies`; optional owners cannot
satisfy this edge. Aliases and contract edges must be unique. The generated
Client name is the PascalCase full component ID plus `Fragments`.
Version ranges use the shared Contract grammar: exact, `*`, caret, tilde, or
one or more `>=`/`>`/`<=`/`<` comparators separated by whitespace,
including tabs/newlines. A single comparator such as `>=1.0.0` is valid; the
Host still checks the installed version and exact schema fingerprint.

The Analyzer Owner diagnostic and imported-constant Quick Fix also support
resolved typedef constructors for `CCComponent` and `CCUIFragmentDependency`.
For a Contract declared in a `part` file, regenerate metadata with the updated
Generator: declaration `packageUri` keeps the part location, while `libraryUri`
records the defining library for exact type matching. Older part metadata defers
until regeneration; a shared Package and marker name alone cannot prove identity.

### Sealed Action unions (UI schema 3)

Use a sealed union when one Fragment emits actions with different payloads.
Props retain the existing DTO-only rules. An Action may be a union itself or
an immutable DTO containing a union. Unions can nest through allowed data fields:

```dart
sealed class SelectionTarget {
  const SelectionTarget(this.id);
  final String id;
}
final class SelectedUser extends SelectionTarget {
  const SelectedUser(super.id);
}
final class SelectedScore extends SelectionTarget {
  const SelectedScore(super.id);
}
sealed class PanelAction { const PanelAction(); }
final class SettingsRequested extends PanelAction {
  const SettingsRequested();
}
final class TargetSelected extends PanelAction {
  const TargetSelected(this.target);
  final SelectionTarget target;
}
```

Declare `PanelAction` as the Contract's Action and export the root, every variant,
all nested data types and the marker through authored public barrels. The consumer
receives `PanelAction` and can exhaustively switch on both unions. The Demo's
`order.panel` adds this path alongside the existing enum and DTO Fragments.

Each sealed root directly extends Object. All direct subtypes must be public,
non-generic final concrete classes extending that root in the same Dart library,
including its `part` files. Final leaves cannot have further subtypes; interfaces,
mixins, extra sealed inheritance levels and overriding inherited fields are
rejected. Type identity uses the defining library URI and symbol, not the part
file location. A nested union may belong to a separate Pure Dart contracts Package;
its variants remain in that union's defining library.

Only public final stored scalar, plain enum, DTO or union fields are allowed.
Every constructor is const and generative. Constructors accept `this.field`
and leaves may use `super.field` to forward directly to base field parameters.
Implicit unnamed const super construction, base field initializers and optional
parameter defaults are supported. Explicit initializer lists (including explicit
`super(...)` calls and asserts), redirects, factories and executable members are
rejected. The data graph must be acyclic and fit within 32 data levels and 512
expanded schema nodes, counting field/parameter schemas and variants.

Fingerprints include the sorted complete variant set, inherited field schemas,
constructor/forwarding/default semantics and concrete types of constant defaults.
Changing `const SelectedUser('x')` to `const SelectedScore('x')` changes the shape.
Reordering variants or moving them between parts of the same library is inert.

Union Actions require UI schema 3 / Package Index schema 5 and compatible tooling.
Mixed documents use the highest required UI version. Legacy enum/DTO contracts keep
their original fingerprints and output versions. SDK scalar modifiers (including
sealed num) never opt a DTO into the union schema. Migrating enum/DTO to a union,
adding/removing union variants, or breaking nested payload shape needs a major
Contract version, an updated consumer range and regeneration of A/B/Host.
Exact Host fingerprints are still required even when SemVer ranges match.
Distributed Packages must regenerate Portable State; modifying a part or a
variant invalidates the published proof. Older tools reject Index 5.

The sink remains synchronous and instance-local. It does not serialize Actions,
return a navigation Future or own account cleanup/session work. Use the existing
active, unmount, capability identity and Runtime generation rules. The Plugin
checks proven union/data violations; complete constructor syntax, defaults,
export proofs and the final schema remain Generator-owned.

## Rendering and consuming

The Owner implementation directly depends on `ccrouter_ui` and declares a public
synchronous top-level function annotated `@CCUIFragmentRenderer(Contract)`.
It accepts exactly one `CCUIFragmentRenderInput<Props, Action>` and returns
`Widget`. Return an ordinary Widget; do not allocate controllers, subscribe,
perform I/O or navigate in this factory. Stateful resources belong in State.

A directly depends on `ccrouter_ui`, imports its own stable generated
`src/ccrouter_generated/<componentId>.ui.api.g.dart` and calls the generated
method with `key`, `props`, `onAction`, and optional `active` (default true).
The generated method returns a normal Widget. The public API does not require
Context, registry lookup, Runtime construction or owner implementation imports.
Generated `ui/*.ui.g.dart` files and `ccrouter_ui_generated.dart` remain SPI.

When its resolved closure declares a UI consumer, Host directly depends on
`ccrouter_ui`, runs normal generation, and passes the
one generated Assembly to `CCRouterHost.initialize`. Generated code uses
`ccrouter_ui_host.dart`; feature code must not import it. A handwritten test
may compose `CCUIHostAssembly.attach` with generated contributions; production
code never writes versions/fingerprints by hand. Required missing, duplicate,
owner-mismatched, stale or incompatible implementations fail before startup.
No first-match fallback, dynamic replacement or multiple-contributor Slot exists.
Installing a Renderer-only component does not opt an otherwise non-UI Host into
the UI catalog or require that Host to add `ccrouter_ui` directly.
Package-local generation does not require unrelated implementations; finish
integration with actual Host `generate --no-cache --check`.

Source metadata schema 5 remains opt-in for UI. Enum contracts retain UI schema 1 and Package
Index schema 3 with unchanged shape fingerprints and signatures. DTO Actions use
UI schema 2 and Package Index schema 4; Contract, Renderer and consumer records
carry the required version and mixed documents declare the highest UI version.
Union Actions use UI schema 3 / Package Index schema 5, including DTO Actions
with nested union fields; old readers reject these indexes.
Older generators reject these artifacts. Changing an enum Action to DTO requires
major Contract SemVer, updated consumer range and regeneration of A/B/Host. Use matching framework/UI/generator
sources. Packages without UI retain their existing schema and generated API.
The optional Analyzer Plugin checks aliases, repeated dependencies, clearly
invalid range tokens, enum/DTO Actions, Renderer signatures and UI SPI access.
Required UI Owner checks share the conservative imported-public-constant Quick
Fix with Service/Command dependencies. Regenerate old metadata to provide UI
marker identity and source positions. Host completeness errors enter the IDE
only through a current validated Generator snapshot. Complete constructor/default/schema validation is
still Generator-owned; see [IDE setup and boundaries](ide-analysis-server.md).
Plugin updates follow the two-stage remote commit then Demo pin workflow.
Dependency checks and fixes require an actual framework constructor; a function
returning `CCComponent` or `CCUIFragmentDependency<T>` does not establish that
identity. Metadata distinguishes same-name markers by their declaration library;
ambiguous parser-only evidence still defers. A Renderer nested inside a function
or method is invalid even when its signature matches the Contract.

## Repair generation failures

Builder errors point to the authored declaration. Start with that error before
reading generated glue. UI consumer errors include the consumer and contract:

| Error | Correction |
| --- | --- |
| `dependencyMissing` | Add the public Owner ID to the consumer's `CCComponent.dependencies`; `optionalDependencies` is insufficient. Same-owner UI should use its ordinary local Widget. |
| `invalidAlias` | Choose a valid Dart member name outside the generated Client's reserved members. |
| `duplicateAlias` | Give different Fragment dependencies unique aliases. |
| `duplicateDependency` | Keep one dependency for the same Owner/contract; render multiple instances through its one generated method. |
| Invalid `versionRange` | Supply a supported SemVer range matching the public Contract; do not guess a component version. |
| `missingImplementation` | Ensure the required Owner implementation and its annotated Renderer participate in the actual Host dependency closure, then regenerate that Host. |

Aliases name generated methods, not mounted instance identities. Multiple cards
of the same Fragment use one dependency and distinct stable business Keys.
Do not add duplicate dependencies just to render a second card. UI-specific
DevTools views remain unavailable; the only UI Quick Fix
is the proven missing required Owner edge described above.

## Adapting a Host Assembly

Pass `ccrouterGeneratedHostAssembly` directly for normal startup. When a Host
test needs an extra handwritten component or a changed route Catalog, use:

```dart
final assembly = CCHostAssembly.extend(
  ccrouterGeneratedHostAssembly,
  additionalComponents: [testComponentManifest],
  routeCatalog: adjustedRouteCatalog, // Omit to keep the existing destinations.
);
```

This Host-only path preserves the original Package provenance, Contract Bundle,
Host Tool Integrations and lifecycle bindings, including the UI catalog plan.
It revalidates and orders the extended component graph and normalizes Catalog
component versions. Existing component IDs cannot be replaced or removed;
duplicate IDs and missing dependencies remain errors. Appended handwritten
components do not create Package bundles. New generated Contracts, Renderers
or consumer edges require regeneration. Bindings are shared plans: shut down
one Host before initializing another derived from the same Assembly.

`CCHostAssembly.fromComponents` builds fresh handwritten inputs. Reconstructing
a generated Assembly field by field loses its lifecycle bindings and Package
provenance. A Host can initialize successfully while a later Fragment build
fails with `runtimeUnavailable` because UI is optional. That error now points
to complete Assembly wiring, `extend`, and the explicit UI test helper; it does
not infer that every unavailable catalog was caused by a missing binding.

## Lifecycle and failures

- Keep a stable Key for the same instance; change the Key to reset it. List
  reorder needs stable business Keys. Independent instances never share State.
- Update Props with a new immutable value. B compares request-relevant fields,
  cancels cancellable work and uses revision tokens to ignore stale responses.
- Pass `active` explicitly for hidden Tabs/Offstage/KeepAlive. False suppresses
  Actions; B pauses polling/animations itself. It is not pixel visibility or
  authorization, and hiding does not dispose State.
  The guard runs only when forwarding `onAction`. Analytics or local navigation
  performed before it still happens unless B checks current State first.
  `input.active` is a build snapshot; retaining that old value is insufficient.
- Flutter `dispose` releases owned controllers, timers and subscriptions.
  Unmount or capability identity changes also revoke the framework Action sink
  and clear its consumer callback reference. Retaining only an old sink does not
  retain Fragment State/Props; retaining render input or Props yourself still
  requires your own cleanup.
  `deactivate` is not terminal. App/Session Services retain their existing Scope
  ownership; cross-component Route-scoped Service Proxy remains unsupported.
- On Session change, clear old account data and invalidate pending work. A Host
  may remount the subtree by Session Key; the framework cannot guess identity.
- Unmount UI before shutdown when possible. Shutdown invalidates callbacks,
  but cannot call an arbitrary State.dispose or forcibly cancel a Dart Future.
  Reinitialization requires an explicit remount; old-generation callbacks are
  never replayed into the new Runtime. Mounted UI reports unavailable/mismatch
  on its next build, rather than silently adopting a new Runtime.
- Handle loading, empty, retry and business errors in B. A chooses placement
  and response to typed Actions. Callback errors follow Flutter error handling,
  with no swallow, retry or automatic Event publication.

Host may inspect `CCUIHostAssembly.diagnostics`: at most 128 sanitized lifecycle
and ignored-action summaries, no Props, payloads, Context or callbacks. It is
local troubleshooting, not an audit log or pixel exposure tracking.

### Retained callbacks and asynchronous results

The Demo's `order_fragment_renderers.dart` shows a complete Renderer-owned State:
it cancels its fake request Timer, invalidates request revisions on Props/activity
changes, and disposes its controller. Its business callbacks read current State
when invoked, even if Flutter has already replaced the button callback:

```dart
void select() {
  if (!mounted || !widget.active) return;
  final result = currentResult;
  if (result == null) return;
  // Put application analytics/local navigation here, after current checks.
  widget.onAction(result.selectedId);
}
```

For async work, capture a revision and relevant Props/Session identity before
starting; on completion verify `mounted`, current activity and that revision
before changing State or performing side effects. Increment the revision when
activity, Props or Session changes, and on disposal; cancel work when its API
supports it. This prevents a response started before hiding from being accepted
after a hide/show cycle. Disabling the button only on rebuild cannot revoke
previously captured business closures. The framework still independently guards
the Action sink after hiding, identity change, unmount and shutdown.

## Testing with the real Host

Use `ccrouter_test` only as a dev/test dependency. The explicit UI entry is:

```dart
import 'package:ccrouter_test/ccrouter_ui_test.dart';

testWidgets('generated Fragment lifecycle', (tester) async {
  final host = CCUIFragmentTestHost(
    hostAssembly: ccrouterGeneratedHostAssembly,
  );
  addTearDown(host.dispose);
  await host.run(
    () async {
      // Application-owned fixture calls A's real generated UI Client.
      await tester.pumpWidget(createConsumerFixture());
      await tester.pump(const Duration(milliseconds: 200));
      // Assert real rendering, actions, State and relevant failure paths.
    },
    unmount: () => tester.pumpWidget(const SizedBox()),
  );
});
```

Create/run the Host inside `testWidgets` to share its fake scheduler, and drive
Timer-based loading explicitly. The helper starts the complete Assembly, awaits
the body, then awaits caller-supplied UI unmount and Host shutdown. It does not
mock Renderer lookup, Contract checks or Action revocation. Each helper runs
once; create another for the next generation. Await all body work.

Always register `addTearDown(host.dispose)` before `run`. A test-framework
timeout does not cancel a pending Dart Future, so `run`'s `finally` alone cannot
release a Host whose body never finishes. `dispose` independently unmounts and
shuts down the owned Host without waiting for that body. Normal completion,
concurrent calls and teardown join one cleanup. Late callers replay the stored
outcome in their own Zone without waiting on an ended fake scheduler. A later
body completion cannot unmount again or close a replacement Host. Disposing
before `run` prevents startup; reentrant disposal during startup waits for it
to unwind and skips the body. The caller's unmount must itself complete.

Cleanup continues through body and unmount failures and returns the earliest
initialization/body/unmount/shutdown error with its original stack. Initialization
rollback completes before the returned Future settles. An initialization failure
never calls the caller's unmount callback. Existing default Hosts and TestHost
Zone overlays are rejected without disposal; overlapping default Hosts cannot
run concurrently. If the body explicitly replaces its Host, the helper will
not close the replacement. It adds no Runtime or UI instances to global caches.
Each `dispose` caller must handle the returned Future. If cleanup failure was
already asserted by the test, the registered teardown must handle that same
failure too. `run` preserves a body failure over cleanup errors; `dispose`
reports the cleanup outcome. Never await it from its own unmount or an owned
disposable, and keep application cancellation of unfinished body work explicit.

Test real generation, missing/incompatible Renderer, Props/callback updates,
multi-instance stable Keys, hidden Tab recovery, request races, Session reset,
unmount, shutdown and late Actions between tests. Use the component-local
fixture pattern in the Demo: it consumes its own generated Client, and Host
tests supply the real generated Assembly. Ordinary `CCRouterTestHost` remains
appropriate for isolated Runtime/Facade tests; its Zone overlay does not switch
the optional UI catalog. See [generation guidance](implementation-patterns.md#sharing-build_runner-with-other-generators)
when FlutterGen or another Builder uses the same build graph.

## Adoption status and completion checks

The local enum/DTO workflow has been verified in a separate consumer Pub
Workspace using copied framework sources outside that Workspace: scaffold
preview/create, explicit configuration, generation, lookup, typed rendering and
callbacks, Owner rejection, DTO migration and reference freshness checks.
Four Widget tests covered the enum and DTO paths. This is agent-executed
technical validation; no uninvolved developer was timed or interviewed.

For an adoption change, complete these steps before calling it integrated:

1. Resolve each participating Package's direct dependencies and generator
   prerequisites. Confirm the actual Host sees the intended components/UI records.
2. Generate, then use `find --usage` to inspect the proven imports, required
   Owner and actual Client alias. Keep the generated Client in its owning
   component; Host tests may use a component-local test fixture with real Assembly.
3. Verify typed output, independent instances, current Props/callbacks and
   applicable inactive, request-race, Session, unmount and shutdown behavior.
4. Run analysis, focused tests and actual Host `generate --no-cache --check`.
   Keep existing enum contracts as a compatibility control when migrating DTOs.

The public API is not finally frozen. Independent human first use, published
installation/upgrades, real platform/device coverage, production backend data,
and long-term memory/performance require separate evidence. UI DevTools Catalog,
complete editor-time schema validation and dynamic Slots remain
outside the implemented scope. Prefer ordinary Flutter composition when its
ownership and dependency boundary already meets the application need.
