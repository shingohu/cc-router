# ccrouter_contracts

Route/Service/Command Contract declarations require exactly one matching annotation; generation
rejects duplicates in declarations, imported bindings and consumer dependencies.
`CCServiceKey<T>` equality requires the exact generic type and name. Subtype
assignability never makes differently typed Keys equal.
Each InitTask Handler must carry exactly one `CCInitTask` annotation; repeated Gate
and failure-policy declarations are rejected by both registration and metadata generation.

Contract and Component versions use the shared `CCSemVer` parser and reject
leading/trailing whitespace; range expressions retain their whitespace grammar.
Generated Service/Command/Event/UI Client names, including inferred names, reject Dart
keywords and Object members (`hashCode`, `runtimeType`, `toString`, `noSuchMethod`).

Provider, Route/RouteImplementation, Handler, Subscription and Contribution
annotations are unique per declaration and annotation kind. Repeated IDs, Scopes
or bindings fail generation; use separate declarations for independent registrations.

Route/Route Contract conflicts require a non-null `pattern` and a nonempty `patterns`
list. Explicit null and empty-list defaults are inactive. InitTask requires exactly one
non-null `contract`/`id`; null constants are inactive and unproven nullable references
defer IDE conflict checks. Two inactive identities still require a value and receive
no deletion fix. Non-null task Contracts/dependsOn retain top-level const-reference
rules in both source and metadata generation. Nullable Component/InitTask Contract
constants whose value is null publish no declaration.
IDE timeout checks prove SDK Duration identity; same-name business holders defer.
Resolved Gate constructor aliases retain framework identity for literal validation.

Only decimal digits make a numeric prerelease identifier: `0x10` and `-0` are
nonnumeric labels, distinct from `16` and `0`. Numeric prereleases compare by
length then lexical order without machine-int conversion. Core fields retain Dart int.
Caret/tilde bounds avoid successor overflow while preserving existing literal
comparator semantics, including next-core prereleases; no Pub/npm filtering is added.
Compatibility diagnostics attribute malformed installed versions to the Owner and
invalid range syntax to the consumer independently; valid consumer ranges are not
blamed for an Owner parse failure. Well-formed mismatches keep `versionOutOfRange`.
UI Host maps malformed generated versions/ranges to sanitized
`CCUIFragmentError('staleGeneratedOutput', id)` rather than raw parser exceptions.
The final Core ContractBundle gate validates both installed and required identities:
capability IDs are bounded to 128 characters, and Owners use bounded lowercase
component syntax. Matching malformed identities are stale generated output, not
valid compatibility evidence. Malformed consumer fingerprints are also
`staleGeneratedOutput`; different valid lowercase SHA-256 values remain
`fingerprintChanged`. Host and Runtime share this check before startup.
Host ContractBundle merging preserves every distinct consumer range constraint.
Only complete duplicate requirement values, including range and fingerprint, are
deduplicated; merge order never selects a winning range. No range intersection is
rewritten, and revalidating the merged snapshot preserves the original constraints.
CLI Package Bundle emission preserves persisted consumer range/fingerprint snapshots.
Only absent legacy fields use the resolved Contract defaults; existing ranges are
not rewritten to the Owner's current exact version. InitTask dependency snapshots
follow the same rule, and stale recorded Owners fail Workspace validation with
`ownerMismatch`. Distinct range constraints survive emission; no authored
`versionRange` parameter is added to source APIs.
IDE Contract Owner identity includes its defining Library, so same-name Contracts
with the same Package/Owner and distinct Libraries cannot overwrite one another,
including shared named parts. Service/Command part metadata keeps source URI and
coordinates plus optional `libraryUri`; catalog round trips retain that evidence.
Absent legacy evidence may be enriched by a consistent record, while explicit
conflicts fail generation. Invalid/query/fragment URI evidence defers IDE Owner
checks and fixes rather than guessing. Regenerate old part metadata for exact identity.
Parser-only Owner fixes require complete export namespace evidence and respect
local shadowing, including named extensions. Conditional, missing or unparseable
branches that may expose the symbol defer edits; they are not proof of absence.
A conditional export that hides the target symbol does not block a proven binding.
Malformed URI encodings, NUL, queries/fragments, noncanonical `package:/...` and
escaping locations never become IDE paths or crash source/diagnostic decoding.
Valid encoded filename characters such as `#` and literal `%` keep their file identity.
CLI preflight defers malformed import/export URIs to Builder's source errors; a
preflight skip does not establish validity.

UI capability and Owner IDs are bounded to 128 characters at generation, Workspace
and Host boundaries. Owner IDs use lowercase component grammar; capability IDs
retain their existing segment spelling. Workspace validates typed identities,
versions and SHA-256 fingerprints on Contract/Renderer/Requirement records even
when snapshots agree. Package-local checks also validate consumer ranges; malformed
ranges produce a source error without duplicate Host comparison fallout.

Pure Dart contracts and immutable value types shared by CCRouter packages and
independent component contract packages. It contains Route, Service, Command,
Event, InitTask, diagnostics, lifecycle, and navigation backend contracts.
Failure and Pending snapshots retain optional Host/Outlet attribution; structured
diagnostic events expose fixed failure reason, attempt and recovery depth without
arbitrary business cancellation codes or exception messages.

Use this package when a contracts-only package must stay independent from
Flutter and implementation packages. Application feature code should normally
depend on `ccrouter` instead.

Optional typed local UI declarations have a separate Pure Dart entry point,
`package:ccrouter_contracts/ccrouter_ui_contracts.dart`. It provides
`CCUIFragmentContract`, `CCUIFragmentDependency`, and `CCUIFragmentRenderer`;
`CCComponent.uiDependencies` records required UI consumption.
UI Contracts support optional `alias`, version defaulting to `0.1.0`, and
`description`; UI dependencies accept only optional `alias`, with Contract alias
and marker-name defaults. Remove legacy `versionRange` arguments and regenerate:
consumers record the exact current Contract version and shape fingerprint.
Props use immutable DTOs; Actions use plain enums, restricted immutable DTOs or restricted sealed
unions, including nested union payloads. Props remain DTO-only. All DTOs are terminal, including within their defining
library/parts; same-library inheritance cannot bypass data-only validation. Scalar types
are supported only as DTO fields, not as root Actions. DTO Actions
require UI schema 2 / Package Index schema 4 compatible tooling; union Actions
require UI schema 3 / Package Index schema 5. Union roots directly extend Object,
with public final direct leaves in the same library/parts, inherited final data
and const super.field forwarding. Export all variants and nested types. Rendering
and Host assembly require the separate Flutter package `ccrouter_ui`; these
declarations do not create another navigation Contract kind or relax Service
types. See the [UI integration guide](../../skills/ccrouter-integration-development/references/ui-fragments.md).

The package does not provide a Runtime or a navigation backend. See the
[architecture documentation](https://github.com/shingohu/cc-router/blob/main/docs/CCRouter-v0.1-architecture.md)
and
[release checklist](https://github.com/shingohu/cc-router/blob/main/docs/CCRouter-release-readiness.md).

`CCEventContract.alias` optionally selects the complete generated Owner publication
member. Omission preserves existing publish/type-name defaults. Alias changes
are fingerprinted; review Contract versions and regenerate without changing
Event IDs or publication permissions.
