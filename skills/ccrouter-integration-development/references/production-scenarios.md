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
