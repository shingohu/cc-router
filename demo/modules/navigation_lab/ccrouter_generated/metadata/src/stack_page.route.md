# CCRouter Routes

Generated from `lib/src/stack_page.dart`. Do not edit by hand.

## `demo_navigation_lab.stack`

交互验证 Push、Replace、组合栈操作与精确 Route Entry 句柄。

- Owner: `demo_navigation_lab_component`
- Component version: `0.1.0`
- Exposure: `internal`
- Deep link: `disabled`
- Result: `String`
- Declaration: `demo_navigation_lab:lib/src/stack_page.dart` (page)
- Placement: host `default`, outlet `root`, shell `none`, parent `none`
- Presentation: `page`
- Navigation sources: `typedIntent, internalUri`
- Restoration: `unsupported`
- Contract library: `demo_navigation_lab:lib/src/stack_page.dart`
- Patterns:
  - `/lab/stack/:level` (CCPathPattern, primary)
- Parameters:

| Name | Wire name | Source | Type | Cardinality | Codec | Required | Description |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `level` | `level` | `path` | `int` | `-` | `-` | true |  |
