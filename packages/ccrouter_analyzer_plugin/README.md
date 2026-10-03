# ccrouter_analyzer_plugin

Optional Analysis Server diagnostics for CCRouter source boundaries and
deterministic generated outputs. The plugin provides low-noise editing feedback
and Metadata-proven Service/Command owner checks, but does not run generation
or replace `ccrouter generate --check`. Its dependency Quick Fix is offered
only for a directly editable list with an exact owner constant already exposed
by a public import; it never guesses or inserts imports.

Annotation diagnostics, generated-output warnings and argument Quick Fixes share
declaration identity checks. Same-name application annotations are ignored.
Resolved identities remain usable when another expression has a Dart error;
unresolved ambiguous imports defer to later resolution or generation.

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
They cover editor overlays, Quick Fix/codeAction application, disk changes to
all five generated capability kinds, and cross-package Workspace ownership
metadata. Fixture disk changes test invalidation, not actual generation.
No Pub or network access is needed after resolving this package's dependencies.
Bootstrap copying, AOT packaging, Git pins, and IDE UI require separate checks.
