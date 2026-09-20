# CCRouter Routes

Generated from `lib/src/web_route_contracts.dart`. Do not edit by hand.

## `demo_web.public`

Loads one allowlisted public HTTPS URL in the shared Web container.

- Owner: `demo_web_component`
- Component version: `0.1.0`
- Exposure: `public`
- Deep link: `enabled`
- Result: `void`
- Declaration: `demo_web_contracts:lib/src/web_route_contracts.dart` (contract)
- Placement: host `default`, outlet `root`, shell `none`, parent `none`
- Presentation: `page`
- Navigation sources: `typedIntent, internalUri, externalDeepLink`
- Restoration: `unsupported`
- Contract library: `demo_web_contracts:lib/src/ccrouter_generated/web_route_contracts.route.contract.g.dart`
- Patterns:
  - `/web` (CCPathPattern, primary)
- Parameters:

| Name | Wire name | Source | Type | Cardinality | Codec | Required | Description |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `target` | `url` | `query` | `DemoPublicWebTarget` | `repeated` | `DemoPublicWebTargetCodec` | true | Public URL safe to serialize into navigation state. |

## `demo_web.private`

Loads a sensitive process-local request without URI serialization.

- Owner: `demo_web_component`
- Component version: `0.1.0`
- Exposure: `public`
- Deep link: `disabled`
- Result: `void`
- Declaration: `demo_web_contracts:lib/src/web_route_contracts.dart` (contract)
- Placement: host `default`, outlet `root`, shell `none`, parent `none`
- Presentation: `page`
- Navigation sources: `typedIntent, internalUri`
- Restoration: `unsupported`
- Contract library: `demo_web_contracts:lib/src/ccrouter_generated/web_route_contracts.route.contract.g.dart`
- Patterns:
  - `/web/private` (CCPathPattern, primary)
- Parameters:

| Name | Wire name | Source | Type | Cardinality | Codec | Required | Description |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `request` | `request` | `extra` | `DemoPrivateWebRequest` | `-` | `-` | true | URL, headers, and JavaScript policy retained outside the route URI. |
