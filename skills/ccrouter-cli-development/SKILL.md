---
name: ccrouter-cli-development
description: Use when generating, validating, locating, cleaning, scaffolding, or planning CCRouter artifacts and CLI workflows. Covers implemented generator commands and safe AI-assisted fallbacks for CLI 2.0 capabilities that are not implemented yet.
---

# CCRouter CLI Development

Use this Skill for generator and developer-tooling work in a CCRouter workspace.
It covers both the implemented `ccrouter` commands and workflows that are not
yet exposed as CLI commands. It does not authorize changing generated files,
performing an unreviewed Contract migration, or inventing a command that does
not exist.

Install this complete directory alongside `ccrouter-integration-development`.
Together they form the consumer Skill bundle; required references do not depend
on a framework checkout. Use the consuming project's installed CLI help, and
report version differences instead of silently upgrading its dependencies.

## First Decide the Operation

Inspect the workspace root, `pubspec.yaml` files, Dart workspace configuration,
component descriptors, current generated indexes, and Git status before writing.
Classify the request as one of these operations:

| Operation | Use |
| --- | --- |
| Generate | Build or refresh Package and Host generated output. |
| Find | Locate a Route, Service, Command, Event, or InitTask from the current Host index. |
| Clean | Remove only CCRouter-owned generated source in explicitly writable Packages. |
| Scaffold | Create non-overwriting Component, Route, Service, Command, Event, or InitTask source. |
| Check | Detect stale output, invalid metadata, dependency violations, or unsupported declarations. |
| Deferred workflow | Assist with Contract promotion, migration, version review, or generation diagnosis when no command exists. |

Do not use a deferred workflow when an existing command already expresses the
operation. Prefer the command, then inspect its result.

## Implemented Commands

Run commands from the workspace root with the project's FVM toolchain:

```bash
fvm dart run --verbosity=error ccrouter_generator:ccrouter create component <package-name> <parent-directory>
fvm dart run --verbosity=error ccrouter_generator:ccrouter create page <PageName> <component-directory>
fvm dart run --verbosity=error ccrouter_generator:ccrouter create service <ServiceName> <component-directory>
fvm dart run --verbosity=error ccrouter_generator:ccrouter create command <CommandName> <component-directory>
fvm dart run --verbosity=error ccrouter_generator:ccrouter create event <EventName> <component-directory> [--with-subscriber]
fvm dart run --verbosity=error ccrouter_generator:ccrouter create init-task <TaskName> <component-directory> [--with-contract]
fvm dart run --verbosity=error ccrouter_generator:ccrouter analyzer status [host-root]
fvm dart run --verbosity=error ccrouter_generator:ccrouter analyzer doctor [host-root]
fvm dart run --verbosity=error ccrouter_generator:ccrouter analyzer install <host-root> --version <published-version> [--dry-run]
fvm dart run --verbosity=error ccrouter_generator:ccrouter analyzer install <host-root> --source git --url <remote-url> --ref <full-commit-sha> [--dry-run]
fvm dart run --verbosity=error ccrouter_generator:ccrouter analyzer upgrade <host-root> --version <published-version> [--dry-run]
fvm dart run --verbosity=error ccrouter_generator:ccrouter analyzer upgrade <host-root> --ref <full-commit-sha> [--dry-run]
fvm dart run --verbosity=error ccrouter_generator:ccrouter analyzer uninstall <host-root> [--dry-run]
fvm dart run --verbosity=error ccrouter_generator:ccrouter generate <host-root>
fvm dart run --verbosity=error ccrouter_generator:ccrouter generate <host-root> --check
fvm dart run --verbosity=error ccrouter_generator:ccrouter generate <host-root> --no-cache
fvm dart run --verbosity=error ccrouter_generator:ccrouter generate <host-root> --profile
fvm dart run --verbosity=error ccrouter_generator:ccrouter generate <host-root> --watch=auto --machine
fvm dart run --verbosity=error ccrouter_generator:ccrouter find <capability-id-or-route-pattern> <host-root>
fvm dart run --verbosity=error ccrouter_generator:ccrouter find <capability-id-or-route-pattern> <host-root> --usage <consumer-component-id>
fvm dart run --verbosity=error ccrouter_generator:ccrouter clean <host-root>
fvm dart run --verbosity=error ccrouter_generator:ccrouter pub-hook install [--sdk <flutter-sdk-root>]
fvm dart run --verbosity=error ccrouter_generator:ccrouter pub-hook status [--sdk <flutter-sdk-root>]
fvm dart run --verbosity=error ccrouter_generator:ccrouter pub-hook uninstall [--sdk <flutter-sdk-root>]
fvm dart run --verbosity=error ccrouter_generator:ccrouter pub-hook run --project-root <host-root> [--pub-command <command>]
```

