# ccrouter_analyzer_plugin

Route/Contract checks report `ccrouter_route_placement_invalid`,
`ccrouter_route_parent_self`, `ccrouter_route_policy_invalid`, and
`ccrouter_route_policy_duplicate` for directly authored literal configuration.
Placement constructors require canonical framework identity; computed values,
unknown expressions and full parent/Host/Shell/Outlet closure defer to generation.
No ID or topology rewrite is offered. Cross-package generated-import diagnostics
check each URI of conditional imports and exports at its precise literal span.

Literal Service/Command/Event/UI Contract aliases use the same generated-member rules:
Dart keywords and inherited Object members (`hashCode`, `runtimeType`, `toString`,
`noSuchMethod`) are invalid. Owner Command type-name defaults are also checked
when alias is omitted or literal null. Computed overrides defer to generation; UI effective
default-name checks remain resolved-identity based. Local Plugin changes do not
update the Demo's pinned Git bootstrap until its separate remote-pin workflow.

Literal Service/Command Dependency aliases in direct `CCComponent` lists report
`ccrouter_alias_invalid`, using the same keyword/Object-member rule. Constructors
require framework identity, including prefixes and typedefs; same-name functions
and foreign descriptors are ignored. Computed aliases and non-literal/spread lists
defer to generation. UI retains its existing diagnostic codes.

Service/Command/UI required-Owner diagnostics and dependency fixes use canonical
component/dependency constructors, including resolved prefixes and typedefs. A resolved
Contract must still carry exactly one matching framework annotation with the metadata
Owner. Removed, duplicate, foreign or changed annotations defer until regeneration.
Parser-only unknown/ambiguous namespaces defer to semantic resolution; generated
metadata alone never proves the constructor identity of a same-name business function.
Proven self-owned Service/Command/UI dependencies receive no missing-Owner repair;
adding the component to itself would create an invalid dependency cycle. Remove the
cross-component declaration; use internal Service lookup, the Owner Command Client,
or internal Widget composition for the matching capability.
Parser-only prefixed `cc.CCComponent(...)` calls and explicit const calls share
constructor identity checks and the same dependency-edit path.

Resolved Component ID constructors support typedefs/prefixes and constant string
references. An unproven consumer ID defers Owner diagnostics and edits to avoid
introducing a self edge. Parser-only exported Owner constants must prove framework
ID identity; same-name business classes are ignored. Adjacent literal strings use
their combined ID/alias value; computed expressions remain conservative.

Argument-conflict diagnostics and source fixes share one private rule set.
Route conflicts require a non-null pattern plus a nonempty patterns list. Nullable
InitTask contract/id constants use their resolved values; unknown nullable references
defer parser-only checks and edits. Null/empty defaults never cause deletion fixes;
both missing task identities still diagnose the missing value. The internal
`quick_fixes.dart` import remains available through explicit exports.
Timeout literals/zero require SDK Duration declaration identity. Business holders with
the same name are ignored; unknown parser namespaces wait for resolution. Resolved
Duration/Gate constructor typedefs and prefixes retain their actual declaration.

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
Conditional imports and part libraries also defer parser-only edits when they may
contribute the symbol. Hidden conditional branches do not block a proven binding.
Parsed Contract matching respects show/hide, local shadowing and conditional imports.
Exact Library metadata must match the real import/export path, not another same-name
type in the Package. Resolved analysis continues to use the actual Dart element.
Malformed URI encodings, NUL, queries/fragments, noncanonical `package:/...` and
escaping locations never become IDE paths or crash source/diagnostic decoding.
Valid encoded filename characters such as `#` and literal `%` keep their file identity.
CLI preflight defers malformed import/export URIs to Builder's source errors; a
preflight skip does not establish validity.
Source boundary diagnostics use Dart target-file semantics for valid file URIs,
queries, encoded separators and import-target symlinks. The current SDK URI converter
maps Package aliases and each conditional branch without full type resolution.
A selected conditional Library is never used as evidence for another branch.
Metadata locations remain subject to
their stricter portable Package-URI validation.

