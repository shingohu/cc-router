# ccrouter_analytics_flutter

Optional Flutter UI analytics helpers for CCRouter.

`CCAnalyticsScrollable` observes an explicitly wrapped Scrollable and emits
bounded start/end events with direction, distance, and duration buckets. It
does not install global gesture listeners, inspect Widget text, consume scroll
notifications, or own a `ScrollController`.

`CCAnalyticsExposureTarget` observes one explicitly wrapped target and emits an
exposure event after a configurable visible-fraction and dwell-time threshold.
It is suitable for stable cards, banners, and list items. It does not infer
business meaning from Widget text or create a global visibility observer.

`CCAnalyticsScope` can be placed at the application or page boundary to inherit
an application-owned Dispatcher and stable context. Nested Scopes merge only
non-null context fields and may disable their subtree without changing global
Consent. The Scope never closes the Dispatcher and does not inspect Routes,
Widget text, pointer events, or foreign overlays.

This package does not enable tracking by itself. The application must still
declare stable event IDs and explicitly wrap scroll/exposure targets or use
`CCAnalyticsTarget` for business callbacks.
