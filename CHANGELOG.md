# Changelog

All notable changes to CCRouter will be documented in this file.

The project is still preparing its first public release. Package-specific
changelogs and migration notes must be finalized before any Package is
published.

## Unreleased

- Separated generated Route consumer APIs from owner bindings. Stable Contract
  barrels now export only the typed Route `id` and `intent()` surface, while
  generated owner glue uses `XxxRouteContractBinding.definition` and keeps
  Arguments and Codec types out of business barrels.
- Built the typed Route, Service, Command, Event, and InitTask contract and
  generation pipeline.
- Added GoRouter Host integration, lifecycle, interception, diagnostics,
  analytics, read-only DevTools, Analyzer diagnostics, and release tooling.
- Added multi-platform Demo coverage and explicit release-readiness gates.
- Made Hook-started `flutter run` wait for the exact leased generation watch to
  publish a live ready session before launching Flutter.
