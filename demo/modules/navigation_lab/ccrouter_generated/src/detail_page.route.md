# CCRouter Routes

Generated from `lib/src/detail_page.dart`. Do not edit by hand.

## `demo_navigation_lab.detail`

验证类型安全参数、Query 集合、多 Path、完整 URL、Scheme 与返回值。

- Owner: `demo_navigation_lab_component`
- Component version: `0.1.0`
- Exposure: `internal`
- Deep link: `enabled`
- Result: `String`
- Declaration: `demo_navigation_lab:lib/src/detail_page.dart` (page)
- Placement: host `default`, outlet `root`, shell `none`, parent `none`
- Presentation: `page`
- Navigation sources: `typedIntent, internalUri, externalDeepLink`
- Restoration: `unsupported`
- Contract library: `demo_navigation_lab:lib/src/ccrouter_generated/detail_page.route.g.dart`
- Patterns:
  - `/lab/detail/:id` (CCPathPattern, primary)
    - Constraints: `{"id":"\\d+"}`
  - `/lab/item/:id` (CCPathPattern)
  - `ccrouter://lab/detail/:id` (CCUriPattern)
  - `https://ccrouter.example/lab/detail/:id` (CCUriPattern)
- Parameters:

| Name | Wire name | Source | Type | Cardinality | Codec | Required | Description |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `id` | `id` | `path` | `int` | `-` | `-` | true |  |
| `title` | `title` | `query` | `String` | `single` | `-` | false |  |
| `tags` | `tags` | `query` | `List<String>` | `repeated` | `-` | false |  |
