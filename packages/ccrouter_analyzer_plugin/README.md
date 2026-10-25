# ccrouter_analyzer_plugin

Route/Contract checks report `ccrouter_route_placement_invalid`,
`ccrouter_route_parent_self`, `ccrouter_route_policy_invalid`, and
`ccrouter_route_policy_duplicate` for directly authored literal configuration.
Placement constructors require canonical framework identity; computed values,
unknown expressions and full parent/Host/Shell/Outlet closure defer to generation.
No ID or topology rewrite is offered. Cross-package generated-import diagnostics
check each URI of conditional imports and exports at its precise literal span.


UI Fragment checks use canonical framework symbols, including prefixed and
transitive public exports. They report `ccrouter_ui_alias_invalid`,
`ccrouter_ui_alias_duplicate`, `ccrouter_ui_dependency_duplicate`,
`ccrouter_ui_version_range_invalid` (only definitely unsupported tokens),
`ccrouter_ui_action_invalid`, and `ccrouter_ui_renderer_invalid`. Unknown or
ambiguous types defer. The Generator remains authoritative for the complete
Props/Action constructor/default schemas, Contract identity/version grammar, and Host closure.
Action checks accept a plain enum, immutable final DTO or restricted sealed
union (including nested unions and same-library/part data leaves), and reject proven
mutable, behavioral, cyclic or non-data types. Complete constructor/default
validation stays Generator-owned. DTO subtypes are rejected even in the same
library/parts. Editor type/field/variant checks share a work budget and cached
per-annotation subtype facts; oversized graphs defer rather than reject or block
the editor. The cache is discarded between checks so edits cannot retain stale facts.
Malformed or inconsistent UI document/record/index versions defer UI Owner
diagnostics and Quick Fixes rather than trusting stale metadata.
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
