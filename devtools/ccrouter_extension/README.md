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

## Getting Started

The application must register `CCDevToolsServiceExtension` in its debug
composition root and provide the static catalog snapshot. The extension shows
Overview, Catalog, Components, and Call Graph views. Source locations are
displayed as copyable package URIs; the extension does not assume or launch a
local IDE. See [`docs/CCRouter-devtools.md`](../../docs/CCRouter-devtools.md)
for the integration and privacy boundaries.
