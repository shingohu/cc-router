# demo_analytics_flutter

Demo 应用侧 Flutter 埋点 Widget 参考，不属于 CCRouter 框架 API。
普通 Flutter library，无平台目录；依赖应用侧 `demo_analytics`，不启用全局自动采集。

`AppAnalyticsScrollable` observes an explicitly wrapped Scrollable and emits
bounded start/end events with direction, distance, and duration buckets. It
does not install global gesture listeners, inspect Widget text, consume scroll
notifications, or own a `ScrollController`.

`AppAnalyticsExposureTarget` observes one explicitly wrapped target and emits an
exposure event after a configurable visible-fraction and dwell-time threshold.
It is suitable for stable cards, banners, and list items. It does not infer
business meaning from Widget text or create a global visibility observer.

`AppAnalyticsScope` can be placed at the application or page boundary to inherit
an application-owned Dispatcher and stable context. Nested Scopes merge only
non-null context fields and may disable their subtree without changing global
Consent. The Scope never closes the Dispatcher and does not inspect Routes,
Widget text, pointer events, or foreign overlays.

This package does not enable tracking by itself. The application must still
declare stable event IDs and explicitly wrap scroll/exposure targets or use
`AppAnalyticsTarget` for business callbacks.

The Widget owns its dwell timer, binding observer and policy/scroll listener
removers. Detach, background and consent revocation cancel the dwell episode;
resume/grant starts a fresh threshold. The injected Dispatcher stays owned by
the application. `once` means accepted into its queue, not uploaded successfully.
Visibility accounts for View/ancestor clips, not arbitrary Overlay occlusion or
opacity. Sampling rejection is not retried every frame.

From the repository root:

```sh
fvm flutter test demo/modules/analytics_flutter/test
```

The existing Scope, scroll, exposure, remount, foreground and listener cleanup
tests moved here with the implementation. Applications may use another tracking
library without changing CCRouter.
