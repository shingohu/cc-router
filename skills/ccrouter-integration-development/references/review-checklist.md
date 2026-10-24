# Review Checklist

## Architecture

- Is the package correctly acting as Host, implementation, or contracts package?
- Does every cross-component dependency point to a contract instead of a page implementation?
- Is a new public contract justified by an actual external consumer?
- Are unsupported framework capabilities avoided rather than locally reimplemented?
- Does each implementation Package declare exactly one top-level `const CCComponent`, while contracts Packages declare only explicit `CCComponentId` owners?

## Contracts Layout and Composition

- Does an ordinary narrow API suffice, or is the chosen Service/Command needed
  for actual framework semantics? Are plain calls' ownership and failures explicit?
- Does the Host assemble application infrastructure while components own their
  internal object graphs, without exporting internals for Host wiring?
- For source moves, are public URIs/symbols, Owner, IDs, wire names and versions
  stable, with shape fingerprints checked separately from path-bearing metadata?
- Are public entries still root `lib/` libraries, with Consumer/Owner/value
  audiences separated and application-specific guards kept exact?
- Was generated output regenerated, obsolete output checked, and the real
  consumer Host validated with `--no-cache --check`?
- For borrowed Extra capabilities, are missing, closed-owner and pending-call
  semantics explicit, with no transfer of disposal rights?

## Navigation

- Does every managed navigation call use `CCRouter.navigator` or the scoped
  `CCNavigator` returned by `CCRouter.navigatorOf(context)`?
- Does every statically known destination use a generated typed Intent?
- Are dynamic internal URIs and external untrusted URIs using different entry points?
- Is `BuildContext` passed when call-site Host/Outlet resolution is needed,
  without retaining it beyond the owning Widget lifetime?
- For scoped navigators, verify async calls across focus/active-Host changes,
  explicit destination placement, conflicting per-call Context rejection, all
  navigation methods and typed results. Same-ID Host replacement and Runtime
  restart must reject old clients before mutation. Retaining a client must not
  retain Context/Navigator/Runtime; page unmount is not Host unregister. Reacquire
  when a component changes Host/Outlet; exact close remains handle-based.
- Are `push`, `replace`, `go`, and `reset` used according to their real stack semantics?
- Is the Pop result type correct and tested?
- Cross queued delivery with remove/re-add of the same listener, old remover
  reuse and independent subscriptions for Lifecycle/Entry/Visibility/Failure/
  Backend/Capability. Preserve simultaneous duplicate-add deduplication.
- Cross shared readiness, InitTask and singleFlight with distinct error Zones;
  assert original failure identity, terminal observations and cleanup. Reenter
  Gate opening synchronously without awaiting the task's own drain; assert
  exactly-once siblings and newly opened work joined before completion.
- Cross deferred Resume with distinct error Zones, repeated defer, cancel,
  timeout, Host replacement and shutdown. Observe both original and restoring
  callers in their own Zones, preserve original error/stack, typed results and
  once-only terminal observations. Failure Policy runs only in the original
  pipeline and may recover independently of the replay error.
- Retain only a Fragment Action after unmount and force GC; consumer callbacks,
  Props and Fragment State must be released. Test current callback/activity,
  changed capability identity and old generation rejection independently.
- Exercise Contract comparator singletons, Tab/newline separators, invalid
  tokens and boundary equality; parsed SemVer collections must stay immutable.
- Cross exact origin (internal/platform/notification/QR) with singleFlight and
  rejectDuplicate. Distinct origins must reach their own policies; same-origin
  shared errors/rejection must remain correct and terminal cleanup permit retry.
- Cross context-free async redirect/recovery/defer with focus changes, including
  missing initial URI, explicit Host hops and named Shell/parent destinations.
  Default destinations keep the operation's original concrete Host; explicit
  Hosts and topology remain authoritative. Unregister/shutdown must not reroute.
- Reuse a logical Host ID after detach during policy/recovery/defer. Old work
  must cancel before its gate completes, never enter the new instance or trigger
  recovery. New work needs independent admission, including immediate retry
  after a visited redirect Host detaches. Cover both concurrency policies and
  late errors. Unmount old Host widgets before mounting their same-ID replacement.
