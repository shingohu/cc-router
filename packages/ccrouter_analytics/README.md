# ccrouter_analytics

Provider-neutral product analytics contracts for CCRouter.

This package converts managed Route lifecycle observations into page view and
page leave events, validates primitive analytics properties, and delivers
events through a bounded asynchronous sink dispatcher. It does not depend on
Firebase, ThinkingData, Sentry, or any other vendor SDK.

Use `ccrouter_analytics_firebase` or an application-owned `CCAnalyticsSink` to
export events. The Firebase package injects the vendor `logEvent` callback and
does not add a Firebase SDK dependency to Core. Arbitrary Widget clicks, scrolling, and exposure are not
guessed by this package; those events require stable explicit targets or a
separate opt-in auto-track package.

Use `CCAnalyticsPolicy` at the application privacy boundary. Set
`consentGranted: false` before consent, then call
`dispatcher.updatePolicy(...)` after the decision. `sampleRate` is applied
before queueing; filtered events never reach a sink. Events already executing
inside a sink cannot be retracted, so sensitive providers should be enabled
only after consent.

The dispatcher exposes bounded, payload-free pressure counters for diagnostics
and benchmarks: `acceptedEventCount`, `pendingEventCount`, `peakQueueDepth`,
and `droppedEventCount`. These counters do not expose queued events and must
not be treated as an audit log or replay source. A standalone reference run is
available at
`packages/ccrouter_test/benchmark/analytics_dispatcher.dart`.
