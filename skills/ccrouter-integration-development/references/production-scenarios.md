# Production Scenario Assessment

Product analytics (PV/dwell definitions, Consent, identity, click/scroll/exposure,
sampling, queues and upload) is application responsibility. CCRouter supplies
navigation/page lifecycle observations and framework diagnostics. The repository's
Demo analytics libraries are references, not a new framework contract or required
dependency; an existing narrow application client can consume the observations.

Visitor/application Session identities must not be injected into Core. An
application observer snapshots them at delivery time and owns Consent resets,
retention and teardown. Layout breakpoints/pane policy and restoration-demand
collection are application responsibilities too; the framework applies resolved
Outlet visibility without replacing retained identities or Route Scopes.

Use this reference when an application's real feature exposes a missing,
unclear, or incorrect framework behavior. Ordinary supported feature work does
not require a framework redesign or a separate approval cycle.

1. Capture the expected and actual behavior, minimal reproduction, installed
   package versions, Host/component boundary, and generated capability used.
   Record Owner/Scope, creation and disposal, cancellation/timeout, concurrency,
   fallback, and privacy constraints only where relevant to the failure.
2. Map the scenario to existing Route, Service, Command, Event, InitTask,
   Interceptor, PopGuard, Aspect, page lifecycle, Host/Outlet, or Generator contracts.
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

## Reporting integration feedback

Adopters may submit CCRouter defects, missing capabilities, confusing diagnostics
and documentation gaps to [GitHub Issues](https://github.com/shingohu/cc-router/issues).
Search for an existing report first; add evidence there when the cause and
scenario match. A documented limitation is valid feedback when a real production
scenario demonstrates its cost, but label it as a capability request rather
than a confirmed Runtime bug. Uncertain causes can be reported as observations.

Use a small standalone example or public fixture instead of the production app.
Include only what helps reproduce and assess the behavior:

- Expected behavior, actual behavior and concrete integration impact.
- Exact CCRouter package versions or source commit; Flutter/Dart/OS versions
  when relevant, and the Host/Workspace topology.
- Minimal authored declarations, generated entry used, commands and steps;
  sanitized error codes and logs, plus a failing test when practical.
- Relevant Owner, lifecycle and cleanup boundaries; what was already verified,
  the current workaround and remaining uncertainty.
- For capability requests, the real use case, existing alternatives and why
  they are insufficient. A framework API design is optional.

Distinguish Pub resolution, Builder generation, Host validation and application
execution failures. Do not call a source test a device validation or infer a
memory leak without an ownership/retention path. Remove credentials, account IDs,
private business source and payloads; keep only sanitized capability identities.

An agent may prepare the title and body during an authorized assessment/fix.
Sending a new Issue or comment requires the user's authorization to publish;
permission to assess or fix code alone is not permission to post externally.
If publication tools or authentication are unavailable, deliver the prepared
report and tracker link. Keep unresolved requests open rather than claiming an
application workaround fixes the framework.

## Exact close after asynchronous completion

A managed A covered by B must close its own instance when its work completes;
ordinary Pop selects B or a foreign Popup. A raw Navigator removal bypasses the
Runtime Entry, result and Scope lifecycle. Use the optional targeted-close
capability rather than application-specific route matching.

Capture `CCRouter.routeEntryHandleOf(context)` while setting up A, then use
`CCRouter.navigator.close(handle, result: value)`. Check the explicit outcome;
never retry unsupported with Pop or same-route lookup. Managed startup pages
also own handles. A null capture means no valid binding to an active Entry in
the current Runtime, not permission to guess from the active stack. Foreign
Routes and local Outlet bases do not create their own Managed identity.
Active Entry, lifecycle and visibility snapshots never expose close handles.
All four Route Service APIs also validate Runtime generation before resolving
the exact Entry, including outgoing render Scopes. Test a foreign payload with
a reused Navigation ID and a mounted old Page after Runtime replacement.
The target's global/local managed guards run, a wrong result fails before
mutation, closed results complete once, and its Scope starts disposal once.

The Managed Router Backend stores Host/Outlet Entries independently and projects
them through `Navigator.pages`, so covered entries, inactive stateful branches,
and Shell structural anchors can be removed by identity without mutating a
match tree. The GoRouter compatibility implementation has been removed.
Native close preserves foreign popups even when removing the last root or Shell
Entry: only an empty structural boundary survives until those popups end.
Custom Adapters opt into the Host-only targeted-close SPI separately.

Regression evidence must include A covered by B, close A then push/pop C and
return from B without A resurrection; repeated same-route instances; foreign
Popup retention; concrete Host/Outlet isolation; denied guards, wrong result,
stale Runtime identity and concurrent duplicate close; exact Scope cleanup.
Do not infer arbitrary declarative-tree surgery, native multi-window, or real
OS gesture coverage from these widget tests.
