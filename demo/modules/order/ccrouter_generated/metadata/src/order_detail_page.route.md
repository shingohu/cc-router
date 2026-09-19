# CCRouter Routes

Generated from `lib/src/order_detail_page.dart`. Do not edit by hand.

## `order.detail`

订单详情，确认后返回订单编号。

- Owner: `demo_order_component`
- Visibility: `exported`
- Deep link: `disabled`
- Result: `String`
- Patterns:
  - `/orders/:orderId` (CCPathPattern, primary)
  - `/order/:orderId` (CCPathPattern)
- Parameters:

| Name | Wire name | Source | Type | Required | Description |
| --- | --- | --- | --- | --- | --- |
| `orderId` | `orderId` | `path` | `int` | true | 需要展示的稳定订单 ID。 |
| `tab` | `tab` | `query` | `String` | false | 首次展示的详情标签。 |

