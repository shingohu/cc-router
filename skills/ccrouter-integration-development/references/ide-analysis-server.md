# IDE / Analysis Server

Use the optional `ccrouter_analyzer_plugin` only for developer feedback:

- `ccrouter_cross_package_generated_import` catches a handwritten import of
  another Package's `src/ccrouter_generated` library.
- `ccrouter_generated_output_missing` warns when a Route/Binding,
  Route/Service Contract, Service, Command Handler, Event Subscription, or
  InitTask source has not produced its deterministic source-preserving output.

The plugin maps generated source-preserving library add/modify/remove events
back to the authored capability source. This clears a stale missing-output
warning after a successful `ccrouter generate` and restores it after
`ccrouter clean`; restarting the Analysis Server should not be required for
this normal workflow. Metadata-only Contracts and component-wide aggregate APIs
remain CLI checks because a partial editor buffer cannot prove their Package
Catalog.

The watcher must preserve original changed paths before the Analyzer reduces
them to Dart import dependencies. The exact `ccrouter_package.json` metadata
path is also an invalidation input: changing an Owner in a watched Workspace
Package refreshes its consumers, even when they do not import generated code.
This does not promise automatic watching of arbitrary dependencies outside the
Server's active roots. Do not silence a stale diagnostic by importing internal
generated files; verify the installed plugin version and keep `generate --check`.

Package and Workspace identity follow the same authored evidence as generation.
The analyzed Package is the `requestedRoot`; only its own Pub root or a Workspace
proven by `workspace_ref.json`/exact membership is the `resolutionRoot`. A
standalone Package nested below another Workspace never borrows that ancestor's
Package graph. Changes to `pubspec.yaml`, `.metadata`, `ccrouter.yaml`, and the
Workspace reference invalidate the relevant Plugin caches.

An active Generator watch additionally publishes bounded structured Workspace
diagnostics to `.dart_tool/ccrouter/v1/watch/diagnostics.json`. The plugin never
parses CLI/log text. It accepts a snapshot only when Host/build root, session,
cycle, event revision, and resolution fingerprint match current `status.json`,
the cycle resolution stayed matched, and the watch is active. One missing Host
Owner is shown at an exact authored `package:` location with capability fallout
folded under that root cause. A successful/new cycle or session clears the old
diagnostic. Without an active watch, terminal Host generation writes
`.dart_tool/ccrouter/v1/generation/diagnostics.json`; the Plugin consumes it only
while its exact Pub-resolution fingerprint remains current. Active watch state
always wins and cannot revive older one-shot errors. Independently of watch
availability, the current `pubspec.yaml` editor overlay versus resolved graph
drift produces only `ccrouter_pub_resolution_stale`; ownership is not inferred
until Pub get. The hint identifies Host versus package-local from `.metadata`
and `ccrouter.yaml`, selects Flutter Pub for Flutter Packages or Dart Pub for
Pure Dart Packages, and clears immediately when the overlay is restored. An
analyzed Workspace root indexes its explicit member manifests and publishes or
clears the hint independently for each participating member; it does not
recursively scan the repository.
Malformed YAML, a non-boolean `host.enabled`, and Host enablement without a
direct `ccrouter` dependency publish
`ccrouter_project_configuration_invalid` on `ccrouter.yaml`. Correcting or
removing the invalid declaration clears the diagnostic without running the
Generator.

