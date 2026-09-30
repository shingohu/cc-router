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

## First Decide the Operation

Inspect the workspace root, `pubspec.yaml` files, Dart workspace configuration,
component descriptors, current generated indexes, and Git status before writing.
Classify the request as one of these operations:

| Operation | Use |
| --- | --- |
| Generate | Build or refresh Package and Host generated output. |
| Find | Locate a Route, Service, Command, Event, or InitTask from the current Host index. |
| Clean | Remove only CCRouter-owned generated source in explicitly writable Packages. |
| Scaffold | Create a non-overwriting Component or internal Route page template. |
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
fvm dart run --verbosity=error ccrouter_generator:ccrouter create event <EventName> <component-directory>
fvm dart run --verbosity=error ccrouter_generator:ccrouter create init-task <TaskName> <component-directory>
fvm dart run --verbosity=error ccrouter_generator:ccrouter analyzer status [host-root]
fvm dart run --verbosity=error ccrouter_generator:ccrouter analyzer doctor [host-root]
fvm dart run --verbosity=error ccrouter_generator:ccrouter generate <host-root>
fvm dart run --verbosity=error ccrouter_generator:ccrouter generate <host-root> --check
fvm dart run --verbosity=error ccrouter_generator:ccrouter generate <host-root> --no-cache
fvm dart run --verbosity=error ccrouter_generator:ccrouter generate <host-root> --profile
fvm dart run --verbosity=error ccrouter_generator:ccrouter find <capability-id-or-route-pattern> <host-root>
fvm dart run --verbosity=error ccrouter_generator:ccrouter clean <host-root>
fvm dart run --verbosity=error ccrouter_generator:ccrouter pub-hook install [--sdk <flutter-sdk-root>]
fvm dart run --verbosity=error ccrouter_generator:ccrouter pub-hook status [--sdk <flutter-sdk-root>]
fvm dart run --verbosity=error ccrouter_generator:ccrouter pub-hook uninstall [--sdk <flutter-sdk-root>]
fvm dart run --verbosity=error ccrouter_generator:ccrouter pub-hook run --project-root <host-root> [--pub-command <command>]
```

The exact command help is authoritative. Do not add `watch`, `promote`,
`migrate`, `analyzer`, or other flags because they appear in a design document.
`--verbosity=error` belongs to `dart run`, not to CCRouter. Keep it before the
Package executable so Dart/Pub cold-start resolution noise is suppressed while
CCRouter progress, diagnostics, and failures remain visible.

### Generate

Run `generate` after authored annotation, component, contribution, dependency,
or Host topology changes. Use `--check` for a read-only freshness gate and
`--no-cache --check` as the reference path when validating cache correctness.
Use `--profile` only to investigate generation performance. Never remove caches
just to make an ordinary generation run pass.

### Find

Use `find` instead of repository-wide text search for a known capability or
Route Pattern. It reads the current Host dependency-closure index and does not
run builders or scan arbitrary source files. If the index is stale, report that
and run `generate`; do not guess a generated API.

### Clean

`clean` is scoped to explicitly writable Packages and removes only files with
CCRouter's generated marker. It must preserve authored source, unknown files,
read-only dependencies, and unrelated build output. After cleaning, run a full
`generate` before making code changes based on generated imports.

### Scaffold

`create component`, `create page`, `create service`, `create command`, `create
event`, and `create init-task` are non-overwriting templates. They must fail
before writing if a target exists or a name is invalid. Capability templates
use the real annotation and Handler signatures, but remain component-internal
by default. The scaffold does not edit Host dependencies, generated output, or
Contract exposure. A cross-component Contract is a later design decision.

### Pub Hook

`pub-hook install` is explicit and per-SDK. It wraps only the Flutter SDK
entrypoints, keeps reversible backups, and must never be run against an SDK
without first resolving its path. The wrapper runs the original `flutter pub`
first; only a successful `get`, `upgrade`, `downgrade`, `add`, or `remove` may
trigger post-pub generation. `flutter run` and `flutter build` run the same
generator as a fail-closed preflight before the original Flutter entrypoint.
It skips projects whose resolved Package config does not contain both
`ccrouter` and `ccrouter_generator`.

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
`pub get`, and does not provide `watch`. `run/build` preflight failures stop the
Flutter command; projects without a resolved CCRouter graph are skipped.

## Generated Output Rules

- Never edit `lib/src/ccrouter_generated/` by hand.
- Never add a generated `part` directive to authored source.
- Do not manually register a generated Route, Service, Command, Event, or
  InitTask in a Registrar.
- Keep the source of truth in annotations, Component definitions, contributions,
  Contracts, and dependency declarations.
- If no generated capability exists, the generator should not leave an empty
  `ccrouter_generated` tree.

## Deferred CLI 2.0 Workflows

These workflows are AI-assisted procedures, not commands. They must produce a
plan and a dry-run summary before any write. Ask for explicit confirmation
before changing Package dependencies, public exposure, or existing declarations.

### Analyzer Plugin Bootstrap

`ccrouter analyzer status [host-root]` inspects one manually installed Host
bootstrap and reports its source, pinned identity, lockfile, and Analyzer
compatibility. `ccrouter analyzer doctor [host-root]` additionally runs locked
dependency resolution, analysis, and loader compilation in a temporary copy.
Run `status` before `doctor`; neither command runs generation or rewrites Host
configuration.

The planned `install/upgrade/uninstall` commands are not implemented. Follow
[`docs/CCRouter-analyzer-cli-plan.md`](../../docs/CCRouter-analyzer-cli-plan.md)
and the manual Host bootstrap procedure in
[`ide-analysis-server.md`](../ccrouter-integration-development/references/ide-analysis-server.md).
Do not attach Analyzer setup to `generate`, Pub Hook, or component scaffolding.
Do not change a pinned Git ref merely to follow local HEAD, use a branch name,
or commit a local absolute path.

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
5. Apply only after confirmation, then run generation, analysis, focused tests,
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
index. The optional `ccrouter_devtools` view consumes Runtime snapshots; future Catalog
integration may use stable IDs but is not a reason to
add a new public runtime API.

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

When the workflow changes a developer-visible command, path, lifecycle, error,
or API boundary, update the root README and the relevant integration Skill
reference in the same change.
