# CCRouter DevTools Extension

This package is the official read-only Dart DevTools Extension for CCRouter.
It consumes `ext.ccrouter.snapshot` through VM Service and decodes the
versioned `ccrouter_devtools_protocol` envelope. It never exposes navigation,
Runtime, Scope, Widget, or Adapter mutation controls.

## Development

Use a stable Flutter SDK with Web support:

```bash
flutter build web --release
dart run devtools_extensions validate --package=.
dart run devtools_extensions build_and_copy --source=. --dest=extension/devtools
```

The repository's OHOS Flutter SDK is suitable for the framework and Demo
tests, but not for compiling the Web-only `devtools_extensions` dependency.
Use the system FVM stable SDK for this package's Web build.
Dependency resolution must use that same SDK. A root package config resolved by
the OHOS SDK still points at OHOS Flutter even when the build command uses stable;
use an isolated Extension/Protocol copy for Web verification when keeping the
OHOS workspace resolution intact.

## Getting Started

The application must register `CCDevToolsServiceExtension` in its debug
composition root and provide the static catalog snapshot. The extension shows
Overview, Catalog, Components, Call Graph, and Diagnostics views with manual
Refresh. Diagnostics includes Failure/Fallback/Pending/InitTask state, bounded
history omissions and Sink delivery health. Missing optional protocol v1 fields
are shown as unavailable rather than zero. Source locations are
displayed as copyable package URIs; the extension does not assume or launch a
local IDE. See [`docs/CCRouter-devtools.md`](../../docs/CCRouter-devtools.md)
for the integration and privacy boundaries.