Analysis Server does not reliably emit plugin filesystem events for
`.dart_tool`. The plugin therefore compares watch and one-shot snapshots every
500ms, caches Package role/context parses until authored identities change, and
checks Package-graph/config identity once per shared Pub resolution root. It
reads/reanalyzes only after a relevant identity change. The Timer is owned by the plugin
and is cancelled on context replacement, shutdown, and channel close. Set
`CCROUTER_DISABLE_ANALYZER_WATCH_BRIDGE=1` before starting Analysis Server to
disable the whole Generator diagnostics bridge without disabling source rules.
For maintainer scale A/B only,
`CCROUTER_ENABLE_ANALYZER_TIERED_POLL=1` retains immediate file-event and
validated-generation refresh while distributing the exact-path fallback across
ten 500ms shards. It is off by default and allows a five-second worst-case
missed-event refresh.
The same-file component alias graph optimization is separate and enabled by
default; `CCROUTER_DISABLE_ANALYZER_COMPONENT_ALIAS_GRAPH=1` restores the
repeated declaration scan only for differential diagnosis. Both switches are
read from the long-lived Analysis Server Plugin process. Changing them in a
terminal after the Server has started does nothing until the Server is fully
restarted, and an IDE may not inherit a shell-only environment at all.
Snapshot publication and consumption are fail-open diagnostics; generation,
Pub Hook failure, and the final `--no-cache --check` gate remain authoritative.

Framework maintainers can run `test/analysis_server_integration_test.dart`
from the isolated plugin Package. It starts actual SDK Server processes for
Legacy/LSP diagnostics, overlays, fixes, and disk events. It uses local plugin
sources and a temporary cache, so passing it does not prove that a consuming
IDE has loaded the same revision. No application setup step is added by this
test harness.

Diagnostics read the Analysis Server overlay after every content update, so an
unsaved edit such as removing a required component owner must be reported before
generation. Initial analysis visits only authored Dart sources and skips
platform/build assets plus CCRouter generated libraries. Do not use `dart
analyze` to test this behavior: the Dart CLI does not run legacy Analysis Server
Plugins. Use an IDE or a real Language Server session, then keep the CLI
generation check as the cross-file authority.

The plugin is not a generator, general dependency resolver, Runtime validator,
or authorization boundary. It must not call `build_runner`, inspect Widgets,
or infer Contract ownership from names or a partial editor buffer. It may read
only Pub-resolved Packages' exact generated metadata and the Contract sources
named there to build the owner index. It may additionally reuse the existing
Analysis Server session for current Handler/Component/Service type and constant
resolution. It does not open a parallel workspace resolver or retain resolved
ASTs. Unknown/invalid semantic results fall back conservatively; source changes
during resolution invalidate the pending diagnostic/fix. Complete
cross-file rules and generated output fingerprints remain the responsibility of:

```bash
fvm dart run ccrouter_generator:ccrouter generate <host-root> --check
```

Single-file diagnostics also cover public/top-level/non-generic Handler shape,
obvious Handler arity/void returns, mutually exclusive Route/InitTask fields,
literal stable IDs and aliases, Gate IDs, positive literal Durations, and
Metadata-proven missing Service/Command owners. Quick Fixes either delete one
conflicting `pattern/patterns` or `contract/id` argument, or add one exact owner
constant to a missing/direct required dependency list. If every missing Owner
of the same Component is provable, a second fix can add all of them in stable
order. These fixes require an existing public import whose export graph proves
each constant's stable value;
variables, spreads, conditionals, ambiguous owners, hidden symbols, and import
insertion remain manual. Never expect the plugin to invent a Contract, ID,
alias, Gate, timeout, import, or owner identity.

Resolved checks distinguish real `dart:async` Future types and typedefs from
same-named application types, and compare component constants by declaration
identity/value rather than their final identifier. Handler acceptance follows
the Generator, including its existing `Future<void>?` support. An unresolved
dependency value is not proof that the required Owner is missing.

Annotation rules and their Quick Fixes verify the canonical CCRouter declaration
library, including aliases exposed by a resolved public barrel. Application
annotations with the same spelling do not trigger CCRouter diagnostics. An
unrelated Dart error does not erase a proven identity. Without resolution, only
an exact visible framework import with no local/ambiguous shadow is accepted;
otherwise the rule waits for resolution or the generation gate.

