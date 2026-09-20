# CCRouter Routes

Generated from `lib/src/failure_page.dart`. Do not edit by hand.

## `demo_navigation_lab.failure`

展示标准导航失败经 Host Failure Policy 恢复后的安全页面。

- Owner: `demo_navigation_lab_component`
- Component version: `0.1.0`
- Exposure: `internal`
- Deep link: `disabled`
- Result: `void`
- Declaration: `demo_navigation_lab:lib/src/failure_page.dart` (page)
- Placement: host `default`, outlet `root`, shell `none`, parent `none`
- Presentation: `page`
- Navigation sources: `typedIntent, internalUri`
- Restoration: `unsupported`
- Contract library: `demo_navigation_lab:lib/src/failure_page.dart`
- Patterns:
  - `/lab/failure` (CCPathPattern, primary)
- Parameters:

| Name | Wire name | Source | Type | Cardinality | Codec | Required | Description |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `stage` | `stage` | `query` | `String` | `single` | `-` | true |  |
| `errorType` | `errorType` | `query` | `String` | `single` | `-` | true |  |
