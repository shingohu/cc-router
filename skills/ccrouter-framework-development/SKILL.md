---
name: ccrouter-framework-development
description: Apply CCRouter framework conventions when adding, changing, reviewing, or refactoring production Dart code under packages/*/lib. Enforces meaningful documentation for declarations and deliberate separation of business, component-author, test, and internal APIs; excludes demos, examples, tests, and generated platform code.
---

# CCRouter Framework Development

Apply these rules to production framework Dart code under `packages/*/lib`.
Do not apply the documentation requirement to `demo/`, `example/`, `test/`, or
generated Android, iOS, macOS, Web, and OHOS platform code.

## Evolve From Production Scenarios

When a production application asks whether CCRouter supports a behavior, or a
real feature exposes a framework limitation, read
[CCRouter-production-adoption-workflow.md](../../docs/CCRouter-production-adoption-workflow.md)
before changing framework code.

- Reproduce and classify the scenario as supported, framework defect,
  developer-experience/documentation gap, application responsibility, general
  framework capability, or conditionally deferred work.
- Map the behavior to existing Route, Service, Command, Event, InitTask,
  Scope, Host/Outlet, diagnostics, analytics, Adapter, and Generator contracts
  before proposing a new abstraction.
- Do not promote one application's business special case into a public API.
- For non-trivial changes, compare application-only, optional Adapter/tooling,
  Core-contract, and defer-with-diagnostics solutions with explicit trade-offs.
- Record owner, lifecycle, failure, cancellation, concurrency, fallback,
  observability, privacy, performance, rollout, and rollback semantics.
- Add a failing or boundary test before fixing a defect. Keep production data
  and private application code out of framework fixtures and history.
- Update design status, integration guidance, Demo, and API documentation only
  when the implementation and verification actually support the claim.

## Document Framework Code

- Add meaningful DartDoc to every framework class, constructor, method,
  property, getter, setter, typedef, enum, enum value, extension, and top-level
  declaration.
- Document private and internal framework declarations too. The public API lint
  is only a minimum check, not the full standard.
- Explain semantics, ownership, lifecycle, constraints, failure behavior, or
  invariants. Do not merely repeat the declaration name.
- Document the intended usage scenarios for framework APIs, including when an
  API should or should not be used when that distinction affects correct use.
- Whenever behavior, constraints, lifecycle, ownership, or supported scenarios
  change, review and update the related DartDoc in the same change so comments
  remain consistent with the implementation.
- Keep `public_member_api_docs: true` enabled in `analysis_options.yaml`.

## Isolate API Layers

Classify every new or changed API before exposing it:

- Business API: application-facing entry points such as `CCRouter`, contracts,
  and immutable diagnostics. Business code imports only
  `package:ccrouter/ccrouter.dart`.
- Component-author API: manifests, component registrars, the restricted
  `CCRegistry`, and provider declarations needed to register components.
- Test API: explicit test support. Low-level Runtime construction must not leak
  through the business facade; a dedicated `ccrouter_test` package is the
  intended stable home for test hosts.
- Internal implementation: Runtime creation and destruction, Scope internals,
  dispatch, storage, and host lifecycle details.

Do not make an internal declaration public merely to access it from another
file. Prefer Dart library privacy with `_private` declarations. Use `part` and
`part of` when closely related files need shared private access and keeping one
library preserves the intended boundary.

Use explicit `show` or `hide` clauses on barrel exports as an additional guard,
not as a substitute for Dart privacy. Keep the
`implementation_imports` and `depend_on_referenced_packages` lint rules enabled.

Preserve these architecture boundaries:

- `CCRouter` owns the default Runtime lifecycle.
- Business code does not construct, open, close, or destroy the Runtime.
- A component registrar receives `CCRegistry`, never the full Runtime.
- Scope, dispatch, storage, and host lifecycle implementation stays internal.

## Keep Source Files Cohesive

- Organize framework declarations by one clear domain responsibility. Split a
  file when it begins mixing independent concerns such as routing, messaging,
  services, lifecycle, invocation state, or errors.
- Keep package barrel files stable so file splits do not force consumers to
  change imports.
- Keep small, tightly related declarations together; do not mechanically create
  one file per class.
- Use normal imports and exports for public contracts. Use `part` / `part of`
  only when related implementation files must share library-private members.
- Review the target file's responsibility before adding a new declaration and
  create or select the appropriate domain file instead of extending a generic
  catch-all file.

## Review Memory And Lifecycle Ownership

Read [memory-lifecycle-review.md](references/memory-lifecycle-review.md) when a
framework change creates, retains, observes, or disposes lifecycle-bound
resources, or when the task requests a memory-leak or cleanup review. Typical
triggers include controllers, Timer, StreamSubscription, listeners, observers,
overlays, animations, image streams, pending Futures, dispatch queues, Runtime,
Host, Adapter, Scope, RouteEntry, and Service lifecycle code.

Do not treat the reference as a generic optimization checklist. Trace concrete
ownership and retaining paths, report only high-confidence `not-disposed` or
`not-GCed` problems, and add lifecycle or `leak_tracker_flutter_testing`
coverage when static ownership is ambiguous.

## Verify Changes

When a change alters a developer-observable public API, usage scenario,
lifecycle, error semantic, generated command/path, supported capability,
Host/business API boundary, or recommended Demo pattern, update the root
`README.md` and the affected guidance in
`skills/ccrouter-integration-development/` in the same change. Do not update
them for internal refactors with no observable integration effect.

Run checks proportional to the affected code:

```sh
dart format packages/*/lib
dart analyze
dart test packages/ccrouter_core/test packages/ccrouter/test
```

For Flutter-facing changes, also analyze and test `demo`. For OHOS-impacting
changes, follow the repository's HarmonyOS tooling instructions and build from
`demo/ohos`.