For concrete annotated Services, `ccrouter_service_disposable_missing` warns
when a compatible instance `dispose()` is not connected to Scope's actual
`CCDisposable`. Its Quick Fix adds only the unambiguously imported interface;
it preserves the method body and cannot prove that cleanup itself is complete.
`ccrouter_service_owned_resource` warns for direct fresh disposable allocations
into private final fields in declarations/constructors. It has no cleanup fix.
Do not generate empty disposers or dispose borrowed/shared resources to silence
a warning. Factory/helper allocations, Contributions and complex ownership
remain lifecycle-test/review responsibilities, not a claimed static guarantee.

If the plugin is unavailable or incompatible with the current Analysis Server,
disable it and continue using Dart Analyzer plus the CLI gate. Do not weaken
public API boundaries to accommodate plugin installation. Unreleased Git
bootstraps must pin a reviewed commit; after publication, use the bootstrap's
Hosted dependency and rerun the same loader `analyze/compile` smoke. Follow the
bundled bootstrap procedure below; it does not require framework repository files.

## Field-formal annotation navigation limitation

On the verified Android Studio 2026.1.4, Dart Plugin 509.0.0, and OHOS Flutter
Dart 3.11.5 toolchain, ordinary Go to Declaration (`Cmd+B` on macOS) does not
navigate from `@CCQueryParam()` or `@CCExtraParam()` when the annotation is on a
field-formal parameter such as `this.id`. The Dart Analysis Server's whole-file
`analysis.navigation` notification omits metadata visited through
`FieldFormalParameter`, although an explicit `analysis.getNavigation` request
and LSP `textDocument/definition` both resolve the correct declaration. This is
an upstream SDK/IDE navigation limitation, not evidence that CCRouter analysis,
generation, or runtime parameter handling failed.

Use Go to Type Declaration (`Cmd+Shift+B` on macOS) as the non-invasive
workaround. A real IDE jump was verified for `CCQueryParam`, and LSP definition
requests resolve both annotation types. Do not rewrite constructors, clear
IDE/global Pub caches, weaken generator validation, or disable the CCRouter
Analyzer Plugin for this symptom. Dart Plugin 509.0.0
gates ordinary LSP definition navigation on both Experimental LSP Features and
a project Dart SDK of at least `3.14.0-65.0.dev`. Flutter and OHOS projects must
upgrade the complete SDK distribution rather than substituting a standalone
Dart SDK. After an upgrade, verify the whole-file navigation notification and a
real IDE `Cmd+B`; a newer version number alone does not prove the upstream
visitor omission is fixed.

## Manual Host bootstrap

Keep the rule Package's Analyzer dependencies out of the application workspace.
For the current development version, create a Host-owned wrapper Package:

```text
<host>/tool/ccrouter_analyzer_host/
  pubspec.yaml
  tools/analyzer_plugin/
    pubspec.yaml
    pubspec.lock
    bin/plugin.dart
```

The outer `pubspec.yaml` contains no Analyzer dependency and no workspace
resolution setting:

```yaml
name: app_ccrouter_analyzer
publish_to: none
environment:
  sdk: ^3.10.0
```

Add it to the application's actual dependency-owning pubspec, rebasing the path
if that owner is above the Host. Merge the plugin entry into the Host's existing
`analysis_options.yaml`; preserve other rules and plugins:

```yaml
# Host pubspec.yaml
dev_dependencies:
  app_ccrouter_analyzer:
    path: tool/ccrouter_analyzer_host
```

```yaml
# Host analysis_options.yaml
analyzer:
  exclude:
    - tool/ccrouter_analyzer_host/tools/analyzer_plugin/**
  plugins:
    - app_ccrouter_analyzer
```

The inner loader is deliberately outside the Host dependency graph. Exclude its
source from ordinary Host `dart analyze` / `flutter analyze`; otherwise those
commands may resolve `bin/plugin.dart` with the application Package config and
report missing `analyzer_plugin` imports even though the isolated loader is
healthy. `analyzer doctor` analyzes and compiles the loader against its own
locked graph. Adjust the exclude path only when a manually maintained bootstrap
uses a different directory name.

