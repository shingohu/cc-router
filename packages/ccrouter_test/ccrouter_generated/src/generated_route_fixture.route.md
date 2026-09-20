# CCRouter Routes

Generated from `lib/src/generated_route_fixture.dart`. Do not edit by hand.

## `generated_route_fixture.detail`

Generated route fixture with safe defaults.

- Owner: `generated_route_fixture`
- Component version: `1.0.0`
- Exposure: `internal`
- Deep link: `enabled`
- Result: `String`
- Declaration: `ccrouter_test:lib/src/generated_route_fixture.dart` (page)
- Placement: host `default`, outlet `root`, shell `none`, parent `none`
- Presentation: `page`
- Navigation sources: `typedIntent, internalUri, externalDeepLink`
- Restoration: `unsupported`
- Contract library: `ccrouter_test:lib/src/ccrouter_generated/generated_route_fixture.route.g.dart`
- Patterns:
  - `/generated/detail/:id` (CCPathPattern, primary)
    - Constraints: `{"id":"\\d+"}`
  - `/generated/legacy/:id` (CCPathPattern)
  - `generated://detail/:id` (CCUriPattern)
  - `/generated/old/(?<id>\d+)` (CCRegexPattern)
- Parameters:

| Name | Wire name | Source | Type | Cardinality | Codec | Required | Description |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `id` | `id` | `path` | `int` | `-` | `-` | true | Stable fixture identity. |
| `search` | `text` | `query` | `String?` | `single` | `-` | false | Optional search text. |
| `tab` | `tab` | `query` | `GeneratedDetailTab` | `single` | `-` | false | Selected tab. |
| `enabled` | `enabled` | `query` | `bool` | `single` | `-` | false | Boolean scalar codec probe. |
| `ratio` | `ratio` | `query` | `double` | `single` | `-` | false | Finite double codec probe. |
| `snapshot` | `snapshot` | `extra` | `GeneratedSnapshot?` | `-` | `-` | false | Optional in-memory snapshot. |

## `generated_route_fixture.internal`

- Owner: `generated_route_fixture`
- Component version: `1.0.0`
- Exposure: `internal`
- Deep link: `disabled`
- Result: `void`
- Declaration: `ccrouter_test:lib/src/generated_route_fixture.dart` (page)
- Placement: host `default`, outlet `root`, shell `none`, parent `none`
- Presentation: `page`
- Navigation sources: `typedIntent, internalUri`
- Restoration: `unsupported`
- Contract library: `ccrouter_test:lib/src/ccrouter_generated/generated_route_fixture.route.g.dart`
- Patterns:
  - `/generated/internal` (CCPathPattern, primary)

## `generated_route_fixture.positional`

- Owner: `generated_route_fixture`
- Component version: `1.0.0`
- Exposure: `internal`
- Deep link: `disabled`
- Result: `int`
- Declaration: `ccrouter_test:lib/src/generated_route_fixture.dart` (page)
- Placement: host `default`, outlet `root`, shell `none`, parent `none`
- Presentation: `page`
- Navigation sources: `typedIntent, internalUri`
- Restoration: `unsupported`
- Contract library: `ccrouter_test:lib/src/ccrouter_generated/generated_route_fixture.route.g.dart`
- Patterns:
  - `/generated/position/:value` (CCPathPattern, primary)
- Parameters:

| Name | Wire name | Source | Type | Cardinality | Codec | Required | Description |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `value` | `value` | `path` | `String` | `-` | `-` | true | Path value. |
| `input` | `input` | `query` | `String` | `single` | `-` | false | Optional positional query value. |

## `generated_route_fixture.extra`

- Owner: `generated_route_fixture`
- Component version: `1.0.0`
- Exposure: `internal`
- Deep link: `disabled`
- Result: `bool`
- Declaration: `ccrouter_test:lib/src/generated_route_fixture.dart` (page)
- Placement: host `default`, outlet `root`, shell `none`, parent `none`
- Presentation: `page`
- Navigation sources: `typedIntent, internalUri`
- Restoration: `unsupported`
- Contract library: `ccrouter_test:lib/src/ccrouter_generated/generated_route_fixture.route.g.dart`
- Patterns:
  - `/generated/extra` (CCPathPattern, primary)
- Parameters:

| Name | Wire name | Source | Type | Cardinality | Codec | Required | Description |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `snapshot` | `snapshot` | `extra` | `GeneratedSnapshot` | `-` | `-` | true | Required snapshot retained by identity. |

## `generated_route_fixture.prefixed`

- Owner: `generated_route_fixture`
- Component version: `1.0.0`
- Exposure: `internal`
- Deep link: `disabled`
- Result: `GeneratedRouteResult`
- Declaration: `ccrouter_test:lib/src/generated_route_fixture.dart` (page)
- Placement: host `default`, outlet `root`, shell `none`, parent `none`
- Presentation: `page`
- Navigation sources: `typedIntent, internalUri`
- Restoration: `unsupported`
- Contract library: `ccrouter_test:lib/src/ccrouter_generated/generated_route_fixture.route.g.dart`
- Patterns:
  - `/generated/prefixed` (CCPathPattern, primary)
- Parameters:

| Name | Wire name | Source | Type | Cardinality | Codec | Required | Description |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `mode` | `mode` | `query` | `GeneratedRouteMode` | `single` | `-` | false | Imported enum value. |
| `payload` | `payload` | `extra` | `GeneratedRoutePayload?` | `-` | `-` | false | Optional imported payload. |
