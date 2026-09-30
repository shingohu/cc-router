# ccrouter_analyzer_plugin

Optional Analysis Server diagnostics for CCRouter source boundaries and
deterministic generated outputs. The plugin provides low-noise editing feedback
but does not run generation, resolve cross-package ownership, or replace
`ccrouter generate --check`.

The plugin uses an isolated Analysis Server bootstrap because its Analyzer
version must not constrain the application Workspace. Follow the
[IDE integration guide](https://github.com/shingohu/cc-router/blob/main/docs/CCRouter-ide-analysis-server.md)
instead of
adding an arbitrary local path dependency.

The package is currently pre-release. Hosted installation and upgrade flows are
tracked in the
[release checklist](https://github.com/shingohu/cc-router/blob/main/docs/CCRouter-release-readiness.md).