- Repeat the same event sequence across at least three same-ID registrations,
  then leave/re-enter within the same Runtime. Check immediate cancellation,
  late callback rejection, unchanged replacement identities, and exactly-once
  Route Service cleanup with zero/small diagnostic capacity. Custom child
  operation IDs may repeat across registrations; duplicates within a registration
  still deduplicate. Verify auxiliary startup renders its own trusted home
  without re-consuming the primary platform link.
- Cross Adapter synchronous acceptance and old Scope cancellation/disposal
  callbacks with detach/re-register/shutdown before Entry commit. Assert no
  retired Entry survives, pending result errors are consumed, and another Host
  can still navigate. Include Push/Replace/Go/Reset/Open.
- Reenter registration during initialize and binding; inject failure, unregister,
  replacement and aggregate disposal. Rollback must preserve the new record and
  release each adopted Adapter/listener once. Reject reuse of an owned Adapter
  without disposing it. Verify pre-init registration binds once, and a pending
  Host cannot replace the active Host before registration succeeds.
  Reenter from unsubscribe/dispose after detach and navigate in the replacement;
  no old event may cancel that new Entry. Reject same-ID registration during
  detach delivery while retaining the old Adapter's once-only ownership.
- Verify MultiHost Pop receipts retain dispatch Host and actual child Outlet
  through async waits, focus changes, unregister and shutdown. Include root
  Popup priority from a named Outlet and LocalHistory callbacks changing focus.
- Do concurrent same-Route returns preserve the actual Flutter result and issue
  only one removal receipt, without queuing a Pop against the next page? Verify
  independent Outlets and Push/Close/Pop/unmount/shutdown during `willPop` waits.
- Does LocalHistory-only Back bypass Managed leave Guards while preserving local
  Flutter gates, Entry and Scope? Remove history during a wait and verify the
  actual leave is still guarded.
- Does Shell exit retain rendered branches/Scopes through the outer transition,
  then release once? Re-enter during reverse animation and verify exactly one
  Navigator owns each Outlet key; detach/shutdown must not wait for a frame.
- Does each newer platform/browser location supersede only its Host's pending
  ingress, including the already-current URI? Verify initial links, async
  interception, redirect, failure recovery, defer/resume and late completion.
- For exact close, was the handle captured from the owning Page before async
  work, and are unsupported/notFound/guardDenied handled without a Pop fallback?
  Verify covered siblings and foreign Popups survive, future pushes cannot
  resurrect the closed entry, duplicate route results stay separate, the
  concrete Host/Outlet stays isolated, and result/Scope cleanup happens once.
- Are local overlays intentionally foreign rather than accidentally registered as routes?
- If predictive back is enabled, does the custom Backend propagate its flag,
  and do authored Page builders explicitly wire the Host bridge? Verify false
  preserves original Route types, cancel has no result/Scope/lifecycle effects,
  commit removes exactly one Entry, and navigation/local-gate changes invalidate
  the preview. Change Theme platform before a start and platform/transition during
  a preview: unsupported starts must fall back, replaced detectors must not leave
  partial animation or `userGestureInProgress`, and late terminal events must not
  revive the preview or Pop. Verify a new gesture after Theme recovery.
  Include ancestor Navigator popups before/during a nested gesture,
  dismissal before commit, and new gestures after an attached Adapter closes.
  After Adapter disposal, read `popGestureEnabled` before the old terminal to
  verify that its commit remains fenced; also omit the terminal and verify that
  the next start cancels the leftover preview and restores Flutter handling.
  Keep Guard/custom/foreign fallback and avoid duplicate manual
  forwarding. Verify failed Adapter construction rolls back every registration,
  throwing handler lifetime probes restore Flutter fallback, and declined starts
  produce one bounded sanitized `predictiveBackFallbacks` reason. With the
  switch off, confirm the history is empty and unallocated. Do not infer OS or
  multi-window coverage from bridge capability.

## Policies

- Is Interceptor limited to pre-navigation policy?
- Does it avoid nested navigation, UI work, and analytics side effects?
- Is async policy bounded by timeout/cancellation?
- When committed state invalidates retained pages, does its owner explicitly
  trigger active-route revalidation instead of wiring Runtime to a Listenable?
- Are revalidation policies Host-registered, side-effect-free, non-reentrant,
  sanitized, and tested for keep/close/replace/reset plus stale/unsupported?
- Does revalidation close remain an exact identity operation that intentionally
  bypasses PopGuard, without positional Pop fallback? Are MultiHost isolation,
  shutdown cancellation, result completion, and Scope cleanup verified?
