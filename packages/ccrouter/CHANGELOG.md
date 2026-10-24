# Changelog

## 0.1.0 - Unreleased

- Expose lightweight read-only diagnostic health, history omissions and Runtime
  revision; navigation failures retain attempted Host/Outlet and safe reason,
  attempt and recovery depth. Normal cancellation no longer emits error alarms.

- Added `CCRouter.navigatorOf(context)` for reusable Host/Outlet-bound navigation
  without retaining Context. Existing calls remain unchanged; stale Host/Runtime
  generations fail explicitly and declared destination placement stays authoritative.
- Added Managed-only `CCManagedRouterApp`, explicit `CCRouterApp.managed`,
  MultiHost/Shell/Outlet composition, context-scoped navigation and parent-stack
  reconstruction. Removed GoRouter Host integration; progressive adoption embeds
  a Managed Outlet while business Intents remain unchanged.
- Added exact RouteEntry handles/close and active-route revalidation. Ordinary
  Pop retains outgoing Route Services through rendering; renderer unmount keeps
  logical entries for remount and shutdown does not wait for another frame.
- Preserved exact Guard/Pop ownership across focus changes, repeated Host
  registration and overlapping returns; foreign popup Back and LocalHistory
  remain separate from underlying Managed exit. Flutter owns gesture animation.
- Kept product analytics, adaptive layout policy and restoration-demand collection
  application-owned. Current contracts and dated verification scopes are indexed
  in the repository's `docs/validation/README.md`.
- Moved Runtime lifecycle and InitTask Gate control to `CCRouterHost` in
  `ccrouter_host.dart`; removed business-facade entry points and kept Session
  operations and read-only InitTask diagnostics available to business code.
- Select default Page/Dialog route families from the application ancestor,
  preserving MaterialApp platform adaptation and explicit route overrides.
- Added optional Host-only predictive-back Route hooks with commit-time local
  gate checks, Theme-change cancellation, and retired-handler recovery, including
  a new gesture after a lost terminal callback. Flutter owns animation and Pop.
- Added Host lifecycle binding for optional typed UI assembly; shutdown
  invalidates old callbacks and reinitialization requires an explicit UI remount.
- Preparing the first public release of the Flutter CCRouter facade.
