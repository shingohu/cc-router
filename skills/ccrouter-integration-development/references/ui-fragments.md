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
DTO Actions share the restricted Props schema below. Sealed unions and heterogeneous
`kind + nullable fields` modeling are outside this increment. Use ordinary public
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
functions, enhanced enums, and sealed Action unions are unsupported.
Scalar types (`String`, `int`, `bool`, `num`, `double`) are DTO field types only;
the root Action must be a plain enum or a restricted immutable DTO.
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

The Analyzer Owner diagnostic and imported-constant Quick Fix also support
resolved typedef constructors for `CCComponent` and `CCUIFragmentDependency`.
For a Contract declared in a `part` file, regenerate metadata with the updated
Generator: declaration `packageUri` keeps the part location, while `libraryUri`
records the defining library for exact type matching. Older part metadata defers
until regeneration; a shared Package and marker name alone cannot prove identity.

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

## Lifecycle and failures

- Keep a stable Key for the same instance; change the Key to reset it. List
  reorder needs stable business Keys. Independent instances never share State.
- Update Props with a new immutable value. B compares request-relevant fields,
  cancels cancellable work and uses revision tokens to ignore stale responses.
- Pass `active` explicitly for hidden Tabs/Offstage/KeepAlive. False suppresses
  Actions; B pauses polling/animations itself. It is not pixel visibility or
  authorization, and hiding does not dispose State.
- Flutter `dispose` releases owned controllers, timers and subscriptions.
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

Test real generation, required edges, type rejection, multi-instance identity,
callback updates, hidden Tab recovery, request races, Session reset, shutdown
and disposal. UI tests currently use the real default Host lifecycle; do not
assume the optional catalog follows `CCRouterTestHost` Zone overlays.

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
complete editor-time schema validation, sealed Actions and dynamic Slots remain
outside the implemented scope. Prefer ordinary Flutter composition when its
ownership and dependency boundary already meets the application need.
