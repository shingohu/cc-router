# Typed UI Fragments

Use the optional `ccrouter_ui` package when B owns a complete local UI region
and A must consume it through a contract. Use ordinary public Flutter widgets
for simple presentation reuse, Service for data-only reuse, and Route for full
destinations. A Fragment has no RouteEntry, result Future, Scope or Deep Link.

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
The current Analyzer Plugin has no UI-specific diagnostics or Quick Fix;
Generator validation is authoritative. Do not change Plugin pins for this work.

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
