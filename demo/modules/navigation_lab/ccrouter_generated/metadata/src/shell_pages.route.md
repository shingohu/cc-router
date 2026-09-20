# CCRouter Routes

Generated from `lib/src/shell_pages.dart`. Do not edit by hand.

## `demo_navigation_lab.shell.feed`

ShellRoute 共享框架中的内容首页。

- Owner: `demo_navigation_lab_component`
- Component version: `0.1.0`
- Exposure: `internal`
- Deep link: `disabled`
- Result: `void`
- Declaration: `demo_navigation_lab:lib/src/shell_pages.dart` (page)
- Placement: host `default`, outlet `shell.content`, shell `demo_navigation_lab.single_shell`, parent `none`
- Presentation: `page`
- Navigation sources: `typedIntent, internalUri`
- Restoration: `unsupported`
- Contract library: `demo_navigation_lab:lib/src/shell_pages.dart`
- Patterns:
  - `/shell/feed` (CCPathPattern, primary)

## `demo_navigation_lab.shell.detail`

ShellRoute 嵌套子路由。

- Owner: `demo_navigation_lab_component`
- Component version: `0.1.0`
- Exposure: `internal`
- Deep link: `disabled`
- Result: `void`
- Declaration: `demo_navigation_lab:lib/src/shell_pages.dart` (page)
- Placement: host `default`, outlet `shell.content`, shell `demo_navigation_lab.single_shell`, parent `demo_navigation_lab.shell.feed`
- Presentation: `page`
- Navigation sources: `typedIntent, internalUri`
- Restoration: `unsupported`
- Contract library: `demo_navigation_lab:lib/src/shell_pages.dart`
- Patterns:
  - `/shell/feed/:item` (CCPathPattern, primary)
- Parameters:

| Name | Wire name | Source | Type | Cardinality | Codec | Required | Description |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `item` | `item` | `path` | `int` | `-` | `-` | true |  |

## `demo_navigation_lab.shell.settings`

ShellRoute 共享框架中的设置页。

- Owner: `demo_navigation_lab_component`
- Component version: `0.1.0`
- Exposure: `internal`
- Deep link: `disabled`
- Result: `void`
- Declaration: `demo_navigation_lab:lib/src/shell_pages.dart` (page)
- Placement: host `default`, outlet `shell.content`, shell `demo_navigation_lab.single_shell`, parent `none`
- Presentation: `page`
- Navigation sources: `typedIntent, internalUri`
- Restoration: `unsupported`
- Contract library: `demo_navigation_lab:lib/src/shell_pages.dart`
- Patterns:
  - `/shell/settings` (CCPathPattern, primary)

## `demo_navigation_lab.workspace.home`

StatefulShellRoute 首页分支。

- Owner: `demo_navigation_lab_component`
- Component version: `0.1.0`
- Exposure: `internal`
- Deep link: `disabled`
- Result: `void`
- Declaration: `demo_navigation_lab:lib/src/shell_pages.dart` (page)
- Placement: host `default`, outlet `workspace.home`, shell `demo_navigation_lab.workspace_shell`, parent `none`
- Presentation: `page`
- Navigation sources: `typedIntent, internalUri`
- Restoration: `unsupported`
- Contract library: `demo_navigation_lab:lib/src/shell_pages.dart`
- Patterns:
  - `/workspace/home` (CCPathPattern, primary)

## `demo_navigation_lab.workspace.detail`

StatefulShellRoute 首页分支的可 Deep Link 子路由。

- Owner: `demo_navigation_lab_component`
- Component version: `0.1.0`
- Exposure: `internal`
- Deep link: `enabled`
- Result: `void`
- Declaration: `demo_navigation_lab:lib/src/shell_pages.dart` (page)
- Placement: host `default`, outlet `workspace.home`, shell `demo_navigation_lab.workspace_shell`, parent `demo_navigation_lab.workspace.home`
- Presentation: `page`
- Navigation sources: `typedIntent, internalUri, externalDeepLink`
- Restoration: `unsupported`
- Contract library: `demo_navigation_lab:lib/src/shell_pages.dart`
- Patterns:
  - `/workspace/home/:item` (CCPathPattern, primary)
- Parameters:

| Name | Wire name | Source | Type | Cardinality | Codec | Required | Description |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `item` | `item` | `path` | `int` | `-` | `-` | true |  |

## `demo_navigation_lab.workspace.activity`

StatefulShellRoute 活动分支。

- Owner: `demo_navigation_lab_component`
- Component version: `0.1.0`
- Exposure: `internal`
- Deep link: `disabled`
- Result: `void`
- Declaration: `demo_navigation_lab:lib/src/shell_pages.dart` (page)
- Placement: host `default`, outlet `workspace.activity`, shell `demo_navigation_lab.workspace_shell`, parent `none`
- Presentation: `page`
- Navigation sources: `typedIntent, internalUri`
- Restoration: `unsupported`
- Contract library: `demo_navigation_lab:lib/src/shell_pages.dart`
- Patterns:
  - `/workspace/activity` (CCPathPattern, primary)

## `demo_navigation_lab.workspace.profile`

StatefulShellRoute 个人分支。

- Owner: `demo_navigation_lab_component`
- Component version: `0.1.0`
- Exposure: `internal`
- Deep link: `disabled`
- Result: `void`
- Declaration: `demo_navigation_lab:lib/src/shell_pages.dart` (page)
- Placement: host `default`, outlet `workspace.profile`, shell `demo_navigation_lab.workspace_shell`, parent `none`
- Presentation: `page`
- Navigation sources: `typedIntent, internalUri`
- Restoration: `unsupported`
- Contract library: `demo_navigation_lab:lib/src/shell_pages.dart`
- Patterns:
  - `/workspace/profile` (CCPathPattern, primary)

## `demo_navigation_lab.extra`

展示仅在进程内传递的类型安全 Extra 对象。

- Owner: `demo_navigation_lab_component`
- Component version: `0.1.0`
- Exposure: `internal`
- Deep link: `disabled`
- Result: `void`
- Declaration: `demo_navigation_lab:lib/src/shell_pages.dart` (page)
- Placement: host `default`, outlet `root`, shell `none`, parent `none`
- Presentation: `page`
- Navigation sources: `typedIntent, internalUri`
- Restoration: `unsupported`
- Contract library: `demo_navigation_lab:lib/src/shell_pages.dart`
- Patterns:
  - `/lab/extra` (CCPathPattern, primary)
- Parameters:

| Name | Wire name | Source | Type | Cardinality | Codec | Required | Description |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `payload` | `payload` | `extra` | `DemoExtraPayload` | `-` | `-` | true |  |