The inner `tools/analyzer_plugin/pubspec.yaml` owns an isolated dependency graph.
This pinned example matches the reviewed 2026-10-03 plugin; compare it with the
application's SDK and installed CCRouter version before adoption. Use a Git URL
the consuming environment can authenticate to. Never use a relative path to the
rule Package: Analysis Server copies the bootstrap into its own directory.

```yaml
name: app_ccrouter_analyzer_loader
publish_to: none
environment:
  sdk: ^3.10.0
dependencies:
  analyzer: 8.4.0
  analyzer_plugin: 0.13.10
  ccrouter_analyzer_plugin:
    git:
      url: git@github.com:shingohu/cc-router.git
      path: packages/ccrouter_analyzer_plugin
      ref: <reviewed-full-commit-sha>
```

For the maintained Demo, read the active bootstrap manifest and lockfile instead
of copying its current ref into guidance. Their `ref` and `resolved-ref` are the
source of truth and must match.

Use this inner `bin/plugin.dart`. The implementation import is intentional only
in this isolated tool entrypoint, never in feature/application code:

```dart
import 'dart:isolate';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:analyzer_plugin/starter.dart';
import 'package:ccrouter_analyzer_plugin/src/plugin.dart';

void main(List<String> args, SendPort sendPort) {
  ServerPluginStarter(
    CCRouterAnalyzerPlugin(PhysicalResourceProvider.INSTANCE),
  ).start(sendPort);
}
```

Resolve the Host dependencies, then run `fvm dart pub get` from the inner loader
directory and commit its lockfile. Resolve an aggregator with
`CCROUTER_PUB_HOOK_DISABLE=1` when its installed Hook cannot classify workspace
roots correctly; run generation against the actual Host separately. Run the
read-only checks below and restart Analysis Server after a bootstrap/ref change.
Do not claim live IDE diagnostics work from loader compilation alone.

After an actual Hosted release, replace only the inner rule dependency with its
reviewed Hosted version and revalidate the isolated graph. Do not infer that
`0.1.0` is published from its source manifest. If the current SDK is incompatible,
disable the plugin entry without weakening Dart analysis or generation gates.

For maintained Git bootstraps, a Plugin production change that affects
diagnostics, fixes, watch/metadata invalidation, path identity, Server lifecycle,
loader protocol, or SDK compatibility requires a corresponding pin update.
Perform it in two stages: commit, verify, and push the Plugin first; then update
the Host manifest and lockfile to that remotely resolvable full SHA in a separate
commit. A commit cannot point its own dependency at itself. Pure tests, comments,
and behavior-preserving refactors do not require a pin bump. Never use a branch,
floating tag, or unpushed SHA. After the pin changes, run `analyzer doctor`,
restart Analysis Server, and verify a real IDE diagnostic or Quick Fix before
claiming the Host uses the new revision. Keep the isolated `analyzer` and
`analyzer_plugin` versions unchanged unless SDK compatibility independently
requires their upgrade.

