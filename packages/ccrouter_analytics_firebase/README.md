# ccrouter_analytics_firebase

Optional Firebase-style mapping for `ccrouter_analytics`.

The package does not depend on `firebase_analytics`. Inject
`FirebaseAnalytics.instance.logEvent` into `CCFirebaseAnalyticsSink` from the
application layer so Firebase remains optional and testable.
