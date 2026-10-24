# Changelog

## 0.1.0 - Unreleased

- Track bounded history completeness independently of external Sink policy and
  retain exact failure placement across redirect, recovery and pending replay.
  Expose payload-free health counters without Runtime timers or subscriptions.

- Added a read-only, weak Host-registration lease for framework-scoped navigation
  clients; same-ID replacement cannot revive a retired registration.
- Preserve a concrete call-site Host named `default` across focus changes and
  asynchronous policy instead of confusing it with the declaration sentinel.
- Added Runtime-owned Managed navigation identity, exact targeted close and
  explicit active-route revalidation with operation/partition commit fences.
- Bound asynchronous navigation and external Pop/close waits to concrete Host
  registrations; retirement releases consumer waits and fences late receipts.
- Separated Route Scope exit rendering from logical result completion; shutdown
  releases rendering waits without a Flutter frame.
- Isolated shared readiness, Scope tokens and Scope-owned factory/initializer
  context from the first caller's arbitrary Zone values. Cancellation detaches
  one waiter; failures propagate in each caller's own error Zone. Preserved
  dependency-cycle checks, origin-lifetime admission and once-only cleanup.
- Kept product identity, analytics queues, layout geometry and restoration-demand
  storage outside Runtime; navigation observations remain framework-provided.
- Preparing the first public release of the Pure Dart CCRouter Runtime.
