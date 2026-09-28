# Analyzer bootstrap

The active `pubspec.yaml` uses a pinned Git commit so the Demo Analysis Server
plugin can be reproduced before `ccrouter_analyzer_plugin` is published. The
plugin loader is intentionally isolated from the main Workspace because its
Analyzer version is different from the generator's Analyzer version.

After publishing `ccrouter_analyzer_plugin`, replace `pubspec.yaml` with the
checked-in `pubspec.hosted.yaml` and run `dart pub get` in this directory. Keep
the Git manifest available for testing unreleased plugin changes, but do not
use both manifests in one bootstrap Package.

Smoke checks:

```bash
cd demo/tools/ccrouter_analyzer_plugin_host/tools/analyzer_plugin
dart pub get
dart analyze
dart compile exe bin/plugin.dart -o /tmp/ccrouter-analyzer-plugin
```

The compile step verifies that Analysis Server can load the plugin entrypoint;
it does not start a server or modify the application. If the plugin cannot be
resolved or starts with an incompatible Analysis Server, disable the bootstrap
and continue with Dart Analyzer plus `ccrouter generate --check`.
