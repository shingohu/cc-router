# CCRouter Routes

Generated from `lib/src/policy_pages.dart`. Do not edit by hand.

## `demo_navigation_lab.proceed`

路由级拦截器放行示例。

- Owner: `demo_navigation_lab_component`
- Component version: `0.1.0`
- Exposure: `internal`
- Deep link: `disabled`
- Result: `void`
- Declaration: `demo_navigation_lab:lib/src/policy_pages.dart` (page)
- Placement: host `default`, outlet `root`, shell `none`, parent `none`
- Presentation: `page`
- Navigation sources: `typedIntent, internalUri`
- Restoration: `unsupported`
- Contract library: `demo_navigation_lab:lib/src/ccrouter_generated/policy_pages.route.g.dart`
- Patterns:
  - `/lab/policy/proceed` (CCPathPattern, primary)

## `demo_navigation_lab.cancel`

路由级拦截器取消示例；页面正常情况下不会创建。

- Owner: `demo_navigation_lab_component`
- Component version: `0.1.0`
- Exposure: `internal`
- Deep link: `disabled`
- Result: `void`
- Declaration: `demo_navigation_lab:lib/src/policy_pages.dart` (page)
- Placement: host `default`, outlet `root`, shell `none`, parent `none`
- Presentation: `page`
- Navigation sources: `typedIntent, internalUri`
- Restoration: `unsupported`
- Contract library: `demo_navigation_lab:lib/src/ccrouter_generated/policy_pages.route.g.dart`
- Patterns:
  - `/lab/policy/cancel` (CCPathPattern, primary)

## `demo_navigation_lab.redirect.source`

路由级拦截器重定向源页面；页面正常情况下不会创建。

- Owner: `demo_navigation_lab_component`
- Component version: `0.1.0`
- Exposure: `internal`
- Deep link: `disabled`
- Result: `void`
- Declaration: `demo_navigation_lab:lib/src/policy_pages.dart` (page)
- Placement: host `default`, outlet `root`, shell `none`, parent `none`
- Presentation: `page`
- Navigation sources: `typedIntent, internalUri`
- Restoration: `unsupported`
- Contract library: `demo_navigation_lab:lib/src/ccrouter_generated/policy_pages.route.g.dart`
- Patterns:
  - `/lab/policy/redirect-source` (CCPathPattern, primary)

## `demo_navigation_lab.redirect.target`

拦截器重定向后的目标页面。

- Owner: `demo_navigation_lab_component`
- Component version: `0.1.0`
- Exposure: `internal`
- Deep link: `disabled`
- Result: `void`
- Declaration: `demo_navigation_lab:lib/src/policy_pages.dart` (page)
- Placement: host `default`, outlet `root`, shell `none`, parent `none`
- Presentation: `page`
- Navigation sources: `typedIntent, internalUri`
- Restoration: `unsupported`
- Contract library: `demo_navigation_lab:lib/src/ccrouter_generated/policy_pages.route.g.dart`
- Patterns:
  - `/lab/policy/redirect-target` (CCPathPattern, primary)

## `demo_navigation_lab.defer`

等待外部同意后恢复的 Deferred Navigation 示例。

- Owner: `demo_navigation_lab_component`
- Component version: `0.1.0`
- Exposure: `internal`
- Deep link: `disabled`
- Result: `void`
- Declaration: `demo_navigation_lab:lib/src/policy_pages.dart` (page)
- Placement: host `default`, outlet `root`, shell `none`, parent `none`
- Presentation: `page`
- Navigation sources: `typedIntent, internalUri`
- Restoration: `unsupported`
- Contract library: `demo_navigation_lab:lib/src/ccrouter_generated/policy_pages.route.g.dart`
- Patterns:
  - `/lab/policy/defer` (CCPathPattern, primary)

## `demo_navigation_lab.timeout`

触发标准 Interceptor Timeout Error 的示例。

- Owner: `demo_navigation_lab_component`
- Component version: `0.1.0`
- Exposure: `internal`
- Deep link: `disabled`
- Result: `void`
- Declaration: `demo_navigation_lab:lib/src/policy_pages.dart` (page)
- Placement: host `default`, outlet `root`, shell `none`, parent `none`
- Presentation: `page`
- Navigation sources: `typedIntent, internalUri`
- Restoration: `unsupported`
- Contract library: `demo_navigation_lab:lib/src/ccrouter_generated/policy_pages.route.g.dart`
- Patterns:
  - `/lab/policy/timeout` (CCPathPattern, primary)

## `demo_navigation_lab.guarded`

未保存状态下拒绝 CCRouter Pop 的路由。

- Owner: `demo_navigation_lab_component`
- Component version: `0.1.0`
- Exposure: `internal`
- Deep link: `disabled`
- Result: `void`
- Declaration: `demo_navigation_lab:lib/src/policy_pages.dart` (page)
- Placement: host `default`, outlet `root`, shell `none`, parent `none`
- Presentation: `page`
- Navigation sources: `typedIntent, internalUri`
- Restoration: `unsupported`
- Contract library: `demo_navigation_lab:lib/src/ccrouter_generated/policy_pages.route.g.dart`
- Patterns:
  - `/lab/policy/guarded` (CCPathPattern, primary)
