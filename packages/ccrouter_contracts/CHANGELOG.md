# Changelog

## 0.1.0 - Unreleased

- Recheck bounded Contract/Owner identities and required SHA-256 fingerprints at the shared Host/Runtime compatibility gate. Classify malformed consumer metadata as stale, preserving fingerprintChanged for valid shape drift.

- Attribute invalid installed versions to their Owner without falsely blaming valid consumer ranges. Continue validating consumer syntax independently and compare only parsed installed versions.

- Compare prerelease decimal identifiers without int parsing; keep signs/radix-like
  labels distinct and preserve equality/hash semantics. Avoid caret/tilde successor
  overflow without changing ordinary comparator boundaries.

- Clarify effective-value argument conflicts, explicit null/empty defaults and absent nullable declaration constants; non-null task Contract references remain top-level const.

- Document one annotation per declaration and role for generated Providers, Routes, page bindings, Handlers, Subscriptions and Contributions.

- Document unique Route Contract and InitTask Handler annotations; generation rejects repeated identities and scheduling policies.

- Fix asymmetric `CCServiceKey<T>` equality: require the exact generic type and name. Document single-annotation Service/Command Contracts.

- Add optional Event Contract alias with legacy default-name compatibility,
  generated Client collision checks and reserved-name diagnostics.

- Reject surrounding whitespace in Contract SemVer values while preserving range-expression whitespace. Document generated Client Object-member restrictions.

- BREAKING: align UI Contract parameters with Service/Command (`alias`, version
  defaulting to `0.1.0`, and `description`). UI Dependency accepts only optional
  `alias`; remove legacy `versionRange` and regenerate to record exact versions.

- Clarify initial Backend snapshot/read-time event ordering, Entry sequence
  lower bounds versus live continuity, and independent operation deduplication.
  Document cancellable Route exit subscription reentry during shutdown/detach.

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
