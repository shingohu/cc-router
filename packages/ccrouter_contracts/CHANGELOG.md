# Changelog

## 0.1.0 - Unreleased

- Add optional Host/Outlet failure and pending attribution plus fixed Sink
  reason/attempt/recovery-depth fields; arbitrary cancellation codes stay private.

- Added immutable RouteEntry handles/close outcomes and active-route revalidation
  contexts, policies and reports without exposing Scope or Flutter objects.
- Added optional Host/Adapter protocols for exact close, synchronous navigation
  commit receipts, parent-stack plans, route-exit rendering, scoped Guard targets,
  outlet visibility and backend-neutral predictive-back contracts. These SPI
  remain outside business integration APIs; custom Backends opt in explicitly.
- Removed product analytics identity and restoration-demand contracts from the
  framework boundary; application integrations own those concerns.
- Added the opt-in Pure Dart UI Contract/Dependency/Renderer declarations and
  `CCComponent.uiDependencies` through the separate `ccrouter_ui_contracts.dart`
  entry point; the five navigation/capability Contract kinds remain unchanged.
- Preparing the first public release of Pure Dart CCRouter contracts.
