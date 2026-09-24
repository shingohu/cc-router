# ccrouter_auto_track

Optional Flutter UI analytics helpers for CCRouter.

`CCAnalyticsScrollable` observes an explicitly wrapped Scrollable and emits
bounded start/end events with direction, distance, and duration buckets. It
does not install global gesture listeners, inspect Widget text, consume scroll
notifications, or own a `ScrollController`.

`CCAnalyticsExposureTarget` observes one explicitly wrapped target and emits an
exposure event after a configurable visible-fraction and dwell-time threshold.
It is suitable for stable cards, banners, and list items. It does not infer
business meaning from Widget text or create a global visibility observer.

This package does not enable tracking by itself. The application must create a
`CCAnalyticsTracker` and explicitly wrap the target subtree.
