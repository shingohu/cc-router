# CCRouter Routes

Generated from `lib/src/order_detail_route_contract.dart`. Do not edit by hand.

## `order.detail`

订单详情，确认后返回订单编号。

- Owner: `demo_order_component`
- Component version: `0.1.0`
- Exposure: `public`
- Deep link: `disabled`
- Result: `String`
- Declaration: `demo_order_contracts:lib/src/order_detail_route_contract.dart` (contract)
- Placement: host `default`, outlet `root`, shell `none`, parent `none`
- Presentation: `page`
- Navigation sources: `typedIntent, internalUri`
- Restoration: `unsupported`
- Contract library: `demo_order_contracts:lib/src/ccrouter_generated/order_detail_route_contract.route.contract.g.dart`
- Patterns:
  - `/orders/:orderId` (CCPathPattern, primary)
  - `/order/:orderId` (CCPathPattern)
- Parameters:

| Name | Wire name | Source | Type | Cardinality | Codec | Required | Description |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `orderId` | `orderId` | `path` | `int` | `-` | `-` | true | Stable order identity encoded in the path. |
| `tab` | `tab` | `query` | `String` | `single` | `-` | false | Initially selected detail tab encoded as a query value. |
