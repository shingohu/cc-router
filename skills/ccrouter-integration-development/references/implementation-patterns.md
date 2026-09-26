# Implementation Patterns

## Package Roles

### Host

The Host may import `ccrouter_go_router` and `ccrouter_host.dart`. A new GoRouter
application should prefer `CCGoRouterApp(catalog: ..., components: ...)` for the
minimal assembly path. When global policies or telemetry are needed, call
`CCRouter.initialize` explicitly and omit `components` from the widget. The Host
still owns generated Host assembly, navigation Backend, Shell/Outlet topology,
platform Deep Link ingress, global policies and final `CCRouter.shutdown`.

Use `CCRouterApp.managed` with a manually created `CCRouterAppBackend` when the
application needs a custom Backend or custom application tree. Use
`CCGoRouterBackend.attach` for an existing application-owned GoRouter; the
minimal widget is not an attach replacement and never disposes an external
Router.

Feature packages must not perform these duties.

### Component Implementation

The component owns its descriptor, private Registrar, pages, local policies, Services and message handlers. Export only intended business contracts.

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

Use `context:` only for call-site Outlet placement. Without Context, the route's declared Host/Outlet semantics remain unchanged.

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
  component: catalogComponent,
  id: 'catalog.product',
  pattern: CCPathPattern('/products/:productId'),
  description: 'Product details.',
)
final class ProductPage extends StatelessWidget {
  const ProductPage({required this.productId, super.key});
  final String productId;
}
```

Do not add a generated `part`. Import the component route API barrel after generation when callers need the generated Intent.

Use `@CCExtraParam` for a typed process-local object that must retain identity:

```dart
final class ProductDraft {
  const ProductDraft(this.id);
  final String id;
}

@CCRoute<void>(
  component: catalogComponent,
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

```dart
registry.registerService<CartRepository>(
  CCServiceProvider(
    scope: CCServiceScope.session,
    factory: (_) => CartRepositoryImpl(),
  ),
);

final repository = CCRouter.service<CartRepository>();
```

For lazy async readiness:

```dart
registry.registerService<RemoteConfig>(
  CCServiceProvider(
    factory: (_) => RemoteConfig(),
    initializer: (service, context) async {
      await service.load(context.cancellation);
    },
  ),
);

final config = await CCRouter.serviceAsync<RemoteConfig>();
```

Resolve Route Service only from the exact managed page Context:

```dart
final draft = CCRouter.routeService<DraftController>(context);
```

Initial/foreign pages do not have a managed Route Scope. Never guess from the top route.

## Command and Event

```dart
final class SubmitOrder implements CCCommand<String> {
  const SubmitOrder(this.id);
  final String id;
}

registry.registerCommand<SubmitOrder, String>((command, context) async {
  if (context.cancellation.isCancelled) {
    throw const CCInvocationCancelledError();
  }
  return submit(command.id);
});

final receipt = await CCRouter.command(const SubmitOrder('42'));
```

```dart
final class OrderSubmitted implements CCEvent {
  const OrderSubmitted(this.id);
  final String id;
}

final orderSubmittedAnalytics = const CCEventSubscriberId<OrderSubmitted>(
  'analytics.order-submitted',
);

registry.registerEventSubscriber<OrderSubmitted>(
  CCEventSubscriber<OrderSubmitted>(
    id: orderSubmittedAnalytics,
    handler: (event, _) => analytics.track(event.id),
  ),
);

await CCRouter.event(const OrderSubmitted('42'));
```

The typed ID is the identity of this subscriber, not the Event type. Assign a
different stable ID to every independent subscriber of the same Event and keep
the values in a generated or component-owned Contract constants library. The
legacy string overload remains only for existing 1.x registrars and low-level
tests.

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

Register tasks in the component Registrar and open their Gate from the Host:

Use the framework-provided `CCInitializationGate.privacyGranted` for work that
must wait for explicit privacy consent. The Host owns consent state and opens
the gate; CCRouter does not inspect or persist that state. Define a custom
`CCInitializationGate` only for a different product condition.

```dart
registry.registerInitializationTask(
  CCInitializationTask(
    id: 'analytics.initialize',
    gate: CCInitializationGate.privacyGranted,
    dependsOn: const ['config.load'],
    failurePolicy: CCInitializationFailurePolicy.optional,
    run: (_) => analytics.initialize(),
  ),
);

await CCRouter.runInitialization(
  gate: CCInitializationGate.privacyGranted,
);
```

## Generation

Run one orchestration command after annotations or component graph changes:

```bash
fvm dart run ccrouter_generator:ccrouter generate demo
```

The command owns files under `lib/src/ccrouter_generated/`. Do not edit, relocate, or add imports to implementation-only binding/package/host outputs. Use a handwritten public barrel to export only intended public contracts.
