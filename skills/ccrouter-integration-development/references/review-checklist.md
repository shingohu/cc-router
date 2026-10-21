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

- Does every managed navigation call use `CCRouter.navigator`?
- Does every statically known destination use a generated typed Intent?
- Are dynamic internal URIs and external untrusted URIs using different entry points?
- Is `BuildContext` passed only for explicit Outlet resolution?
- Are `push`, `replace`, `go`, and `reset` used according to their real stack semantics?
- Is the Pop result type correct and tested?
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
- Is PopGuard synchronous and in-memory?
- Is confirmation UI implemented with `PopScope` instead?
- Is Aspect observational, sanitized, and non-reentrant?

## Lifecycle

- For optional UI Fragments, were required Owner edges, stable Keys, Props races,
  latest callback dispatch, inactive Tabs, Session reset and final unmount tested?
  Keep Renderer/Host SPI out of A and do not create a fake Route or new Scope.
- Does Service use the narrowest valid Scope?
- Is `@CCService` limited to the supported zero-argument construction model, with complex registration kept in `@CCComponentContribution`?
- Does a promoted Service contract explicitly declare `componentId`, export only its interface from the business barrel, and is each simple `@CCService` implementation bound through exactly one direct Contract?
- Does every cross-component Service consumer declare `CCServiceDependency<T>`, require the owner component, and use its generated component Client instead of a handwritten Proxy or direct lookup?
- If a complex promoted Provider needs a Token, is it confined to an owner-only SPI barrel and absent from every consumer dependency?
- Are disposable resources released by the owning Scope?
- Is Session opened/closed only by authentication lifecycle?
- Does Route Service resolve from an exact managed page Context?
- Are PageShow/PageHide not mistaken for Widget lifetime or physical visibility?
- Are listener removers, streams, controllers, and Overlay entries cleaned up?

## Messaging and Initialization

- Does Command have exactly one owner and the correct result type?
- Is Event used only for an already completed fact whose subscribers are optional?
- Does handler code cooperate with cancellation before irreversible side effects where possible?
- Are `CCRouterHost.initialize/shutdown/runInitTasks` confined to the Host Composition Root, with no old `CCRouter` aliases?
- Do component UI actions request product decisions through narrow callbacks/Contracts rather than receiving a generic Gate runner?
- Is InitTask truly once-per-Runtime startup work?
- Are DAG dependency, Gate, timeout, and failure policy explicit?

## Generated Code and Tests

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
