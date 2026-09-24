# ccrouter_analytics

Provider-neutral product analytics contracts for CCRouter.

This package converts managed Route lifecycle observations into page view and
page leave events, validates primitive analytics properties, and delivers
events through a bounded asynchronous sink dispatcher. It does not depend on
Firebase, ThinkingData, Sentry, or any other vendor SDK.

Use a vendor-specific package or an application-owned `CCAnalyticsSink` to
export events. Arbitrary Widget clicks, scrolling, and exposure are not
guessed by this package; those events require stable explicit targets or a
separate opt-in auto-track package.