The exact command help is authoritative. `analyzer status/doctor/install/upgrade/uninstall`
and generation watch are supported; `promote` and `migrate` are not.
Do not invent commands or flags because they appear in a design document.
`--verbosity=error` belongs to `dart run`, not to CCRouter. Keep it before the
Package executable so Dart/Pub cold-start resolution noise is suppressed while
CCRouter progress, diagnostics, and failures remain visible.

### Generate

Run `generate` after authored annotation, component, contribution, dependency,
or Host topology changes. Use `--check` for a read-only freshness gate and
`--no-cache --check` as the reference path when validating cache correctness.
Custom `--output-dir` catalogs also participate in comparison and rollback,
including docs/build directories. Only the explicit current/legacy catalog
files are owned; neighboring files stay untouched. Check output must remain
inside the build root.
Use `--profile` only to investigate generation performance. On a miss, distinguish
`build-targets` from the post-build `dirty-packages` reuse set and use the reported
reason (`cache-missing`, `metadata`, `output`, `dependency-index`, or
`propagated-from`) before changing cache behavior. Never remove caches just to
make an ordinary generation run pass.
Use `--watch=auto --machine` for a long-lived local or AI development session.
Consume its schema `1` NDJSON stdout and keep stderr as diagnostic text. A
successful Builder event is not final until `aggregationSucceeded`; wait for
`ready` before relying on the initial result. Set
`CCROUTER_DISABLE_BUILD_WATCH=1` for the one-shot fallback. Watch owns one build
root and holds its generation lock for the lease lifetime. Stop it before the
final `--no-cache --check`; watch never replaces that authority.
After Builder success, watch skips only the redundant ordinary fast-path and
Build Plan decision. It retains input barriers, preflight, snapshots,
validation, aggregation, and local state writes. Set
`CCROUTER_DISABLE_WATCH_CYCLE_OPTIMIZATION=1` to restore the reference cycle for
byte-for-byte A/B diagnosis without disabling watch.
`input-delta` compares exact Package facts with the last successful local Build
Plan: `authored` is an own-source/config change, `resolutionOnly` means unchanged
own input with changed resolution identity. This is not a proven causal edge or
semantic dependency graph. `output-delta` counts actual Dart, metadata, Markdown
and portable-state additions/removals/modifications before `--check` restores.
Missing either authored digest means `authoredUnavailable`, not equal source.
No baseline means `unavailable`, not no change. A changed state file is not a
changed business API; unchanged Dart does not prove unchanged docs/locations.
Attribution never authorizes skipping Builder or rewriting Portable State.
The Build Plan reports `suggested`, `actual`, and bounded `reasons`. Only
`actual=aggregateOnly` means that this invocation skipped build_runner. P2
allows a pure Host dependency-closure deletion when every remaining Builder
input, resolution identity, metadata file, and managed output is unchanged. P3
also allows a pure Package addition when every added Package has a verified
`lib/src/ccrouter_generated/metadata/ccrouter_generation_state.json`. The CLI
recomputes source, configuration, resolution, metadata, and managed-output
digests before trusting it. A writable unproven Package falls back to
`actual=runBuilder`; a read-only Git/Pub/external-Path Package fails explicitly
instead of being modified by the Host. Set `CCROUTER_DISABLE_AGGREGATE_ONLY=1`
to disable both optimizations. Commit Portable Generation State with managed
outputs, but never commit the disposable local baseline under
`.dart_tool/ccrouter/v1/build_plans/`. `--no-cache --profile` must report
`no-cache-reference` and run the authoritative full path; CI keeps using
`--no-cache --check`.

### Find

Use `find` instead of repository-wide text search for a known capability or
Route Pattern. It reads the current Host dependency-closure index and does not
run builders or scan arbitrary source files. If the index is stale, report that
and run `generate`; do not guess a generated API.
Use `--usage` only for an existing consumer component in that Host closure. It
prints a non-mutating recipe from generated facts: verified public imports,
direct Pub and owner edges, kind-specific dependencies, the stable component
API, and a typed call when one exists. It never edits Pubspec, component source,
imports, or generated output. Do not guess a public barrel when the Index lacks
one: require Contract promotion/export and regeneration. Keep Route, Service,
Command, Event, and InitTask models distinct; in particular, do not invent
`eventDependencies` or an InitTask business Client.

