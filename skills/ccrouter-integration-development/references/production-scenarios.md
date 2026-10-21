# Production Scenario Assessment

Use this reference when an application's real feature exposes a missing,
unclear, or incorrect framework behavior. Ordinary supported feature work does
not require a framework redesign or a separate approval cycle.

1. Capture the expected and actual behavior, minimal reproduction, installed
   package versions, Host/component boundary, and generated capability used.
   Record Owner/Scope, creation and disposal, cancellation/timeout, concurrency,
   fallback, and privacy constraints only where relevant to the failure.
2. Map the scenario to existing Route, Service, Command, Event, InitTask,
   Interceptor, PopGuard, Aspect, Analytics, Host/Outlet, or Generator contracts.
   Inspect public APIs and generated output; a planning document is not proof
   that a capability exists.
3. Classify it as supported integration, framework defect, developer-experience
   or documentation gap, application responsibility, reusable framework
   capability, or conditionally deferred work. Business rules, vendor SDKs,
   consent decisions, and local UI usually remain application responsibilities.
4. Compare only relevant alternatives: existing API, application-only code,
   optional Adapter/tooling, Core change, or defer with diagnostics. Explain the
   benefit, ownership, compatibility cost, and rollback path. Do not introduce a
   general public API solely for one application's special case.
5. For a defect, establish a failing regression before a minimal fix. Keep
   private production data out of diagnostics, fixtures, and commits. Framework
   changes need their own authorized scope and independently reproducible tests;
   do not patch Pub caches or bypass boundaries through internal imports.
6. Validate success and the relevant failure/lifecycle cases, then update the
   application's integration notes and affected tests. Upstream framework
   maintainers also update their README, Skill guidance, and design status.
   Distinguish implemented behavior from proposals and untested platforms.

Report the evidence, classification, chosen capability, ownership, verification,
and any remaining limitation. A request to assess a scenario does not authorize
implementing it, expanding public contracts, or sending an upstream report.

The framework's expanded governance rationale is optional background:
[production adoption workflow](https://github.com/shingohu/cc-router/blob/main/docs/CCRouter-production-adoption-workflow.md).
This local procedure is sufficient when the remote document is unavailable.

## Exact close after asynchronous completion

A managed A covered by B must close its own instance when its work completes;
ordinary Pop selects B or a foreign Popup. A raw Navigator removal can leave A
in GoRouter's declarative tree and resurrect it on the next push/pop. This is a
general optional Adapter capability, not application-specific route matching.

Capture `CCRouter.routeEntryHandleOf(context)` while setting up A, then use
`CCRouter.navigator.close(handle, result: value)`. Check the explicit outcome;
never retry unsupported with Pop or same-route lookup. A null capture means an
unmanaged/initial/removed page, not permission to guess from the active stack.
`CCRouter.activeRouteEntries` and lifecycle/visibility snapshots remain
observational and never expose the close handle.
The target's global/local managed guards run, a wrong result fails before
mutation, closed results complete once, and its Scope starts disposal once.

GoRouter supports safely removable observed imperative push/replace entries,
including nested Shell Outlets whose structural ancestors remain. Declarative
go/reset entries, inactive retained branches, emptying a Shell, and any tree
with external GoRoute.onExit return unsupported. Old custom Adapters remain
source compatible and opt into the Host-only targeted-close SPI separately.

Regression evidence must include A covered by B, close A then push/pop C and
return from B without A resurrection; repeated same-route instances; foreign
Popup retention; concrete Host/Outlet isolation; denied guards, wrong result,
stale Runtime identity and concurrent duplicate close; exact Scope cleanup.
Do not infer arbitrary declarative-tree surgery, native multi-window, or real
OS gesture coverage from these widget tests.
