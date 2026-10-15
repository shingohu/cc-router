# Contracts Layout and Relocation

Use this reference when a contracts Package accumulates multiple domains or
when handwritten declarations move without an intended public API change.
These are application organization recommendations, not a mandatory directory
schema or a new Generator migration command.

## Choose the Boundary

Keep small, cohesive contracts flat. When unrelated domains become difficult to
review together, group handwritten declarations by business domain rather than
global `routes/`, `models/` and `services/` folders. Do not create empty layers or
one Package per file. Split Packages only for demonstrated ownership, release,
compatibility or dependency/build boundaries; file count alone is insufficient.

Contracts contain stable cross-component declarations and necessary values,
not repositories, runtime implementations, UI state or component assembly.
A Capability's ordinary narrow API may stay in its owning Package. A second
consumer does not automatically justify promotion or Service registration.
When a type serves another domain, review who owns its meaning and failure
semantics; moving its file does not transfer ownership. Avoid a generic
`common/` bucket used only to conceal unclear domain relationships.

## Internal Layout Versus Public Libraries

```text
lib/
  orders.dart                 # Consumer Route and necessary values
  orders_owner.dart           # Authored declarations for the implementation
  order_result.dart           # Narrow value entry when independently needed
  src/
    orders/
      order_route_contract.dart
      order_result.dart
    catalog/
      catalog_route_contract.dart
    ccrouter_generated/       # Entirely Generator-owned
```

Current public exposure validation recognizes libraries directly under `lib/`
as public endpoints. `lib/src/orders/` can contain nested declarations;
`lib/orders/api.dart` is not a recognized public endpoint. Preserve root public
URIs during internal reorganization. Supporting nested public endpoints would
be a separate tool/compatibility change, not a cosmetic move.

Consumer barrels explicitly select Route types from
`src/ccrouter_generated/<package>.contracts.api.g.dart`. They do not bind to
individual generated files. Author-facing barrels select authored Contract
declarations and necessary owner identifiers/values; generated Arguments,
Binding, Definition and Codec stay out of these authored barrels. Values used
in generated signatures need a stable narrow public export when needed by the
generator; do not expose every domain through an omnibus consumer barrel.

An `_owner.dart` suffix describes intent; Dart does not enforce its audience.
Document permitted consumers and retain the consuming project's own checker
where it has one. Do not claim CCRouter provides that project's exact Owner
allowlist or assume every file under a generated directory is a legal import.

## Source-Only Relocation

1. Record current public URIs/symbols, contract IDs, Owners, versions and shape
   fingerprints. Inspect authored consumers, generated references and any
   application-specific path-sensitive tests/allowlists. Identify unrelated
   work before editing and use the application's configured SDK.
2. Move handwritten sources and update same-Package imports and root exports.
   Preserve explicit `show` lists. Keep route patterns, wire names, results,
   defaults, error/lifecycle semantics and public URI identity unchanged. A
   move that also changes those is a contract migration and needs separate
   compatibility review; do not hide it inside directory cleanup.
3. Run `ccrouter generate <host-root>` from the configured resolution context.
   Do not move, rewrite or format generated files manually. Stop/cooperate with
   an active Watch according to its documented lifecycle; never delete locks
   or caches to force generation. A contracts-only check is useful but does
   not validate its implementation and consumer Host.
4. Inspect new output, obsolete managed output removal and all generated
   consumers. Update project-owned exact path guards and their test fixtures
   to verified output paths; never replace them with wildcard exemptions.
5. Compare contract shape fingerprints and public exposure independently from
   source/index/portable fingerprints and catalog ordering, which may change
   with paths. A stable shape fingerprint is evidence about generated shape,
   not proof of unchanged business behavior or every source-compatible API.
   A source-only move does not itself require a contract version bump. For
   distributed Packages, refresh opted-in Portable State with the documented
   portable workflow; never edit state or compatibility hashes by hand.
6. Run analysis, relevant contract/consumer tests and the application's boundary
   checker, then `ccrouter generate <host-root> --no-cache --check` with Watch
   stopped. Update the owning Package README. Build/device requirements follow
   actual platform impact and the consuming project's gates; do not infer
   device authorization from this workflow.

Keep the migration reviewable and reversible through version control. A
temporary public re-export is useful when an intentionally changed public URI
needs a migration window; it is unnecessary when existing public entries remain
stable. No new runtime flag is needed for a behavior-preserving source move.