- Do replace/reset final requests preserve their operation and remain fenced to
  the original Host/Outlet or Host after destination resolution, Interceptor
  redirect, and Failure Policy recovery? For default placement, verify the
  concrete admitted Host survives later focus changes. Confirm replace reports
  after its own Entry commits, does not share business `singleFlight`, and that
  shutdown cancels a deferred continuation before joining revalidation.
- Does early Replace acceptance come from an explicit Backend commit receipt,
  with legacy/unsupported child Adapters rejected before any dispatch? Check
  synchronous rejection preserves the original Entry, and recovery keeps the
  same acceptance strategy. Do not treat an unresolved Future as acceptance.
- Cross active/inactive Host with root/named Outlet/Shell placement through
  direct navigation, redirect, recovery, and defer/resume. Assert both the
  concrete Host and preserved topology, rather than only the report status.
- Exercise shutdown while Backend close/reset is pending, including work that
  only ends after Adapter disposal. Verify bounded teardown, once-only cleanup,
  and late success/error cannot resume the pass or rebuild cleared histories.
- Is PopGuard synchronous and in-memory?
- For Managed migration, cover cold parent links, Go/Reset/Open-Go/browser
  reconstruction, missing ancestor parameters/Extra, ancestor policy
  cancel/redirect/defer/shutdown, independent Scopes and MultiHost isolation.
  Assert old identity survives rejection; do not manufacture Flutter-only parents.
- Verify default platform startup paths remain external, Host deny policy still
  rejects, and explicit `overridePlatformDefaultLocation` is forwarded by custom
  factories. A trusted fallback must not silently swallow a platform link.
- Cross covered Shell-seed close with a Context-selected generic page: covering
  identity, result and Scope survive, and only the seed's Scope closes once.
  Check direct branch navigation, retained-branch URL, root overlay reveal and
  adaptive panes independently of pointer focus.
- Foreign popup Back must target the real live owner, including nested Context
  and an inactive Host. Guarding the underlying page must not block its popup;
  closing the popup must restore that page's visibility and Guard. Verify
  mounted Shell/popup/gesture shutdown without Flutter errors or double removal.
- Is confirmation UI implemented with `PopScope` instead?
- Is Aspect observational, sanitized, and non-reentrant?

- Does the Host choose layout policy and pass only resolved visible Outlet IDs
  to `setActiveOutlets`? Check rejected input, other Host isolation, hidden
  retained pages, identity, result channels and Scope ownership across resizes.
  Use a real Managed child, then navigate in a hidden Outlet and change focus:
  the child Store, Runtime lifecycle and PageShow/PageHide must still agree.
  Also verify root overlay masking/reveal and explicit split-Shell selection.
- Is restoration demand measured entirely in application/platform code without
  representing it as implemented stack restoration or adding a Runtime queue?

## Lifecycle

- Cross native AppBar semantics and iOS eligibility with another focused Outlet
  and another active Host; Guard must receive the actual Route identity.
- Destroy and remount named, root and Shell renderers, including a local Popup
  and a pending Pop animation. Assert logical identity, pending result and Scope
  survive live remount; retired Routes/guards/foreign/lifecycle references release.
  Verify old Routes are GC-eligible while the Adapter remains alive. Reusing
  RouterConfig must not replay initial Go. Hidden focus must select the sole
  visible mounted Outlet for Back without affecting explicit Context targeting.
  Reorder panes in the same frame and verify the retained Navigator keeps its
  foreign popup ledger, exact native Guard and Route identity.
- During ordinary Pop, assert content remains at an intermediate reverse frame
  and a ModalRoute-dependent rebuild can resolve its exact Route Service. Check
  result completion before rendering ends, one Scope disposal after exit, and
  shutdown/unmount before animation completion without hanging or double cleanup.
- Close the final Managed Entry under one and several foreign Popups. Verify
  pop/remove/replace release only the final anchor, replacement preserves its
  new Popup, and a subsequent push cannot return to an obsolete empty Page.

- Are product analytics, Consent, identity, PV/dwell, scroll/exposure and upload
  application-owned? Keep CCRouter observations distinct from product events.
  Demo analytics packages and AppAnalytics types are examples, not framework API.
  Do analytics owners detach listeners, cancel timers and close delivery resources
  without affecting navigation or closing injected resources?

