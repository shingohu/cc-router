# ccrouter_auto_track

Optional Flutter UI analytics helpers for CCRouter.

`CCAnalyticsScrollable` observes an explicitly wrapped Scrollable and emits
bounded start/end events with direction, distance, and duration buckets. It
does not install global gesture listeners, inspect Widget text, consume scroll
notifications, or own a `ScrollController`.

This package does not enable tracking by itself. The application must create a
`CCAnalyticsTracker` and explicitly wrap the target subtree.
