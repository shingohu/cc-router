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
<host>/tools/ccrouter_analyzer_host/
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
    path: tools/ccrouter_analyzer_host
```

```yaml
# Host analysis_options.yaml
analyzer:
  plugins:
    - app_ccrouter_analyzer
```

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
      ref: a275d1d46ddfdded6678ecbf1d2d23818cdbdfdc
```

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

Expanded rationale is optional background:
[IDE integration design](https://github.com/shingohu/cc-router/blob/main/docs/CCRouter-ide-analysis-server.md).

## Status and verification

For an already configured Host, prefer the implemented read-only checks:

```bash
fvm dart run --verbosity=error ccrouter_generator:ccrouter analyzer status <host-root>
fvm dart run --verbosity=error ccrouter_generator:ccrouter analyzer doctor <host-root>
```

`status: healthy` proves only that the bootstrap manifest, lockfile, source, and
versions are statically consistent. `doctor` additionally proves dependency
resolution, bootstrap analysis, loader compilation, and checks for stale or
incomplete legacy cache entries belonging to the current bootstrap path.
If it names a cache, stop the Analysis Server and move the entire listed hash
directory outside `.plugin_manager` as a backup before restarting. Moving only
its `analyzer_plugin` child leaves an existing parent that Dart 3.11 reuses and
fails to load. Do not clear unrelated IDE or Pub caches or infer ownership from
a shared plugin name. This SDK-specific cache check does not prove live IDE
loading; verify a diagnostic and Quick Fix in the running IDE. Rerun doctor
after the bootstrap or pinned ref changed.

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
same healthy installation preserves files and lockfiles. A Flutter application
Host must directly depend on ccrouter/flutter and have an app `.metadata` or a
top-level main in `lib/main.dart`; aggregators and library components are refused.

The CLI creates `tools/ccrouter_analyzer_host/`, updates one Host dev_dependency
and `analyzer.plugins`, and preserves unrelated rules, comments and inherited
options. It records hashes in `.ccrouter-analyzer.json`; commit this marker, the
wrapper manifest, inner bootstrap manifest/lockfile/loader and Host configuration.
Candidate dependency resolution, analysis and loader compilation precede Host
writes. Host Pub uses the current Flutter SDK with Pub Hook disabled. Shared
Workspace writes are locked; no generated files or IDE caches are changed.

Ordinary failure restores recorded configuration and Pub resolution files, not
global caches. Concurrent user edits or interruption retain original bytes in
the Pub owner's `.dart_tool/ccrouter/analyzer/transactions/` and block subsequent
writes. Review those exact files for recovery; never remove caches to bypass this
check. Modified owned files and existing manual bootstraps are not overwritten or
adopted. Unknown files survive uninstall. For manual installations keep using the
procedure above. Never attach setup to generation/Pub Hook or follow repository
HEAD automatically. Restart Analysis Server after changes and verify a real
diagnostic; command success alone is not proof of IDE loading.