- For optional UI Fragments, were required Owner edges, stable Keys, Props races,
  latest callback dispatch, inactive Tabs, Session reset and final unmount tested?
  Keep Renderer/Host SPI out of A and do not create a fake Route or new Scope.
- Does Service use the narrowest valid Scope?
- Is `@CCService` limited to the supported zero-argument construction model, with complex registration kept in `@CCComponentContribution`?
- Does a promoted Service contract explicitly declare `componentId`, export only its interface from the business barrel, and is each simple `@CCService` implementation bound through exactly one direct Contract?
- Does every cross-component Service consumer declare `CCServiceDependency<T>`, require the owner component, and use its generated component Client instead of a handwritten Proxy or direct lookup?
- If a complex promoted Provider needs a Token, is it confined to an owner-only SPI barrel and absent from every consumer dependency?
- Are disposable resources released by the owning Scope?
- Close Scope reentrantly during construction: returned disposables must be
  reclaimed once, async cleanup joined and dependencies released in reverse
  order even when disposal throws. Avoid self-waiting Owner closure.
- Shared readiness timeout tests need an explicit initializer start gate;
  timeout before work starts is a separate legitimate outcome.
- Keep a shared initializer alive after independent waiters cancel, time out or
  lose their Session/Route. Assert their Zone payloads GC before producer
  completion, other callers still succeed/fail with the original outcome/stack,
  and independent error Zones consume late failures without restarting setup.
- Give two custom Host children the same local Entry ID. Assert aggregate
  snapshots, events/previous IDs, active/scoped/Guard targets and ordinary/
  predictive outcomes agree within each registration and differ between them.
  Pop must preserve the other Host's stack, RouteEntry and Service. Repeat after
  same-name Host replacement with an old pending receipt and both zero/nonzero
  removed-entry history capacity; the replacement must not be falsely marked
  desynchronized. A throwing predictive
  observer must not block Runtime reconciliation or later observers.
- Repeat pending Pop with only initial backend snapshots and no prior Runtime
  navigation. End Host/Runtime before the backend Future settles; check handled
  consumption, no removal, replacement diagnostics and late success/errors.
- Replace the Host synchronously during Guard evaluation, for both business
  Pop and async Back. The old request must never call the replacement; a fresh
  request must still work. Create Widget-test Runtime inside its fake scheduler
  and explicitly drive startup timers rather than mixing real `setUp` clocks.
- End a pending exact close by Entry replacement, Host detach and shutdown.
  Assert `notFound`, GC before producer completion and a still-operational live
  Runtime. Completing native/legacy exact receipts must keep their real outcome.
- Keep Host/Route/Session/shared Service owners alive after the first caller
  returns or cancels. Check arbitrary caller Zone payload GC, including cached
  readiness success/failure and pending factory callbacks. Cross independent
  error Zones and verify dependency cycles, new-instance ownership and Guard
  navigation-reentrancy fences after producer context isolation.
- Cancel before a generated Service method starts, with no initializer and an
  already-ready/shared instance; also close Session or Runtime at the readiness
  handoff. Assert zero method calls, the cancellation result and once-only owned
  disposal. Keep a separate explicit-start test for already-running work and
  verify another caller/account is unaffected by late completion/errors.
- Is Session opened/closed only by authentication lifecycle?
- Resume old Session methods and initializers after account switch and attempt
  fresh synchronous single/optional/batch/Key lookup, with cached and new-instance
  providers. Assert zero late factory calls, no new-account resource returned,
  normal independent new-account lookup and once-only disposal. Repeat after
  caller cancellation/timeout. Also verify that shared singleton initialization
  still resolves dependencies after only its first waiter terminates.
- Repeat after the original method has already returned successfully, both
  directly and through an App Service. Cover Session switch and Route closure,
  synchronous/async/proxy/Key/cache/new-instance lookup plus Command/Event entry.
  A live-Scope callback remains valid; an ended origin admits no new factory or
  handler. A pending child must cancel even if its parent already returned.
  Preserve Scope-owned shared factory/initializer independence and new-instance
  caller ownership. Retain the old Zone through GC and verify closed Services
  release. Cross-Runtime Zones must not fence independent Runtime calls.
- Retain factory, initializer, invocation, navigation decision and observer
  Zones through GC. Check ended Runtime and closed Route payload targets, not
  only Service disposal counts. Cover App/Session/Route ownership, a live-owner
  control, shared App initialization first reached from a Route, and exact
  dependency ownership after GC. Old callbacks must remain fenced.
