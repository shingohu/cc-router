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

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
