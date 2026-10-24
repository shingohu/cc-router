# Framework Memory And Lifecycle Review

Read this reference when framework production code creates, retains, observes,
or disposes lifecycle-bound Dart or Flutter resources, or when the task asks for
a memory-leak or cleanup review.

## Evidence Standard

Classify only proven lifecycle problems:

- `not-disposed`: an owned disposable resource has no reachable matching
  `dispose`, `close`, `cancel`, `remove`, or unsubscribe path.
- `not-GCed`: cleanup ran, but a callback, singleton, static collection, Timer,
  subscription, observer, or retained context still strongly references the
  owner. Treat delayed GC caused by a known retaining path the same way.

Do not report speculative leaks. Trace who creates the resource, who owns it,
which terminal paths exist, whether cleanup is idempotent, and whether any
reference survives cleanup. When ownership cannot be proven statically, add a
focused `leak_tracker_flutter_testing` or lifecycle regression test.

## Review Workflow

1. Identify the changed production files and their owning Runtime, Host,
   Adapter, Scope, RouteEntry, Widget, or provider.
2. Scan for `addListener`, `listen`, `Timer`, controllers, recognizers,
   observers, overlays, image streams, animations, Completers, pending Futures,
   and callbacks stored by global or long-lived objects.
3. Trace every creation path to its cleanup path, including initialization
   failure, cancellation, timeout, Host detach, Session close, route removal,
   component failure, and Runtime shutdown where applicable.
4. Verify cleanup order follows ownership and dependency order and can run more
   than once without double completion or double disposal.
5. Verify callbacks cannot retain the owner after cleanup and async continuations
   check `mounted`, disposal state, cancellation, or the corresponding Scope.
6. Add tests for the relevant terminal paths; use heap/leak tooling when a
   retaining path is otherwise ambiguous.

See [memory-lifecycle-examples.md](memory-lifecycle-examples.md) when calibration
between a real leak and a false positive is needed.

## High-Risk Resources

### Disposable objects

Verify disposal for locally owned `ChangeNotifier`, `ValueNotifier`,
`AnimationController`, `CurvedAnimation`, `TrainHoppingAnimation`,
`TextEditingController`, `ScrollController`, `PageController`, `TabController`,
`FocusNode`, `GestureRecognizer`, `TextPainter`, `BoxPainter`,
`ImageStreamCompleterHandle`, and third-party controller-like objects.

Do not create a disposable controller or recognizer inline in `build` unless it
is disposed within the same call. Objects supplied to Flutter widgets are not
implicitly owned by those widgets unless the Flutter API explicitly says so.

### Listeners and observers

Every `addListener` or `addStatusListener` needs the same callback identity in a
matching removal path. Do not register anonymous listeners from rebuild paths.
Remove `WidgetsBindingObserver`, `RouteObserver`/`RouteAware`, backend observers,
and application lifecycle listeners when their owner ends.

### Timers, async work, and pending completion

Cancel and clear every owned Timer. After an `await`, verify the owner is still
active before creating a Timer, mutating state, completing a request, or
registering another callback. Timer and Future callbacks must not retain an
ended Runtime, Scope, RouteEntry, Adapter, or Widget State.

Cancel request tokens, pending navigation continuations, readiness operations,
and other framework work on their documented terminal boundary. Uncompleted
Futures must complete with the documented cancellation/disposal outcome.

### Streams and controllers

Store every `StreamSubscription` and cancel it. Close every owned
`StreamController`. Confirm plugin or platform streams release their internal
subscription and callback references.

### Overlay, route, and image resources

Remove and dispose owned `OverlayEntry` instances when the owner ends. Unsubscribe
manual image-stream listeners and dispose completer handles. Route and backend
entries must not remain retained after their Scope and result channel terminate.

### Retaining references

Inspect static maps, registries, event buses, dispatch queues, singletons, Zone
overlays, and closures for references to disposed owners. Do not retain
`BuildContext`, Widget, Flutter `Route`, Navigator, arguments, Extra, or business
results in framework history or long-lived callbacks.

## CCRouter-Specific Invariants

- `CCRouterHost` controls the default Runtime for the Composition Root; business `CCRouter` cannot initialize, stop, or open InitTask Gates.
- Runtime shutdown releases pending work, listeners, queues, Route/Backend
  entries, Scopes, owned Services, Adapter resources, and Host bindings.
- Page Pop, Session close, component failure, Host detach, and Runtime shutdown
  are distinct boundaries; one must not silently substitute for another.
- Attached backends are not disposed by CCRouter; framework-created backends are.
- Route Services end with their exact managed RouteEntry, not PageHide or an
  unrelated backend Pop.
- A removed Entry may retain its Scope only through an exact backend-owned
  outgoing render lifetime. It must leave the active stack immediately. Detach
  render callbacks and cancel waits before shutdown joins Scope closures; never
  await a UI frame during teardown or retain Runtime in an unfinished Route Future.
- Bounded framework diagnostics queues must release queued callbacks and
  payload references on close.
- Observer and Sink failures must not skip framework cleanup.
- Exercise retained invocation, construction, navigation-operation and callback
  Zones separately. Runtime identity must not be a Runtime back-reference;
  construction owners must not keep ended Scopes or Route payloads alive.
  Verify both ended Runtime and payload GC, plus live-owner dependency resolution
  and original cancellation fences. Service disposal counts alone do not prove
  these retaining paths are clear.
- Test both detached callbacks after a method returns and the business-returned
  Future itself remaining unfinished after framework cancellation. The latter
  must release framework wait frames at the concrete owner's terminal boundary;
  late errors still need consumers, without a second terminal observation.
  Cross shared/new-instance readiness and Event fan-out with independent error
  Zones. Keep live-owner and completed-work GC controls. MultiHost constructors
  must preflight unique Adapter identity before adopting any child, independently
  of the dynamic registration path and overloaded equality.
- Keep the shared initializer's actual owner alive while cancelling independent
  readiness waiters. A Future.any terminal result is insufficient: unregister
  each consumer relay so the shared Future cannot retain its Zone. Check caller
  payload GC before shared completion, Session/Route origin closure, distinct
  error Zones, original shared failure/stack and unaffected live/late consumers.
  MultiHost Entry identity must use one registration domain across every event,
  snapshot, target, Guard and Pop/predictive outcome; namespace operations alone
  cannot prevent cross-Host Scope cleanup. Isolate observers at each fan-out.
- Pop/close wait relays must release their consumer Completer, owner listeners
  and entry-removal timer on every terminal path. Only a relay without owner
  references may remain on an uncooperative external Future. Test initial-stack
  Host identity before any navigation, synchronous detach/replacement, separate
  error Zones and live Runtime Entry replacement. Keep exact close receipts
  ahead of an orphaned-entry fallback without awaiting an outgoing UI frame.
- Retained Host tokens, Route/Session Scopes and cached readiness records must
  use Host context rather than first-caller Zone. Keep owners alive while
  checking caller payload GC after success, cached failure and cancellation;
  also exercise detached factory callbacks, dependency chains and the original
  framework decision reentrancy fence.
- Cleanup tests must include concurrent, synchronously reentrant and late
  awaiters across error Zones, with both success and failure. Assert completion
  ordering, once-only cleanup and original error/stack delivery.

## Review Output

Lead with high-confidence findings ordered by severity. For every finding state:

- leak type: `not-disposed` or `not-GCed`;
- impact and retained owner/resource;
- exact file and line;
- broken ownership or lifecycle invariant;
- smallest concrete fix and required regression test.

If no proven issue exists, say that no high-confidence memory or lifecycle leak
was found and identify any untested lifecycle boundary as residual risk.