- Separately keep the returned business initializer/Subscriber Future pending
  after owner cancellation. Cross App/Session/Route and singleton/newInstance,
  legacy/typed/generated Events, caller cancellation/deadline/shutdown, different
  error Zones, and late success/failure. Assert ended Runtime/Route GC, live-owner
  controls, once-only disposal/terminal observations and no unhandled late error.
  Create failing business Futures in their actual producer error Zone; an error
  Future deliberately imported across a Dart error Zone is not a valid fixture.
  Preflight constructor and dynamic MultiHost inputs separately: duplicate
  identity must fail, distinct instances with overloaded equality must succeed,
  and rejected constructor input must not dispose caller-owned children.
- With gated and failing cleanup, join `CCRouterTestHost.dispose()` concurrently,
  synchronously reentrantly and after completion in the same and distinct error
  Zones. Assert no early success, one resource disposal, original error/stack
  delivery and no uncaught error. Never await owner teardown from its disposable.
- Trigger Runtime shutdown inside a root synchronous factory: reject delivery
  while retaining exactly-once resource cleanup and the original shutdown error.
- Does Route Service resolve from an exact managed page Context?
  Test all four lookups against foreign payloads and retired Runtime bindings,
  including reused Navigation IDs. Diagnostic snapshots must expose no close
  handle; low-level identity lookup stays outside the business barrel.
- Does a Managed startup page receive the same Entry/Scope binding as later
  routes, while foreign Routes and local Outlet base surfaces create no Scope?
- Are PageShow/PageHide not mistaken for Widget lifetime or physical visibility?
- Are listener removers, streams, controllers, and Overlay entries cleaned up?

## Messaging and Initialization

- Does Command have exactly one owner and the correct result type?
- With throwing timeout cancellation listeners, do all notifications run while
  the original timeout and Trace remain consistent and late errors are consumed?
  Explicit token cancellation must retain its documented error contract.
- Is Event used only for an already completed fact whose subscribers are optional?
- Does handler code cooperate with cancellation before irreversible side effects where possible?
- Are `CCRouterHost.initialize/shutdown/runInitTasks` confined to the Host Composition Root, with no old `CCRouter` aliases?
- Do component UI actions request product decisions through narrow callbacks/Contracts rather than receiving a generic Gate runner?
- Is InitTask truly once-per-Runtime startup work?
- Are DAG dependency, Gate, timeout, and failure policy explicit?

## Generated Code and Tests

- Verify Native Managed is the only shipped Demo Backend; retire only
  GoRouter-specific configuration tests and map shared behavior to real Managed
  tests. Do not replace integration assertions with a mocked navigation result.
- Cover exact close of the last root/Shell Entry under a foreign Popup, direct
  `Navigator.pop(result)`, copied Page identity, and disposed foreign/opaque
  diagnostic bridge handles without retaining the Adapter.
- Were generated files left untouched?
- Was generation run after annotation or component graph changes?
- Does `generate --check` pass?
- Does analyze pass without internal API warnings?
- Do tests cover failure, cancellation, typed result, and lifecycle cleanup as applicable?
- Does the change avoid retaining Context, Route, Scope, listener, subscription, or Service past its owner?
- If IDE diagnostics are enabled, are they advisory and deterministic, with `generate --check` still
  used as the final generated-output and dependency gate?

## Documentation Synchronization

For framework changes that alter a developer-observable public API, lifecycle,
error, generated path/command, supported capability, API isolation boundary, or
recommended Demo pattern, framework maintainers review and update:

- root `README.md`;
- `skills/ccrouter-integration-development/SKILL.md`;
- the relevant file in `skills/ccrouter-integration-development/references/`.

Do not churn these files for internal refactors with no observable integration change.
In a consumer repository, update its own integration notes and tests instead;
the bundle does not require a framework checkout or permission to edit upstream.

When consolidating framework documentation, separate current contracts from
historical Backend algorithms and unimplemented proposals. Preserve dated test
counts, original failures and device scopes; link subsequent fixes and keep one
validation index. Do not treat a disabled iOS swipe as a guaranteed confirmation
callback, or expose a coordinator/resume-token API that the installed version
does not provide. Documentation-only work does not certify new device behavior.
