# Changelog

All notable changes to CCRouter will be documented in this file.

The project is still preparing its first public release. Package-specific
changelogs and migration notes must be finalized before any Package is
published.

## Unreleased

- Added Runtime-bound route-entry handles and optional exact close for covered
  managed pages, preserving other results, Scopes, and foreign Popups. GoRouter
  rejects unsupported declarative/structural/onExit cases without Pop fallback;
  existing Adapter implementations and ordinary Pop remain compatible.

- Moved default Runtime initialization, shutdown, and InitTask Gate control to
  Host-only `CCRouterHost` APIs. Business `CCRouter` retains Session operations
  and read-only InitTask diagnostics, without lifecycle compatibility aliases.
- Added opt-in typed UI Fragments with Pure Dart contracts, generated consumer
  Clients, static Host assembly, and Flutter-owned State. UI enums must be plain;
  DTO defaults enter shape fingerprints and unsupported constructors fail early.
- Added the optional Android predictive-back Route/Adapter bridge. Flutter owns
  animation and Pop; cancellation preserves results and Scopes, while local
  gates, navigation, Theme changes, and Adapter disposal invalidate old previews.
  A new start recovers a sequence whose terminal callback was lost.
- Cleaned up watch resources on initial snapshot/session setup failure and on
  shutdown before `ready`; terminal startup failures remain inactive `failed`.
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