Expanded rationale is optional background:
[IDE integration design](https://github.com/shingohu/cc-router/blob/main/docs/CCRouter-ide-analysis-server.md).

## Status and verification

For an already configured Host, prefer the implemented read-only checks:

```bash
fvm dart run --verbosity=error ccrouter_generator:ccrouter analyzer status <host-root>
fvm dart run --verbosity=error ccrouter_generator:ccrouter analyzer doctor <host-root>
fvm dart run --verbosity=error ccrouter_generator:ccrouter analyzer pin-check <host-root>
```

`status: healthy` proves only that the bootstrap manifest, lockfile, source, and
versions are statically consistent. `doctor` additionally proves dependency
resolution, bootstrap analysis, and loader compilation in a temporary copy. It
reports source pin, legacy cache artifact (`absent`, `current`, or `stale`),
restart, and live-verification state separately. A passed loader smoke is not a
live IDE result.

`pin-check` is a manual maintainer/release command for a Git bootstrap. It
verifies the full manifest/lock/resolved SHA, fetches that exact remote commit
in a temporary bare repository, and reports production changes under the
Plugin `lib` after the pin. Pending changes are advisory so the first Plugin
commit can be verified and pushed before a separate pin bump; do not wire this
state into every Plugin PR as a hard gate.

If doctor names a cache, use its PID/PPID/elapsed/command list only as ownership
candidates. Save work, stop Analysis Server from the IDE, confirm the relevant
process has exited, then manually move the entire listed hash directory to the
exact backup path outside `.plugin_manager`. Doctor never kills a process or
moves/deletes global state. Moving only the `analyzer_plugin` child leaves an
existing parent that Dart 3.11 reuses and fails to load. Do not clear unrelated
IDE or Pub caches or infer ownership from a shared plugin name. Restart, rerun
doctor, and verify a real diagnostic or Quick Fix; the CLI cannot observe or
control the running IDE session.

For a new Host, explicit installation is available:

```bash
ccrouter analyzer install <host-root> --version <published-version> --dry-run
ccrouter analyzer install <host-root> --source git --url <remote-url> --ref <full-commit-sha>
ccrouter analyzer upgrade <host-root> --ref <full-commit-sha>
ccrouter analyzer uninstall <host-root> --dry-run
```

All three write commands support `--dry-run` without processes or file writes.
Hosted requires an explicit published version; Git accepts remote HTTPS/SSH URLs
and full SHA only (`--git-path` defaults to `packages/ccrouter_analyzer_plugin`).
Upgrade keeps the source kind and requires an explicit version/ref. Repeating the
same healthy installation preserves files and lockfiles. The selected Package
must resolve to the shared Host role: `project_type: app` with direct
`ccrouter`/Flutter dependencies, or a direct runtime Package with explicit
`ccrouter.yaml` `host.enabled: true`. `host.enabled: false`, aggregators, and
package-local components are refused; `lib/main.dart` is not Host evidence.

The CLI creates `tool/ccrouter_analyzer_host/`, updates one Host dev_dependency,
`analyzer.plugins`, and the exact inner-loader `analyzer.exclude`. It records
whether that exclude was newly added in `.ccrouter-analyzer.json`; uninstall
removes only a CLI-owned entry and preserves a pre-existing identical entry,
other excludes, rules, comments and inherited options. `status` and `doctor`
report a missing loader exclude as incomplete. Commit the marker, wrapper
manifest, inner bootstrap manifest/lockfile/loader and Host configuration.
CLI-owned installations created by older versions under
`tools/ccrouter_analyzer_host/` remain manageable in place; install, upgrade,
and uninstall do not silently relocate user directories. A source-controlled
manual migration must move the complete wrapper and update both the Host path
dependency and exact loader exclude in the same change.
Candidate dependency resolution, analysis and loader compilation precede Host
writes. Host Pub uses the current Flutter SDK with Pub Hook disabled. Shared
Workspace writes are locked; no generated files or IDE caches are changed.

Ordinary failure restores recorded configuration and Pub resolution files, not
global caches. Concurrent user edits or interruption retain original bytes in
the canonical Pub owner's project-isolated
`CCROUTER_HOME/coordination/v2/.../analyzer/transactions/` and block subsequent
writes. Review those exact files for recovery; never remove caches to bypass this
check. Modified owned files and existing manual bootstraps are not overwritten or
adopted. Unknown files survive uninstall. For manual installations keep using the
procedure above. Never attach setup to generation/Pub Hook or follow repository
HEAD automatically. Restart Analysis Server after changes and verify a real
diagnostic; command success alone is not proof of IDE loading.
