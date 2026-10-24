# demo_analytics

Demo 应用拥有的埋点基础设施参考，不属于 CCRouter 框架 API，不发布到 pub.dev。
包名是 `demo_analytics`，公开类型使用 `AppAnalytics…` 和
`AppNavigationAnalyticsBridge`。生产应用可接自己的现有埋点服务，无需依赖本包。

This package converts managed Route lifecycle observations into page view and
page leave events, validates primitive analytics properties, and delivers
events through a bounded asynchronous sink dispatcher. It does not depend on
Firebase, ThinkingData, Sentry, or any other vendor SDK.

Use an application-owned `AppAnalyticsSink` to export events. Vendor SDK
initialization, consent, identity, persistence, retry, and upload policy remain
application responsibilities. `demo/modules/analytics_firebase` shows one
callback-based Firebase mapping without adding a Firebase SDK dependency to the
framework. Arbitrary Widget clicks, scrolling, and exposure are not guessed by
this package; those events require stable explicit targets or the separate
opt-in auto-track package.

Use `AppAnalyticsPolicy` at the application privacy boundary. Set
`consentGranted: false` before consent, then call
`dispatcher.updatePolicy(...)` after the decision. `sampleRate` is applied
before queueing; filtered events never reach a sink. Events already executing
inside a sink cannot be retracted, so sensitive providers should be enabled
only after consent.

The dispatcher exposes bounded, payload-free pressure counters for diagnostics
and benchmarks: `acceptedEventCount`, `pendingEventCount`, `peakQueueDepth`,
`droppedEventCount`, `timedOutSinkWriteCount`, and `quarantinedSinkCount`.
`dispatcher.snapshot` adds per-Sink success, failure, timeout, and duration
counters in configured order. These values do not expose queued events or prove
durable provider upload and must not be treated as an audit log or replay source.
A standalone reference run is
available at
`demo/modules/analytics/benchmark/analytics_dispatcher.dart`.

## Navigation observation and ownership

`AppNavigationAnalyticsBridge` uses public `CCNavigationAspect` facts. The Demo
chooses Arrival/Show as page visits and Hide as leave, with a bounded visit ID
and foreground/total dwell. These are application rules, not framework PV
guarantees. The bridge accepts an application `identityProvider`; CCRouter receives no
visitor or application Session IDs. Identity is captured at first delivered
Found (Arrival/Show fallback), not at navigation invocation time, and retained
across redirects and visibility until removal. Call `resetTracking()` before
Consent/account changes. Invalid identities/provider errors are isolated;
`dispose()` clears snapshots and releases the provider, fencing old callbacks.
The Host forwards `onForeground/onBackground` and calls `dispose()`
when releasing the bridge. Framework diagnostics remain separate.

The dispatcher owner awaits `close()` on teardown. Sink writes start on a later
event-loop turn and failures are isolated. Consent revocation drops queued events
and prevents later Sinks of the active event from starting; immediate re-grant
does not revive them. Already-running writes require application cancellation.
An optional `sinkWriteTimeout` quarantines slow Sinks but cannot cancel their
Dart Futures. Do not await dispatcher close from its own Sink.write.

Properties are immutable and bounded: strings 256 characters, lists 32 entries,
events 64 properties and 4096 conservative value units. Numbers must be finite.
Keep Tokens, full URIs, arguments, Extra, Widgets, exceptions and business
results out of events. Admission/health counters do not prove durable upload.

From the repository root:

```sh
fvm dart test demo/modules/analytics/test
fvm dart run demo/modules/analytics/benchmark/analytics_dispatcher.dart --events=1000
```

Tests moved with the implementation, preserving contract, delivery, consent,
timeout, failure and navigation-bridge coverage. Source migration renames the old
framework package and types without retaining compatibility exports.
