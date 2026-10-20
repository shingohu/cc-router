# Typed UI Fragments

Use the optional `ccrouter_ui` package when B owns a complete local UI region
and A must consume it through a contract. Use ordinary public Flutter widgets
for simple presentation reuse, Service for data-only reuse, and Route for full
destinations. A Fragment has no RouteEntry, result Future, Scope or Deep Link.

## Check the business interaction first

Before adding declarations, check what A must receive from B. v1 Action is a
plain enum and cannot carry a selected ID or other dynamic payload. A can capture
an ID it already supplied in Props (for example, a fixed order summary). A cannot
recover the selected ID of a list loaded privately by B from an enum Action.
That interaction is not supported by the current Fragment contract. Do not use
global mutable selection, a Service returning Widget/callback, an Event detour,
or a private implementation import to make it appear supported. B may handle
the action internally if that is the actual product requirement; otherwise use
ordinary public Flutter composition with explicit ownership or defer the
Fragment integration until a data-bearing Action contract is supported.

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

The public contracts Package imports
`package:ccrouter_contracts/ccrouter_ui_contracts.dart` and exports the marker,
Props, Action and canonical `CCComponentId` through its authored public barrel.
Declare a public non-generic marker with
`@CCUIFragmentContract<Props, Action>(componentId: owner, id: ..., version: ...)`.
v1 Props are final classes with only const generative constructors, public final
stored fields, no inheritance/mixins/interfaces or declared methods. Fields may
contain scalar values, ordinary enums and nested DTOs, with supported nullable
fields. Generic collections, dynamic/Object, Flutter types, Future/Stream,
functions, enhanced enums, and sealed Action unions are unsupported.
Use a plain public enum for Action and enum fields: no authored fields, getters,
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

UI metadata schema 5 / UI schema 1 and Package Index schema 3 are opt-in.
Older generators reject these artifacts. Use matching framework/UI/generator
sources. Packages without UI retain their existing schema and generated API.
The optional Analyzer Plugin checks aliases, repeated dependencies, clearly
invalid range tokens, plain enum Actions, Renderer signatures and UI SPI access.
Required UI Owner checks share the conservative imported-public-constant Quick
Fix with Service/Command dependencies. Regenerate old metadata to provide UI
marker identity and source positions. Host completeness errors enter the IDE
only through a current validated Generator snapshot. Full schema validation is
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
`find --usage` and DevTools views remain unavailable; the only UI Quick Fix
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
