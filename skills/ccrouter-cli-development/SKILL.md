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
fvm dart run --verbosity=error ccrouter_generator:ccrouter create component <package-name> <parent-directory> [--with-example]
fvm dart run --verbosity=error ccrouter_generator:ccrouter create page <PageName> <component-directory>
fvm dart run --verbosity=error ccrouter_generator:ccrouter create service <ServiceName> <component-directory>
fvm dart run --verbosity=error ccrouter_generator:ccrouter create command <CommandName> <component-directory>
fvm dart run --verbosity=error ccrouter_generator:ccrouter create event <EventName> <component-directory> [--with-subscriber]
fvm dart run --verbosity=error ccrouter_generator:ccrouter create init-task <TaskName> <component-directory> [--with-contract]
fvm dart run --verbosity=error ccrouter_generator:ccrouter analyzer status [host-root]
fvm dart run --verbosity=error ccrouter_generator:ccrouter analyzer doctor [host-root]
fvm dart run --verbosity=error ccrouter_generator:ccrouter analyzer pin-check [host-root]
fvm dart run --verbosity=error ccrouter_generator:ccrouter analyzer install <host-root> --version <published-version> [--dry-run]
fvm dart run --verbosity=error ccrouter_generator:ccrouter analyzer install <host-root> --source git --url <remote-url> --ref <full-commit-sha> [--dry-run]
fvm dart run --verbosity=error ccrouter_generator:ccrouter analyzer upgrade <host-root> --version <published-version> [--dry-run]
fvm dart run --verbosity=error ccrouter_generator:ccrouter analyzer upgrade <host-root> --ref <full-commit-sha> [--dry-run]
fvm dart run --verbosity=error ccrouter_generator:ccrouter analyzer uninstall <host-root> [--dry-run]
fvm dart run --verbosity=error ccrouter_generator:ccrouter generate <project-root>
fvm dart run --verbosity=error ccrouter_generator:ccrouter generate <project-root> --check
fvm dart run --verbosity=error ccrouter_generator:ccrouter generate <project-root> --no-cache
fvm dart run --verbosity=error ccrouter_generator:ccrouter generate <project-root> --profile
fvm dart run --verbosity=error ccrouter_generator:ccrouter generate <host-root> --watch=auto --machine
fvm dart run --verbosity=error ccrouter_generator:ccrouter watch status <host-root>
fvm dart run --verbosity=error ccrouter_generator:ccrouter watch follow <host-root>
fvm dart run --verbosity=error ccrouter_generator:ccrouter find <capability-id-or-route-pattern> <host-root>
fvm dart run --verbosity=error ccrouter_generator:ccrouter find <capability-id-or-route-pattern> <host-root> --usage <consumer-component-id>
fvm dart run --verbosity=error ccrouter_generator:ccrouter clean <project-root>
fvm dart run --verbosity=error ccrouter_generator:ccrouter portable prepare <host-root>
fvm dart run --verbosity=error ccrouter_generator:ccrouter portable publish <host-root>
fvm dart run --verbosity=error ccrouter_generator:ccrouter aggregate <scan-root> [--output-dir <directory>] [--generate-component-registrars]
fvm dart run --verbosity=error ccrouter_generator:ccrouter pub-hook install [--sdk <flutter-sdk-root>]
fvm dart run --verbosity=error ccrouter_generator:ccrouter pub-hook status [--sdk <flutter-sdk-root>]
fvm dart run --verbosity=error ccrouter_generator:ccrouter pub-hook uninstall [--sdk <flutter-sdk-root>]
fvm dart run --verbosity=error ccrouter_generator:ccrouter pub-hook run --project-root <host-root> [--pub-command <command>]
fvm dart run --verbosity=error ccrouter_generator:ccrouter pub-hook guard-clean --project-root <project-root>
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
The selected Package is the `requestedRoot`; the Package or Workspace that owns
Pub state, build cache, and the generation lock is the `resolutionRoot`.
Workspace members must validate Pub's `workspace_ref.json` or exact Workspace
membership, while standalone nested Packages remain independent.
Resolve the requested project role before generation. An app-role Host owns
Builder publication across its writable dependency closure, cross-Package
validation, Host assembly, and Host catalogs. A Flutter component or Pure Dart
contracts Package owns only its requested Package Builder/API/Bundle/index and
package catalog; it must not publish a Host facade or reject an independent
Contract merely because no implementation is present locally. A
non-participating Workspace aggregator is skipped. `--output-dir` and watch are
Host-only until package-local watch has an explicit target/ownership model.
Read-only sibling Workspace members are local index inputs, not distributed
Packages requiring Portable State. External Hosted, Git, and out-of-Workspace
Path dependencies still require verified published artifacts. Shared metadata
cache writes merge Package entries under the generation lock so one
package-local invocation cannot evict another Host's local planning data.
Ordinary one-shot generation prints only its final elapsed time. Use `--profile`
only to investigate generation performance. Benchmarks and AI performance
diagnostics must pass it explicitly; never infer an AI caller from environment
or terminal heuristics. On a miss, distinguish
`build-targets` from the post-build `dirty-packages` reuse set and use the reported
reason (`cache-missing`, `metadata`, `output`, `dependency-index`, or
`propagated-from`) before changing cache behavior. Never remove caches just to
make an ordinary generation run pass.
After a successful Pub command, keep Pub success distinct from a failed CCRouter
phase. If Builder completed before Workspace validation failed, render its
summary plus structured root causes, corrections, requested Host/Package, and
resolution root; suppress routine Builder progress/skipped lines. `--profile`
retains raw validation errors. If Builder itself did not complete, retain the
full bounded output tail.
Use `--watch=auto --machine` for a long-lived local or AI development session.
Consume its schema `1` NDJSON stdout and keep stderr as diagnostic text. A
successful Builder event is not final until `aggregationSucceeded`; wait for
`ready` before relying on the initial result. Default events retain final build
and aggregation timings; add `--profile` explicitly when a benchmark or slow
run needs build_runner verbose durations and the complete cycle trace. Treat
the default `build` value as CCRouter's end-to-end observation; the narrower
upstream build_runner duration is profile-only. Set
`CCROUTER_DISABLE_BUILD_WATCH=1` for the one-shot fallback. Watch owns one build
root and holds its generation lock for the lease lifetime. Coordination locks,
Host registrations, Flutter-run leases, and minimal Host/Builder session authority live under the user-level
`CCROUTER_HOME` (`~/.ccrouter` on macOS/Linux or `%LOCALAPPDATA%\\CCRouter` on
Windows) in a full-SHA-256 build-root directory; `.dart_tool` retains
disposable build/planning data plus Host-facing status/diagnostic mirrors. An
active watch republishes deleted mirrors, while Pub Hook and `watch status`
can read exact stable sessions without treating planning or Builder caches as
global state. Use `watch status` to inspect the effective schema and path. V2 fails fast when a
live V1 owner is detected; stop the old process and reinstall the current Pub
Hook instead of mixing protocols. `CCROUTER_USE_LEGACY_DART_TOOL_LOCKS=1` is a
temporary A/B fallback; it also restores project-local Flutter-run leases and
does not make old and new processes interoperable.
Stop watch before the final `--no-cache --check`; watch never replaces that
authority.
Different Hosts resolving to that same build root share one Builder owner. The
owner watches the union of their active target closures, while every Host keeps
its own aggregation, validation, lease, status, diagnostics, and input revision.
`status.json.pid` identifies the Host watch and `builderOwnerPid` identifies the
shared owner. A subscriber takes over if the owner exits. A duplicate watch for
the same Host fails before it can compete for the status file. Set
`CCROUTER_DISABLE_MULTI_HOST_WATCH=1` only for the previous one-watch-per-root
A/B fallback. Hosts with distinct Pub build roots never share a Builder.
For a wrapper-started background watch, use read-only `watch status <host-root>`
for one snapshot or `watch follow <host-root>` for concise state changes. The
watch atomically publishes `.dart_tool/ccrouter/v1/watch/status.json`; complete
Hook diagnostics stay in `watch/flutter-run.log` and must not be copied into
Flutter Tool's machine stdout. Status publication is fail-open observability:
failure to update it never changes locking, Builder, validation, restoration,
atomic artifact publication, or the final reference gate. If an abrupt exit
leaves an `active` record, the read-only commands report it as `stale` once the
owner lock is released; they do not rewrite the historical status file.
Workspace validation failures also atomically publish a bounded
`watch/diagnostics.json` beside the status file. It is tied to Host/build root,
session, cycle, event revision, and exact resolution fingerprint; a success,
new cycle, or restarted session clears it. The optional Analyzer bridge accepts
only a fully matching, resolution-stable pair and folds capability fallout from
one missing Owner into one authored-source root cause. It polls file identities
at 500ms because Analysis Server does not reliably forward `.dart_tool` events,
and reanalyzes only after a change. Saved-versus-resolved Pub hints do not
require an active watch: they use validated requested/resolution roots plus
`.metadata` and `ccrouter.yaml` to distinguish Host, Flutter package-local, and
Pure Dart package-local commands. Set
`CCROUTER_DISABLE_ANALYZER_WATCH_BRIDGE=1` to disable this IDE-only bridge.
Publication and consumption remain fail-open; they do not replace the final
`--no-cache --check` gate.
For Hook-started `flutter run --machine`, the wrapper launches the original
Flutter Tool behind a narrow stdin-only reload gate. Watch publishes monotonic
`inputRevision`, `completedInputRevision`, and
`failedInputRevision` evidence; the gate forwards `app.restart` only
after the corresponding stable `aggregationSucceeded`. It returns a standard
daemon error with bounded Generator diagnostics on failure. A topology-changing
session restart publishes `hotRestartRequired`; reject Hot Reload until an
explicit Hot Restart receives a successful daemon response. This does not cover
interactive terminal `r` and does not parse Flutter daemon stdout except for
the matching Hot Restart response. Use
`CCROUTER_DISABLE_HOT_RELOAD_GATE=1` for an isolated fallback.
One-shot generate, check, and clean commands fail fast when that root already
has an active watch; wait for `aggregationSucceeded` during iteration, then
stop the watch before the final reference gate. Do not retry the blocked command
in a polling loop. Starting watch while a one-shot command owns or awaits the
root lock also fails fast; retry watch only after that command completes.
Watch detects exact Pub-resolution changes independently of build_runner's
source events. A covered version or dependency-edge change runs a
`resolutionStarted` aggregation cycle without claiming that Builder ran. A new
Host-closure Package, changed Builder target/filter set, or a child that exits
after resolution changes rotates `sessionId` under the same lock and lease.
Adding a subscriber may therefore expand and restart the shared child; removing
one retains the harmless target superset until the owner exits. Actual Pub target
removal still rotates the session. Each affected subscriber refreshes its own
closure and publishes its own new `ready` fence.
Stopping or rotating a build_runner child is bounded: allow 10 seconds after
SIGINT, 5 seconds after SIGTERM, then send SIGKILL and wait at most 5 more
seconds. Never leave session restart or generation-lock release waiting on an
unbounded child exit.
Wait for the new session's `ready`; its earlier `aggregationSucceeded` is not a
completion fence. Set `CCROUTER_DISABLE_WATCH_SESSION_RESTART=1` only to make
such changes fail closed and require a stopped-watch one-shot reference.
After Builder success, watch skips only the redundant ordinary fast-path and
Build Plan decision. It retains input barriers, preflight, snapshots,
validation, aggregation, and local state writes. Set
`CCROUTER_DISABLE_WATCH_CYCLE_OPTIMIZATION=1` to restore the reference cycle for
byte-for-byte A/B diagnosis without disabling watch.
Aggregation runs through the in-process generation kernel by default; machine
events report `aggregationSucceeded.cycleMode=inProcess`. Set
`CCROUTER_DISABLE_WATCH_IN_PROCESS_CYCLE=1` only for the subprocess reference
used in byte-for-byte or timing A/B checks. Neither switch weakens the final
`--no-cache --check` gate.
`input-delta` compares exact Package facts with the last successful local Build
Plan: `authored` is an own-source/config change, `resolutionOnly` means unchanged
own input with changed resolution identity. This is not a proven causal edge or
semantic dependency graph. `output-delta` counts actual Dart, metadata, Markdown
and portable-state additions/removals/modifications before `--check` restores.
Missing either authored digest means `authoredUnavailable`, not equal source.
No baseline means `unavailable`, not no change. A changed state file is not a
changed business API; unchanged Dart does not prove unchanged docs/locations.
Attribution never authorizes skipping Builder or rewriting Portable State.
Successful cycles reuse one exact-content planning snapshot for the local
fast-path manifest and Build Plan state. Use
`CCROUTER_DISABLE_SHARED_PLANNING_SNAPSHOT=1` only for byte-for-byte or timing
A/B against the separate-scan reference path; it does not disable input
barriers, validation, artifact restoration, atomic state writes, or the final
`--no-cache --check` authority.
Watch planning publication reuses the exact input snapshot already captured by
the final barrier. On an aggregation reuse hit it may additionally reuse only
the verified aggregation-owned entry bytes, while rereading current
Builder-owned outputs. The `planning-snapshot-capture` span reports
`attributes.evidenceMode`; set `CCROUTER_DISABLE_WATCH_EVIDENCE_REUSE=1` to
restore complete planning recapture for byte-for-byte and timing A/B.
The watch output-delta scan also supplies its exact current managed-output
bytes to planning publication after Builder, aggregation, and the final input
barrier succeed. This reports `input-and-current-output`. Set
`CCROUTER_DISABLE_WATCH_OUTPUT_EVIDENCE_REUSE=1` to restore only the separate
planning output scan while retaining input and aggregation evidence reuse.
The `aggregation-input-fingerprint` profile span reports a SHA-256 identity in
`attributes.fingerprint` for Builder metadata, resolved Package indexes, and
the Host aggregation graph. It is diagnostic-only: equality is not permission
to skip Builder, validation, aggregation, writes, or the final reference gate.
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
read-only dependencies, and unrelated build output. Package ownership stops at
a nested `pubspec.yaml`; an independently runnable example Host is never owned
by its parent component's clean, fingerprint, or Builder protection scope.
After cleaning, run a full `generate` before making code changes based on
generated imports.

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
Component output includes `.metadata` `project_type: package`. With
`--with-example`, run the current Flutter SDK's `create --template=app --empty
--no-pub` in a same-filesystem staging directory, add direct component/runtime/
generator dependencies, and retain the app `project_type`; the example is
therefore a Host by default. Publish the component directory only after all
steps succeed. A failure removes only that unique staging directory. In a
Workspace, list both the component and example as members; outside one, the
example uses `path: ..` for the component.
Component manifests inherit the nearest explicit Dart SDK constraint and
`ccrouter`/`ccrouter_generator` Hosted, Git, or rebased Path declarations. A
resolved Package version is used only when no explicit declaration exists; if
either source cannot be proven, creation fails before writing instead of using
a hard-coded framework version.
After success, follow the printed `Next steps`. They are deterministic guidance,
not proof of the intended Host, and they never authorize silent Workspace or
dependency edits.

### Pub Hook

`pub-hook install` is explicit and per-SDK. It wraps the Flutter SDK entrypoints
and the platform-supported Dart entrypoint, keeps reversible backups, and must
never be run against an SDK without first resolving its path. The wrappers run
the original `flutter pub` or `dart pub`
first; only a successful `get`, `upgrade`, `downgrade`, `add`, or `remove` may
trigger post-pub generation. Help and dry-run invocations (`--help`, `-h`,
`--dry-run`, or `-n`) never trigger it. `flutter run` and `flutter build` run the same
generator as a fail-closed preflight before the original Flutter entrypoint.
The wrappers locate the first real top-level command by consuming known global
option values, then accept only the first real Pub subcommand. Never scan all
tokens: option values, script arguments, and business arguments named `pub`,
`run`, `build`, or `get` are not commands. An unknown global option with
unproven arity skips the Hook and remains owned by the original CLI.
It resolves the current Package role from `.metadata`, `ccrouter.yaml`, and its
direct `ccrouter`/`ccrouter_contracts` dependency. An app-role Host runs Host
generation; other participating Packages run package-local generation. The
resolved Package config must contain the matching runtime/contracts Package and
`ccrouter_generator`. A Workspace aggregator is skipped rather than treated as
a Host or used to guess one of its members.

Successful run/build output is labeled `preflight`; successful Pub-triggered
output is labeled `post-pub generation`. Success prints only the generator fast
path, validation summary, and final elapsed time; Hook does not enable detailed
profiling by default. Failure preserves the recent
bounded generator tail so actionable Builder errors remain visible without
unbounded buffering or routine console noise.
When the same Host already has an active watch, post-pub generation waits for
an `aggregationSucceeded` event published after the latest Pub resolution
input instead of starting a conflicting one-shot command. A Builder,
validation, or aggregation failure remains fail-closed and its bounded watch
diagnostics are surfaced by the Hook. `sessionId`, `cycle`, and monotonic
`eventRevision` reject failures that predate the wait. If Pub resolution changes
during a cycle, a new terminal failure returns immediately with the available
diagnostics and requires another cycle/session; success still requires the exact
current resolution fingerprint. Set
`CCROUTER_DISABLE_PUB_HOOK_WATCH_FAILURE_FENCE=1` only for the legacy
fingerprint-only A/B fallback. Missing state, watch exit, or the bounded
five-minute wait also fails; never treat another Host's status as evidence.
When watch rotates its child after Pub topology changes, Hook accepts the new
session only after `sessionReady: true`/`ready` and an exact matching resolution
fingerprint. It must not reuse that session's pre-ready aggregation event.
Package-local post-pub generation never treats a Host target name as exact
completion evidence or performs Host validation. Before starting its one-shot
path, it may consume only a schema-valid build-root `builder-status.json` whose
canonical build root matches and whose owner lock is actually held. It then
fails early with the owner Host, requested Package, coverage, and stop/retry
guidance instead of falling through to a generic generation-lock error. Stale,
malformed, or wrong-root status is ignored. A covered Package may wait for the
Host `aggregationSucceeded`, but a Hook invocation that must itself succeed
still requires stopping the watch and retrying from that Package.

Use `status` after an FVM version switch; it prints the resolved SDK path and
verifies the marker, Flutter/Dart POSIX/Windows wrappers, and backups. It returns non-zero
when the hook is missing or inconsistent. Use `uninstall` before removing a
managed SDK. Set `CCROUTER_PUB_HOOK_DISABLE=1` for a one-shot bypass. Do not
patch Flutter's `shared.sh`, snapshots, or tool sources manually. On POSIX the
hook wraps `bin/cache/dart-sdk/bin/dart`, including IDE direct `dart pub`
invocations. On Windows it wraps `bin/dart.bat`; direct IDE execution of
`cache/dart-sdk/bin/dart.exe` remains unsupported and must be reported by
`status`. Flutter Tool's internal implicit `pub get` remains outside the hook.
The Flutter wrapper runs the internal `guard-clean` check before a real
top-level `flutter clean`. A live watch for the resolved build root blocks clean
without killing it; stop `flutter run/watch` and retry. Help, unknown global
options, and argument values named `clean` do not trigger the guard. Use
`CCROUTER_DISABLE_FLUTTER_CLEAN_GUARD=1` only for an explicit recovery or A/B
run; bypassing does not make a watch valid after Pub or build_runner state is
deleted.
If the guard is bypassed, watch confirms persistent loss of the build root's
package config, package graph, or established build_runner Asset Graph before
publishing `invalidatedByClean`, stopping the child within the normal bounded
shutdown, and releasing stable locks. Restore Pub state and start a new watch;
never wait for that invalidated session to recover. Cleaning only a Workspace
member's local `.dart_tool` does not invalidate an intact shared build root.
Upgrade a schema 4 installation by uninstalling it before reinstalling. After a
successful `flutter run` preflight it starts watch under a
lifecycle lease and removes the lease when Flutter exits; `flutter build`
remains one-shot. `run/build` preflight failures stop the Flutter command;
on Windows a terminal-inheriting Dart supervisor refreshes a versioned lease
heartbeat, removes it after normal/non-zero/handled-interrupt exits, and lets
watch expire the lease after an uncatchable supervisor termination. Use
`CCROUTER_DISABLE_WINDOWS_RUN_SUPERVISOR=1` only for old-path A/B comparison.
projects without a resolved CCRouter graph are skipped. Before the original
Flutter process starts, the run wrapper prints the successful watch start plus
its PID and status/log paths to stdout, consistently with successful preflight
messages; actual failures remain on stderr. Watch NDJSON stays redirected to
the log and is never mixed into Flutter Tool's machine stream.

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
`ccrouter analyzer pin-check [host-root]` is a manual maintainer/release check
for Git manifest/lock/resolved identity, exact remote SHA fetch, and production
changes after the pin. Pending production changes remain advisory for the
two-stage push-then-pin workflow. Run `status` before `doctor`; none of these
commands runs generation or rewrites Host configuration.

If doctor reports a stale or incomplete plugin-manager entry, stop the Analysis
Server from the IDE, use the reported PID/PPID/elapsed/command only as candidate
ownership evidence, confirm the process exited, and manually back up the entire
listed hash directory to the exact path outside `.plugin_manager`, not just its
`analyzer_plugin` child. Doctor never kills, moves, or deletes global state.
It reports source, cache, temporary loader smoke, restart, and live verification
separately. Then restart and verify a real IDE diagnostic; doctor alone does not
prove the live session loaded the plugin.

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
retain a recovery journal in the canonical Pub owner's project-isolated
`CCROUTER_HOME/coordination/v2` directory. The operation lock lives there too,
so `flutter clean` cannot unlink an active transaction or its recovery evidence.
`CCROUTER_USE_LEGACY_DART_TOOL_LOCKS=1` moves both back under the Pub owner's
`.dart_tool/ccrouter/analyzer` only for A/B; stable and legacy writers fail fast
when the other protocol still owns its lock.
Inspect its exact paths and recover deliberately; do not erase it to bypass the
next command's recovery check. Commit owned source files, ownership marker and
lockfiles, never the private journal. Installation success does not prove live IDE loading.
Do not attach Analyzer setup to `generate`, Pub Hook, or component scaffolding.
Do not change a pinned Git ref merely to follow local HEAD, use a branch name,
or commit a local absolute path.
Analyzer installation accepts only the shared Host role. An app `.metadata`
defaults to Host for a direct runtime Package; `host.enabled: true` may promote
another Flutter project type, while `host.enabled: false` demotes an app.
`lib/main.dart` is not Host evidence. The Plugin itself remains read-only and
uses the same role inputs only to select diagnostics and Pub guidance.

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
