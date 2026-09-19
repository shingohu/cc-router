# CCRouter Routes

Generated from `test/fixtures/annotated_routes.dart`. Do not edit by hand.

## `fixture.detail`

A typed detail route.
Includes safe defaults.

- Owner: `fixture`
- Visibility: `exported`
- Deep link: `enabled`
- Result: `String`
- Patterns:
  - `/detail/:id` (CCPathPattern, primary)
  - `/legacy/:id` (CCPathPattern)
  - `sample://detail/:id` (CCUriPattern)
  - `/old/(?<id>\d+)` (CCRegexPattern)
- Parameters:

| Name | Wire name | Source | Type | Required | Description |
| --- | --- | --- | --- | --- | --- |
| `id` | `id` | `path` | `int` | true | Stable fixture identity shown in generated route documentation. |
| `search` | `text` | `query` | `String?` | false | Optional filter whose wire name differs from this field name. |
| `tab` | `tab` | `query` | `DetailTab` | false |  |
| `enabled` | `enabled` | `query` | `bool` | false |  |
| `ratio` | `ratio` | `query` | `double` | false |  |
| `snapshot` | `snapshot` | `extra` | `Snapshot?` | false |  |

## `fixture.internal`

- Owner: `fixture`
- Visibility: `component`
- Deep link: `disabled`
- Result: `void`
- Patterns:
  - `/internal` (CCPathPattern, primary)

## `fixture.positional`

- Owner: `fixture`
- Visibility: `exported`
- Deep link: `disabled`
- Result: `int`
- Patterns:
  - `/position/:value` (CCPathPattern, primary)
- Parameters:

| Name | Wire name | Source | Type | Required | Description |
| --- | --- | --- | --- | --- | --- |
| `value` | `value` | `path` | `String` | true |  |
| `input` | `input` | `query` | `String` | false |  |

## `fixture.extra`

- Owner: `fixture`
- Visibility: `exported`
- Deep link: `disabled`
- Result: `bool`
- Patterns:
  - `/extra` (CCPathPattern, primary)
- Parameters:

| Name | Wire name | Source | Type | Required | Description |
| --- | --- | --- | --- | --- | --- |
| `snapshot` | `snapshot` | `extra` | `Snapshot` | true |  |

## `fixture.prefixed`

- Owner: `fixture`
- Visibility: `exported`
- Deep link: `disabled`
- Result: `types.Result`
- Patterns:
  - `/prefixed` (CCPathPattern, primary)
- Parameters:

| Name | Wire name | Source | Type | Required | Description |
| --- | --- | --- | --- | --- | --- |
| `mode` | `mode` | `query` | `types.Mode` | false |  |
| `payload` | `payload` | `extra` | `types.Payload?` | false |  |