Plugin semantic-resolution triggers reuse the annotation identity table and
include UI-only Contract/Renderer files with imported Owner constants and UI SPI
references. These markers request current session facts; they do not establish
framework identity. Generator Analyzer 13 and Plugin Analyzer 8.4 remain isolated;
the maintainer Demo integration test verifies generated metadata, Owner identity,
diagnostic source spans and Quick Fixes across these graphs. The Demo manifest/lock
pin the pushed fix; pin-check and temporary loader smoke pass. The current IDE
session remains unverified. Further updates push the Plugin first and update the
pin separately, then run doctor and verify an IDE diagnostic/Quick Fix.

UI Fragment checks use canonical framework symbols, including prefixed and
transitive public exports. They report `ccrouter_ui_alias_invalid`,
`ccrouter_ui_alias_duplicate`, `ccrouter_ui_dependency_duplicate`,
`ccrouter_ui_action_invalid`, and `ccrouter_ui_renderer_invalid`. Unknown or
ambiguous types defer. Alias checks include the effective Contract/type defaults;
Dependency aliases override them. UI dependencies have no version-range parameter.
The Generator remains authoritative for the complete
Props/Action constructor/default schemas, Contract identity/version grammar, and Host closure.
Action checks accept a plain enum, immutable final DTO or restricted sealed
union (including nested unions and same-library/part data leaves), and reject proven
mutable, behavioral, cyclic or non-data types. Complete constructor/default
validation stays Generator-owned. DTO subtypes are rejected even in the same
library/parts. Editor type/field/variant checks share a work budget and cached
per-annotation subtype facts; oversized graphs defer rather than reject or block
the editor. The cache is discarded between checks so edits cannot retain stale facts.
Malformed or inconsistent UI document/record/index versions defer UI Owner
diagnostics and Quick Fixes rather than trusting stale metadata. Resolved UI
markers must still carry one framework annotation whose Owner matches metadata;
removed annotations and source Owner changes defer until facts are regenerated.
Union Actions require UI schema 3 / Package Index schema 5 and a matching Plugin. DTO Actions need the matching
UI schema 2 Generator; mixed UI schema 2 Owner metadata retains required-edge checks.

`ccrouter_ui_spi_access` rejects handwritten Generated SPI and component access
to UI Host SPI, including conditional imports/exports and resolved canonical
type references. Host assembly remains allowed in Host Packages; tests and
generated libraries are exempt. UI dependencies join the existing
`ccrouter_component_owner_dependency_missing` rule using UI metadata declaration
identity. Its Quick Fix requires an exact public Owner constant already imported
and a missing/direct editable required list; hidden constants, computed lists,
spreads and ambiguous evidence never trigger speculative edits. Legacy metadata
without UI declaration identity defers until regeneration. No alias, Action,
Renderer or import rewrite is offered. Self-owner UI declarations defer to the
Generator; a cyclic self dependency is never suggested.
Constructor-based checks prove the invoked constructor declaration rather than
the expression's return type, so ordinary factory functions cannot receive a
constructor argument fix. Owner indexes retain distinct declaration libraries
for same-name markers, while ambiguous parser-only lookups defer. Renderer
annotations on nested functions are rejected even with an otherwise valid signature.
Resolved `CCComponent` and `CCUIFragmentDependency` typedef constructors retain
Owner diagnostics and Quick Fixes. Regenerate UI metadata for part declarations:
`packageUri` retains the declaration location and `libraryUri` identifies its
defining library. Legacy part metadata without library proof defers; malformed
or foreign-package library identities never fall back to Package-only matching.

Generator UI metadata records portable Contract, Renderer and consumer
locations. Validated watch/Host one-shot snapshots can publish
`ccrouter_ui_missing_implementation`, `ccrouter_ui_owner_mismatch`,
`ccrouter_ui_implementation_duplicate`, `ccrouter_ui_contract_duplicate`,
`ccrouter_ui_dependency_missing`, `ccrouter_ui_fingerprint_changed`,
`ccrouter_ui_version_out_of_range`, and `ccrouter_ui_stale_generated_output`.
Snapshots retain the existing exact identity/staleness rules. Records without
a proven authored position remain CLI-only errors. The Plugin does not run
generation, infer runtime visibility, or prove resource disposal.

