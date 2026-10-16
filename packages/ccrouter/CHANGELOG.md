# Changelog

## 0.1.0 - Unreleased

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
