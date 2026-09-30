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

The plugin is not a generator, general dependency resolver, Runtime validator,
or authorization boundary. It must not call `build_runner`, inspect Widgets,
or infer Contract ownership from names or a partial editor buffer. It may read
only Pub-resolved Packages' exact generated metadata and the Contract sources
named there to diagnose a missing required Service/Command owner. Complete
cross-file rules and generated output fingerprints remain the responsibility of:

```bash
fvm dart run ccrouter_generator:ccrouter generate <host-root> --check
```

Single-file diagnostics also cover public/top-level/non-generic Handler shape,
obvious Handler arity/void returns, mutually exclusive Route/InitTask fields,
literal stable IDs and aliases, Gate IDs, positive literal Durations, and
Metadata-proven missing Service/Command owners. Quick Fixes either delete one
conflicting `pattern/patterns` or `contract/id` argument, or add one exact owner
constant to a missing/direct required dependency list. The latter requires an
existing public import whose export graph proves the constant's stable value;
variables, spreads, conditionals, ambiguous owners, hidden symbols, and import
insertion remain manual. Never expect the plugin to invent a Contract, ID,
alias, Gate, timeout, import, or owner identity.

If the plugin is unavailable or incompatible with the current Analysis Server,
disable it and continue using Dart Analyzer plus the CLI gate. Do not weaken
public API boundaries to accommodate plugin installation. Unreleased Git
bootstraps must pin a reviewed commit; after publication, use the bootstrap's
Hosted manifest and rerun the same loader `analyze/compile` smoke. See
[`docs/CCRouter-ide-analysis-server.md`](../../../docs/CCRouter-ide-analysis-server.md)
for dependency setup and the current Analyzer version isolation rationale.

For an already configured Host, prefer the implemented read-only checks:

```bash
fvm dart run --verbosity=error ccrouter_generator:ccrouter analyzer status <host-root>
fvm dart run --verbosity=error ccrouter_generator:ccrouter analyzer doctor <host-root>
```

The planned `install/upgrade/uninstall` commands in
[`docs/CCRouter-analyzer-cli-plan.md`](../../../docs/CCRouter-analyzer-cli-plan.md)
are not implemented. Keep using the manual Host bootstrap, do not attach setup
to generation or Pub Hook, and do not change a pinned ref merely to follow
repository HEAD.