The Plugin reports `ccrouter_host_lifecycle_access` as an error when a
non-Host participating Package exposes `CCRouterHost` through a direct
`ccrouter_host.dart` import/export, including conditional branches, or references
the canonical framework class through a prefixed/transitive public barrel.
Explicit show/hide lists are respected; Adapter infrastructure may import only
its needed SPI without exposing the lifecycle class. Class spelling alone is
never proof: foreign same-name declarations are ignored, and unresolved
transitive identities defer. Roles use the same `.metadata`, `ccrouter.yaml`,
and direct-dependency evidence as Host selection. The check applies only to
Package `lib/` sources; tests/tools and generated code are excluded. Saved role
changes refresh diagnostics without a Server restart. Unknown role evidence
is deferred, and files inside a Host Package still require review to separate
composition code from feature code. There is no automatic import or role fix.
Dart API visibility remains enforced independently of this optional Plugin.
Host/UI SPI boundary identity also resolves URI/symlink aliases against the
configured SDK libraries. Named types and typedef references participate; show
names are checked only when every combinator exposes them, and hide names are
excluded from references. Same-name foreign library copies stay ignored. UI
declarations/references request existing-session semantics even without a
Component declaration in the same file. Contract/Renderer type compatibility
continues to use its existing Dart declaration identity checks.

Optional Analysis Server diagnostics for CCRouter source boundaries and
deterministic generated outputs. The plugin provides low-noise editing feedback
and Metadata-proven Service/Command/UI owner checks, but does not run generation
or replace `ccrouter generate --check`. Its dependency Quick Fix is offered
only for a directly editable list with an exact owner constant already exposed
by a public import; it never guesses or inserts imports.

Annotation diagnostics, generated-output warnings and argument Quick Fixes share
declaration identity checks. Same-name application annotations are ignored.
Resolved identities remain usable when another expression has a Dart error;
unresolved ambiguous imports defer to later resolution or generation.

Package discovery is Workspace-aware. The plugin validates Pub's
`workspace_ref.json` or exact Workspace membership and never borrows an
unrelated ancestor's Package graph for a standalone nested Package. It also
reports saved-versus-resolved dependency drift without requiring an active
Generator watch, selecting Host/package-local and Flutter/Dart Pub guidance
from `.metadata`, `ccrouter.yaml`, and direct CCRouter dependencies. Workspace
analysis indexes explicit member manifests so each participating Package gets
its own current drift diagnostic without a recursive directory scan. Drift
checks use the current Analysis Server overlay, so commenting or restoring a
dependency updates the hint before the manifest is saved.

An active Generator watch is the authoritative structured diagnostic source.
Without one, the plugin can consume the latest terminal Host one-shot snapshot
only while its exact Pub-resolution fingerprint remains current. A successful
one-shot or any input change clears prior errors, and an active watch never
falls back to older one-shot evidence. The 500ms fallback polling covers both
the Analysis context root and explicit nested Workspace Hosts.

The plugin uses an isolated Analysis Server bootstrap because its Analyzer
version must not constrain the application Workspace. Follow the
[IDE integration guide](https://github.com/shingohu/cc-router/blob/main/docs/CCRouter-ide-analysis-server.md)
instead of
adding an arbitrary local path dependency.

The package is currently pre-release. Hosted installation and upgrade flows are
tracked in the
[release checklist](https://github.com/shingohu/cc-router/blob/main/docs/CCRouter-release-readiness.md).

From this package directory, run `fvm dart test` for the complete suite or
`fvm dart test test/analysis_server_integration_test.dart` for real Server
process tests. They use the installed SDK's JIT Analysis Server snapshot with
Legacy and LSP protocols, an isolated cache, and the local plugin sources.
They cover manifest and Dart editor overlays, structured Generator snapshots,
Quick Fix/codeAction application, disk changes to all five generated capability
kinds, and cross-package Workspace ownership metadata. Fixture disk changes
test invalidation, not actual generation.
No Pub or network access is needed after resolving this package's dependencies.
Bootstrap copying, AOT packaging, Git pins, and IDE UI require separate checks.