### Clean

`clean` is scoped to explicitly writable Packages and removes only files with
CCRouter's generated marker. It must preserve authored source, unknown files,
read-only dependencies, and unrelated build output. After cleaning, run a full
`generate` before making code changes based on generated imports.

### Scaffold

`create component`, `create page`, `create service`, `create command`, `create
event`, and `create init-task` are non-overwriting templates. They must fail
before writing if a target exists or a name is invalid. Capability templates
use the real annotations, but remain component-internal by default. Internal
Service scaffolds emit one concrete `@CCService(id: ...)`; Event Subscribers
require `--with-subscriber`; reusable InitTask Contracts require
`--with-contract`. The scaffold does not edit Host dependencies, generated
output, or Contract exposure. A cross-component Contract is a later design
decision.
Component manifests inherit the nearest explicit Dart SDK constraint and
`ccrouter`/`ccrouter_generator` Hosted, Git, or rebased Path declarations. A
resolved Package version is used only when no explicit declaration exists; if
either source cannot be proven, creation fails before writing instead of using
a hard-coded framework version.
After success, follow the printed `Next steps`. They are deterministic guidance,
not proof of the intended Host, and they never authorize silent Workspace or
dependency edits.

### Pub Hook

`pub-hook install` is explicit and per-SDK. It wraps only the Flutter SDK
entrypoints, keeps reversible backups, and must never be run against an SDK
without first resolving its path. The wrapper runs the original `flutter pub`
first; only a successful `get`, `upgrade`, `downgrade`, `add`, or `remove` may
trigger post-pub generation. `flutter run` and `flutter build` run the same
generator as a fail-closed preflight before the original Flutter entrypoint.
It skips projects whose current Package does not directly declare `ccrouter`,
or whose resolved Package config does not contain both `ccrouter` and
`ccrouter_generator`. A Workspace aggregator is skipped rather than treated as
a Host or used to guess one of its members.

Successful run/build output is labeled `preflight`; successful Pub-triggered
output is labeled `post-pub generation`. Success prints only the generator fast
path, validation summary, and profile timings. Failure preserves the recent
bounded generator tail so actionable Builder errors remain visible without
unbounded buffering or routine console noise.

Use `status` after an FVM version switch; it prints the resolved SDK path and
verifies the marker, POSIX/Windows wrapper, and backups. It returns non-zero
when the hook is missing or inconsistent. Use `uninstall` before removing a
managed SDK. Set `CCROUTER_PUB_HOOK_DISABLE=1` for a one-shot bypass. Do not
patch Flutter's `shared.sh`, snapshots, or tool sources manually. The hook does
not cover direct `dart pub` commands or Flutter Tool's internal implicit
`pub get`. After a successful `flutter run` preflight it starts watch under a
lifecycle lease and removes the lease when Flutter exits; `flutter build`
remains one-shot. `run/build` preflight failures stop the Flutter command;
projects without a resolved CCRouter graph are skipped.

## Generated Output Rules

- Never edit `lib/src/ccrouter_generated/` by hand.
- Never add a generated `part` directive to authored source.
- Do not manually register a generated Route, Service, Command, Event, or
  InitTask in a Registrar.
- Keep the source of truth in annotations, Component definitions, contributions,
  Contracts, and dependency declarations.
- Contracts Package authored barrels re-export the generated
  `lib/src/ccrouter_generated/<package>.contracts.api.g.dart` with explicit
  `show`; they do not import individual `contract/*.route.contract.g.dart`
  outputs. The CLI owns first-build placeholders and final replacement.
- If no generated capability exists, the generator should not leave an empty
  `ccrouter_generated` tree.

## Analyzer Plugin Bootstrap

`ccrouter analyzer status [host-root]` inspects one manual or CLI-managed Host
bootstrap and reports its source, pinned identity, lockfile, and Analyzer
compatibility. `ccrouter analyzer doctor [host-root]` additionally runs locked
dependency resolution, analysis, and loader compilation in a temporary copy.
Run `status` before `doctor`; neither command runs generation or rewrites Host
configuration.

If doctor reports a stale or incomplete plugin-manager entry, stop the Analysis
Server and back up the entire listed hash directory outside `.plugin_manager`,
not just its `analyzer_plugin` child. Then restart and verify a real IDE
diagnostic; doctor alone does not prove the live session loaded the plugin.

