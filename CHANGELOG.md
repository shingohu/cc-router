# Changelog

All notable changes to CCRouter will be documented in this file.

The project is still preparing its first public release. Package-specific
changelogs and migration notes must be finalized before any Package is
published.

## Unreleased

- Preserved Runtime-generation isolation for all four Route Service lookups
  while integrating main into Managed. Diagnostic Entry/lifecycle/visibility
  snapshots no longer expose close handles; capture them from the owning Page.
  The low-level identity bridge stays outside the business API.

- Align component example scaffolds with native Managed assembly and startup;
  include standalone Portable preparation and build prerequisites. Extend optional
  Analyzer feedback to conditional generated imports and literal route placement/
  policy errors; keep topology and generated-output validation authoritative.

- Separated logical Managed Pop from outgoing rendering: results complete first,
  while Route Services remain available through the exit transition. Renderer
  unmount preserves logical Entry identity, pending results and Scopes for remount;
  shutdown releases render waits without another frame. Exact close releases
  only its target's business resources, preserving covering foreign Popups.
- Bound navigation and pending custom-Adapter Pop/close waits to concrete Host
  registrations, including initial stacks and synchronous Guard replacement.
  Retired Pop is consumed without removal; lost close ownership returns
  `notFound`. Late receipts/errors cannot mutate a same-name replacement.
- Isolated shared readiness and Scope-owned factories/initializers from arbitrary
  first-caller Zone values. Independent cancellation releases only that waiter's
  relay, errors return in each caller's error Zone, and new-instance initialization
  retains caller cancellation lineage. Ended invocation origins cannot access a
  replacement Session's resources.
- Added explicit active-route revalidation with identity-based keep/close/replace/
  reset decisions, Host/Outlet fences and optional synchronous Backend commit
  receipts. Policies are Host-owned; business code uses the facade and reports.
- Consolidated current contracts and dated verification evidence under
  `docs/validation/README.md`; retained historical platform results and release
  blockers without treating source regressions as new device acceptance.

- Removed analytics identity and restoration-demand SPI/history from Core/Host
  and the demand-only DevTools section. Application bridges own visitor identity
  snapshots at observation delivery, Consent resets and bounded demand collection.
  Moved adaptive geometry/600–840 breakpoints/pane policy into the Demo; Host
  integration now calls `CCMultiHostNavigationAdapter.setActiveOutlets` with a
  resolved visible set, preserving retained Entry identity and Scope ownership.
  This is a pre-release Host/observation API migration; no old API aliases remain.

- Moved product analytics out of the framework into unpublished Demo libraries
  `demo_analytics` and `demo_analytics_flutter` under `demo/modules/`. Renamed
  their types to `AppAnalytics…` / `AppNavigationAnalyticsBridge`, migrated
  tests and benchmarks, and removed analytics dependencies from `ccrouter_test`.
  No old package/type compatibility exports remain. CCRouter continues to expose
  navigation lifecycle observations and diagnostics; product tracking is
  application-owned.

- Removed `ccrouter_go_router`, its GoRouter dependency, and compatibility Demo
  launchers. Composition Roots migrate to `CCManagedRouterApp` or
  `CCManagedRouterBackend` with `CCRouterApp.managed`; business Intents and
  navigator calls remain unchanged. Attaching to an existing GoRouter is no
  longer supported; progressive adoption uses an embedded Managed Outlet.
- Migrated foreign/opaque UI diagnostic reporting to the Host-only Managed
  `foreignRouteBridge`. Runtime bounded history replaces the removed GoRouter
  Adapter history API. Predictive Back remains backend-neutral and opt-in.
- Preserved covering foreign Popups when closing the last Managed Entry,
  retained direct Flutter `Navigator.pop(result)` results, and rejected foreign
  Routes that copy a Managed Page's key or settings.
- Connected Managed Navigator/Outlet changes to page lifecycle delivery and
  added Host-only Shell branch initialization checks so returning to an existing
  branch preserves its stack and Widget State.
- Added immutable Runtime-resolved `CCNavigationRequest.pathParameters` for
  custom Host Adapters. Its defensive copy makes the Host/Adapter SPI
  constructor non-`const`.
- Added Runtime-bound route-entry handles and optional exact close for covered
  managed pages, preserving other results, Scopes, and foreign Popups. Native
  Managed supports declarative Entries and retained Shell branches; custom
  Adapters opt in without changing ordinary Pop.

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
- Added native Managed Host integration, lifecycle, interception, diagnostics,
  navigation observation hooks, read-only DevTools, Analyzer diagnostics, and release tooling.
- Added multi-platform Demo coverage and explicit release-readiness gates.
- Made Hook-started `flutter run` wait for the exact leased generation watch to
  publish a live ready session before launching Flutter.
