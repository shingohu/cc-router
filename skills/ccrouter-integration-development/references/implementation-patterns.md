# Implementation Patterns

## Package Roles

### Host

The Host may import `ccrouter_go_router` and `ccrouter_host.dart`. It owns `CCRouter.initialize` configuration, generated Host assembly, `CCRouterApp`, navigation Backend, Shell/Outlet topology, platform Deep Link ingress, global policies and final `CCRouter.shutdown`.

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

registry.registerEvent<OrderSubmitted>(
  'analytics.order-submitted',
  (event, _) => analytics.track(event.id),
);

await CCRouter.event(const OrderSubmitted('42'));
```

## Initialization

Register tasks in the component Registrar and open their Gate from the Host:

```dart
registry.registerInitializationTask(
  CCInitializationTask(
    id: 'analytics.initialize',
    gate: const CCInitializationGate('privacy.granted'),
    dependsOn: const ['config.load'],
    failurePolicy: CCInitializationFailurePolicy.optional,
    run: (_) => analytics.initialize(),
  ),
);

await CCRouter.runInitialization(
  gate: const CCInitializationGate('privacy.granted'),
);
```

## Generation

Run one orchestration command after annotations or component graph changes:

```bash
fvm dart run ccrouter_generator:ccrouter generate demo
```

The command owns files under `lib/src/ccrouter_generated/`. Do not edit, relocate, or add imports to implementation-only binding/package/host outputs. Use a handwritten public barrel to export only intended public contracts.
