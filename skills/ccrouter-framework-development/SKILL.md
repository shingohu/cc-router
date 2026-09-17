---
name: ccrouter-framework-development
description: Apply CCRouter framework conventions when adding, changing, reviewing, or refactoring production Dart code under packages/*/lib. Enforces meaningful documentation for declarations and deliberate separation of business, component-author, test, and internal APIs; excludes demos, examples, tests, and generated platform code.
---

# CCRouter Framework Development

Apply these rules to production framework Dart code under `packages/*/lib`.
Do not apply the documentation requirement to `demo/`, `example/`, `test/`, or
generated Android, iOS, macOS, Web, and OHOS platform code.

## Document Framework Code

- Add meaningful DartDoc to every framework class, constructor, method,
  property, getter, setter, typedef, enum, enum value, extension, and top-level
  declaration.
- Document private and internal framework declarations too. The public API lint
  is only a minimum check, not the full standard.
- Explain semantics, ownership, lifecycle, constraints, failure behavior, or
  invariants. Do not merely repeat the declaration name.
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

## Verify Changes

Run checks proportional to the affected code:

```sh
dart format packages/*/lib
dart analyze
dart test packages/ccrouter_core/test packages/ccrouter/test
```

For Flutter-facing changes, also analyze and test `demo`. For OHOS-impacting
changes, follow the repository's HarmonyOS tooling instructions and build from
`demo/ohos`.