Use explicit `install/upgrade/uninstall` for a CLI-owned installation. All three
support `--dry-run` without processes or writes. Hosted requires an explicit
published version; Git requires a remote URL and full SHA verified by remote
fetch. The command validates a candidate loader before updating Host configuration
and running Pub with Hook disabled. Existing manual bootstraps are not adopted;
keep using the self-contained manual procedure in
[`ide-analysis-server.md`](../ccrouter-integration-development/references/ide-analysis-server.md).
The CLI preserves unrelated YAML and unknown files, refuses modified owned
files, and serializes writes at the Workspace Pub owner. A failed transaction
restores recorded configuration/resolution files; concurrent edits or interruption
retain a recovery journal under `.dart_tool/ccrouter/analyzer/transactions`.
Inspect its exact paths and recover deliberately; do not erase it to bypass the
next command's recovery check. Commit owned source files, ownership marker and
lockfiles, never the private journal. Installation success does not prove live IDE loading.
Do not attach Analyzer setup to `generate`, Pub Hook, or component scaffolding.
Do not change a pinned Git ref merely to follow local HEAD, use a branch name,
or commit a local absolute path.

## Deferred CLI 2.0 Workflows

These workflows are AI-assisted procedures, not commands. Summarize affected
declarations, dependencies, public exposure, and call sites before a migration.
Proceed when the user has authorized those changes; a request for assessment
alone does not authorize implementation. Ask only when a material choice or
expansion beyond that scope remains, rather than reconfirming approved work.

### Contract Scaffold or Promotion

Use when a real external component consumer exists and an internal Route or
Service must become a public Contract.

1. Identify the current Owner component and every real consumer.
2. Check whether a Contracts Package already exists and whether the consumer
   has a declared dependency on it and on the Owner where required.
3. Show the proposed public API, generated barrel changes, dependency changes,
   and affected call sites.
4. Keep the implementation Route/Page in the Owner Package; do not copy it into
   the Contracts Package.
5. Apply within the user's authorized scope, then run generation, analysis, focused tests,
   and `generate --check`.

Do not promote all internal capabilities by default. Promotion is a public API
decision, not a mechanical rename.

### Contract Migration

For a legacy declaration, first report the current declaration, generated
consumers, and dependency direction. Prefer a reversible, additive migration:
introduce the Contract, migrate one consumer, generate and test, then remove
the old path only after no consumer remains. Do not rewrite AST or `pubspec`
files silently.

### Version and Compatibility Review

When reviewing a Package or generated artifact version, compare the declared
`ccrouter_*` package versions, Dart/Flutter constraints, generator identity,
metadata schema, and generated manifest. Report incompatible combinations and
the smallest compatible change. This workflow does not silently upgrade
dependencies or regenerate lockfiles.

### Generation Failure Diagnosis

Capture the failing command, phase, Package, input declaration, and first
actionable error. Distinguish authored-source errors, dependency-resolution
errors, builder errors, aggregation errors, stale-output errors, and environment
errors. Preserve the failing workspace, propose the narrowest fix, and rerun
the same command before using `--no-cache` for comparison.

### Catalog and Source Location

Use generated metadata and `ccrouter find` as the machine-readable source of
truth. Catalog Markdown is a human view; it must not be edited to repair an
index. The optional `ccrouter_devtools` panel and official Extension already join
static Catalog records with Runtime snapshots by stable IDs. Source locations
are portable `package:` references; an embedded panel can use a Host-provided
`onOpenSource` callback, while the Extension does not directly open an IDE.
Keep this observational and use the bundled
[DevTools guide](../ccrouter-integration-development/references/devtools.md);
do not add public Runtime control APIs for tooling.

## Required Validation

After any authored or generated change, run the smallest relevant checks and
then the workspace gate:

```bash
fvm dart analyze
fvm flutter test <focused-test-target>
fvm dart run --verbosity=error ccrouter_generator:ccrouter generate <host-root> --check
```

For generator changes also run the generator unit tests and compare cached and
`--no-cache` output. For Contract or dependency changes add a clean-generation
run and a cross-Package consumer test. Do not claim success when only the
builder completed but the final aggregate or analyzer failed.

## Reporting

Every CLI or deferred workflow report must state:

- the operation and exact command or AI fallback used;
- Packages and files inspected or changed;
- whether generated output was regenerated or only checked;
- validation commands and their result;
- unsupported CLI capabilities that remain deferred;
- any required manual confirmation or follow-up.

When changing a framework command, path, lifecycle, error, or API boundary,
update the framework README and affected Skill guidance with the implementation.
For ordinary consumer work, update the application's integration notes instead
of requiring files from a framework checkout or editing its cached packages.
