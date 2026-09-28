# IDE / Analysis Server

Use the optional `ccrouter_analyzer_plugin` only for developer feedback:

- `ccrouter_cross_package_generated_import` catches a handwritten import of
  another Package's `src/ccrouter_generated` library.
- `ccrouter_generated_output_missing` warns when an annotated `@CCRoute` page
  has not produced its expected Route library.

The plugin is not a generator, dependency resolver, Runtime validator, or
authorization boundary. It must not call `build_runner`, inspect Widgets, or
infer Contract ownership from a partial editor buffer. Cross-file rules and
generated output fingerprints remain the responsibility of:

```bash
fvm dart run ccrouter_generator:ccrouter generate <host-root> --check
```

If the plugin is unavailable or incompatible with the current Analysis Server,
disable it and continue using Dart Analyzer plus the CLI gate. Do not weaken
public API boundaries to accommodate plugin installation. See
[`docs/CCRouter-ide-analysis-server.md`](../../../docs/CCRouter-ide-analysis-server.md)
for dependency setup and the current Analyzer version isolation rationale.
